// C# calling functions that were written in C and compiled to IL by `cc`.
// CProgram is an ordinary public .NET type; its methods bind like any C# API.

Console.WriteLine("C# is calling functions compiled from C:");
Console.WriteLine($"  CProgram.fib(20)      = {CProgram.fib(20)}");
Console.WriteLine($"  CProgram.gcd(1071,462)= {CProgram.gcd(1071, 462)}");
Console.WriteLine($"  CProgram.count_primes(100) = {CProgram.count_primes(100)}");
