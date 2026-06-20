// C# driving an object world written in Smalltalk. Smalltalk is "everything is an
// object": every value is a boxed Obj* (an int handle into cc's arena) and you compute by
// sending messages. So C# interops at that level -- it creates instances with mknew,
// sends messages with send(), and boxes/unboxes integers with mkint/intval. Selector
// strings are pushed into the arena with CRuntime.InternString.

using CRuntimeLib;                        // CRuntime.InternString lives here

CProgram.st_boot();                       // initialise nil / true / false

int Counter = 10;                         // first class defined in lib.st -> class id 10
int c = CProgram.mknew(Counter, 1);       // Counter has one instance variable

int Init = CRuntime.InternString("init");
int Add  = CRuntime.InternString("add:");
int Cnt  = CRuntime.InternString("count");

CProgram.send(c, Init, 0, 0);
CProgram.send(c, Add, CProgram.mkint(40), 0);
CProgram.send(c, Add, CProgram.mkint(2), 0);

int result = CProgram.intval(CProgram.send(c, Cnt, 0, 0));
Console.WriteLine("C# sent #init, #add: 40, #add: 2 to a Smalltalk Counter");
Console.WriteLine($"  Counter value = {result}");
