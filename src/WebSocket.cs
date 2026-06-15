using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text;

public sealed class Ws
{
    private static readonly TimeSpan TimeSyncInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan EndedRoomRetention = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan SendLockTimeout = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan SendTimeout = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan CloseTimeout = TimeSpan.FromSeconds(2);
    private const double MinAimAngleDegrees = 0.0;
    private const double MaxAimAngleDegrees = 360.0;
    private const int MaxMessageBytes = 16 * 1024;
    private const int MaxWeaponTypeLength = 64;
    private const int MaxShotIdLength = 128;
    private const int MaxPlayerIdLength = 128;
    private const int MaxPlayerNameLength = 64;
    private const int MaxChatContentLength = 300;
    private const int MinPlayerLevel = 0;
    private const int MaxPlayerLevel = 1000;
    private const double DefaultPlayerHealth = 100.0;
    private const double MaxHitDamage = DefaultPlayerHealth;
    private const double MedkitPickupDistance = 64.0;
    private const double PlayerPositionTolerance = 64.0;
    private const double MinRocketLauncherDamage = 1.0;
    private const double MaxRocketLauncherDamage = 80.0;
    private const string MedkitHealRequest = "medkit_heal";
    private const string MedkitSource = "medkit";
    private const string AssultRifleWeaponType = "Assult rifle";
    private const string SniperWeaponType = "Sniper";
    private const string RocketLauncherWeaponType = "Rocket Launcher";
    private const string ShotgunWeaponType = "Shotgun";

    private static readonly IReadOnlyDictionary<string, string> AcceptedWeaponTypes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            [AssultRifleWeaponType] = AssultRifleWeaponType,
            [SniperWeaponType] = SniperWeaponType,
            [RocketLauncherWeaponType] = RocketLauncherWeaponType,
            [ShotgunWeaponType] = ShotgunWeaponType
        };

    private static readonly IReadOnlyDictionary<string, double> ServerWeaponDamage =
        new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);

    private readonly ConcurrentDictionary<string, ClientConnection> clients;
    private readonly IMatchRepository matchRepository;

    // Active match rooms keyed by room id. Ended rooms are retained briefly for final client packets.
    private readonly ConcurrentDictionary<string, GameRoom> rooms = new();

    // Serializes matchmaking and room removal so concurrent connects can't fragment players
    // across half-empty rooms, and can't reserve a slot in a room being removed.
    private readonly object roomsLock = new();

    public Ws(ConcurrentDictionary<string, ClientConnection> clients)
        : this(clients, NullMatchRepository.Instance)
    {
    }

    public Ws(
        ConcurrentDictionary<string, ClientConnection> clients,
        IMatchRepository matchRepository
    )
    {
        this.clients = clients;
        this.matchRepository = matchRepository;
        _ = RunRoomTimersAsync();
    }

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

        Console.WriteLine($"Socket connected: {connectionId}");

        using var connectionLifetime = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);

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

            await CloseSocketAsync(client, WebSocketCloseStatus.NormalClosure, "Closing");

            socket.Dispose();
            Console.WriteLine($"Client disconnected: {client.LogId}");

            if (disconnectedRoom is not null && client.HasJoinedGame)
                await BroadcastPlayerLeftAsync(disconnectedRoom, client.PlayerId);
        }
    }

    private GameRoom AssignRoom(string playerId)
    {
        lock (roomsLock)
        {
            // First reserve a slot in any non-ended room that still has capacity.
            foreach (var room in rooms.Values)
            {
                if (room.TryReservePlayer(playerId))
                    return room;
            }

            // No room had space. Create one and reserve atomically so two simultaneous
            // connects don't each spawn a fresh half-empty room.
            var newRoom = GameRoom.Create();
            newRoom.TryReservePlayer(playerId);
            rooms[newRoom.RoomId] = newRoom;
            return newRoom;
        }
    }

    private GameRoom? RemovePlayerFromRoom(ClientConnection client, bool removeLeaderboardEntry = false)
    {
        lock (roomsLock)
        {
            if (!rooms.TryGetValue(client.RoomId, out var room))
                return null;

            var hadJoined = client.HasJoinedGame;
            room.RemovePlayer(client.PlayerId, removeLeaderboardEntry);

            // Waiting rooms have no match state. Running rooms stay alive until the timer ends
            // so a page reload or short network drop does not reset the match.
            if (room.IsEmpty && room.State == GameRoomState.Waiting)
            {
                rooms.TryRemove(room.RoomId, out _);
                return null;
            }

            return hadJoined ? room : null;
        }
    }

    private async Task LeaveRoomAsync(ClientConnection client, string reason)
    {
        if (!client.HasPlayerId || !client.HasRoom)
        {
            Console.WriteLine($"leave_match before on_connect from {client.LogId}");
            return;
        }

        var roomId = client.RoomId;
        var playerId = client.PlayerId;
        var leftRoom = RemovePlayerFromRoom(client, removeLeaderboardEntry: true);
        client.LeaveRoom();

        Console.WriteLine($"Player left match: playerId={playerId}, roomId={roomId}, reason={reason}");

        await SendJsonAsync(client, new
        {
            type = "match_left",
            player_id = playerId,
            room_id = roomId
        });

        if (leftRoom is not null)
            await BroadcastPlayerLeftAsync(leftRoom, playerId);
    }

    private async Task BroadcastPlayerLeftAsync(GameRoom room, string playerId)
    {
        var leaderboard = room.LeaderboardSnapshot();

        // Only players remaining in the same room should see this player leave.
        await BroadcastToRoomAsync(room, new
        {
            type = "player_left",
            player_id = playerId,
            leaderboard
        });

        await BroadcastToRoomAsync(room, new
        {
            type = "leaderboard_update",
            room_id = room.RoomId,
            leaderboard
        });
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
                    if (room.State == GameRoomState.Ended)
                    {
                        CleanupEndedRoomIfExpired(room);
                        continue;
                    }

                    if (room.State != GameRoomState.Running)
                        continue;

                    var remainingSeconds = room.RemainingSeconds;

                    if (remainingSeconds <= 0)
                    {
                        // Time is up: end the match once, but keep the room briefly for final packets.
                        await EndRoomAsync(room);
                        continue;
                    }

                    await BroadcastToRoomAsync(room, new
                    {
                        type = "time_sync",
                        room_id = room.RoomId,
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

        await BroadcastMatchEndedAsync(room);
        _ = SaveMatchAsync(room);
    }

    private void CleanupEndedRoomIfExpired(GameRoom room)
    {
        var endedAtUtc = room.EndedAtUtc;
        if (endedAtUtc is null || DateTime.UtcNow - endedAtUtc.Value < EndedRoomRetention)
            return;

        lock (roomsLock)
        {
            if (rooms.TryRemove(room.RoomId, out _))
                Console.WriteLine($"Cleaned up ended room after retention: {room.RoomId}");
        }
    }

    private async Task<bool> EndRoomIfExpiredAsync(GameRoom room)
    {
        if (room.State == GameRoomState.Running && room.RemainingSeconds <= 0)
        {
            await EndRoomAsync(room);
            return true;
        }

        return false;
    }

    private async Task<bool> EnsureRoomRunningAsync(GameRoom room)
    {
        await EndRoomIfExpiredAsync(room);
        return room.State == GameRoomState.Running;
    }

    private Task BroadcastMatchEndedAsync(GameRoom room) =>
        BroadcastToRoomAsync(room, MatchEndedPayload(room));

    private Task SendMatchEndedAsync(ClientConnection client, GameRoom room) =>
        SendJsonAsync(client, MatchEndedPayload(room));

    private static object MatchEndedPayload(GameRoom room) => new
    {
        type = "match_ended",
        match_id = room.MatchId,
        room_id = room.RoomId,
        remaining_seconds = 0,
        duration_seconds = room.DurationSeconds,
        leaderboard = room.LeaderboardSnapshot()
    };

    private async Task SaveMatchAsync(GameRoom room)
    {
        const int maxAttempts = 3;

        try
        {
            var match = room.MatchRecordSnapshot();
            var playerIds = room.LeaderboardSnapshot()
                .Select(entry => entry.PlayerId)
                .ToArray();

            for (var attempt = 1; ; attempt += 1)
            {
                try
                {
                    await matchRepository.SaveAsync(match);
                    break;
                }
                catch when (attempt < maxAttempts)
                {
                    await Task.Delay(TimeSpan.FromSeconds(attempt));
                }
            }

            var payload = new
            {
                type = "match_saved",
                match_id = match.Id,
                room_id = room.RoomId
            };

            await SendToPlayersAsync(playerIds, payload);
            Console.WriteLine(
                $"Saved match {match.Id} for room {room.RoomId}"
            );
        }
        catch (Exception ex)
        {
            Console.WriteLine(
                $"Failed to save match {room.MatchId} for room {room.RoomId} after {maxAttempts} attempts: {ex.Message}"
            );
        }
    }

    private async Task SendToPlayersAsync(
        IEnumerable<string> playerIds,
        object payload
    )
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(payload);
        var sendTasks = playerIds
            .Distinct(StringComparer.Ordinal)
            .Select(playerId =>
                clients.TryGetValue(playerId, out var client)
                    ? SendBytesAsync(client, bytes)
                    : Task.CompletedTask
            );

        await Task.WhenAll(sendTasks);
    }

    // Sends one JSON message while serializing writes per socket.
    public Task SendJsonAsync(ClientConnection client, object payload)
    {
        if (client.Socket.State != WebSocketState.Open)
            return Task.CompletedTask;

        return SendBytesAsync(client, JsonSerializer.SerializeToUtf8Bytes(payload));
    }

    // Sends an already-encoded UTF-8 JSON payload. Broadcasts share one buffer across recipients
    // so the same room update isn't re-serialized per player.
    private async Task SendBytesAsync(ClientConnection client, byte[] bytes)
    {
        if (client.Socket.State != WebSocketState.Open)
            return;

        var hasSendLock = false;

        try
        {
            if (!await client.SendLock.WaitAsync(SendLockTimeout))
            {
                AbortClientSocket(client, $"send queue blocked for {SendLockTimeout.TotalSeconds:F0}s");
                return;
            }

            hasSendLock = true;

            if (client.Socket.State == WebSocketState.Open)
            {
                using var sendTimeout = new CancellationTokenSource(SendTimeout);
                await client.Socket.SendAsync(
                    new ArraySegment<byte>(bytes),
                    WebSocketMessageType.Text,
                    true,
                    sendTimeout.Token
                );
            }
        }
        catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
        {
            Console.WriteLine($"Send failed for {client.PlayerId}: {ex.Message}");
            if (ex is OperationCanceledException)
                AbortClientSocket(client, $"send timed out after {SendTimeout.TotalSeconds:F0}s");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Unexpected send failure for {client.PlayerId}: {ex}");
            AbortClientSocket(client, "unexpected send failure");
        }
        finally
        {
            if (hasSendLock)
                client.SendLock.Release();
        }
    }

    private async Task CloseSocketAsync(ClientConnection client, WebSocketCloseStatus status, string reason)
    {
        if (client.Socket.State is not (WebSocketState.Open or WebSocketState.CloseReceived))
            return;

        try
        {
            using var closeTimeout = new CancellationTokenSource(CloseTimeout);
            await client.Socket.CloseAsync(status, reason, closeTimeout.Token);
        }
        catch (Exception ex) when (IsExpectedWebSocketDisconnect(ex))
        {
            Console.WriteLine($"Close skipped for {client.LogId}: {ex.Message}");
            AbortClientSocket(client, $"close failed during {reason}");
        }
    }

    private static void AbortClientSocket(ClientConnection client, string reason)
    {
        Console.WriteLine($"Aborting websocket for {client.LogId}: {reason}");
        client.Socket.Abort();
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

            if (!TryReadMessageKind(root, out var type))
            {
                Console.WriteLine($"Message missing type from {client.LogId}: {message}");
                return;
            }

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
                            player_id = playerId
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
                if (room is not null)
                {
                    await EndRoomIfExpiredAsync(room);

                    if (room.State == GameRoomState.Ended)
                    {
                        await SendMatchEndedAsync(client, room);
                        return;
                    }
                }

                if (room is null)
                    room = AssignRoom(playerId);

                client.AssignRoom(room.RoomId);
                Console.WriteLine($"On connect from {client.PlayerId}: name={client.PlayerName}, level={client.Level}, reservedRoom={room.RoomId}");

                await SendJsonAsync(client, new
                {
                    type = "room_reserved",
                    player_id = client.PlayerId,
                    player_name = client.PlayerName,
                    level = client.Level,
                    room_id = room.RoomId,
                    duration_seconds = room.DurationSeconds,
                    remaining_seconds = room.RemainingSeconds,
                    leaderboard = room.LeaderboardSnapshot()
                });

                return;
            }

            if (client.HasPlayerId &&
                !ValidateOptionalSessionFields(root, message, client))
            {
                return;
            }

            if (type == "on_join")
            {
                if (!client.HasPlayerId || !client.HasRoom)
                {
                    Console.WriteLine($"Join before on_connect from {client.LogId}: {message}");
                    return;
                }

                // Block repeat on_join on the same socket — it would otherwise reset health to full,
                // letting a wounded or dead player heal by re-sending the join packet. Respawn is the
                // intended path for coming back from death.
                if (client.HasJoinedGame)
                {
                    Console.WriteLine($"Rejected duplicate on_join from {client.PlayerId} in room {client.RoomId}");
                    return;
                }

                if (!rooms.TryGetValue(client.RoomId, out var room))
                    return;

                await EndRoomIfExpiredAsync(room);

                if (room.State == GameRoomState.Ended)
                {
                    await SendMatchEndedAsync(client, room);
                    return;
                }

                if (!TryReadPlayerState(root, message, client.PlayerId, "on_join", out var x, out var y, out var angle, out var aimFrame, out var weapon))
                    return;

                var health = client.MarkJoined(x, y, angle, aimFrame, weapon);
                room.MarkPlayerJoined(client.PlayerId, client.PlayerName, client.Level);
                Console.WriteLine($"On join from {client.PlayerId}: name={client.PlayerName}, level={client.Level}, x={x}, y={y}, angle={angle}, weapon={weapon}, health={health}");

                await SendJsonAsync(client, new
                {
                    type = "room_joined",
                    player_id = client.PlayerId,
                    player_name = client.PlayerName,
                    level = client.Level,
                    room_id = room.RoomId,
                    duration_seconds = room.DurationSeconds,
                    remaining_seconds = room.RemainingSeconds,
                    leaderboard = room.LeaderboardSnapshot()
                });

                await SendExistingPlayersAsync(client);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_connected",
                    player_id = client.PlayerId,
                    player_name = client.PlayerName,
                    level = client.Level,
                    x,
                    y,
                    angle,
                    aim_frame = aimFrame,
                    weapon_type = weapon,
                    health,
                    is_dead = false
                });

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "leaderboard_update",
                    room_id = client.RoomId,
                    leaderboard = room.LeaderboardSnapshot()
                });

                await SendExistingMedkitsAsync(client, room);

                return;
            }

            if (type == "message" || type == "chat_message")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!TryReadChatMessage(root, message, client, out var chat))
                    return;

                await BroadcastToRoomAsync(client.RoomId, chat.ToPayload(client.RoomId));

                return;
            }

            if (type == "leave_match")
            {
                if (!TryReadLeaveMatch(root, message, client, out _))
                    return;

                await LeaveRoomAsync(client, "client_request");

                return;
            }

            if (type == "leaderboard_request")
            {
                if (!TryReadLeaderboardRequest(root, message, client, out var roomId))
                    return;

                if (!rooms.TryGetValue(roomId, out var room))
                {
                    Console.WriteLine($"leaderboard_request for missing room from {client.PlayerId}: {message}");
                    return;
                }

                await EndRoomIfExpiredAsync(room);

                await SendJsonAsync(client, new
                {
                    type = "leaderboard_update",
                    room_id = room.RoomId,
                    leaderboard = room.LeaderboardSnapshot()
                });

                return;
            }

            if (type == "move")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!client.IsAlive)
                    return;

                if (!TryReadMove(root, message, client.PlayerId, out var x, out var y, out var angle, out var aimFrame))
                    return;

                client.MarkMovement(x, y, angle, aimFrame);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_move",
                    player_id = client.PlayerId,
                    x,
                    y,
                    angle,
                    aim_frame = aimFrame
                });

                return;
            }

            if (type == "angle")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!client.IsAlive)
                    return;

                if (!TryReadAngle(root, message, client.PlayerId, out var angle, out var aimFrame))
                    return;

                client.MarkAngle(angle, aimFrame);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_angle",
                    player_id = client.PlayerId,
                    angle,
                    aim_frame = aimFrame
                });

                return;
            }

            if (type == "hit")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!TryReadHit(root, message, client.PlayerId, out var hit))
                    return;

                await ResolveHitAsync(client, hit);

                return;
            }

            if (type == "heal")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!rooms.TryGetValue(client.RoomId, out var room) ||
                    !TryReadHeal(root, message, client, out var heal))
                    return;

                if (!client.TryGetStateSnapshot(out var state) ||
                    state.IsDead ||
                    !PositionsWithin(state.X, state.Y, heal.X, heal.Y, PlayerPositionTolerance) ||
                    state.Health != heal.CurrentHealth ||
                    (heal.WeaponType is not null && state.Weapon != heal.WeaponType))
                {
                    Console.WriteLine($"Rejected stale or invalid heal state from {client.PlayerId}: {message}");
                    return;
                }

                if (!room.TryConsumeMedkit(
                        heal.MedkitId,
                        heal.X,
                        heal.Y,
                        MedkitPickupDistance,
                        out var medkit))
                {
                    Console.WriteLine($"Rejected missing, distant, or duplicate medkit {heal.MedkitId} from {client.PlayerId}");
                    return;
                }

                var result = client.ApplyHeal(DefaultPlayerHealth);
                if (result.Heal <= 0)
                {
                    room.RestoreMedkit(medkit);
                    Console.WriteLine($"Rejected heal from {client.PlayerId}: player is dead or already at full health");
                    return;
                }

                client.MarkAngle(heal.Angle, heal.AimFrame);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "medkit_removed",
                    medkit_id = heal.MedkitId
                });

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "heal",
                    request = MedkitHealRequest,
                    source = MedkitSource,
                    medkit_id = heal.MedkitId,
                    player_id = client.PlayerId,
                    x = state.X,
                    y = state.Y,
                    health = result.Health,
                    heal_amount = result.Heal,
                    is_dead = result.IsDead,
                    angle = heal.Angle,
                    aim_frame = heal.AimFrame
                });

                return;
            }

            if (type == "player_death")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!TryReadCoordinates(root, message, client.PlayerId, "player_death", out var x, out var y) ||
                    !client.TryGetStateSnapshot(out var state) ||
                    !PositionsWithin(state.X, state.Y, x, y, PlayerPositionTolerance))
                {
                    Console.WriteLine($"Rejected invalid player_death from {client.PlayerId}: {message}");
                    return;
                }

                if (!rooms.TryGetValue(client.RoomId, out var room))
                    return;

                var death = client.ApplyDeath();
                if (!death.BecameDead)
                    return;

                room.RecordDeath(client.PlayerId);

                await BroadcastToRoomAsync(room, new
                {
                    type = "player_health",
                    player_id = client.PlayerId,
                    health = death.Health,
                    damage = death.Damage,
                    is_dead = true,
                    reason = "player_death"
                });

                await BroadcastToRoomAsync(room, new
                {
                    type = "player_death",
                    player_id = client.PlayerId,
                    x = state.X,
                    y = state.Y
                });

                await SpawnDeathMedkitAsync(room, client, state);

                await BroadcastToRoomAsync(room, new
                {
                    type = "leaderboard_update",
                    room_id = room.RoomId,
                    leaderboard = room.LeaderboardSnapshot()
                });

                return;
            }

            if (type == "health_update")
            {
                Console.WriteLine($"Rejected client-authoritative health update from {client.PlayerId}: {message}");

                return;
            }

            if (type == "respawn")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!TryReadRespawn(root, message, client.PlayerId, out var spawnX, out var spawnY, out var angle, out var aimFrame, out var weapon))
                    return;

                // Respawn must only fire after death. Without this, a living player at low HP could
                // send respawn to instantly refill health and clear shot-dedup state.
                if (!client.GetAuthoritativeHealthSnapshot().IsDead)
                {
                    Console.WriteLine($"Rejected respawn from live player {client.PlayerId}");
                    return;
                }

                var result = client.Respawn(spawnX, spawnY, angle, aimFrame, weapon);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_respawned",
                    player_id = client.PlayerId,
                    health = result.Health,
                    is_dead = result.IsDead,
                    x = result.X,
                    y = result.Y,
                    angle = result.Angle,
                    aim_frame = result.AimFrame,
                    weapon_type = result.Weapon
                });

                if (rooms.TryGetValue(client.RoomId, out var room))
                {
                    foreach (var medkit in room.RemoveMedkitsForOwner(client.PlayerId))
                    {
                        await BroadcastToRoomAsync(room, new
                        {
                            type = "medkit_removed",
                            medkit_id = medkit.MedkitId
                        });
                    }
                }

                return;
            }

            if (type == "idle")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!client.IsAlive)
                    return;

                if (!TryReadIdle(root, message, client.PlayerId, out var x, out var y, out var angle, out var aimFrame))
                    return;

                client.MarkIdle(x, y, angle, aimFrame);

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_idle",
                    player_id = client.PlayerId,
                    x,
                    y,
                    angle,
                    aim_frame = aimFrame
                });

                return;
            }

            if (type == "weapon_switch")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
                    return;

                if (!TryReadWeapon(root, message, client.PlayerId, "weapon_switch", out var weapon))
                    return;

                client.MarkWeaponSwitch(weapon);
                Console.WriteLine($"Weapon switch from {client.PlayerId}: weapon={weapon}");

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_weapon_switch",
                    player_id = client.PlayerId,
                    weapon_type = weapon
                });

                return;
            }

            if (type == "shoot")
            {
                if (!await RequireActiveJoinedAsync(client, type, message))
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
                    ["player_id"] = client.PlayerId,
                    ["weapon_type"] = shoot.WeaponType ?? state.Weapon,
                    ["angle"] = shoot.Angle,
                    ["x"] = shoot.X ?? state.X,
                    ["y"] = shoot.Y ?? state.Y
                };

                if (shoot.StartX is not null)
                    bulletSpawn["start_x"] = shoot.StartX.Value;

                if (shoot.StartY is not null)
                    bulletSpawn["start_y"] = shoot.StartY.Value;

                if (shoot.TargetX is not null)
                    bulletSpawn["target_x"] = shoot.TargetX.Value;

                if (shoot.TargetY is not null)
                    bulletSpawn["target_y"] = shoot.TargetY.Value;

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
                player_id = roomClient.PlayerId,
                player_name = roomClient.PlayerName,
                level = roomClient.Level,
                x = state.X,
                y = state.Y,
                angle = state.Angle,
                aim_frame = state.AimFrame,
                weapon_type = state.Weapon,
                health = state.Health,
                is_dead = state.IsDead
            });
        }
    }

    private async Task SendExistingMedkitsAsync(ClientConnection client, GameRoom room)
    {
        foreach (var medkit in room.MedkitsSnapshot())
        {
            await SendJsonAsync(client, new
            {
                type = "medkit_spawned",
                medkit_id = medkit.MedkitId,
                owner_player_id = medkit.OwnerPlayerId,
                x = medkit.X,
                y = medkit.Y
            });
        }
    }

    private async Task SpawnDeathMedkitAsync(
        GameRoom room,
        ClientConnection player,
        PlayerState state)
    {
        if (!player.TryClaimDeathMedkit())
            return;

        var medkit = room.SpawnMedkit(player.PlayerId, state.X, state.Y);

        await BroadcastToRoomAsync(room, new
        {
            type = "medkit_spawned",
            medkit_id = medkit.MedkitId,
            owner_player_id = medkit.OwnerPlayerId,
            x = medkit.X,
            y = medkit.Y
        });
    }

    private static bool RequireJoined(ClientConnection client, string messageType, string message)
    {
        if (client.HasJoinedGame)
            return true;

        Console.WriteLine($"{messageType} before on_join from {client.LogId}: {message}");
        return false;
    }

    private async Task<bool> RequireActiveJoinedAsync(ClientConnection client, string messageType, string message)
    {
        if (!RequireJoined(client, messageType, message))
            return false;

        if (!rooms.TryGetValue(client.RoomId, out var room))
        {
            Console.WriteLine($"{messageType} for missing room from {client.PlayerId}: {message}");
            return false;
        }

        var endedFromThisPacket = await EndRoomIfExpiredAsync(room);

        if (room.State == GameRoomState.Running)
            return true;

        if (room.State == GameRoomState.Ended)
        {
            Console.WriteLine($"Ignored {messageType} after match end from {client.PlayerId} in room {room.RoomId}");
            if (!endedFromThisPacket)
                await SendMatchEndedAsync(client, room);

            return false;
        }

        Console.WriteLine($"Ignored {messageType} in non-running room {room.RoomId} from {client.PlayerId}: state={room.State}");
        return false;
    }

    private async Task ResolveHitAsync(ClientConnection shooter, HitRequest hit)
    {
        if (!rooms.TryGetValue(shooter.RoomId, out var room))
            return;

        if (!await EnsureRoomRunningAsync(room))
        {
            if (room.State == GameRoomState.Ended)
                await SendMatchEndedAsync(shooter, room);

            return;
        }

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

        var isSelfHit = hit.TargetPlayerId == shooter.PlayerId;
        var isRocket = IsRocketLauncher(hit.WeaponType);

        if (isSelfHit && !isRocket)
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
        var isSelfKill = isSelfHit && result.IsDead;
        var shouldUpdateLeaderboard = result.Damage > 0 && !isSelfHit;

        if (shouldUpdateLeaderboard)
            room.RecordHit(shooter.PlayerId, target.PlayerId, result.Damage, result.IsDead);
        else if (isSelfKill)
            room.RecordDeath(target.PlayerId);

        await BroadcastToRoomAsync(shooter.RoomId, new
        {
            type = "player_health",
            player_id = target.PlayerId,
            health = result.Health,
            damage = result.Damage,
            is_dead = result.IsDead,
            attacker_id = shooter.PlayerId,
            attacker_weapon_type = hit.WeaponType
        });

        if (result.IsDead)
        {
            if (target.TryGetStateSnapshot(out var deadState))
            {
                await BroadcastToRoomAsync(room, new
                {
                    type = "player_death",
                    player_id = target.PlayerId,
                    x = deadState.X,
                    y = deadState.Y
                });

                await SpawnDeathMedkitAsync(room, target, deadState);
            }

            await BroadcastToRoomAsync(room, new
            {
                type = "kill_feed",
                killer_id = shooter.PlayerId,
                killer_name = shooter.PlayerName,
                victim_id = target.PlayerId,
                victim_name = target.PlayerName,
                weapon_type = hit.WeaponType,
                self_kill = isSelfKill,
                killer = shooter.PlayerName,
                killed = target.PlayerName
            });
        }

        if (shouldUpdateLeaderboard || isSelfKill)
        {
            await BroadcastToRoomAsync(room, new
            {
                type = "leaderboard_update",
                room_id = room.RoomId,
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

    private static bool TryReadHeal(
        JsonElement root,
        string message,
        ClientConnection client,
        out MedkitHealRequestData heal)
    {
        heal = default;

        if (!Helper.TryGetString(root, "request", out var request) ||
            request != MedkitHealRequest ||
            !Helper.TryGetString(root, "medkit_id", out var medkitId) ||
            medkitId.Length > MaxShotIdLength ||
            !Helper.TryGetString(root, "player_id", out var playerId) ||
            playerId != client.PlayerId)
        {
            Console.WriteLine($"Invalid heal identity or medkit from {client.LogId}: {message}");
            return false;
        }

        if (root.TryGetProperty("source", out _) &&
            (!Helper.TryGetString(root, "source", out var source) ||
             source != MedkitSource))
        {
            Console.WriteLine($"Invalid heal source from {client.PlayerId}: {message}");
            return false;
        }

        if (!TryReadCoordinates(root, message, client.PlayerId, "heal", out var x, out var y) ||
            !TryReadAim(root, message, client.PlayerId, "heal", out var angle, out var aimFrame) ||
            !Helper.TryGetNumber(root, "current_health", out var currentHealth) ||
            !double.IsFinite(currentHealth) ||
            currentHealth < 0 ||
            currentHealth > DefaultPlayerHealth ||
            !root.TryGetProperty("is_dead", out var isDeadElement) ||
            isDeadElement.ValueKind is not JsonValueKind.True and not JsonValueKind.False ||
            isDeadElement.GetBoolean())
        {
            Console.WriteLine($"Invalid heal state from {client.PlayerId}: {message}");
            return false;
        }

        string? weaponType = null;
        if (root.TryGetProperty("weapon_type", out _) ||
            root.TryGetProperty("weapon", out _))
        {
            if (!TryReadWeapon(root, message, client.PlayerId, "heal", out var parsedWeapon))
                return false;

            weaponType = parsedWeapon;
        }

        if (root.TryGetProperty("timestamp", out var timestampElement) &&
            timestampElement.ValueKind is not JsonValueKind.Number and not JsonValueKind.String)
        {
            Console.WriteLine($"Invalid heal timestamp from {client.PlayerId}: {message}");
            return false;
        }

        heal = new MedkitHealRequestData(
            medkitId,
            x,
            y,
            angle,
            aimFrame,
            currentHealth,
            weaponType);
        return true;
    }

    private static bool TryReadRespawn(
        JsonElement root,
        string message,
        string playerId,
        out double spawnX,
        out double spawnY,
        out double angle,
        out int aimFrame,
        out string weapon)
    {
        angle = default;
        aimFrame = default;
        weapon = string.Empty;

        if (!TryReadCoordinates(root, message, playerId, "respawn", out spawnX, out spawnY) ||
            !TryReadAim(root, message, playerId, "respawn", out angle, out aimFrame) ||
            !TryReadWeapon(root, message, playerId, "respawn", out weapon))
            return false;

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
        out double angle,
        out int aimFrame)
    {
        angle = default;
        aimFrame = default;

        if (!TryReadCoordinates(root, message, playerId, "move", out x, out y))
            return false;

        return TryReadAim(root, message, playerId, "move", out angle, out aimFrame);
    }

    private static bool TryReadPlayerState(
        JsonElement root,
        string message,
        string playerId,
        string messageType,
        out double x,
        out double y,
        out double angle,
        out int aimFrame,
        out string weapon)
    {
        angle = default;
        aimFrame = default;
        weapon = string.Empty;

        if (!TryReadCoordinates(root, message, playerId, messageType, out x, out y))
            return false;

        if (!TryReadAim(root, message, playerId, messageType, out angle, out aimFrame))
            return false;

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

        if (!Helper.TryGetString(root, "player_id", out playerId))
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

        if (!Helper.TryGetString(root, "player_name", out playerName))
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

    private static bool TryReadLeaveMatch(
        JsonElement root,
        string message,
        ClientConnection client,
        out string roomId)
    {
        roomId = string.Empty;

        if (!client.HasPlayerId || !client.HasRoom)
        {
            Console.WriteLine($"leave_match before on_connect from {client.LogId}: {message}");
            return false;
        }

        if (!Helper.TryGetString(root, "player_id", out var playerId) ||
            playerId.Length > MaxPlayerIdLength ||
            playerId != client.PlayerId)
        {
            Console.WriteLine($"Invalid leave_match player id from {client.LogId}: {message}");
            return false;
        }

        if (!TryReadRoomId(root, out roomId) ||
            roomId != client.RoomId)
        {
            Console.WriteLine($"Invalid leave_match room id from {client.LogId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadLeaderboardRequest(
        JsonElement root,
        string message,
        ClientConnection client,
        out string roomId)
    {
        roomId = string.Empty;

        if (!client.HasPlayerId || !client.HasRoom)
        {
            Console.WriteLine($"leaderboard_request before on_connect from {client.LogId}: {message}");
            return false;
        }

        if (!Helper.TryGetString(root, "player_id", out var playerId) ||
            playerId.Length > MaxPlayerIdLength ||
            playerId != client.PlayerId)
        {
            Console.WriteLine($"Invalid leaderboard_request player id from {client.LogId}: {message}");
            return false;
        }

        if (!TryReadRoomId(root, out roomId) ||
            roomId != client.RoomId)
        {
            Console.WriteLine($"Invalid leaderboard_request room id from {client.LogId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadRoomId(JsonElement root, out string roomId) =>
        Helper.TryGetString(root, "room_id", out roomId);

    private static bool ValidateOptionalSessionFields(
        JsonElement root,
        string message,
        ClientConnection client)
    {
        if (root.TryGetProperty("player_id", out _) &&
            (!Helper.TryGetString(root, "player_id", out var playerId) ||
             playerId != client.PlayerId))
        {
            Console.WriteLine($"Rejected mismatched player identity from {client.LogId}: {message}");
            return false;
        }

        if (root.TryGetProperty("room_id", out _) &&
            (!TryReadRoomId(root, out var roomId) ||
             !client.HasRoom ||
             roomId != client.RoomId))
        {
            Console.WriteLine($"Rejected mismatched room identity from {client.LogId}: {message}");
            return false;
        }

        if (root.TryGetProperty("player_name", out _) &&
            (!Helper.TryGetString(root, "player_name", out var playerName) ||
             playerName != client.PlayerName))
        {
            Console.WriteLine($"Rejected mismatched player name from {client.LogId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadMessageKind(JsonElement root, out string type) =>
        Helper.TryGetString(root, "type", out type) ||
        Helper.TryGetString(root, "request", out type);

    private static bool TryReadChatMessage(
        JsonElement root,
        string message,
        ClientConnection client,
        out ChatMessage chat)
    {
        chat = default;

        if (!Helper.TryGetString(root, "player_id", out var playerId) ||
            playerId.Length > MaxPlayerIdLength ||
            playerId != client.PlayerId)
        {
            Console.WriteLine($"Invalid chat player id from {client.LogId}: {message}");
            return false;
        }

        if (TryReadRoomId(root, out var roomId) && roomId != client.RoomId)
        {
            Console.WriteLine($"Invalid chat room id from {client.LogId}: {message}");
            return false;
        }

        if (!Helper.TryGetString(root, "content", out var content))
        {
            Console.WriteLine($"Invalid chat content from {client.LogId}: {message}");
            return false;
        }

        if (content.Length > MaxChatContentLength)
        {
            Console.WriteLine($"Chat content too long from {client.LogId}: {message}");
            return false;
        }

        object? timestamp = null;
        if (root.TryGetProperty("timestamp", out var timestampElement))
        {
            if (timestampElement.ValueKind == JsonValueKind.Number)
            {
                if (timestampElement.TryGetInt64(out var longTimestamp))
                    timestamp = longTimestamp;
                else if (timestampElement.TryGetDouble(out var doubleTimestamp))
                    timestamp = doubleTimestamp;
                else
                {
                    Console.WriteLine($"Invalid chat timestamp from {client.LogId}: {message}");
                    return false;
                }
            }
            else if (timestampElement.ValueKind == JsonValueKind.String)
            {
                timestamp = timestampElement.GetString();
            }
            else
            {
                Console.WriteLine($"Invalid chat timestamp from {client.LogId}: {message}");
                return false;
            }
        }

        chat = new ChatMessage(client.PlayerId, client.PlayerName, content, timestamp);
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

        if (!Helper.TryGetString(root, "target_player_id", out var targetPlayerId))
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
        if (root.TryGetProperty("shot_id", out var shotIdElement))
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
        if (!Helper.TryGetString(root, "weapon_type", out weapon) &&
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

        if (!AcceptedWeaponTypes.TryGetValue(weapon, out var canonicalWeapon))
        {
            Console.WriteLine($"Unsupported {messageType} weapon from {playerId}: {message}");
            return false;
        }

        weapon = canonicalWeapon;
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
            !double.IsFinite(angle) ||
            angle < MinAimAngleDegrees ||
            angle >= MaxAimAngleDegrees)
        {
            Console.WriteLine($"Invalid shoot angle from {playerId}: {message}");
            return false;
        }

        string? weaponType = null;
        if (root.TryGetProperty("weapon_type", out _) || root.TryGetProperty("weapon", out _))
        {
            if (!TryReadWeapon(root, message, playerId, "shoot", out var weapon))
                return false;

            weaponType = weapon;
        }

        if (!TryReadOptionalNumber(root, "x", message, playerId, "shoot", out var x) ||
            !TryReadOptionalNumber(root, "y", message, playerId, "shoot", out var y) ||
            !TryReadOptionalNumber(root, "start_x", message, playerId, "shoot", out var startX) ||
            !TryReadOptionalNumber(root, "start_y", message, playerId, "shoot", out var startY) ||
            !TryReadOptionalNumber(root, "target_x", message, playerId, "shoot", out var targetX) ||
            !TryReadOptionalNumber(root, "target_y", message, playerId, "shoot", out var targetY))
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
        out double angle,
        out int aimFrame)
    {
        return TryReadAim(root, message, playerId, "angle", out angle, out aimFrame);
    }

    private static bool TryReadIdle(
        JsonElement root,
        string message,
        string playerId,
        out double x,
        out double y,
        out double angle,
        out int aimFrame)
    {
        angle = default;
        aimFrame = default;

        if (!TryReadCoordinates(root, message, playerId, "idle", out x, out y))
            return false;

        return TryReadAim(root, message, playerId, "idle", out angle, out aimFrame);
    }

    private static bool TryReadAim(
        JsonElement root,
        string message,
        string playerId,
        string messageType,
        out double angle,
        out int aimFrame)
    {
        angle = default;
        aimFrame = default;

        if (!Helper.TryGetNumber(root, "angle", out angle) ||
            !double.IsFinite(angle) ||
            !TryReadInt(root, "aim_frame", out aimFrame) ||
            aimFrame < 0 ||
            aimFrame > 7 ||
            angle != aimFrame * 45.0)
        {
            Console.WriteLine($"Invalid {messageType} aim from {playerId}: {message}");
            return false;
        }

        return true;
    }

    private static bool PositionsWithin(
        double firstX,
        double firstY,
        double secondX,
        double secondY,
        double maximumDistance)
    {
        var deltaX = firstX - secondX;
        var deltaY = firstY - secondY;
        return deltaX * deltaX + deltaY * deltaY <= maximumDistance * maximumDistance;
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
        List<Task>? sendTasks = null;
        byte[]? bytes = null;

        // Snapshot room members, then send only to clients still assigned to this room.
        foreach (var playerId in room.PlayerIdsSnapshot())
        {
            if (clients.TryGetValue(playerId, out var client) &&
                client.RoomId == room.RoomId &&
                client.HasJoinedGame)
            {
                // Encode lazily so an empty room costs no JSON work.
                bytes ??= JsonSerializer.SerializeToUtf8Bytes(payload);
                sendTasks ??= new List<Task>();
                sendTasks.Add(SendBytesAsync(client, bytes));
            }
        }

        if (sendTasks is not null)
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
    private readonly Dictionary<string, MedkitState> medkits = new(StringComparer.Ordinal);

    private GameRoom(string roomId)
    {
        RoomId = roomId;
        MatchId = Guid.NewGuid();
    }

    public string RoomId { get; }
    public Guid MatchId { get; }
    public int MaxPlayers { get; } = 8;
    public DateTime? StartTimeUtc { get; private set; }
    public DateTime? EndTimeUtc { get; private set; }
    public DateTime? EndedAtUtc { get; private set; }
    public int DurationSeconds { get; } = 300;
    public GameRoomState State { get; private set; } = GameRoomState.Waiting;
    public IReadOnlyCollection<string> Players => playerIds.Keys.ToArray();

    // Calculated from the authoritative server end time once the first player joins.
    public int RemainingSeconds =>
        EndTimeUtc is null
            ? DurationSeconds
            : Math.Max(0, (int)Math.Ceiling((EndTimeUtc.Value - DateTime.UtcNow).TotalSeconds));

    public bool HasExpired => State == GameRoomState.Running && RemainingSeconds <= 0;

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
            if (State == GameRoomState.Ended || HasExpired || playerIds.Count >= MaxPlayers)
                return false;

            // Empty running rooms are retained only for players reconnecting to that match.
            if (State == GameRoomState.Running &&
                playerIds.IsEmpty &&
                !leaderboard.ContainsKey(playerId))
            {
                return false;
            }

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

    public void RemovePlayer(string playerId, bool removeLeaderboardEntry = false)
    {
        lock (syncRoot)
        {
            playerIds.TryRemove(playerId, out _);
            joinedPlayerIds.TryRemove(playerId, out _);

            // Running match scores survive refreshes and websocket drops, but an explicit
            // leave_match removes the player from the visible leaderboard.
            if (State == GameRoomState.Waiting || removeLeaderboardEntry)
                leaderboard.TryRemove(playerId, out _);
        }
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

    public MedkitState SpawnMedkit(string ownerPlayerId, double x, double y)
    {
        lock (syncRoot)
        {
            var medkit = new MedkitState(
                $"medkit-{Guid.NewGuid():N}",
                ownerPlayerId,
                x,
                y);
            medkits[medkit.MedkitId] = medkit;
            return medkit;
        }
    }

    public MedkitState[] MedkitsSnapshot()
    {
        lock (syncRoot)
        {
            return medkits.Values.ToArray();
        }
    }

    public bool TryConsumeMedkit(
        string medkitId,
        double playerX,
        double playerY,
        double maximumDistance,
        out MedkitState medkit)
    {
        lock (syncRoot)
        {
            if (!medkits.TryGetValue(medkitId, out medkit))
                return false;

            var deltaX = medkit.X - playerX;
            var deltaY = medkit.Y - playerY;
            if (deltaX * deltaX + deltaY * deltaY > maximumDistance * maximumDistance)
                return false;

            medkits.Remove(medkitId);
            return true;
        }
    }

    public void RestoreMedkit(MedkitState medkit)
    {
        lock (syncRoot)
        {
            medkits.TryAdd(medkit.MedkitId, medkit);
        }
    }

    public MedkitState[] RemoveMedkitsForOwner(string ownerPlayerId)
    {
        lock (syncRoot)
        {
            var ownedMedkits = medkits.Values
                .Where(medkit => medkit.OwnerPlayerId == ownerPlayerId)
                .ToArray();

            foreach (var medkit in ownedMedkits)
                medkits.Remove(medkit.MedkitId);

            return ownedMedkits;
        }
    }

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

    public void RecordDeath(string targetPlayerId)
    {
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
            EndedAtUtc = DateTime.UtcNow;
            return true;
        }
    }

    public MatchRecord MatchRecordSnapshot()
    {
        lock (syncRoot)
        {
            if (StartTimeUtc is null || EndedAtUtc is null)
            {
                throw new InvalidOperationException(
                    "Only ended matches can be persisted."
                );
            }

            var durationSeconds = Math.Max(
                0,
                (int)Math.Round(
                    (EndedAtUtc.Value - StartTimeUtc.Value).TotalSeconds
                )
            );

            return new MatchRecord(
                MatchId,
                new DateTimeOffset(StartTimeUtc.Value, TimeSpan.Zero),
                new DateTimeOffset(EndedAtUtc.Value, TimeSpan.Zero),
                durationSeconds
            );
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

public readonly record struct MedkitHealRequestData(
    string MedkitId,
    double X,
    double Y,
    double Angle,
    int AimFrame,
    double CurrentHealth,
    string? WeaponType);

public readonly record struct MedkitState(
    string MedkitId,
    string OwnerPlayerId,
    double X,
    double Y);

public readonly record struct ShootRequest(
    string? WeaponType,
    double Angle,
    double? X,
    double? Y,
    double? StartX,
    double? StartY,
    double? TargetX,
    double? TargetY);

public readonly record struct ChatMessage(
    string PlayerId,
    string PlayerName,
    string Content,
    object? Timestamp)
{
    public Dictionary<string, object> ToPayload(string roomId)
    {
        var payload = new Dictionary<string, object>
        {
            ["request"] = "message",
            ["type"] = "chat_message",
            ["player_id"] = PlayerId,
            ["player_name"] = PlayerName,
            ["content"] = Content,
            ["room_id"] = roomId
        };

        if (Timestamp is not null)
            payload["timestamp"] = Timestamp;

        return payload;
    }
}

public readonly record struct ShotTargetKey(string ShotId, string TargetPlayerId);

public readonly record struct HealthSnapshot(double Health, bool IsDead);

public readonly record struct RespawnResult(
    double Health,
    bool IsDead,
    double X,
    double Y,
    double Angle,
    int AimFrame,
    string Weapon);

public readonly record struct DamageResult(double Health, double Damage, bool IsDead);

public readonly record struct DeathResult(
    double Health,
    double Damage,
    bool BecameDead);

public readonly record struct HealResult(double Health, double Heal, double PreviousHealth, bool IsDead);

public readonly record struct PlayerState(
    double X,
    double Y,
    double Angle,
    int AimFrame,
    string Weapon,
    double Health,
    bool IsDead);

public readonly record struct LeaderboardEntry(
    [property: JsonPropertyName("player_id")]
    string PlayerId,
    [property: JsonPropertyName("player_name")]
    string PlayerName,
    [property: JsonPropertyName("level")]
    int Level,
    [property: JsonPropertyName("score")]
    double Score,
    [property: JsonPropertyName("kills")]
    int Kills,
    [property: JsonPropertyName("deaths")]
    int Deaths,
    [property: JsonPropertyName("damage_dealt")]
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
            Score = Score + damage,
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
    private int aimFrame;
    private string weapon = string.Empty;
    private double health = 100.0;
    private bool isDead;
    private bool deathMedkitClaimed;
    private readonly HashSet<ShotTargetKey> processedShotHits = new();

    public void Identify(string playerId, string playerName, int level)
    {
        lock (stateLock)
        {
            this.playerId = playerId;
            this.playerName = playerName;
            this.level = level;
        }
    }

    public void UpdateProfile(string playerName, int level)
    {
        lock (stateLock)
        {
            this.playerName = playerName;
            this.level = level;
        }
    }

    public void AssignRoom(string roomId)
    {
        lock (stateLock)
        {
            this.roomId = roomId;
        }
    }

    public void LeaveRoom()
    {
        lock (stateLock)
        {
            roomId = null;
            hasState = false;
            x = default;
            y = default;
            angle = default;
            aimFrame = default;
            weapon = string.Empty;
            health = 100.0;
            isDead = false;
            deathMedkitClaimed = false;
            processedShotHits.Clear();
        }
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

            state = new PlayerState(x, y, angle, aimFrame, weapon, health, isDead);
            return true;
        }
    }

    public double MarkJoined(double x, double y, double angle, int aimFrame, string weapon)
    {
        lock (stateLock)
        {
            this.x = x;
            this.y = y;
            this.angle = angle;
            this.aimFrame = aimFrame;
            this.weapon = weapon;
            health = 100.0;
            isDead = false;
            deathMedkitClaimed = false;
            hasState = true;
        }

        return health;
    }

    public void MarkMovement(double x, double y, double angle, int aimFrame)
    {
        lock (stateLock)
        {
            this.x = x;
            this.y = y;
            this.angle = angle;
            this.aimFrame = aimFrame;
        }
    }

    public void MarkAngle(double angle, int aimFrame)
    {
        lock (stateLock)
        {
            this.angle = angle;
            this.aimFrame = aimFrame;
        }
    }

    public void MarkWeaponSwitch(string weapon)
    {
        lock (stateLock)
        {
            this.weapon = weapon;
        }
    }

    public void MarkIdle(double x, double y, double angle, int aimFrame)
    {
        lock (stateLock)
        {
            this.x = x;
            this.y = y;
            this.angle = angle;
            this.aimFrame = aimFrame;
        }
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
            {
                isDead = true;
                deathMedkitClaimed = false;
            }

            return new DamageResult(health, previousHealth - health, isDead);
        }
    }

    public DeathResult ApplyDeath()
    {
        lock (stateLock)
        {
            if (!hasState || isDead)
                return new DeathResult(health, 0, false);

            var damage = health;
            health = 0;
            isDead = true;
            deathMedkitClaimed = false;

            return new DeathResult(health, damage, true);
        }
    }

    public HealResult ApplyHeal(double amount)
    {
        lock (stateLock)
        {
            if (!hasState || isDead || amount <= 0)
                return new HealResult(health, 0, health, isDead);

            var previousHealth = health;
            health = Math.Clamp(health + amount, 0, 100.0);

            return new HealResult(health, health - previousHealth, previousHealth, isDead);
        }
    }

    public bool TryClaimDeathMedkit()
    {
        lock (stateLock)
        {
            if (!hasState || !isDead || deathMedkitClaimed)
                return false;

            deathMedkitClaimed = true;
            return true;
        }
    }

    public RespawnResult Respawn(
        double spawnX,
        double spawnY,
        double angle,
        int aimFrame,
        string weapon)
    {
        lock (stateLock)
        {
            health = 100.0;
            isDead = false;
            x = spawnX;
            y = spawnY;
            this.angle = angle;
            this.aimFrame = aimFrame;
            this.weapon = weapon;
            deathMedkitClaimed = false;
            processedShotHits.Clear();

            return new RespawnResult(
                health,
                isDead,
                x,
                y,
                this.angle,
                this.aimFrame,
                this.weapon);
        }
    }
}
