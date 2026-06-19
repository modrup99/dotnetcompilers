// C# calling functions written in Fortran 90 and compiled to .NET IL by our
// fortran -> C -> cc toolchain. CProgram is an ordinary public .NET type; each
// Fortran FUNCTION is a public static method (prefixed f_), so it binds like any
// C# API — with type checking and IntelliSense.

Console.WriteLine("C# is calling functions compiled from Fortran 90:");
Console.WriteLine($"  CProgram.f_add(20, 22)        = {CProgram.f_add(20, 22)}");
Console.WriteLine($"  CProgram.f_fib(15)            = {CProgram.f_fib(15)}");
Console.WriteLine($"  CProgram.f_circle_area(3.0)   = {CProgram.f_circle_area(3.0)}");
