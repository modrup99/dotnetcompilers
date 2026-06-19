using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Text;

namespace TinyC;

// Lowers the Tiny AST to .NET IL using PersistedAssemblyBuilder (the in-box,
// .NET 9+ supported way to emit IL via ILGenerator AND save a real assembly).
//
// Every Tiny function becomes a `public static int` method on a public type
// `TinyProgram`, so C#/VB.NET can call them directly. When building an exe we
// also synthesize a `Main` entry point that invokes the Tiny `main` function.
//
// Types are resolved against .NET *reference* assemblies via MetadataLoadContext
// (not the live runtime), so emitted assemblies reference System.Runtime /
// System.Console — exactly what the C# compiler binds against — instead of the
// implementation assembly System.Private.CoreLib.
public sealed class Emitter
{
    private readonly ProgramNode _program;
    private readonly string _asmName;
    private readonly StringBuilder _ilDump = new();

    private readonly MetadataLoadContext _mlc;
    private readonly Assembly _coreAssembly;
    private readonly Type _intType;
    private readonly Type _voidType;
    private readonly Type _objectType;
    private readonly MethodInfo _writeLineInt;

    // function name -> (builder, parameter names)
    private readonly Dictionary<string, (MethodBuilder Method, IReadOnlyList<string> Params)> _funcs = new();

    public Emitter(ProgramNode program, string asmName)
    {
        _program = program;
        _asmName = asmName;

        string refDir = ReferenceAssemblies.LocateNet10();
        var resolver = new PathAssemblyResolver(Directory.GetFiles(refDir, "*.dll"));
        _mlc = new MetadataLoadContext(resolver, coreAssemblyName: "System.Runtime");

        _coreAssembly = _mlc.LoadFromAssemblyName("System.Runtime");
        _intType = _coreAssembly.GetType("System.Int32")!;
        _voidType = _coreAssembly.GetType("System.Void")!;
        _objectType = _coreAssembly.GetType("System.Object")!;

        Type console = _mlc.LoadFromAssemblyName("System.Console").GetType("System.Console")!;
        _writeLineInt = console.GetMethod("WriteLine", new[] { _intType })!;
    }

    /// <summary>Compiles and writes the assembly. Returns the textual IL dump.</summary>
    public string Emit(string outputPath, bool asExe)
    {
        var ab = new PersistedAssemblyBuilder(new AssemblyName(_asmName), _coreAssembly);
        ModuleBuilder mod = ab.DefineDynamicModule(_asmName);
        TypeBuilder tb = mod.DefineType("TinyProgram",
            TypeAttributes.Public | TypeAttributes.Class, _objectType);

        // Pass 1: declare every function so calls resolve regardless of order.
        foreach (var f in _program.Functions)
        {
            var paramTypes = Enumerable.Repeat(_intType, f.Parameters.Count).ToArray();
            var mb = tb.DefineMethod(f.Name,
                MethodAttributes.Public | MethodAttributes.Static, _intType, paramTypes);
            for (int i = 0; i < f.Parameters.Count; i++)
                mb.DefineParameter(i + 1, ParameterAttributes.None, f.Parameters[i]);
            _funcs[f.Name] = (mb, f.Parameters);
        }

        // Pass 2: emit bodies.
        foreach (var f in _program.Functions)
            EmitFunction(f);

        MethodBuilder? entry = asExe ? EmitEntryPoint(tb) : null;

        tb.CreateType();
        WriteAssembly(ab, outputPath, asExe, entry);
        return _ilDump.ToString();
    }

    private MethodBuilder EmitEntryPoint(TypeBuilder tb)
    {
        if (!_funcs.TryGetValue("main", out var main) || main.Params.Count != 0)
            throw new TinyCompileException("an executable requires a parameterless 'func main()'");

        var mb = tb.DefineMethod("Main",
            MethodAttributes.Public | MethodAttributes.Static, _voidType, Type.EmptyTypes);
        var il = mb.GetILGenerator();
        il.Emit(OpCodes.Call, main.Method); // int result
        il.Emit(OpCodes.Pop);               // discard – output already happened via print
        il.Emit(OpCodes.Ret);
        return mb;
    }

    private void EmitFunction(FuncDecl f)
    {
        var (mb, _) = _funcs[f.Name];
        var il = mb.GetILGenerator();
        _ilDump.AppendLine($".method public static int32 {f.Name}({string.Join(", ", f.Parameters.Select(p => "int32 " + p))})");
        _ilDump.AppendLine("{");

        var ctx = new MethodContext(il, f.Parameters, _intType);
        foreach (var stmt in f.Body.Statements)
            EmitStmt(stmt, ctx);

        // Guarantee a return on every path.
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Ret);
        _ilDump.AppendLine("  // (implicit) ldc.i4.0 ; ret");
        _ilDump.AppendLine("}");
        _ilDump.AppendLine();
    }

    private void EmitStmt(Stmt stmt, MethodContext ctx)
    {
        switch (stmt)
        {
            case LetStmt s:
            {
                var local = ctx.DeclareLocal(s.Name);
                EmitExpr(s.Value, ctx);
                ctx.Il.Emit(OpCodes.Stloc, local);
                _ilDump.AppendLine($"  stloc   {s.Name}");
                break;
            }
            case AssignStmt s:
            {
                EmitExpr(s.Value, ctx);
                ctx.StoreVar(s.Name, _ilDump);
                break;
            }
            case PrintStmt s:
            {
                EmitExpr(s.Value, ctx);
                ctx.Il.Emit(OpCodes.Call, _writeLineInt);
                _ilDump.AppendLine("  call    System.Console::WriteLine(int32)");
                break;
            }
            case ReturnStmt s:
            {
                if (s.Value is not null) EmitExpr(s.Value, ctx);
                else ctx.Il.Emit(OpCodes.Ldc_I4_0);
                ctx.Il.Emit(OpCodes.Ret);
                _ilDump.AppendLine("  ret");
                break;
            }
            case IfStmt s:
            {
                var elseLabel = ctx.Il.DefineLabel();
                var endLabel = ctx.Il.DefineLabel();
                EmitExpr(s.Cond, ctx);
                ctx.Il.Emit(OpCodes.Brfalse, elseLabel);
                _ilDump.AppendLine("  brfalse else");
                foreach (var st in s.Then.Statements) EmitStmt(st, ctx);
                ctx.Il.Emit(OpCodes.Br, endLabel);
                ctx.Il.MarkLabel(elseLabel);
                if (s.Else is not null)
                    foreach (var st in s.Else.Statements) EmitStmt(st, ctx);
                ctx.Il.MarkLabel(endLabel);
                break;
            }
            case WhileStmt s:
            {
                var top = ctx.Il.DefineLabel();
                var done = ctx.Il.DefineLabel();
                ctx.Il.MarkLabel(top);
                EmitExpr(s.Cond, ctx);
                ctx.Il.Emit(OpCodes.Brfalse, done);
                _ilDump.AppendLine("  brfalse done   // while");
                foreach (var st in s.Body.Statements) EmitStmt(st, ctx);
                ctx.Il.Emit(OpCodes.Br, top);
                ctx.Il.MarkLabel(done);
                break;
            }
            case ExprStmt s:
            {
                EmitExpr(s.Expr, ctx);
                ctx.Il.Emit(OpCodes.Pop); // discard value
                _ilDump.AppendLine("  pop");
                break;
            }
            default:
                throw new TinyCompileException($"cannot emit statement {stmt.GetType().Name}");
        }
    }

    private void EmitExpr(Expr expr, MethodContext ctx)
    {
        switch (expr)
        {
            case IntLit e:
                ctx.Il.Emit(OpCodes.Ldc_I4, e.Value);
                _ilDump.AppendLine($"  ldc.i4  {e.Value}");
                break;
            case VarRef e:
                ctx.LoadVar(e.Name, _ilDump);
                break;
            case Binary e:
                EmitBinary(e, ctx);
                break;
            case Call e:
            {
                if (!_funcs.TryGetValue(e.Name, out var target))
                    throw new TinyCompileException($"call to undefined function '{e.Name}'");
                if (target.Params.Count != e.Args.Count)
                    throw new TinyCompileException($"'{e.Name}' expects {target.Params.Count} args, got {e.Args.Count}");
                foreach (var a in e.Args) EmitExpr(a, ctx);
                ctx.Il.Emit(OpCodes.Call, target.Method);
                _ilDump.AppendLine($"  call    {e.Name}");
                break;
            }
            default:
                throw new TinyCompileException($"cannot emit expression {expr.GetType().Name}");
        }
    }

    private void EmitBinary(Binary e, MethodContext ctx)
    {
        EmitExpr(e.Left, ctx);
        EmitExpr(e.Right, ctx);
        var il = ctx.Il;
        switch (e.Op)
        {
            case "+": il.Emit(OpCodes.Add); _ilDump.AppendLine("  add"); break;
            case "-": il.Emit(OpCodes.Sub); _ilDump.AppendLine("  sub"); break;
            case "*": il.Emit(OpCodes.Mul); _ilDump.AppendLine("  mul"); break;
            case "/": il.Emit(OpCodes.Div); _ilDump.AppendLine("  div"); break;
            case "%": il.Emit(OpCodes.Rem); _ilDump.AppendLine("  rem"); break;
            case "==": il.Emit(OpCodes.Ceq); _ilDump.AppendLine("  ceq"); break;
            case "!=": il.Emit(OpCodes.Ceq); EmitNot(il); break;
            case "<": il.Emit(OpCodes.Clt); _ilDump.AppendLine("  clt"); break;
            case ">": il.Emit(OpCodes.Cgt); _ilDump.AppendLine("  cgt"); break;
            case "<=": il.Emit(OpCodes.Cgt); EmitNot(il); break;   // !(a > b)
            case ">=": il.Emit(OpCodes.Clt); EmitNot(il); break;   // !(a < b)
            default:
                throw new TinyCompileException($"unknown operator '{e.Op}'");
        }
    }

    private void EmitNot(ILGenerator il)
    {
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Ceq);
        _ilDump.AppendLine("  ldc.i4.0 ; ceq   // logical not");
    }

    // Serialize the in-memory assembly to a PE file. For an exe we set the
    // executable PE characteristics and the entry-point token; for a library
    // the default (Dll) characteristics apply.
    private static void WriteAssembly(PersistedAssemblyBuilder ab, string outputPath, bool asExe, MethodBuilder? entry)
    {
        MetadataBuilder metadata = ab.GenerateMetadata(out BlobBuilder ilStream, out BlobBuilder fieldData);

        // ExecutableImage means "no unresolved externals" and is set on BOTH
        // exes and dlls; a library additionally sets the Dll bit.
        var characteristics = asExe
            ? Characteristics.ExecutableImage
            : Characteristics.ExecutableImage | Characteristics.Dll;
        var peHeader = new PEHeaderBuilder(imageCharacteristics: characteristics);

        MethodDefinitionHandle entryHandle = asExe && entry is not null
            ? MetadataTokens.MethodDefinitionHandle(entry.MetadataToken)
            : default;

        var peBuilder = new ManagedPEBuilder(
            header: peHeader,
            metadataRootBuilder: new MetadataRootBuilder(metadata),
            ilStream: ilStream,
            mappedFieldData: fieldData,
            entryPoint: entryHandle);

        var peBlob = new BlobBuilder();
        peBuilder.Serialize(peBlob);

        using var fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write);
        peBlob.WriteContentTo(fs);
    }
}

// Per-method codegen state: parameter slots + declared locals.
internal sealed class MethodContext
{
    public ILGenerator Il { get; }
    private readonly Type _intType;
    private readonly Dictionary<string, int> _params = new();
    private readonly Dictionary<string, LocalBuilder> _locals = new();

    public MethodContext(ILGenerator il, IReadOnlyList<string> parameters, Type intType)
    {
        Il = il;
        _intType = intType;
        for (int i = 0; i < parameters.Count; i++)
            _params[parameters[i]] = i;
    }

    public LocalBuilder DeclareLocal(string name)
    {
        var local = Il.DeclareLocal(_intType);
        _locals[name] = local;
        return local;
    }

    public void LoadVar(string name, StringBuilder dump)
    {
        if (_locals.TryGetValue(name, out var local)) { Il.Emit(OpCodes.Ldloc, local); dump.AppendLine($"  ldloc   {name}"); }
        else if (_params.TryGetValue(name, out var idx)) { Il.Emit(OpCodes.Ldarg, idx); dump.AppendLine($"  ldarg   {name}"); }
        else throw new TinyCompileException($"undefined variable '{name}'");
    }

    public void StoreVar(string name, StringBuilder dump)
    {
        if (_locals.TryGetValue(name, out var local)) { Il.Emit(OpCodes.Stloc, local); dump.AppendLine($"  stloc   {name}"); }
        else if (_params.TryGetValue(name, out var idx)) { Il.Emit(OpCodes.Starg, idx); dump.AppendLine($"  starg   {name}"); }
        else throw new TinyCompileException($"cannot assign undefined variable '{name}' (use 'let' first)");
    }
}
