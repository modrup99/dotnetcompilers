namespace Cc;

// Recursive-descent parser for the C subset. Tracks typedef names (C's grammar
// is context-sensitive on them), struct/union/enum specifiers, member access,
// switch, and indirect calls through function pointers.
public sealed class Parser
{
    private readonly List<Token> _t;
    private int _i;

    private readonly Dictionary<string, CType> _typedefs = new();
    private readonly Dictionary<string, StructDef> _structs = new();
    private readonly Dictionary<string, int> _enums = new();
    private int _anon;

    public Parser(List<Token> toks) => _t = toks;

    private Token Cur => _t[_i];
    private Token Pk(int n = 1) => _t[Math.Min(_i + n, _t.Count - 1)];
    private bool At(T k) => Cur.Kind == k;
    private bool AtKw(string kw) => Cur.Kind == T.Keyword && Cur.Text == kw;
    private Token Next() => _t[_i++];
    private Token Expect(T k, string what) { if (!At(k)) throw Err($"expected {what}, got '{Cur.Text}'"); return Next(); }
    private bool Accept(T k) { if (At(k)) { _i++; return true; } return false; }

    public TranslationUnit Parse()
    {
        var decls = new List<Decl>();
        while (!At(T.Eof)) decls.AddRange(ParseExternalDecl());
        return new TranslationUnit(decls, _structs, _enums);
    }

    private static readonly HashSet<string> BaseTypeWords = new()
    { "void", "char", "int", "short", "long", "signed", "unsigned", "double", "float" };
    private static readonly HashSet<string> Qualifiers = new()
    { "const", "static", "extern", "register", "volatile", "auto", "inline" };

    private bool IsTypedefName(Token t) => t.Kind == T.Ident && _typedefs.ContainsKey(t.Text);

    private bool AtTypeStart()
        => (Cur.Kind == T.Keyword && (BaseTypeWords.Contains(Cur.Text) || Qualifiers.Contains(Cur.Text)
            || Cur.Text is "struct" or "union" or "enum" or "typedef"))
        || IsTypedefName(Cur);

    // ---- declaration specifiers ----------------------------------------
    private (CType Type, bool IsTypedef, bool IsStatic) ParseDeclSpecifiers()
    {
        bool isTypedef = false, isStatic = false;
        CType? baseType = null;
        var words = new List<string>();

        while (true)
        {
            if (AtKw("typedef")) { isTypedef = true; Next(); continue; }
            if (AtKw("static")) { isStatic = true; Next(); continue; }
            if (Cur.Kind == T.Keyword && Qualifiers.Contains(Cur.Text)) { Next(); continue; }
            if (Cur.Kind == T.Keyword && BaseTypeWords.Contains(Cur.Text)) { words.Add(Next().Text); continue; }
            if (AtKw("struct") || AtKw("union")) { baseType = ParseStructSpecifier(); continue; }
            if (AtKw("enum")) { baseType = ParseEnumSpecifier(); continue; }
            if (baseType is null && words.Count == 0 && IsTypedefName(Cur)) { baseType = _typedefs[Next().Text]; continue; }
            break;
        }

        if (baseType is null)
        {
            if (words.Count == 0) throw Err($"expected a type, got '{Cur.Text}'");
            bool uns = words.Contains("unsigned");
            baseType = words.Contains("void") ? CType.Void
                : words.Contains("double") ? CType.Double
                : words.Contains("float") ? CType.Float
                : words.Contains("char") ? CType.Char           // (signed/unsigned) char -> 1-byte
                : words.Contains("long") ? (uns ? CType.ULong : CType.Long)
                : uns ? CType.UInt
                : CType.Int;
        }
        return (baseType, isTypedef, isStatic);
    }

    private CType ParseStructSpecifier()
    {
        bool isUnion = Next().Text == "union";
        string tag = At(T.Ident) ? Next().Text : $"__anon{_anon++}";

        if (Accept(T.LBrace))
        {
            var fields = new List<FieldDecl>();
            while (!At(T.RBrace) && !At(T.Eof))
            {
                var (fb, _, _) = ParseDeclSpecifiers();
                while (true)
                {
                    var (ft, fname) = ParseDeclarator(fb);
                    fields.Add(new FieldDecl(ft, fname));
                    if (Accept(T.Comma)) continue;
                    Expect(T.Semi, "';'");
                    break;
                }
            }
            Expect(T.RBrace, "'}'");
            _structs[tag] = new StructDef(tag, isUnion, fields);
        }
        return new StructType(tag);
    }

    private CType ParseEnumSpecifier()
    {
        Next(); // 'enum'
        if (At(T.Ident)) Next(); // optional tag (unused; enum is just int)
        if (Accept(T.LBrace))
        {
            int val = 0;
            while (!At(T.RBrace) && !At(T.Eof))
            {
                string name = Expect(T.Ident, "enum constant").Text;
                if (Accept(T.Assign)) val = ConstEval(ParseConditional());
                _enums[name] = val++;
                if (!Accept(T.Comma)) break;
            }
            Expect(T.RBrace, "'}'");
        }
        return CType.Int;
    }

    // ---- external declarations -----------------------------------------
    private IEnumerable<Decl> ParseExternalDecl()
    {
        var (baseType, isTypedef, _) = ParseDeclSpecifiers();   // file-scope `static` ignored
        var results = new List<Decl>();
        if (Accept(T.Semi)) return results; // e.g. `struct X { ... };`

        while (true)
        {
            var (type, name) = ParseDeclarator(baseType);
            var funcParams = _lastParams;

            if (isTypedef) { _typedefs[name] = type; }
            else if (type is FuncType ft && At(T.LBrace))
            {
                results.Add(new FuncDef(ft.Return, name, funcParams, ft.Variadic, ParseCompound()));
                return results;
            }
            else if (type is FuncType ft2) results.Add(new FuncDef(ft2.Return, name, funcParams, ft2.Variadic, null));
            else
            {
                Init? init = Accept(T.Assign) ? ParseInitializer() : null;
                results.Add(new GlobalVar(InferArrayLen(type, init), name, init));
            }

            if (Accept(T.Comma)) continue;
            Expect(T.Semi, "';'");
            return results;
        }
    }

    private Init ParseInitializer()
    {
        if (Accept(T.LBrace))
        {
            var items = new List<Init>();
            if (!At(T.RBrace))
            {
                items.Add(ParseDesignatedItem());
                while (Accept(T.Comma)) { if (At(T.RBrace)) break; items.Add(ParseDesignatedItem()); }
            }
            Expect(T.RBrace, "'}'");
            return new InitList(items);
        }
        return new InitExpr(ParseAssign());
    }

    private Init ParseDesignatedItem()
    {
        if (Accept(T.Dot))
        {
            string field = Expect(T.Ident, "field name").Text;
            Expect(T.Assign, "'='");
            return new Designated(field, null, ParseInitializer());
        }
        if (Accept(T.LBracket))
        {
            int idx = ConstEval(ParseAssign());
            Expect(T.RBracket, "']'");
            Expect(T.Assign, "'='");
            return new Designated(null, idx, ParseInitializer());
        }
        return ParseInitializer();
    }

    // `T a[] = {...}` / `char s[] = "..."` infers the array length from the initializer.
    private static CType InferArrayLen(CType t, Init? init)
    {
        if (t is ArrayType { Length: null } a && init is not null)
        {
            int n;
            if (init is InitExpr { E: StrLit s } && a.Element is PrimType { Kind: BaseKind.Char }) n = s.Value.Length + 1;
            else if (init is InitList l)
            {
                int cur = 0, max = 0;
                foreach (var it in l.Items) { if (it is Designated { Index: int ix }) cur = ix; cur++; if (cur > max) max = cur; }
                n = max;
            }
            else n = 0;
            return new ArrayType(a.Element, n);
        }
        return t;
    }

    private List<Param> _lastParams = new();

    private (CType, string) ParseDeclarator(CType baseType)
    {
        int ptr = 0;
        while (Accept(T.Star)) { ptr++; while (AtKw("const") || AtKw("volatile")) _i++; }

        // parenthesized declarator: function pointer `R (*name)(params)` or
        // pointer-to-array `R (*name)[n]`.
        if (At(T.LParen) && Pk().Kind == T.Star)
        {
            Next(); // '('
            int inner = 0;
            while (Accept(T.Star)) { inner++; while (AtKw("const") || AtKw("volatile")) _i++; }
            string innerName = At(T.Ident) ? Next().Text : "";
            Expect(T.RParen, "')'");
            if (At(T.LParen))
            {
                var (pts, va, plist) = ParseParamList();
                _lastParams = plist;
                CType fn = new FuncType(Wrap(baseType, ptr), pts, va);
                return (Wrap(fn, inner), innerName);
            }
            if (Accept(T.LBracket))
            {
                int? len = null;
                if (!At(T.RBracket)) len = ConstEval(ParseAssign());
                Expect(T.RBracket, "']'");
                return (Wrap(new ArrayType(Wrap(baseType, ptr), len), inner), innerName);
            }
            return (Wrap(Wrap(baseType, ptr), inner), innerName);
        }

        string name = At(T.Ident) ? Next().Text : "";

        if (At(T.LParen))
        {
            var (paramTypes, variadic, paramList) = ParseParamList();
            _lastParams = paramList;
            return (new FuncType(Wrap(baseType, ptr), paramTypes, variadic), name);
        }
        if (At(T.LBracket))
        {
            var dims = new List<int?>();
            while (Accept(T.LBracket))
            {
                int? len = null;
                if (!At(T.RBracket)) len = ConstEval(ParseAssign());
                Expect(T.RBracket, "']'");
                dims.Add(len);
            }
            CType t = Wrap(baseType, ptr);
            for (int d = dims.Count - 1; d >= 0; d--) t = new ArrayType(t, dims[d]); // outer dim first
            return (t, name);
        }
        return (Wrap(baseType, ptr), name);
    }

    private static CType Wrap(CType t, int ptr) { for (int i = 0; i < ptr; i++) t = new PointerType(t); return t; }

    private (List<CType>, bool, List<Param>) ParseParamList()
    {
        Expect(T.LParen, "'('");
        var types = new List<CType>();
        var pars = new List<Param>();
        bool variadic = false;

        if (At(T.RParen)) { Next(); return (types, false, pars); }
        if (AtKw("void") && Pk().Kind == T.RParen) { Next(); Next(); return (types, false, pars); }

        while (true)
        {
            if (Accept(T.Ellipsis)) { variadic = true; break; }
            var (bt, _, _) = ParseDeclSpecifiers();
            var (pt, pname) = ParseDeclarator(bt);
            types.Add(pt);
            pars.Add(new Param(pt, pname));
            if (Accept(T.Comma)) continue;
            break;
        }
        Expect(T.RParen, "')'");
        return (types, variadic, pars);
    }

    // ---- statements ----------------------------------------------------
    private CompoundStmt ParseCompound()
    {
        Expect(T.LBrace, "'{'");
        var items = new List<Stmt>();
        while (!At(T.RBrace) && !At(T.Eof))
        {
            var tok = Cur;
            if (AtTypeStart())
                foreach (var d in ParseLocalDecl())
                {
                    if (d.Line == 0) { d.Line = tok.Line; d.Col = tok.Col; d.Doc = tok.Doc; }
                    items.Add(d);
                }
            else items.Add(ParseStmt());
        }
        Expect(T.RBrace, "'}'");
        return new CompoundStmt(items);
    }

    private IEnumerable<Stmt> ParseLocalDecl()
    {
        var (baseType, isTypedef, isStatic) = ParseDeclSpecifiers();
        var outp = new List<Stmt>();
        if (Accept(T.Semi)) return outp;
        while (true)
        {
            var (type, name) = ParseDeclarator(baseType);
            if (isTypedef) { _typedefs[name] = type; }
            else
            {
                Init? init = Accept(T.Assign) ? ParseInitializer() : null;
                outp.Add(new DeclStmt(InferArrayLen(type, init), name, init, isStatic));
            }
            if (Accept(T.Comma)) continue;
            Expect(T.Semi, "';'");
            return outp;
        }
    }

    private Stmt ParseStmt()
    {
        var tok = Cur;
        var s = ParseStmtInner();
        if (s.Line == 0) { s.Line = tok.Line; s.Col = tok.Col; s.Doc = tok.Doc; }
        return s;
    }

    private Stmt ParseStmtInner()
    {
        if (At(T.LBrace)) return ParseCompound();
        if (Accept(T.Semi)) return new ExprStmt(null);

        if (AtKw("if"))
        {
            Next(); Expect(T.LParen, "'('"); var c = ParseExpr(); Expect(T.RParen, "')'");
            var then = ParseStmt();
            Stmt? els = AtKw("else") ? (Next(), ParseStmt()).Item2 : null;
            return new IfStmt(c, then, els);
        }
        if (AtKw("while"))
        {
            Next(); Expect(T.LParen, "'('"); var c = ParseExpr(); Expect(T.RParen, "')'");
            return new WhileStmt(c, ParseStmt());
        }
        if (AtKw("do"))
        {
            Next(); var body = ParseStmt();
            if (!AtKw("while")) throw Err("expected 'while' after do-body");
            Next(); Expect(T.LParen, "'('"); var c = ParseExpr(); Expect(T.RParen, "')'"); Expect(T.Semi, "';'");
            return new DoWhileStmt(body, c);
        }
        if (AtKw("for"))
        {
            Next(); Expect(T.LParen, "'('");
            Stmt? init;
            if (Accept(T.Semi)) init = null;
            else if (AtTypeStart()) { var d = ParseLocalDecl().ToList(); init = d.Count > 0 ? d[0] : null; }
            else { var e = ParseExpr(); Expect(T.Semi, "';'"); init = new ExprStmt(e); }
            Expr? cond = At(T.Semi) ? null : ParseExpr(); Expect(T.Semi, "';'");
            Expr? post = At(T.RParen) ? null : ParseExpr(); Expect(T.RParen, "')'");
            return new ForStmt(init, cond, post, ParseStmt());
        }
        if (AtKw("switch"))
        {
            Next(); Expect(T.LParen, "'('"); var v = ParseExpr(); Expect(T.RParen, "')'");
            return new SwitchStmt(v, ParseStmt());
        }
        if (AtKw("case"))
        {
            Next(); int val = ConstEval(ParseConditional()); Expect(T.Colon, "':'");
            return new CaseLabel(val);
        }
        if (AtKw("default")) { Next(); Expect(T.Colon, "':'"); return new DefaultLabel(); }
        if (AtKw("return"))
        {
            Next(); Expr? v = At(T.Semi) ? null : ParseExpr(); Expect(T.Semi, "';'");
            return new ReturnStmt(v);
        }
        if (AtKw("break")) { Next(); Expect(T.Semi, "';'"); return new BreakStmt(); }
        if (AtKw("continue")) { Next(); Expect(T.Semi, "';'"); return new ContinueStmt(); }
        if (AtKw("goto")) { Next(); string nm = Expect(T.Ident, "label").Text; Expect(T.Semi, "';'"); return new GotoStmt(nm); }

        // label:  (identifier directly followed by ':')
        if (At(T.Ident) && Pk().Kind == T.Colon) { string nm = Next().Text; Next(); return new LabelStmt(nm, ParseStmt()); }

        var expr = ParseExpr();
        Expect(T.Semi, "';'");
        return new ExprStmt(expr);
    }

    // ---- expressions ---------------------------------------------------
    // Full expressions allow the comma operator; function args / initializers
    // call ParseAssign directly so commas there stay separators.
    public Expr ParseExpr()
    {
        var e = ParseAssign();
        while (Accept(T.Comma)) e = new Comma(e, ParseAssign());
        return e;
    }

    private static readonly Dictionary<T, string> CompoundOps = new()
    {
        [T.PlusEq] = "+", [T.MinusEq] = "-", [T.StarEq] = "*", [T.SlashEq] = "/",
        [T.PercentEq] = "%", [T.AmpEq] = "&", [T.PipeEq] = "|", [T.CaretEq] = "^",
        [T.ShlEq] = "<<", [T.ShrEq] = ">>",
    };

    private Expr ParseAssign()
    {
        var left = ParseConditional();
        if (Accept(T.Assign)) return new Assign(left, ParseAssign());
        if (CompoundOps.TryGetValue(Cur.Kind, out var op)) { Next(); return new Assign(left, new Binary(op, left, ParseAssign())); }
        return left;
    }

    private Expr ParseConditional()
    {
        var c = ParseBinary(1);
        if (Accept(T.Question))
        {
            var then = ParseExpr(); Expect(T.Colon, "':'");
            return new Conditional(c, then, ParseConditional());
        }
        return c;
    }

    private static int Prec(T k) => k switch
    {
        T.PipePipe => 1, T.AmpAmp => 2, T.Pipe => 3, T.Caret => 4, T.Amp => 5,
        T.EqEq or T.NotEq => 6,
        T.Lt or T.Le or T.Gt or T.Ge => 7,
        T.Shl or T.Shr => 8,
        T.Plus or T.Minus => 9,
        T.Star or T.Slash or T.Percent => 10,
        _ => -1
    };

    private static string OpText(T k) => k switch
    {
        T.PipePipe => "||", T.AmpAmp => "&&", T.Pipe => "|", T.Caret => "^", T.Amp => "&",
        T.EqEq => "==", T.NotEq => "!=", T.Lt => "<", T.Le => "<=", T.Gt => ">", T.Ge => ">=",
        T.Shl => "<<", T.Shr => ">>", T.Plus => "+", T.Minus => "-",
        T.Star => "*", T.Slash => "/", T.Percent => "%",
        _ => throw new CCompileException($"not a binary operator: {k}")
    };

    private Expr ParseBinary(int minPrec)
    {
        var left = ParseUnary();
        while (true)
        {
            int p = Prec(Cur.Kind);
            if (p < minPrec) break;
            string op = OpText(Cur.Kind); Next();
            left = new Binary(op, left, ParseBinary(p + 1));
        }
        return left;
    }

    private bool NextStartsTypeName()
        => (Pk().Kind == T.Keyword && (BaseTypeWords.Contains(Pk().Text) || Pk().Text is "struct" or "union" or "enum"
            || Qualifiers.Contains(Pk().Text)))
        || IsTypedefName(Pk());

    private Expr ParseUnary()
    {
        if (At(T.LParen) && NextStartsTypeName())
        {
            Next(); var ty = ParseTypeName(); Expect(T.RParen, "')'");
            return new Cast(ty, ParseUnary());
        }
        switch (Cur.Kind)
        {
            case T.Minus: Next(); return new Unary("-", ParseUnary());
            case T.Plus: Next(); return new Unary("+", ParseUnary());
            case T.Not: Next(); return new Unary("!", ParseUnary());
            case T.Tilde: Next(); return new Unary("~", ParseUnary());
            case T.Star: Next(); return new Unary("*", ParseUnary());
            case T.Amp: Next(); return new Unary("&", ParseUnary());
            case T.Inc: Next(); return new PreInc("+", ParseUnary());
            case T.Dec: Next(); return new PreInc("-", ParseUnary());
        }
        if (AtKw("sizeof"))
        {
            Next();
            if (At(T.LParen) && NextStartsTypeName())
            {
                Next(); var ty = ParseTypeName(); Expect(T.RParen, "')'");
                return new SizeofType(ty);
            }
            return new SizeofExpr(ParseUnary());
        }
        return ParsePostfix();
    }

    private CType ParseTypeName()
    {
        var (t, _, _) = ParseDeclSpecifiers();
        while (Accept(T.Star)) { t = new PointerType(t); while (AtKw("const") || AtKw("volatile")) _i++; }
        // abstract function-pointer type: `R (*)(params)`
        if (At(T.LParen) && Pk().Kind == T.Star)
        {
            Next(); int inner = 0;
            while (Accept(T.Star)) inner++;
            Expect(T.RParen, "')'");
            if (At(T.LParen)) { var (pts, va, _) = ParseParamList(); return Wrap(new FuncType(t, pts, va), inner); }
        }
        if (Accept(T.LBracket))
        {
            int? len = null;
            if (!At(T.RBracket)) len = ConstEval(ParseAssign());
            Expect(T.RBracket, "']'");
            t = new ArrayType(t, len);
        }
        return t;
    }

    private Expr ParsePostfix()
    {
        var e = ParsePrimary();
        while (true)
        {
            if (Accept(T.LParen))
            {
                var args = new List<Expr>();
                if (!At(T.RParen)) { args.Add(ParseAssign()); while (Accept(T.Comma)) args.Add(ParseAssign()); }
                Expect(T.RParen, "')'");
                e = new CallExpr(e, args);
            }
            else if (Accept(T.LBracket)) { var idx = ParseExpr(); Expect(T.RBracket, "']'"); e = new Index(e, idx); }
            else if (Accept(T.Dot)) e = new Member(e, Expect(T.Ident, "member name").Text, false);
            else if (Accept(T.Arrow)) e = new Member(e, Expect(T.Ident, "member name").Text, true);
            else if (At(T.Inc)) { Next(); e = new PostInc("+", e); }
            else if (At(T.Dec)) { Next(); e = new PostInc("-", e); }
            else break;
        }
        return e;
    }

    private Expr ParsePrimary()
    {
        if (At(T.IntConst)) return new IntLit((int)Next().Value);
        if (At(T.LongConst)) return new LongLit(Next().Value);
        if (At(T.FloatConst)) return new FloatLit(double.Parse(Next().Text, System.Globalization.CultureInfo.InvariantCulture));
        if (At(T.CharConst)) return new IntLit((int)Next().Value);
        if (At(T.StrConst))
        {
            string s = Next().Text;
            while (At(T.StrConst)) s += Next().Text; // adjacent string-literal concatenation
            return new StrLit(s);
        }
        if (At(T.Ident)) return new Ident(Next().Text);
        if (Accept(T.LParen)) { var e = ParseExpr(); Expect(T.RParen, "')'"); return e; }
        throw Err($"unexpected token '{Cur.Text}'");
    }

    // ---- constant folding (enum values, array sizes, case labels) ------
    private int ConstEval(Expr e) => e switch
    {
        IntLit n => n.Value,
        LongLit n => (int)n.Value,
        Ident id when _enums.TryGetValue(id.Name, out int v) => v,
        Unary u => u.Op switch
        {
            "-" => -ConstEval(u.Operand), "+" => ConstEval(u.Operand),
            "~" => ~ConstEval(u.Operand), "!" => ConstEval(u.Operand) == 0 ? 1 : 0,
            _ => throw Err("non-constant expression")
        },
        Binary b => Fold(b.Op, ConstEval(b.Left), ConstEval(b.Right)),
        Cast c => ConstEval(c.Operand),
        SizeofType => throw Err("sizeof in a constant expression is not supported yet"),
        _ => throw Err("expected a constant expression")
    };

    private static int Fold(string op, int a, int b) => op switch
    {
        "+" => a + b, "-" => a - b, "*" => a * b, "/" => a / b, "%" => a % b,
        "<<" => a << b, ">>" => a >> b, "&" => a & b, "|" => a | b, "^" => a ^ b,
        "==" => a == b ? 1 : 0, "!=" => a != b ? 1 : 0,
        "<" => a < b ? 1 : 0, "<=" => a <= b ? 1 : 0, ">" => a > b ? 1 : 0, ">=" => a >= b ? 1 : 0,
        _ => throw new CCompileException($"non-constant operator '{op}'")
    };

    private CCompileException Err(string msg) => new($"parse error ({Cur.Line}:{Cur.Col}): {msg}");
}
