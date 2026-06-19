using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;

namespace Cc;

// Lowers the C AST to .NET IL using the flat-arena memory model (see CRuntime).
// A C pointer is an int address into CRuntime's byte arena. Structs/unions are
// byte layouts (offsets), enum constants fold to ints, and function pointers are
// small int ids dispatched through generated switch methods.
public sealed class Emitter
{
    private readonly TranslationUnit _tu;
    private readonly string _asmName;
    private readonly IReadOnlyList<string> _documents;

    // PDB sequence points: per method, (IL offset, line, column, document index).
    private readonly Dictionary<MethodBuilder, List<(int Off, int Line, int Col, int Doc)>> _seq = new();
    private List<(int Off, int Line, int Col, int Doc)>? _curSeq;

    private readonly MetadataLoadContext _mlc;
    private readonly Assembly _core;
    private readonly Type _int, _void, _object, _string, _double, _long;

    private readonly MethodInfo _ldU8, _ldI32, _stI8, _stI32, _memcpy, _memset;
    private readonly MethodInfo _ldF64, _ldF32, _stF64, _stF32, _ldI64, _stI64;
    private readonly MethodInfo _stackSave, _stackAlloc, _stackRestore, _dataAlloc, _internString;
    private readonly Dictionary<string, MethodInfo> _libc = new();

    private readonly Dictionary<string, FuncSym> _funcs = new();
    private readonly Dictionary<string, VarSym> _globals = new();
    private readonly Dictionary<string, FieldBuilder> _strLits = new();
    private readonly List<(GlobalVar G, FieldBuilder Addr)> _globalList = new();
    private readonly Dictionary<DeclStmt, VarSym> _staticOf = new();
    private readonly List<(FieldBuilder Addr, CType Type, Init? Init)> _staticInits = new();
    private readonly Dictionary<string, StructLayout> _layouts = new();
    private readonly Dictionary<(int N, bool V), MethodBuilder> _dispatchers = new();

    private TypeBuilder _tb = null!;

    private sealed record FuncSym(MethodBuilder Method, CType Return, IReadOnlyList<CType> Params, int Id);
    private sealed class StructLayout
    {
        public int Size, Align;
        public readonly Dictionary<string, (int Off, CType Type)> Fields = new();
    }

    private static readonly Dictionary<string, int> StdStreams = new() { ["stdin"] = 1, ["stdout"] = 2, ["stderr"] = 3 };

    public Emitter(TranslationUnit tu, string asmName, IReadOnlyList<string>? documents = null)
    {
        _tu = tu;
        _asmName = asmName;
        _documents = documents ?? new[] { "src.c" };

        string refDir = ReferenceAssemblies.LocateNet10();
        string rtPath = Path.Combine(AppContext.BaseDirectory, "CRuntime.dll");
        if (!File.Exists(rtPath)) throw new CCompileException($"CRuntime.dll not found next to the compiler ({rtPath})");

        var files = Directory.GetFiles(refDir, "*.dll").Append(rtPath);
        _mlc = new MetadataLoadContext(new PathAssemblyResolver(files), coreAssemblyName: "System.Runtime");
        _core = _mlc.LoadFromAssemblyName("System.Runtime");
        _int = _core.GetType("System.Int32")!;
        _void = _core.GetType("System.Void")!;
        _object = _core.GetType("System.Object")!;
        _string = _core.GetType("System.String")!;
        _double = _core.GetType("System.Double")!;
        _long = _core.GetType("System.Int64")!;

        Type rt = _mlc.LoadFromAssemblyPath(rtPath).GetType("CRuntimeLib.CRuntime")!;
        MethodInfo M(string n, params Type[] ps) => rt.GetMethod(n, ps) ?? throw new CCompileException($"CRuntime.{n} missing");
        _ldU8 = M("LdU8", _int); _ldI32 = M("LdI32", _int);
        _stI8 = M("StI8", _int, _int); _stI32 = M("StI32", _int, _int);
        _ldF64 = M("LdF64", _int); _ldF32 = M("LdF32", _int);
        _stF64 = M("StF64", _int, _double); _stF32 = M("StF32", _int, _double);
        _ldI64 = M("LdI64", _int); _stI64 = M("StI64", _int, _long);
        _memcpy = M("memcpy", _int, _int, _int);
        _memset = M("memset", _int, _int, _int);
        _stackSave = M("StackSave"); _stackAlloc = M("StackAlloc", _int); _stackRestore = M("StackRestore", _int);
        _dataAlloc = M("DataAlloc", _int); _internString = M("InternString", _string);

        foreach (var m in rt.GetMethods(BindingFlags.Public | BindingFlags.Static))
            if (m.DeclaringType == rt) _libc[m.Name] = m;
    }

    public string Emit(string outputPath, bool asExe)
    {
        var ab = new PersistedAssemblyBuilder(new AssemblyName(_asmName), _core);
        ModuleBuilder mod = ab.DefineDynamicModule(_asmName);
        _tb = mod.DefineType("CProgram", TypeAttributes.Public | TypeAttributes.Class, _object);

        foreach (var g in _tu.Decls.OfType<GlobalVar>())
        {
            if (_globals.ContainsKey(g.Name)) continue;
            var addr = _tb.DefineField("g_" + g.Name, _int, FieldAttributes.Public | FieldAttributes.Static);
            _globals[g.Name] = new VarSym(Storage.Global, 0, addr, g.Type);
            _globalList.Add((g, addr));
        }
        int nextId = 1;
        foreach (var f in _tu.Decls.OfType<FuncDef>())
        {
            if (f.Body is null || _funcs.ContainsKey(f.Name)) continue;
            if (f.Variadic) throw new CCompileException($"variadic user function '{f.Name}' is not supported yet");
            bool sret = f.ReturnType is StructType; // struct returns use a hidden return-buffer pointer
            var ps = f.Params.Select(p => MapType(p.Type)).ToArray();
            var sig = sret ? new[] { _int }.Concat(ps).ToArray() : ps;
            var mb = _tb.DefineMethod(f.Name, MethodAttributes.Public | MethodAttributes.Static,
                sret ? _void : MapType(f.ReturnType), sig);
            int poff = sret ? 1 : 0;
            if (sret) mb.DefineParameter(1, ParameterAttributes.None, "__ret");
            for (int i = 0; i < f.Params.Count; i++) mb.DefineParameter(i + 1 + poff, ParameterAttributes.None, f.Params[i].Name);
            _funcs[f.Name] = new FuncSym(mb, f.ReturnType, f.Params.Select(p => p.Type).ToList(), nextId++);
        }

        CollectStatics();
        EmitStaticCtor();
        foreach (var f in _tu.Decls.OfType<FuncDef>())
            if (f.Body is not null) EmitFunctionBody(f);
        EmitDispatchers();

        MethodBuilder? entry = asExe ? EmitEntryPoint() : null;
        _tb.CreateType();
        WriteAssembly(ab, outputPath, asExe, entry);
        return string.Empty;
    }

    private Type MapType(CType t) => t.IsVoid ? _void : t.IsFloating ? _double : t.IsLong ? _long : _int;
    private static bool IsFloat(CType t) => t.IsFloating;
    // numeric stack class: 0 = int32 (int/char/uint/pointer), 1 = int64 (long), 2 = float64
    private static int NumClass(CType t) => t.IsFloating ? 2 : t.IsLong ? 1 : 0;

    // ---- sizes / layout ------------------------------------------------
    private int SizeOf(CType t) => t switch
    {
        PrimType { Kind: BaseKind.Char } => 1,
        PrimType { Kind: BaseKind.Int } => 4,
        PrimType { Kind: BaseKind.UInt } => 4,
        PrimType { Kind: BaseKind.Float } => 4,
        PrimType { Kind: BaseKind.Double } => 8,
        PrimType { Kind: BaseKind.Long } => 8,
        PrimType { Kind: BaseKind.ULong } => 8,
        PrimType { Kind: BaseKind.Void } => 1,
        PointerType or FuncType => 4,
        ArrayType a => SizeOf(a.Element) * (a.Length ?? 0),
        StructType s => Layout(s.Tag).Size,
        _ => 4
    };
    private int AlignOf(CType t) => t switch
    {
        PrimType { Kind: BaseKind.Char } => 1,
        PrimType { Kind: BaseKind.Double or BaseKind.Long or BaseKind.ULong } => 8,
        ArrayType a => AlignOf(a.Element),
        StructType s => Layout(s.Tag).Align,
        _ => 4
    };
    private int SlotSize(CType t) => t is ArrayType or StructType ? (SizeOf(t) + 3) & ~3 : Math.Max(4, SizeOf(t));
    private static CType Decay(CType t) => t switch
    {
        ArrayType a => new PointerType(a.Element),
        FuncType f => new PointerType(f),
        _ => t
    };

    private StructLayout Layout(string tag)
    {
        if (_layouts.TryGetValue(tag, out var l)) return l;
        if (!_tu.Structs.TryGetValue(tag, out var def)) throw new CCompileException($"unknown struct/union '{tag}'");
        l = new StructLayout { Align = 1 };
        _layouts[tag] = l; // memoize before recursion
        int cursor = 0;
        foreach (var fld in def.Fields)
        {
            int a = AlignOf(fld.Type), sz = SizeOf(fld.Type);
            if (def.IsUnion) { l.Fields[fld.Name] = (0, fld.Type); l.Size = Math.Max(l.Size, sz); }
            else { cursor = (cursor + a - 1) & ~(a - 1); l.Fields[fld.Name] = (cursor, fld.Type); cursor += sz; }
            l.Align = Math.Max(l.Align, a);
        }
        if (!def.IsUnion) l.Size = cursor;
        l.Size = (l.Size + l.Align - 1) & ~(l.Align - 1);
        return l;
    }

    private (int Off, CType Type) Field(string tag, string name)
    {
        if (!Layout(tag).Fields.TryGetValue(name, out var f)) throw new CCompileException($"struct '{tag}' has no member '{name}'");
        return f;
    }

    // `static` locals get one persistent data-segment slot, initialised once.
    private void CollectStatics()
    {
        void Walk(Stmt? s)
        {
            switch (s)
            {
                case CompoundStmt c: foreach (var i in c.Items) Walk(i); break;
                case DeclStmt d when d.IsStatic:
                    var f = _tb.DefineField($"g_s{_staticOf.Count}", _int, FieldAttributes.Static | FieldAttributes.Private);
                    _staticOf[d] = new VarSym(Storage.Global, 0, f, d.Type);
                    _staticInits.Add((f, d.Type, d.Init));
                    break;
                case IfStmt i: Walk(i.Then); Walk(i.Else); break;
                case WhileStmt w: Walk(w.Body); break;
                case DoWhileStmt dw: Walk(dw.Body); break;
                case ForStmt fr: Walk(fr.Init); Walk(fr.Body); break;
                case SwitchStmt sw: Walk(sw.Body); break;
                case LabelStmt lb: Walk(lb.Body); break;
            }
        }
        foreach (var fd in _tu.Decls.OfType<FuncDef>()) Walk(fd.Body);
    }

    // ---- static constructor --------------------------------------------
    private void EmitStaticCtor()
    {
        InternStringLiterals();
        if (_globalList.Count == 0 && _strLits.Count == 0 && _staticInits.Count == 0) return;

        var il = _tb.DefineTypeInitializer().GetILGenerator();
        var ctx = new FuncCtx(il, CType.Void);
        foreach (var (lit, fld) in _strLits.Select(kv => (kv.Key, kv.Value)))
        {
            il.Emit(OpCodes.Ldstr, lit); il.Emit(OpCodes.Call, _internString); il.Emit(OpCodes.Stsfld, fld);
        }
        foreach (var (g, addr) in _globalList)
        {
            il.Emit(OpCodes.Ldc_I4, Math.Max(SizeOf(g.Type), 4));
            il.Emit(OpCodes.Call, _dataAlloc);
            il.Emit(OpCodes.Stsfld, addr);
            if (g.Init is not null)
                EmitInitializer(g.Type, g.Init, ctx, () => il.Emit(OpCodes.Ldsfld, addr));
        }
        foreach (var (addr, type, init) in _staticInits)
        {
            il.Emit(OpCodes.Ldc_I4, Math.Max(SizeOf(type), 4));
            il.Emit(OpCodes.Call, _dataAlloc);
            il.Emit(OpCodes.Stsfld, addr);
            if (init is not null) EmitInitializer(type, init, ctx, () => il.Emit(OpCodes.Ldsfld, addr));
        }
        il.Emit(OpCodes.Ret);
    }

    private void InternStringLiterals()
    {
        void Scan(Expr? e)
        {
            switch (e)
            {
                case StrLit s when !_strLits.ContainsKey(s.Value):
                    _strLits[s.Value] = _tb.DefineField($"s_{_strLits.Count}", _int, FieldAttributes.Static | FieldAttributes.Private); break;
                case Unary u: Scan(u.Operand); break;
                case PreInc p: Scan(p.Target); break;
                case PostInc p: Scan(p.Target); break;
                case Binary b: Scan(b.Left); Scan(b.Right); break;
                case Assign a: Scan(a.Target); Scan(a.Value); break;
                case Conditional q: Scan(q.Cond); Scan(q.Then); Scan(q.Else); break;
                case Index ix: Scan(ix.Base); Scan(ix.Idx); break;
                case Member m: Scan(m.Base); break;
                case Cast c: Scan(c.Operand); break;
                case SizeofExpr se: Scan(se.Operand); break;
                case CallExpr c: Scan(c.Callee); foreach (var a in c.Args) Scan(a); break;
            }
        }
        void ScanInit(Init? init)
        {
            if (init is InitExpr ie) Scan(ie.E);
            else if (init is InitList l) foreach (var it in l.Items) ScanInit(it);
            else if (init is Designated d) ScanInit(d.Inner);
        }
        void ScanStmt(Stmt? s)
        {
            switch (s)
            {
                case CompoundStmt c: foreach (var i in c.Items) ScanStmt(i); break;
                case DeclStmt d: ScanInit(d.Init); break;
                case ExprStmt e: Scan(e.Expr); break;
                case ReturnStmt r: Scan(r.Value); break;
                case IfStmt i: Scan(i.Cond); ScanStmt(i.Then); ScanStmt(i.Else); break;
                case WhileStmt w: Scan(w.Cond); ScanStmt(w.Body); break;
                case DoWhileStmt dw: ScanStmt(dw.Body); Scan(dw.Cond); break;
                case ForStmt f: ScanStmt(f.Init); Scan(f.Cond); Scan(f.Post); ScanStmt(f.Body); break;
                case SwitchStmt sw: Scan(sw.Value); ScanStmt(sw.Body); break;
                case LabelStmt lb: ScanStmt(lb.Body); break;
            }
        }
        foreach (var g in _tu.Decls.OfType<GlobalVar>()) ScanInit(g.Init);
        foreach (var f in _tu.Decls.OfType<FuncDef>()) ScanStmt(f.Body);
    }

    private MethodBuilder EmitEntryPoint()
    {
        if (!_funcs.TryGetValue("main", out var main)) throw new CCompileException("an executable requires a 'main' function");
        int np = main.Params.Count;
        if (np != 0 && np != 2) throw new CCompileException("main must be 'int main(void)' or 'int main(int argc, char **argv)'");
        // entry takes string[] only when main wants argc/argv, so the runtime hands it the args
        Type[] entryParams = np == 2 ? new[] { _string.MakeArrayType() } : Type.EmptyTypes;
        var mb = _tb.DefineMethod("Main", MethodAttributes.Public | MethodAttributes.Static, _int, entryParams);
        var il = mb.GetILGenerator();
        if (np == 2)
        {
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Call, _libc["rt_make_argv"]); il.Emit(OpCodes.Pop);   // build argv in the arena
            il.Emit(OpCodes.Call, _libc["rt_argc"]);                               // push argc
            il.Emit(OpCodes.Call, _libc["rt_argv"]);                               // push argv (char**)
        }
        il.Emit(OpCodes.Call, main.Method);
        if (main.Return.IsVoid) il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Ret);
        return mb;
    }

    // ---- function bodies -----------------------------------------------
    private void EmitFunctionBody(FuncDef f)
    {
        var mb = _funcs[f.Name].Method;
        _curSeq = _seq[mb] = new();
        var il = mb.GetILGenerator();
        var ctx = new FuncCtx(il, f.ReturnType);

        int cursor = 0;
        foreach (var p in f.Params) { ctx.ParamSlot[p] = cursor; cursor += SlotSize(Decay(p.Type)); }
        cursor = LayoutLocals(f.Body!, ctx, cursor);
        ctx.FrameSize = cursor;

        bool sret = f.ReturnType is StructType;
        int argBase = sret ? 1 : 0;

        ctx.SavedSp = il.DeclareLocal(_int);
        ctx.Fp = il.DeclareLocal(_int);
        il.Emit(OpCodes.Call, _stackSave); il.Emit(OpCodes.Stloc, ctx.SavedSp);
        il.Emit(OpCodes.Ldc_I4, ctx.FrameSize); il.Emit(OpCodes.Call, _stackAlloc); il.Emit(OpCodes.Stloc, ctx.Fp);
        if (!f.ReturnType.IsVoid && !sret) ctx.RetVal = il.DeclareLocal(MapType(f.ReturnType));

        ctx.PushScope();
        for (int i = 0; i < f.Params.Count; i++)
        {
            var p = f.Params[i];
            if (string.IsNullOrEmpty(p.Name)) continue;
            var pt = Decay(p.Type);
            ctx.Bind(p.Name, new VarSym(Storage.Frame, ctx.ParamSlot[p], null, pt));
            il.Emit(OpCodes.Ldloc, ctx.Fp); EmitAddOffset(il, ctx.ParamSlot[p]);
            il.Emit(OpCodes.Ldarg, i + argBase);
            if (pt is StructType) { il.Emit(OpCodes.Ldc_I4, SizeOf(pt)); il.Emit(OpCodes.Call, _memcpy); il.Emit(OpCodes.Pop); }
            else { il.Emit(OpCodes.Call, StoreOp(pt)); il.Emit(OpCodes.Pop); }
        }

        ctx.Epilogue = il.DefineLabel();
        EmitStmt(f.Body!, ctx);
        ctx.PopScope();

        il.MarkLabel(ctx.Epilogue);
        il.Emit(OpCodes.Ldloc, ctx.SavedSp); il.Emit(OpCodes.Call, _stackRestore);
        if (!f.ReturnType.IsVoid && !sret) il.Emit(OpCodes.Ldloc, ctx.RetVal!);
        il.Emit(OpCodes.Ret);
    }

    private int LayoutLocals(Stmt s, FuncCtx ctx, int cursor)
    {
        switch (s)
        {
            case CompoundStmt c: foreach (var i in c.Items) cursor = LayoutLocals(i, ctx, cursor); break;
            case DeclStmt d: if (!d.IsStatic) { ctx.DeclSlot[d] = cursor; cursor += SlotSize(d.Type); } break;
            case IfStmt i: cursor = LayoutLocals(i.Then, ctx, cursor); if (i.Else is not null) cursor = LayoutLocals(i.Else, ctx, cursor); break;
            case WhileStmt w: cursor = LayoutLocals(w.Body, ctx, cursor); break;
            case DoWhileStmt dw: cursor = LayoutLocals(dw.Body, ctx, cursor); break;
            case ForStmt f: if (f.Init is not null) cursor = LayoutLocals(f.Init, ctx, cursor); cursor = LayoutLocals(f.Body, ctx, cursor); break;
            case SwitchStmt sw: cursor = LayoutLocals(sw.Body, ctx, cursor); break;
            case LabelStmt lb: cursor = LayoutLocals(lb.Body, ctx, cursor); break;
        }
        return cursor;
    }

    private static void EmitAddOffset(ILGenerator il, int off) { if (off != 0) { il.Emit(OpCodes.Ldc_I4, off); il.Emit(OpCodes.Add); } }

    // ---- statements ----------------------------------------------------
    private void EmitStmt(Stmt s, FuncCtx ctx)
    {
        var il = ctx.Il;
        // record a sequence point at the start of each executable statement
        if (_curSeq != null && s.Line > 0 && s is not CompoundStmt and not CaseLabel and not DefaultLabel and not LabelStmt)
            _curSeq.Add((il.ILOffset, s.Line, s.Col < 1 ? 1 : s.Col, s.Doc));
        switch (s)
        {
            case CompoundStmt c:
                ctx.PushScope(); foreach (var i in c.Items) EmitStmt(i, ctx); ctx.PopScope();
                break;

            case DeclStmt d:
                if (d.IsStatic) { ctx.Bind(d.Name, _staticOf[d]); break; } // persistent; initialised in cctor
                ctx.Bind(d.Name, new VarSym(Storage.Frame, ctx.DeclSlot[d], null, d.Type));
                if (d.Init is not null)
                    EmitInitializer(d.Type, d.Init, ctx, () => EmitAddressOfVar(d.Name, ctx, out _));
                break;

            case ExprStmt e:
                if (e.Expr is not null) { var t = EmitExpr(e.Expr, ctx); if (!t.IsVoid) il.Emit(OpCodes.Pop); }
                break;

            case ReturnStmt r:
                if (r.Value is not null && ctx.ReturnType is StructType)
                {
                    il.Emit(OpCodes.Ldarg_0);              // hidden return-buffer pointer
                    EmitValue(r.Value, ctx);               // struct value = its address
                    il.Emit(OpCodes.Ldc_I4, SizeOf(ctx.ReturnType)); il.Emit(OpCodes.Call, _memcpy); il.Emit(OpCodes.Pop);
                }
                else if (r.Value is not null && !ctx.ReturnType.IsVoid) { var vt = EmitExpr(r.Value, ctx); Coerce(vt, ctx.ReturnType, il); il.Emit(OpCodes.Stloc, ctx.RetVal!); }
                else if (r.Value is not null) { var t = EmitExpr(r.Value, ctx); if (!t.IsVoid) il.Emit(OpCodes.Pop); }
                il.Emit(OpCodes.Br, ctx.Epilogue);
                break;

            case IfStmt i:
            {
                var elseL = il.DefineLabel(); var endL = il.DefineLabel();
                EmitCond(i.Cond, ctx); il.Emit(OpCodes.Brfalse, i.Else is null ? endL : elseL);
                EmitStmt(i.Then, ctx);
                if (i.Else is not null) { il.Emit(OpCodes.Br, endL); il.MarkLabel(elseL); EmitStmt(i.Else, ctx); }
                il.MarkLabel(endL);
                break;
            }

            case WhileStmt w:
            {
                var top = il.DefineLabel(); var end = il.DefineLabel();
                il.MarkLabel(top); EmitCond(w.Cond, ctx); il.Emit(OpCodes.Brfalse, end);
                ctx.PushLoop(end, top); EmitStmt(w.Body, ctx); ctx.PopLoop();
                il.Emit(OpCodes.Br, top); il.MarkLabel(end);
                break;
            }

            case DoWhileStmt dw:
            {
                var top = il.DefineLabel(); var cond = il.DefineLabel(); var end = il.DefineLabel();
                il.MarkLabel(top);
                ctx.PushLoop(end, cond); EmitStmt(dw.Body, ctx); ctx.PopLoop();
                il.MarkLabel(cond); EmitCond(dw.Cond, ctx); il.Emit(OpCodes.Brtrue, top); il.MarkLabel(end);
                break;
            }

            case ForStmt fr:
            {
                ctx.PushScope();
                if (fr.Init is not null) EmitStmt(fr.Init, ctx);
                var top = il.DefineLabel(); var post = il.DefineLabel(); var end = il.DefineLabel();
                il.MarkLabel(top);
                if (fr.Cond is not null) { EmitCond(fr.Cond, ctx); il.Emit(OpCodes.Brfalse, end); }
                ctx.PushLoop(end, post); EmitStmt(fr.Body, ctx); ctx.PopLoop();
                il.MarkLabel(post);
                if (fr.Post is not null) { var t = EmitExpr(fr.Post, ctx); if (!t.IsVoid) il.Emit(OpCodes.Pop); }
                il.Emit(OpCodes.Br, top); il.MarkLabel(end);
                ctx.PopScope();
                break;
            }

            case SwitchStmt sw: EmitSwitch(sw, ctx); break;

            case GotoStmt g: il.Emit(OpCodes.Br, ctx.GetLabel(g.Label)); break;
            case LabelStmt lb: il.MarkLabel(ctx.GetLabel(lb.Name)); EmitStmt(lb.Body, ctx); break;

            case CaseLabel: case DefaultLabel:
                throw new CCompileException("'case'/'default' must appear directly inside a switch body");

            case BreakStmt: il.Emit(OpCodes.Br, ctx.BreakLabel()); break;
            case ContinueStmt: il.Emit(OpCodes.Br, ctx.ContinueLabel()); break;

            default: throw new CCompileException($"cannot emit statement {s.GetType().Name}");
        }
    }

    private void EmitSwitch(SwitchStmt sw, FuncCtx ctx)
    {
        var il = ctx.Il;
        var tmp = il.DeclareLocal(_int);
        EmitValue(sw.Value, ctx); il.Emit(OpCodes.Stloc, tmp);

        var items = sw.Body is CompoundStmt cs ? (IReadOnlyList<Stmt>)cs.Items : new[] { sw.Body };
        var end = il.DefineLabel();
        var labelMap = new Dictionary<Stmt, Label>();
        Label? defLabel = null;
        foreach (var it in items)
        {
            if (it is CaseLabel cl) { var L = il.DefineLabel(); labelMap[it] = L; il.Emit(OpCodes.Ldloc, tmp); il.Emit(OpCodes.Ldc_I4, cl.Value); il.Emit(OpCodes.Beq, L); }
            else if (it is DefaultLabel) { var L = il.DefineLabel(); labelMap[it] = L; defLabel = L; }
        }
        il.Emit(OpCodes.Br, defLabel ?? end);

        ctx.PushBreak(end); ctx.PushScope();
        foreach (var it in items)
            if (labelMap.TryGetValue(it, out var L)) il.MarkLabel(L);
            else EmitStmt(it, ctx);
        ctx.PopScope(); ctx.PopBreak();
        il.MarkLabel(end);
    }

    // ---- initializers --------------------------------------------------
    private void EmitInitializer(CType type, Init init, FuncCtx ctx, Action emitBase)
    {
        var il = ctx.Il;
        if (type is not (ArrayType or StructType))
        {
            emitBase(); var vt = EmitExpr(InitScalar(init), ctx); Coerce(vt, type, il);
            il.Emit(OpCodes.Call, StoreOp(type)); il.Emit(OpCodes.Pop);
            return;
        }
        if (init is InitExpr ie)
        {
            if (type is StructType)
            {
                emitBase(); EmitValue(ie.E, ctx);
                il.Emit(OpCodes.Ldc_I4, SizeOf(type)); il.Emit(OpCodes.Call, _memcpy); il.Emit(OpCodes.Pop);
                return;
            }
            if (type is ArrayType a && ie.E is StrLit s && a.Element is PrimType { Kind: BaseKind.Char })
            {
                var bt0 = il.DeclareLocal(_int); emitBase(); il.Emit(OpCodes.Stloc, bt0);
                ZeroAggregate(bt0, SizeOf(type), il); StoreStringBytes(bt0, 0, s.Value, il);
                return;
            }
            throw new CCompileException("invalid initializer for an aggregate");
        }
        var bt = il.DeclareLocal(_int); emitBase(); il.Emit(OpCodes.Stloc, bt);
        ZeroAggregate(bt, SizeOf(type), il);
        FillInit(bt, 0, type, (InitList)init, ctx);
    }

    private void ZeroAggregate(LocalBuilder bt, int size, ILGenerator il)
    {
        il.Emit(OpCodes.Ldloc, bt); il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Ldc_I4, size);
        il.Emit(OpCodes.Call, _memset); il.Emit(OpCodes.Pop);
    }

    private void StoreStringBytes(LocalBuilder bt, int off, string s, ILGenerator il)
    {
        for (int k = 0; k < s.Length; k++)
        {
            il.Emit(OpCodes.Ldloc, bt); EmitAddOffset(il, off + k);
            il.Emit(OpCodes.Ldc_I4, (int)(byte)s[k]); il.Emit(OpCodes.Call, _stI8); il.Emit(OpCodes.Pop);
        }
    }

    private void FillInit(LocalBuilder bt, int off, CType type, InitList list, FuncCtx ctx)
    {
        if (type is ArrayType a)
        {
            int esz = SizeOf(a.Element), cur = 0;
            foreach (var item in list.Items)
            {
                if (item is Designated { Index: int ix }) cur = ix;
                FillElem(bt, off + cur * esz, a.Element, Unwrap(item), ctx);
                cur++;
            }
        }
        else if (type is StructType st)
        {
            var fields = _tu.Structs[st.Tag].Fields;
            int cur = 0;
            foreach (var item in list.Items)
            {
                if (item is Designated { Field: string fn }) cur = FieldIndex(fields, fn);
                if (cur >= fields.Count) break;
                var (foff, ft) = Field(st.Tag, fields[cur].Name);
                FillElem(bt, off + foff, ft, Unwrap(item), ctx);
                cur++;
            }
        }
        else throw new CCompileException("brace initializer applied to a scalar");
    }

    private static Init Unwrap(Init i) => i is Designated d ? d.Inner : i;
    private static int FieldIndex(IReadOnlyList<FieldDecl> fields, string name)
    {
        for (int i = 0; i < fields.Count; i++) if (fields[i].Name == name) return i;
        throw new CCompileException($"no such field '{name}' in initializer");
    }

    private void FillElem(LocalBuilder bt, int off, CType elemType, Init item, FuncCtx ctx)
    {
        var il = ctx.Il;
        if (elemType is ArrayType or StructType)
        {
            if (item is InitList l) { FillInit(bt, off, elemType, l, ctx); return; }
            if (item is InitExpr ie && elemType is ArrayType ea && ie.E is StrLit s && ea.Element is PrimType { Kind: BaseKind.Char })
            { StoreStringBytes(bt, off, s.Value, il); return; }
            if (item is InitExpr ie2 && elemType is StructType)
            {
                il.Emit(OpCodes.Ldloc, bt); EmitAddOffset(il, off); EmitValue(ie2.E, ctx);
                il.Emit(OpCodes.Ldc_I4, SizeOf(elemType)); il.Emit(OpCodes.Call, _memcpy); il.Emit(OpCodes.Pop);
                return;
            }
            throw new CCompileException("invalid aggregate element initializer");
        }
        il.Emit(OpCodes.Ldloc, bt); EmitAddOffset(il, off);
        var vt = EmitExpr(InitScalar(item), ctx); Coerce(vt, elemType, il);
        il.Emit(OpCodes.Call, StoreOp(elemType)); il.Emit(OpCodes.Pop);
    }

    private static Expr InitScalar(Init init) => init switch
    {
        InitExpr ie => ie.E,
        InitList { Items: [InitExpr one] } => one.E,
        _ => throw new CCompileException("expected a scalar initializer")
    };

    // ---- expressions ---------------------------------------------------
    private void EmitValue(Expr e, FuncCtx ctx) { if (EmitExpr(e, ctx).IsVoid) throw new CCompileException("a void value cannot be used in an expression"); }

    private CType EmitExpr(Expr e, FuncCtx ctx)
    {
        var il = ctx.Il;
        switch (e)
        {
            case IntLit n: il.Emit(OpCodes.Ldc_I4, n.Value); return CType.Int;
            case LongLit ln: il.Emit(OpCodes.Ldc_I8, ln.Value); return CType.Long;
            case FloatLit fl: il.Emit(OpCodes.Ldc_R8, fl.Value); return CType.Double;
            case StrLit s: il.Emit(OpCodes.Ldsfld, _strLits[s.Value]); return new PointerType(CType.Char);

            case Ident id:
            {
                if (ctx.TryLookup(id.Name, out var v) || _globals.TryGetValue(id.Name, out v!))
                {
                    if (v.Type is ArrayType a) { EmitAddressOf(e, ctx, out _); return new PointerType(a.Element); }
                    if (v.Type is StructType) { EmitAddressOf(e, ctx, out _); return v.Type; }
                    EmitAddressOf(e, ctx, out var t); il.Emit(OpCodes.Call, LoadOp(t)); return t;
                }
                if (_tu.EnumConstants.TryGetValue(id.Name, out int ev)) { il.Emit(OpCodes.Ldc_I4, ev); return CType.Int; }
                if (_funcs.TryGetValue(id.Name, out var fs)) { il.Emit(OpCodes.Ldc_I4, fs.Id); return FuncPtr(fs); }
                if (StdStreams.TryGetValue(id.Name, out int h)) { il.Emit(OpCodes.Ldc_I4, h); return CType.Int; }
                throw new CCompileException($"undefined identifier '{id.Name}'");
            }

            case Unary { Op: "&" } u:
                if (u.Operand is Ident fid && !IsVariable(fid.Name, ctx) && _funcs.TryGetValue(fid.Name, out var f2))
                { il.Emit(OpCodes.Ldc_I4, f2.Id); return FuncPtr(f2); }
                EmitAddressOf(u.Operand, ctx, out var pt); return new PointerType(pt);

            case Unary { Op: "*" } u:
            {
                var t = Decay(TypeOf(u.Operand, ctx));
                if (t is not PointerType p) throw new CCompileException("cannot dereference a non-pointer");
                EmitValue(u.Operand, ctx);
                if (p.Pointee is ArrayType pa) return new PointerType(pa.Element);
                if (p.Pointee is StructType) return p.Pointee;
                il.Emit(OpCodes.Call, LoadOp(p.Pointee)); return p.Pointee;
            }

            case Unary u:
                EmitValue(u.Operand, ctx);
                switch (u.Op) { case "-": il.Emit(OpCodes.Neg); break; case "+": break; case "~": il.Emit(OpCodes.Not); break; case "!": il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Ceq); break; }
                return CType.Int;

            case Cast c:
            {
                var ot = EmitExpr(c.Operand, ctx);
                if (c.Type is PrimType { Kind: BaseKind.Char }) { EmitConvCls(ot, 0, il); il.Emit(OpCodes.Conv_U1); }
                else EmitConvCls(ot, NumClass(c.Type), il);
                return c.Type;
            }

            case Index ix:
            {
                EmitElementAddress(ix, ctx, out var elem);
                if (elem is ArrayType ea) return new PointerType(ea.Element);
                if (elem is StructType) return elem;
                il.Emit(OpCodes.Call, LoadOp(elem)); return elem;
            }

            case Member m:
            {
                EmitMemberAddress(m, ctx, out var ft);
                if (ft is ArrayType fa) return new PointerType(fa.Element);
                if (ft is StructType) return ft;
                il.Emit(OpCodes.Call, LoadOp(ft)); return ft;
            }

            case SizeofType st: il.Emit(OpCodes.Ldc_I4, SizeOf(st.Type)); return CType.Int;
            case SizeofExpr se: il.Emit(OpCodes.Ldc_I4, SizeOf(TypeOf(se.Operand, ctx))); return CType.Int;

            case Binary b: return EmitBinary(b, ctx);
            case Assign a: return EmitAssign(a, ctx);
            case PreInc p: return EmitIncDec(p.Target, p.Op, true, ctx);
            case PostInc p: return EmitIncDec(p.Target, p.Op, false, ctx);

            case Conditional q:
            {
                var elseL = il.DefineLabel(); var endL = il.DefineLabel();
                EmitValue(q.Cond, ctx); il.Emit(OpCodes.Brfalse, elseL);
                var t = TypeOf(q.Then, ctx); EmitValue(q.Then, ctx); il.Emit(OpCodes.Br, endL);
                il.MarkLabel(elseL); EmitValue(q.Else, ctx); il.MarkLabel(endL);
                return t;
            }

            case Comma cm:
            {
                var lt = EmitExpr(cm.Left, ctx);
                if (!lt.IsVoid) il.Emit(OpCodes.Pop);
                return EmitExpr(cm.Right, ctx);
            }

            case CallExpr c: return EmitCall(c, ctx);
            default: throw new CCompileException($"cannot emit expression {e.GetType().Name}");
        }
    }

    private static PointerType FuncPtr(FuncSym fs) => new(new FuncType(fs.Return, fs.Params, false));
    private bool IsVariable(string name, FuncCtx ctx) => ctx.TryLookup(name, out _) || _globals.ContainsKey(name);

    private CType EmitBinary(Binary b, FuncCtx ctx)
    {
        var il = ctx.Il;
        if (b.Op is "&&" or "||")
        {
            var sc = il.DefineLabel(); var end = il.DefineLabel();
            EmitCond(b.Left, ctx); il.Emit(b.Op == "&&" ? OpCodes.Brfalse : OpCodes.Brtrue, sc);
            EmitCond(b.Right, ctx); il.Emit(b.Op == "&&" ? OpCodes.Brfalse : OpCodes.Brtrue, sc);
            il.Emit(b.Op == "&&" ? OpCodes.Ldc_I4_1 : OpCodes.Ldc_I4_0); il.Emit(OpCodes.Br, end);
            il.MarkLabel(sc); il.Emit(b.Op == "&&" ? OpCodes.Ldc_I4_0 : OpCodes.Ldc_I4_1); il.MarkLabel(end);
            return CType.Int;
        }

        var lt = Decay(TypeOf(b.Left, ctx)); var rt = Decay(TypeOf(b.Right, ctx));
        bool lp = lt is PointerType, rp = rt is PointerType;
        if (b.Op == "+" && (lp || rp))
        {
            var (pe, ie, pTy) = lp ? (b.Left, b.Right, (PointerType)lt) : (b.Right, b.Left, (PointerType)rt);
            EmitValue(pe, ctx); EmitValue(ie, ctx); EmitScale(il, SizeOf(pTy.Pointee)); il.Emit(OpCodes.Add); return pTy;
        }
        if (b.Op == "-" && lp)
        {
            EmitValue(b.Left, ctx); EmitValue(b.Right, ctx);
            if (rp) { il.Emit(OpCodes.Sub); EmitDiv(il, SizeOf(((PointerType)lt).Pointee)); return CType.Int; }
            EmitScale(il, SizeOf(((PointerType)lt).Pointee)); il.Emit(OpCodes.Sub); return lt;
        }

        // unified numeric path: promote both operands to the wider class
        // (int32 -> int64 -> float64). Shift counts stay int32.
        int cls = Math.Max(NumClass(lt), NumClass(rt));
        bool uns = lt.IsUnsigned || rt.IsUnsigned;
        bool fp = cls == 2;
        bool isShift = b.Op is "<<" or ">>";
        if (fp && b.Op is "&" or "|" or "^" or "<<" or ">>")
            throw new CCompileException($"operator '{b.Op}' is not valid on floating-point values");

        var vl = EmitExpr(b.Left, ctx); EmitConvCls(vl, cls, il);
        var vr = EmitExpr(b.Right, ctx); EmitConvCls(vr, isShift ? 0 : cls, il);
        switch (b.Op)
        {
            case "+": il.Emit(OpCodes.Add); break; case "-": il.Emit(OpCodes.Sub); break;
            case "*": il.Emit(OpCodes.Mul); break;
            case "/": il.Emit(uns && !fp ? OpCodes.Div_Un : OpCodes.Div); break;
            case "%": il.Emit(uns && !fp ? OpCodes.Rem_Un : OpCodes.Rem); break;
            case "&": il.Emit(OpCodes.And); break; case "|": il.Emit(OpCodes.Or); break; case "^": il.Emit(OpCodes.Xor); break;
            case "<<": il.Emit(OpCodes.Shl); break;
            case ">>": il.Emit(uns ? OpCodes.Shr_Un : OpCodes.Shr); break;
            case "==": il.Emit(OpCodes.Ceq); return CType.Int;
            case "!=": il.Emit(OpCodes.Ceq); Not(il); return CType.Int;
            case "<": il.Emit(uns && !fp ? OpCodes.Clt_Un : OpCodes.Clt); return CType.Int;
            case ">": il.Emit(uns && !fp ? OpCodes.Cgt_Un : OpCodes.Cgt); return CType.Int;
            case "<=": il.Emit(uns && !fp ? OpCodes.Cgt_Un : OpCodes.Cgt); Not(il); return CType.Int;
            case ">=": il.Emit(uns && !fp ? OpCodes.Clt_Un : OpCodes.Clt); Not(il); return CType.Int;
            default: throw new CCompileException($"unknown operator '{b.Op}'");
        }
        return cls == 2 ? CType.Double : cls == 1 ? (uns ? CType.ULong : CType.Long) : (uns ? CType.UInt : CType.Int);
    }

    private static void EmitScale(ILGenerator il, int size) { if (size != 1) { il.Emit(OpCodes.Ldc_I4, size); il.Emit(OpCodes.Mul); } }
    private static void EmitDiv(ILGenerator il, int size) { if (size != 1) { il.Emit(OpCodes.Ldc_I4, size); il.Emit(OpCodes.Div); } }
    private static void Not(ILGenerator il) { il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Ceq); }

    private CType EmitAssign(Assign a, FuncCtx ctx)
    {
        var il = ctx.Il;
        var tt = TypeOf(a.Target, ctx);
        if (tt is StructType)
        {
            EmitAddressOf(a.Target, ctx, out _);
            EmitValue(a.Value, ctx);
            il.Emit(OpCodes.Ldc_I4, SizeOf(tt)); il.Emit(OpCodes.Call, _memcpy);
            return tt;
        }
        EmitAddressOf(a.Target, ctx, out var t);
        var vt = EmitExpr(a.Value, ctx); Coerce(vt, t, il);
        il.Emit(OpCodes.Call, StoreOp(t));
        return t;
    }

    private CType EmitIncDec(Expr target, string op, bool prefix, FuncCtx ctx)
    {
        var il = ctx.Il;
        EmitAddressOf(target, ctx, out var t);
        var addr = il.DeclareLocal(_int); var oldv = il.DeclareLocal(MapType(t));
        il.Emit(OpCodes.Stloc, addr);
        il.Emit(OpCodes.Ldloc, addr); il.Emit(OpCodes.Call, LoadOp(t)); il.Emit(OpCodes.Stloc, oldv);
        il.Emit(OpCodes.Ldloc, addr); il.Emit(OpCodes.Ldloc, oldv);
        if (Decay(t) is PointerType pp) il.Emit(OpCodes.Ldc_I4, SizeOf(pp.Pointee));   // ptr step = sizeof element
        else if (NumClass(t) == 1) il.Emit(OpCodes.Ldc_I8, 1L);
        else if (NumClass(t) == 2) il.Emit(OpCodes.Ldc_R8, 1.0);
        else il.Emit(OpCodes.Ldc_I4_1);
        il.Emit(op == "+" ? OpCodes.Add : OpCodes.Sub);
        il.Emit(OpCodes.Call, StoreOp(t));
        if (!prefix) { il.Emit(OpCodes.Pop); il.Emit(OpCodes.Ldloc, oldv); }
        return t;
    }

    private CType EmitCall(CallExpr c, FuncCtx ctx)
    {
        var il = ctx.Il;
        if (c.Callee is Ident id && !IsVariable(id.Name, ctx))
        {
            if (_funcs.TryGetValue(id.Name, out var sym))
            {
                if (sym.Params.Count != c.Args.Count) throw new CCompileException($"'{id.Name}' expects {sym.Params.Count} args, got {c.Args.Count}");
                if (sym.Return is StructType st)
                {
                    // sret: allocate a return buffer, pass it as the hidden first arg.
                    var buf = il.DeclareLocal(_int);
                    il.Emit(OpCodes.Ldc_I4, SizeOf(st)); il.Emit(OpCodes.Call, _stackAlloc); il.Emit(OpCodes.Stloc, buf);
                    il.Emit(OpCodes.Ldloc, buf);
                    for (int i = 0; i < c.Args.Count; i++) { var at = EmitExpr(c.Args[i], ctx); Coerce(at, Decay(sym.Params[i]), il); }
                    il.Emit(OpCodes.Call, sym.Method);
                    il.Emit(OpCodes.Ldloc, buf); // result is the buffer (struct value)
                    return sym.Return;
                }
                for (int i = 0; i < c.Args.Count; i++) { var at = EmitExpr(c.Args[i], ctx); Coerce(at, Decay(sym.Params[i]), il); }
                il.Emit(OpCodes.Call, sym.Method);
                return sym.Return;
            }
            if (_libc.TryGetValue(id.Name, out var m)) return EmitLibcCall(id.Name, m, c, ctx);
            throw new CCompileException($"call to undefined function '{id.Name}'");
        }

        // indirect call through a function pointer
        var ct = Decay(TypeOf(c.Callee, ctx));
        int n; bool v;
        if (ct is PointerType { Pointee: FuncType fty }) { n = fty.Params.Count; v = fty.Return.IsVoid; }
        else { n = c.Args.Count; v = false; }
        if (c.Args.Count != n) throw new CCompileException($"indirect call expects {n} args, got {c.Args.Count}");
        foreach (var a in c.Args) EmitValue(a, ctx);
        EmitValue(c.Callee, ctx); // the function id
        il.Emit(OpCodes.Call, GetDispatcher(n, v));
        return v ? CType.Void : CType.Int;
    }

    private CType EmitLibcCall(string name, MethodInfo m, CallExpr c, FuncCtx ctx)
    {
        var il = ctx.Il;
        var ps = m.GetParameters();
        bool variadic = ps.Length > 0 && ps[^1].ParameterType.IsArray && ps[^1].ParameterType.GetElementType()!.FullName == "System.Object";
        int fixedCount = variadic ? ps.Length - 1 : ps.Length;
        if (variadic ? c.Args.Count < fixedCount : c.Args.Count != fixedCount)
            throw new CCompileException($"'{name}' argument count mismatch (expected {(variadic ? fixedCount + "+" : fixedCount.ToString())}, got {c.Args.Count})");

        for (int i = 0; i < fixedCount; i++) { var at = EmitExpr(c.Args[i], ctx); CoerceToClr(at, ps[i].ParameterType, il); }
        if (variadic)
        {
            int extra = c.Args.Count - fixedCount;
            il.Emit(OpCodes.Ldc_I4, extra); il.Emit(OpCodes.Newarr, _object);
            for (int i = 0; i < extra; i++)
            {
                il.Emit(OpCodes.Dup); il.Emit(OpCodes.Ldc_I4, i);
                var at = EmitExpr(c.Args[fixedCount + i], ctx);
                il.Emit(OpCodes.Box, at.IsFloating ? _double : at.IsLong ? _long : _int); il.Emit(OpCodes.Stelem_Ref);
            }
        }
        il.Emit(OpCodes.Call, m);
        return m.ReturnType.FullName switch { "System.Void" => CType.Void, "System.Double" => CType.Double, "System.Int64" => CType.Long, _ => CType.Int };
    }

    // ---- function-pointer dispatchers ----------------------------------
    private MethodBuilder GetDispatcher(int n, bool retVoid)
    {
        if (_dispatchers.TryGetValue((n, retVoid), out var mb)) return mb;
        var ps = Enumerable.Repeat(_int, n + 1).ToArray(); // n args + id
        mb = _tb.DefineMethod($"__call_{n}_{(retVoid ? "v" : "i")}", MethodAttributes.Private | MethodAttributes.Static,
            retVoid ? _void : _int, ps);
        _dispatchers[(n, retVoid)] = mb;
        return mb;
    }

    private void EmitDispatchers()
    {
        foreach (var ((n, retVoid), mb) in _dispatchers)
        {
            var il = mb.GetILGenerator();
            foreach (var fs in _funcs.Values.Where(s => s.Params.Count == n && s.Return.IsVoid == retVoid))
            {
                var next = il.DefineLabel();
                il.Emit(OpCodes.Ldarg, n); il.Emit(OpCodes.Ldc_I4, fs.Id); il.Emit(OpCodes.Bne_Un, next);
                for (int i = 0; i < n; i++) il.Emit(OpCodes.Ldarg, i);
                il.Emit(OpCodes.Call, fs.Method);
                il.Emit(OpCodes.Ret);
                il.MarkLabel(next);
            }
            if (!retVoid) il.Emit(OpCodes.Ldc_I4_0);
            il.Emit(OpCodes.Ret);
        }
    }

    // ---- addresses -----------------------------------------------------
    private void EmitAddressOf(Expr e, FuncCtx ctx, out CType pointee)
    {
        switch (e)
        {
            case Ident id: EmitAddressOfVar(id.Name, ctx, out pointee); return;
            case Unary { Op: "*" } u:
            {
                var t = Decay(TypeOf(u.Operand, ctx));
                if (t is not PointerType p) throw new CCompileException("cannot dereference a non-pointer");
                EmitValue(u.Operand, ctx); pointee = p.Pointee; return;
            }
            case Index ix: EmitElementAddress(ix, ctx, out pointee); return;
            case Member m: EmitMemberAddress(m, ctx, out pointee); return;
            default: throw new CCompileException($"expression is not an lvalue ({e.GetType().Name})");
        }
    }

    private void EmitAddressOfVar(string name, FuncCtx ctx, out CType type)
    {
        var il = ctx.Il;
        if (ctx.TryLookup(name, out var v) || _globals.TryGetValue(name, out v!))
        {
            type = v.Type;
            if (v.Storage == Storage.Frame) { il.Emit(OpCodes.Ldloc, ctx.Fp); EmitAddOffset(il, v.FrameOffset); }
            else il.Emit(OpCodes.Ldsfld, v.GlobalAddr!);
            return;
        }
        throw new CCompileException($"'{name}' is not an addressable variable");
    }

    private void EmitElementAddress(Index ix, FuncCtx ctx, out CType elem)
    {
        var il = ctx.Il;
        var bt = Decay(TypeOf(ix.Base, ctx));
        if (bt is not PointerType p) throw new CCompileException("cannot index a non-pointer/array");
        elem = p.Pointee;
        EmitValue(ix.Base, ctx);
        var it = EmitExpr(ix.Idx, ctx); if (it.IsFloating) il.Emit(OpCodes.Conv_I4);
        EmitScale(il, SizeOf(elem)); il.Emit(OpCodes.Add);
    }

    private void EmitMemberAddress(Member m, FuncCtx ctx, out CType fieldType)
    {
        var il = ctx.Il;
        string tag;
        if (m.Arrow)
        {
            var t = Decay(TypeOf(m.Base, ctx));
            if (t is not PointerType { Pointee: StructType st }) throw new CCompileException($"'->' requires a pointer to struct");
            EmitValue(m.Base, ctx); tag = st.Tag;
        }
        else
        {
            EmitAddressOf(m.Base, ctx, out var bt);
            if (bt is not StructType st2) throw new CCompileException($"'.' requires a struct");
            tag = st2.Tag;
        }
        var (off, ft) = Field(tag, m.Name);
        EmitAddOffset(il, off);
        fieldType = ft;
    }

    private MethodInfo LoadOp(CType t) => t switch
    {
        PrimType { Kind: BaseKind.Char } => _ldU8,
        PrimType { Kind: BaseKind.Double } => _ldF64,
        PrimType { Kind: BaseKind.Float } => _ldF32,
        PrimType { Kind: BaseKind.Long or BaseKind.ULong } => _ldI64,
        _ => _ldI32
    };
    private MethodInfo StoreOp(CType t) => t switch
    {
        PrimType { Kind: BaseKind.Char } => _stI8,
        PrimType { Kind: BaseKind.Double } => _stF64,
        PrimType { Kind: BaseKind.Float } => _stF32,
        PrimType { Kind: BaseKind.Long or BaseKind.ULong } => _stI64,
        _ => _stI32
    };

    // Convert a stack value of representation class(from) to class(to).
    private static void EmitConvCls(CType from, int toCls, ILGenerator il)
    {
        int fc = NumClass(from);
        if (fc == toCls) return;
        switch (toCls)
        {
            case 0: il.Emit(OpCodes.Conv_I4); break;                                   // <- i64/f64
            case 1: il.Emit(fc == 0 && from.IsUnsigned ? OpCodes.Conv_U8 : OpCodes.Conv_I8); break;
            case 2: il.Emit(OpCodes.Conv_R8); break;                                   // <- i32/i64
        }
    }
    private static void Coerce(CType from, CType to, ILGenerator il) => EmitConvCls(from, NumClass(to), il);
    private static void CoerceToClr(CType from, Type clr, ILGenerator il)
        => EmitConvCls(from, clr.FullName == "System.Double" ? 2 : clr.FullName == "System.Int64" ? 1 : 0, il);

    // emit a value, then reduce it to an int32 truth value usable by brtrue/brfalse.
    private void EmitCond(Expr e, FuncCtx ctx)
    {
        var t = EmitExpr(e, ctx);
        int c = NumClass(t);
        if (c == 1) { ctx.Il.Emit(OpCodes.Ldc_I8, 0L); ctx.Il.Emit(OpCodes.Ceq); ctx.Il.Emit(OpCodes.Ldc_I4_0); ctx.Il.Emit(OpCodes.Ceq); }
        else if (c == 2) { ctx.Il.Emit(OpCodes.Ldc_R8, 0.0); ctx.Il.Emit(OpCodes.Ceq); ctx.Il.Emit(OpCodes.Ldc_I4_0); ctx.Il.Emit(OpCodes.Ceq); }
    }

    // ---- static type inference -----------------------------------------
    private CType TypeOf(Expr e, FuncCtx ctx) => e switch
    {
        IntLit => CType.Int,
        LongLit => CType.Long,
        FloatLit => CType.Double,
        StrLit s => new ArrayType(CType.Char, s.Value.Length + 1),
        Ident id => LookupType(id.Name, ctx),
        Unary { Op: "&", Operand: Ident fn } when !IsVariable(fn.Name, ctx) && _funcs.ContainsKey(fn.Name) => FuncPtr(_funcs[fn.Name]),
        Unary { Op: "&" } u => new PointerType(TypeOf(u.Operand, ctx)),
        Unary { Op: "*" } u => Decay(TypeOf(u.Operand, ctx)) is PointerType p ? p.Pointee : CType.Int,
        Unary => CType.Int,
        Cast c => c.Type,
        Index ix => Decay(TypeOf(ix.Base, ctx)) is PointerType p ? p.Pointee : CType.Int,
        Member m => MemberType(m, ctx),
        SizeofType or SizeofExpr => CType.Int,
        Binary b => BinaryType(b, ctx),
        Assign a => TypeOf(a.Target, ctx),
        PreInc p => Decay(TypeOf(p.Target, ctx)),
        PostInc p => Decay(TypeOf(p.Target, ctx)),
        Conditional q => TypeOf(q.Then, ctx),
        Comma cm => TypeOf(cm.Right, ctx),
        CallExpr c => CallType(c, ctx),
        _ => CType.Int
    };

    private CType MemberType(Member m, FuncCtx ctx)
    {
        var bt = m.Arrow ? Decay(TypeOf(m.Base, ctx)) : TypeOf(m.Base, ctx);
        string tag = m.Arrow ? ((bt as PointerType)?.Pointee as StructType)?.Tag ?? throw new CCompileException("'->' needs pointer to struct")
                             : (bt as StructType)?.Tag ?? throw new CCompileException("'.' needs a struct");
        return Field(tag, m.Name).Type;
    }

    private CType BinaryType(Binary b, FuncCtx ctx)
    {
        if (b.Op is "&&" or "||" or "==" or "!=" or "<" or "<=" or ">" or ">=") return CType.Int;
        var lt = Decay(TypeOf(b.Left, ctx)); var rt = Decay(TypeOf(b.Right, ctx));
        if (b.Op == "+") { if (lt is PointerType) return lt; if (rt is PointerType) return rt; }
        if (b.Op == "-") { if (lt is PointerType && rt is PointerType) return CType.Int; if (lt is PointerType) return lt; }
        int cls = Math.Max(NumClass(lt), NumClass(rt));
        bool uns = lt.IsUnsigned || rt.IsUnsigned;
        return cls == 2 ? CType.Double : cls == 1 ? (uns ? CType.ULong : CType.Long) : (uns ? CType.UInt : CType.Int);
    }

    private CType CallType(CallExpr c, FuncCtx ctx)
    {
        if (c.Callee is Ident id && !IsVariable(id.Name, ctx))
        {
            if (_funcs.TryGetValue(id.Name, out var s)) return s.Return;
            if (_libc.TryGetValue(id.Name, out var m))
                return m.ReturnType.FullName switch { "System.Void" => CType.Void, "System.Double" => CType.Double, "System.Int64" => CType.Long, _ => CType.Int };
        }
        return Decay(TypeOf(c.Callee, ctx)) is PointerType { Pointee: FuncType ft } ? ft.Return : CType.Int;
    }

    private CType LookupType(string name, FuncCtx ctx)
    {
        if (ctx.TryLookup(name, out var v) || _globals.TryGetValue(name, out v!)) return v.Type;
        if (_tu.EnumConstants.ContainsKey(name)) return CType.Int;
        if (_funcs.TryGetValue(name, out var fs)) return FuncPtr(fs);
        if (StdStreams.ContainsKey(name)) return CType.Int;
        throw new CCompileException($"undefined identifier '{name}'");
    }

    private void WriteAssembly(PersistedAssemblyBuilder ab, string outputPath, bool asExe, MethodBuilder? entry)
    {
        MetadataBuilder metadata = ab.GenerateMetadata(out BlobBuilder ilStream, out BlobBuilder fieldData);
        var entryHandle = asExe && entry is not null ? MetadataTokens.MethodDefinitionHandle(entry.MetadataToken) : default;

        // Portable PDB (sequence points) + a CodeView debug-directory entry pointing at it.
        DebugDirectoryBuilder? dbg = null;
        var (pdbBlob, pdbId) = BuildPdb(metadata, entryHandle);
        if (pdbBlob is not null)
        {
            string pdbPath = Path.ChangeExtension(outputPath, ".pdb");
            using (var pfs = new FileStream(pdbPath, FileMode.Create, FileAccess.Write)) pdbBlob.WriteContentTo(pfs);
            dbg = new DebugDirectoryBuilder();
            dbg.AddCodeViewEntry(Path.GetFileName(pdbPath), pdbId, 0x0100);
        }

        var ch = asExe ? Characteristics.ExecutableImage : Characteristics.ExecutableImage | Characteristics.Dll;
        var peHeader = new PEHeaderBuilder(imageCharacteristics: ch);
        var peBuilder = new ManagedPEBuilder(peHeader, new MetadataRootBuilder(metadata), ilStream, fieldData,
            debugDirectoryBuilder: dbg, entryPoint: entryHandle);
        var peBlob = new BlobBuilder();
        peBuilder.Serialize(peBlob);
        using var fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write);
        peBlob.WriteContentTo(fs);
    }

    // Build a Portable PDB from the collected sequence points. The MethodDebugInformation
    // table is parallel to MethodDef, so we emit rows 1..maxRow (empty where we have none).
    private (BlobBuilder? Blob, BlobContentId Id) BuildPdb(MetadataBuilder peMetadata, MethodDefinitionHandle entryHandle)
    {
        var byRow = new SortedDictionary<int, List<(int Off, int Line, int Col, int Doc)>>();
        foreach (var kv in _seq)
            if (kv.Value.Count > 0) byRow[kv.Key.MetadataToken & 0x00FFFFFF] = kv.Value;
        if (byRow.Count == 0) return (null, default);

        var pdb = new MetadataBuilder();
        var docs = new DocumentHandle[_documents.Count];
        for (int i = 0; i < _documents.Count; i++)
            docs[i] = pdb.AddDocument(pdb.GetOrAddDocumentName(_documents[i]), default, default, default);

        int maxRow = byRow.Keys.Max();
        for (int row = 1; row <= maxRow; row++)
        {
            if (byRow.TryGetValue(row, out var pts))
            {
                var blob = EncodeSequencePoints(pts, docs, out var doc);
                pdb.AddMethodDebugInformation(doc, pdb.GetOrAddBlob(blob));
            }
            else pdb.AddMethodDebugInformation(default, default);
        }

        var pdbBlob = new BlobBuilder();
        var ppb = new PortablePdbBuilder(pdb, peMetadata.GetRowCounts(), entryHandle);
        var id = ppb.Serialize(pdbBlob);
        return (pdbBlob, id);
    }

    private static BlobBuilder EncodeSequencePoints(List<(int Off, int Line, int Col, int Doc)> pts, DocumentHandle[] docs, out DocumentHandle doc)
    {
        // keep strictly-increasing IL offsets (the encoding requires δIL > 0)
        var f = new List<(int Off, int Line, int Col, int Doc)>();
        int last = -1;
        foreach (var p in pts.OrderBy(p => p.Off)) if (p.Off > last) { f.Add(p); last = p.Off; }
        doc = docs[Math.Clamp(f[0].Doc, 0, docs.Length - 1)];

        var b = new BlobBuilder();
        b.WriteCompressedInteger(0);                       // LocalSignature row id (none)
        int pOff = 0, pLine = 0, pCol = 0; bool first = true;
        foreach (var p in f)
        {
            b.WriteCompressedInteger(first ? p.Off : p.Off - pOff);
            b.WriteCompressedInteger(0);                   // ΔLines = 0 (point spans one line)
            b.WriteCompressedInteger(1);                   // ΔColumns = 1 (must be > 0 when ΔLines == 0)
            if (first) { b.WriteCompressedInteger(p.Line); b.WriteCompressedInteger(p.Col); }
            else { b.WriteCompressedSignedInteger(p.Line - pLine); b.WriteCompressedSignedInteger(p.Col - pCol); }
            pOff = p.Off; pLine = p.Line; pCol = p.Col; first = false;
        }
        return b;
    }
}

// Per-function codegen state.
internal sealed class FuncCtx
{
    public ILGenerator Il { get; }
    public CType ReturnType { get; }
    public LocalBuilder Fp = null!, SavedSp = null!;
    public LocalBuilder? RetVal;
    public Label Epilogue;
    public int FrameSize;

    public readonly Dictionary<Param, int> ParamSlot = new();
    public readonly Dictionary<DeclStmt, int> DeclSlot = new();

    private readonly List<Dictionary<string, VarSym>> _scopes = new() { new() };
    private readonly Stack<Label> _breaks = new();
    private readonly Stack<Label> _continues = new();
    private readonly Dictionary<string, Label> _labels = new();

    public FuncCtx(ILGenerator il, CType ret) { Il = il; ReturnType = ret; }

    // goto labels are function-scoped; created on first reference so forward gotos work.
    public Label GetLabel(string name)
    {
        if (!_labels.TryGetValue(name, out var l)) { l = Il.DefineLabel(); _labels[name] = l; }
        return l;
    }

    public void PushScope() => _scopes.Add(new());
    public void PopScope() => _scopes.RemoveAt(_scopes.Count - 1);
    public void Bind(string name, VarSym sym) => _scopes[^1][name] = sym;
    public bool TryLookup(string name, out VarSym sym)
    {
        for (int i = _scopes.Count - 1; i >= 0; i--) if (_scopes[i].TryGetValue(name, out sym!)) return true;
        sym = null!; return false;
    }

    public void PushLoop(Label brk, Label cont) { _breaks.Push(brk); _continues.Push(cont); }
    public void PopLoop() { _breaks.Pop(); _continues.Pop(); }
    public void PushBreak(Label brk) => _breaks.Push(brk);
    public void PopBreak() => _breaks.Pop();
    public Label BreakLabel() => _breaks.Count > 0 ? _breaks.Peek() : throw new CCompileException("'break' outside loop/switch");
    public Label ContinueLabel() => _continues.Count > 0 ? _continues.Peek() : throw new CCompileException("'continue' outside a loop");
}

internal enum Storage { Frame, Global }
internal sealed record VarSym(Storage Storage, int FrameOffset, FieldBuilder? GlobalAddr, CType Type);
