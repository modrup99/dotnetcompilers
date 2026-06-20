using System.Text;

namespace Cc;

// A pragmatic C preprocessor: object- and function-like #define, #undef,
// #include "..."/<...>, #ifdef/#ifndef/#if/#elif/#else/#endif (with defined()
// and constant-expression evaluation), line continuations, and comment removal.
// Not implemented: # stringize and ## paste (rare in hand-written code).
public sealed class Preprocessor
{
    private sealed record Macro(bool Func, List<string> Params, string Body);
    private struct Cond { public bool Active, TakenAny, ParentActive; }

    private readonly Dictionary<string, Macro> _macros = new();
    private readonly string _baseDir;
    private readonly List<string> _includeDirs;

    public Preprocessor(string baseDir, IEnumerable<string>? includeDirs = null)
    {
        _baseDir = baseDir;
        _includeDirs = includeDirs is null ? new List<string>() : new List<string>(includeDirs);
    }

    public string Process(string src)
    {
        var sb = new StringBuilder();
        var cond = new Stack<Cond>();
        Run(JoinContinuations(StripComments(src)), sb, cond);
        return sb.ToString();
    }

    private bool Active(Stack<Cond> c) => c.Count == 0 || c.Peek().Active;

    private void Run(string text, StringBuilder sb, Stack<Cond> cond)
    {
        foreach (var raw in text.Split('\n'))
        {
            string line = raw;
            string t = line.TrimStart();
            if (t.StartsWith("#"))
            {
                Directive(t.Substring(1).TrimStart(), sb, cond);
                continue;
            }
            // keep a 1:1 line mapping (so the lexer's line numbers match the source);
            // inactive regions still emit a blank line.
            sb.Append(Active(cond) ? Expand(line, new HashSet<string>()) : "").Append('\n');
        }
    }

    private void Directive(string d, StringBuilder sb, Stack<Cond> cond)
    {
        string kw = ReadWord(d, out string rest);
        switch (kw)
        {
            case "define" when Active(cond): DefineMacro(rest); break;
            case "undef" when Active(cond): _macros.Remove(ReadWord(rest, out _)); break;
            // #include injects the file's lines; it manages its own newlines.
            case "include" when Active(cond): DoInclude(rest, sb, cond); return;
            // pass #line through so the lexer can remap source positions (for PDB).
            case "line" when Active(cond): sb.Append("#line ").Append(rest).Append('\n'); return;

            case "ifdef": Push(cond, _macros.ContainsKey(ReadWord(rest, out _))); break;
            case "ifndef": Push(cond, !_macros.ContainsKey(ReadWord(rest, out _))); break;
            case "if": Push(cond, EvalIf(rest) != 0); break;
            case "elif": Elif(cond, EvalIf(rest) != 0); break;
            case "else": Else(cond); break;
            case "endif": if (cond.Count > 0) cond.Pop(); break;

            // #error/#pragma/#warning and unknown directives: ignore
            default: break;
        }
        sb.Append('\n');   // consumed directive -> one blank line, preserving line numbers
    }

    private void Push(Stack<Cond> cond, bool test)
    {
        bool parent = Active(cond);
        cond.Push(new Cond { ParentActive = parent, Active = parent && test, TakenAny = parent && test });
    }
    private void Elif(Stack<Cond> cond, bool test)
    {
        if (cond.Count == 0) return;
        var c = cond.Pop();
        if (!c.TakenAny && c.ParentActive && test) { c.Active = true; c.TakenAny = true; }
        else c.Active = false;
        cond.Push(c);
    }
    private void Else(Stack<Cond> cond)
    {
        if (cond.Count == 0) return;
        var c = cond.Pop();
        c.Active = c.ParentActive && !c.TakenAny; c.TakenAny = true;
        cond.Push(c);
    }

    private void DefineMacro(string rest)
    {
        string name = ReadIdent(rest, out int after);
        if (name.Length == 0) return;
        if (after < rest.Length && rest[after] == '(')   // function-like (no space before '(')
        {
            int close = rest.IndexOf(')', after);
            var ps = rest.Substring(after + 1, close - after - 1)
                         .Split(',').Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
            _macros[name] = new Macro(true, ps, rest.Substring(close + 1).Trim());
        }
        else
        {
            _macros[name] = new Macro(false, new(), rest.Substring(after).Trim());
        }
    }

    private void DoInclude(string rest, StringBuilder sb, Stack<Cond> cond)
    {
        rest = rest.Trim();
        if (rest.Length < 2) return;
        char open = rest[0];
        if (open != '"' && open != '<') return;
        char close = open == '"' ? '"' : '>';
        int end = rest.IndexOf(close, 1);
        if (end < 0) return;
        string name = rest.Substring(1, end - 1);
        // search the base directory first, then each -I directory in order
        string? path = null;
        string cand = Path.Combine(_baseDir, name);
        if (File.Exists(cand)) path = cand;
        else foreach (var d in _includeDirs) { string c = Path.Combine(d, name); if (File.Exists(c)) { path = c; break; } }
        if (path is null) return;                  // missing/system headers: no-op (libc is built in)
        Run(JoinContinuations(StripComments(File.ReadAllText(path))), sb, cond);
    }

    // ---- macro expansion (span-based, preserves operators/layout) ------
    private string Expand(string s, HashSet<string> hide)
    {
        var sb = new StringBuilder();
        int i = 0;
        while (i < s.Length)
        {
            char c = s[i];
            if (c == '"' || c == '\'') { i = CopyLiteral(s, i, sb); continue; }
            if (IsIdentStart(c))
            {
                int st = i; while (i < s.Length && IsIdentPart(s[i])) i++;
                string id = s.Substring(st, i - st);
                if (!hide.Contains(id) && _macros.TryGetValue(id, out var m))
                {
                    if (!m.Func) { sb.Append(Expand(m.Body, Plus(hide, id))); continue; }
                    int j = i; while (j < s.Length && char.IsWhiteSpace(s[j])) j++;
                    if (j < s.Length && s[j] == '(')
                    {
                        var args = ReadArgs(s, j, out int afterCall);
                        i = afterCall;
                        sb.Append(Expand(SubstParams(m, args), Plus(hide, id)));
                        continue;
                    }
                    sb.Append(id); continue;   // function-like name without '(' is plain text
                }
                sb.Append(id); continue;
            }
            sb.Append(c); i++;
        }
        return sb.ToString();
    }

    private List<string> ReadArgs(string s, int open, out int afterCall)
    {
        var args = new List<string>();
        int j = open + 1, start = j, depth = 1;
        while (j < s.Length && depth > 0)
        {
            char d = s[j];
            if (d == '(') depth++;
            else if (d == ')') { depth--; if (depth == 0) break; }
            else if (d == ',' && depth == 1) { args.Add(s.Substring(start, j - start)); start = j + 1; }
            j++;
        }
        args.Add(s.Substring(start, j - start));
        afterCall = j + 1;
        return args;
    }

    private string SubstParams(Macro m, List<string> args)
    {
        var raw = new Dictionary<string, string>();
        var exp = new Dictionary<string, string>();
        for (int k = 0; k < m.Params.Count; k++)
        {
            string a = k < args.Count ? args[k].Trim() : "";
            raw[m.Params[k]] = a;
            exp[m.Params[k]] = Expand(a, new HashSet<string>());
        }
        var toks = TokenizeBody(m.Body);
        var outTok = new List<string>();
        for (int i = 0; i < toks.Count; i++)
        {
            string tk = toks[i];
            if (tk == "#" && i + 1 < toks.Count && raw.ContainsKey(toks[i + 1]))   // stringize
            {
                outTok.Add("\"" + raw[toks[++i]].Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"");
            }
            else if (tk == "##" && i + 1 < toks.Count)                              // token paste
            {
                string next = toks[++i];
                string nv = raw.TryGetValue(next, out var nr) ? nr : next;
                if (outTok.Count > 0) outTok[^1] += nv; else outTok.Add(nv);
            }
            else outTok.Add(exp.TryGetValue(tk, out var ev) ? ev : tk);
        }
        return string.Join(" ", outTok);
    }

    private static List<string> TokenizeBody(string s)
    {
        var t = new List<string>();
        int i = 0;
        while (i < s.Length)
        {
            char c = s[i];
            if (char.IsWhiteSpace(c)) { i++; continue; }
            if (c == '#') { if (i + 1 < s.Length && s[i + 1] == '#') { t.Add("##"); i += 2; } else { t.Add("#"); i++; } continue; }
            if (c == '"' || c == '\'') { var sb = new StringBuilder(); i = CopyLiteral(s, i, sb); t.Add(sb.ToString()); continue; }
            if (IsIdentStart(c)) { int st = i; while (i < s.Length && IsIdentPart(s[i])) i++; t.Add(s.Substring(st, i - st)); continue; }
            int s2 = i; while (i < s.Length && !char.IsWhiteSpace(s[i]) && s[i] != '#' && !IsIdentStart(s[i]) && s[i] != '"' && s[i] != '\'') i++;
            t.Add(s.Substring(s2, i - s2));
        }
        return t;
    }

    // ---- #if constant-expression evaluation ----------------------------
    private long EvalIf(string expr)
    {
        expr = ReplaceDefined(expr);
        expr = Expand(expr, new HashSet<string>());
        var toks = TokenizeExpr(expr);
        int pos = 0;
        return ParseExpr(toks, ref pos, 0);
    }

    private string ReplaceDefined(string e)
    {
        var sb = new StringBuilder();
        int i = 0;
        while (i < e.Length)
        {
            if (IsIdentStart(e[i]))
            {
                int st = i; while (i < e.Length && IsIdentPart(e[i])) i++;
                string id = e.Substring(st, i - st);
                if (id == "defined")
                {
                    int j = i; while (j < e.Length && char.IsWhiteSpace(e[j])) j++;
                    string name;
                    if (j < e.Length && e[j] == '(') { int k = e.IndexOf(')', j); name = e.Substring(j + 1, k - j - 1).Trim(); i = k + 1; }
                    else { int s2 = j; while (j < e.Length && IsIdentPart(e[j])) j++; name = e.Substring(s2, j - s2); i = j; }
                    sb.Append(_macros.ContainsKey(name) ? "1" : "0");
                }
                else sb.Append(id);
            }
            else { sb.Append(e[i]); i++; }
        }
        return sb.ToString();
    }

    private static List<string> TokenizeExpr(string e)
    {
        var toks = new List<string>();
        int i = 0;
        while (i < e.Length)
        {
            char c = e[i];
            if (char.IsWhiteSpace(c)) { i++; continue; }
            if (char.IsDigit(c))
            {
                int st = i;
                if (c == '0' && i + 1 < e.Length && (e[i + 1] is 'x' or 'X')) { i += 2; while (i < e.Length && Uri.IsHexDigit(e[i])) i++; }
                else while (i < e.Length && char.IsLetterOrDigit(e[i])) i++;
                toks.Add(e.Substring(st, i - st));
                continue;
            }
            if (IsIdentStart(c)) { while (i < e.Length && IsIdentPart(e[i])) i++; toks.Add("0"); continue; } // undefined id => 0
            string two = i + 1 < e.Length ? e.Substring(i, 2) : "";
            if (two is "==" or "!=" or "<=" or ">=" or "&&" or "||" or "<<" or ">>") { toks.Add(two); i += 2; continue; }
            toks.Add(c.ToString()); i++;
        }
        return toks;
    }

    // precedence-climbing evaluator over the token list
    private long ParseExpr(List<string> t, ref int pos, int minPrec)
    {
        long left = ParseUnary(t, ref pos);
        while (pos < t.Count)
        {
            string op = t[pos];
            int prec = Prec(op);
            if (prec < minPrec || prec < 0) break;
            pos++;
            long right = ParseExpr(t, ref pos, prec + 1);
            left = Apply(op, left, right);
        }
        return left;
    }
    private long ParseUnary(List<string> t, ref int pos)
    {
        if (pos >= t.Count) return 0;
        string x = t[pos];
        if (x == "!") { pos++; return ParseUnary(t, ref pos) == 0 ? 1 : 0; }
        if (x == "~") { pos++; return ~ParseUnary(t, ref pos); }
        if (x == "-") { pos++; return -ParseUnary(t, ref pos); }
        if (x == "+") { pos++; return ParseUnary(t, ref pos); }
        if (x == "(") { pos++; long v = ParseExpr(t, ref pos, 0); if (pos < t.Count && t[pos] == ")") pos++; return v; }
        pos++;
        return x.StartsWith("0x") || x.StartsWith("0X") ? Convert.ToInt64(x.Substring(2), 16)
             : long.TryParse(x, out long n) ? n : 0;
    }
    private static int Prec(string op) => op switch
    {
        "||" => 1, "&&" => 2, "|" => 3, "^" => 4, "&" => 5,
        "==" or "!=" => 6, "<" or "<=" or ">" or ">=" => 7,
        "<<" or ">>" => 8, "+" or "-" => 9, "*" or "/" or "%" => 10,
        _ => -1
    };
    private static long Apply(string op, long a, long b) => op switch
    {
        "||" => (a != 0 || b != 0) ? 1 : 0, "&&" => (a != 0 && b != 0) ? 1 : 0,
        "|" => a | b, "^" => a ^ b, "&" => a & b,
        "==" => a == b ? 1 : 0, "!=" => a != b ? 1 : 0,
        "<" => a < b ? 1 : 0, "<=" => a <= b ? 1 : 0, ">" => a > b ? 1 : 0, ">=" => a >= b ? 1 : 0,
        "<<" => a << (int)b, ">>" => a >> (int)b,
        "+" => a + b, "-" => a - b, "*" => a * b, "/" => b != 0 ? a / b : 0, "%" => b != 0 ? a % b : 0,
        _ => 0
    };

    // ---- lexical helpers ----------------------------------------------
    private static string StripComments(string s)
    {
        var sb = new StringBuilder(s.Length);
        int i = 0;
        while (i < s.Length)
        {
            char c = s[i];
            if (c == '"' || c == '\'') { i = CopyLiteral(s, i, sb); continue; }
            if (c == '/' && i + 1 < s.Length && s[i + 1] == '/') { while (i < s.Length && s[i] != '\n') i++; continue; }
            if (c == '/' && i + 1 < s.Length && s[i + 1] == '*')
            {
                i += 2; while (i + 1 < s.Length && !(s[i] == '*' && s[i + 1] == '/')) { if (s[i] == '\n') sb.Append('\n'); i++; }
                i += 2; sb.Append(' '); continue;
            }
            sb.Append(c); i++;
        }
        return sb.ToString();
    }

    private static string JoinContinuations(string s) => s.Replace("\\\r\n", "").Replace("\\\n", "");

    private static int CopyLiteral(string s, int i, StringBuilder sb)
    {
        char q = s[i]; sb.Append(q); i++;
        while (i < s.Length)
        {
            sb.Append(s[i]);
            if (s[i] == '\\' && i + 1 < s.Length) { sb.Append(s[i + 1]); i += 2; continue; }
            if (s[i] == q) { i++; break; }
            i++;
        }
        return i;
    }

    private static bool IsIdentStart(char c) => char.IsLetter(c) || c == '_';
    private static bool IsIdentPart(char c) => char.IsLetterOrDigit(c) || c == '_';
    private static HashSet<string> Plus(HashSet<string> h, string s) => new(h) { s };

    private static string ReadWord(string s, out string rest)
    {
        int i = 0; while (i < s.Length && !char.IsWhiteSpace(s[i])) i++;
        rest = s.Substring(i).TrimStart();
        return s.Substring(0, i);
    }
    private static string ReadIdent(string s, out int after)
    {
        int i = 0; while (i < s.Length && IsIdentPart(s[i])) i++;
        after = i; return s.Substring(0, i);
    }
}
