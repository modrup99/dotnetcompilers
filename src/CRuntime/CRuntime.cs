using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CRuntimeLib;

// The C abstract machine + a libc subset, for assemblies emitted by `cc`.
//
// Memory model: one flat byte arena `Mem`. A C pointer is just an int address
// into it, so pointer arithmetic is integer arithmetic, casts are free, and
// unions/struct layout are faithful (everything is bytes). Address 0 is NULL.
//
// Layout:  [0..7] null guard | data+heap growing up (_brk) | C stack growing
// down from the top (_sp). malloc/free use a simple size-prefixed free list.
//
// The compiler emits calls to the Ld*/St*/Stack*/DataAlloc/InternString helpers
// (its internal ABI) and to the libc functions (bound by their C names).
public static class CRuntime
{
    private const int MemSize = 256 * 1024 * 1024;
    private static readonly byte[] Mem = new byte[MemSize];
    private static int _brk = 8;            // bump pointer for data + heap
    private static int _sp = MemSize;       // C stack top (grows down)
    private static int _freeList = 0;       // malloc free list head

    // ---- typed load / store (compiler ABI) -----------------------------
    public static int LdU8(int a) => Mem[a];
    public static int LdI8(int a) => (sbyte)Mem[a];
    public static int LdU16(int a) => Mem[a] | (Mem[a + 1] << 8);
    public static int LdI16(int a) => (short)(Mem[a] | (Mem[a + 1] << 8));
    public static int LdI32(int a) => Mem[a] | (Mem[a + 1] << 8) | (Mem[a + 2] << 16) | (Mem[a + 3] << 24);

    public static int StI8(int a, int v) { Mem[a] = (byte)v; return v; }
    public static int StI16(int a, int v) { Mem[a] = (byte)v; Mem[a + 1] = (byte)(v >> 8); return v; }
    public static int StI32(int a, int v)
    {
        Mem[a] = (byte)v; Mem[a + 1] = (byte)(v >> 8);
        Mem[a + 2] = (byte)(v >> 16); Mem[a + 3] = (byte)(v >> 24);
        return v;
    }

    public static long LdI64(int a) => BitConverter.ToInt64(Mem, a);
    public static long StI64(int a, long v) { BitConverter.GetBytes(v).CopyTo(Mem, a); return v; }

    // floating load/store (values live as double on the IL stack)
    public static double LdF64(int a) => BitConverter.ToDouble(Mem, a);
    public static double LdF32(int a) => BitConverter.ToSingle(Mem, a);
    public static double StF64(int a, double v) { BitConverter.GetBytes(v).CopyTo(Mem, a); return v; }
    public static double StF32(int a, double v) { BitConverter.GetBytes((float)v).CopyTo(Mem, a); return v; }

    // ---- allocation (compiler ABI) -------------------------------------
    private static int Align(int n) => (n + 3) & ~3;

    public static int DataAlloc(int n)
    {
        int a = _brk;
        _brk += Align(n);
        if (_brk >= _sp) throw new InvalidOperationException("C heap/stack collision");
        return a; // freshly zeroed (arena starts zero, data never reused)
    }

    public static int StackSave() => _sp;
    public static int StackAlloc(int n)
    {
        _sp -= Align(n);
        if (_sp <= _brk) throw new InvalidOperationException("C stack overflow");
        return _sp;
    }
    public static void StackRestore(int sp) => _sp = sp;

    public static int InternString(string s)
    {
        int a = DataAlloc(s.Length + 1);
        for (int i = 0; i < s.Length; i++) Mem[a + i] = (byte)s[i];
        Mem[a + s.Length] = 0;
        return a;
    }

    // ---- <stdlib.h> ----------------------------------------------------
    public static int malloc(int n)
    {
        if (n <= 0) n = 1;
        n = Align(n);
        int prev = 0, cur = _freeList;
        while (cur != 0)
        {
            int bsz = LdI32(cur - 4);
            if (bsz >= n)
            {
                int next = LdI32(cur);
                if (prev == 0) _freeList = next; else StI32(prev, next);
                return cur;
            }
            prev = cur; cur = LdI32(cur);
        }
        int hdr = DataAlloc(n + 4);
        StI32(hdr, n);
        return hdr + 4;
    }

    public static void free(int p)
    {
        if (p == 0) return;
        StI32(p, _freeList); // store next-link in the payload
        _freeList = p;
    }

    public static int calloc(int count, int size)
    {
        int n = count * size;
        int p = malloc(n);
        for (int i = 0; i < n; i++) Mem[p + i] = 0;
        return p;
    }

    public static int realloc(int p, int n)
    {
        if (p == 0) return malloc(n);
        int old = LdI32(p - 4);
        int q = malloc(n);
        int copy = Math.Min(old, n);
        Array.Copy(Mem, p, Mem, q, copy);
        free(p);
        return q;
    }

    public static int atoi(int s)
    {
        int i = s, sign = 1, val = 0;
        while (Mem[i] is (byte)' ' or (byte)'\t' or (byte)'\n') i++;
        if (Mem[i] == '+') i++; else if (Mem[i] == '-') { sign = -1; i++; }
        while (Mem[i] >= '0' && Mem[i] <= '9') { val = val * 10 + (Mem[i] - '0'); i++; }
        return sign * val;
    }
    public static int atol(int s) => atoi(s);
    public static int abs(int v) => Math.Abs(v);
    public static void exit(int code) { FlushAll(); Environment.Exit(code); }
    public static void abort() { FlushAll(); Environment.Exit(134); }

    private static uint _seed = 1;
    public static void srand(int s) => _seed = (uint)s;
    public static int rand() { _seed = _seed * 1103515245 + 12345; return (int)((_seed >> 16) & 0x7FFF); }

    public static double atof(int s)
    { double.TryParse(ReadCStr(s), NumberStyles.Any, CultureInfo.InvariantCulture, out double d); return d; }

    // ---- <math.h> ------------------------------------------------------
    public static double sqrt(double x) => Math.Sqrt(x);
    public static double pow(double a, double b) => Math.Pow(a, b);
    public static double sin(double x) => Math.Sin(x);
    public static double cos(double x) => Math.Cos(x);
    public static double tan(double x) => Math.Tan(x);
    public static double asin(double x) => Math.Asin(x);
    public static double acos(double x) => Math.Acos(x);
    public static double atan(double x) => Math.Atan(x);
    public static double atan2(double y, double x) => Math.Atan2(y, x);
    public static double exp(double x) => Math.Exp(x);
    public static double log(double x) => Math.Log(x);
    public static double log10(double x) => Math.Log10(x);
    public static double floor(double x) => Math.Floor(x);
    public static double ceil(double x) => Math.Ceiling(x);
    public static double round(double x) => Math.Round(x, MidpointRounding.AwayFromZero);
    public static double trunc(double x) => Math.Truncate(x);
    public static double fabs(double x) => Math.Abs(x);
    public static double fmod(double a, double b) => a % b;

    // ---- <string.h> ----------------------------------------------------
    public static int strlen(int s) { int n = 0; while (Mem[s + n] != 0) n++; return n; }

    public static int strcpy(int d, int s)
    {
        int i = 0;
        do { Mem[d + i] = Mem[s + i]; } while (Mem[s + i++] != 0);
        return d;
    }
    public static int strncpy(int d, int s, int n)
    {
        int i = 0;
        for (; i < n && Mem[s + i] != 0; i++) Mem[d + i] = Mem[s + i];
        for (; i < n; i++) Mem[d + i] = 0;
        return d;
    }
    public static int strcat(int d, int s) { strcpy(d + strlen(d), s); return d; }
    public static int strncat(int d, int s, int n)
    {
        int dl = strlen(d), i = 0;
        for (; i < n && Mem[s + i] != 0; i++) Mem[d + dl + i] = Mem[s + i];
        Mem[d + dl + i] = 0;
        return d;
    }
    public static int strcmp(int a, int b)
    {
        int i = 0;
        while (Mem[a + i] != 0 && Mem[a + i] == Mem[b + i]) i++;
        return Mem[a + i] - Mem[b + i];
    }
    public static int strncmp(int a, int b, int n)
    {
        for (int i = 0; i < n; i++)
        {
            int d = Mem[a + i] - Mem[b + i];
            if (d != 0 || Mem[a + i] == 0) return d;
        }
        return 0;
    }
    public static int strchr(int s, int c)
    {
        for (int i = 0; ; i++)
        {
            if (Mem[s + i] == (byte)c) return s + i;
            if (Mem[s + i] == 0) return 0;
        }
    }
    public static int strrchr(int s, int c)
    {
        int last = 0;
        for (int i = 0; ; i++) { if (Mem[s + i] == (byte)c) last = s + i; if (Mem[s + i] == 0) return last; }
    }
    public static int strstr(int h, int n)
    {
        int nl = strlen(n);
        if (nl == 0) return h;
        for (int i = 0; Mem[h + i] != 0; i++)
            if (strncmp(h + i, n, nl) == 0) return h + i;
        return 0;
    }
    public static int strdup(int s) { int n = strlen(s) + 1; int p = malloc(n); Array.Copy(Mem, s, Mem, p, n); return p; }

    public static int memcpy(int d, int s, int n) { Array.Copy(Mem, s, Mem, d, n); return d; }
    public static int memmove(int d, int s, int n) { Array.Copy(Mem, s, Mem, d, n); return d; }
    public static int memset(int d, int c, int n) { for (int i = 0; i < n; i++) Mem[d + i] = (byte)c; return d; }
    public static int memcmp(int a, int b, int n)
    {
        for (int i = 0; i < n; i++) { int x = Mem[a + i] - Mem[b + i]; if (x != 0) return x; }
        return 0;
    }

    // ---- <ctype.h> -----------------------------------------------------
    public static int isalpha(int c) => (c is >= 'a' and <= 'z' or >= 'A' and <= 'Z') ? 1 : 0;
    public static int isdigit(int c) => (c is >= '0' and <= '9') ? 1 : 0;
    public static int isalnum(int c) => (isalpha(c) != 0 || isdigit(c) != 0) ? 1 : 0;
    public static int isspace(int c) => (c is ' ' or '\t' or '\n' or '\r' or '\f' or '\v') ? 1 : 0;
    public static int isupper(int c) => (c is >= 'A' and <= 'Z') ? 1 : 0;
    public static int islower(int c) => (c is >= 'a' and <= 'z') ? 1 : 0;
    public static int isxdigit(int c) => (isdigit(c) != 0 || c is >= 'a' and <= 'f' or >= 'A' and <= 'F') ? 1 : 0;
    public static int ispunct(int c) => (c > 32 && c < 127 && isalnum(c) == 0) ? 1 : 0;
    public static int iscntrl(int c) => (c is >= 0 and < 32 or 127) ? 1 : 0;
    public static int isprint(int c) => (c is >= 32 and < 127) ? 1 : 0;
    public static int toupper(int c) => islower(c) != 0 ? c - 32 : c;
    public static int tolower(int c) => isupper(c) != 0 ? c + 32 : c;

    // ---- <stdio.h> -----------------------------------------------------
    // FILE* is an opaque small int handle (never a Mem address). 1/2/3 = std streams.
    private static readonly List<Stream> _files = new() { null, null, null, null };
    private static Stream _in, _out, _err;

    private static Stream FileFor(int h) => h switch
    {
        1 => _in ??= Console.OpenStandardInput(),
        2 => _out ??= Console.OpenStandardOutput(),
        3 => _err ??= Console.OpenStandardError(),
        _ => (h > 0 && h < _files.Count) ? _files[h] : null
    };
    private static void FlushAll() { try { _out?.Flush(); _err?.Flush(); } catch { } }

    public static int fopen(int path, int mode)
    {
        string p = ReadCStr(path), m = ReadCStr(mode);
        FileMode fm = m.Contains('a') ? FileMode.Append : m.Contains('w') ? FileMode.Create : FileMode.Open;
        FileAccess fa = m.Contains('+') ? FileAccess.ReadWrite
            : (m.Contains('w') || m.Contains('a')) ? FileAccess.Write : FileAccess.Read;
        try { _files.Add(new FileStream(p, fm, fa)); return _files.Count - 1; }
        catch { return 0; }
    }
    public static int fclose(int h)
    {
        if (h > 3 && h < _files.Count && _files[h] != null) { _files[h].Dispose(); _files[h] = null; }
        else FileFor(h)?.Flush();
        return 0;
    }
    public static int fgetc(int h) { var s = FileFor(h); int b = s?.ReadByte() ?? -1; return b; }
    public static int getchar() => fgetc(1);
    public static int fputc(int c, int h)
    {
        if ((h == 2 || h == 3) && HostOut != null) { HostOut(new[] { (byte)c }); return c; }
        var s = FileFor(h); s?.WriteByte((byte)c); if (h == 2 || h == 3) s?.Flush(); return c;
    }
    public static int putchar(int c) => fputc(c, 2);
    public static int putint(int v) { var b = Encoding.Latin1.GetBytes(v.ToString() + "\n"); WriteBytes(2, b); return v; }

    public static int fputs(int s, int h) { WriteBytes(h, ReadCBytes(s)); return 0; }
    public static int puts(int s) { WriteBytes(2, ReadCBytes(s)); WriteBytes(2, new byte[] { (byte)'\n' }); return 0; }

    public static int fgets(int buf, int n, int h)
    {
        var s = FileFor(h);
        if (s == null || n <= 0) return 0;
        int i = 0;
        while (i < n - 1)
        {
            int b = s.ReadByte();
            if (b < 0) { if (i == 0) return 0; break; }
            Mem[buf + i++] = (byte)b;
            if (b == '\n') break;
        }
        Mem[buf + i] = 0;
        return buf;
    }

    public static int fread(int ptr, int size, int nmemb, int h)
    {
        var s = FileFor(h); if (s == null) return 0;
        int total = size * nmemb, got = 0;
        while (got < total) { int b = s.ReadByte(); if (b < 0) break; Mem[ptr + got++] = (byte)b; }
        return size == 0 ? 0 : got / size;
    }
    public static int fwrite(int ptr, int size, int nmemb, int h)
    {
        int total = size * nmemb;
        var b = new byte[total];
        Array.Copy(Mem, ptr, b, 0, total);
        WriteBytes(h, b);
        return nmemb;
    }
    public static int feof(int h) { var s = FileFor(h); return (s != null && s.CanSeek && s.Position >= s.Length) ? 1 : 0; }

    public static int printf(int fmt, object[] args) { var b = Encoding.Latin1.GetBytes(Format(fmt, args)); WriteBytes(2, b); return b.Length; }
    public static int fprintf(int h, int fmt, object[] args) { var b = Encoding.Latin1.GetBytes(Format(fmt, args)); WriteBytes(h, b); return b.Length; }
    public static int sprintf(int dst, int fmt, object[] args)
    {
        string r = Format(fmt, args);
        for (int i = 0; i < r.Length; i++) Mem[dst + i] = (byte)r[i];
        Mem[dst + r.Length] = 0;
        return r.Length;
    }
    public static int snprintf(int dst, int n, int fmt, object[] args)
    {
        string r = Format(fmt, args);
        int w = Math.Min(r.Length, Math.Max(0, n - 1));
        for (int i = 0; i < w; i++) Mem[dst + i] = (byte)r[i];
        if (n > 0) Mem[dst + w] = 0;
        return r.Length;
    }

    // ---- more <string.h> ----------------------------------------------
    public static int memchr(int s, int c, int n) { for (int i = 0; i < n; i++) if (Mem[s + i] == (byte)c) return s + i; return 0; }
    public static int strpbrk(int s, int set) { for (int i = s; Mem[i] != 0; i++) if (strchr(set, Mem[i]) != 0) return i; return 0; }
    public static int strspn(int s, int set) { int n = 0; while (Mem[s + n] != 0 && strchr(set, Mem[s + n]) != 0) n++; return n; }
    public static int strcspn(int s, int set) { int n = 0; while (Mem[s + n] != 0 && strchr(set, Mem[s + n]) == 0) n++; return n; }

    // ---- more <stdlib.h> ----------------------------------------------
    public static long labs(long v) => Math.Abs(v);
    public static long llabs(long v) => Math.Abs(v);
    public static long atoll(int s)
    {
        int i = s; long sign = 1, val = 0;
        while (IsWs(Mem[i])) i++;
        if (Mem[i] == '+') i++; else if (Mem[i] == '-') { sign = -1; i++; }
        while (Mem[i] >= '0' && Mem[i] <= '9') { val = val * 10 + (Mem[i] - '0'); i++; }
        return sign * val;
    }
    public static long strtol(int s, int endptr, int bas)
    {
        int i = s; while (IsWs(Mem[i])) i++;
        long sign = 1; if (Mem[i] == '+') i++; else if (Mem[i] == '-') { sign = -1; i++; }
        if (bas == 0) { if (Mem[i] == '0' && (Mem[i + 1] is (byte)'x' or (byte)'X')) { bas = 16; i += 2; } else if (Mem[i] == '0') bas = 8; else bas = 10; }
        else if (bas == 16 && Mem[i] == '0' && (Mem[i + 1] is (byte)'x' or (byte)'X')) i += 2;
        long v = 0; while (true) { int d = HexVal(Mem[i]); if (d < 0 || d >= bas) break; v = v * bas + d; i++; }
        if (endptr != 0) StI32(endptr, i);
        return sign * v;
    }
    public static long strtoul(int s, int endptr, int bas) => strtol(s, endptr, bas);
    public static double strtod(int s, int endptr)
    {
        int i = s; while (IsWs(Mem[i])) i++;
        int st = i;
        if (Mem[i] is (byte)'+' or (byte)'-') i++;
        while (Mem[i] >= '0' && Mem[i] <= '9') i++;
        if (Mem[i] == '.') { i++; while (Mem[i] >= '0' && Mem[i] <= '9') i++; }
        if (Mem[i] is (byte)'e' or (byte)'E') { i++; if (Mem[i] is (byte)'+' or (byte)'-') i++; while (Mem[i] >= '0' && Mem[i] <= '9') i++; }
        double d = double.TryParse(ReadRange(st, i), NumberStyles.Any, CultureInfo.InvariantCulture, out double r) ? r : 0;
        if (endptr != 0) StI32(endptr, i);
        return d;
    }

    // ---- more <stdio.h> -----------------------------------------------
    public static int fseek(int h, int off, int whence)
    {
        var s = FileFor(h); if (s == null) return -1;
        s.Seek(off, whence == 1 ? SeekOrigin.Current : whence == 2 ? SeekOrigin.End : SeekOrigin.Begin);
        return 0;
    }
    public static int ftell(int h) { var s = FileFor(h); return s == null ? -1 : (int)s.Position; }
    public static int rewind(int h) { var s = FileFor(h); if (s != null) s.Seek(0, SeekOrigin.Begin); return 0; }
    public static int fflush(int h) { if (h == 0) { _out?.Flush(); _err?.Flush(); } else FileFor(h)?.Flush(); return 0; }

    // ---- shell support (process execution, redirection, env) -----------
    private static readonly Dictionary<string, string> _exports = new();
    private static string _rIn, _rOut; private static bool _rApp, _pIn, _pOut;
    private static byte[] _pData = System.Array.Empty<byte>();
    private static MemoryStream _sinkMs; private static Stream _sinkFile;
    private static MemoryStream _capCur;                      // current $(...) capture buffer (null = not capturing)

    // command substitution: isolate the inner command from outer pipe/redirect state,
    // capture its stdout to a fresh buffer, then restore. Supports nesting via a stack.
    private sealed class SinkCtx { public string rIn, rOut; public bool rApp, pIn, pOut; public MemoryStream sinkMs, capCur; public Stream sinkFile; }
    private static readonly Stack<SinkCtx> _capStack = new();
    public static void sh_capture_begin()
    {
        _capStack.Push(new SinkCtx { rIn = _rIn, rOut = _rOut, rApp = _rApp, pIn = _pIn, pOut = _pOut, sinkMs = _sinkMs, sinkFile = _sinkFile, capCur = _capCur });
        _rIn = null; _rOut = null; _rApp = false; _pIn = false; _pOut = false; _sinkMs = null; _sinkFile = null;
        _capCur = new MemoryStream();
    }
    public static int sh_capture_end()
    {
        byte[] bytes = _capCur != null ? _capCur.ToArray() : System.Array.Empty<byte>();
        _capCur?.Dispose();
        var c = _capStack.Count > 0 ? _capStack.Pop() : new SinkCtx();
        _rIn = c.rIn; _rOut = c.rOut; _rApp = c.rApp; _pIn = c.pIn; _pOut = c.pOut; _sinkMs = c.sinkMs; _sinkFile = c.sinkFile; _capCur = c.capCur;
        int len = bytes.Length;
        while (len > 0 && (bytes[len - 1] == (byte)'\n' || bytes[len - 1] == (byte)'\r')) len--;   // strip trailing newlines
        return Cstr(Encoding.Latin1.GetString(bytes, 0, len));
    }

    public static void sh_clear() { _rIn = null; _rOut = null; _rApp = false; _pIn = false; _pOut = false; }
    public static void sh_rin(int p) { _rIn = ReadCStr(p); }
    public static void sh_rout(int p, int app) { _rOut = ReadCStr(p); _rApp = app != 0; }
    public static void sh_pin() { _pIn = true; }
    public static void sh_pout() { _pOut = true; }

    private static Stream CurSink()   // null => inherit console
    {
        if (_pOut) return _sinkMs ??= new MemoryStream();
        if (_rOut != null) return _sinkFile ??= new FileStream(_rOut, _rApp ? FileMode.Append : FileMode.Create, FileAccess.Write);
        if (_capCur != null) return _capCur;           // inside $(...) -> capture
        return null;
    }
    public static void sh_end()
    {
        if (_pOut && _sinkMs != null) _pData = _sinkMs.ToArray();
        _sinkMs?.Dispose(); _sinkMs = null; _sinkFile?.Dispose(); _sinkFile = null;
        sh_clear();
    }

    public static int sh_write(int s) { var b = ReadCBytes(s); var k = CurSink(); if (k != null) k.Write(b, 0, b.Length); else WriteBytes(2, b); return 0; }

    // resolve a program path: a relative path that contains a separator (e.g.
    // "yacc/yacc.exe", "./tool") is made absolute against the current directory,
    // so the shell can launch tools by relative path like a real shell.
    private static string ResolveExe(string fn)
    {
        if ((fn.Contains('/') || fn.Contains('\\')) && !Path.IsPathRooted(fn))
            try { return Path.GetFullPath(fn); } catch { }
        return fn;
    }

    public static int sh_run(int argv, int argc)
    {
        var a = new List<string>();
        for (int k = 0; k < argc; k++) a.Add(ReadCStr(LdI32(argv + k * 4)));
        if (a.Count == 0) return 0;
        var snk = CurSink();
        var psi = new ProcessStartInfo { FileName = ResolveExe(a[0]), UseShellExecute = false, RedirectStandardOutput = snk != null, RedirectStandardInput = _pIn || _rIn != null };
        for (int k = 1; k < a.Count; k++) psi.ArgumentList.Add(a[k]);
        foreach (var kv in _exports) psi.Environment[kv.Key] = kv.Value;
        Process pr;
        try { pr = Process.Start(psi); }
        catch { WriteBytes(3, Encoding.Latin1.GetBytes(a[0] + ": command not found\n")); return 127; }
        if (psi.RedirectStandardInput)
        {
            byte[] inp = _pIn ? _pData : File.ReadAllBytes(_rIn);
            pr.StandardInput.BaseStream.Write(inp, 0, inp.Length); pr.StandardInput.Close();
        }
        if (snk != null) pr.StandardOutput.BaseStream.CopyTo(snk);
        pr.WaitForExit();
        return pr.ExitCode;
    }

    private static readonly List<Process> _jobs = new();
    public static int sh_run_bg(int argv, int argc)   // launch detached (good for GUI editors); don't wait
    {
        var a = new List<string>();
        for (int k = 0; k < argc; k++) a.Add(ReadCStr(LdI32(argv + k * 4)));
        if (a.Count == 0) return -1;
        var psi = new ProcessStartInfo { FileName = ResolveExe(a[0]), UseShellExecute = true };
        for (int k = 1; k < a.Count; k++) psi.ArgumentList.Add(a[k]);
        try { var p = Process.Start(psi); _jobs.Add(p); return p.Id; } catch { return -1; }
    }
    public static void sh_jobs()
    {
        for (int i = 0; i < _jobs.Count; i++)
        {
            string st; try { st = _jobs[i].HasExited ? "done" : "running"; } catch { st = "?"; }
            WriteBytes(2, Encoding.Latin1.GetBytes($"[{i + 1}] {_jobs[i].Id} {st}\n"));
        }
    }
    // %APPDATA%\ilsh — holds appsettings.json and (by default) the shell HOME.
    private static string AppDir()
    {
        try { string d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ilsh"); Directory.CreateDirectory(d); return d; }
        catch { return "."; }
    }
    private static string ReadSetting(string cfg, string key)
    {
        try { if (File.Exists(cfg)) { using var doc = JsonDocument.Parse(File.ReadAllText(cfg)); if (doc.RootElement.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String) return v.GetString(); } }
        catch { }
        return null;
    }
    public static int rt_home()
    {
        string appdir = AppDir();
        string cfg = Path.Combine(appdir, "appsettings.json");
        string home = ReadSetting(cfg, "home");
        if (string.IsNullOrEmpty(home))
        {
            home = appdir;                                  // default HOME = %APPDATA%\ilsh
            try
            {
                var o = new Dictionary<string, string> { ["home"] = home, ["path"] = "C:\\Windows\\System32;C:\\Windows" };
                File.WriteAllText(cfg, JsonSerializer.Serialize(o, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch { }
        }
        try { Directory.CreateDirectory(home); } catch { }
        return Cstr(home);
    }
    public static int rt_setting(int key)
    {
        string v = ReadSetting(Path.Combine(AppDir(), "appsettings.json"), ReadCStr(key));
        return string.IsNullOrEmpty(v) ? 0 : Cstr(v);
    }

    // --- time helpers (cc-compiled code can't reach DateTime directly) ---
    public static long rt_epoch_ms() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    public static int rt_datefmt(int fmt)   // strftime-ish format -> string (empty fmt = default)
    {
        string f = fmt == 0 ? "" : ReadCStr(fmt);
        var n = DateTime.Now;
        if (string.IsNullOrEmpty(f)) return Cstr(n.ToString("ddd MMM dd HH:mm:ss yyyy", CultureInfo.InvariantCulture));
        var sb = new StringBuilder();
        for (int i = 0; i < f.Length; i++)
        {
            if (f[i] != '%' || i + 1 >= f.Length) { sb.Append(f[i]); continue; }
            char c = f[++i];
            switch (c)
            {
                case 'Y': sb.Append(n.Year.ToString("D4")); break;
                case 'y': sb.Append((n.Year % 100).ToString("D2")); break;
                case 'm': sb.Append(n.Month.ToString("D2")); break;
                case 'd': sb.Append(n.Day.ToString("D2")); break;
                case 'H': sb.Append(n.Hour.ToString("D2")); break;
                case 'M': sb.Append(n.Minute.ToString("D2")); break;
                case 'S': sb.Append(n.Second.ToString("D2")); break;
                case 'j': sb.Append(n.DayOfYear.ToString("D3")); break;
                case 'p': sb.Append(n.Hour < 12 ? "AM" : "PM"); break;
                case 'A': sb.Append(n.ToString("dddd", CultureInfo.InvariantCulture)); break;
                case 'a': sb.Append(n.ToString("ddd", CultureInfo.InvariantCulture)); break;
                case 'B': sb.Append(n.ToString("MMMM", CultureInfo.InvariantCulture)); break;
                case 'b': sb.Append(n.ToString("MMM", CultureInfo.InvariantCulture)); break;
                case '%': sb.Append('%'); break;
                default: sb.Append('%'); sb.Append(c); break;
            }
        }
        return Cstr(sb.ToString());
    }
    public static int rt_tasklist()   // best-effort `tasklist` capture; empty string on failure
    {
        try
        {
            var p = new System.Diagnostics.Process();
            p.StartInfo.FileName = "tasklist"; p.StartInfo.UseShellExecute = false;
            p.StartInfo.RedirectStandardOutput = true; p.StartInfo.CreateNoWindow = true;
            p.Start(); string o = p.StandardOutput.ReadToEnd(); p.WaitForExit();
            return Cstr(o);
        }
        catch { return Cstr(""); }
    }

    public static int sh_cd(int p) { try { Directory.SetCurrentDirectory(ReadCStr(p)); return 0; } catch { return 1; } }
    public static int sh_cwd(int buf) { var s = Directory.GetCurrentDirectory(); for (int i = 0; i < s.Length; i++) Mem[buf + i] = (byte)s[i]; Mem[buf + s.Length] = 0; return buf; }
    public static int sh_export(int name, int val) { _exports[ReadCStr(name)] = ReadCStr(val); return 0; }
    public static int sh_getenv(int name)
    {
        string k = ReadCStr(name);
        string v = _exports.TryGetValue(k, out var x) ? x : Environment.GetEnvironmentVariable(k);
        if (v == null) return 0;
        int a = malloc(v.Length + 1);
        for (int i = 0; i < v.Length; i++) Mem[a + i] = (byte)v[i];
        Mem[a + v.Length] = 0; return a;
    }

    // ---- host hooks: when a display server (Avalonia) is driving us, console
    // I/O is routed to its terminal grid instead of System.Console. -------
    public static Action<byte[]> HostOut;     // console stdout/stderr sink
    public static Func<int> HostKey;          // next key code, or -1 at EOF
    public static Func<int> HostCols, HostRows;
    public static Action HostClear;
    public static Action<int, int> HostGoto;
    public static Action HostReloadMenu;      // ask the GUI host to rebuild its context menu
    public static bool HostMode => HostOut != null;
    public static int rt_reloadmenu() { HostReloadMenu?.Invoke(); return 0; }

    // ---- graphics: a simple ARGB framebuffer rasterized in-process; a host
    // (Avalonia) blits it to a window and feeds back mouse position + quit. ----
    private static int[] _fb;                  // ARGB pixels, _gw * _gh
    private static int _gw, _gh;
    public static Action<int, int, int[], string> HostGfxOpen;  // (w, h, framebuffer, title)
    public static Action HostGfxPresent;       // request a redraw from the framebuffer
    public static Func<int> HostGfxMouseX, HostGfxMouseY;
    public static Func<int> HostGfxQuit;       // nonzero when the window was closed

    public static int gfx_open(int w, int h, int title)
    {
        _gw = w; _gh = h; _fb = new int[w * h];
        HostGfxOpen?.Invoke(w, h, _fb, title != 0 ? ReadCStr(title) : "");
        return 0;
    }
    public static int gfx_width() => _gw;
    public static int gfx_height() => _gh;
    public static int gfx_present() { HostGfxPresent?.Invoke(); return 0; }
    public static int gfx_mousex() => HostGfxMouseX != null ? HostGfxMouseX() : 0;
    public static int gfx_mousey() => HostGfxMouseY != null ? HostGfxMouseY() : 0;
    public static int gfx_poll() => HostGfxQuit != null ? HostGfxQuit() : 0;
    public static int gfx_sleep(int ms) { try { System.Threading.Thread.Sleep(ms); } catch { } return 0; }

    // locate the repo root (dir containing build_all.sh) by walking up from where
    // this assembly was loaded — lets the shell find ilgfx.exe / out/*.dll.
    public static int rt_repo()
    {
        try
        {
            string d = Path.GetDirectoryName(typeof(CRuntime).Assembly.Location);
            for (int i = 0; i < 10 && !string.IsNullOrEmpty(d); i++)
            {
                if (File.Exists(Path.Combine(d, "build_all.sh"))) return Cstr(d);
                d = Path.GetDirectoryName(d);
            }
        }
        catch { }
        return Cstr(Directory.GetCurrentDirectory());
    }

    // ---- Pascal sets (0..255 bitsets, referenced by an int handle) --------
    private static readonly List<bool[]> _sets = new();
    public static int ps_lit(int n, object[] a)
    {
        var s = new bool[256];
        for (int i = 0; i < n; i++) { int lo = Convert.ToInt32(a[2 * i]), hi = Convert.ToInt32(a[2 * i + 1]); for (int v = lo; v <= hi; v++) if (v >= 0 && v < 256) s[v] = true; }
        _sets.Add(s); return _sets.Count - 1;
    }
    public static int ps_in(int h, int x) { return (h >= 0 && h < _sets.Count && x >= 0 && x < 256 && _sets[h][x]) ? 1 : 0; }
    private static int ps_bin(int a, int b, int op) { var s = new bool[256]; for (int i = 0; i < 256; i++) s[i] = op == 0 ? (_sets[a][i] || _sets[b][i]) : op == 1 ? (_sets[a][i] && _sets[b][i]) : (_sets[a][i] && !_sets[b][i]); _sets.Add(s); return _sets.Count - 1; }
    public static int ps_or(int a, int b) { return ps_bin(a, b, 0); }
    public static int ps_and(int a, int b) { return ps_bin(a, b, 1); }
    public static int ps_sub(int a, int b) { return ps_bin(a, b, 2); }
    public static int ps_incl(int h, int x) { if (h >= 0 && h < _sets.Count && x >= 0 && x < 256) _sets[h][x] = true; return 0; }
    public static int ps_excl(int h, int x) { if (h >= 0 && h < _sets.Count && x >= 0 && x < 256) _sets[h][x] = false; return 0; }

    // ---- Pascal text files (assign/reset/rewrite/read/write/eof/close) -----
    private static readonly List<object> _pfobj = new();    // StreamReader | StreamWriter | null
    private static readonly List<string> _pfname = new();
    public static int pf_assign(int name) { _pfobj.Add(null); _pfname.Add(ReadCStr(name)); return _pfobj.Count - 1; }
    public static int pf_reset(int id)   { try { _pfobj[id] = new StreamReader(_pfname[id]); } catch { } return 0; }
    public static int pf_rewrite(int id) { try { _pfobj[id] = new StreamWriter(_pfname[id], false); } catch { } return 0; }
    public static int pf_append(int id)  { try { _pfobj[id] = new StreamWriter(_pfname[id], true); } catch { } return 0; }
    public static int pf_close(int id)   { var o = _pfobj[id]; if (o is StreamReader r) r.Dispose(); else if (o is StreamWriter w) { w.Flush(); w.Dispose(); } _pfobj[id] = null; return 0; }
    public static int pf_eof(int id)     { return (_pfobj[id] is StreamReader r) ? (r.Peek() < 0 ? 1 : 0) : 1; }
    public static int pf_readln(int id)  { return Cstr(_pfobj[id] is StreamReader r ? (r.ReadLine() ?? "") : ""); }
    public static int pf_writes(int id, int s) { if (_pfobj[id] is StreamWriter w) w.Write(ReadCStr(s)); return 0; }
    public static int pf_writei(int id, int n) { if (_pfobj[id] is StreamWriter w) w.Write(n); return 0; }
    public static int pf_writer(int id, double d) { if (_pfobj[id] is StreamWriter w) w.Write(d); return 0; }
    public static int pf_writec(int id, int c) { if (_pfobj[id] is StreamWriter w) w.Write((char)c); return 0; }
    public static int pf_writeln(int id) { if (_pfobj[id] is StreamWriter w) w.Write('\n'); return 0; }

    // command-line arguments, marshalled into the arena as a C argv (char**).
    // argv[0] is the program name; argv[1..] are the user arguments.
    private static int _argc, _argv;
    public static int rt_make_argv(string[] args)
    {
        int extra = args?.Length ?? 0;
        int n = extra + 1;
        int vec = DataAlloc(n * 4);                       // n pointers (4 bytes each)
        string prog = System.Reflection.Assembly.GetEntryAssembly()?.GetName().Name ?? "prog";
        StI32(vec, Cstr(prog));
        for (int i = 0; i < extra; i++) StI32(vec + (i + 1) * 4, Cstr(args[i]));
        _argc = n; _argv = vec;
        return 0;
    }
    public static int rt_argc() => _argc;
    public static int rt_argv() => _argv;

    private static int Argb(int rgb) => unchecked((int)0xFF000000) | (rgb & 0xFFFFFF);
    private static void Px(int x, int y, int c) { if (_fb != null && x >= 0 && y >= 0 && x < _gw && y < _gh) _fb[y * _gw + x] = c; }

    public static int gfx_clear(int rgb)
    {
        if (_fb == null) return 0;
        int c = Argb(rgb);
        for (int i = 0; i < _fb.Length; i++) _fb[i] = c;
        return 0;
    }
    public static int gfx_fill_rect(int x, int y, int w, int h, int rgb)
    {
        int c = Argb(rgb);
        for (int yy = y; yy < y + h; yy++) for (int xx = x; xx < x + w; xx++) Px(xx, yy, c);
        return 0;
    }
    public static int gfx_fill_ellipse(int cx, int cy, int rx, int ry, int rgb)
    {
        if (rx <= 0 || ry <= 0) return 0;
        int c = Argb(rgb);
        long rx2 = (long)rx * rx, ry2 = (long)ry * ry;
        for (int dy = -ry; dy <= ry; dy++)
        {
            // x span where (dx/rx)^2 + (dy/ry)^2 <= 1
            double t = 1.0 - (double)(dy * dy) / ry2;
            if (t < 0) continue;
            int dx = (int)(rx * Math.Sqrt(t));
            int yy = cy + dy;
            for (int xx = cx - dx; xx <= cx + dx; xx++) Px(xx, yy, c);
        }
        return 0;
    }
    public static int gfx_draw_ellipse(int cx, int cy, int rx, int ry, int rgb)
    {
        if (rx <= 0 || ry <= 0) return 0;
        int c = Argb(rgb);
        for (int a = 0; a < 360; a++)
        {
            double r = a * Math.PI / 180.0;
            Px(cx + (int)(rx * Math.Cos(r)), cy + (int)(ry * Math.Sin(r)), c);
        }
        return 0;
    }
    public static int gfx_line(int x0, int y0, int x1, int y1, int rgb)
    {
        int c = Argb(rgb);
        int dx = Math.Abs(x1 - x0), dy = -Math.Abs(y1 - y0);
        int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy;
        while (true)
        {
            Px(x0, y0, c);
            if (x0 == x1 && y0 == y1) break;
            int e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
        return 0;
    }

    // ---- filesystem / console support for the shell + coreutils --------
    private static int Cstr(string s)
    {
        int a = malloc(s.Length + 1);
        for (int i = 0; i < s.Length; i++) Mem[a + i] = (byte)s[i];
        Mem[a + s.Length] = 0; return a;
    }
    private static int _inlen;
    public static int rt_inlen() => _inlen;

    // current builtin stdin: pipe buffer, redirected file, or empty
    public static int rt_input()
    {
        byte[] d = _pIn ? _pData : (_rIn != null ? SafeRead(_rIn) : System.Array.Empty<byte>());
        int a = malloc(d.Length + 1);
        for (int i = 0; i < d.Length; i++) Mem[a + i] = d[i];
        Mem[a + d.Length] = 0; _inlen = d.Length; return a;
    }
    public static int rt_slurp(int path)
    {
        byte[] d = SafeRead(ReadCStr(path));
        if (d == null) { _inlen = 0; return 0; }
        int a = malloc(d.Length + 1);
        for (int i = 0; i < d.Length; i++) Mem[a + i] = d[i];
        Mem[a + d.Length] = 0; _inlen = d.Length; return a;
    }
    private static byte[] SafeRead(string p) { try { return File.ReadAllBytes(p); } catch { return null; } }

    // directory listing (single-level snapshot for `ls`)
    private static readonly List<string> _lsName = new();
    private static readonly List<long> _lsSize = new();
    private static readonly List<bool> _lsDir = new();
    private static readonly List<string> _lsMode = new();
    private static readonly List<string> _lsDate = new();
    public static int rt_lsopen(int path)
    {
        _lsName.Clear(); _lsSize.Clear(); _lsDir.Clear(); _lsMode.Clear(); _lsDate.Clear();
        string p = ReadCStr(path); if (p.Length == 0) p = ".";
        try
        {
            if (File.Exists(p) && !Directory.Exists(p)) { AddEntry(new FileInfo(p)); return 1; }
            foreach (var e in new DirectoryInfo(p).GetFileSystemInfos().OrderBy(e => e.Name, StringComparer.OrdinalIgnoreCase))
                AddEntry(e);
            return _lsName.Count;
        }
        catch { return -1; }
    }
    private static void AddEntry(FileSystemInfo e)
    {
        bool dir = (e.Attributes & FileAttributes.Directory) != 0;
        bool ro = (e.Attributes & FileAttributes.ReadOnly) != 0;
        string ext = Path.GetExtension(e.Name).ToLowerInvariant();
        bool exe = ext is ".exe" or ".bat" or ".cmd" or ".com" or ".dll" or ".ps1";
        string perm = (dir || exe) ? (ro ? "r-xr-xr-x" : "rwxr-xr-x") : (ro ? "r--r--r--" : "rw-rw-rw-");
        _lsName.Add(e.Name);
        _lsSize.Add(dir ? 0 : ((FileInfo)e).Length);
        _lsDir.Add(dir);
        _lsMode.Add((dir ? "d" : "-") + perm);
        _lsDate.Add(e.LastWriteTime.ToString("MMM dd HH:mm", CultureInfo.InvariantCulture));
    }
    public static int rt_lsname(int i) => Cstr(_lsName[i]);
    public static long rt_lssize(int i) => _lsSize[i];
    public static int rt_lsisdir(int i) => _lsDir[i] ? 1 : 0;
    public static int rt_lsmode(int i) => Cstr(_lsMode[i]);
    public static int rt_lsdate(int i) => Cstr(_lsDate[i]);

    // recursive find with a glob pattern
    private static readonly List<string> _find = new();
    public static int rt_find(int path, int pat)
    {
        _find.Clear();
        string root = ReadCStr(path); string p = pat == 0 ? "*" : ReadCStr(pat);
        try { FindRec(root, p); } catch { }
        return _find.Count;
    }
    private static void FindRec(string dir, string pat)
    {
        foreach (var e in Directory.EnumerateFileSystemEntries(dir))
        {
            if (WildMatch(pat, Path.GetFileName(e))) _find.Add(e.Replace('\\', '/'));
            if (Directory.Exists(e)) FindRec(e, pat);
        }
    }
    public static int rt_findname(int i) => Cstr(_find[i]);
    private static bool WildMatch(string pat, string s)
    {
        if (pat == "*") return true;
        int pi = 0, si = 0, star = -1, ss = 0;
        while (si < s.Length)
        {
            if (pi < pat.Length && (pat[pi] == '?' || char.ToLowerInvariant(pat[pi]) == char.ToLowerInvariant(s[si]))) { pi++; si++; }
            else if (pi < pat.Length && pat[pi] == '*') { star = pi++; ss = si; }
            else if (star >= 0) { pi = star + 1; si = ++ss; }
            else return false;
        }
        while (pi < pat.Length && pat[pi] == '*') pi++;
        return pi == pat.Length;
    }

    // stat + file operations
    public static int rt_exists(int p) { string s = ReadCStr(p); return (File.Exists(s) || Directory.Exists(s)) ? 1 : 0; }
    public static int rt_isdir(int p) => Directory.Exists(ReadCStr(p)) ? 1 : 0;
    public static long rt_size(int p) { try { return new FileInfo(ReadCStr(p)).Length; } catch { return -1; } }
    public static long rt_mtime(int p)
    {
        string s = ReadCStr(p);
        try { if (Directory.Exists(s)) return Directory.GetLastWriteTimeUtc(s).Ticks; if (File.Exists(s)) return File.GetLastWriteTimeUtc(s).Ticks; return -1; }
        catch { return -1; }
    }
    public static int rt_copy(int s, int d) { try { File.Copy(ReadCStr(s), ReadCStr(d), true); return 0; } catch { return 1; } }
    public static int rt_move(int s, int d) { try { string sd = ReadCStr(s), dd = ReadCStr(d); if (File.Exists(dd)) File.Delete(dd); File.Move(sd, dd); return 0; } catch { return 1; } }
    public static int rt_remove(int p) { try { string s = ReadCStr(p); if (Directory.Exists(s)) Directory.Delete(s, true); else File.Delete(s); return 0; } catch { return 1; } }
    public static int rt_mkdir(int p) { try { Directory.CreateDirectory(ReadCStr(p)); return 0; } catch { return 1; } }
    public static int rt_touch(int p) { try { string s = ReadCStr(p); if (File.Exists(s)) File.SetLastWriteTimeUtc(s, DateTime.UtcNow); else File.Create(s).Dispose(); return 0; } catch { return 1; } }
    public static int rt_link(int target, int linkpath, int symbolic)
    {
        string tg = ReadCStr(target), lp = ReadCStr(linkpath);
        try
        {
            if (symbolic != 0) { if (Directory.Exists(tg)) Directory.CreateSymbolicLink(lp, tg); else File.CreateSymbolicLink(lp, tg); return 0; }
            File.Copy(tg, lp, true); return 0;                         // hardlink not in BCL -> copy
        }
        catch { try { File.Copy(tg, lp, true); return 0; } catch { return 1; } }  // symlink needs privilege -> copy
    }

    // console (routed to the host window when one is attached)
    public static int rt_isatty() => HostMode ? 1 : (Console.IsInputRedirected ? 0 : 1);
    public static int rt_readline(int buf, int n)
    {
        string line = Console.ReadLine();
        if (line == null) return -1;
        int i = 0; for (; i < line.Length && i < n - 1; i++) Mem[buf + i] = (byte)line[i];
        Mem[buf + i] = 0; return i;
    }
    public static int rt_cols() { if (HostCols != null) return HostCols(); try { return Console.WindowWidth; } catch { return 80; } }
    public static int rt_rows() { if (HostRows != null) return HostRows(); try { return Console.WindowHeight; } catch { return 25; } }
    public static void rt_clear() { if (HostClear != null) { HostClear(); return; } try { Console.Clear(); } catch { } }
    public static void rt_gotoxy(int x, int y) { if (HostGoto != null) { HostGoto(x, y); return; } try { Console.SetCursorPosition(x, y); } catch { } }
    public static int rt_getkey()
    {
        if (HostKey != null) return HostKey();
        if (Console.IsInputRedirected) return -100;  // -100 = EOF (distinct from arrow keys -1..-9)
        var k = Console.ReadKey(true);
        return k.Key switch
        {
            ConsoleKey.UpArrow => -1, ConsoleKey.DownArrow => -2, ConsoleKey.LeftArrow => -3, ConsoleKey.RightArrow => -4,
            ConsoleKey.Delete => -5, ConsoleKey.Home => -6, ConsoleKey.End => -7, ConsoleKey.PageUp => -8, ConsoleKey.PageDown => -9,
            ConsoleKey.Enter => 13, ConsoleKey.Backspace => 8, ConsoleKey.Escape => 27, ConsoleKey.Tab => 9,
            _ => k.KeyChar
        };
    }

    // ---- scanf family --------------------------------------------------
    public static int sscanf(int src, int fmt, object[] args) { int p = src; return ScanFrom(ref p, fmt, args); }
    public static int scanf(int fmt, object[] args)
    {
        var s = FileFor(1);
        var sb = new StringBuilder();
        int b;
        while ((b = s.ReadByte()) >= 0) { if (b == '\n') break; sb.Append((char)b); }
        if (b < 0 && sb.Length == 0) return -1; // EOF
        int buf = malloc(sb.Length + 1);
        for (int i = 0; i < sb.Length; i++) Mem[buf + i] = (byte)sb[i];
        Mem[buf + sb.Length] = 0;
        int p = buf; int r = ScanFrom(ref p, fmt, args); free(buf); return r;
    }

    private static bool IsWs(int c) => c is ' ' or '\t' or '\n' or '\r' or '\f' or '\v';
    private static int HexVal(int c) => c is >= '0' and <= '9' ? c - '0' : c is >= 'a' and <= 'f' ? c - 'a' + 10 : c is >= 'A' and <= 'F' ? c - 'A' + 10 : -1;

    private static int ScanFrom(ref int p, int fmt, object[] args)
    {
        int fi = fmt, ai = 0, matched = 0;
        while (Mem[fi] != 0)
        {
            char fc = (char)Mem[fi];
            if (fc == '%')
            {
                fi++;
                bool suppress = (char)Mem[fi] == '*'; if (suppress) fi++;
                int width = 0; while (Mem[fi] >= '0' && Mem[fi] <= '9') width = width * 10 + (Mem[fi++] - '0');
                bool isLong = false;
                while ((char)Mem[fi] is 'l' or 'h' or 'L') { if ((char)Mem[fi] is 'l' or 'L') isLong = true; fi++; }
                char conv = (char)Mem[fi++];

                if (conv != 'c') while (Mem[p] != 0 && IsWs(Mem[p])) p++;

                if (conv is 'd' or 'i' or 'u' or 'x' or 'X')
                {
                    int bas = conv is 'x' or 'X' ? 16 : 10;
                    bool neg = false;
                    if ((char)Mem[p] is '+' or '-') { neg = Mem[p] == '-'; p++; }
                    long v = 0; int dig = 0;
                    while (true) { int d = HexVal(Mem[p]); if (d < 0 || d >= bas) break; v = v * bas + d; p++; if (++dig == width) break; }
                    if (dig == 0) return matched;
                    if (neg) v = -v;
                    if (!suppress) { StI32(Convert.ToInt32(args[ai++]), (int)v); matched++; }
                }
                else if (conv is 'f' or 'e' or 'g' or 'E' or 'G')
                {
                    int start = p;
                    if ((char)Mem[p] is '+' or '-') p++;
                    while (Mem[p] >= '0' && Mem[p] <= '9') p++;
                    if ((char)Mem[p] == '.') { p++; while (Mem[p] >= '0' && Mem[p] <= '9') p++; }
                    if ((char)Mem[p] is 'e' or 'E') { p++; if ((char)Mem[p] is '+' or '-') p++; while (Mem[p] >= '0' && Mem[p] <= '9') p++; }
                    if (p == start) return matched;
                    double d = double.Parse(ReadRange(start, p), CultureInfo.InvariantCulture);
                    if (!suppress) { int a = Convert.ToInt32(args[ai++]); if (isLong) StF64(a, d); else StF32(a, d); matched++; }
                }
                else if (conv == 'c')
                {
                    if (Mem[p] == 0) return matched;
                    if (!suppress) { StI8(Convert.ToInt32(args[ai++]), Mem[p]); matched++; }
                    p++;
                }
                else if (conv == 's')
                {
                    if (Mem[p] == 0) return matched;
                    int addr = suppress ? 0 : Convert.ToInt32(args[ai++]); int n = 0;
                    while (Mem[p] != 0 && !IsWs(Mem[p])) { if (!suppress) Mem[addr + n] = Mem[p]; n++; p++; if (n == width) break; }
                    if (!suppress) { Mem[addr + n] = 0; matched++; }
                }
                else if (conv == '%') { if ((char)Mem[p] == '%') p++; }
            }
            else if (IsWs(fc)) { fi++; while (Mem[p] != 0 && IsWs(Mem[p])) p++; }
            else { if (Mem[p] == fc) { p++; fi++; } else return matched; }
        }
        return matched;
    }

    private static string ReadRange(int a, int b) { var sb = new StringBuilder(); for (int i = a; i < b; i++) sb.Append((char)Mem[i]); return sb.ToString(); }

    // ---- helpers -------------------------------------------------------
    private static void WriteBytes(int h, byte[] b)
    {
        if ((h == 2 || h == 3) && HostOut != null) { HostOut(b); return; }   // route console to the window
        var s = FileFor(h); if (s == null) return;
        s.Write(b, 0, b.Length);
        if (h == 2 || h == 3) s.Flush();
    }
    private static string ReadCStr(int a) => Encoding.Latin1.GetString(ReadCBytes(a));
    private static byte[] ReadCBytes(int a)
    {
        int n = strlen(a);
        var b = new byte[n];
        Array.Copy(Mem, a, b, 0, n);
        return b;
    }

    // printf-family formatter: a practical subset of C conversions.
    private static string Format(int fmt, object[] args)
    {
        var sb = new StringBuilder();
        int ai = 0;
        int i = fmt;
        while (Mem[i] != 0)
        {
            char c = (char)Mem[i++];
            if (c != '%') { sb.Append(c); continue; }

            // flags
            bool left = false, zero = false, plus = false, space = false;
            while (true)
            {
                char f = (char)Mem[i];
                if (f == '-') left = true; else if (f == '0') zero = true;
                else if (f == '+') plus = true; else if (f == ' ') space = true;
                else break;
                i++;
            }
            // width
            int width = 0;
            if ((char)Mem[i] == '*') { width = Convert.ToInt32(args[ai++]); i++; }
            else while (Mem[i] >= '0' && Mem[i] <= '9') width = width * 10 + (Mem[i++] - '0');
            // precision
            int prec = -1;
            if ((char)Mem[i] == '.')
            {
                i++; prec = 0;
                if ((char)Mem[i] == '*') { prec = Convert.ToInt32(args[ai++]); i++; }
                else while (Mem[i] >= '0' && Mem[i] <= '9') prec = prec * 10 + (Mem[i++] - '0');
            }
            // length modifiers: track 'l'/'ll' so %ld/%lu use 64-bit width
            bool lng = false;
            while ((char)Mem[i] is 'l' or 'h' or 'L' or 'z' or 'j' or 't') { if ((char)Mem[i] is 'l' or 'L') lng = true; i++; }

            char conv = (char)Mem[i++];
            string body;
            switch (conv)
            {
                case '%': sb.Append('%'); continue;
                case 'd': case 'i':
                {
                    long v = Convert.ToInt64(args[ai++]);
                    body = (v < 0 ? -(decimal)v : v).ToString();
                    if (prec >= 0) body = body.PadLeft(prec, '0');
                    string sign = v < 0 ? "-" : plus ? "+" : space ? " " : "";
                    body = sign + body;
                    break;
                }
                case 'u': body = ULongArg(args, ref ai, lng).ToString(); if (prec >= 0) body = body.PadLeft(prec, '0'); break;
                case 'x': body = ULongArg(args, ref ai, lng).ToString("x"); if (prec >= 0) body = body.PadLeft(prec, '0'); break;
                case 'X': body = ULongArg(args, ref ai, lng).ToString("X"); if (prec >= 0) body = body.PadLeft(prec, '0'); break;
                case 'o': body = Convert.ToString(Convert.ToInt64(args[ai++]), 8); break;
                case 'p': body = "0x" + ((uint)Convert.ToInt64(args[ai++])).ToString("x"); break;
                case 'f': case 'F':
                {
                    double d = Convert.ToDouble(args[ai++]);
                    body = Math.Abs(d).ToString("F" + (prec < 0 ? 6 : prec), CultureInfo.InvariantCulture);
                    body = (d < 0 ? "-" : plus ? "+" : space ? " " : "") + body;
                    break;
                }
                case 'e': case 'E':
                {
                    double d = Convert.ToDouble(args[ai++]);
                    body = d.ToString((conv == 'e' ? "e" : "E") + (prec < 0 ? 6 : prec), CultureInfo.InvariantCulture);
                    break;
                }
                case 'g': case 'G':
                {
                    double d = Convert.ToDouble(args[ai++]);
                    body = d.ToString("G" + (prec <= 0 ? 6 : prec), CultureInfo.InvariantCulture);
                    if (conv == 'g') body = body.Replace("E", "e");
                    break;
                }
                case 'c': body = ((char)Convert.ToInt32(args[ai++])).ToString(); break;
                case 's':
                {
                    int addr = Convert.ToInt32(args[ai++]);
                    body = addr == 0 ? "(null)" : ReadCStr(addr);
                    if (prec >= 0 && body.Length > prec) body = body[..prec];
                    break;
                }
                default: sb.Append('%').Append(conv); continue;
            }
            if (width > body.Length)
                body = left ? body.PadRight(width)
                     : zero && prec < 0 && conv is 'd' or 'i' or 'u' or 'x' or 'X' ? PadZeroSigned(body, width)
                     : body.PadLeft(width);
            sb.Append(body);
        }
        return sb.ToString();
    }

    // %u/%x/%X argument: mask to 32 bits unless an 'l' length modifier was given.
    private static ulong ULongArg(object[] args, ref int ai, bool lng)
    {
        long v = Convert.ToInt64(args[ai++]);
        return lng ? (ulong)v : (uint)v;
    }

    private static string PadZeroSigned(string body, int width)
    {
        string sign = (body.Length > 0 && body[0] is '-' or '+' or ' ') ? body[..1] : "";
        string digits = body[sign.Length..];
        return sign + digits.PadLeft(width - sign.Length, '0');
    }

    // ============================ Forth runtime ============================
    // The data stack is a real .NET Stack<object>, so any cell type (int, double,
    // string) can be pushed. The Forth compiler emits direct calls to these (one
    // C function per Forth word -> real IL), never an inner interpreter.
    private static readonly System.Collections.Generic.Stack<object> _fs = new();
    private static readonly System.Collections.Generic.List<object> _fcells = new();

    private static object FPop() => _fs.Count > 0 ? _fs.Pop() : 0;
    private static int FI(object o) => o is int i ? i : o is double d ? (int)d : o is bool b ? (b ? -1 : 0) : 0;
    private static double FD(object o) => o is double d ? d : o is int i ? i : 0;
    private static void FW(string s) => WriteBytes(2, Encoding.Latin1.GetBytes(s));
    private static string FNum(object o) => o is double d ? d.ToString("0.######", CultureInfo.InvariantCulture) : FI(o).ToString();

    public static int f_pushi(int v) { _fs.Push(v); return 0; }
    public static int f_pushd(double v) { _fs.Push(v); return 0; }
    public static int f_pushs(int cstr) { _fs.Push(ReadCStr(cstr)); return 0; }
    public static int f_popi() => FI(FPop());
    public static double f_popd() => FD(FPop());
    public static int f_pops() => Cstr(FPop()?.ToString() ?? "");
    public static int f_depth() { _fs.Push(_fs.Count); return 0; }

    // arithmetic — polymorphic: string concat, else double if any double, else int
    public static int f_add() { object b = FPop(), a = FPop(); if (a is string || b is string) _fs.Push((a?.ToString() ?? "") + (b?.ToString() ?? "")); else if (a is double || b is double) _fs.Push(FD(a) + FD(b)); else _fs.Push(FI(a) + FI(b)); return 0; }
    public static int f_sub() { object b = FPop(), a = FPop(); if (a is double || b is double) _fs.Push(FD(a) - FD(b)); else _fs.Push(FI(a) - FI(b)); return 0; }
    public static int f_mul() { object b = FPop(), a = FPop(); if (a is double || b is double) _fs.Push(FD(a) * FD(b)); else _fs.Push(FI(a) * FI(b)); return 0; }
    public static int f_div() { object b = FPop(), a = FPop(); if (a is double || b is double) _fs.Push(FD(a) / FD(b)); else _fs.Push(FI(a) / FI(b)); return 0; }
    public static int f_mod() { int b = FI(FPop()), a = FI(FPop()); _fs.Push(a % b); return 0; }
    public static int f_negate() { object a = FPop(); if (a is double d) _fs.Push(-d); else _fs.Push(-FI(a)); return 0; }
    public static int f_abs() { object a = FPop(); if (a is double d) _fs.Push(System.Math.Abs(d)); else _fs.Push(System.Math.Abs(FI(a))); return 0; }
    public static int f_min() { object b = FPop(), a = FPop(); _fs.Push(FD(a) <= FD(b) ? a : b); return 0; }
    public static int f_max() { object b = FPop(), a = FPop(); _fs.Push(FD(a) >= FD(b) ? a : b); return 0; }

    // stack manipulation — type-agnostic
    public static int f_dup() { var a = FPop(); _fs.Push(a); _fs.Push(a); return 0; }
    public static int f_drop() { FPop(); return 0; }
    public static int f_swap() { var b = FPop(); var a = FPop(); _fs.Push(b); _fs.Push(a); return 0; }
    public static int f_over() { var b = FPop(); var a = FPop(); _fs.Push(a); _fs.Push(b); _fs.Push(a); return 0; }
    public static int f_rot() { var c = FPop(); var b = FPop(); var a = FPop(); _fs.Push(b); _fs.Push(c); _fs.Push(a); return 0; }
    public static int f_qdup() { var a = FPop(); _fs.Push(a); if (FI(a) != 0) _fs.Push(a); return 0; }
    public static int f_nip() { var b = FPop(); FPop(); _fs.Push(b); return 0; }
    public static int f_tuck() { var b = FPop(); var a = FPop(); _fs.Push(b); _fs.Push(a); _fs.Push(b); return 0; }
    public static int f_2dup() { var b = FPop(); var a = FPop(); _fs.Push(a); _fs.Push(b); _fs.Push(a); _fs.Push(b); return 0; }
    public static int f_2drop() { FPop(); FPop(); return 0; }

    // comparison — Forth true = -1, false = 0
    private static int FB(bool t) => t ? -1 : 0;
    public static int f_eq() { object b = FPop(), a = FPop(); _fs.Push(FB((a is string || b is string) ? (a?.ToString() == b?.ToString()) : (FD(a) == FD(b)))); return 0; }
    public static int f_ne() { object b = FPop(), a = FPop(); _fs.Push(FB((a is string || b is string) ? (a?.ToString() != b?.ToString()) : (FD(a) != FD(b)))); return 0; }
    public static int f_lt() { object b = FPop(), a = FPop(); _fs.Push(FB(FD(a) < FD(b))); return 0; }
    public static int f_gt() { object b = FPop(), a = FPop(); _fs.Push(FB(FD(a) > FD(b))); return 0; }
    public static int f_le() { object b = FPop(), a = FPop(); _fs.Push(FB(FD(a) <= FD(b))); return 0; }
    public static int f_ge() { object b = FPop(), a = FPop(); _fs.Push(FB(FD(a) >= FD(b))); return 0; }
    public static int f_0eq() { _fs.Push(FB(FI(FPop()) == 0)); return 0; }
    public static int f_0lt() { _fs.Push(FB(FD(FPop()) < 0)); return 0; }
    public static int f_0gt() { _fs.Push(FB(FD(FPop()) > 0)); return 0; }
    public static int f_and() { int b = FI(FPop()), a = FI(FPop()); _fs.Push(a & b); return 0; }
    public static int f_or() { int b = FI(FPop()), a = FI(FPop()); _fs.Push(a | b); return 0; }
    public static int f_xor() { int b = FI(FPop()), a = FI(FPop()); _fs.Push(a ^ b); return 0; }
    public static int f_invert() { _fs.Push(~FI(FPop())); return 0; }

    // I/O
    public static int f_dot() { FW(FNum(FPop()) + " "); return 0; }
    public static int f_dots() { FW("<" + _fs.Count + "> "); foreach (var o in _fs.Reverse()) FW(FNum(o) + " "); return 0; }
    public static int f_emit() { FW(((char)FI(FPop())).ToString()); return 0; }
    public static int f_cr() { FW("\n"); return 0; }
    public static int f_space() { FW(" "); return 0; }
    public static int f_spaces() { int n = FI(FPop()); for (int k = 0; k < n; k++) FW(" "); return 0; }
    public static int f_type() { FW(FPop()?.ToString() ?? ""); return 0; }

    // variables / cells: a VARIABLE pushes its cell index; @ fetches, ! stores
    public static int f_fetch() { int i = FI(FPop()); _fs.Push(i >= 0 && i < _fcells.Count ? _fcells[i] : 0); return 0; }
    public static int f_store() { int i = FI(FPop()); object v = FPop(); while (_fcells.Count <= i) _fcells.Add(0); if (i >= 0) _fcells[i] = v; return 0; }

    // ======================= Logo turtle canvas =======================
    // An ARGB canvas the Logo interpreter draws turtle paths into. Records line
    // segments (for SVG), can capture frames (for animated GIF), rasterizes to a
    // self-contained PNG, and can blit to the gfx window for live/interactive use.
    private static int[] _tc; private static int _tcw, _tch, _tbg;
    private static readonly System.Collections.Generic.List<int[]> _tsegs = new();   // {x0,y0,x1,y1,rgb,size}
    private static readonly System.Collections.Generic.List<int[]> _tframes = new();
    private static readonly System.Collections.Generic.List<int> _tdelay = new();

    public static int tc_init(int w, int h, int bg) { _tcw = w; _tch = h; _tbg = bg | unchecked((int)0xFF000000); _tc = new int[w * h]; for (int i = 0; i < _tc.Length; i++) _tc[i] = _tbg; _tsegs.Clear(); _tframes.Clear(); _tdelay.Clear(); return 0; }
    public static int tc_clear(int bg) { _tbg = bg | unchecked((int)0xFF000000); for (int i = 0; i < _tc.Length; i++) _tc[i] = _tbg; _tsegs.Clear(); return 0; }
    private static void TPlot(int x, int y, int rgb, int sz) { int r = sz / 2; for (int dy = -r; dy <= r; dy++) for (int dx = -r; dx <= r; dx++) { int px = x + dx, py = y + dy; if (px >= 0 && px < _tcw && py >= 0 && py < _tch) _tc[py * _tcw + px] = rgb; } }
    public static int tc_line(int x0, int y0, int x1, int y1, int rgb, int sz)
    {
        rgb |= unchecked((int)0xFF000000); if (sz < 1) sz = 1;
        _tsegs.Add(new[] { x0, y0, x1, y1, rgb, sz });
        int dx = System.Math.Abs(x1 - x0), dy = -System.Math.Abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx + dy;
        while (true) { TPlot(x0, y0, rgb, sz); if (x0 == x1 && y0 == y1) break; int e2 = 2 * err; if (e2 >= dy) { err += dy; x0 += sx; } if (e2 <= dx) { err += dx; y0 += sy; } }
        return 0;
    }
    public static int tc_present() { if (HostGfxPresent != null && _fb != null && _tc != null && _fb.Length >= _tc.Length) { System.Array.Copy(_tc, _fb, _tc.Length); HostGfxPresent(); } return 0; }
    public static int tc_frame(int delayCs) { if (_tc == null) return 0; _tframes.Add((int[])_tc.Clone()); _tdelay.Add(delayCs <= 0 ? 5 : delayCs); return 0; }

    private static string THex(int rgb) { return "#" + (rgb & 0xFFFFFF).ToString("X6"); }
    public static int tc_svg(int pathc)
    {
        var sb = new StringBuilder();
        sb.Append($"<svg xmlns='http://www.w3.org/2000/svg' width='{_tcw}' height='{_tch}' viewBox='0 0 {_tcw} {_tch}'>\n");
        sb.Append($"<rect width='100%' height='100%' fill='{THex(_tbg)}'/>\n");
        foreach (var s in _tsegs) sb.Append($"<line x1='{s[0]}' y1='{s[1]}' x2='{s[2]}' y2='{s[3]}' stroke='{THex(s[4])}' stroke-width='{(s[5] < 1 ? 1 : s[5])}' stroke-linecap='round'/>\n");
        sb.Append("</svg>\n");
        File.WriteAllText(ReadCStr(pathc), sb.ToString());
        return 0;
    }

    // ---- PNG (RGB, single IDAT; zlib via DeflateStream + adler32) ----
    private static uint[] _crcTab;
    private static uint Crc32(byte[] d)
    {
        if (_crcTab == null) { _crcTab = new uint[256]; for (uint n = 0; n < 256; n++) { uint c = n; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; _crcTab[n] = c; } }
        uint crc = 0xFFFFFFFF; foreach (byte b in d) crc = _crcTab[(crc ^ b) & 0xFF] ^ (crc >> 8); return crc ^ 0xFFFFFFFF;
    }
    private static uint Adler32(byte[] d) { uint a = 1, b = 0; foreach (byte x in d) { a = (a + x) % 65521; b = (b + a) % 65521; } return (b << 16) | a; }
    private static void BE32(MemoryStream m, uint v) { m.WriteByte((byte)(v >> 24)); m.WriteByte((byte)(v >> 16)); m.WriteByte((byte)(v >> 8)); m.WriteByte((byte)v); }
    private static void PngChunk(MemoryStream m, string type, byte[] data)
    {
        BE32(m, (uint)data.Length); var tb = Encoding.ASCII.GetBytes(type);
        var body = new byte[tb.Length + data.Length]; tb.CopyTo(body, 0); data.CopyTo(body, tb.Length);
        m.Write(body, 0, body.Length); BE32(m, Crc32(body));
    }
    public static int tc_png(int pathc)
    {
        int w = _tcw, h = _tch;
        byte[] raw = new byte[h * (1 + w * 3)]; int p = 0;
        for (int y = 0; y < h; y++) { raw[p++] = 0; for (int x = 0; x < w; x++) { int c = _tc[y * w + x]; raw[p++] = (byte)(c >> 16); raw[p++] = (byte)(c >> 8); raw[p++] = (byte)c; } }
        var def = new MemoryStream(); using (var ds = new DeflateStream(def, CompressionLevel.Optimal, true)) ds.Write(raw, 0, raw.Length);
        var zlib = new MemoryStream(); zlib.WriteByte(0x78); zlib.WriteByte(0x9C); var db = def.ToArray(); zlib.Write(db, 0, db.Length); BE32(zlib, Adler32(raw));
        var png = new MemoryStream();
        png.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
        var ihdr = new MemoryStream(); BE32(ihdr, (uint)w); BE32(ihdr, (uint)h); ihdr.WriteByte(8); ihdr.WriteByte(2); ihdr.WriteByte(0); ihdr.WriteByte(0); ihdr.WriteByte(0);
        PngChunk(png, "IHDR", ihdr.ToArray());
        PngChunk(png, "IDAT", zlib.ToArray());
        PngChunk(png, "IEND", System.Array.Empty<byte>());
        File.WriteAllBytes(ReadCStr(pathc), png.ToArray());
        return 0;
    }

    // ---- animated GIF (GIF89a, shared palette, LZW) ----
    public static int tc_gif(int pathc)
    {
        if (_tframes.Count == 0) tc_frame(5);
        // build palette from distinct colors across frames (cap 256)
        var map = new System.Collections.Generic.Dictionary<int, int>();
        var pal = new System.Collections.Generic.List<int>();
        foreach (var fr in _tframes) foreach (int c in fr) { int rgb = c & 0xFFFFFF; if (!map.ContainsKey(rgb) && pal.Count < 256) { map[rgb] = pal.Count; pal.Add(rgb); } }
        if (pal.Count == 0) pal.Add(0);
        int bits = 1; while ((1 << bits) < pal.Count) bits++; int tableSize = 1 << bits;
        int Idx(int c) { int rgb = c & 0xFFFFFF; if (map.TryGetValue(rgb, out int v)) return v; int best = 0, bd = int.MaxValue; for (int i = 0; i < pal.Count; i++) { int dr = ((pal[i] >> 16) & 255) - ((rgb >> 16) & 255), dg = ((pal[i] >> 8) & 255) - ((rgb >> 8) & 255), db2 = (pal[i] & 255) - (rgb & 255); int d = dr * dr + dg * dg + db2 * db2; if (d < bd) { bd = d; best = i; } } return best; }
        var m = new MemoryStream();
        m.Write(Encoding.ASCII.GetBytes("GIF89a"), 0, 6);
        m.WriteByte((byte)_tcw); m.WriteByte((byte)(_tcw >> 8)); m.WriteByte((byte)_tch); m.WriteByte((byte)(_tch >> 8));
        m.WriteByte((byte)(0xF0 | (bits - 1))); m.WriteByte(0); m.WriteByte(0);            // global color table, depth
        for (int i = 0; i < tableSize; i++) { int c = i < pal.Count ? pal[i] : 0; m.WriteByte((byte)(c >> 16)); m.WriteByte((byte)(c >> 8)); m.WriteByte((byte)c); }
        // NETSCAPE loop forever
        m.Write(new byte[] { 0x21, 0xFF, 0x0B }, 0, 3); m.Write(Encoding.ASCII.GetBytes("NETSCAPE2.0"), 0, 11); m.Write(new byte[] { 0x03, 0x01, 0x00, 0x00, 0x00 }, 0, 5);
        for (int f = 0; f < _tframes.Count; f++)
        {
            int delay = _tdelay[f];
            m.Write(new byte[] { 0x21, 0xF9, 0x04, 0x00, (byte)delay, (byte)(delay >> 8), 0x00, 0x00 }, 0, 8);   // graphic control (delay)
            m.WriteByte(0x2C); m.WriteByte(0); m.WriteByte(0); m.WriteByte(0); m.WriteByte(0);
            m.WriteByte((byte)_tcw); m.WriteByte((byte)(_tcw >> 8)); m.WriteByte((byte)_tch); m.WriteByte((byte)(_tch >> 8)); m.WriteByte(0);  // image descriptor
            byte[] idx = new byte[_tcw * _tch]; var fr = _tframes[f]; for (int i = 0; i < idx.Length; i++) idx[i] = (byte)Idx(fr[i]);
            GifLzw(m, idx, bits);
        }
        m.WriteByte(0x3B);   // trailer
        File.WriteAllBytes(ReadCStr(pathc), m.ToArray());
        return 0;
    }
    private static void GifLzw(MemoryStream outp, byte[] idx, int minBits)
    {
        int minCode = minBits < 2 ? 2 : minBits;
        outp.WriteByte((byte)minCode);
        int clear = 1 << minCode, end = clear + 1;
        var dict = new System.Collections.Generic.Dictionary<string, int>();
        void Reset() { dict.Clear(); for (int i = 0; i < clear; i++) dict[((char)i).ToString()] = i; }
        Reset(); int next = end + 1, codeSize = minCode + 1;
        var bitbuf = new System.Collections.Generic.List<byte>(); int cur = 0, nbits = 0;
        void Emit(int code) { cur |= code << nbits; nbits += codeSize; while (nbits >= 8) { bitbuf.Add((byte)(cur & 255)); cur >>= 8; nbits -= 8; } }
        Emit(clear);
        string w = "";
        foreach (byte b in idx)
        {
            string wc = w + (char)b;
            if (dict.ContainsKey(wc)) { w = wc; }
            else { Emit(dict[w]); dict[wc] = next++; if (next > (1 << codeSize) && codeSize < 12) codeSize++; if (next >= 4096) { Emit(clear); Reset(); next = end + 1; codeSize = minCode + 1; } w = wc.Substring(wc.Length - 1); }
        }
        if (w.Length > 0) Emit(dict[w]);
        Emit(end);
        if (nbits > 0) bitbuf.Add((byte)(cur & 255));
        // sub-blocks of <=255
        int pos = 0; while (pos < bitbuf.Count) { int n = System.Math.Min(255, bitbuf.Count - pos); outp.WriteByte((byte)n); for (int i = 0; i < n; i++) outp.WriteByte(bitbuf[pos + i]); pos += n; }
        outp.WriteByte(0);
    }
}

// A small VT102-ish terminal: a character grid with cursor, colours, scroll,
// and a parser for the escape sequences our shell/utilities/vi emit. The
// display server (Avalonia) feeds output bytes in and renders the cells; the
// headless test harness feeds bytes in and reads ToText(). Reusable, no GUI.
public sealed class TermGrid
{
    public int Cols, Rows, Cx, Cy;
    public char[] Ch = System.Array.Empty<char>();
    public byte[] Fg = System.Array.Empty<byte>();
    public byte[] Bg = System.Array.Empty<byte>();
    private int _fg = 7, _bg = 0;
    private int _state;                 // 0 normal, 1 saw ESC, 2 in CSI
    private readonly List<int> _ps = new();
    private int _cur;

    public TermGrid(int c, int r) => Resize(c, r);

    public void Resize(int c, int r)
    {
        if (c < 1) c = 1; if (r < 1) r = 1;
        var nc = new char[c * r]; var nf = new byte[c * r]; var nb = new byte[c * r];
        for (int i = 0; i < nc.Length; i++) { nc[i] = ' '; nf[i] = 7; }
        // preserve overlapping cells
        if (Ch.Length > 0) for (int y = 0; y < Math.Min(r, Rows); y++) for (int x = 0; x < Math.Min(c, Cols); x++)
            { nc[y * c + x] = Ch[y * Cols + x]; nf[y * c + x] = Fg[y * Cols + x]; nb[y * c + x] = Bg[y * Cols + x]; }
        Cols = c; Rows = r; Ch = nc; Fg = nf; Bg = nb;
        if (Cx >= c) Cx = c - 1; if (Cy >= r) Cy = r - 1;
    }

    public void Process(byte[] b) { foreach (var x in b) Process(x); }
    public void Process(int b)
    {
        if (_state == 0)
        {
            switch (b)
            {
                case 27: _state = 1; break;
                case (int)'\n': Cx = 0; Lf(); break;
                case (int)'\r': Cx = 0; break;
                case (int)'\b': if (Cx > 0) Cx--; break;
                case (int)'\t': Cx = (Cx + 8) & ~7; if (Cx >= Cols) Cx = Cols - 1; break;
                case 7: break;                                   // bell
                default: if (b >= 32) Put((char)b); break;
            }
        }
        else if (_state == 1) { if (b == '[') { _state = 2; _ps.Clear(); _cur = 0; } else _state = 0; }
        else { Csi(b); }
    }

    private void Csi(int b)
    {
        if (b >= '0' && b <= '9') { _cur = _cur * 10 + (b - '0'); return; }
        if (b == ';') { _ps.Add(_cur); _cur = 0; return; }
        _ps.Add(_cur);
        int P(int i, int d) => i < _ps.Count && _ps[i] != 0 ? _ps[i] : d;
        switch ((char)b)
        {
            case 'H': case 'f': Cy = Clamp(P(0, 1) - 1, 0, Rows - 1); Cx = Clamp(P(1, 1) - 1, 0, Cols - 1); break;
            case 'A': Cy = Clamp(Cy - P(0, 1), 0, Rows - 1); break;
            case 'B': Cy = Clamp(Cy + P(0, 1), 0, Rows - 1); break;
            case 'C': Cx = Clamp(Cx + P(0, 1), 0, Cols - 1); break;
            case 'D': Cx = Clamp(Cx - P(0, 1), 0, Cols - 1); break;
            case 'J': EraseDisplay(_ps.Count > 0 ? _ps[0] : 0); break;
            case 'K': EraseLine(_ps.Count > 0 ? _ps[0] : 0); break;
            case 'm': Sgr(); break;
        }
        _state = 0;
    }

    private bool _bold;
    private void Sgr()
    {
        if (_ps.Count == 0) { _fg = 7; _bg = 0; _bold = false; return; }
        foreach (int p in _ps)
        {
            if (p == 0) { _fg = 7; _bg = 0; _bold = false; }
            else if (p == 1) { _bold = true; if (_fg < 8) _fg += 8; }
            else if (p == 22) { _bold = false; if (_fg >= 8) _fg -= 8; }
            else if (p >= 30 && p <= 37) _fg = (p - 30) + (_bold ? 8 : 0);
            else if (p >= 90 && p <= 97) _fg = (p - 90) + 8;       // bright foreground
            else if (p >= 40 && p <= 47) _bg = p - 40;
            else if (p >= 100 && p <= 107) _bg = (p - 100) + 8;    // bright background
            else if (p == 39) _fg = 7; else if (p == 49) _bg = 0;
        }
    }

    private static int Clamp(int v, int lo, int hi) => v < lo ? lo : v > hi ? hi : v;
    private void Put(char ch) { if (Cx >= Cols) { Cx = 0; Lf(); } int i = Cy * Cols + Cx; Ch[i] = ch; Fg[i] = (byte)_fg; Bg[i] = (byte)_bg; Cx++; }
    private void Lf() { Cy++; if (Cy >= Rows) { Scroll(); Cy = Rows - 1; } }
    private void Scroll()
    {
        System.Array.Copy(Ch, Cols, Ch, 0, (Rows - 1) * Cols);
        System.Array.Copy(Fg, Cols, Fg, 0, (Rows - 1) * Cols);
        System.Array.Copy(Bg, Cols, Bg, 0, (Rows - 1) * Cols);
        int last = (Rows - 1) * Cols;
        for (int x = 0; x < Cols; x++) { Ch[last + x] = ' '; Fg[last + x] = 7; Bg[last + x] = 0; }
    }
    private void EraseLine(int mode)
    {
        int s = mode == 1 ? 0 : Cx, e = mode == 0 ? Cols : Cx + 1;
        if (mode == 2) { s = 0; e = Cols; }
        for (int x = s; x < e && x < Cols; x++) { Ch[Cy * Cols + x] = ' '; Bg[Cy * Cols + x] = 0; }
    }
    private void EraseDisplay(int mode)
    {
        if (mode == 2) { for (int i = 0; i < Ch.Length; i++) { Ch[i] = ' '; Bg[i] = 0; } Cx = 0; Cy = 0; }
        else EraseLine(0);
    }

    public string ToText()
    {
        var sb = new StringBuilder();
        for (int y = 0; y < Rows; y++)
        {
            int end = Cols; while (end > 0 && Ch[y * Cols + end - 1] == ' ') end--;
            for (int x = 0; x < end; x++) sb.Append(Ch[y * Cols + x]);
            sb.Append('\n');
        }
        return sb.ToString();
    }
}
