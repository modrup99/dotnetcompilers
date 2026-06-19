// C# host that calls functions from a Coil-compiled assembly. CoilProgram's
// methods are public static with real .NET signatures, so they're ordinary calls.
Console.WriteLine($"add(2, 3)        = {CoilProgram.add(2, 3)}");
Console.WriteLine($"fib(15)          = {CoilProgram.fib(15)}");
Console.WriteLine($"circleArea(3.0)  = {CoilProgram.circleArea(3.0)}");
Console.WriteLine($"greet(\"C#\")      = {CoilProgram.greet("C#")}");
