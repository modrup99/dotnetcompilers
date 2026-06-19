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

static int Run(string[] args)
{
    string? input = null, output = null;
    bool asExe = true;

    for (int i = 0; i < args.Length; i++)
    {
        switch (args[i])
        {
            case "--exe": asExe = true; break;
            case "--dll": asExe = false; break;
            case "-o":
                if (++i >= args.Length) throw new CCompileException("-o requires a path");
                output = args[i];
                break;
            default:
                if (args[i].StartsWith('-')) throw new CCompileException($"unknown option '{args[i]}'");
                input = args[i];
                break;
        }
    }

    if (input is null)
    {
        Console.Error.WriteLine("usage: cc <input.c> [-o <output>] [--exe|--dll]");
        return 2;
    }

    string source = File.ReadAllText(input);
    output ??= Path.ChangeExtension(input, ".dll");
    // The managed image is always a .dll (a native apphost .exe boots it); so an
    // -o foo.exe still yields foo.dll + foo.exe rather than a managed-PE-named-.exe.
    string managed = asExe ? Path.ChangeExtension(output, ".dll") : output;
    // The assembly's identity must match the output file name, else the host
    // can resolve a same-named sibling assembly instead of this one.
    string asmName = Path.GetFileNameWithoutExtension(managed);

    string baseDir = Path.GetDirectoryName(Path.GetFullPath(input)) ?? ".";
    source = new Preprocessor(baseDir).Process(source);
    var lexer = new Lexer(source, Path.GetFullPath(input));
    var tokens = lexer.Tokenize();
    var unit = new Parser(tokens).Parse();
    new Emitter(unit, asmName, lexer.Documents).Emit(managed, asExe);

    CopyRuntime(managed);
    if (asExe)
    {
        WriteRuntimeConfig(managed);
        string exe = WriteAppHost(managed);
        Console.WriteLine($"compiled {input} -> {managed}{(exe != null ? " + " + exe : "")} (executable)");
    }
    else Console.WriteLine($"compiled {input} -> {managed} (library)");
    return 0;
}

// Stamp out a native apphost .exe that boots the managed .dll, by patching the
// app-path placeholder in the SDK's apphost template (same scheme as the SDK).
static string? WriteAppHost(string managedDllPath)
{
    string? template = FindAppHostTemplate();
    if (template is null)
    {
        Console.Error.WriteLine($"cc: apphost template not found; run with 'dotnet {Path.GetFileName(managedDllPath)}'");
        return null;
    }
    string exePath = Path.ChangeExtension(managedDllPath, ".exe");
    byte[] host = File.ReadAllBytes(template);
    byte[] mark = Encoding.UTF8.GetBytes("c3ab8ff13720e8ad9047dd39466b3c8974e592c2fa383d4a3960714caef0c4f2");
    int off = IndexOf(host, mark);
    if (off < 0) { Console.Error.WriteLine("cc: apphost placeholder not found"); return null; }

    byte[] appBin = Encoding.UTF8.GetBytes(Path.GetFileName(managedDllPath));   // relative: exe sits beside dll
    if (appBin.Length >= 1024) { Console.Error.WriteLine("cc: app path too long for apphost"); return null; }
    Array.Copy(appBin, 0, host, off, appBin.Length);
    for (int i = off + appBin.Length; i < off + mark.Length; i++) host[i] = 0;   // clear the rest of the marker
    File.WriteAllBytes(exePath, host);
    return exePath;
}

static int IndexOf(byte[] hay, byte[] needle)
{
    for (int i = 0; i <= hay.Length - needle.Length; i++)
    {
        int j = 0; while (j < needle.Length && hay[i + j] == needle[j]) j++;
        if (j == needle.Length) return i;
    }
    return -1;
}

static string? FindAppHostTemplate()
{
    string rtDir = RuntimeEnvironment.GetRuntimeDirectory();                 // <root>/shared/Microsoft.NETCore.App/<ver>/
    string root = Path.GetFullPath(Path.Combine(rtDir, "..", "..", ".."));
    string rid = RuntimeInformation.RuntimeIdentifier;                        // e.g. win-x64
    string hostPacks = Path.Combine(root, "packs", $"Microsoft.NETCore.App.Host.{rid}");
    if (Directory.Exists(hostPacks))
        foreach (var v in Directory.GetDirectories(hostPacks).OrderByDescending(x => x))
        {
            string p = Path.Combine(v, "runtimes", rid, "native", "apphost.exe");
            if (File.Exists(p)) return p;
        }
    string sdks = Path.Combine(root, "sdk");
    if (Directory.Exists(sdks))
        foreach (var v in Directory.GetDirectories(sdks).OrderByDescending(x => x))
        {
            string p = Path.Combine(v, "AppHostTemplate", "apphost.exe");
            if (File.Exists(p)) return p;
        }
    return null;
}

// The emitted assembly references CRuntime; place it alongside the output.
static void CopyRuntime(string outputPath)
{
    string src = Path.Combine(AppContext.BaseDirectory, "CRuntime.dll");
    string dst = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(outputPath)) ?? ".", "CRuntime.dll");
    if (!File.Exists(src) || Path.GetFullPath(src) == Path.GetFullPath(dst)) return;
    // The destination may be locked because a running tool (e.g. our pascal.exe,
    // which lives in the output dir) has it loaded; the existing copy is fine.
    try { File.Copy(src, dst, overwrite: true); }
    catch (IOException) { }
}

static void WriteRuntimeConfig(string assemblyPath)
{
    string configPath = Path.ChangeExtension(assemblyPath, ".runtimeconfig.json");
    var config = new
    {
        runtimeOptions = new
        {
            tfm = "net10.0",
            framework = new { name = "Microsoft.NETCore.App", version = "10.0.0" }
        }
    };
    File.WriteAllText(configPath, JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true }));
}
