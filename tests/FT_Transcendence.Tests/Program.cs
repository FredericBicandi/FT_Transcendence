using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

var tests = new (string Name, Func<Task> Run)[]
{
    ("client identity and sending", ClientIdentityAndSending),
    ("multiple clients broadcast", MultipleClientsBroadcast),
    ("new clients receive the latest 50 messages", ChatHistoryReplayAndEviction),
    ("Supabase match insert", SupabaseMatchInsert),
    ("invalid JSON and malformed payloads", InvalidJsonAndMalformedPayloads),
    ("empty and oversized fields", EmptyAndOversizedFields),
    ("Arabic chat content", ArabicChatContent),
    ("rate limiting", RateLimiting),
    ("presence connect and disconnect", PresenceConnectAndDisconnect),
    ("multiple tabs count separately", MultipleTabsCountSeparately),
    ("abrupt disconnect cleanup", AbruptDisconnectCleanup),
    ("heartbeat keeps connection active", HeartbeatKeepsConnectionActive),
    ("stale connection cleanup", StaleConnectionCleanup),
    ("game websocket isolation", GameWebSocketIsolation)
};

var failed = 0;

foreach (var test in tests)
{
    try
    {
        await test.Run();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception ex)
    {
        failed += 1;
        Console.Error.WriteLine($"FAIL {test.Name}: {ex.Message}");
    }
}

return failed == 0 ? 0 : 1;

static async Task ClientIdentityAndSending()
{
    var hub = CreateHub();
    var receiver = new FakeWebSocket();
    var sender = new FakeWebSocket();
    var receiverTask = hub.RunConnectionAsync(receiver);
    var senderTask = hub.RunConnectionAsync(sender);

    await WaitForCountAsync(hub, 2);
    sender.SendTextFromClient(
        """
        {
          "type":"global_chat",
          "player_id":"  user-1  ",
          "player_name":"  Alice  ",
          "content":"  hello dashboard  "
        }
        """
    );

    using var message = await WaitForTypeAsync(receiver, "global_chat");
    AssertEqual("user-1", ReadString(message.RootElement, "player_id"));
    AssertEqual("Alice", ReadString(message.RootElement, "player_name"));
    AssertEqual("hello dashboard", ReadString(message.RootElement, "content"));
    AssertTrue(
        Guid.TryParse(ReadString(message.RootElement, "message_id"), out _),
        "message_id should be a UUID"
    );
    var sentAt = ReadString(message.RootElement, "sent_at");
    AssertTrue(
        DateTimeOffset.TryParse(sentAt, out _) && sentAt.EndsWith('Z'),
        "sent_at should be ISO-8601 UTC"
    );

    await CloseAllAsync(
        (receiver, receiverTask),
        (sender, senderTask)
    );
}

static async Task MultipleClientsBroadcast()
{
    var hub = CreateHub();
    var receiver = new FakeWebSocket();
    var sender = new FakeWebSocket();
    var receiverTask = hub.RunConnectionAsync(receiver);
    var senderTask = hub.RunConnectionAsync(sender);

    await WaitForCountAsync(hub, 2);
    sender.SendTextFromClient(
        """
        {
          "type":"global_chat",
          "player_id":"user-2",
          "player_name":"Bob",
          "content":"visible to all clients"
        }
        """
    );
    using var broadcast = await WaitForTypeAsync(receiver, "global_chat");
    AssertEqual(
        "visible to all clients",
        ReadString(broadcast.RootElement, "content")
    );

    await CloseAllAsync(
        (receiver, receiverTask),
        (sender, senderTask)
    );
}

static async Task ChatHistoryReplayAndEviction()
{
    var hub = CreateHub(new DashboardWebSocketOptions
    {
        RateLimitMessages = 100,
        RateLimitWindow = TimeSpan.FromMinutes(1),
        HeartbeatInterval = TimeSpan.FromMinutes(1),
        HeartbeatTimeout = TimeSpan.FromMinutes(2)
    });
    var sender = new FakeWebSocket();
    var senderTask = hub.RunConnectionAsync(sender);

    await WaitForCountAsync(hub, 1);

    for (var index = 1; index <= 51; index += 1)
    {
        sender.SendTextFromClient(
            ChatMessage("history-user", "Historian", $"message-{index}")
        );
    }

    await WaitForChatContentAsync(sender, "message-51");

    var newcomer = new FakeWebSocket();
    var newcomerTask = hub.RunConnectionAsync(newcomer);
    await WaitForCountAsync(hub, 2);
    await WaitForChatContentAsync(newcomer, "message-51");

    var replayedContent = ReadChatContents(newcomer);
    AssertEqual(50, replayedContent.Count);
    AssertEqual("message-2", replayedContent[0]);
    AssertEqual("message-51", replayedContent[^1]);

    await CloseAllAsync(
        (sender, senderTask),
        (newcomer, newcomerTask)
    );
}

static async Task SupabaseMatchInsert()
{
    HttpRequestMessage? capturedRequest = null;
    string? capturedBody = null;
    var handler = new StubHttpMessageHandler(async request =>
    {
        capturedRequest = request;
        capturedBody = await request.Content!.ReadAsStringAsync();
        return new HttpResponseMessage(HttpStatusCode.Created);
    });
    var configuration = new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Supabase:Url"] = "https://example.supabase.co",
            ["Supabase:PublishableKey"] = "publishable-key"
        })
        .Build();
    var repository = new SupabaseMatchRepository(
        new StubHttpClientFactory(handler),
        configuration
    );
    var match = new MatchRecord(
        Guid.Parse("11111111-2222-3333-4444-555555555555"),
        DateTimeOffset.Parse("2026-06-14T12:00:00Z"),
        DateTimeOffset.Parse("2026-06-14T12:05:00Z"),
        300
    );

    await repository.SaveAsync(match);

    AssertEqual(HttpMethod.Post, capturedRequest!.Method);
    AssertEqual(
        "https://example.supabase.co/rest/v1/matches",
        capturedRequest.RequestUri!.ToString()
    );
    AssertEqual<AuthenticationHeaderValue?>(
        null,
        capturedRequest.Headers.Authorization
    );
    AssertTrue(
        capturedRequest.Headers.TryGetValues("apikey", out var apiKeys) &&
            apiKeys.Single() == "publishable-key",
        "Supabase apikey header was missing"
    );
    AssertTrue(
        capturedRequest.Headers.TryGetValues("Prefer", out var preferences) &&
            preferences.Single() == "return=minimal",
        "Supabase return preference was missing"
    );

    using var body = JsonDocument.Parse(capturedBody!);
    AssertEqual(
        match.Id.ToString(),
        ReadString(body.RootElement, "id")
    );
    AssertEqual(
        300,
        body.RootElement.GetProperty("duration_seconds").GetInt32()
    );
    AssertTrue(
        body.RootElement.TryGetProperty("started_at", out _),
        "started_at was missing"
    );
    AssertTrue(
        body.RootElement.TryGetProperty("ended_at", out _),
        "ended_at was missing"
    );
}

static async Task InvalidJsonAndMalformedPayloads()
{
    var hub = CreateHub();
    var socket = new FakeWebSocket();
    var task = hub.RunConnectionAsync(socket);

    await WaitForCountAsync(hub, 1);

    socket.SendTextFromClient("{");
    await AssertErrorAsync(socket, "INVALID_JSON");

    socket.SendTextFromClient("""{"content":"missing type"}""");
    await AssertErrorAsync(socket, "INVALID_MESSAGE");

    socket.SendTextFromClient("""{"type":"unknown"}""");
    await AssertErrorAsync(socket, "UNSUPPORTED_MESSAGE_TYPE");

    socket.SendTextFromClient(
        """{"type":"global_chat","player_name":"Carol","content":"hello"}"""
    );
    await AssertErrorAsync(socket, "INVALID_PLAYER_ID");

    socket.SendTextFromClient(
        """{"type":"global_chat","playerId":"user-3","player_name":"Carol","content":"hello"}"""
    );
    await AssertErrorAsync(socket, "INVALID_PLAYER_ID");

    socket.SendTextFromClient(
        """{"type":"global_chat","player_id":"user-3","playerName":"Carol","content":"hello"}"""
    );
    await AssertErrorAsync(socket, "INVALID_PLAYER_NAME");

    socket.SendTextFromClient(
        """{"type":"global_chat","player_id":"user-3","player_name":"Carol","content":42}"""
    );
    await AssertErrorAsync(socket, "INVALID_CONTENT");

    await CloseAllAsync((socket, task));
}

static async Task EmptyAndOversizedFields()
{
    var hub = CreateHub();
    var socket = new FakeWebSocket();
    var task = hub.RunConnectionAsync(socket);

    await WaitForCountAsync(hub, 1);

    socket.SendTextFromClient(
        """{"type":"global_chat","player_id":" ","player_name":"Dan","content":"hello"}"""
    );
    await AssertErrorAsync(socket, "INVALID_PLAYER_ID");

    socket.SendTextFromClient(
        """{"type":"global_chat","player_id":"user-4","player_name":" ","content":"hello"}"""
    );
    await AssertErrorAsync(socket, "INVALID_PLAYER_NAME");

    socket.SendTextFromClient(
        """{"type":"global_chat","player_id":"user-4","player_name":"Dan","content":"   "}"""
    );
    await AssertErrorAsync(socket, "INVALID_CONTENT");

    socket.SendTextFromClient(
        JsonSerializer.Serialize(new
        {
            type = "global_chat",
            player_id = new string('x', 129),
            player_name = "Dan",
            content = "hello"
        })
    );
    await AssertErrorAsync(socket, "INVALID_PLAYER_ID");

    socket.SendTextFromClient(
        JsonSerializer.Serialize(new
        {
            type = "global_chat",
            player_id = "user-4",
            player_name = new string('x', 65),
            content = "hello"
        })
    );
    await AssertErrorAsync(socket, "INVALID_PLAYER_NAME");

    socket.SendTextFromClient(
        JsonSerializer.Serialize(new
        {
            type = "global_chat",
            player_id = "user-4",
            player_name = "Dan",
            content = new string('x', 141)
        })
    );
    await AssertErrorAsync(socket, "INVALID_CONTENT");

    await CloseAllAsync((socket, task));
}

static async Task RateLimiting()
{
    var hub = CreateHub(new DashboardWebSocketOptions
    {
        RateLimitMessages = 2,
        RateLimitWindow = TimeSpan.FromMinutes(1),
        HeartbeatInterval = TimeSpan.FromMinutes(1),
        HeartbeatTimeout = TimeSpan.FromMinutes(2)
    });
    var socket = new FakeWebSocket();
    var task = hub.RunConnectionAsync(socket);

    await WaitForCountAsync(hub, 1);
    socket.SendTextFromClient(ChatMessage("user-5", "Eve", "one"));
    await WaitForChatContentAsync(socket, "one");
    socket.SendTextFromClient(ChatMessage("user-5", "Eve", "two"));
    await WaitForChatContentAsync(socket, "two");
    socket.SendTextFromClient(ChatMessage("user-5", "Eve", "three"));
    await AssertErrorAsync(socket, "RATE_LIMITED");

    await CloseAllAsync((socket, task));
}

static async Task ArabicChatContent()
{
    var hub = CreateHub();
    var socket = new FakeWebSocket();
    var task = hub.RunConnectionAsync(socket);
    var content = string.Concat(Enumerable.Repeat("م", 140));

    await WaitForCountAsync(hub, 1);
    socket.SendTextFromClient(
        ChatMessage("user-ar", "لاعب", content)
    );

    using var message = await WaitForTypeAsync(socket, "global_chat");
    AssertEqual(content, ReadString(message.RootElement, "content"));
    AssertEqual("لاعب", ReadString(message.RootElement, "player_name"));

    await CloseAllAsync((socket, task));
}

static async Task PresenceConnectAndDisconnect()
{
    var hub = CreateHub();
    var first = new FakeWebSocket();
    var second = new FakeWebSocket();
    var firstTask = hub.RunConnectionAsync(first);

    await WaitForOnlineCountAsync(first, 1);

    var secondTask = hub.RunConnectionAsync(second);
    await WaitForOnlineCountAsync(first, 2);
    await WaitForOnlineCountAsync(second, 2);

    second.CloseFromClient();
    await secondTask.WaitAsync(TimeSpan.FromSeconds(3));
    await WaitForOnlineCountAsync(first, 1);

    await CloseAllAsync((first, firstTask));
}

static async Task MultipleTabsCountSeparately()
{
    var hub = CreateHub();
    var first = new FakeWebSocket();
    var second = new FakeWebSocket();
    var firstTask = hub.RunConnectionAsync(first);
    var secondTask = hub.RunConnectionAsync(second);

    await WaitForCountAsync(hub, 2);
    await WaitForOnlineCountAsync(first, 2);
    await WaitForOnlineCountAsync(second, 2);

    await CloseAllAsync((first, firstTask), (second, secondTask));
}

static async Task AbruptDisconnectCleanup()
{
    var hub = CreateHub();
    var survivor = new FakeWebSocket();
    var dropped = new FakeWebSocket();
    var survivorTask = hub.RunConnectionAsync(survivor);
    var droppedTask = hub.RunConnectionAsync(dropped);

    await WaitForCountAsync(hub, 2);
    dropped.DisconnectAbruptly();
    await droppedTask.WaitAsync(TimeSpan.FromSeconds(3));
    await WaitForCountAsync(hub, 1);
    await WaitForOnlineCountAsync(survivor, 1);

    await CloseAllAsync((survivor, survivorTask));
}

static async Task StaleConnectionCleanup()
{
    var hub = CreateHub(new DashboardWebSocketOptions
    {
        HeartbeatInterval = TimeSpan.FromMilliseconds(10),
        HeartbeatTimeout = TimeSpan.FromMilliseconds(25),
        SendTimeout = TimeSpan.FromMilliseconds(100),
        CloseTimeout = TimeSpan.FromMilliseconds(100)
    });
    var socket = new FakeWebSocket();
    var task = hub.RunConnectionAsync(socket);

    await WaitForCountAsync(hub, 1);
    await task.WaitAsync(TimeSpan.FromSeconds(3));
    AssertEqual(0, hub.ActiveConnectionCount);
    AssertEqual(
        WebSocketCloseStatus.PolicyViolation,
        socket.CloseStatus
    );
}

static async Task HeartbeatKeepsConnectionActive()
{
    var hub = CreateHub(new DashboardWebSocketOptions
    {
        HeartbeatInterval = TimeSpan.FromMilliseconds(10),
        HeartbeatTimeout = TimeSpan.FromMilliseconds(80),
        SendTimeout = TimeSpan.FromMilliseconds(100),
        CloseTimeout = TimeSpan.FromMilliseconds(100)
    });
    var socket = new FakeWebSocket();
    var task = hub.RunConnectionAsync(socket);

    await WaitForCountAsync(hub, 1);

    for (var index = 0; index < 4; index += 1)
    {
        using var ping = await WaitForTypeAsync(socket, "ping");
        socket.SendTextFromClient("""{"type":"pong"}""");
        await Task.Delay(20);
    }

    AssertEqual(1, hub.ActiveConnectionCount);
    AssertTrue(!task.IsCompleted, "Heartbeat responses should keep the socket open");

    await CloseAllAsync((socket, task));
}

static async Task GameWebSocketIsolation()
{
    var gameConnections = new ConcurrentDictionary<string, ClientConnection>();
    var dashboardHub = CreateHub();
    var socket = new FakeWebSocket();
    var task = dashboardHub.RunConnectionAsync(socket);

    await WaitForCountAsync(dashboardHub, 1);
    AssertEqual(0, gameConnections.Count);

    socket.SendTextFromClient(ChatMessage("game-user", "Player", "isolated"));
    await WaitForChatContentAsync(socket, "isolated");
    AssertEqual(0, gameConnections.Count);

    await CloseAllAsync((socket, task));
}

static DashboardWebSocketHub CreateHub(
    DashboardWebSocketOptions? options = null
) =>
    new(
        NullLogger<DashboardWebSocketHub>.Instance,
        options ?? new DashboardWebSocketOptions
        {
            HeartbeatInterval = TimeSpan.FromMinutes(1),
            HeartbeatTimeout = TimeSpan.FromMinutes(2)
        }
    );

static string ChatMessage(
    string playerId,
    string playerName,
    string content
) =>
    JsonSerializer.Serialize(new
    {
        type = "global_chat",
        player_id = playerId,
        player_name = playerName,
        content
    });

static async Task AssertErrorAsync(FakeWebSocket socket, string expectedCode)
{
    using var error = await WaitForTypeAsync(socket, "error");
    AssertEqual(expectedCode, ReadString(error.RootElement, "code"));
}

static async Task WaitForChatContentAsync(
    FakeWebSocket socket,
    string expectedContent
)
{
    using var message = JsonDocument.Parse(
        await socket.WaitForMessageAsync(message =>
        {
            using var document = JsonDocument.Parse(message);
            var root = document.RootElement;
            return root.TryGetProperty("type", out var type) &&
                type.GetString() == "global_chat" &&
                root.TryGetProperty("content", out var content) &&
                content.GetString() == expectedContent;
        })
    );
}

static IReadOnlyList<string> ReadChatContents(FakeWebSocket socket)
{
    var contents = new List<string>();

    foreach (var message in socket.SentMessages)
    {
        using var document = JsonDocument.Parse(message);
        var root = document.RootElement;

        if (root.TryGetProperty("type", out var type) &&
            type.GetString() == "global_chat")
        {
            contents.Add(ReadString(root, "content"));
        }
    }

    return contents;
}

static async Task<JsonDocument> WaitForTypeAsync(
    FakeWebSocket socket,
    string expectedType
) =>
    JsonDocument.Parse(
        await socket.WaitForMessageAsync(message =>
        {
            using var document = JsonDocument.Parse(message);
            return document.RootElement.TryGetProperty("type", out var type) &&
                type.GetString() == expectedType;
        })
    );

static async Task WaitForOnlineCountAsync(
    FakeWebSocket socket,
    int expectedCount
)
{
    using var document = JsonDocument.Parse(
        await socket.WaitForMessageAsync(message =>
        {
            using var candidate = JsonDocument.Parse(message);
            var root = candidate.RootElement;
            return root.TryGetProperty("type", out var type) &&
                type.GetString() == "online_count" &&
                root.TryGetProperty("count", out var count) &&
                count.GetInt32() == expectedCount;
        })
    );
}

static async Task WaitForCountAsync(
    DashboardWebSocketHub hub,
    int expectedCount
)
{
    var deadline = DateTimeOffset.UtcNow + TimeSpan.FromSeconds(3);

    while (DateTimeOffset.UtcNow < deadline)
    {
        if (hub.ActiveConnectionCount == expectedCount)
            return;

        await Task.Delay(10);
    }

    throw new InvalidOperationException(
        $"Expected {expectedCount} connections, got {hub.ActiveConnectionCount}."
    );
}

static async Task CloseAllAsync(
    params (FakeWebSocket Socket, Task ConnectionTask)[] connections
)
{
    foreach (var connection in connections)
        connection.Socket.CloseFromClient();

    await Task.WhenAll(
        connections.Select(connection =>
            connection.ConnectionTask.WaitAsync(TimeSpan.FromSeconds(3))
        )
    );
}

static string ReadString(JsonElement root, string propertyName) =>
    root.GetProperty(propertyName).GetString() ??
    throw new InvalidOperationException($"{propertyName} was null.");

static void AssertTrue(bool condition, string message)
{
    if (!condition)
        throw new InvalidOperationException(message);
}

static void AssertEqual<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException(
            $"Expected '{expected}', got '{actual}'."
        );
    }
}

internal sealed class StubHttpClientFactory : IHttpClientFactory
{
    private readonly HttpMessageHandler handler;

    public StubHttpClientFactory(HttpMessageHandler handler)
    {
        this.handler = handler;
    }

    public HttpClient CreateClient(string name) =>
        new(handler, disposeHandler: false);
}

internal sealed class StubHttpMessageHandler : HttpMessageHandler
{
    private readonly Func<
        HttpRequestMessage,
        Task<HttpResponseMessage>
    > handle;

    public StubHttpMessageHandler(
        Func<HttpRequestMessage, Task<HttpResponseMessage>> handle
    )
    {
        this.handle = handle;
    }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken
    ) =>
        handle(request);
}
