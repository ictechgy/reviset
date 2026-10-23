using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Reviset.Windows;

// WPF owns min/max constraints, flow direction, DPI and star sizing. Capture
// preferences only after its keyboard move has been arranged on the parent grid.
internal sealed class NativeSplitter : GridSplitter
{
    internal Action? Persist { get; init; }
    protected override void OnKeyDown(KeyEventArgs args)
    {
        base.OnKeyDown(args);
        if (!args.Handled || args.Key is not (Key.Left or Key.Right or Key.Up or Key.Down) || Parent is not Grid grid) return;
        grid.UpdateLayout(); Persist?.Invoke();
    }
}
