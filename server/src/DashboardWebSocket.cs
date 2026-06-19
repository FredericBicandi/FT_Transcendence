using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

// Dashboard WebSocket hub for lobby presence and global chat.
// Receives JSON ping, presence, and global_chat messages. Sends pong, errors,
// online_count, and global_chat history/broadcasts. Be careful changing presence
// counting, chat history ordering, or send cleanup because they run across many
// sockets concurrently.
public sealed class DashboardWebSocketOptions
{
    public int MaxMessageBytes { get; init; } = 4 * 1024;
    public int MaxPlayerIdLength { get; init; } = 128;
    public int MaxPlayerNameLength { get; init; } = 64;
    public int MaxPresenceIdLength { get; init; } = 128;
    public int MaxChatContentLength { get; init; } = 140;
    public int MaxChatHistoryMessages { get; init; } = 50;
    public int RateLimitMessages { get; init; } = 5;
    public TimeSpan RateLimitWindow { get; init; } = TimeSpan.FromSeconds(10);
    public TimeSpan HeartbeatInterval { get; init; } = TimeSpan.FromSeconds(5);
    public TimeSpan HeartbeatTimeout { get; init; } = TimeSpan.FromSeconds(15);
    public TimeSpan SendTimeout { get; init; } = TimeSpan.FromSeconds(2);
    public TimeSpan CloseTimeout { get; init; } = TimeSpan.FromSeconds(2);
}

public sealed class DashboardWebSocketHub
{
    // Connections are added/removed by independent socket loops and heartbeat tasks.
    private readonly ConcurrentDictionary<string, DashboardConnection> connections =
        new();
    private readonly Queue<DashboardChatMessage> chatHistory = new();
    // Keeps chat history and broadcasts in the same order clients should display them.
    private readonly SemaphoreSlim chatOrderLock = new(1, 1);
    private readonly ILogger<DashboardWebSocketHub> logger;
    private readonly DashboardWebSocketOptions options;
    private readonly TimeProvider timeProvider;

    public DashboardWebSocketHub(
        ILogger<DashboardWebSocketHub> logger
    ) : this(
        logger,
        new DashboardWebSocketOptions(),
        TimeProvider.System
    )
    {
    }

    public DashboardWebSocketHub(
        ILogger<DashboardWebSocketHub> logger,
        DashboardWebSocketOptions options,
        TimeProvider? timeProvider = null
    )
    {
        if (options.MaxChatHistoryMessages < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(options.MaxChatHistoryMessages)
            );
        }

        this.logger = logger;
        this.options = options;
        this.timeProvider = timeProvider ?? TimeProvider.System;
    }

    public int ActiveConnectionCount =>
        connections.Values.Count(connection =>
            connection.Socket.State == WebSocketState.Open
        );

    public int ActivePresenceCount => GetOnlineCount();

    public async Task RunWebSocketApp(HttpContext context)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("Expected WebSocket request");
            return;
        }

        var presenceId = ReadPresenceIdFromQuery(context);

        if (presenceId is null)
        {
            logger.LogWarning(
                "Rejected dashboard socket without session_id: remoteIp={RemoteIp}; forwardedFor={ForwardedFor}; realIp={RealIp}; userAgent={UserAgent}",
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                context.Request.Headers["X-Forwarded-For"].ToString(),
                context.Request.Headers["X-Real-IP"].ToString(),
                context.Request.Headers.UserAgent.ToString()
            );
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("Missing dashboard session_id");
            return;
        }

        var metadata = new DashboardConnectionMetadata(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            context.Request.Headers["X-Forwarded-For"].ToString(),
            context.Request.Headers["X-Real-IP"].ToString(),
            context.Request.Headers.UserAgent.ToString(),
            presenceId
        );
        var socket = await context.WebSockets.AcceptWebSocketAsync();
        await RunConnectionAsync(
            socket,
            context.RequestAborted,
            presenceId,
            metadata
        );
    }

    public async Task RunConnectionAsync(
        WebSocket socket,
        CancellationToken cancellationToken = default,
        string? presenceId = null,
        DashboardConnectionMetadata? metadata = null
    )
    {
        var connection = new DashboardConnection(
            Helper.GetConnectionId(),
            socket,
            options,
            timeProvider,
            metadata ?? DashboardConnectionMetadata.Empty
        );
        if (presenceId is not null)
            connection.SetPresenceId(presenceId);

        await chatOrderLock.WaitAsync(cancellationToken);
        try
        {
            if (!connections.TryAdd(connection.ConnectionId, connection))
            {
                socket.Abort();
                socket.Dispose();
                return;
            }

            // New dashboard clients receive retained chat before online_count updates
            // so the UI can hydrate history before live messages arrive.
            foreach (var message in chatHistory)
                await SendJsonAsync(connection, message);
        }
        finally
        {
            chatOrderLock.Release();
        }

        using var connectionLifetime =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var heartbeatTask = MonitorHeartbeatAsync(
            connection,
            connectionLifetime.Token
        );

        await BroadcastOnlineCountAsync();
        logger.LogInformation(
            "Dashboard socket connected: {ConnectionId}; session={SessionId}; remoteIp={RemoteIp}; forwardedFor={ForwardedFor}; realIp={RealIp}; userAgent={UserAgent}; online={OnlineCount}",
            connection.ConnectionId,
            connection.SessionIdForLog,
            connection.Metadata.RemoteIp,
            connection.Metadata.ForwardedFor,
            connection.Metadata.RealIp,
            connection.Metadata.UserAgent,
            GetOnlineCount()
        );

        try
        {
            while (socket.State == WebSocketState.Open)
            {
                var received = await ReceiveMessageAsync(
                    socket,
                    connectionLifetime.Token
                );

                if (received.IsClosed)
                    break;

                if (received.ErrorCode is not null)
                {
                    await SendErrorAsync(
                        connection,
                        received.ErrorCode,
                        received.ErrorMessage!
                    );
                    continue;
                }

                connection.MarkActivity();
                await HandleMessageAsync(connection, received.Text!);
            }
        }
        catch (Exception ex) when (IsExpectedDisconnect(ex))
        {
            logger.LogInformation(
                "Dashboard socket disconnected unexpectedly: {ConnectionId}; session={SessionId}; remoteIp={RemoteIp}; forwardedFor={ForwardedFor}; realIp={RealIp}; userAgent={UserAgent}",
                connection.ConnectionId,
                connection.SessionIdForLog,
                connection.Metadata.RemoteIp,
                connection.Metadata.ForwardedFor,
                connection.Metadata.RealIp,
                connection.Metadata.UserAgent
            );
        }
        catch (Exception ex)
        {
            logger.LogError(
                ex,
                "Unexpected dashboard socket failure: {ConnectionId}",
                connection.ConnectionId
            );
            await SendErrorAsync(
                connection,
                "INTERNAL_ERROR",
                "The message could not be processed."
            );
        }
        finally
        {
            connectionLifetime.Cancel();
            RemoveConnection(connection);

            try
            {
                await heartbeatTask;
            }
            catch (Exception ex) when (IsExpectedDisconnect(ex))
            {
            }

            await CloseSocketAsync(
                connection,
                WebSocketCloseStatus.NormalClosure,
                "Closing"
            );
            socket.Dispose();

            logger.LogInformation(
                "Dashboard socket disconnected: {ConnectionId}; session={SessionId}; remoteIp={RemoteIp}; forwardedFor={ForwardedFor}; realIp={RealIp}; userAgent={UserAgent}; online={OnlineCount}",
                connection.ConnectionId,
                connection.SessionIdForLog,
                connection.Metadata.RemoteIp,
                connection.Metadata.ForwardedFor,
                connection.Metadata.RealIp,
                connection.Metadata.UserAgent,
                GetOnlineCount()
            );
            await BroadcastOnlineCountAsync();
        }
    }

    private async Task HandleMessageAsync(
        DashboardConnection connection,
        string message
    )
    {
        JsonDocument document;

        try
        {
            document = JsonDocument.Parse(message);
        }
        catch (JsonException)
        {
            await SendErrorAsync(
                connection,
                "INVALID_JSON",
                "The message must be valid JSON."
            );
            return;
        }

        using (document)
        {
            var root = document.RootElement;

            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("type", out var typeElement) ||
                typeElement.ValueKind != JsonValueKind.String)
            {
                await SendErrorAsync(
                    connection,
                    "INVALID_MESSAGE",
                    "The message must include a string type."
                );
                return;
            }

            var type = typeElement.GetString();

            if (type == "pong")
                return;

            if (type == "ping")
            {
                await SendJsonAsync(connection, new { type = "pong" });
                return;
            }

            if (type == "presence")
            {
                await HandlePresenceAsync(connection, root);
                return;
            }

            if (type != "global_chat")
            {
                await SendErrorAsync(
                    connection,
                    "UNSUPPORTED_MESSAGE_TYPE",
                    "The message type is not supported."
                );
                return;
            }

            await HandleGlobalChatAsync(connection, root);
        }
    }

    private async Task HandlePresenceAsync(
        DashboardConnection connection,
        JsonElement root
    )
    {
        var presenceId = ReadChatField(
            root,
            "session_id",
            options.MaxPresenceIdLength
        );

        if (!presenceId.IsValid)
        {
            await SendErrorAsync(
                connection,
                "INVALID_SESSION_ID",
                presenceId.Error!
            );
            return;
        }

        if (connection.SetPresenceId(presenceId.Value!))
        {
            logger.LogInformation(
                "Dashboard presence updated: {ConnectionId}; session={SessionId}; remoteIp={RemoteIp}; forwardedFor={ForwardedFor}; realIp={RealIp}; userAgent={UserAgent}",
                connection.ConnectionId,
                connection.SessionIdForLog,
                connection.Metadata.RemoteIp,
                connection.Metadata.ForwardedFor,
                connection.Metadata.RealIp,
                connection.Metadata.UserAgent
            );
            await BroadcastOnlineCountAsync();
        }
    }

    private async Task HandleGlobalChatAsync(
        DashboardConnection connection,
        JsonElement root
    )
    {
        var playerId = ReadChatField(
            root,
            "player_id",
            options.MaxPlayerIdLength
        );
        if (!playerId.IsValid)
        {
            await SendErrorAsync(connection, "INVALID_PLAYER_ID", playerId.Error!);
            return;
        }

        var playerName = ReadChatField(
            root,
            "player_name",
            options.MaxPlayerNameLength
        );
        if (!playerName.IsValid)
        {
            await SendErrorAsync(
                connection,
                "INVALID_PLAYER_NAME",
                playerName.Error!
            );
            return;
        }

        var content = ReadChatField(
            root,
            "content",
            options.MaxChatContentLength
        );
        if (!content.IsValid)
        {
            await SendErrorAsync(connection, "INVALID_CONTENT", content.Error!);
            return;
        }

        if (!connection.TryConsumeChatAllowance(out var retryAfter))
        {
            await SendErrorAsync(
                connection,
                "RATE_LIMITED",
                "Too many messages. Please wait before sending again.",
                (int)Math.Ceiling(retryAfter.TotalSeconds)
            );
            return;
        }

        await chatOrderLock.WaitAsync();
        try
        {
            // The server assigns message_id/sent_at after validation so clients cannot
            // spoof ordering metadata or replay someone else's message id.
            var payload = new DashboardChatMessage(
                type: "global_chat",
                message_id: Guid.NewGuid().ToString(),
                player_id: playerId.Value!,
                player_name: playerName.Value!,
                content: content.Value!,
                sent_at: timeProvider.GetUtcNow().UtcDateTime.ToString("O")
            );

            chatHistory.Enqueue(payload);
            while (chatHistory.Count > options.MaxChatHistoryMessages)
                chatHistory.Dequeue();

            await BroadcastAsync(payload);
        }
        finally
        {
            chatOrderLock.Release();
        }
    }

    private static ChatField ReadChatField(
        JsonElement root,
        string propertyName,
        int maxLength
    )
    {
        if (!root.TryGetProperty(propertyName, out var element) ||
            element.ValueKind != JsonValueKind.String)
        {
            return ChatField.Invalid($"{propertyName} must be a string.");
        }

        var value = element.GetString()!.Trim();

        if (value.Length == 0)
            return ChatField.Invalid($"{propertyName} cannot be empty.");

        if (value.EnumerateRunes().Count() > maxLength)
        {
            return ChatField.Invalid(
                $"{propertyName} cannot exceed {maxLength} characters."
            );
        }

        return ChatField.Valid(value);
    }

    private async Task BroadcastOnlineCountAsync()
    {
        PruneClosedConnections();

        var removedDuringBroadcast = await BroadcastAsync(new
        {
            type = "online_count",
            count = GetOnlineCount()
        });

        if (removedDuringBroadcast)
        {
            PruneClosedConnections();
            await BroadcastAsync(new
            {
                type = "online_count",
                count = GetOnlineCount()
            });
        }
    }

    private int GetOnlineCount()
    {
        PruneClosedConnections();

        return connections.Values
            .Where(connection => connection.Socket.State == WebSocketState.Open)
            .Select(connection => connection.PresenceKey)
            .Distinct(StringComparer.Ordinal)
            .Count();
    }

    private async Task<bool> BroadcastAsync(object payload)
    {
        // Encode once per broadcast. Each socket still uses its own SendLock because
        // WebSocket.SendAsync does not support concurrent sends on the same instance.
        var bytes = JsonSerializer.SerializeToUtf8Bytes(payload);
        var recipients = connections.Values
            .Where(connection => connection.Socket.State == WebSocketState.Open)
            .ToArray();

        var sendResults = await Task.WhenAll(
            recipients.Select(connection => SendBytesAsync(connection, bytes))
        );

        return sendResults.Any(sent => !sent);
    }

    private Task<bool> SendJsonAsync(DashboardConnection connection, object payload) =>
        SendBytesAsync(connection, JsonSerializer.SerializeToUtf8Bytes(payload));

    private Task SendErrorAsync(
        DashboardConnection connection,
        string code,
        string message,
        int? retryAfterSeconds = null
    ) =>
        SendJsonAsync(connection, new
        {
            type = "error",
            code,
            message,
            retry_after_seconds = retryAfterSeconds
        });

    private async Task<bool> SendBytesAsync(
        DashboardConnection connection,
        byte[] bytes
    )
    {
        if (connection.Socket.State != WebSocketState.Open)
        {
            RemoveConnection(connection);
            return false;
        }

        var hasSendLock = false;

        try
        {
            if (!await connection.SendLock.WaitAsync(options.SendTimeout))
            {
                AbortSocket(connection, "send queue timeout");
                RemoveConnection(connection);
                return false;
            }

            hasSendLock = true;

            if (connection.Socket.State != WebSocketState.Open)
            {
                RemoveConnection(connection);
                return false;
            }

            using var sendTimeout = new CancellationTokenSource(options.SendTimeout);
            await connection.Socket.SendAsync(
                new ArraySegment<byte>(bytes),
                WebSocketMessageType.Text,
                true,
                sendTimeout.Token
            );
            return true;
        }
        catch (Exception ex) when (IsExpectedDisconnect(ex))
        {
            logger.LogInformation(
                "Dashboard send failed: {ConnectionId}",
                connection.ConnectionId
            );
            AbortSocket(connection, "send failure");
            RemoveConnection(connection);
            return false;
        }
        catch (Exception ex)
        {
            logger.LogError(
                ex,
                "Unexpected dashboard send failure: {ConnectionId}",
                connection.ConnectionId
            );
            AbortSocket(connection, "unexpected send failure");
            RemoveConnection(connection);
            return false;
        }
        finally
        {
            if (hasSendLock)
                connection.SendLock.Release();
        }
    }

    private void PruneClosedConnections()
    {
        foreach (var connection in connections.Values.ToArray())
        {
            if (connection.Socket.State != WebSocketState.Open)
                RemoveConnection(connection);
        }
    }

    private bool RemoveConnection(DashboardConnection connection) =>
        connections.TryRemove(
            new KeyValuePair<string, DashboardConnection>(
                connection.ConnectionId,
                connection
            )
        );

    private string? ReadPresenceIdFromQuery(HttpContext context)
    {
        if (!context.Request.Query.TryGetValue("session_id", out var values))
            return null;

        var value = values.FirstOrDefault()?.Trim();
        if (string.IsNullOrWhiteSpace(value))
            return null;

        if (value.EnumerateRunes().Count() > options.MaxPresenceIdLength)
            return null;

        return value;
    }

    private async Task MonitorHeartbeatAsync(
        DashboardConnection connection,
        CancellationToken cancellationToken
    )
    {
        using var timer = new PeriodicTimer(options.HeartbeatInterval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            if (connection.Socket.State != WebSocketState.Open)
            {
                if (RemoveConnection(connection))
                    await BroadcastOnlineCountAsync();
                return;
            }

            var inactiveDuration =
                timeProvider.GetUtcNow() - connection.LastActivityUtc;

            if (inactiveDuration >= options.HeartbeatTimeout)
            {
                logger.LogInformation(
                    "Dashboard heartbeat timeout: {ConnectionId}",
                    connection.ConnectionId
                );
                await CloseSocketAsync(
                    connection,
                    WebSocketCloseStatus.PolicyViolation,
                    "Heartbeat timeout"
                );
                return;
            }

            if (!await SendJsonAsync(connection, new { type = "ping" }))
                await BroadcastOnlineCountAsync();
        }
    }

    private async Task<DashboardReceiveResult> ReceiveMessageAsync(
        WebSocket socket,
        CancellationToken cancellationToken
    )
    {
        var buffer = new byte[1024];
        using var stream = new MemoryStream();
        WebSocketMessageType? messageType = null;

        while (true)
        {
            var result = await socket.ReceiveAsync(
                new ArraySegment<byte>(buffer),
                cancellationToken
            );

            if (result.MessageType == WebSocketMessageType.Close)
                return DashboardReceiveResult.Closed;

            messageType ??= result.MessageType;

            if (stream.Length + result.Count > options.MaxMessageBytes)
            {
                while (!result.EndOfMessage)
                {
                    result = await socket.ReceiveAsync(
                        new ArraySegment<byte>(buffer),
                        cancellationToken
                    );
                }

                return DashboardReceiveResult.Error(
                    "INVALID_MESSAGE",
                    "The message is too large."
                );
            }

            stream.Write(buffer, 0, result.Count);

            if (!result.EndOfMessage)
                continue;

            if (messageType != WebSocketMessageType.Text)
            {
                return DashboardReceiveResult.Error(
                    "INVALID_MESSAGE",
                    "Only text messages are supported."
                );
            }

            return DashboardReceiveResult.Message(
                Encoding.UTF8.GetString(stream.ToArray())
            );
        }
    }

    private async Task CloseSocketAsync(
        DashboardConnection connection,
        WebSocketCloseStatus status,
        string reason
    )
    {
        if (connection.Socket.State is not (
            WebSocketState.Open or WebSocketState.CloseReceived
        ))
        {
            return;
        }

        try
        {
            using var closeTimeout = new CancellationTokenSource(options.CloseTimeout);
            await connection.Socket.CloseAsync(
                status,
                reason,
                closeTimeout.Token
            );
        }
        catch (Exception ex) when (IsExpectedDisconnect(ex))
        {
            AbortSocket(connection, "close failure");
        }
    }

    private void AbortSocket(DashboardConnection connection, string reason)
    {
        logger.LogInformation(
            "Aborting dashboard socket {ConnectionId}: {Reason}",
            connection.ConnectionId,
            reason
        );
        connection.Socket.Abort();
    }

    private static bool IsExpectedDisconnect(Exception ex) =>
        ex is WebSocketException or
            OperationCanceledException or
            IOException or
            InvalidOperationException or
            ObjectDisposedException;
}

internal sealed class DashboardConnection
{
    // Presence and rate-limit state are updated by receive and heartbeat paths.
    private readonly object presenceLock = new();
    private readonly object rateLimitLock = new();
    private readonly Queue<DateTimeOffset> recentChatMessages = new();
    private readonly DashboardWebSocketOptions options;
    private readonly TimeProvider timeProvider;
    private long lastActivityUtcTicks;
    private string? presenceId;

    public DashboardConnection(
        string connectionId,
        WebSocket socket,
        DashboardWebSocketOptions options,
        TimeProvider timeProvider,
        DashboardConnectionMetadata metadata
    )
    {
        ConnectionId = connectionId;
        Socket = socket;
        this.options = options;
        this.timeProvider = timeProvider;
        Metadata = metadata;
        lastActivityUtcTicks = timeProvider.GetUtcNow().UtcTicks;
    }

    public string ConnectionId { get; }
    public DashboardConnectionMetadata Metadata { get; }
    public WebSocket Socket { get; }
    public SemaphoreSlim SendLock { get; } = new(1, 1);

    public string SessionIdForLog
    {
        get
        {
            lock (presenceLock)
            {
                return presenceId ?? Metadata.InitialSessionId ?? "(none)";
            }
        }
    }

    public string PresenceKey
    {
        get
        {
            lock (presenceLock)
            {
                return presenceId ?? ConnectionId;
            }
        }
    }

    public DateTimeOffset LastActivityUtc =>
        new(Interlocked.Read(ref lastActivityUtcTicks), TimeSpan.Zero);

    public void MarkActivity() =>
        Interlocked.Exchange(
            ref lastActivityUtcTicks,
            timeProvider.GetUtcNow().UtcTicks
        );

    public bool SetPresenceId(string value)
    {
        lock (presenceLock)
        {
            if (presenceId == value)
                return false;

            presenceId = value;
            return true;
        }
    }

    public bool TryConsumeChatAllowance(out TimeSpan retryAfter)
    {
        var now = timeProvider.GetUtcNow();
        var cutoff = now - options.RateLimitWindow;
        retryAfter = TimeSpan.Zero;

        lock (rateLimitLock)
        {
            while (recentChatMessages.TryPeek(out var sentAt) && sentAt <= cutoff)
                recentChatMessages.Dequeue();

            if (recentChatMessages.Count >= options.RateLimitMessages)
            {
                retryAfter = recentChatMessages.Peek() + options.RateLimitWindow - now;
                if (retryAfter < TimeSpan.Zero)
                    retryAfter = TimeSpan.Zero;
                return false;
            }

            recentChatMessages.Enqueue(now);
            return true;
        }
    }
}

public sealed record DashboardConnectionMetadata(
    string RemoteIp,
    string ForwardedFor,
    string RealIp,
    string UserAgent,
    string? InitialSessionId
)
{
    public static DashboardConnectionMetadata Empty { get; } =
        new("test", "", "", "", null);
}

internal sealed record ChatField(string? Value, string? Error)
{
    public bool IsValid => Value is not null;

    public static ChatField Valid(string value) => new(value, null);

    public static ChatField Invalid(string error) => new(null, error);
}

internal sealed record DashboardChatMessage(
    string type,
    string message_id,
    string player_id,
    string player_name,
    string content,
    string sent_at
);

internal sealed record DashboardReceiveResult(
    string? Text,
    bool IsClosed,
    string? ErrorCode,
    string? ErrorMessage
)
{
    public static DashboardReceiveResult Closed { get; } =
        new(null, true, null, null);

    public static DashboardReceiveResult Message(string text) =>
        new(text, false, null, null);

    public static DashboardReceiveResult Error(string code, string message) =>
        new(null, false, code, message);
}
