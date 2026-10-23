using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Reviset.Windows;

// Keep keyboard geometry and persisted preferences in one native control path.
// Dragging remains WPF GridSplitter's normal resize implementation.
internal sealed class NativeSplitter : GridSplitter
{
    internal Action? Persist { get; init; }
    protected override void OnPreviewKeyDown(KeyEventArgs args)
    {
        var horizontal = ResizeDirection == GridResizeDirection.Columns;
        var direction = args.Key switch { Key.Left when horizontal => -1, Key.Right when horizontal => 1, Key.Up when !horizontal => -1, Key.Down when !horizontal => 1, _ => 0 };
        if (direction == 0 || Parent is not Grid grid) { base.OnPreviewKeyDown(args); return; }
        var index = horizontal ? Grid.GetColumn(this) : Grid.GetRow(this);
        if (index < 1 || (horizontal ? index + 1 >= grid.ColumnDefinitions.Count : index + 1 >= grid.RowDefinitions.Count)) { base.OnPreviewKeyDown(args); return; }
        var previous = horizontal ? grid.ColumnDefinitions[index - 1].ActualWidth : grid.RowDefinitions[index - 1].ActualHeight;
        var next = horizontal ? grid.ColumnDefinitions[index + 1].ActualWidth : grid.RowDefinitions[index + 1].ActualHeight;
        var minPrevious = horizontal ? grid.ColumnDefinitions[index - 1].MinWidth : grid.RowDefinitions[index - 1].MinHeight;
        var minNext = horizontal ? grid.ColumnDefinitions[index + 1].MinWidth : grid.RowDefinitions[index + 1].MinHeight;
        var change = Math.Clamp(direction * KeyboardIncrement, minPrevious - previous, next - minNext);
        if (Math.Abs(change) > .01)
        {
            var first = horizontal ? grid.ColumnDefinitions[index - 1].Width : grid.RowDefinitions[index - 1].Height;
            var second = horizontal ? grid.ColumnDefinitions[index + 1].Width : grid.RowDefinitions[index + 1].Height;
            var a = new GridLength(previous + change, first.IsStar ? GridUnitType.Star : GridUnitType.Pixel);
            var b = new GridLength(next - change, second.IsStar ? GridUnitType.Star : GridUnitType.Pixel);
            if (first.IsStar && !second.IsStar) a = first;
            if (!first.IsStar && second.IsStar) b = second;
            if (horizontal) { grid.ColumnDefinitions[index - 1].Width = a; grid.ColumnDefinitions[index + 1].Width = b; }
            else { grid.RowDefinitions[index - 1].Height = a; grid.RowDefinitions[index + 1].Height = b; }
            grid.UpdateLayout(); Persist?.Invoke();
        }
        args.Handled = true;
    }
}
