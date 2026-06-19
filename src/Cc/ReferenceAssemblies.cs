namespace Cc;

// Locates the net10.0 reference-assembly folder so the compiler binds against
// the framework's public surface (System.Runtime, System.Console, ...) rather
// than the live runtime's implementation assembly. (Same approach as tinyc.)
internal static class ReferenceAssemblies
{
    public static string LocateNet10()
    {
        foreach (var root in CandidateDotnetRoots())
        {
            string refPacks = Path.Combine(root, "packs", "Microsoft.NETCore.App.Ref");
            if (!Directory.Exists(refPacks)) continue;

            var match = Directory.GetDirectories(refPacks)
                .Select(d => Path.Combine(d, "ref", "net10.0"))
                .Where(Directory.Exists)
                .OrderByDescending(p => p, StringComparer.OrdinalIgnoreCase)
                .FirstOrDefault();

            if (match is not null) return match;
        }

        throw new CCompileException(
            "could not locate net10.0 reference assemblies " +
            "(looked under <dotnet root>/packs/Microsoft.NETCore.App.Ref/*/ref/net10.0)");
    }

    private static IEnumerable<string> CandidateDotnetRoots()
    {
        string? proc = Environment.ProcessPath;
        if (proc is not null)
        {
            string? dir = Path.GetDirectoryName(proc);
            if (dir is not null && File.Exists(Path.Combine(dir, "dotnet.exe")))
                yield return dir;
        }
        foreach (var env in new[] { "DOTNET_ROOT", "DOTNET_ROOT(x86)" })
        {
            string? v = Environment.GetEnvironmentVariable(env);
            if (!string.IsNullOrEmpty(v)) yield return v;
        }
        yield return @"C:\Program Files\dotnet";
        yield return "/usr/share/dotnet";
        yield return "/usr/local/share/dotnet";
    }
}

public sealed class CCompileException(string message) : Exception(message);
