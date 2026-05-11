using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text.Json;
using System.Text;

public sealed class Ws
{
    private static readonly TimeSpan HeartbeatTimeout = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan HeartbeatCheckInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan IdleTimeout = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan TimeSyncInterval = TimeSpan.FromSeconds(5);
    private const double MinAimAngleDegrees = 0.0;
    private const double MaxAimAngleDegrees = 360.0;

    private readonly ConcurrentDictionary<string, ClientConnection> clients;

    // Active match rooms keyed by room id. Rooms are removed when empty or ended.
    private readonly ConcurrentDictionary<string, GameRoom> rooms = new();

    public Ws(ConcurrentDictionary<string, ClientConnection> clients)
    {
        this.clients = clients;
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
        var playerId = Helper.GetPlayerId();

        // Put this new player into an existing running room, or create one.
        var room = AssignRoom(playerId);
        var client = Helper.AcceptPlayer(playerId, socket, room.RoomId);

        clients[playerId] = client;
        Console.WriteLine($"Client connected: {playerId}");

        // Tell the client which room it joined and how much match time is left.
        await SendJsonAsync(client, new
        {
            type = "room_joined",
            playerId,
            roomId = room.RoomId,
            durationSeconds = room.DurationSeconds,
            remainingSeconds = room.RemainingSeconds
        });

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
            Console.WriteLine($"Client disconnected unexpectedly: {playerId}");
        }
        finally
        {
            // Remove the disconnected socket from global and room-level state.
            connectionLifetime.Cancel();
            Helper.RemovePlayer(clients, playerId);
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
                Console.WriteLine($"Close skipped for {playerId}: {ex.Message}");
            }

            socket.Dispose();
            Console.WriteLine($"Client disconnected: {playerId}");

            if (disconnectedRoom is not null)
            {
                // Only players in the same room should see this player leave.
                await BroadcastToRoomAsync(disconnectedRoom, new
                {
                    type = "player_left",
                    playerId
                });
            }
        }
    }

    private GameRoom AssignRoom(string playerId)
    {
        // First try to join any running room that still has capacity.
        foreach (var room in rooms.Values)
        {
            if (room.TryAddPlayer(playerId))
                return room;
        }

        // No available room exists, so create a fresh 10-minute match room.
        while (true)
        {
            var room = GameRoom.Create();

            if (!room.TryAddPlayer(playerId))
                continue;

            if (rooms.TryAdd(room.RoomId, room))
                return room;
        }
    }

    private GameRoom? RemovePlayerFromRoom(ClientConnection client)
    {
        if (!rooms.TryGetValue(client.RoomId, out var room))
            return null;

        room.RemovePlayer(client.PlayerId);

        // Empty rooms are no longer useful and should not receive timer ticks.
        if (room.IsEmpty)
        {
            rooms.TryRemove(room.RoomId, out _);
            return null;
        }

        return room;
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
                if (room.State == GameRoomState.Ended)
                    continue;

                var remainingSeconds = room.RemainingSeconds;

                if (remainingSeconds <= 0)
                {
                    // Time is up: end the match once and clean up its sockets.
                    await EndRoomAsync(room);
                    continue;
                }

                // Do not spam every second; clients receive periodic corrections.
                var remainingTime = TimeSpan.FromSeconds(remainingSeconds);
                Console.WriteLine($"Time sync for room {room.RoomId}: {remainingTime.Minutes:D2}:{remainingTime.Seconds:D2} remaining");

                await BroadcastToRoomAsync(room, new
                {
                    type = "time_sync",
                    roomId = room.RoomId,
                    remainingSeconds
                });
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
            reason = "time_limit"
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

            if (inactiveDuration < HeartbeatTimeout)
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
            Console.WriteLine($"Invalid JSON from {client.PlayerId}: {message}");
            return;
        }

        using (document)
        {
            var root = document.RootElement;

            if (!root.TryGetProperty("type", out var typeElement) ||
                typeElement.ValueKind != JsonValueKind.String)
            {
                Console.WriteLine($"Message missing type from {client.PlayerId}: {message}");
                return;
            }

            var type = typeElement.GetString();
            if (type == "move")
            {
                if (!TryReadMove(root, message, client.PlayerId, out var x, out var y, out var angle))
                    return;

                client.MarkMovement(x, y, angle);
                Console.WriteLine($"Move from {client.PlayerId}: x={x}, y={y}, angle={angle}");

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

            if (type == "angle")
            {
                if (!TryReadAngle(root, message, client.PlayerId, out var angle))
                    return;

                client.MarkAngle(angle);
                Console.WriteLine($"Angle from {client.PlayerId}: angle={angle}");

                await BroadcastToRoomAsync(client.RoomId, new
                {
                    type = "player_angle",
                    playerId = client.PlayerId,
                    angle
                });

                return;
            }

            if (type == "idle")
            {
                if (!TryReadIdle(root, message, client.PlayerId, out var x, out var y, out var angle))
                    return;

                client.MarkIdle(x, y, angle);
                Console.WriteLine($"Idle from {client.PlayerId}: x={x}, y={y}, angle={angle}");

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

            Console.WriteLine($"Unknown message type from {client.PlayerId}: {type}");
        }
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
            !Helper.TryGetNumber(root, "y", out y))
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
            angle < MinAimAngleDegrees ||
            angle >= MaxAimAngleDegrees)
        {
            Console.WriteLine($"Invalid move angle from {playerId}: {message}");
            return false;
        }

        return true;
    }

    private static bool TryReadAngle(
        JsonElement root,
        string message,
        string playerId,
        out double angle)
    {
        if (!Helper.TryGetNumber(root, "angle", out angle) ||
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
        // Snapshot room members, then send only to clients still assigned to this room.
        foreach (var playerId in room.PlayerIdsSnapshot())
        {
            if (clients.TryGetValue(playerId, out var client) &&
                client.RoomId == room.RoomId)
            {
                await SendJsonAsync(client, payload);
            }
        }
    }
}

public sealed class GameRoom
{
    // Protects capacity checks and state changes that must happen atomically.
    private readonly object syncRoot = new();

    // Concurrent set of player ids. The byte value is unused.
    private readonly ConcurrentDictionary<string, byte> playerIds = new();

    private GameRoom(string roomId, DateTime startTimeUtc, DateTime endTimeUtc)
    {
        RoomId = roomId;
        StartTimeUtc = startTimeUtc;
        EndTimeUtc = endTimeUtc;
    }

    public string RoomId { get; }
    public int MaxPlayers { get; } = 16;
    public DateTime StartTimeUtc { get; }
    public DateTime EndTimeUtc { get; }
    public int DurationSeconds { get; } = 600;
    public GameRoomState State { get; private set; } = GameRoomState.Running;
    public IReadOnlyCollection<string> Players => playerIds.Keys.ToArray();

    // Calculated from the authoritative server end time, never from client clocks.
    public int RemainingSeconds => Math.Max(0, (int)Math.Ceiling((EndTimeUtc - DateTime.UtcNow).TotalSeconds));
    public bool IsEmpty => playerIds.IsEmpty;

    public static GameRoom Create()
    {
        // Room lifetime starts at creation time and always lasts 600 seconds.
        var startTimeUtc = DateTime.UtcNow;
        return new GameRoom(
            Guid.NewGuid().ToString("N"),
            startTimeUtc,
            startTimeUtc.AddSeconds(600)
        );
    }

    public bool TryAddPlayer(string playerId)
    {
        lock (syncRoot)
        {
            // Do not let players join ended or full rooms.
            if (State != GameRoomState.Running || playerIds.Count >= MaxPlayers)
                return false;

            playerIds[playerId] = 0;
            return true;
        }
    }

    public void RemovePlayer(string playerId) =>
        playerIds.TryRemove(playerId, out _);

    public string[] PlayerIdsSnapshot() =>
        playerIds.Keys.ToArray();

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
    Running,
    Ended
}

public sealed record ClientConnection(string PlayerId, WebSocket Socket, string RoomId)
{
    public SemaphoreSlim SendLock { get; } = new(1, 1);
    private long lastActivityUtcTicks = DateTimeOffset.UtcNow.UtcTicks;
    private long idleSinceUtcTicks;

    public DateTimeOffset LastActivityUtc =>
        new(Interlocked.Read(ref lastActivityUtcTicks), TimeSpan.Zero);

    public bool IsIdle => Interlocked.Read(ref idleSinceUtcTicks) != 0;

    public DateTimeOffset IdleSinceUtc =>
        new(Interlocked.Read(ref idleSinceUtcTicks), TimeSpan.Zero);

    public double X { get; private set; }
    public double Y { get; private set; }
    public double Angle { get; private set; }

    public void MarkMovement(double x, double y, double angle)
    {
        X = x;
        Y = y;
        Angle = angle;
        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
        Interlocked.Exchange(ref idleSinceUtcTicks, 0);
    }

    public void MarkAngle(double angle)
    {
        Angle = angle;
        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
        Interlocked.Exchange(ref idleSinceUtcTicks, 0);
    }

    public void MarkIdle(double x, double y, double angle)
    {
        var now = DateTimeOffset.UtcNow.UtcTicks;

        X = x;
        Y = y;
        Angle = angle;
        Interlocked.Exchange(ref lastActivityUtcTicks, now);
        Interlocked.CompareExchange(ref idleSinceUtcTicks, now, 0);
    }
}
