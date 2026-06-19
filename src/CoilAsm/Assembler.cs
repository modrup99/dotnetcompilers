using System.Globalization;
using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Text;

namespace CoilAsm;

// Turns Coil's stack-IL IR into a real .NET assembly. The IR is one-to-one with
// CIL, so this is a thin assembler: each IR op maps to one ILGenerator emit.
// Every Coil function becomes a `public static` method on the public type
// `CoilProgram`, so C#/VB.NET can call them; types are bound through reference
// assemblies (MetadataLoadContext) so the output references System.Runtime/Console.

internal sealed record MethodIR(string Name, string Ret)
{
    public List<(string Ty, string Nm)> Params { get; } = new();
    public List<(string Ty, string Nm)> Locals { get; } = new();
    public List<string> Ops { get; } = new();
}

public sealed class Assembler
{
    private readonly string _asmName;
    private readonly MetadataLoadContext _mlc;
    private readonly Assembly _core;
    private readonly Type _int, _double, _bool, _string, _void, _object;
    private readonly MethodInfo _concat, _strEquals;
    private readonly Dictionary<(string, bool), MethodInfo> _print = new();   // (type, newline) -> Console method
    private readonly Dictionary<string, MethodBuilder> _methods = new();

    public Assembler(string asmName)
    {
        _asmName = asmName;
        string refDir = ReferenceAssemblies.LocateNet10();
        _mlc = new MetadataLoadContext(new PathAssemblyResolver(Directory.GetFiles(refDir, "*.dll")), "System.Runtime");
        _core = _mlc.LoadFromAssemblyName("System.Runtime");
        _int = _core.GetType("System.Int32")!;
        _double = _core.GetType("System.Double")!;
        _bool = _core.GetType("System.Boolean")!;
        _string = _core.GetType("System.String")!;
        _void = _core.GetType("System.Void")!;
        _object = _core.GetType("System.Object")!;
        _concat = _string.GetMethod("Concat", new[] { _object, _object })!;
        _strEquals = _string.GetMethod("Equals", new[] { _string, _string })!;

        Type console = _mlc.LoadFromAssemblyName("System.Console").GetType("System.Console")!;
        foreach (var (key, t) in new[] { ("int", _int), ("double", _double), ("bool", _bool), ("string", _string) })
        {
            _print[(key, false)] = console.GetMethod("Write", new[] { t })!;
            _print[(key, true)] = console.GetMethod("WriteLine", new[] { t })!;
        }
    }

    private Type Resolve(string t) => t switch
    {
        "int" => _int, "double" => _double, "bool" => _bool, "string" => _string, "void" => _void,
        _ => throw new CoilAsmException($"unknown type '{t}'")
    };

    public void Assemble(string ir, string outputPath, bool asExe)
    {
        var methods = Parse(ir);

        var ab = new PersistedAssemblyBuilder(new AssemblyName(_asmName), _core);
        ModuleBuilder mod = ab.DefineDynamicModule(_asmName);
        TypeBuilder tb = mod.DefineType("CoilProgram", TypeAttributes.Public | TypeAttributes.Class, _object);

        // Pass 1: declare every method (so calls resolve regardless of order).
        foreach (var m in methods)
        {
            var ptypes = m.Params.Select(p => Resolve(p.Ty)).ToArray();
            var mb = tb.DefineMethod(m.Name, MethodAttributes.Public | MethodAttributes.Static, Resolve(m.Ret), ptypes);
            for (int i = 0; i < m.Params.Count; i++) mb.DefineParameter(i + 1, ParameterAttributes.None, m.Params[i].Nm);
            _methods[m.Name] = mb;
        }

        // Pass 2: emit bodies.
        foreach (var m in methods) EmitBody(m);

        MethodBuilder? entry = null;
        if (asExe)
        {
            if (!_methods.TryGetValue("main", out entry))
                throw new CoilAsmException("an executable requires a 'func main()'");
        }

        tb.CreateType();
        WriteAssembly(ab, outputPath, asExe, entry);
    }

    private static List<MethodIR> Parse(string ir)
    {
        var list = new List<MethodIR>();
        MethodIR? cur = null;
        bool inCode = false;
        foreach (var raw in ir.Split('\n'))
        {
            string line = raw.TrimEnd('\r');
            if (line.Length == 0) continue;
            string t = line.TrimStart();
            if (t.StartsWith("method "))
            {
                var p = t.Split(' ');
                cur = new MethodIR(p[1], p[2]); list.Add(cur); inCode = false;
            }
            else if (t.StartsWith("param ")) { var p = t.Split(' '); cur!.Params.Add((p[1], p[2])); }
            else if (t.StartsWith("local ")) { var p = t.Split(' '); cur!.Locals.Add((p[1], p[2])); }
            else if (t == "code") inCode = true;
            else if (t == "endmethod") { cur = null; inCode = false; }
            else if (inCode && cur is not null) cur.Ops.Add(t);
        }
        return list;
    }

    private void EmitBody(MethodIR m)
    {
        var il = _methods[m.Name].GetILGenerator();
        var locals = new Dictionary<string, LocalBuilder>();
        foreach (var (ty, nm) in m.Locals) locals[nm] = il.DeclareLocal(Resolve(ty));
        var argIx = new Dictionary<string, int>();
        for (int i = 0; i < m.Params.Count; i++) argIx[m.Params[i].Nm] = i;
        var labels = new Dictionary<string, Label>();
        foreach (var op in m.Ops)
            if (op.StartsWith("label ")) labels[op[6..].Trim()] = il.DefineLabel();

        foreach (var op in m.Ops) EmitOp(il, op, locals, argIx, labels);

        // default trailing return guarantees valid IL on fall-through paths
        switch (m.Ret)
        {
            case "void": il.Emit(OpCodes.Ret); break;
            case "double": il.Emit(OpCodes.Ldc_R8, 0.0); il.Emit(OpCodes.Ret); break;
            case "string": il.Emit(OpCodes.Ldnull); il.Emit(OpCodes.Ret); break;
            default: il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Ret); break;
        }
    }

    private void EmitOp(ILGenerator il, string op, Dictionary<string, LocalBuilder> locals,
                        Dictionary<string, int> argIx, Dictionary<string, Label> labels)
    {
        int sp = op.IndexOf(' ');
        string code = sp < 0 ? op : op[..sp];
        string arg = sp < 0 ? "" : op[(sp + 1)..];
        switch (code)
        {
            case "ldc.i": il.Emit(OpCodes.Ldc_I4, int.Parse(arg)); break;
            case "ldc.r": il.Emit(OpCodes.Ldc_R8, double.Parse(arg, CultureInfo.InvariantCulture)); break;
            case "ldstr": il.Emit(OpCodes.Ldstr, Unescape(arg)); break;
            case "ldloc": il.Emit(OpCodes.Ldloc, locals[arg]); break;
            case "stloc": il.Emit(OpCodes.Stloc, locals[arg]); break;
            case "ldarg": EmitLdarg(il, argIx[arg]); break;
            case "starg": il.Emit(OpCodes.Starg, (short)argIx[arg]); break;
            case "add": il.Emit(OpCodes.Add); break;
            case "sub": il.Emit(OpCodes.Sub); break;
            case "mul": il.Emit(OpCodes.Mul); break;
            case "div": il.Emit(OpCodes.Div); break;
            case "rem": il.Emit(OpCodes.Rem); break;
            case "neg": il.Emit(OpCodes.Neg); break;
            case "ceq": il.Emit(OpCodes.Ceq); break;
            case "clt": il.Emit(OpCodes.Clt); break;
            case "cgt": il.Emit(OpCodes.Cgt); break;
            case "not": il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Ceq); break;
            case "conv.r8": il.Emit(OpCodes.Conv_R8); break;
            case "box.i": il.Emit(OpCodes.Box, _int); break;
            case "box.r": il.Emit(OpCodes.Box, _double); break;
            case "box.b": il.Emit(OpCodes.Box, _bool); break;
            case "concat": il.Emit(OpCodes.Call, _concat); break;
            case "streq": il.Emit(OpCodes.Call, _strEquals); break;
            case "pop": il.Emit(OpCodes.Pop); break;
            case "ret": il.Emit(OpCodes.Ret); break;
            case "label": il.MarkLabel(labels[arg]); break;
            case "br": il.Emit(OpCodes.Br, labels[arg]); break;
            case "brfalse": il.Emit(OpCodes.Brfalse, labels[arg]); break;
            case "brtrue": il.Emit(OpCodes.Brtrue, labels[arg]); break;
            case "call":
            {
                string name = arg.Split(' ')[0];
                if (!_methods.TryGetValue(name, out var target)) throw new CoilAsmException($"call to undefined function '{name}'");
                il.Emit(OpCodes.Call, target);
                break;
            }
            case "print":
            {
                var p = arg.Split(' ');                  // <type> <nl>
                il.Emit(OpCodes.Call, _print[(p[0], p[1] == "1")]);
                break;
            }
            default: throw new CoilAsmException($"unknown IR op '{op}'");
        }
    }

    private static void EmitLdarg(ILGenerator il, int i)
    {
        switch (i)
        {
            case 0: il.Emit(OpCodes.Ldarg_0); break;
            case 1: il.Emit(OpCodes.Ldarg_1); break;
            case 2: il.Emit(OpCodes.Ldarg_2); break;
            case 3: il.Emit(OpCodes.Ldarg_3); break;
            default: il.Emit(OpCodes.Ldarg_S, (byte)i); break;
        }
    }

    private static string Unescape(string s)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i] == '\\' && i + 1 < s.Length)
            {
                i++;
                sb.Append(s[i] switch { 'n' => '\n', 't' => '\t', 'r' => '\r', '\\' => '\\', var x => x });
            }
            else sb.Append(s[i]);
        }
        return sb.ToString();
    }

    private static void WriteAssembly(PersistedAssemblyBuilder ab, string outputPath, bool asExe, MethodBuilder? entry)
    {
        MetadataBuilder metadata = ab.GenerateMetadata(out BlobBuilder ilStream, out BlobBuilder fieldData);
        var characteristics = asExe ? Characteristics.ExecutableImage : Characteristics.ExecutableImage | Characteristics.Dll;
        MethodDefinitionHandle entryHandle = asExe && entry is not null
            ? MetadataTokens.MethodDefinitionHandle(entry.MetadataToken) : default;
        var peBuilder = new ManagedPEBuilder(
            header: new PEHeaderBuilder(imageCharacteristics: characteristics),
            metadataRootBuilder: new MetadataRootBuilder(metadata),
            ilStream: ilStream, mappedFieldData: fieldData, entryPoint: entryHandle);
        var peBlob = new BlobBuilder();
        peBuilder.Serialize(peBlob);
        using var fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write);
        peBlob.WriteContentTo(fs);
    }
}
