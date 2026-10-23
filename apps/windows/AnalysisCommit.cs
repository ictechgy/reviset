using System.Runtime.ExceptionServices;
using System.Text.Json;

namespace Reviset.Windows;

internal static class AnalysisCommit
{
    internal static async Task<JsonElement> Save(string project, bool workbook, JsonElement stage, CancellationToken token, Func<string, object, CancellationToken, Task<JsonElement>> call)
    {
        var run = stage.Get("analysis_run_id").Text(); var expected = stage.Get("report_id").Text();
        if (stage.Get("project_id").Text() != project || run.Length == 0 || expected.Length == 0 || expected == "latest") throw new InvalidOperationException("Invalid owned analysis descriptor.");
        try
        {
            token.ThrowIfCancellationRequested();
            var saved = await call(workbook ? "workbookCommit" : "commit", new { project_id = project, result = stage }, token);
            if (saved.Get("report_id").Text() != expected || saved.Get("status").Text() != "complete" || (workbook && saved.Get("project_id").Text() != project)) throw new InvalidOperationException("The commit acknowledgement did not confirm the exact staged report.");
            return saved;
        }
        catch (Exception original)
        {
            JsonElement status;
            try { status = await call(workbook ? "workbookRunStatus" : "runStatus", new { project_id = project, analysis_run_id = run }, CancellationToken.None); }
            catch (Exception lookup) { throw new AggregateException("Save outcome is unconfirmed. Reopen this project to recover the exact run; no stage was discarded.", original, lookup); }
            if (status.Get("project_id").Text() != project || status.Get("analysis_run_id").Text() != run) throw new AggregateException("The run status did not belong to the exact owned analysis. No stage was discarded.", original);
            var state = status.Get("status").Text();
            if (state is "success" or "partial")
            {
                if (status.Get("report_id").Text() != expected) throw new AggregateException("The saved report differs from the staged descriptor. Save outcome is unconfirmed.", original);
                return status;
            }
            if (workbook && state is "staged" or "running")
            {
                try { await call("workbookDiscard", new { project_id = project, analysis_run_id = run }, CancellationToken.None); }
                catch (Exception cleanup) { throw new AggregateException("The exact owned stage could not be cleaned up. Reopen the project to recover it.", original, cleanup); }
            }
            ExceptionDispatchInfo.Capture(original).Throw(); throw new InvalidOperationException("Unreachable");
        }
    }
}
