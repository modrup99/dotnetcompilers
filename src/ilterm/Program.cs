using System.Collections.Concurrent;
using System.Globalization;
using System.Reflection;
using System.Runtime.Loader;
using System.Text;
using System.Threading;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Threading;
using CRuntimeLib;

// ilterm — an Avalonia "display server": a resizable terminal window that hosts
// our compiled shell (ilsh) by wiring CRuntime's console I/O to a VT grid.
//
//   1) build the shell:  bash shell/build.sh   (produces out/ilsh.dll)
//   2) run:              dotnet run --project src/ilterm -- out/ilsh.dll

internal static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        // make ilsh.dll's CRuntime dependency resolve to *this* loaded CRuntime,
        // so the I/O hooks we set actually affect the shell.
        AssemblyLoadContext.Default.Resolving += (ctx, name) =>
            name.Name == "CRuntime" ? typeof(CRuntime).Assembly : null;
        Shell.Path = args.Length > 0 ? System.IO.Path.GetFullPath(args[0]) : "out/ilsh.dll";
        Shell.Args = args.Length > 1 ? args[1..] : System.Array.Empty<string>();   // forwarded to the shell (e.g. --home DIR)
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}

internal static class Shell { public static string Path = "out/ilsh.dll"; public static string[] Args = System.Array.Empty<string>(); }

internal sealed class App : Application
{
    public override void Initialize() => Styles.Add(new Avalonia.Themes.Fluent.FluentTheme());
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime d)
            d.MainWindow = new Window { Title = "ilterm", Width = 760, Height = 460, Content = new TerminalControl() };
        base.OnFrameworkInitializationCompleted();
    }
}

internal sealed class TerminalControl : Control
{
    private readonly TermGrid _grid = new(80, 24);
    private readonly BlockingCollection<int> _keys = new(new ConcurrentQueue<int>());
    private readonly Typeface _tf = new("Cascadia Mono, Consolas, Menlo, monospace");
    private double _cw, _ch;
    private const double FontSize = 15;

    public TerminalControl()
    {
        Focusable = true;
        var m = Measure("M");
        _cw = m.Width; _ch = m.Height;

        CRuntime.HostOut = b => { lock (_grid) _grid.Process(b); };
        CRuntime.HostKey = () => _keys.Take();                 // blocks the shell thread until a key
        CRuntime.HostCols = () => _grid.Cols;
        CRuntime.HostRows = () => _grid.Rows;
        CRuntime.HostClear = () => { lock (_grid) _grid.Process(new byte[] { 27, (byte)'[', (byte)'2', (byte)'J' }); };
        CRuntime.HostGoto = (x, y) => { lock (_grid) { _grid.Cx = x; _grid.Cy = y; } };

        var t = new Thread(RunShell) { IsBackground = true };
        t.Start();

        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        timer.Tick += (_, _) => InvalidateVisual();
        timer.Start();

        SizeChanged += (_, _) =>
        {
            int c = Math.Max(20, (int)(Bounds.Width / _cw));
            int r = Math.Max(6, (int)(Bounds.Height / _ch));
            lock (_grid) _grid.Resize(c, r);
        };
    }

    private FormattedText Measure(string s) =>
        new(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, _tf, FontSize, Brushes.White);

    private static void RunShell()
    {
        try
        {
            var asm = Assembly.LoadFrom(Shell.Path);
            var m = asm.GetType("CProgram")!.GetMethod("Main", BindingFlags.Public | BindingFlags.Static)!;
            object[] inv = m.GetParameters().Length == 1 ? new object[] { Shell.Args } : null;   // forward --home etc.
            m.Invoke(null, inv);
        }
        catch (Exception e) { lock (typeof(TerminalControl)) Console.Error.WriteLine(e); }
    }

    protected override void OnTextInput(TextInputEventArgs e)
    {
        if (!string.IsNullOrEmpty(e.Text))
            foreach (char c in e.Text) if (c >= 32) _keys.Add(c);
        e.Handled = true;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        int code = e.Key switch
        {
            Key.Enter => 13, Key.Back => 8, Key.Tab => 9, Key.Escape => 27,
            Key.Up => -1, Key.Down => -2, Key.Left => -3, Key.Right => -4,
            Key.Delete => -5, Key.Home => -6, Key.End => -7, Key.PageUp => -8, Key.PageDown => -9,
            _ => 0
        };
        if (code != 0) { _keys.Add(code); e.Handled = true; }
    }

    public override void Render(DrawingContext ctx)
    {
        ctx.FillRectangle(Brushes.Black, new Rect(Bounds.Size));
        lock (_grid)
        {
            for (int y = 0; y < _grid.Rows; y++)
            {
                var sb = new StringBuilder(_grid.Cols);
                for (int x = 0; x < _grid.Cols; x++) sb.Append(_grid.Ch[y * _grid.Cols + x]);
                var ft = Measure(sb.ToString().TrimEnd());
                ft.SetForegroundBrush(Brushes.Gainsboro);
                ctx.DrawText(ft, new Point(2, y * _ch));
            }
            ctx.FillRectangle(new SolidColorBrush(Colors.Gainsboro, 0.55),
                new Rect(2 + _grid.Cx * _cw, _grid.Cy * _ch, _cw, _ch));
        }
    }
}
