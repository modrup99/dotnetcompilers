using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;

// ilshell — a real launch .exe for the shell. Loads the compiled ilsh.dll in its
// own assembly load context (so CRuntime resolves from the shell's directory),
// enables ANSI on the Windows console (for the line editor), and runs the shell.
internal static class Program
{
    [DllImport("kernel32.dll")] static extern nint GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(nint h, out uint m);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(nint h, uint m);

    static int Main(string[] args)
    {
        EnableVirtualTerminal();
        // first non-flag arg (if any) names ilsh.dll; everything else is forwarded to the shell
        string dllArg = null;
        var shellArgs = new System.Collections.Generic.List<string>();
        foreach (var a in args)
        {
            if (dllArg == null && !a.StartsWith("-") && a.EndsWith(".dll")) dllArg = a;
            else shellArgs.Add(a);
        }
        string dll = Locate(dllArg);
        if (dll == null) { Console.Error.WriteLine("ilshell: cannot find ilsh.dll (pass its path as an argument)"); return 1; }

        string dir = Path.GetDirectoryName(dll);
        var alc = new AssemblyLoadContext("ilsh", isCollectible: false);
        alc.Resolving += (ctx, name) =>
        {
            string p = Path.Combine(dir, name.Name + ".dll");
            return File.Exists(p) ? ctx.LoadFromAssemblyPath(p) : null;
        };
        var asm = alc.LoadFromAssemblyPath(dll);
        var m = asm.GetType("CProgram")?.GetMethod("Main", BindingFlags.Public | BindingFlags.Static);
        if (m == null) { Console.Error.WriteLine("ilshell: CProgram.Main not found in " + dll); return 1; }
        // CProgram.Main takes string[] when the shell's main wants argc/argv; forward the args
        object[] inv = m.GetParameters().Length == 1 ? new object[] { shellArgs.ToArray() } : null;
        return m.Invoke(null, inv) is int rc ? rc : 0;
    }

    static void EnableVirtualTerminal()
    {
        try
        {
            if (!OperatingSystem.IsWindows()) return;
            var h = GetStdHandle(-11);                       // STD_OUTPUT_HANDLE
            if (GetConsoleMode(h, out uint m)) SetConsoleMode(h, m | 0x0004);  // ENABLE_VIRTUAL_TERMINAL_PROCESSING
        }
        catch { }
    }

    static string Locate(string arg)
    {
        var c = new List<string>();
        if (arg != null) c.Add(arg);
        string b = AppContext.BaseDirectory;
        c.Add(Path.Combine(b, "ilsh.dll"));
        c.Add(Path.Combine(b, "..", "..", "..", "..", "..", "out", "ilsh.dll"));
        c.Add(Path.Combine(Directory.GetCurrentDirectory(), "out", "ilsh.dll"));
        foreach (var x in c) if (File.Exists(x)) return Path.GetFullPath(x);
        return null;
    }
}
