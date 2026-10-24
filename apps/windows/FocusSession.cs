namespace Reviset.Windows;

// Focus hides panels for this workspace session while retaining the user's
// arrangement. Its transient visibility never becomes a saved layout.
internal sealed class FocusSession
{
    private WorkspaceLayout? retained;
    internal bool Active => retained is not null;

    internal WorkspaceLayout Toggle(WorkspaceLayout current)
    {
        if (!Active)
        {
            retained = current.Bounded();
            return Hidden(retained);
        }
        var restored = Persisted(current);
        retained = null;
        return restored;
    }

    internal WorkspaceLayout Baseline(WorkspaceLayout next)
    {
        retained = null;
        return next.Bounded();
    }

    internal WorkspaceLayout Edit(WorkspaceLayout current)
    {
        var bounded = current.Bounded();
        if (!Active) return bounded;
        retained = Persisted(bounded);
        return Hidden(bounded);
    }

    internal WorkspaceLayout Visibility(WorkspaceLayout current, bool? sidebar = null, bool? inspector = null, bool? changes = null)
    {
        var restored = Persisted(current);
        retained = null;
        return (restored with { Sidebar = sidebar ?? restored.Sidebar, Inspector = inspector ?? restored.Inspector, ChangesVisible = changes ?? restored.ChangesVisible }).Bounded();
    }

    internal WorkspaceLayout Persisted(WorkspaceLayout current)
    {
        var bounded = current.Bounded();
        return retained is { } original ? bounded with { Sidebar = original.Sidebar, Inspector = original.Inspector, ChangesVisible = original.ChangesVisible } : bounded;
    }

    private static WorkspaceLayout Hidden(WorkspaceLayout layout) => layout with { Sidebar = false, Inspector = false, ChangesVisible = false };
}
