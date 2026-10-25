using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace Reviset.Windows;

internal sealed class App : Application
{
    [STAThread]
    public static int Main(string[] args)
    {
        string? smoke = Argument(args, "--smoke");
        string? fixtures = Argument(args, "--fixtures");
        var settingsRoot = smoke is null ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Reviset") : Path.Combine(Path.GetFullPath(smoke), "profile");
        var library = Path.Combine(settingsRoot, "library");
        var bundle = AppContext.BaseDirectory;
        if (Argument(args, "--backend-root") is { } overrideRoot)
        {
            if (smoke is null) { MessageBox.Show("--backend-root is supported only with an isolated --smoke profile.", "Reviset"); return 2; }
            bundle = Path.GetFullPath(overrideRoot);
        }
        Directory.CreateDirectory(library);
        var app = new App { ShutdownMode = ShutdownMode.OnMainWindowClose };
        FileStream libraryLock;
        try { libraryLock = new FileStream(Path.Combine(library, ".windows-app.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException)
        {
            if (smoke is not null) { Directory.CreateDirectory(smoke); File.WriteAllText(Path.Combine(smoke, "result.json"), "{\"ok\":false,\"code\":\"LIBRARY_LOCKED\"}"); }
            else MessageBox.Show(new Copy()["lock"], "Reviset");
            return 3;
        }
        using (libraryLock)
        using (var bridge = new BridgeClient(bundle, library))
        {
            var window = new MainWindow(bridge, Path.Combine(settingsRoot, "preferences.json"))
            {
                Icon = BitmapFrame.Create(new Uri("pack://application:,,,/Assets/reviset.ico", UriKind.Absolute))
            };
            app.MainWindow = window;
            window.Loaded += async (_, _) =>
            {
                if (smoke is not null)
                {
                    var success = await Smoke.Run(window, bridge, Path.GetFullPath(smoke), fixtures is null ? null : Path.GetFullPath(fixtures));
                    app.Shutdown(success ? 0 : 1);
                }
                else await window.Initialize();
            };
            app.DispatcherUnhandledException += (_, eventArgs) => { MessageBox.Show(window, eventArgs.Exception.Message, "Reviset"); eventArgs.Handled = true; };
            return app.Run(window);
        }
    }
    private static string? Argument(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        if (index < 0) return null;
        if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal)) throw new ArgumentException("Missing value for " + name);
        return args[index + 1];
    }
}
