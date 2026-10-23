using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace Reviset.Windows;

internal sealed class BridgeException(string code, string message) : Exception(code + ": " + message)
{
    public string Code { get; } = code;
}

internal sealed class BridgeClient : IDisposable
{
    private readonly SemaphoreSlim serial = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    public string BundleRoot { get; }
    public string Library { get; }
    public string Node => Path.Combine(BundleRoot, "runtime", "node.exe");
    public string Backend => Path.Combine(BundleRoot, "backend", "bridge.mjs");
    public BridgeClient(string bundleRoot, string library) { BundleRoot = Path.GetFullPath(bundleRoot); Library = Path.GetFullPath(library); }

    public async Task<JsonElement> Call(string action, object? arguments = null, CancellationToken token = default, Action<JsonElement>? progress = null, Action<int>? startedForSmoke = null, Func<JsonElement, CancellationToken, Task>? beforeReplyForSmoke = null)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, lifetime.Token);
        token = linked.Token;
        await serial.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (!File.Exists(Node) || !File.Exists(Backend)) throw new BridgeException("BUNDLE_MISSING", "The bundled Node runtime or backend is missing. Install the complete Reviset package.");
            var start = StartInfo(Backend);
            start.ArgumentList.Add("--root"); start.ArgumentList.Add(Library);
            return await Execute(start, new { action, args = arguments ?? new { } }, token, progress, startedForSmoke, beforeReplyForSmoke).ConfigureAwait(false);
        }
        finally { serial.Release(); }
    }

    public ProcessStartInfo StartInfo(string script)
    {
        var start = new ProcessStartInfo(Node) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = BundleRoot, StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        start.ArgumentList.Add("--max-old-space-size=2048"); start.ArgumentList.Add(Path.GetFullPath(script));
        var inherited = new[] { "SystemRoot", "WINDIR", "TEMP", "TMP", "USERPROFILE", "LOCALAPPDATA", "APPDATA", "PROGRAMDATA", "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE" };
        start.Environment.Clear();
        foreach (var key in inherited) if (Environment.GetEnvironmentVariable(key) is { } value) start.Environment[key] = value;
        start.Environment["PATH"] = Environment.GetFolderPath(Environment.SpecialFolder.System);
        return start;
    }

    private async Task<JsonElement> Execute(ProcessStartInfo start, object request, CancellationToken token, Action<JsonElement>? progress, Action<int>? startedForSmoke, Func<JsonElement, CancellationToken, Task>? beforeReplyForSmoke)
    {
        using var job = new ProcessJob();
        using var process = new Process { StartInfo = start };
        if (!process.Start()) throw new BridgeException("HELPER_START", "The document engine could not start.");
        job.Assign(process);
        using var kill = token.Register(() => { try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { } });
        startedForSmoke?.Invoke(process.Id);
        using var outputStop = CancellationTokenSource.CreateLinkedTokenSource(token);
        var stderr = new StringBuilder();
        var errorTask = ReadErrors(process.StandardError, stderr, progress, outputStop.Token);
        var outputTask = ReadBounded(process.StandardOutput, 64 * 1024 * 1024, outputStop.Token);
        try
        {
            await process.StandardInput.WriteAsync(JsonSerializer.Serialize(request).AsMemory(), token).ConfigureAwait(false);
            process.StandardInput.Close();
            // Drain stdout and stderr concurrently. An oversized response kills the helper immediately.
            var wait = process.WaitForExitAsync(token);
            var first = await Task.WhenAny(outputTask, errorTask, wait).ConfigureAwait(false);
            if (first.IsFaulted) await first.ConfigureAwait(false);
            var output = await outputTask.ConfigureAwait(false);
            await wait.ConfigureAwait(false); await errorTask.ConfigureAwait(false); token.ThrowIfCancellationRequested();
            using var document = JsonDocument.Parse(output, new JsonDocumentOptions { MaxDepth = 128 });
            var reply = document.RootElement;
            if (reply.Get("protocol_version").Text() != "0.1.0" || reply.Get("schema_version").Text() != "0.4.0") throw new BridgeException("PROTOCOL_MISMATCH", "The app and document engine contract versions differ.");
            if (!reply.Get("ok").Flag()) throw new BridgeException(reply.Get("error").Get("code").Text(), reply.Get("error").Get("message").Text());
            if (process.ExitCode != 0) throw new BridgeException("HELPER_EXIT", "The engine exited with code " + process.ExitCode);
            var value = reply.Get("value").Clone();
            // Isolated native QA can withhold a verified real helper reply before
            // its caller receives any descriptor. Normal requests have no gate.
            if (beforeReplyForSmoke is not null) await beforeReplyForSmoke(value, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested(); return value;
        }
        catch (Exception error)
        {
            try { if (!process.HasExited) process.Kill(true); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { }
            outputStop.Cancel();
            try { await process.WaitForExitAsync(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(5)).ConfigureAwait(false); } catch (Exception) { }
            try { await Task.WhenAll(outputTask, errorTask).ConfigureAwait(false); } catch (Exception) { }
            token.ThrowIfCancellationRequested();
            if (error is JsonException || error is BridgeException helper && helper.Code is "PROTOCOL_MISMATCH" or "HELPER_EXIT" or "HELPER_OUTPUT_LIMIT")
            {
                var path = WriteDiagnostics(error, stderr.ToString());
                throw new BridgeException("HELPER_PROTOCOL", "The engine returned an invalid or incomplete response." + (path is null ? "" : " Diagnostic log: " + path));
            }
            throw;
        }
    }

    private string? WriteDiagnostics(Exception error, string stderr)
    {
        try
        {
            var folder = Path.Combine(Path.GetDirectoryName(Library) ?? Library, "logs"); Directory.CreateDirectory(folder); var path = Path.Combine(folder, "helper-error.log");
            // Plain text only, bounded and overwritten. No source/output is executed,
            // interpolated into commands or interpreted as a format string.
            var text = DateTimeOffset.UtcNow.ToString("O", System.Globalization.CultureInfo.InvariantCulture) + "\n" + error.GetType().Name + "\n" + (stderr.Length > 65536 ? stderr[^65536..] : stderr);
            File.WriteAllText(path, new string(text.Select(character => char.IsControl(character) && character is not ('\n' or '\r' or '\t') ? '�' : character).ToArray()), new UTF8Encoding(false)); return path;
        }
        catch (Exception errorWriting) when (errorWriting is IOException or UnauthorizedAccessException) { return null; }
    }
    internal Task<JsonElement> ProtocolControlForSmoke(string trustedScript) => Execute(StartInfo(trustedScript), new { }, CancellationToken.None, null, null, null);

    private static async Task<string> ReadBounded(StreamReader reader, int maximum, CancellationToken token)
    {
        var result = new StringBuilder(); var buffer = new char[8192]; int count;
        while ((count = await reader.ReadAsync(buffer.AsMemory(), token).ConfigureAwait(false)) != 0)
        { if (result.Length + count > maximum) throw new BridgeException("HELPER_OUTPUT_LIMIT", "The engine response exceeded the desktop limit."); result.Append(buffer, 0, count); }
        return result.ToString();
    }
    private static async Task ReadErrors(StreamReader reader, StringBuilder tail, Action<JsonElement>? progress, CancellationToken token)
    {
        var pending = new StringBuilder(); var buffer = new char[4096]; int count;
        while ((count = await reader.ReadAsync(buffer.AsMemory(), token).ConfigureAwait(false)) != 0)
        {
            tail.Append(buffer, 0, count); if (tail.Length > 65536) tail.Remove(0, tail.Length - 65536);
            foreach (var character in buffer.Take(count))
            {
                if (character == '\n') { try { using var line = JsonDocument.Parse(pending.ToString()); if (line.RootElement.Get("event").Text() == "progress") progress?.Invoke(line.RootElement.Get("progress").Clone()); } catch (JsonException) { } pending.Clear(); }
                else if (pending.Length < 65536) pending.Append(character); else pending.Clear();
            }
        }
    }
    public void Dispose() { lifetime.Cancel(); lifetime.Dispose(); }
}
