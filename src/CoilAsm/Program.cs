using System.Text.Json;
using CoilAsm;

// coilasm — assembles Coil's stack-IL IR into a real .NET assembly.
//   coilasm <input.ir> -o <output> [--dll]
try
{
    string? input = null, output = null;
    bool asExe = true;
    for (int i = 0; i < args.Length; i++)
    {
        switch (args[i])
        {
            case "--dll": asExe = false; break;
            case "--exe": asExe = true; break;
            case "-o": output = args[++i]; break;
            default: input = args[i]; break;
        }
    }
    if (input is null) { Console.Error.WriteLine("usage: coilasm <input.ir> -o <output> [--dll]"); return 2; }
    output ??= Path.ChangeExtension(input, asExe ? ".exe" : ".dll");

    string ir = File.ReadAllText(input);
    string asmName = Path.GetFileNameWithoutExtension(output);
    new Assembler(asmName).Assemble(ir, output, asExe);

    if (asExe) WriteRuntimeConfig(output);
    Console.WriteLine($"coilasm: {input} -> {output} ({(asExe ? "executable" : "library")})");
    return 0;
}
catch (CoilAsmException ex) { Console.Error.WriteLine(ex.Message); return 1; }

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
    File.WriteAllText(configPath, JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true }));
}
