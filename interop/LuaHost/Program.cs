// C# calling functions written in Lua and compiled to .NET IL by our lua -> C -> cc
// toolchain. Lua is dynamically typed: every value is a boxed Val* (an int handle into
// cc's arena). C# runs the Lua chunk once (which registers the global functions), then
// looks each up by name with gget (selector strings via CRuntime.InternString), calls it
// with the call helpers, and unboxes the numeric result with numval.

using CRuntimeLib;

CProgram.main(0, 0);                         // run the chunk: defines the global functions

int add = CProgram.gget(CRuntime.InternString("add"));
int fib = CProgram.gget(CRuntime.InternString("fib"));

double sum = CProgram.numval(CProgram.call2(add, CProgram.mknum(20), CProgram.mknum(22)));
double f15 = CProgram.numval(CProgram.call1(fib, CProgram.mknum(15)));

Console.WriteLine("C# is calling functions compiled from Lua:");
Console.WriteLine($"  add(20, 22) = {sum}");
Console.WriteLine($"  fib(15)     = {f15}");
