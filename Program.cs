using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// Important: listen publicly, not only localhost
builder.WebHost.UseUrls("http://0.0.0.0:5000");

var app = builder.Build();
var clients = new ConcurrentDictionary<string, ClientConnection>();

app.UseWebSockets();

app.MapGet("/", () => "Game server running");

app.Map("/ws", async context =>
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
            var message = await ReceiveTextMessageAsync(socket);

            if (message is null)
                break;

            await HandleMessageAsync(client, message);
        }
    }
    catch (WebSocketException ex)
    {
        Console.WriteLine($"WebSocket error for {playerId}: {ex.Message}");
    }
    finally
    {
        clients.TryRemove(playerId, out _);

        if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
        {
            await socket.CloseAsync(
                WebSocketCloseStatus.NormalClosure,
                "Closing",
                CancellationToken.None
            );
        }

        socket.Dispose();

        Console.WriteLine($"Client disconnected: {playerId}");
        await BroadcastAsync(new
        {
            type = "player_left",
            playerId
        });
    }
});

app.Run();

async Task HandleMessageAsync(ClientConnection client, string message)
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
            if (!TryGetNumber(root, "x", out var x) || !TryGetNumber(root, "y", out var y))
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

async Task<string?> ReceiveTextMessageAsync(WebSocket socket)
{
    var buffer = new byte[1024 * 4];
    using var stream = new MemoryStream();

    while (true)
    {
        var result = await socket.ReceiveAsync(
            new ArraySegment<byte>(buffer),
            CancellationToken.None
        );

        if (result.MessageType == WebSocketMessageType.Close)
            return null;

        if (result.MessageType != WebSocketMessageType.Text)
            continue;

        stream.Write(buffer, 0, result.Count);

        if (result.EndOfMessage)
            return Encoding.UTF8.GetString(stream.ToArray());
    }
}

async Task BroadcastAsync(object payload)
{
    foreach (var client in clients.Values)
    {
        await SendJsonAsync(client, payload);
    }
}

async Task SendJsonAsync(ClientConnection client, object payload)
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
    catch (WebSocketException ex)
    {
        Console.WriteLine($"Send failed for {client.PlayerId}: {ex.Message}");
    }
    finally
    {
        client.SendLock.Release();
    }
}

bool TryGetNumber(JsonElement root, string propertyName, out double value)
{
    value = default;

    if (!root.TryGetProperty(propertyName, out var element) ||
        element.ValueKind != JsonValueKind.Number)
    {
        return false;
    }

    return element.TryGetDouble(out value);
}

sealed record ClientConnection(string PlayerId, WebSocket Socket)
{
    public SemaphoreSlim SendLock { get; } = new(1, 1);
}
