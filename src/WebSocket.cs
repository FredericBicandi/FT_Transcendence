using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

public sealed class Ws
{
    private static readonly TimeSpan HeartbeatTimeout = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan HeartbeatCheckInterval = TimeSpan.FromSeconds(5);

    private readonly ConcurrentDictionary<string, ClientConnection> clients;

    public Ws(ConcurrentDictionary<string, ClientConnection> clients)
    {
        this.clients = clients;
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
        var client = Helper.AcceptPlayer(playerId, socket);

        clients[playerId] = client;
        Console.WriteLine($"Client connected: {playerId}");

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
            connectionLifetime.Cancel();
            Helper.RemovePlayer(clients, playerId);

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

            await BroadcastAsync(new
            {
                type = "player_left",
                playerId
            });
        }
    }

    // Closes stale sockets when the client stops sending movement or heartbeat pings.
    private async Task MonitorHeartbeatAsync(ClientConnection client, CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(HeartbeatCheckInterval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            if (client.Socket.State != WebSocketState.Open)
                return;

            var idleFor = DateTimeOffset.UtcNow - client.LastActivityUtc;

            if (idleFor < HeartbeatTimeout)
                continue;

            Console.WriteLine($"Heartbeat timeout for {client.PlayerId}: idle for {idleFor.TotalSeconds:F0}s");

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
            if (type == "ping")
            {
                if (!TryReadCoordinates(root, message, client.PlayerId, "ping", out var x, out var y))
                    return;

                client.MarkActivity(x, y);
                Console.WriteLine($"player {client.PlayerId} standing at : x={x}, y={y}");

                await SendJsonAsync(client, new
                {
                    type = "pong",
                    playerId = client.PlayerId,
                    x,
                    y
                });

                return;
            }

            if (type == "move")
            {
                if (!TryReadCoordinates(root, message, client.PlayerId, "move", out var x, out var y))
                    return;

                client.MarkActivity(x, y);
                Console.WriteLine($"Move from {client.PlayerId}: x={x}, y={y}");

                await BroadcastAsync(new
                {
                    type = "player_move",
                    playerId = client.PlayerId,
                    x,
                    y
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

    // Sends a payload to the clients connected at this moment.
    public async Task BroadcastAsync(object payload)
    {
        foreach (var client in clients.Values)
            await SendJsonAsync(client, payload);
    }
}

public sealed record ClientConnection(string PlayerId, WebSocket Socket)
{
    public SemaphoreSlim SendLock { get; } = new(1, 1);
    private long lastActivityUtcTicks = DateTimeOffset.UtcNow.UtcTicks;

    public DateTimeOffset LastActivityUtc =>
        new(Interlocked.Read(ref lastActivityUtcTicks), TimeSpan.Zero);

    public double X { get; private set; }
    public double Y { get; private set; }

    public void MarkActivity(double x, double y)
    {
        X = x;
        Y = y;
        Interlocked.Exchange(ref lastActivityUtcTicks, DateTimeOffset.UtcNow.UtcTicks);
    }
}
