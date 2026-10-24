namespace Reviset.Windows;

// Presentation-only, bounded comparison of stored text. It does not infer
// document deletion, recalculate cells or change the canonical report.
internal sealed record SourceDiffLine(char Prefix, string Text);
internal sealed record SourceDiffResult(IReadOnlyList<SourceDiffLine> Lines, bool Truncated, bool Coarse);
internal static class SourceDiff
{
    internal const int CharacterLimit = 16384;
    internal const int LineLimit = 300;
    internal static SourceDiffResult Build(string before, string after)
    {
        var truncated = false;
        string[] Split(string value)
        {
            if (value.Length > CharacterLimit) { var end = CharacterLimit; if (char.IsHighSurrogate(value[end - 1])) end--; value = value[..end]; truncated = true; }
            var lines = value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');
            if (lines.Length > LineLimit) { lines = lines[..LineLimit]; truncated = true; }
            return lines;
        }
        var a = Split(before); var b = Split(after); var result = new List<SourceDiffLine>();
        // The matrix is at most 301 x 301; input lines/characters are bounded.
        var table = new int[a.Length + 1, b.Length + 1];
        for (var i = a.Length - 1; i >= 0; i--) for (var j = b.Length - 1; j >= 0; j--) table[i, j] = a[i] == b[j] ? 1 + table[i + 1, j + 1] : Math.Max(table[i + 1, j], table[i, j + 1]);
        var x = 0; var y = 0;
        while (x < a.Length || y < b.Length)
        {
            if (x < a.Length && y < b.Length && a[x] == b[y]) { result.Add(new(' ', a[x])); x++; y++; }
            else if (x < a.Length && (y == b.Length || table[x + 1, y] >= table[x, y + 1])) result.Add(new('-', a[x++]));
            else result.Add(new('+', b[y++]));
        }
        return new(result, truncated, false);
    }
    internal static (int Before, int After) PreviousToSelected(int selected, int count)
    {
        if (count < 1) return (-1, -1);
        var after = Math.Clamp(selected, 0, count - 1); return (Math.Max(0, after - 1), after);
    }
}
