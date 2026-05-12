using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text.Json;

public static class Helper
{
    // Reads a numeric JSON property without throwing on missing or invalid data.
    public static bool TryGetNumber(JsonElement root, string propertyName, out double value)
    {
        value = default;

        if (!root.TryGetProperty(propertyName, out var element) ||
            element.ValueKind != JsonValueKind.Number)
            return false;

        return element.TryGetDouble(out value);
    }

    // Reads a non-empty string JSON property without throwing on missing or invalid data.
    public static bool TryGetString(JsonElement root, string propertyName, out string value)
    {
        value = string.Empty;

        if (!root.TryGetProperty(propertyName, out var element) ||
            element.ValueKind != JsonValueKind.String)
            return false;

        var text = element.GetString();
        if (string.IsNullOrWhiteSpace(text))
            return false;

        value = text.Trim();
        return true;
    }

    // TODO:: get the real player ID by username from the dashboard
    public static string GetPlayerId() =>
        Guid.NewGuid().ToString("N");
    
    public static ClientConnection AcceptPlayer(string playerId, WebSocket clientSocket, string roomId)
    {
        return new ClientConnection(
            playerId,
            clientSocket,
            roomId
        );
    }
    
    public static void RemovePlayer(ConcurrentDictionary<string, ClientConnection> players, string playerId) =>
        players.TryRemove(playerId, out _);
}
