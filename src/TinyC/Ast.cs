namespace TinyC;

// The AST for Tiny. Everything is typed as 32-bit int — the smallest
// surface that still proves real codegen, control flow and .NET interop.

public abstract record Node;

public sealed record ProgramNode(IReadOnlyList<FuncDecl> Functions) : Node;

public sealed record FuncDecl(string Name, IReadOnlyList<string> Parameters, Block Body) : Node;

public sealed record Block(IReadOnlyList<Stmt> Statements) : Node;

// Statements
public abstract record Stmt : Node;
public sealed record LetStmt(string Name, Expr Value) : Stmt;
public sealed record AssignStmt(string Name, Expr Value) : Stmt;
public sealed record PrintStmt(Expr Value) : Stmt;
public sealed record ReturnStmt(Expr? Value) : Stmt;
public sealed record IfStmt(Expr Cond, Block Then, Block? Else) : Stmt;
public sealed record WhileStmt(Expr Cond, Block Body) : Stmt;
public sealed record ExprStmt(Expr Expr) : Stmt;

// Expressions
public abstract record Expr : Node;
public sealed record IntLit(int Value) : Expr;
public sealed record VarRef(string Name) : Expr;
public sealed record Binary(string Op, Expr Left, Expr Right) : Expr;
public sealed record Call(string Name, IReadOnlyList<Expr> Args) : Expr;
