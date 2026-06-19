namespace Cc;

// ---- Top level ----------------------------------------------------------
public abstract record Decl;

public sealed record Param(CType Type, string Name);

// A function with a body; Body == null means a prototype/declaration only.
public sealed record FuncDef(
    CType ReturnType, string Name, IReadOnlyList<Param> Params, bool Variadic,
    CompoundStmt? Body) : Decl;

public sealed record GlobalVar(CType Type, string Name, Init? Init) : Decl;

// An initializer is either a scalar expression or a brace-enclosed list.
public abstract record Init;
public sealed record InitExpr(Expr E) : Init;
public sealed record InitList(IReadOnlyList<Init> Items) : Init;
public sealed record Designated(string? Field, int? Index, Init Inner) : Init;  // .field= or [i]=

public sealed record TranslationUnit(
    IReadOnlyList<Decl> Decls,
    IReadOnlyDictionary<string, StructDef> Structs,
    IReadOnlyDictionary<string, int> EnumConstants);

// ---- Statements ---------------------------------------------------------
// Line/Doc carry the source position (set by the parser) for PDB sequence points.
public abstract record Stmt { public int Line; public int Doc; public int Col = 1; }

public sealed record CompoundStmt(IReadOnlyList<Stmt> Items) : Stmt;
public sealed record DeclStmt(CType Type, string Name, Init? Init, bool IsStatic = false) : Stmt; // local variable
public sealed record IfStmt(Expr Cond, Stmt Then, Stmt? Else) : Stmt;
public sealed record WhileStmt(Expr Cond, Stmt Body) : Stmt;
public sealed record DoWhileStmt(Stmt Body, Expr Cond) : Stmt;
public sealed record ForStmt(Stmt? Init, Expr? Cond, Expr? Post, Stmt Body) : Stmt;
public sealed record ReturnStmt(Expr? Value) : Stmt;
public sealed record BreakStmt : Stmt;
public sealed record ContinueStmt : Stmt;
public sealed record ExprStmt(Expr? Expr) : Stmt;
public sealed record SwitchStmt(Expr Value, Stmt Body) : Stmt;
public sealed record CaseLabel(int Value) : Stmt;   // constant-folded at parse time
public sealed record DefaultLabel : Stmt;
public sealed record GotoStmt(string Label) : Stmt;
public sealed record LabelStmt(string Name, Stmt Body) : Stmt;

// ---- Expressions --------------------------------------------------------
public abstract record Expr;

public sealed record IntLit(int Value) : Expr;
public sealed record LongLit(long Value) : Expr;
public sealed record FloatLit(double Value) : Expr;
public sealed record StrLit(string Value) : Expr;
public sealed record Ident(string Name) : Expr;
public sealed record CallExpr(Expr Callee, IReadOnlyList<Expr> Args) : Expr; // callee is an expr (supports function pointers)
public sealed record Member(Expr Base, string Name, bool Arrow) : Expr;      // e.m / e->m
public sealed record Unary(string Op, Expr Operand) : Expr;       // - ! ~ + (prefix) and ++/-- handled via PreInc
public sealed record PreInc(string Op, Expr Target) : Expr;      // ++x / --x
public sealed record PostInc(string Op, Expr Target) : Expr;     // x++ / x--
public sealed record Binary(string Op, Expr Left, Expr Right) : Expr;
public sealed record Assign(Expr Target, Expr Value) : Expr;
public sealed record Conditional(Expr Cond, Expr Then, Expr Else) : Expr;
public sealed record Comma(Expr Left, Expr Right) : Expr;          // (a, b) — evaluates a, yields b
public sealed record Index(Expr Base, Expr Idx) : Expr;            // base[idx]
public sealed record Cast(CType Type, Expr Operand) : Expr;        // (type)expr
public sealed record SizeofType(CType Type) : Expr;               // sizeof(type)
public sealed record SizeofExpr(Expr Operand) : Expr;             // sizeof expr
