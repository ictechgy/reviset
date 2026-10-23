using System.Text.Json;

namespace Reviset.Windows;

internal static class Json
{
    public static JsonElement Get(this JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var found) ? found : default;
    public static string Text(this JsonElement value) => value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : value.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False ? value.GetRawText() : "";
    public static int Number(this JsonElement value, int fallback = 0) => value.TryNumber(out var number) ? number : fallback;
    private static bool TryNumber(this JsonElement value, out int result) { result = 0; return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out result); }
    public static bool Flag(this JsonElement value) => value.ValueKind == JsonValueKind.True;
    public static List<JsonElement> Items(this JsonElement value) => value.ValueKind == JsonValueKind.Array ? value.EnumerateArray().ToList() : [];
    public static string Pretty(this JsonElement value) => value.ValueKind == JsonValueKind.Undefined ? "" : JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true });
    public static Dictionary<string, object?> Scope(string project, string report) => new() { ["project_id"] = project, ["report_id"] = report };
}

internal sealed record Choice(string Id, string Label, JsonElement Value)
{
    public override string ToString() => Label;
    public static Choice From(JsonElement value, string key, string label) => new(value.Get(key).Text(), value.Get(label).Text(), value);
}
