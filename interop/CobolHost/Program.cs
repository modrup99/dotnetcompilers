// C# calling code written in COBOL and compiled to .NET IL by our cobol -> C -> cc
// toolchain. Each COBOL paragraph becomes a public static method on CProgram (prefixed
// pg_), so C# can invoke it directly. (Passing data in/out would use a LINKAGE SECTION
// and PROCEDURE DIVISION USING, which is outside this subset; here we drive paragraphs
// that DISPLAY.)

Console.WriteLine("C# is calling paragraphs compiled from COBOL:");
CProgram.pg_SHOW_BANNER();
Console.WriteLine("  ...(C# does its own work here)...");
CProgram.pg_SHOW_FOOTER();
