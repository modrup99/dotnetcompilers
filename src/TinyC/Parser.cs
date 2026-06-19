namespace TinyC;

// A hand-written recursive-descent parser with standard precedence climbing
// for binary operators. Produces the AST defined in Ast.cs.
public sealed class Parser
{
    private readonly List<Token> _toks;
    private int _i;

    public Parser(List<Token> toks) => _toks = toks;

    private Token Cur => _toks[_i];
    private Token Next() => _toks[_i++];
    private bool Is(TokKind k) => Cur.Kind == k;
    private bool IsKw(string kw) => Cur.Kind == TokKind.Keyword && Cur.Text == kw;

    private Token Expect(TokKind k, string what)
    {
        if (!Is(k)) throw Err($"expected {what}, got '{Cur.Text}'");
        return Next();
    }

    public ProgramNode ParseProgram()
    {
        var funcs = new List<FuncDecl>();
        while (!Is(TokKind.Eof))
            funcs.Add(ParseFunc());
        return new ProgramNode(funcs);
    }

    private FuncDecl ParseFunc()
    {
        if (!IsKw("func")) throw Err($"expected 'func', got '{Cur.Text}'");
        Next();
        string name = Expect(TokKind.Ident, "function name").Text;
        Expect(TokKind.LParen, "'('");
        var ps = new List<string>();
        if (!Is(TokKind.RParen))
        {
            ps.Add(Expect(TokKind.Ident, "parameter").Text);
            while (Is(TokKind.Comma)) { Next(); ps.Add(Expect(TokKind.Ident, "parameter").Text); }
        }
        Expect(TokKind.RParen, "')'");
        var body = ParseBlock();
        return new FuncDecl(name, ps, body);
    }

    private Block ParseBlock()
    {
        Expect(TokKind.LBrace, "'{'");
        var stmts = new List<Stmt>();
        while (!Is(TokKind.RBrace) && !Is(TokKind.Eof))
            stmts.Add(ParseStmt());
        Expect(TokKind.RBrace, "'}'");
        return new Block(stmts);
    }

    private Stmt ParseStmt()
    {
        if (IsKw("let"))
        {
            Next();
            string name = Expect(TokKind.Ident, "variable name").Text;
            Expect(TokKind.Assign, "'='");
            var val = ParseExpr();
            Expect(TokKind.Semi, "';'");
            return new LetStmt(name, val);
        }
        if (IsKw("print"))
        {
            Next();
            var val = ParseExpr();
            Expect(TokKind.Semi, "';'");
            return new PrintStmt(val);
        }
        if (IsKw("return"))
        {
            Next();
            Expr? val = Is(TokKind.Semi) ? null : ParseExpr();
            Expect(TokKind.Semi, "';'");
            return new ReturnStmt(val);
        }
        if (IsKw("if"))
        {
            Next();
            Expect(TokKind.LParen, "'('");
            var cond = ParseExpr();
            Expect(TokKind.RParen, "')'");
            var then = ParseBlock();
            Block? els = null;
            if (IsKw("else")) { Next(); els = ParseBlock(); }
            return new IfStmt(cond, then, els);
        }
        if (IsKw("while"))
        {
            Next();
            Expect(TokKind.LParen, "'('");
            var cond = ParseExpr();
            Expect(TokKind.RParen, "')'");
            var body = ParseBlock();
            return new WhileStmt(cond, body);
        }

        // assignment 'name = expr;' or bare expression statement
        if (Is(TokKind.Ident) && _toks[_i + 1].Kind == TokKind.Assign)
        {
            string name = Next().Text;
            Next(); // '='
            var val = ParseExpr();
            Expect(TokKind.Semi, "';'");
            return new AssignStmt(name, val);
        }

        var e = ParseExpr();
        Expect(TokKind.Semi, "';'");
        return new ExprStmt(e);
    }

    // Precedence (low -> high): comparison, additive, multiplicative, unary, primary.
    private static int Prec(TokKind k) => k switch
    {
        TokKind.EqEq or TokKind.NotEq or TokKind.Lt or TokKind.Le or TokKind.Gt or TokKind.Ge => 1,
        TokKind.Plus or TokKind.Minus => 2,
        TokKind.Star or TokKind.Slash or TokKind.Percent => 3,
        _ => -1
    };

    private Expr ParseExpr(int minPrec = 1)
    {
        var left = ParseUnary();
        while (true)
        {
            int prec = Prec(Cur.Kind);
            if (prec < minPrec) break;
            string op = Next().Text;
            var right = ParseExpr(prec + 1);
            left = new Binary(op, left, right);
        }
        return left;
    }

    private Expr ParseUnary()
    {
        if (Is(TokKind.Minus))
        {
            Next();
            return new Binary("-", new IntLit(0), ParseUnary());
        }
        return ParsePrimary();
    }

    private Expr ParsePrimary()
    {
        if (Is(TokKind.Int))
            return new IntLit(int.Parse(Next().Text));

        if (Is(TokKind.LParen))
        {
            Next();
            var e = ParseExpr();
            Expect(TokKind.RParen, "')'");
            return e;
        }

        if (Is(TokKind.Ident))
        {
            string name = Next().Text;
            if (Is(TokKind.LParen))
            {
                Next();
                var args = new List<Expr>();
                if (!Is(TokKind.RParen))
                {
                    args.Add(ParseExpr());
                    while (Is(TokKind.Comma)) { Next(); args.Add(ParseExpr()); }
                }
                Expect(TokKind.RParen, "')'");
                return new Call(name, args);
            }
            return new VarRef(name);
        }

        throw Err($"unexpected token '{Cur.Text}'");
    }

    private Exception Err(string msg)
        => new TinyCompileException($"parse error ({Cur.Line}:{Cur.Col}): {msg}");
}
