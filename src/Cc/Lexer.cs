namespace Cc;

public enum T
{
    Ident, IntConst, LongConst, FloatConst, CharConst, StrConst, Keyword,
    // punctuators / operators
    LParen, RParen, LBrace, RBrace, LBracket, RBracket,
    Semi, Comma, Dot, Arrow, Ellipsis,
    Assign, PlusEq, MinusEq, StarEq, SlashEq, PercentEq, AmpEq, PipeEq, CaretEq, ShlEq, ShrEq,
    Plus, Minus, Star, Slash, Percent,
    Inc, Dec,
    EqEq, NotEq, Lt, Le, Gt, Ge,
    AmpAmp, PipePipe, Not,
    Amp, Pipe, Caret, Tilde, Shl, Shr,
    Question, Colon,
    Eof
}

public readonly record struct Token(T Kind, string Text, long Value, int Line, int Col, int Doc = 0);

public sealed class Lexer
{
    public static readonly HashSet<string> Keywords = new()
    {
        "int", "char", "void", "short", "long", "unsigned", "signed", "const", "double", "float",
        "if", "else", "while", "for", "do", "return", "break", "continue",
        "switch", "case", "default", "goto",
        "struct", "union", "enum", "typedef", "static", "extern", "sizeof"
    };

    private readonly string _s;
    private int _p, _line = 1, _col = 1, _doc;

    // Documents[0] is the primary input file; #line "file" directives add more.
    public readonly List<string> Documents = new();

    public Lexer(string src, string file = "src.c") { _s = src; Documents.Add(file); }

    private char Cur => _p < _s.Length ? _s[_p] : '\0';
    private char Pk(int n = 1) => _p + n < _s.Length ? _s[_p + n] : '\0';

    private void Adv()
    {
        if (Cur == '\n') { _line++; _col = 1; } else _col++;
        _p++;
    }

    public List<Token> Tokenize()
    {
        var toks = new List<Token>();
        while (true)
        {
            SkipTrivia();
            if (_p >= _s.Length) { toks.Add(new(T.Eof, "", 0, _line, _col, _doc)); break; }
            int line = _line, col = _col;
            char c = Cur;

            if (char.IsDigit(c) || (c == '.' && char.IsDigit(Pk())))
            { toks.Add(LexNumber(line, col)); continue; }

            if (char.IsLetter(c) || c == '_')
            {
                int start = _p;
                while (char.IsLetterOrDigit(Cur) || Cur == '_') Adv();
                string id = _s[start.._p];
                toks.Add(new(Keywords.Contains(id) ? T.Keyword : T.Ident, id, 0, line, col, _doc));
                continue;
            }

            if (c == '\'') { toks.Add(LexChar(line, col)); continue; }
            if (c == '"') { toks.Add(LexString(line, col)); continue; }

            toks.Add(LexOp(line, col));
        }
        return toks;
    }

    private void SkipTrivia()
    {
        while (_p < _s.Length)
        {
            char c = Cur;
            if (c is ' ' or '\t' or '\r' or '\n' or '\f' or '\v') { Adv(); continue; }
            if (c == '/' && Pk() == '/') { while (_p < _s.Length && Cur != '\n') Adv(); continue; }
            if (c == '/' && Pk() == '*')
            {
                Adv(); Adv();
                while (_p < _s.Length && !(Cur == '*' && Pk() == '/')) Adv();
                if (_p < _s.Length) { Adv(); Adv(); }
                continue;
            }
            // honor "#line N "file"" (and gcc-style "# N "file""); skip other # lines
            if (c == '#') { HandleHashLine(); continue; }
            break;
        }
    }

    // a "#line N "file"" directive sets the line/document of the FOLLOWING line.
    private void HandleHashLine()
    {
        int s = _p;
        while (_p < _s.Length && Cur != '\n') _p++;     // raw scan of the directive line
        string line = _s[s.._p];
        var m = System.Text.RegularExpressions.Regex.Match(line, "^#\\s*(?:line\\s+)?(\\d+)(?:\\s+\"([^\"]*)\")?");
        if (m.Success)
        {
            if (m.Groups[2].Success)
            {
                string file = m.Groups[2].Value;
                int idx = Documents.IndexOf(file);
                if (idx < 0) { idx = Documents.Count; Documents.Add(file); }
                _doc = idx;
            }
            _line = int.Parse(m.Groups[1].Value);       // next line is line N
            _col = 1;
            if (Cur == '\n') _p++;                        // consume newline WITHOUT bumping _line
        }
        // non-#line directive: leave the trailing '\n' for SkipTrivia's normal handling
    }

    private Token LexNumber(int line, int col)
    {
        int start = _p;
        if (Cur == '0' && (Pk() is 'x' or 'X'))
        {
            Adv(); Adv();
            int hs = _p;
            while (Uri.IsHexDigit(Cur)) Adv();
            long hv = Convert.ToUInt64(_s[hs.._p], 16) is var u && u <= long.MaxValue ? (long)u : unchecked((long)u);
            bool hl = false; while (Cur is 'u' or 'U' or 'l' or 'L') { if (Cur is 'l' or 'L') hl = true; Adv(); }
            bool big = hv < int.MinValue || hv > uint.MaxValue;
            return new(hl || big ? T.LongConst : T.IntConst, _s[start.._p], hv, line, col, _doc);
        }

        bool isFloat = false;
        while (char.IsDigit(Cur)) Adv();
        if (Cur == '.') { isFloat = true; Adv(); while (char.IsDigit(Cur)) Adv(); }
        if (Cur is 'e' or 'E') { isFloat = true; Adv(); if (Cur is '+' or '-') Adv(); while (char.IsDigit(Cur)) Adv(); }

        string text = _s[start.._p];
        if (isFloat)
        {
            while (Cur is 'f' or 'F' or 'l' or 'L') Adv();
            return new(T.FloatConst, text, 0, line, col, _doc);
        }
        bool isLong = false;
        while (Cur is 'u' or 'U' or 'l' or 'L') { if (Cur is 'l' or 'L') isLong = true; Adv(); }
        // a leading 0 (with more digits) denotes octal in C
        long val = text.Length > 1 && text[0] == '0' && text.All(ch => ch is >= '0' and <= '7')
            ? Convert.ToInt64(text, 8)
            : long.Parse(text);
        bool outOfRange = val < int.MinValue || val > int.MaxValue;
        return new(isLong || outOfRange ? T.LongConst : T.IntConst, text, val, line, col, _doc);
    }

    private Token LexChar(int line, int col)
    {
        Adv(); // opening '
        int v;
        if (Cur == '\\') v = ReadEscape();   // ReadEscape consumes the escape
        else { v = Cur; Adv(); }
        if (Cur != '\'') throw Err(line, col, "unterminated character constant");
        Adv(); // closing '
        return new(T.CharConst, ((char)v).ToString(), v, line, col, _doc);
    }

    private Token LexString(int line, int col)
    {
        Adv(); // "
        var sb = new System.Text.StringBuilder();
        while (Cur != '"' && _p < _s.Length)
            sb.Append(Cur == '\\' ? (char)ReadEscape() : Consume());
        if (Cur != '"') throw Err(line, col, "unterminated string literal");
        Adv();
        return new(T.StrConst, sb.ToString(), 0, line, col, _doc);
    }

    private char Consume() { char c = Cur; Adv(); return c; }

    private int ReadEscape()
    {
        Adv(); // backslash
        char e = Cur;
        if (e is 'x' or 'X')               // \xHH hex escape
        {
            Adv();
            int v = 0;
            while (Uri.IsHexDigit(Cur)) { v = v * 16 + HexDigit(Cur); Adv(); }
            return v;
        }
        if (e is >= '0' and <= '7')        // \NNN octal escape (1-3 digits)
        {
            int v = 0, n = 0;
            while (Cur is >= '0' and <= '7' && n < 3) { v = v * 8 + (Cur - '0'); Adv(); n++; }
            return v;
        }
        Adv();
        return e switch
        {
            'n' => '\n', 't' => '\t', 'r' => '\r',
            '\\' => '\\', '\'' => '\'', '"' => '"', 'a' => '\a',
            'b' => '\b', 'f' => '\f', 'v' => '\v',
            _ => e
        };
    }

    private static int HexDigit(char c) => c <= '9' ? c - '0' : char.ToLowerInvariant(c) - 'a' + 10;

    private Token LexOp(int line, int col)
    {
        char c = Cur;
        // three-character
        if (c == '.' && Pk() == '.' && Pk(2) == '.') { Adv(); Adv(); Adv(); return Mk(T.Ellipsis, "...", line, col); }
        if (c == '<' && Pk() == '<' && Pk(2) == '=') { Adv3(); return Mk(T.ShlEq, "<<=", line, col); }
        if (c == '>' && Pk() == '>' && Pk(2) == '=') { Adv3(); return Mk(T.ShrEq, ">>=", line, col); }

        // two-character
        (char, char, T, string)[] two =
        {
            ('-', '>', T.Arrow, "->"), ('+', '+', T.Inc, "++"), ('-', '-', T.Dec, "--"),
            ('=', '=', T.EqEq, "=="), ('!', '=', T.NotEq, "!="), ('<', '=', T.Le, "<="),
            ('>', '=', T.Ge, ">="), ('&', '&', T.AmpAmp, "&&"), ('|', '|', T.PipePipe, "||"),
            ('<', '<', T.Shl, "<<"), ('>', '>', T.Shr, ">>"),
            ('+', '=', T.PlusEq, "+="), ('-', '=', T.MinusEq, "-="), ('*', '=', T.StarEq, "*="),
            ('/', '=', T.SlashEq, "/="), ('%', '=', T.PercentEq, "%="), ('&', '=', T.AmpEq, "&="),
            ('|', '=', T.PipeEq, "|="), ('^', '=', T.CaretEq, "^="),
        };
        foreach (var (a, b, kind, txt) in two)
            if (c == a && Pk() == b) { Adv(); Adv(); return Mk(kind, txt, line, col); }

        T single = c switch
        {
            '(' => T.LParen, ')' => T.RParen, '{' => T.LBrace, '}' => T.RBrace,
            '[' => T.LBracket, ']' => T.RBracket, ';' => T.Semi, ',' => T.Comma,
            '.' => T.Dot, '=' => T.Assign, '+' => T.Plus, '-' => T.Minus,
            '*' => T.Star, '/' => T.Slash, '%' => T.Percent, '<' => T.Lt, '>' => T.Gt,
            '!' => T.Not, '&' => T.Amp, '|' => T.Pipe, '^' => T.Caret, '~' => T.Tilde,
            '?' => T.Question, ':' => T.Colon,
            _ => throw Err(line, col, $"unexpected character '{c}'")
        };
        Adv();
        return Mk(single, c.ToString(), line, col);
    }

    private void Adv3() { Adv(); Adv(); Adv(); }
    private Token Mk(T k, string s, int line, int col) => new(k, s, 0, line, col, _doc);
    private static CCompileException Err(int line, int col, string msg)
        => new($"lex error ({line}:{col}): {msg}");
}
