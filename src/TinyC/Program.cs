using System.Text.Json;
using TinyC;

// tinyc — a tiny compiler that emits pure .NET IL.
//
//   tinyc <input.tiny> [-o <output>] [--exe | --dll] [--il]
//
//   --exe   produce a runnable assembly with a Main entry point (default)
//   --dll   produce a class library for C#/VB.NET to reference
//   --il    also write a human-readable <output>.il dump alongside the assembly

try
{
    return Run(args);
}
catch (TinyCompileException ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}

static int Run(string[] args)
{
    string? input = null;
    string? output = null;
    bool asExe = true;
    bool dumpIl = false;

    for (int i = 0; i < args.Length; i++)
    {
        switch (args[i])
        {
            case "--exe": asExe = true; break;
            case "--dll": asExe = false; break;
            case "--il": dumpIl = true; break;
            case "-o":
                if (++i >= args.Length) throw new TinyCompileException("-o requires a path");
                output = args[i];
                break;
            default:
                if (args[i].StartsWith('-')) throw new TinyCompileException($"unknown option '{args[i]}'");
                input = args[i];
                break;
        }
    }

    if (input is null)
    {
        Console.Error.WriteLine("usage: tinyc <input.tiny> [-o <output>] [--exe|--dll] [--il]");
        return 2;
    }

    string source = File.ReadAllText(input);
    string asmName = Path.GetFileNameWithoutExtension(input);
    output ??= Path.ChangeExtension(input, ".dll");

    var tokens = new Lexer(source).Tokenize();
    var program = new Parser(tokens).ParseProgram();
    var emitter = new Emitter(program, asmName);
    string ilText = emitter.Emit(output, asExe);

    if (dumpIl)
    {
        string ilPath = Path.ChangeExtension(output, ".il");
        File.WriteAllText(ilPath, ilText);
        Console.WriteLine($"wrote IL dump  -> {ilPath}");
    }

    // An exe must ship a runtimeconfig.json so `dotnet <out>.dll` resolves a runtime.
    if (asExe)
        WriteRuntimeConfig(output);

    Console.WriteLine($"compiled {input} -> {output} ({(asExe ? "executable" : "library")})");
    return 0;
}

static void WriteRuntimeConfig(string assemblyPath)
{
    string configPath = Path.ChangeExtension(assemblyPath, ".runtimeconfig.json");
    var config = new
    {
        runtimeOptions = new
        {
            tfm = "net10.0",
            framework = new { name = "Microsoft.NETCore.App", version = "10.0.0" },
            configProperties = new Dictionary<string, object>()
        }
    };
    var opts = new JsonSerializerOptions { WriteIndented = true };
    File.WriteAllText(configPath, JsonSerializer.Serialize(config, opts));
}
