using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Threading.Channels;

internal sealed class FakeWebSocket : WebSocket
{
    private readonly Channel<IncomingFrame> incoming =
        Channel.CreateUnbounded<IncomingFrame>();
    private readonly Channel<string> outgoing = Channel.CreateUnbounded<string>();
    private readonly ConcurrentQueue<string> sentMessages = new();
    private WebSocketState state = WebSocketState.Open;
    private WebSocketCloseStatus? closeStatus;
    private string? closeStatusDescription;

    public override WebSocketCloseStatus? CloseStatus => closeStatus;
    public override string? CloseStatusDescription => closeStatusDescription;
    public override WebSocketState State => state;
    public override string? SubProtocol => null;

    public IReadOnlyCollection<string> SentMessages => sentMessages.ToArray();

    public void SendTextFromClient(string text) =>
        incoming.Writer.TryWrite(IncomingFrame.FromText(text));

    public void CloseFromClient()
    {
        incoming.Writer.TryWrite(IncomingFrame.Close());
    }

    public void DisconnectAbruptly()
    {
        incoming.Writer.TryWrite(
            IncomingFrame.Failure(new WebSocketException("Connection reset"))
        );
    }

    public async Task<string> WaitForMessageAsync(
        Func<string, bool> predicate,
        TimeSpan? timeout = null
    )
    {
        using var cancellation = new CancellationTokenSource(
            timeout ?? TimeSpan.FromSeconds(3)
        );

        while (await outgoing.Reader.WaitToReadAsync(cancellation.Token))
        {
            while (outgoing.Reader.TryRead(out var message))
            {
                if (predicate(message))
                    return message;
            }
        }

        throw new InvalidOperationException("Expected WebSocket message was not sent.");
    }

    public override void Abort()
    {
        state = WebSocketState.Aborted;
        incoming.Writer.TryWrite(
            IncomingFrame.Failure(new WebSocketException("Socket aborted"))
        );
    }

    public override Task CloseAsync(
        WebSocketCloseStatus closeStatus,
        string? statusDescription,
        CancellationToken cancellationToken
    )
    {
        this.closeStatus ??= closeStatus;
        closeStatusDescription ??= statusDescription;
        state = WebSocketState.Closed;
        incoming.Writer.TryWrite(IncomingFrame.Close());
        return Task.CompletedTask;
    }

    public override Task CloseOutputAsync(
        WebSocketCloseStatus closeStatus,
        string? statusDescription,
        CancellationToken cancellationToken
    ) =>
        CloseAsync(closeStatus, statusDescription, cancellationToken);

    public override void Dispose()
    {
        if (state != WebSocketState.Aborted)
            state = WebSocketState.Closed;
    }

    public override async Task<WebSocketReceiveResult> ReceiveAsync(
        ArraySegment<byte> buffer,
        CancellationToken cancellationToken
    )
    {
        var frame = await incoming.Reader.ReadAsync(cancellationToken);

        if (frame.Exception is not null)
        {
            state = WebSocketState.Aborted;
            throw frame.Exception;
        }

        if (frame.MessageType == WebSocketMessageType.Close)
        {
            if (state == WebSocketState.Open)
                state = WebSocketState.CloseReceived;
            return new WebSocketReceiveResult(
                0,
                WebSocketMessageType.Close,
                true,
                WebSocketCloseStatus.NormalClosure,
                "Client closed"
            );
        }

        var bytes = Encoding.UTF8.GetBytes(frame.Text!);
        Array.Copy(bytes, 0, buffer.Array!, buffer.Offset, bytes.Length);

        return new WebSocketReceiveResult(
            bytes.Length,
            WebSocketMessageType.Text,
            true
        );
    }

    public override Task SendAsync(
        ArraySegment<byte> buffer,
        WebSocketMessageType messageType,
        bool endOfMessage,
        CancellationToken cancellationToken
    )
    {
        if (state != WebSocketState.Open)
            throw new WebSocketException("Socket is not open");

        var message = Encoding.UTF8.GetString(
            buffer.Array!,
            buffer.Offset,
            buffer.Count
        );
        sentMessages.Enqueue(message);
        outgoing.Writer.TryWrite(message);
        return Task.CompletedTask;
    }

    private sealed record IncomingFrame(
        string? Text,
        WebSocketMessageType MessageType,
        Exception? Exception
    )
    {
        public static IncomingFrame FromText(string text) =>
            new(text, WebSocketMessageType.Text, null);

        public static IncomingFrame Close() =>
            new(null, WebSocketMessageType.Close, null);

        public static IncomingFrame Failure(Exception exception) =>
            new(null, WebSocketMessageType.Close, exception);
    }
}
