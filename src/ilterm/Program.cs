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

// ilterm — an Avalonia "display server": a resizable, colored terminal window that hosts
// our compiled shell (ilsh) by wiring CRuntime's console I/O to a VT grid.
//
//   1) build the shell:  bash shell/build.sh   (produces out/ilsh.dll)
//   2) run:              dotnet run --project src/ilterm -- out/ilsh.dll [--home DIR]

internal static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        AssemblyLoadContext.Default.Resolving += (ctx, name) =>
            name.Name == "CRuntime" ? typeof(CRuntime).Assembly : null;
        Shell.Path = args.Length > 0 ? System.IO.Path.GetFullPath(args[0]) : "out/ilsh.dll";
        Shell.Args = args.Length > 1 ? args[1..] : System.Array.Empty<string>();   // forwarded to the shell (e.g. --home DIR)
        Shell.LaunchArgs = args;
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}

internal static class Shell
{
    public static string Path = "out/ilsh.dll";
    public static string[] Args = System.Array.Empty<string>();
    public static string[] LaunchArgs = System.Array.Empty<string>();

    // The home directory used to find .quicklaunch: the --home value if present, else %USERPROFILE%.
    public static string HomeDir()
    {
        for (int i = 0; i < Args.Length; i++)
        {
            if (Args[i] == "--home" && i + 1 < Args.Length) return Args[i + 1];
            if (Args[i].StartsWith("--home=")) return Args[i].Substring(7);
        }
        return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }
}

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

    // a standard 16-color ANSI palette (0-7 normal, 8-15 bright)
    private static readonly Color[] Palette =
    {
        Color.FromRgb(0x1e,0x1e,0x1e), Color.FromRgb(0xcd,0x31,0x31), Color.FromRgb(0x0d,0xbc,0x79), Color.FromRgb(0xe5,0xe5,0x10),
        Color.FromRgb(0x24,0x72,0xc8), Color.FromRgb(0xbc,0x3f,0xbc), Color.FromRgb(0x11,0xa8,0xcd), Color.FromRgb(0xd0,0xd0,0xd0),
        Color.FromRgb(0x66,0x66,0x66), Color.FromRgb(0xf1,0x4c,0x4c), Color.FromRgb(0x23,0xd1,0x8b), Color.FromRgb(0xf5,0xf5,0x43),
        Color.FromRgb(0x3b,0x8e,0xea), Color.FromRgb(0xd6,0x70,0xd6), Color.FromRgb(0x29,0xb8,0xdb), Color.FromRgb(0xff,0xff,0xff),
    };
    private readonly IBrush[] _fgBrush = new IBrush[16];
    private readonly IBrush[] _bgBrush = new IBrush[16];

    private string _fontFamily = "Cascadia Mono, Consolas, Menlo, monospace";
    private double _fontSize = 15;
    private Typeface _tf;
    private double _cw, _ch;

    // mouse selection: linear cell indices, -1 = no selection
    private int _selA = -1, _selB = -1;
    private bool _selecting;

    public TerminalControl()
    {
        Focusable = true;
        for (int i = 0; i < 16; i++) { _fgBrush[i] = new SolidColorBrush(Palette[i]); _bgBrush[i] = new SolidColorBrush(Palette[i]); }
        SetFont(_fontFamily, _fontSize);

        CRuntime.HostOut = b => { lock (_grid) _grid.Process(b); };
        CRuntime.HostKey = () => _keys.Take();
        CRuntime.HostCols = () => _grid.Cols;
        CRuntime.HostRows = () => _grid.Rows;
        CRuntime.HostClear = () => { lock (_grid) _grid.Process(new byte[] { 27, (byte)'[', (byte)'2', (byte)'J' }); };
        CRuntime.HostGoto = (x, y) => { lock (_grid) { _grid.Cx = x; _grid.Cy = y; } };
        CRuntime.HostReloadMenu = () => Dispatcher.UIThread.Post(() => ContextMenu = BuildMenu());   // `refresh` re-reads .quicklaunch

        new Thread(RunShell) { IsBackground = true }.Start();

        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        timer.Tick += (_, _) => InvalidateVisual();
        timer.Start();

        SizeChanged += (_, _) =>
        {
            int c = Math.Max(20, (int)(Bounds.Width / _cw));
            int r = Math.Max(6, (int)(Bounds.Height / _ch));
            lock (_grid) _grid.Resize(c, r);
        };

        ContextMenu = BuildMenu();
    }

    private void SetFont(string family, double size)
    {
        _fontFamily = family; _fontSize = size;
        _tf = new Typeface(family);
        var m = Measure("M");
        _cw = m.Width; _ch = m.Height;
        if (Bounds.Width > 0)
        {
            int c = Math.Max(20, (int)(Bounds.Width / _cw));
            int r = Math.Max(6, (int)(Bounds.Height / _ch));
            lock (_grid) _grid.Resize(c, r);
        }
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();
        var items = new System.Collections.Generic.List<object>();

        MenuItem mk(string h, Action a) { var mi = new MenuItem { Header = h }; mi.Click += (_, _) => a(); return mi; }

        items.Add(mk("Copy", CopySelection));
        items.Add(mk("Paste", PasteClipboard));
        items.Add(mk("Cut", CopySelection));            // a terminal can't remove emitted text; cut == copy
        items.Add(new Separator());
        items.Add(mk("New shell window", LaunchDuplicate));

        var font = new MenuItem { Header = "Font" };
        var fitems = new System.Collections.Generic.List<object>
        {
            mk("Larger",  () => SetFont(_fontFamily, Math.Min(40, _fontSize + 1))),
            mk("Smaller", () => SetFont(_fontFamily, Math.Max(8,  _fontSize - 1))),
            new Separator(),
            mk("Cascadia Mono", () => SetFont("Cascadia Mono, Consolas, monospace", _fontSize)),
            mk("Consolas",      () => SetFont("Consolas, monospace", _fontSize)),
            mk("Lucida Console",() => SetFont("Lucida Console, monospace", _fontSize)),
        };
        font.ItemsSource = fitems;
        items.Add(font);

        // .quicklaunch entries (Label = command), injected as if typed
        var ql = LoadQuickLaunch();
        if (ql.Count > 0)
        {
            items.Add(new Separator());
            foreach (var (label, cmd) in ql) items.Add(mk(label, () => InjectLine(cmd)));
        }

        menu.ItemsSource = items;
        return menu;
    }

    private System.Collections.Generic.List<(string, string)> LoadQuickLaunch()
    {
        var list = new System.Collections.Generic.List<(string, string)>();
        try
        {
            string path = System.IO.Path.Combine(Shell.HomeDir(), ".quicklaunch");
            if (!File.Exists(path)) return list;
            foreach (var raw in File.ReadAllLines(path))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) { list.Add((line, line)); continue; }
                list.Add((line.Substring(0, eq).Trim(), line.Substring(eq + 1).Trim()));
            }
        }
        catch { }
        return list;
    }

    private void InjectLine(string s) { foreach (char c in s) _keys.Add(c); _keys.Add(13); }

    private void CopySelection()
    {
        string text = SelectedText();
        if (text.Length == 0) return;
        TopLevel.GetTopLevel(this)?.Clipboard?.SetTextAsync(text);
    }
    private async void PasteClipboard()
    {
        var cb = TopLevel.GetTopLevel(this)?.Clipboard;
        if (cb == null) return;
        string s = await cb.GetTextAsync() ?? "";
        foreach (char c in s) { if (c == '\n' || c == '\r') _keys.Add(13); else if (c >= 32) _keys.Add(c); }
    }
    private void LaunchDuplicate()
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo { FileName = Environment.ProcessPath, UseShellExecute = false };
            foreach (var a in Shell.LaunchArgs) psi.ArgumentList.Add(a);
            System.Diagnostics.Process.Start(psi);
        }
        catch (Exception e) { Console.Error.WriteLine("ilterm: launch failed: " + e.Message); }
    }

    private string SelectedText()
    {
        if (_selA < 0 || _selB < 0) return "";
        int a = Math.Min(_selA, _selB), b = Math.Max(_selA, _selB);
        lock (_grid)
        {
            var sb = new StringBuilder();
            for (int i = a; i <= b && i < _grid.Ch.Length; i++)
            {
                sb.Append(_grid.Ch[i]);
                if ((i + 1) % _grid.Cols == 0) { while (sb.Length > 0 && sb[sb.Length - 1] == ' ') sb.Length--; sb.Append('\n'); }
            }
            return sb.ToString();
        }
    }

    private int CellAt(Point p)
    {
        int x = Math.Clamp((int)((p.X - 2) / _cw), 0, _grid.Cols - 1);
        int y = Math.Clamp((int)(p.Y / _ch), 0, _grid.Rows - 1);
        return y * _grid.Cols + x;
    }
    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        var pt = e.GetCurrentPoint(this);
        if (pt.Properties.IsLeftButtonPressed) { _selecting = true; _selA = _selB = CellAt(pt.Position); Focus(); e.Handled = true; }
    }
    protected override void OnPointerMoved(PointerEventArgs e)
    {
        if (_selecting) { _selB = CellAt(e.GetCurrentPoint(this).Position); e.Handled = true; }
    }
    protected override void OnPointerReleased(PointerReleasedEventArgs e) { _selecting = false; }

    private FormattedText Measure(string s) =>
        new(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, _tf, _fontSize, Brushes.White);

    private static void RunShell()
    {
        try
        {
            var asm = Assembly.LoadFrom(Shell.Path);
            var m = asm.GetType("CProgram")!.GetMethod("Main", BindingFlags.Public | BindingFlags.Static)!;
            object[] inv = m.GetParameters().Length == 1 ? new object[] { Shell.Args } : null;
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
        bool ctrl = e.KeyModifiers.HasFlag(KeyModifiers.Control);
        if (ctrl && e.Key == Key.C) { CopySelection(); e.Handled = true; return; }
        if (ctrl && e.Key == Key.V) { PasteClipboard(); e.Handled = true; return; }
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
        ctx.FillRectangle(_bgBrush[0], new Rect(Bounds.Size));
        lock (_grid)
        {
            int selLo = Math.Min(_selA, _selB), selHi = Math.Max(_selA, _selB);
            bool hasSel = _selA >= 0 && _selB >= 0;
            for (int y = 0; y < _grid.Rows; y++)
            {
                int rowBase = y * _grid.Cols;
                // draw background runs (skip default bg 0) and selection
                for (int x = 0; x < _grid.Cols; x++)
                {
                    int i = rowBase + x;
                    bool sel = hasSel && i >= selLo && i <= selHi;
                    int bg = _grid.Bg[i];
                    if (sel) ctx.FillRectangle(_fgBrush[4], new Rect(2 + x * _cw, y * _ch, _cw, _ch));
                    else if (bg != 0) ctx.FillRectangle(_bgBrush[bg & 15], new Rect(2 + x * _cw, y * _ch, _cw, _ch));
                }
                // draw foreground runs grouped by color
                int run = 0;
                while (run < _grid.Cols)
                {
                    int fg = _grid.Fg[rowBase + run] & 15;
                    int end = run;
                    var sb = new StringBuilder();
                    while (end < _grid.Cols && (_grid.Fg[rowBase + end] & 15) == fg) { sb.Append(_grid.Ch[rowBase + end]); end++; }
                    string s = sb.ToString();
                    if (s.Trim().Length > 0)
                    {
                        var ft = Measure(s);
                        ft.SetForegroundBrush(_fgBrush[fg]);
                        ctx.DrawText(ft, new Point(2 + run * _cw, y * _ch));
                    }
                    run = end;
                }
            }
            ctx.FillRectangle(new SolidColorBrush(Colors.Gainsboro, 0.55),
                new Rect(2 + _grid.Cx * _cw, _grid.Cy * _ch, _cw, _ch));
        }
    }
}
