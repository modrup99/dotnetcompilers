using CoilAsm;
using ILForge;

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

    // The managed image is always a .dll; a native apphost .exe boots it (as cc does). So
    // `-o prog.exe` yields prog.dll + prog.runtimeconfig.json + a runnable prog.exe rather
    // than a managed PE named .exe, which could only be started via `dotnet prog.exe`.
    string managed = asExe ? Path.ChangeExtension(output, ".dll") : output;
    string ir = File.ReadAllText(input);
    string asmName = Path.GetFileNameWithoutExtension(managed);
    new Assembler(asmName).Assemble(ir, managed, asExe);

    if (asExe)
    {
        AppHost.WriteRuntimeConfig(managed);
        string? exe = AppHost.Stamp(managed, "coilasm");
        Console.WriteLine($"coilasm: {input} -> {managed}{(exe != null ? " + " + exe : "")} (executable)");
    }
    else Console.WriteLine($"coilasm: {input} -> {managed} (library)");
    return 0;
}
catch (CoilAsmException ex) { Console.Error.WriteLine(ex.Message); return 1; }
