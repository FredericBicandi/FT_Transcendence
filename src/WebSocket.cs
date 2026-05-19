using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text;

public sealed class Ws
{
    private static readonly TimeSpan HeartbeatTimeout = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan PendingJoinTimeout = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan HeartbeatCheckInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan IdleTimeout = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan TimeSyncInterval = TimeSpan.FromSeconds(5);
    private const double MinAimAngleDegrees = 0.0;
    private const double MaxAimAngleDegrees = 360.0;
    private const int MaxMessageBytes = 16 * 1024;
    private const int MaxWeaponTypeLength = 64;
    private const int MaxShotIdLength = 128;
    private const int MaxPlayerIdLength = 128;
    private const int MaxPlayerNameLength = 64;
    private const int MinPlayerLevel = 0;
    private const int MaxPlayerLevel = 1000;
    private const double DefaultPlayerHealth = 100.0;
    private const double DefaultSpawnX = 0.0;
    private const double DefaultSpawnY = 0.0;
    private const double MaxHitDamage = DefaultPlayerHealth;
    private const double MinRocketLauncherDamage = 1.0;
    private const double MaxRocketLauncherDamage = 80.0;
    private const string RocketLauncherWeaponType = "Rocket Launcher";

    private static readonly IReadOnlyDictionary<string, double> ServerWeaponDamage =
        new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);

    private readonly ConcurrentDictionary<string, ClientConnection> clients;
    private int onlinePlayerCount;

    // Active match rooms keyed by room id. Rooms are removed when empty or ended.
    private readonly ConcurrentDictionary<string, GameRoom> rooms = new();

    public Ws(ConcurrentDictionary<string, ClientConnection> clients)
    {
        this.clients = clients;
        _ = RunRoomTimersAsync();
    }

    public int OnlinePlayerCount => Volatile.Read(ref onlinePlayerCount);

    // Handles one upgraded /ws connection from connect to cleanup.
    public async Task RunWebSocketApp(HttpContext context)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("Expected WebSocket request");
            return;
        }

        var socket = await context.WebSockets.AcceptWebSocketAsync();
        var connectionId = Helper.GetConnectionId();
        var client = Helper.AcceptPlayer(connectionId, socket);
        Interlocked.Increment(ref onlinePlayerCount);

        Console.WriteLine($"Socket connected: {connectionId}");

        using var connectionLifetime = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
        var heartbeatTask = MonitorHeartbeatAsync(client, connectionLifetime.Token);

        try
        {
            while (socket.State == WebSocketState.Open)
            {
                var message = await ReceiveTextMessageAsync(socket, connectionLifetime.Token);

                if (message is null)
                    break;

                await HandleMessageAsync(client, message);
            }
        }
        catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
        {
            Console.WriteLine($"Client disconnected unexpectedly: {client.LogId}");
        }
        finally
        {
            // Remove the disconnected socket from global and room-level state.
            connectionLifetime.Cancel();
            if (client.HasPlayerId)
                Helper.RemovePlayer(clients, client.PlayerId);
            var disconnectedRoom = RemovePlayerFromRoom(client);

            try
            {
                await heartbeatTask;
            }
            catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
            {
            }

            try
            {
                if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
                {
                    await socket.CloseAsync(
                        WebSocketCloseStatus.NormalClosure,
                        "Closing",
                        CancellationToken.None
                    );
                }
            }
            catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
            {
                Console.WriteLine($"Close skipped for {client.LogId}: {ex.Message}");
            }

            socket.Dispose();
            Interlocked.Decrement(ref onlinePlayerCount);
            Console.WriteLine($"Client disconnected: {client.LogId}");

            if (disconnectedRoom is not null && client.HasJoinedGame)
            {
                var leaderboard = disconnectedRoom.LeaderboardSnapshot();

                // Only players in the same room should see this player leave.
                await BroadcastToRoomAsync(disconnectedRoom, new
                {
                    type = "player_left",
                    playerId = client.PlayerId,
                    leaderboard
                });

                await BroadcastToRoomAsync(disconnectedRoom, new
                {
                    type = "leaderboard_update",
                    roomId = disconnectedRoom.RoomId,
                    leaderboard
                });
            }
        }
    }

    private GameRoom AssignRoom(string playerId)
    {
        // First reserve a slot in any non-ended room that still has capacity.
        foreach (var room in rooms.Values)
        {
            if (room.TryReservePlayer(playerId))
                return room;
        }

        // No available room exists, so create a fresh room. Its timer starts on first join.
        while (true)
        {
            var room = GameRoom.Create();

            if (!room.TryReservePlayer(playerId))
                continue;

            if (rooms.TryAdd(room.RoomId, room))
                return room;
        }
    }

    private GameRoom? RemovePlayerFromRoom(ClientConnection client)
    {
        if (!rooms.TryGetValue(client.RoomId, out var room))
            return null;

        var hadJoined = client.HasJoinedGame;
        room.RemovePlayer(client.PlayerId);

        // Empty rooms are no longer useful and should not receive timer ticks.
        if (room.IsEmpty)
        {
            rooms.TryRemove(room.RoomId, out _);
            return null;
        }

        return hadJoined ? room : null;
    }

    private async Task RunRoomTimersAsync()
    {
        using var timer = new PeriodicTimer(TimeSyncInterval);

        // Authoritative server timer: send sync messages every few seconds.
        while (await timer.WaitForNextTickAsync())
        {
            // Snapshot avoids problems if rooms are added/removed during the loop.
            foreach (var room in rooms.Values.ToArray())
            {
                try
                {
                    if (room.State != GameRoomState.Running)
                        continue;

                    var remainingSeconds = room.RemainingSeconds;

                    if (remainingSeconds <= 0)
                    {
                        // Time is up: end the match once and clean up its sockets.
                        await EndRoomAsync(room);
                        continue;
                    }

                    await BroadcastToRoomAsync(room, new
                    {
                        type = "time_sync",
                        roomId = room.RoomId,
                        remainingSeconds,
                        leaderboard = room.LeaderboardSnapshot()
                    });
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Room timer failed for {room.RoomId}: {ex.Message}");
                }
            }
        }
    }

    private async Task EndRoomAsync(GameRoom room)
    {
        // MarkEnded returns false if another timer pass already ended this room.
        if (!room.MarkEnded())
            return;

        Console.WriteLine($"Room ended by time limit: {room.RoomId}");

        await BroadcastToRoomAsync(room, new
        {
            type = "match_ended",
            roomId = room.RoomId,
            reason = "time_limit",
            leaderboard = room.LeaderboardSnapshot()
        });

        foreach (var playerId in room.PlayerIdsSnapshot())
        {
            if (!clients.TryGetValue(playerId, out var client))
                continue;

            try
            {
                // Simpler cleanup policy: close sockets and let normal disconnect cleanup run.
                if (client.Socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
                {
                    await client.Socket.CloseAsync(
                        WebSocketCloseStatus.NormalClosure,
                        "Match ended",
                        CancellationToken.None
                    );
                }
            }
            catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
            {
                Console.WriteLine($"Match-end close skipped for {playerId}: {ex.Message}");
            }
        }

        rooms.TryRemove(room.RoomId, out _);
    }

    // Closes stale sockets when the client stops sending gameplay messages.
    private async Task MonitorHeartbeatAsync(ClientConnection client, CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(HeartbeatCheckInterval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            if (client.Socket.State != WebSocketState.Open)
                return;

            if (client.IsIdle)
            {
                var idleDuration = DateTimeOffset.UtcNow - client.IdleSinceUtc;

                if (idleDuration < IdleTimeout)
                    continue;

                Console.WriteLine($"Idle timeout for {client.PlayerId}: idle for {idleDuration.TotalSeconds:F0}s");

                await client.Socket.CloseAsync(
                    WebSocketCloseStatus.PolicyViolation,
                    "Idle timeout",
                    CancellationToken.None
                );

                return;
            }

            var inactiveDuration = DateTimeOffset.UtcNow - client.LastActivityUtc;
            var timeout = client.HasJoinedGame ? HeartbeatTimeout : PendingJoinTimeout;

            if (inactiveDuration < timeout)
                continue;

            Console.WriteLine($"Heartbeat timeout for {client.PlayerId}: idle for {inactiveDuration.TotalSeconds:F0}s");

            await client.Socket.CloseAsync(
                WebSocketCloseStatus.PolicyViolation,
                "Heartbeat timeout",
                CancellationToken.None
            );

            return;
        }
    }

    // Sends one JSON message while serializing writes per socket.
    public async Task SendJsonAsync(ClientConnection client, object payload)
    {
        if (client.Socket.State != WebSocketState.Open)
            return;

        var json = JsonSerializer.Serialize(payload);
        var bytes = Encoding.UTF8.GetBytes(json);

        await client.SendLock.WaitAsync();

        try
        {
            if (client.Socket.State == WebSocketState.Open)
            {
                await client.Socket.SendAsync(
                    new ArraySegment<byte>(bytes),
                    WebSocketMessageType.Text,
                    true,
                    CancellationToken.None
                );
            }
        }
        catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
        {
            Console.WriteLine($"Send failed for {client.PlayerId}: {ex.Message}");
        }
        finally
        {
            client.SendLock.Release();
        }
    }

    // Reassembles fragmented WebSocket text messages.
    public async Task<string?> ReceiveTextMessageAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[1024 * 4];
        using var stream = new MemoryStream();

        while (true)
        {
            WebSocketReceiveResult result;

            try
            {
                result = await socket.ReceiveAsync(
                    new ArraySegment<byte>(buffer),
                    cancellationToken
                );
            }
            catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
            {
                return null;
            }

            if (result.MessageType == WebSocketMessageType.Close)
                return null;

            if (result.MessageType != WebSocketMessageType.Text)
                continue;

            if (stream.Length + result.Count > MaxMessageBytes)
                return null;

            stream.Write(buffer, 0, result.Count);

            if (result.EndOfMessage)
                return Encoding.UTF8.GetString(stream.ToArray());
        }
    }

    // Treat normal network close paths as disconnects, not server errors.
    public bool IsExpectedWebSocketDisconnect(Exception ex) =>
        ex is WebSocketException or OperationCanceledException or IOException or
            InvalidOperationException or ObjectDisposedException;

    // Applies the current client message protocol.
    public async Task HandleMessageAsync(ClientConnection client, string message)
    {
        JsonDocument document;

        try
        {
            document = JsonDocument.Parse(message);
        }
        catch (JsonException)
        {
            Console.WriteLine($"Invalid JSON from {client.LogId}: {message}");
            return;
        }

        using (document)
        {
            var root = document.RootElement;

            if (!root.TryGetProperty("type", out var typeElement) ||
                typeElement.ValueKind != JsonValueKind.String)
            {
                Console.WriteLine($"Message missing type from {client.LogId}: {message}");
                return;
            }

            var type = typeElement.GetString();
            if (type == "on_connect")
            {
                if (!TryReadConnect(root, message, client.LogId, out var playerId, out var playerName, out var level))
                    return;

                if (client.HasPlayerId && client.PlayerId != playerId)
                {
                    Console.WriteLine($"Rejected player id change from {client.PlayerId} to {playerId}");
                    return;
                }

                if (!client.HasPlayerId)
                {
                    if (!clients.TryAdd(playerId, client))
                    {
                        Console.WriteLine($"Rejected duplicate player id on_connect: {playerId}");
                        await SendJsonAsync(client, new
                        {
                            type = "connect_rejected",
                            reason = "duplicate_player_id",
                            playerId
                        });
                        return;
                    }

                    client.Identify(playerId, playerName, level);
                }
                else
                {
                    client.UpdateProfile(playerName, level);
                }

                var room = client.HasRoom ? rooms.GetValueOrDefault(client.RoomId) : null;
                if (room is null || room.State == GameRoomState.Ended)
                    room = AssignRoom(playerId);

                client.AssignRoom(room.RoomId);
                Console.WriteLine($"On connect from {client.PlayerId}: name={client.PlayerName}, level={client.Level}, reservedRoom={room.RoomId}");

                await SendJsonAsync(client, new
                {
                    type = "room_reserved",
                    playerId = client.PlayerId,
                    playerName = client.PlayerName,
                    level = client.Level,
                    roomId = room.RoomId,
                    durationSeconds = room.DurationSeconds,
                    remainingSeconds = room.RemainingSeconds,
                    leaderboard = room.LeaderboardSnapshot()
                });

                return;
            }

            if (type == "on_join")
            {
                if (!client.HasPlayerId || !client.HasRoom)
                {
                    Console.WriteLine($"Join before on_connect from {client.LogId}: {message}");
                    return;
                }

                if (!TryReadPlayerState(root, message, client.PlayerId, "on_join", out var x, out var y, out var angle, out var weapon))
                    return;

                if (!rooms.TryGetValue(client.RoomId, out var room))
                    return;

                if (room.State == GameRoomState.Ended)
                {
                    room.RemovePlayer(client.PlayerId);
                    room = AssignRoom(client.PlayerId);
                    client.AssignRoom(room.RoomId);
                }

                var health = client.MarkJoined(x, y, angle, weapon);
                room.MarkPlayerJoined(client.PlayerId, client.PlayerName, client.Level);
                Console.WriteLine($"On join from {client.PlayerId}: name={client.PlayerName}, level={client.Level}, x={x}, y={y}, angle={angle}, weapon={weapon}, health={health}");

                await SendJsonAsync(client, new
                {
                    type = "room_joined",
                    playerId = client.PlayerId,
                    playerName = client.PlayerName,
                    level = client.Level,
                    roomId = room.RoomId,
                    durationSeconds = room.DurationSeconds,
                    remainingSeconds = room.RemainingSeconds,
                    leaderboard = room.LeaderboardSnapshot()
                });

                await SendExistingPlayersAsync(client);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_connected",
                    playerId = client.PlayerId,
                    playerName = client.PlayerName,
                    level = client.Level,
                    x,
                    y,
                    angle,
                    weaponType = weapon,
                    health,
                    isDead = false
                });

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "leaderboard_update",
                    roomId = client.RoomId,
                    leaderboard = room.LeaderboardSnapshot()
                });

                return;
            }

            if (type == "move")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadMove(root, message, client.PlayerId, out var x, out var y, out var angle))
                    return;

                client.MarkMovement(x, y, angle);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_move",
                    playerId = client.PlayerId,
                    x,
                    y,
                    angle
                });

                return;
            }

            if (type == "heartbeat")
            {
                client.MarkHeartbeat();
                if (!client.HasJoinedGame)
                    return;

                var snapshot = client.GetAuthoritativeHealthSnapshot();

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_heartbeat",
                    playerId = client.PlayerId,
                    health = snapshot.Health,
                    isDead = snapshot.IsDead
                });

                return;
            }

            if (type == "angle")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadAngle(root, message, client.PlayerId, out var angle))
                    return;

                client.MarkAngle(angle);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_angle",
                    playerId = client.PlayerId,
                    angle
                });

                return;
            }

            if (type == "hit")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadHit(root, message, client.PlayerId, out var hit))
                    return;

                await ResolveHitAsync(client, hit);

                return;
            }

            if (type == "health_update")
            {
                Console.WriteLine($"Rejected client-authoritative health update from {client.PlayerId}: {message}");

                return;
            }

            if (type == "respawn")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadOptionalRespawnPosition(root, message, client.PlayerId, out var spawnX, out var spawnY))
                    return;

                var result = client.Respawn(spawnX, spawnY);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_health",
                    playerId = client.PlayerId,
                    health = result.Health,
                    x = result.X,
                    y = result.Y,
                    damage = 0,
                    sourcePlayerId = client.PlayerId,
                    weaponType = "respawn",
                    isDead = result.IsDead
                });

                return;
            }

            if (type == "idle")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadIdle(root, message, client.PlayerId, out var x, out var y, out var angle))
                    return;

                client.MarkIdle(x, y, angle);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_idle",
                    playerId = client.PlayerId,
                    x,
                    y,
                    angle
                });

                return;
            }

            if (type == "idle_heartbeat")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadIdle(root, message, client.PlayerId, out var x, out var y, out var angle))
                    return;

                client.MarkIdle(x, y, angle);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_idle",
                    playerId = client.PlayerId,
                    x,
                    y,
                    angle
                });

                return;
            }

            if (type == "weapon_switch")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadWeapon(root, message, client.PlayerId, "weapon_switch", out var weapon))
                    return;

                client.MarkWeaponSwitch(weapon);
                Console.WriteLine($"Weapon switch from {client.PlayerId}: weapon={weapon}");

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_weapon_switch",
                    playerId = client.PlayerId,
                    weaponType = weapon
                });

                return;
            }

            if (type == "shoot")
            {
                if (!RequireJoined(client, type, message))
                    return;

                if (!TryReadShoot(root, message, client.PlayerId, out var shoot))
                    return;

                if (!client.TryGetStateSnapshot(out var state))
                {
                    Console.WriteLine($"Shoot before on_join from {client.PlayerId}: {message}");
                    return;
                }

                if (state.IsDead)
                {
                    Console.WriteLine($"Rejected shoot from dead player {client.PlayerId}: {message}");
                    return;
                }

                var bulletSpawn = new Dictionary<string, object>
                {
                    ["type"] = "bullet_spawn",
                    ["playerId"] = client.PlayerId,
                    ["weaponType"] = shoot.WeaponType ?? state.Weapon,
                    ["angle"] = shoot.Angle,
                    ["x"] = shoot.X ?? state.X,
                    ["y"] = shoot.Y ?? state.Y
                };

                if (shoot.StartX is not null)
                    bulletSpawn["startX"] = shoot.StartX.Value;

                if (shoot.StartY is not null)
                    bulletSpawn["startY"] = shoot.StartY.Value;

                if (shoot.TargetX is not null)
                    bulletSpawn["targetX"] = shoot.TargetX.Value;

                if (shoot.TargetY is not null)
                    bulletSpawn["targetY"] = shoot.TargetY.Value;

                await BroadcastToRoomAsync(client.RoomId, bulletSpawn);

                return;
            }

            Console.WriteLine($"Unknown message type from {client.PlayerId}: {type}");
        }
    }

    private async Task SendExistingPlayersAsync(ClientConnection client)
    {
        if (!rooms.TryGetValue(client.RoomId, out var room))
            return;

        foreach (var playerId in room.PlayerIdsSnapshot())
        {
            if (playerId == client.PlayerId ||
                !clients.TryGetValue(playerId, out var roomClient) ||
                roomClient.RoomId != room.RoomId)
            {
                continue;
            }

            if (!roomClient.TryGetStateSnapshot(out var state))
                continue;

            await SendJsonAsync(client, new
            {
                type = "player_connected",
                playerId = roomClient.PlayerId,
                playerName = roomClient.PlayerName,
                level = roomClient.Level,
                x = state.X,
                y = state.Y,
                angle = state.Angle,
                weaponType = state.Weapon,
                health = state.Health,
                isDead = state.IsDead
            });
        }
    }

    private static bool RequireJoined(ClientConnection client, string messageType, string message)
    {
        if (client.HasJoinedGame)
            return true;

        Console.WriteLine($"{messageType} before on_join from {client.LogId}: {message}");
        return false;
    }

    private async Task ResolveHitAsync(ClientConnection shooter, HitRequest hit)
    {
        if (!rooms.TryGetValue(shooter.RoomId, out var room))
            return;

        if (!clients.TryGetValue(shooter.PlayerId, out var currentShooter) ||
            currentShooter.RoomId != shooter.RoomId)
        {
            return;
        }

        if (!clients.TryGetValue(hit.TargetPlayerId, out var target) ||
            target.RoomId != shooter.RoomId)
        {
            Console.WriteLine($"Rejected hit from {shooter.PlayerId}: target {hit.TargetPlayerId} is not in the same room");
            return;
        }

        if (hit.TargetPlayerId == shooter.PlayerId)
        {
            Console.WriteLine($"Rejected self-hit from {shooter.PlayerId}");
            return;
        }

        if (!currentShooter.IsAlive || !target.IsAlive)
        {
            Console.WriteLine($"Rejected hit from {shooter.PlayerId}: shooter or target is dead");
            return;
        }

        if (hit.ShotId is not null &&
            !currentShooter.TryMarkShotHit(hit.ShotId, hit.TargetPlayerId))
        {
            Console.WriteLine($"Rejected duplicate shot {hit.ShotId} against {hit.TargetPlayerId} from {shooter.PlayerId}");
            return;
        }

        var damage = ResolveDamage(hit.WeaponType, hit.Damage);
        var result = target.ApplyDamage(damage);
        var shouldUpdateLeaderboard = result.Damage > 0;

        if (shouldUpdateLeaderboard)
            room.RecordHit(shooter.PlayerId, target.PlayerId, result.Damage, result.IsDead);

        await BroadcastToRoomAsync(shooter.RoomId, new
        {
            type = "player_health",
            playerId = target.PlayerId,
            health = result.Health,
            damage = result.Damage,
            sourcePlayerId = shooter.PlayerId,
            weaponType = hit.WeaponType,
            isDead = result.IsDead
        });

        if (shouldUpdateLeaderboard)
        {
            await BroadcastToRoomAsync(room, new
            {
                type = "leaderboard_update",
                roomId = room.RoomId,
                leaderboard = room.LeaderboardSnapshot()
            });
        }
    }

    private static double ResolveDamage(string weaponType, double requestedDamage)
    {
        if (IsRocketLauncher(weaponType))
            return Math.Clamp(requestedDamage, MinRocketLauncherDamage, MaxRocketLauncherDamage);

        if (ServerWeaponDamage.TryGetValue(weaponType, out var configuredDamage))
            return configuredDamage;

        return Math.Clamp(requestedDamage, 0, MaxHitDamage);
    }

    private static bool IsRocketLauncher(string weaponType) =>
        string.Equals(weaponType, RocketLauncherWeaponType, StringComparison.OrdinalIgnoreCase);

    private static bool TryReadOptionalRespawnPosition(
        JsonElement root,
        string message,
        string playerId,
        out double spawnX,
        out double spawnY)
    {
        spawnX = DefaultSpawnX;
        spawnY = DefaultSpawnY;

        var hasX = root.TryGetProperty("x", out _);
        var hasY = root.TryGetProperty("y", out _);

        if (!hasX && !hasY)
            return true;

        if (!hasX || !hasY ||
            !Helper.TryGetNumber(root, "x", out spawnX) ||
            !Helper.TryGetNumber(root, "y", out spawnY) ||
            !double.IsFinite(spawnX) ||
            !double.IsFinite(spawnY))
        {
            Console.WriteLine($"Invalid respawn position from {playerId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadCoordinates(
        JsonElement root,
        string message,
        string playerId,
        string messageType,
        out double x,
        out double y)
    {
        x = default;
        y = default;

        if (!Helper.TryGetNumber(root, "x", out x) ||
            !Helper.TryGetNumber(root, "y", out y) ||
            !double.IsFinite(x) ||
            !double.IsFinite(y))
        {
            Console.WriteLine($"Invalid {messageType} from {playerId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadMove(
        JsonElement root,
        string message,
        string playerId,
        out double x,
        out double y,
        out double angle)
    {
        angle = default;

        if (!TryReadCoordinates(root, message, playerId, "move", out x, out y))
            return false;

        if (!Helper.TryGetNumber(root, "angle", out angle) ||
            !double.IsFinite(angle) ||
            angle < MinAimAngleDegrees ||
            angle >= MaxAimAngleDegrees)
        {
            Console.WriteLine($"Invalid move angle from {playerId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadPlayerState(
        JsonElement root,
        string message,
        string playerId,
        string messageType,
        out double x,
        out double y,
        out double angle,
        out string weapon)
    {
        angle = default;
        weapon = string.Empty;

        if (!TryReadCoordinates(root, message, playerId, messageType, out x, out y))
            return false;

        if (!Helper.TryGetNumber(root, "angle", out angle) ||
            !double.IsFinite(angle) ||
            angle < MinAimAngleDegrees ||
            angle >= MaxAimAngleDegrees)
        {
            Console.WriteLine($"Invalid {messageType} angle from {playerId}: {message}");
            return false;
        }

        if (!TryReadWeapon(root, message, playerId, messageType, out weapon))
            return false;

        return true;
    }

    private static bool TryReadConnect(
        JsonElement root,
        string message,
        string logId,
        out string playerId,
        out string playerName,
        out int level)
    {
        level = default;

        if (!Helper.TryGetString(root, "playerId", out playerId) &&
            !Helper.TryGetString(root, "id", out playerId))
        {
            Console.WriteLine($"Invalid on_connect player id from {logId}: {message}");
            playerName = string.Empty;
            return false;
        }

        if (playerId.Length > MaxPlayerIdLength)
        {
            Console.WriteLine($"Player id too long in on_connect from {logId}: {message}");
            playerName = string.Empty;
            return false;
        }

        if (!Helper.TryGetString(root, "playerName", out playerName) &&
            !Helper.TryGetString(root, "name", out playerName))
        {
            Console.WriteLine($"Invalid on_connect player name from {logId}: {message}");
            return false;
        }

        if (playerName.Length > MaxPlayerNameLength)
        {
            Console.WriteLine($"Player name too long in on_connect from {logId}: {message}");
            return false;
        }

        if (!TryReadInt(root, "level", out level) ||
            level < MinPlayerLevel ||
            level > MaxPlayerLevel)
        {
            Console.WriteLine($"Invalid on_connect level from {logId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadInt(JsonElement root, string propertyName, out int value)
    {
        value = default;

        if (!root.TryGetProperty(propertyName, out var element) ||
            element.ValueKind != JsonValueKind.Number)
        {
            return false;
        }

        return element.TryGetInt32(out value);
    }

    private static bool TryReadHit(
        JsonElement root,
        string message,
        string playerId,
        out HitRequest hit)
    {
        hit = default;

        if (!Helper.TryGetString(root, "targetPlayerId", out var targetPlayerId))
        {
            Console.WriteLine($"Invalid hit target from {playerId}: {message}");
            return false;
        }

        if (!TryReadWeapon(root, message, playerId, "hit", out var weapon))
            return false;

        if (!Helper.TryGetNumber(root, "damage", out var damage) ||
            !double.IsFinite(damage))
        {
            Console.WriteLine($"Invalid hit damage from {playerId}: {message}");
            return false;
        }

        if (!IsRocketLauncher(weapon) &&
            (damage < 0 || damage > MaxHitDamage))
        {
            Console.WriteLine($"Invalid hit damage from {playerId}: {message}");
            return false;
        }

        string? shotId = null;
        if (root.TryGetProperty("shotId", out var shotIdElement))
        {
            if (shotIdElement.ValueKind != JsonValueKind.String)
            {
                Console.WriteLine($"Invalid hit shotId from {playerId}: {message}");
                return false;
            }

            shotId = shotIdElement.GetString()?.Trim();
            if (string.IsNullOrWhiteSpace(shotId) || shotId.Length > MaxShotIdLength)
            {
                Console.WriteLine($"Invalid hit shotId from {playerId}: {message}");
                return false;
            }
        }

        if (root.TryGetProperty("x", out _) &&
            (!Helper.TryGetNumber(root, "x", out var x) || !double.IsFinite(x)))
        {
            Console.WriteLine($"Invalid hit x from {playerId}: {message}");
            return false;
        }

        if (root.TryGetProperty("y", out _) &&
            (!Helper.TryGetNumber(root, "y", out var y) || !double.IsFinite(y)))
        {
            Console.WriteLine($"Invalid hit y from {playerId}: {message}");
            return false;
        }

        if (root.TryGetProperty("angle", out _) &&
            (!Helper.TryGetNumber(root, "angle", out var angle) ||
             !double.IsFinite(angle) ||
             angle < MinAimAngleDegrees ||
             angle >= MaxAimAngleDegrees))
        {
            Console.WriteLine($"Invalid hit angle from {playerId}: {message}");
            return false;
        }

        if (root.TryGetProperty("timestamp", out var timestampElement) &&
            timestampElement.ValueKind is not JsonValueKind.Number and not JsonValueKind.String)
        {
            Console.WriteLine($"Invalid hit timestamp from {playerId}: {message}");
            return false;
        }

        hit = new HitRequest(targetPlayerId, weapon, damage, shotId);
        return true;
    }

    private static bool TryReadWeapon(
        JsonElement root,
        string message,
        string playerId,
        string messageType,
        out string weapon)
    {
        if (!Helper.TryGetString(root, "weaponType", out weapon) &&
            !Helper.TryGetString(root, "weapon", out weapon))
        {
            Console.WriteLine($"Invalid {messageType} weapon from {playerId}: {message}");
            return false;
        }

        if (weapon.Length > MaxWeaponTypeLength)
        {
            Console.WriteLine($"Weapon type too long in {messageType} from {playerId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadShoot(
        JsonElement root,
        string message,
        string playerId,
        out ShootRequest shoot)
    {
        shoot = default;

        double angle;
        if (!Helper.TryGetNumber(root, "angle", out angle) ||
            !double.IsFinite(angle))
        {
            Console.WriteLine($"Invalid shoot angle from {playerId}: {message}");
            return false;
        }

        string? weaponType = null;
        if (root.TryGetProperty("weaponType", out _) || root.TryGetProperty("weapon", out _))
        {
            if (!TryReadWeapon(root, message, playerId, "shoot", out var weapon))
                return false;

            weaponType = weapon;
        }

        if (!TryReadOptionalNumber(root, "x", message, playerId, "shoot", out var x) ||
            !TryReadOptionalNumber(root, "y", message, playerId, "shoot", out var y) ||
            !TryReadOptionalNumber(root, "startX", message, playerId, "shoot", out var startX) ||
            !TryReadOptionalNumber(root, "startY", message, playerId, "shoot", out var startY) ||
            !TryReadOptionalNumber(root, "targetX", message, playerId, "shoot", out var targetX) ||
            !TryReadOptionalNumber(root, "targetY", message, playerId, "shoot", out var targetY))
        {
            return false;
        }

        shoot = new ShootRequest(weaponType, angle, x, y, startX, startY, targetX, targetY);
        return true;
    }

    private static bool TryReadOptionalNumber(
        JsonElement root,
        string propertyName,
        string message,
        string playerId,
        string messageType,
        out double? value)
    {
        value = null;

        if (!root.TryGetProperty(propertyName, out _))
            return true;

        if (!Helper.TryGetNumber(root, propertyName, out var parsed) ||
            !double.IsFinite(parsed))
        {
            Console.WriteLine($"Invalid {messageType} {propertyName} from {playerId}: {message}");
            return false;
        }

        value = parsed;
        return true;
    }

    private static bool TryReadAngle(
        JsonElement root,
        string message,
        string playerId,
        out double angle)
    {
        if (!Helper.TryGetNumber(root, "angle", out angle) ||
            !double.IsFinite(angle) ||
            angle < MinAimAngleDegrees ||
            angle >= MaxAimAngleDegrees)
        {
            Console.WriteLine($"Invalid angle from {playerId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadIdle(
        JsonElement root,
        string message,
        string playerId,
        out double x,
        out double y,
        out double angle)
    {
        angle = default;

        if (!TryReadCoordinates(root, message, playerId, "idle", out x, out y))
            return false;

        if (!Helper.TryGetNumber(root, "angle", out angle) ||
            !double.IsFinite(angle) ||
            angle < MinAimAngleDegrees ||
            angle >= MaxAimAngleDegrees)
        {
            Console.WriteLine($"Invalid idle angle from {playerId}: {message}");
            return false;
        }

        return true;
    }

    // Sends a payload to the clients currently connected to a room.
    public async Task BroadcastToRoomAsync(string roomId, object payload)
    {
        if (!rooms.TryGetValue(roomId, out var room))
            return;

        await BroadcastToRoomAsync(room, payload);
    }

    public async Task BroadcastToRoomAsync(GameRoom room, object payload)
    {
        var sendTasks = new List<Task>();

        // Snapshot room members, then send only to clients still assigned to this room.
        foreach (var playerId in room.PlayerIdsSnapshot())
        {
            if (clients.TryGetValue(playerId, out var client) &&
                client.RoomId == room.RoomId &&
                client.HasJoinedGame)
            {
                sendTasks.Add(SendJsonAsync(client, payload));
            }
        }

        await Task.WhenAll(sendTasks);
    }
}

public sealed class GameRoom
{
    // Protects capacity checks and state changes that must happen atomically.
    private readonly object syncRoot = new();

    // Reserved sockets are assigned a room; joined players are visible in-game.
    private readonly ConcurrentDictionary<string, byte> playerIds = new();
    private readonly ConcurrentDictionary<string, byte> joinedPlayerIds = new();
    private readonly ConcurrentDictionary<string, LeaderboardEntry> leaderboard = new();

    private GameRoom(string roomId)
    {
        RoomId = roomId;
    }

    public string RoomId { get; }
    public int MaxPlayers { get; } = 16;
    public DateTime? StartTimeUtc { get; private set; }
    public DateTime? EndTimeUtc { get; private set; }
    public int DurationSeconds { get; } = 600;
    public GameRoomState State { get; private set; } = GameRoomState.Waiting;
    public IReadOnlyCollection<string> Players => playerIds.Keys.ToArray();

    // Calculated from the authoritative server end time once the first player joins.
    public int RemainingSeconds =>
        EndTimeUtc is null
            ? DurationSeconds
            : Math.Max(0, (int)Math.Ceiling((EndTimeUtc.Value - DateTime.UtcNow).TotalSeconds));

    public bool IsEmpty => playerIds.IsEmpty;

    public static GameRoom Create()
    {
        return new GameRoom(Guid.NewGuid().ToString("N"));
    }

    public bool TryReservePlayer(string playerId)
    {
        lock (syncRoot)
        {
            // Do not let clients reserve ended or full rooms.
            if (State == GameRoomState.Ended || playerIds.Count >= MaxPlayers)
                return false;

            playerIds[playerId] = 0;
            return true;
        }
    }

    public void MarkPlayerJoined(string playerId, string playerName, int level)
    {
        lock (syncRoot)
        {
            if (State == GameRoomState.Ended)
                return;

            if (!playerIds.ContainsKey(playerId))
                playerIds[playerId] = 0;

            if (State == GameRoomState.Waiting)
            {
                var startTimeUtc = DateTime.UtcNow;
                StartTimeUtc = startTimeUtc;
                EndTimeUtc = startTimeUtc.AddSeconds(DurationSeconds);
                State = GameRoomState.Running;
            }

            joinedPlayerIds[playerId] = 0;
            leaderboard.AddOrUpdate(
                playerId,
                LeaderboardEntry.Empty(playerId, playerName, level),
                (_, entry) => entry.WithProfile(playerName, level)
            );
        }
    }

    public void RemovePlayer(string playerId)
    {
        playerIds.TryRemove(playerId, out _);
        joinedPlayerIds.TryRemove(playerId, out _);
        leaderboard.TryRemove(playerId, out _);
    }

    public string[] PlayerIdsSnapshot() =>
        joinedPlayerIds.Keys.ToArray();

    public LeaderboardEntry[] LeaderboardSnapshot() =>
        leaderboard.Values
            .OrderByDescending(entry => entry.Score)
            .ThenByDescending(entry => entry.Kills)
            .ThenBy(entry => entry.Deaths)
            .ThenBy(entry => entry.PlayerId, StringComparer.Ordinal)
            .ToArray();

    public void RecordHit(string shooterPlayerId, string targetPlayerId, double damage, bool killed)
    {
        leaderboard.AddOrUpdate(
            shooterPlayerId,
            LeaderboardEntry.Empty(shooterPlayerId).WithDamage(damage, killed),
            (_, entry) => entry.WithDamage(damage, killed)
        );

        if (!killed)
            return;

        leaderboard.AddOrUpdate(
            targetPlayerId,
            LeaderboardEntry.Empty(targetPlayerId).WithDeath(),
            (_, entry) => entry.WithDeath()
        );
    }

    public bool MarkEnded()
    {
        lock (syncRoot)
        {
            // Idempotent so multiple timer checks cannot end the same room twice.
            if (State == GameRoomState.Ended)
                return false;

            State = GameRoomState.Ended;
            return true;
        }
    }
}

public enum GameRoomState
{
    Waiting,
    Running,
    Ended
}

public readonly record struct HitRequest(
    string TargetPlayerId,
    string WeaponType,
    double Damage,
    string? ShotId);

public readonly record struct ShootRequest(
    string? WeaponType,
    double Angle,
    double? X,
    double? Y,
    double? StartX,
    double? StartY,
    double? TargetX,
    double? TargetY);

public readonly record struct ShotTargetKey(string ShotId, string TargetPlayerId);

public readonly record struct HealthSnapshot(double Health, bool IsDead);

public readonly record struct RespawnResult(double Health, bool IsDead, double X, double Y);

public readonly record struct DamageResult(double Health, double Damage, bool IsDead);

public readonly record struct PlayerState(double X, double Y, double Angle, string Weapon, double Health, bool IsDead);

public readonly record struct LeaderboardEntry(
    [property: JsonPropertyName("playerId")]
    string PlayerId,
    [property: JsonPropertyName("playerName")]
    string PlayerName,
    [property: JsonPropertyName("level")]
    int Level,
    [property: JsonPropertyName("score")]
    int Score,
    [property: JsonPropertyName("kills")]
    int Kills,
    [property: JsonPropertyName("deaths")]
    int Deaths,
    [property: JsonPropertyName("damageDealt")]
    double DamageDealt)
{
    public static LeaderboardEntry Empty(string playerId) =>
        new(playerId, string.Empty, 0, 0, 0, 0, 0);

    public static LeaderboardEntry Empty(string playerId, string playerName, int level) =>
        new(playerId, playerName, level, 0, 0, 0, 0);

    public LeaderboardEntry WithProfile(string playerName, int level) =>
        this with
        {
            PlayerName = playerName,
            Level = level
        };

    public LeaderboardEntry WithDamage(double damage, bool killed) =>
        this with
        {
            Score = killed ? Score + 1 : Score,
            Kills = killed ? Kills + 1 : Kills,
            DamageDealt = DamageDealt + damage
        };

    public LeaderboardEntry WithDeath() =>
        this with
        {
            Deaths = Deaths + 1
        };
}

public sealed class ClientConnection
{
    public ClientConnection(string connectionId, WebSocket socket)
    {
        ConnectionId = connectionId;
        Socket = socket;
    }

    public SemaphoreSlim SendLock { get; } = new(1, 1);
    public string ConnectionId { get; }
    public WebSocket Socket { get; }
    private readonly object stateLock = new();
    private long lastActivityUtcTicks = DateTimeOffset.UtcNow.UtcTicks;
    private long idleSinceUtcTicks;
    private bool hasState;
    private string? playerId;
    private string? roomId;
    private string playerName = string.Empty;
    private int level;

    public string PlayerId => playerId ?? ConnectionId;
    public string RoomId => roomId ?? string.Empty;
    public string PlayerName => playerName;
    public int Level => level;
    public string LogId => playerId ?? ConnectionId;
    public bool HasPlayerId => playerId is not null;
    public bool HasRoom => roomId is not null;

    public DateTimeOffset LastActivityUtc =>
        new(Interlocked.Read(ref lastActivityUtcTicks), TimeSpan.Zero);

    public bool IsIdle => Interlocked.Read(ref idleSinceUtcTicks) != 0;

    public DateTimeOffset IdleSinceUtc =>
        new(Interlocked.Read(ref idleSinceUtcTicks), TimeSpan.Zero);

    public bool HasJoinedGame
    {
        get
        {
            lock (stateLock)
            {
                return hasState;
            }
        }
    }

    private double x;
    private double y;
    private double angle;
    private string weapon = string.Empty;
    private double health = 100.0;
    private bool isDead;
    private readonly HashSet<ShotTargetKey> processedShotHits = new();

    public void Identify(string playerId, string playerName, int level)
    {
        lock (stateLock)
        {
            this.playerId = playerId;
            this.playerName = playerName;
            this.level = level;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
    }

    public void UpdateProfile(string playerName, int level)
    {
        lock (stateLock)
        {
            this.playerName = playerName;
            this.level = level;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
    }

    public void AssignRoom(string roomId)
    {
        lock (stateLock)
        {
            this.roomId = roomId;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
    }

    public bool TryGetStateSnapshot(out PlayerState state)
    {
        lock (stateLock)
        {
            if (!hasState)
            {
                state = default;
                return false;
            }

            state = new PlayerState(x, y, angle, weapon, health, isDead);
            return true;
        }
    }

    public double MarkJoined(double x, double y, double angle, string weapon)
    {
        lock (stateLock)
        {
            this.x = x;
            this.y = y;
            this.angle = angle;
            this.weapon = weapon;
            health = 100.0;
            isDead = false;
            hasState = true;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
        Interlocked.Exchange(ref idleSinceUtcTicks, 0);

        return health;
    }

    public void MarkMovement(double x, double y, double angle)
    {
        lock (stateLock)
        {
            this.x = x;
            this.y = y;
            this.angle = angle;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
        Interlocked.Exchange(ref idleSinceUtcTicks, 0);
    }

    public void MarkAngle(double angle)
    {
        lock (stateLock)
        {
            this.angle = angle;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
        Interlocked.Exchange(ref idleSinceUtcTicks, 0);
    }

    public void MarkWeaponSwitch(string weapon)
    {
        lock (stateLock)
        {
            this.weapon = weapon;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
        Interlocked.Exchange(ref idleSinceUtcTicks, 0);
    }

    public void MarkIdle(double x, double y, double angle)
    {
        var now = DateTimeOffset.UtcNow.UtcTicks;

        lock (stateLock)
        {
            this.x = x;
            this.y = y;
            this.angle = angle;
        }

        Interlocked.Exchange(ref lastActivityUtcTicks, now);
        Interlocked.CompareExchange(ref idleSinceUtcTicks, now, 0);
    }

    public void MarkHeartbeat()
    {
        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
    }

    public HealthSnapshot GetAuthoritativeHealthSnapshot()
    {
        lock (stateLock)
        {
            return new HealthSnapshot(health, isDead);
        }
    }

    public bool IsAlive
    {
        get
        {
            lock (stateLock)
            {
                return hasState && !isDead && health > 0;
            }
        }
    }

    public bool TryMarkShotHit(string shotId, string targetPlayerId)
    {
        lock (stateLock)
        {
            return processedShotHits.Add(new ShotTargetKey(shotId, targetPlayerId));
        }
    }

    public DamageResult ApplyDamage(double damage)
    {
        lock (stateLock)
        {
            if (!hasState || isDead || damage <= 0)
                return new DamageResult(health, 0, isDead);

            var previousHealth = health;
            health = Math.Clamp(health - damage, 0, 100.0);

            if (health <= 0)
                isDead = true;

            return new DamageResult(health, previousHealth - health, isDead);
        }
    }

    public RespawnResult Respawn(double spawnX, double spawnY)
    {
        lock (stateLock)
        {
            health = 100.0;
            isDead = false;
            x = spawnX;
            y = spawnY;
            processedShotHits.Clear();

            return new RespawnResult(health, isDead, x, y);
        }
    }
}
