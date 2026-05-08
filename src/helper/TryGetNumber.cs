using System.Text.Json;

public static class JsonHelpers
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
}
