using System.Reflection;
using CRuntimeLib;

// Headless harness for vi: seed a file, drive the shell -> vi with a scripted key
// stream (normal-mode motions/edits, undo, search, ex :%s and :wq), then read the
// saved file back to prove the editor logic works without a GUI.

string ilsh = args.Length > 0 ? args[0] : "out/ilsh.dll";
string file = @"C:\claude\dotnetcomp\out\vitest.txt";
string fileFwd = "C:/claude/dotnetcomp/out/vitest.txt";   // forward slashes -> one shell WORD
File.WriteAllText(file, "hello world\nsecond line\nthird line\n");

var grid = new TermGrid(80, 24);
var keys = new Queue<int>();
CRuntime.HostOut = b => grid.Process(b);
CRuntime.HostKey = () => keys.Count > 0 ? keys.Dequeue() : -100;
CRuntime.HostCols = () => grid.Cols;
CRuntime.HostRows = () => grid.Rows;
CRuntime.HostClear = () => grid.Process(new byte[] { 27, (byte)'[', (byte)'2', (byte)'J' });
CRuntime.HostGoto = (x, y) => { grid.Cx = x; grid.Cy = y; };

void Type(string s) { foreach (char c in s) keys.Enqueue(c); }
void Enter() => keys.Enqueue(13);
void Esc() => keys.Enqueue(27);

// ---- Run A: x, undo, $, a!, j, dd, :wq ----
Type("vi " + fileFwd); Enter();          // launch vi (absolute path -> independent of cwd)
Type("x");                               // delete 'h'  -> "ello world"
Type("u");                               // undo        -> "hello world"
Type("$");                               // end of line
Type("a"); Type("!"); Esc();             // append '!'  -> "hello world!"
Type("j"); Type("dd");                   // down, delete "second line"
Type(":wq"); Enter();                    // save + quit

Type("cat " + fileFwd); Enter();         // back in shell: show file after run A

// ---- Run B: search /orld, substitute :%s/l/L/, :wq ----
Type("vi " + fileFwd); Enter();
Type("/orld"); Enter();                  // search
Type(":%s/l/L/"); Enter();               // replace every 'l' with 'L'
Type(":wq"); Enter();

Type("cat " + fileFwd); Enter();         // show file after run B
// EOF -> shell exits

var asm = Assembly.LoadFrom(Path.GetFullPath(ilsh));
var prog = asm.GetType("CProgram");
prog.GetMethod("Main", BindingFlags.Public | BindingFlags.Static).Invoke(null, null);

Console.WriteLine("\n=========== file after scripted vi session ===========");
Console.Write(File.ReadAllText(file));
Console.WriteLine("=========== final terminal grid (last screen) ===========");
Console.Write(grid.ToText());
