using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace ILForge;

// Shared packaging for the back ends that emit real assemblies (cc and coilasm).
//
// A framework-dependent .NET program is a managed .dll plus a native launcher: the SDK
// ships an "apphost" stub whose embedded app-path placeholder is patched with the name of
// the .dll to boot. Without it a managed PE named .exe cannot be started directly -- it
// has to be run as `dotnet prog.exe` -- so every compiler here produces <name>.dll +
// <name>.runtimeconfig.json + a stamped <name>.exe.
public static class AppHost
{
    // the placeholder the SDK's apphost carries, to be replaced with the app .dll name
    private const string Placeholder = "c3ab8ff13720e8ad9047dd39466b3c8974e592c2fa383d4a3960714caef0c4f2";

    public static void WriteRuntimeConfig(string assemblyPath)
    {
        string configPath = Path.ChangeExtension(assemblyPath, ".runtimeconfig.json");
        var config = new
        {
            runtimeOptions = new
            {
                tfm = "net10.0",
                framework = new { name = "Microsoft.NETCore.App", version = "10.0.0" },
                configProperties = new Dictionary<string, object>()
            }
        };
        File.WriteAllText(configPath, JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true }));
    }

    // Stamp a native launcher next to the managed .dll. Returns the .exe path, or null
    // (with a note on stderr) when no apphost template is installed -- the .dll still runs
    // under `dotnet`, so this is a warning rather than a failure.
    public static string? Stamp(string managedDllPath, string toolName)
    {
        string? template = FindTemplate();
        if (template is null)
        {
            Console.Error.WriteLine($"{toolName}: apphost template not found; run with 'dotnet {Path.GetFileName(managedDllPath)}'");
            return null;
        }
        string exePath = Path.ChangeExtension(managedDllPath, ".exe");
        byte[] host = File.ReadAllBytes(template);
        byte[] mark = Encoding.UTF8.GetBytes(Placeholder);
        int off = IndexOf(host, mark);
        if (off < 0) { Console.Error.WriteLine($"{toolName}: apphost placeholder not found"); return null; }

        byte[] appBin = Encoding.UTF8.GetBytes(Path.GetFileName(managedDllPath));   // relative: exe sits beside dll
        if (appBin.Length >= 1024) { Console.Error.WriteLine($"{toolName}: app path too long for apphost"); return null; }
        Array.Copy(appBin, 0, host, off, appBin.Length);
        for (int i = off + appBin.Length; i < off + mark.Length; i++) host[i] = 0;   // clear the rest of the marker
        File.WriteAllBytes(exePath, host);
        return exePath;
    }

    private static int IndexOf(byte[] hay, byte[] needle)
    {
        for (int i = 0; i <= hay.Length - needle.Length; i++)
        {
            int j = 0; while (j < needle.Length && hay[i + j] == needle[j]) j++;
            if (j == needle.Length) return i;
        }
        return -1;
    }

    private static string? FindTemplate()
    {
        string rtDir = RuntimeEnvironment.GetRuntimeDirectory();                 // <root>/shared/Microsoft.NETCore.App/<ver>/
        string root = Path.GetFullPath(Path.Combine(rtDir, "..", "..", ".."));
        string rid = RuntimeInformation.RuntimeIdentifier;                        // e.g. win-x64
        string hostPacks = Path.Combine(root, "packs", $"Microsoft.NETCore.App.Host.{rid}");
        if (Directory.Exists(hostPacks))
            foreach (var v in Directory.GetDirectories(hostPacks).OrderByDescending(x => x))
            {
                string p = Path.Combine(v, "runtimes", rid, "native", "apphost.exe");
                if (File.Exists(p)) return p;
            }
        string sdks = Path.Combine(root, "sdk");
        if (Directory.Exists(sdks))
            foreach (var v in Directory.GetDirectories(sdks).OrderByDescending(x => x))
            {
                string p = Path.Combine(v, "AppHostTemplate", "apphost.exe");
                if (File.Exists(p)) return p;
            }
        return null;
    }
}
