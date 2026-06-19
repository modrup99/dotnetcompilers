namespace TinyC;

public enum TokKind
{
    Ident, Int, Keyword,
    // punctuation / operators
    LParen, RParen, LBrace, RBrace, Comma, Semi,
    Plus, Minus, Star, Slash, Percent, Assign,
    EqEq, NotEq, Lt, Le, Gt, Ge,
    Eof
}

public readonly record struct Token(TokKind Kind, string Text, int Line, int Col);

public sealed class Lexer
{
    private static readonly HashSet<string> Keywords = new()
    {
        "func", "let", "print", "return", "if", "else", "while"
    };

    private readonly string _src;
    private int _pos;
    private int _line = 1;
    private int _col = 1;

    public Lexer(string src) => _src = src;

    private char Cur => _pos < _src.Length ? _src[_pos] : '\0';
    private char Peek => _pos + 1 < _src.Length ? _src[_pos + 1] : '\0';

    private void Advance()
    {
        if (Cur == '\n') { _line++; _col = 1; }
        else _col++;
        _pos++;
    }

    public List<Token> Tokenize()
    {
        var tokens = new List<Token>();
        while (true)
        {
            SkipTrivia();
            if (_pos >= _src.Length) { tokens.Add(new(TokKind.Eof, "", _line, _col)); break; }

            int line = _line, col = _col;
            char c = Cur;

            if (char.IsDigit(c))
            {
                int start = _pos;
                while (char.IsDigit(Cur)) Advance();
                tokens.Add(new(TokKind.Int, _src[start.._pos], line, col));
                continue;
            }

            if (char.IsLetter(c) || c == '_')
            {
                int start = _pos;
                while (char.IsLetterOrDigit(Cur) || Cur == '_') Advance();
                string text = _src[start.._pos];
                tokens.Add(new(Keywords.Contains(text) ? TokKind.Keyword : TokKind.Ident, text, line, col));
                continue;
            }

            tokens.Add(LexOperator(line, col));
        }
        return tokens;
    }

    private Token LexOperator(int line, int col)
    {
        char c = Cur;
        switch (c)
        {
            case '(': Advance(); return new(TokKind.LParen, "(", line, col);
            case ')': Advance(); return new(TokKind.RParen, ")", line, col);
            case '{': Advance(); return new(TokKind.LBrace, "{", line, col);
            case '}': Advance(); return new(TokKind.RBrace, "}", line, col);
            case ',': Advance(); return new(TokKind.Comma, ",", line, col);
            case ';': Advance(); return new(TokKind.Semi, ";", line, col);
            case '+': Advance(); return new(TokKind.Plus, "+", line, col);
            case '-': Advance(); return new(TokKind.Minus, "-", line, col);
            case '*': Advance(); return new(TokKind.Star, "*", line, col);
            case '/': Advance(); return new(TokKind.Slash, "/", line, col);
            case '%': Advance(); return new(TokKind.Percent, "%", line, col);
            case '=':
                Advance();
                if (Cur == '=') { Advance(); return new(TokKind.EqEq, "==", line, col); }
                return new(TokKind.Assign, "=", line, col);
            case '!':
                Advance();
                if (Cur == '=') { Advance(); return new(TokKind.NotEq, "!=", line, col); }
                throw Err(line, col, "unexpected '!'");
            case '<':
                Advance();
                if (Cur == '=') { Advance(); return new(TokKind.Le, "<=", line, col); }
                return new(TokKind.Lt, "<", line, col);
            case '>':
                Advance();
                if (Cur == '=') { Advance(); return new(TokKind.Ge, ">=", line, col); }
                return new(TokKind.Gt, ">", line, col);
            default:
                throw Err(line, col, $"unexpected character '{c}'");
        }
    }

    private void SkipTrivia()
    {
        while (_pos < _src.Length)
        {
            char c = Cur;
            if (c is ' ' or '\t' or '\r' or '\n') { Advance(); continue; }
            // line comment: //
            if (c == '/' && Peek == '/')
            {
                while (_pos < _src.Length && Cur != '\n') Advance();
                continue;
            }
            break;
        }
    }

    private static Exception Err(int line, int col, string msg)
        => new TinyCompileException($"lex error ({line}:{col}): {msg}");
}

public sealed class TinyCompileException(string message) : Exception(message);
