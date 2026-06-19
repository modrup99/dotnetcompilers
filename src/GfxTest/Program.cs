using System.Reflection;
using CRuntimeLib;

// Headless harness for graphics programs: wire CRuntime's gfx_* hooks to an
// in-memory framebuffer + a fixed mouse, run the program for a few frames, then
// render the framebuffer to ASCII so we can verify it without a GUI.

string prog = args.Length > 0 ? args[0] : "out/xeyes.dll";
int mouseX = args.Length > 1 ? int.Parse(args[1]) : 410;   // mouse at far right by default
int mouseY = args.Length > 2 ? int.Parse(args[2]) : 130;

int[] fb = null; int W = 0, H = 0; int frames = 0;
CRuntime.HostGfxOpen = (w, h, f, title) => { W = w; H = h; fb = f; Console.WriteLine($"gfx_open {w}x{h} \"{title}\""); };
CRuntime.HostGfxPresent = () => frames++;
CRuntime.HostGfxMouseX = () => mouseX;
CRuntime.HostGfxMouseY = () => mouseY;
CRuntime.HostGfxQuit = () => frames >= 1 ? 1 : 0;          // let it draw one full frame, then quit

var asm = Assembly.LoadFrom(Path.GetFullPath(prog));
asm.GetType("CProgram").GetMethod("Main", BindingFlags.Public | BindingFlags.Static).Invoke(null, null);

Console.WriteLine($"frames presented: {frames}");
if (fb == null) { Console.WriteLine("no framebuffer!"); return; }

// classify pixels: count colours, then downsample to ASCII
int white = 0, dark = 0, other = 0;
foreach (int p in fb)
{
    int r = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF;
    if (r > 200 && g > 200 && b > 200) white++;
    else if (r < 60 && g < 60 && b < 60) dark++;
    else other++;
}
Console.WriteLine($"pixels: white(sclera)={white}  dark(rim+pupil)={dark}  bg={other}");

int cols = 84, rows = 30;
Console.WriteLine(new string('-', cols));
for (int ry = 0; ry < rows; ry++)
{
    var sb = new System.Text.StringBuilder(cols);
    for (int rx = 0; rx < cols; rx++)
    {
        int x = rx * W / cols, y = ry * H / rows;
        int p = fb[y * W + x];
        int r = (p >> 16) & 0xFF, g = (p >> 8) & 0xFF, b = p & 0xFF;
        char c = (r < 60 && g < 60 && b < 60) ? '#' : (r > 200 && g > 200 && b > 200) ? '.' : ' ';
        sb.Append(c);
    }
    Console.WriteLine(sb.ToString());
}
Console.WriteLine(new string('-', cols));
