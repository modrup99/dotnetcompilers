namespace Cc;

// The C type model. Pointers/arrays/functions are represented now so the
// parser is complete; the Stage-1 emitter handles the scalar + function subset
// and reports a clear error for the rest (fat pointers/structs land next).
public abstract record CType
{
    public static readonly PrimType Int = new(BaseKind.Int);
    public static readonly PrimType Char = new(BaseKind.Char);
    public static readonly PrimType Void = new(BaseKind.Void);
    public static readonly PrimType Double = new(BaseKind.Double);
    public static readonly PrimType Float = new(BaseKind.Float);
    public static readonly PrimType UInt = new(BaseKind.UInt);
    public static readonly PrimType Long = new(BaseKind.Long);
    public static readonly PrimType ULong = new(BaseKind.ULong);

    public bool IsInteger => this is PrimType { Kind: BaseKind.Int or BaseKind.Char or BaseKind.UInt or BaseKind.Long or BaseKind.ULong };
    public bool IsVoid => this is PrimType { Kind: BaseKind.Void };
    public bool IsFloating => this is PrimType { Kind: BaseKind.Double or BaseKind.Float };
    public bool IsUnsigned => this is PrimType { Kind: BaseKind.UInt or BaseKind.ULong };
    public bool IsLong => this is PrimType { Kind: BaseKind.Long or BaseKind.ULong };
}

public enum BaseKind { Void, Char, Int, Double, Float, UInt, Long, ULong }

public sealed record PrimType(BaseKind Kind) : CType;
public sealed record PointerType(CType Pointee) : CType;
public sealed record ArrayType(CType Element, int? Length) : CType;
public sealed record FuncType(CType Return, IReadOnlyList<CType> Params, bool Variadic) : CType;
// struct/union referenced by tag; the layout lives in TranslationUnit.Structs.
public sealed record StructType(string Tag) : CType;

// One struct/union definition: ordered fields; offsets/size computed by the emitter.
public sealed record FieldDecl(CType Type, string Name);
public sealed record StructDef(string Tag, bool IsUnion, IReadOnlyList<FieldDecl> Fields);
