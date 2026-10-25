namespace Reviset.Windows;

// One version entry can contain a supplied PPTX/PDF pair. Count entries,
// independently of the number of files or the report currently being read.
internal sealed record ImportIntent(bool Workbook, int MinimumEntries)
{
    internal static ImportIntent Reading(bool workbook) => new(workbook, 1);
    internal static ImportIntent Comparison(bool workbook) => new(workbook, 2);
    internal bool Accepts(int entryCount) => MinimumEntries is 1 or 2 && entryCount >= MinimumEntries && entryCount <= 100;
}
