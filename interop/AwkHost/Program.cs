// C# calling functions written in AWK and compiled to .NET IL by our awk -> C -> cc
// toolchain. AWK values are dynamically typed strings (with numeric coercion), so each
// AWK function compiles to a public static method f_<name> on CProgram taking and
// returning char* (an int handle into cc's arena). C# pushes string arguments in with
// CRuntime.InternString and reads results back out of the arena, after a one-time
// awk_init() that sets up the special variables.

using CRuntimeLib;

static string CStr(int p)            // read a NUL-terminated C string out of cc's arena
{
    int n = CRuntime.strlen(p);
    var sb = new System.Text.StringBuilder(n);
    for (int i = 0; i < n; i++) sb.Append((char)CRuntime.LdU8(p + i));
    return sb.ToString();
}

CProgram.awk_init();

int greeting = CProgram.f_greet(CRuntime.InternString("Ada"));
int fib15 = CProgram.f_fib(CRuntime.InternString("15"));

Console.WriteLine("C# is calling functions compiled from AWK:");
Console.WriteLine($"  greet(\"Ada\") = {CStr(greeting)}");
Console.WriteLine($"  fib(15)      = {CStr(fib15)}");
