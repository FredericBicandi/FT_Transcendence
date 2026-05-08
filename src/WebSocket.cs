using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

public sealed class Ws
{
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
            context.Response.StatusCode = 400;
            await context.Response.WriteAsync("Expected WebSocket request");
            return;
        }

        var socket = await context.WebSockets.AcceptWebSocketAsync();
        var playerId = Guid.NewGuid().ToString("N");
        var client = new ClientConnection(playerId, socket);

        clients[playerId] = client;
        Console.WriteLine($"Client connected: {playerId}");

        try
        {
            while (socket.State == WebSocketState.Open)
            {
                var message = await ReceiveTextMessageAsync(socket, context.RequestAborted);

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
            clients.TryRemove(playerId, out _);

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
                await SendJsonAsync(client, new { type = "pong" });
                return;
            }

            if (type == "move")
            {
                if (!JsonHelpers.TryGetNumber(root, "x", out var x) ||
                    !JsonHelpers.TryGetNumber(root, "y", out var y))
                {
                    Console.WriteLine($"Invalid move from {client.PlayerId}: {message}");
                    return;
                }

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
}
