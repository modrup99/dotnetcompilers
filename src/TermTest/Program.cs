using System.Reflection;
using CRuntimeLib;

// Headless harness: load the compiled ilsh shell, wire CRuntime's console I/O to
// a TermGrid + a scripted key queue, run the shell, and dump the resulting grid.
// This verifies the shell runs "inside the terminal" (VT grid) with the raw line
// editor + history — no GUI needed.

string ilsh = args.Length > 0 ? args[0] : "out/ilsh.dll";
var grid = new TermGrid(80, 24);
var keys = new Queue<int>();

CRuntime.HostOut = b => grid.Process(b);
CRuntime.HostKey = () => keys.Count > 0 ? keys.Dequeue() : -100; // -100 = EOF -> shell exits
CRuntime.HostCols = () => grid.Cols;
CRuntime.HostRows = () => grid.Rows;
CRuntime.HostClear = () => grid.Process(new byte[] { 27, (byte)'[', (byte)'2', (byte)'J' });
CRuntime.HostGoto = (x, y) => { grid.Cx = x; grid.Cy = y; };

void Type(string s) { foreach (char c in s) keys.Enqueue(c); }
void Enter() => keys.Enqueue(13);
const int UP = -1, DOWN = -2;

// A scripted session: run a couple of commands, then recall the previous one
// with Up-arrow, then exercise !! history expansion, then EOF.
Type("X=7"); Enter();
Type("echo X is $X"); Enter();
keys.Enqueue(UP); Enter();              // recall "echo X is $X"
Type("ls shell"); Enter();
Type("!!"); Enter();                    // re-run "ls shell" via history expansion
// EOF -> shell exits

// load ilsh.dll and invoke its synthesized entry point (the shell REPL)
var asm = Assembly.LoadFrom(Path.GetFullPath(ilsh));
var prog = asm.GetType("CProgram");
prog.GetMethod("Main", BindingFlags.Public | BindingFlags.Static).Invoke(null, null);

Console.WriteLine("================ final terminal grid ================");
Console.Write(grid.ToText());
