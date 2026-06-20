// C# calling functions written in Ada and compiled to .NET IL by our ada -> C -> cc
// toolchain. Each Ada subprogram is a public static method on CProgram (prefixed ada_),
// so it binds like any C# API. Parameters are by value here, giving clean signatures.

Console.WriteLine("C# is calling functions compiled from Ada:");
Console.WriteLine($"  CProgram.ada_add(20, 22) = {CProgram.ada_add(20, 22)}");
Console.WriteLine($"  CProgram.ada_fib(15)     = {CProgram.ada_fib(15)}");
