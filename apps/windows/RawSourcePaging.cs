using System.Text.Json;

namespace Reviset.Windows;

internal static class RawSourcePaging
{
    // All cell and before/after text fields share one UTF-16 offset selector.
    // Advance to the smallest returned continuation, never infer a fixed stride.
    public static int? Next(JsonElement value, int current)
    {
        int? next = null;
        void Visit(JsonElement item)
        {
            if (item.ValueKind == JsonValueKind.Object) foreach (var property in item.EnumerateObject())
            {
                if (property.Name == "next_offset" && property.Value.ValueKind == JsonValueKind.Number && property.Value.TryGetInt32(out var offset) && offset > current) next = next is null ? offset : Math.Min(next.Value, offset);
                else Visit(property.Value);
            }
            else if (item.ValueKind == JsonValueKind.Array) foreach (var child in item.EnumerateArray()) Visit(child);
        }
        Visit(value); return next;
    }
}
