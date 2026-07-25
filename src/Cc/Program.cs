using System.Text;
using System.Text.Json;
using System.Runtime.InteropServices;
using Cc;

// cc — a C-subset compiler that emits pure .NET IL.
//
//   cc <input.c> [-o <output>] [--exe | --dll]
//
//   --exe   produce a runnable assembly with an entry point (default)
//   --dll   produce a class library for C#/VB.NET to reference

try
{
    return Run(args);
}
catch (CCompileException ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}

static void Usage(TextWriter w) => w.WriteLine(
    "usage: cc <input.c> [-o <output>] [--exe|--dll] [-I <dir>...] [-L <dir>...] [-l <name>...] [--icon <file>]\n" +
    "  -o <output>   output path (default: input with .dll)\n" +
    "  --exe|--dll   produce an executable (default) or a class library\n" +
    "  -I <dir>      add a directory to the #include search path (repeatable; also -I<dir>)\n" +
    "  -L <dir>      add a directory to the library search path (repeatable; also -L<dir>)\n" +
    "  -l <name>     stage <name>.dll (found via -L) beside the output (repeatable; also -l<name>)\n" +
    "  --icon <file> set the .exe icon from a .png/.ico/.bmp (default: the toolchain icon)\n" +
    "  --noicon      do not set any icon on the .exe\n" +
    "  -h, --help    show this help");

static int Run(string[] args)
{
    string? input = null, output = null, iconPath = null;
    bool asExe = true, noIcon = false;
    var includeDirs = new List<string>();
    var libDirs = new List<string>();
    var libNames = new List<string>();

    for (int i = 0; i < args.Length; i++)
    {
        string a = args[i];
        switch (a)
        {
            case "--exe": asExe = true; break;
            case "--dll": asExe = false; break;
            case "-h": case "--help": Usage(Console.Out); return 0;
            case "-o": if (++i >= args.Length) throw new CCompileException("-o requires a path"); output = args[i]; break;
            case "-I": if (++i >= args.Length) throw new CCompileException("-I requires a directory"); includeDirs.Add(args[i]); break;
            case "-L": if (++i >= args.Length) throw new CCompileException("-L requires a directory"); libDirs.Add(args[i]); break;
            case "-l": if (++i >= args.Length) throw new CCompileException("-l requires a name"); libNames.Add(args[i]); break;
            case "--icon": if (++i >= args.Length) throw new CCompileException("--icon requires a file"); iconPath = args[i]; break;
            case "--noicon": noIcon = true; break;
            default:
                if (a.StartsWith("-I")) includeDirs.Add(a.Substring(2));
                else if (a.StartsWith("-L")) libDirs.Add(a.Substring(2));
                else if (a.StartsWith("-l")) libNames.Add(a.Substring(2));
                else if (a.StartsWith('-')) throw new CCompileException($"unknown option '{a}'");
                else input = a;
                break;
        }
    }

    if (input is null)
    {
        Usage(Console.Error);
        return 2;
    }

    // Like a Visual Studio developer prompt, honour INCLUDE and LIB from the environment
    // (the ILForge Developer Command Prompt sets them). Explicit -I/-L win: they come first.
    AddEnvPaths(includeDirs, "INCLUDE");
    AddEnvPaths(libDirs, "LIB");

    string source = File.ReadAllText(input);
    output ??= Path.ChangeExtension(input, ".dll");
    // The managed image is always a .dll (a native apphost .exe boots it); so an
    // -o foo.exe still yields foo.dll + foo.exe rather than a managed-PE-named-.exe.
    string managed = asExe ? Path.ChangeExtension(output, ".dll") : output;
    // The assembly's identity must match the output file name, else the host
    // can resolve a same-named sibling assembly instead of this one.
    string asmName = Path.GetFileNameWithoutExtension(managed);

    string baseDir = Path.GetDirectoryName(Path.GetFullPath(input)) ?? ".";
    source = new Preprocessor(baseDir, includeDirs).Process(source);
    var lexer = new Lexer(source, Path.GetFullPath(input));
    var tokens = lexer.Tokenize();
    var unit = new Parser(tokens).Parse();
    new Emitter(unit, asmName, lexer.Documents).Emit(managed, asExe);

    CopyRuntime(managed, libDirs);
    StageLibs(managed, libDirs, libNames);
    if (asExe)
    {
        WriteRuntimeConfig(managed);
        string exe = WriteAppHost(managed);
        if (exe != null && !noIcon)
        {
            string icon = iconPath ?? Path.Combine(FindRepo(), "icons", "default.png");
            if (File.Exists(icon))
            {
                if (!IconEmbedder.TryEmbed(exe, icon, out var err)) Console.Error.WriteLine($"cc: icon not embedded ({err})");
            }
            else if (iconPath != null) Console.Error.WriteLine($"cc: icon not found: {iconPath}");
        }
        Console.WriteLine($"compiled {input} -> {managed}{(exe != null ? " + " + exe : "")} (executable)");
    }
    else Console.WriteLine($"compiled {input} -> {managed} (library)");
    return 0;
}

// The apphost stamping and runtimeconfig writing live in src/Shared/AppHost.cs, shared
// with coilasm so both back ends produce the same .dll + .runtimeconfig.json + .exe shape.
static string? WriteAppHost(string managedDllPath) => ILForge.AppHost.Stamp(managedDllPath, "cc");

// append the semicolon-separated directories of an environment variable to a search list
static void AddEnvPaths(List<string> into, string envVar)
{
    string? v = Environment.GetEnvironmentVariable(envVar);
    if (string.IsNullOrWhiteSpace(v)) return;
    foreach (var part in v.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        if (Directory.Exists(part) && !into.Contains(part)) into.Add(part);
}

// walk up from the compiler's location to the repo root (folder with build_all.sh),
// where the toolchain's icons\ live; falls back to the current directory.
static string FindRepo()
{
    string? d = AppContext.BaseDirectory;
    for (int i = 0; i < 12 && !string.IsNullOrEmpty(d); i++)
    {
        if (File.Exists(Path.Combine(d, "build_all.sh"))) return d;
        d = Path.GetDirectoryName(d.TrimEnd('\\', '/'));
    }
    return Directory.GetCurrentDirectory();
}

static void CopyRuntime(string outputPath, List<string>? libDirs = null)
{
    string src = Path.Combine(AppContext.BaseDirectory, "CRuntime.dll");
    if (!File.Exists(src) && libDirs != null)                       // -L can supply CRuntime.dll
        foreach (var d in libDirs) { string c = Path.Combine(d, "CRuntime.dll"); if (File.Exists(c)) { src = c; break; } }
    string dst = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(outputPath)) ?? ".", "CRuntime.dll");
    if (!File.Exists(src) || Path.GetFullPath(src) == Path.GetFullPath(dst)) return;
    // The destination may be locked because a running tool (e.g. our pascal.exe,
    // which lives in the output dir) has it loaded; the existing copy is fine.
    try { File.Copy(src, dst, overwrite: true); }
    catch (IOException) { }
}

// -l <name> stages <name>.dll, located via the -L search paths, next to the output.
static void StageLibs(string outputPath, List<string> libDirs, List<string> libNames)
{
    if (libNames.Count == 0) return;
    string outDir = Path.GetDirectoryName(Path.GetFullPath(outputPath)) ?? ".";
    foreach (var name in libNames)
    {
        string file = name.EndsWith(".dll") ? name : name + ".dll";
        string? found = null;
        foreach (var d in libDirs) { string c = Path.Combine(d, file); if (File.Exists(c)) { found = c; break; } }
        if (found is null) { Console.Error.WriteLine($"cc: -l {name}: {file} not found in any -L directory"); continue; }
        string dst = Path.Combine(outDir, Path.GetFileName(found));
        if (Path.GetFullPath(found) == Path.GetFullPath(dst)) continue;
        try { File.Copy(found, dst, overwrite: true); } catch (IOException) { }
    }
}

static void WriteRuntimeConfig(string assemblyPath) => ILForge.AppHost.WriteRuntimeConfig(assemblyPath);
