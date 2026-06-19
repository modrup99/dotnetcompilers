using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Threading;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using Avalonia.VisualTree;
using CRuntimeLib;

// ilgfx — an Avalonia "display server" for graphics programs: it hosts a compiled
// IL program (e.g. xeyes.dll) by wiring CRuntime's gfx_* hooks to a window that
// blits the program's ARGB framebuffer and feeds back the mouse position.
//
//   dotnet run --project src/ilgfx -- out/xeyes.dll

internal static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        AssemblyLoadContext.Default.Resolving += (ctx, name) =>
            name.Name == "CRuntime" ? typeof(CRuntime).Assembly : null;
        Prog.Path = args.Length > 0 ? System.IO.Path.GetFullPath(args[0]) : "out/xeyes.dll";
        AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace()
            .StartWithClassicDesktopLifetime(args);
    }
}

internal static class Prog { public static string Path = "out/xeyes.dll"; }

internal sealed class App : Application
{
    public override void Initialize() => Styles.Add(new Avalonia.Themes.Fluent.FluentTheme());
    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime d)
            d.MainWindow = new Window { Title = "ilgfx", Width = 420, Height = 260, Content = new GfxControl() };
        base.OnFrameworkInitializationCompleted();
    }
}

internal sealed class GfxControl : Control
{
    private int[] _fb;
    private int _w, _h;
    private WriteableBitmap _bmp;
    private Point _mouse;
    private volatile bool _quit;

    public GfxControl()
    {
        CRuntime.HostGfxOpen = (w, h, fb, title) =>
        {
            _w = w; _h = h; _fb = fb;
            Dispatcher.UIThread.Post(() =>
            {
                _bmp = new WriteableBitmap(new PixelSize(w, h), new Vector(96, 96), PixelFormat.Bgra8888, AlphaFormat.Premul);
                if (this.GetVisualRoot() is Window win) { win.Title = title; win.Width = w; win.Height = h; }
                InvalidateVisual();
            });
        };
        CRuntime.HostGfxPresent = () => Dispatcher.UIThread.Post(InvalidateVisual);
        CRuntime.HostGfxMouseX = () => Bounds.Width > 0 ? (int)(_mouse.X * _w / Bounds.Width) : 0;
        CRuntime.HostGfxMouseY = () => Bounds.Height > 0 ? (int)(_mouse.Y * _h / Bounds.Height) : 0;
        CRuntime.HostGfxQuit = () => _quit ? 1 : 0;

        var t = new Thread(RunProg) { IsBackground = true };
        t.Start();
    }

    protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (this.GetVisualRoot() is Window w)
            w.Closing += (_, _) => _quit = true;
    }

    protected override void OnPointerMoved(PointerEventArgs e) { _mouse = e.GetPosition(this); }

    private static void RunProg()
    {
        try
        {
            var asm = Assembly.LoadFrom(Prog.Path);
            asm.GetType("CProgram")!.GetMethod("Main", BindingFlags.Public | BindingFlags.Static)!
                .Invoke(null, null);
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); }
        finally { Dispatcher.UIThread.Post(() => (Application.Current?.ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.Shutdown()); }
    }

    public override void Render(DrawingContext ctx)
    {
        if (_bmp == null || _fb == null) { ctx.FillRectangle(Brushes.Black, new Rect(Bounds.Size)); return; }
        using (var buf = _bmp.Lock())
            Marshal.Copy(_fb, 0, buf.Address, _fb.Length);
        ctx.DrawImage(_bmp, new Rect(0, 0, _w, _h), new Rect(Bounds.Size));
    }
}
