// C# calling into a library produced by the Tiny compiler.
// TinyProgram and its methods are ordinary public static members of a .NET
// assembly, so they bind like any C# API — full IntelliSense, type checking.

Console.WriteLine("C# is calling functions compiled from Tiny:");
Console.WriteLine($"  TinyProgram.add(20, 22)   = {TinyProgram.add(20, 22)}");
Console.WriteLine($"  TinyProgram.fib(15)       = {TinyProgram.fib(15)}");
Console.WriteLine($"  TinyProgram.factorial(6)  = {TinyProgram.factorial(6)}");
