/* yacc.c — a clean-room LALR(1) parser generator, written in the C subset
 * compiled by `cc`. Reads a .y grammar from stdin, emits a C parser to stdout.
 *
 *   dotnet yacc.dll < grammar.y > parser.c
 *
 * Algorithm: build the canonical LR(1) item-set collection, then merge states
 * with identical LR(0) cores -> LALR(1). ACTION/GOTO tables are produced with
 * precedence/associativity-based shift/reduce resolution (%left/%right/%nonassoc)
 * and earliest-rule reduce/reduce resolution. The emitted parser is a standard
 * table-driven LR engine driving yylex(); semantic values are int (YYSTYPE).
 */

char src[400000]; int srclen;
char topcode[200000]; int ntop;
char usercode[200000]; int nuser;

/* ---- symbols: 0 = $end. terminals then nonterminals, interleaved by use ---- */
char symname[512][40];
int  symterm[512];     /* 1 = terminal */
int  symprec[512];     /* precedence level (0 = none) */
int  symassoc[512];    /* 0 none, 1 left, 2 right, 3 nonassoc */
int  tokcode[512];     /* token code yylex returns (terminals) */
int  nsym;
int  preclevel;
int  nextcode;         /* next named-token code (starts 257) */

/* ---- productions ---- */
int  plhs[600];
int  prhs[600][24];
int  plen[600];
char pact[600][4096];
int  pprec[600];
int  nprod;
int  startsym;

/* output helpers */
void outc(int c) { putchar(c); }
void outs(char *s) { int i = 0; while (s[i]) putchar(s[i++]); }
void outd(int n) { char t[16]; int i = 0; if (n < 0) { putchar('-'); n = -n; } if (n == 0) { putchar('0'); return; } while (n > 0) { t[i++] = '0' + (n % 10); n = n / 10; } while (i > 0) putchar(t[--i]); }

/* diagnostics + fatal errors go to stderr (fd 3), so they don't pollute the
 * parser written to stdout. */
void eputs(char *s) { fputs((int)s, 3); }
void eputn(int n) { char t[16]; int i = 0, j = 0; char b[16]; if (n == 0) { eputs("0"); return; } if (n < 0) { eputs("-"); n = -n; } while (n > 0) { t[i++] = '0' + (n % 10); n = n / 10; } while (i > 0) b[j++] = t[--i]; b[j] = 0; eputs(b); }
void die(char *s, int n) { eputs("yacc: "); eputs(s); eputs(" ("); eputn(n); eputs(")\n"); exit(2); }

int streq(char *a, char *b) { return strcmp(a, b) == 0; }

int findsym(char *name)
{
    int i; for (i = 0; i < nsym; i++) if (streq(symname[i], name)) return i;
    return -1;
}
int addsym(char *name, int isterm)
{
    int id = findsym(name);
    if (id >= 0) return id;
    id = nsym++;
    int j = 0; while (name[j]) { symname[id][j] = name[j]; j++; } symname[id][j] = 0;
    symterm[id] = isterm; symprec[id] = 0; symassoc[id] = 0; tokcode[id] = 0;
    return id;
}

/* ======================= reading the .y file ======================= */
int p;   /* cursor into src */

void skipws(void)
{
    while (p < srclen)
    {
        int c = src[p];
        if (c == ' ' || c == '\t' || c == '\n' || c == 13) { p++; continue; }
        if (c == '/' && src[p + 1] == '*') { p = p + 2; while (p < srclen && !(src[p] == '*' && src[p + 1] == '/')) p++; p = p + 2; continue; }
        break;
    }
}

int at_sep(void) { return src[p] == '%' && src[p + 1] == '%'; }
int next_line(int q) { while (q < srclen && src[q] != '\n') q++; if (q < srclen) q++; return q; }

/* read an identifier or 'c' char-literal token name into buf; returns 1 if a
 * char-literal (so caller knows the token code), else 0. returns -1 if none. */
int read_symname(char *buf)
{
    skipws();
    if (p >= srclen) return -1;
    if (src[p] == '\'')
    {
        p++;
        int c;
        if (src[p] == '\\') { p++; c = src[p]; if (c == 'n') c = 10; else if (c == 't') c = 9; else if (c == 'r') c = 13; else if (c == '0') c = 0; p++; }
        else { c = src[p]; p++; }
        if (src[p] == '\'') p++;
        buf[0] = (char)c; buf[1] = 0;
        return c;          /* char-literal: token code is the char */
    }
    if (isalpha(src[p]) || src[p] == '_')
    {
        int j = 0;
        while (p < srclen && (isalnum(src[p]) || src[p] == '_')) buf[j++] = src[p++];
        buf[j] = 0;
        return -2;          /* identifier */
    }
    return -1;
}

void declare_tokens(int assoc)
{
    /* read symbol names to end of line; assoc<0 => %token (no precedence) */
    if (assoc >= 0) preclevel++;
    int eol = next_line(p);
    while (p < eol)
    {
        skipws();
        if (p >= eol) break;
        char nm[40];
        int r = read_symname(nm);
        if (r == -1) break;
        int id = addsym(nm, 1);
        if (r >= 0) tokcode[id] = r;               /* char literal */
        else { if (tokcode[id] == 0) tokcode[id] = nextcode++; }
        if (assoc >= 0) { symprec[id] = preclevel; symassoc[id] = assoc; }
    }
    p = eol;
}

void read_declarations(void)
{
    while (p < srclen)
    {
        skipws();
        if (at_sep()) { p = p + 2; p = next_line(p); return; }
        if (src[p] == '%' && src[p + 1] == '{')
        {
            p = next_line(p);
            while (p < srclen && !(src[p] == '%' && src[p + 1] == '}'))
            {
                int e = next_line(p); int i = p; while (i < e) { if (ntop >= 200000) die("prologue too long (topcode)", ntop); topcode[ntop++] = src[i++]; } p = e;
            }
            p = next_line(p);
            continue;
        }
        if (src[p] == '%')
        {
            if (strncmp(src + p, "%token", 6) == 0) { p = p + 6; declare_tokens(-1); }
            else if (strncmp(src + p, "%left", 5) == 0) { p = p + 5; declare_tokens(1); }
            else if (strncmp(src + p, "%right", 6) == 0) { p = p + 6; declare_tokens(2); }
            else if (strncmp(src + p, "%nonassoc", 9) == 0) { p = p + 9; declare_tokens(3); }
            else if (strncmp(src + p, "%start", 6) == 0)
            {
                p = p + 6; char nm[40]; read_symname(nm); startsym = addsym(nm, 0);
                p = next_line(p);
            }
            else p = next_line(p);   /* %type, %union, %option, ... ignored */
            continue;
        }
        /* a stray line in declarations */
        p = next_line(p);
    }
}

void read_action(char *out)
{
    int depth = 0; int k = 0;
    p++;   /* skip '{' */
    while (p < srclen)
    {
        int c = src[p];
        if (k >= 4090) die("action too long", k);
        /* copy string/char literals verbatim so their braces don't fool the
         * nesting counter (actions emit C like e("{\n")). */
        if (c == '"' || c == '\'')
        {
            int q = c; out[k++] = src[p++];
            while (p < srclen && src[p] != q)
            {
                if (src[p] == '\\') { out[k++] = src[p++]; if (p < srclen) out[k++] = src[p++]; continue; }
                out[k++] = src[p++];
            }
            if (p < srclen) out[k++] = src[p++];   /* closing quote */
            continue;
        }
        if (c == '/' && src[p + 1] == '/') { while (p < srclen && src[p] != '\n') out[k++] = src[p++]; continue; }
        if (c == '/' && src[p + 1] == '*')
        {
            out[k++] = src[p++]; out[k++] = src[p++];
            while (p < srclen && !(src[p] == '*' && src[p + 1] == '/')) out[k++] = src[p++];
            if (p < srclen) { out[k++] = src[p++]; out[k++] = src[p++]; }
            continue;
        }
        if (c == '{') depth++;
        if (c == '}') { if (depth == 0) { p++; break; } depth--; }
        out[k++] = c; p++;
    }
    out[k] = 0;
}

/* is a name a terminal? declared via %token/%left/.. or char-literal */
void read_rules(void)
{
    while (1)
    {
        skipws();
        if (p >= srclen || at_sep()) { if (at_sep()) { p = p + 2; p = next_line(p); } return; }

        char lhsname[40];
        if (read_symname(lhsname) != -2) { p = next_line(p); continue; }
        int lhs = addsym(lhsname, 0);
        if (startsym < 0) startsym = lhs;
        skipws();
        if (src[p] == ':') p++;

        /* one alternative per iteration */
        while (1)
        {
            int prod = nprod++;
            plhs[prod] = lhs; plen[prod] = 0; pact[prod][0] = 0; pprec[prod] = 0;
            int lastterm = -1;

            while (1)
            {
                skipws();
                int c = src[p];
                if (c == '|' || c == ';' || at_sep() || p >= srclen) break;
                if (c == '{') { read_action(pact[prod]); continue; }
                if (c == '%' && strncmp(src + p, "%prec", 5) == 0)
                {
                    p = p + 5; char nm[40]; read_symname(nm); int s = findsym(nm);
                    if (s >= 0) pprec[prod] = symprec[s];
                    continue;
                }
                char nm[40];
                int r = read_symname(nm);
                if (r == -1) { p++; continue; }
                int isterm = (r >= 0);                 /* char literal => terminal */
                int s = findsym(nm);
                if (s < 0) s = addsym(nm, isterm);
                if (r >= 0) { symterm[s] = 1; if (tokcode[s] == 0) tokcode[s] = r; }
                prhs[prod][plen[prod]++] = s;
                if (symterm[s]) lastterm = s;
            }
            if (pprec[prod] == 0 && lastterm >= 0) pprec[prod] = symprec[lastterm];

            skipws();
            if (src[p] == '|') { p++; continue; }
            if (src[p] == ';') { p++; break; }
            break;
        }
    }
}

void read_usercode(void) { while (p < srclen) { if (nuser >= 199999) die("user-code too long", nuser); usercode[nuser++] = src[p++]; } usercode[nuser] = 0; }

/* ======================= FIRST / nullable ======================= */
int nullable[512];
int firstbs[512][16];   /* bitset over symbol ids (512 bits) */

int getb(int *bs, int i) { return (bs[i >> 5] >> (i & 31)) & 1; }
void setb(int *bs, int i) { bs[i >> 5] = bs[i >> 5] | (1 << (i & 31)); }

void compute_first(void)
{
    int i, j, k;
    for (i = 0; i < nsym; i++) { nullable[i] = 0; for (j = 0; j < 16; j++) firstbs[i][j] = 0; }
    for (i = 0; i < nsym; i++) if (symterm[i]) setb(firstbs[i], i);

    int changed = 1;
    while (changed)
    {
        changed = 0;
        for (i = 0; i < nprod; i++)
        {
            int A = plhs[i]; int allnull = 1; int x;
            for (x = 0; x < plen[i]; x++)
            {
                int X = prhs[i][x];
                /* add FIRST(X) to FIRST(A) */
                for (k = 0; k < nsym; k++)
                    if (getb(firstbs[X], k) && !getb(firstbs[A], k)) { setb(firstbs[A], k); changed = 1; }
                if (!nullable[X]) { allnull = 0; break; }
            }
            if (allnull && !nullable[A]) { nullable[A] = 1; changed = 1; }
        }
    }
}

/* FIRST of the string (prhs[prod] from index dot .. end) followed by lookahead la,
 * written into bitset out. */
void first_of_tail(int prod, int dot, int la, int *out)
{
    int x;
    for (x = dot; x < plen[prod]; x++)
    {
        int X = prhs[prod][x]; int k;
        for (k = 0; k < nsym; k++) if (getb(firstbs[X], k)) setb(out, k);
        if (!nullable[X]) return;
    }
    setb(out, la);
}

/* ======================= LR(1) item sets ======================= */
/* item = (prod*25 + dot)*256 + la */
int mkitem(int prod, int dot, int la) { return (prod * 25 + dot) * 256 + la; }
int it_prod(int it) { return (it / 256) / 25; }
int it_dot(int it) { return (it / 256) % 25; }
int it_la(int it) { return it % 256; }

int W[120000]; int wn;     /* working item list */
void addW(int it) { int i; for (i = 0; i < wn; i++) if (W[i] == it) return; if (wn >= 120000) die("item-set overflow (W)", wn); W[wn++] = it; }

void closure(void)
{
    int i = 0;
    while (i < wn)
    {
        int it = W[i++];
        int prod = it_prod(it), dot = it_dot(it), la = it_la(it);
        if (dot >= plen[prod]) continue;
        int B = prhs[prod][dot];
        if (symterm[B]) continue;
        int fb[16]; int z; for (z = 0; z < 16; z++) fb[z] = 0;
        first_of_tail(prod, dot + 1, la, fb);
        int q;
        for (q = 0; q < nprod; q++) if (plhs[q] == B)
        {
            int b;
            for (b = 0; b < nsym; b++) if (getb(fb, b)) addW(mkitem(q, 0, b));
        }
    }
}

void sortints(int *a, int n) { int i, j; for (i = 1; i < n; i++) { int v = a[i]; j = i - 1; while (j >= 0 && a[j] > v) { a[j + 1] = a[j]; j--; } a[j + 1] = v; } }

/* LALR(1) by construction: states are identified by their LR(0) core (the set of
 * prod*25+dot, ignoring lookahead). When a goto reaches a state whose core already
 * exists, we UNION the new lookaheads into it and (if they grew) re-queue it so the
 * extra lookaheads propagate. This keeps the state count at the LR(0) level instead
 * of exploding into canonical LR(1) states. Each state's items live in a fixed-stride
 * slot of `pool` (so a state can grow in place); a hash over the core gives O(1) lookup. */
#define MAXST 3000
#define STRIDE 5000
#define CORESZ 1024
int pool[15000000];             /* MAXST * STRIDE items; state s occupies [s*STRIDE .. +slen[s]) */
int slen[MAXST]; int nstate;
int trans[MAXST][512];
int cstore[3072000]; int clen[MAXST];   /* MAXST * CORESZ : LR(0) core (sorted distinct it/256) per state */
int hh[8192]; int hn[MAXST];             /* hash buckets over the core, for fast lookup */
int wq[24000]; int qh, qt; int inq[MAXST];   /* worklist ring of states to (re)process */
int nmerged;                             /* = nstate (the ACTION/GOTO builder calls them "merged") */

int sortuniq_core(int *items, int n, int *out)   /* distinct sorted (it/256) of items[0..n) */
{
    int i; for (i = 0; i < n; i++) out[i] = items[i] / 256;
    sortints(out, n);
    int m = 0; for (i = 0; i < n; i++) if (m == 0 || out[i] != out[m - 1]) out[m++] = out[i];
    return m;
}
int corehash(int *c, int n) { int h = 0, i; for (i = 0; i < n; i++) h = (h * 131 + c[i] + 1) & 0x7fffffff; return h; }
int core_eq(int s, int *c, int n) { if (clen[s] != n) return 0; int i; for (i = 0; i < n; i++) if (cstore[s * CORESZ + i] != c[i]) return 0; return 1; }
void enqueue(int s) { if (inq[s]) return; inq[s] = 1; wq[qt++] = s; if (qt >= 24000) qt = 0; }

/* W (about to be sorted) is a closured item set; merge into the state with the same
 * LR(0) core, or create a new state. Returns the state id (and queues work). */
int find_or_merge(void)
{
    sortints(W, wn);
    int core[CORESZ]; int cn = sortuniq_core(W, wn, core);
    if (cn >= CORESZ) die("state core overflow", cn);
    int h = corehash(core, cn) & 8191;
    int s = hh[h];
    while (s >= 0)
    {
        if (core_eq(s, core, cn))
        {
            int base = s * STRIDE; int merged[STRIDE]; int mn = 0; int i = 0, j = 0;   /* sorted union */
            while (i < slen[s] && j < wn)
            {
                int a = pool[base + i], b = W[j];
                if (a == b) { merged[mn++] = a; i++; j++; }
                else if (a < b) { merged[mn++] = a; i++; }
                else { merged[mn++] = b; j++; }
            }
            while (i < slen[s]) merged[mn++] = pool[base + i++];
            while (j < wn) merged[mn++] = W[j++];
            if (mn > slen[s])
            {
                if (mn >= STRIDE) die("state item overflow", mn);
                int k; for (k = 0; k < mn; k++) pool[base + k] = merged[k];
                slen[s] = mn; enqueue(s);
            }
            return s;
        }
        s = hn[s];
    }
    if (nstate >= MAXST) die("too many LALR states", nstate);
    if (wn >= STRIDE) die("state item overflow", wn);
    s = nstate++;
    int base = s * STRIDE; int k; for (k = 0; k < wn; k++) pool[base + k] = W[k];
    slen[s] = wn;
    for (k = 0; k < cn; k++) cstore[s * CORESZ + k] = core[k];
    clen[s] = cn;
    hn[s] = hh[h]; hh[h] = s;
    int x; for (x = 0; x < 512; x++) trans[s][x] = -1;
    enqueue(s);
    return s;
}

void build_lalr(void)
{
    int i; for (i = 0; i < 8192; i++) hh[i] = -1;
    nstate = 0; qh = 0; qt = 0; for (i = 0; i < MAXST; i++) inq[i] = 0;
    wn = 0; addW(mkitem(0, 0, 0)); closure(); find_or_merge();
    while (qh != qt)
    {
        int s = wq[qh++]; if (qh >= 24000) qh = 0; inq[s] = 0;
        int X;
        for (X = 0; X < nsym; X++)
        {
            wn = 0;
            int base = s * STRIDE;
            for (i = 0; i < slen[s]; i++)
            {
                int it = pool[base + i]; int prod = it_prod(it), dot = it_dot(it), la = it_la(it);
                if (dot < plen[prod] && prhs[prod][dot] == X) addW(mkitem(prod, dot + 1, la));
            }
            if (wn == 0) { trans[s][X] = -1; continue; }
            closure();
            trans[s][X] = find_or_merge();
        }
    }
    nmerged = nstate;
}

/* ======================= ACTION / GOTO ======================= */
int *gAct; int *gArg; int *gGo;   /* sized nmerged*nsym */
int nconflict;

void set_action(int m, int sym, int type, int arg)
{
    int idx = m * nsym + sym;
    int cur = gAct[idx];
    if (cur == 0) { gAct[idx] = type; gArg[idx] = arg; return; }
    if (cur == type && gArg[idx] == arg) return;

    /* conflict */
    if (cur == 1 && type == 2)        /* shift/reduce */
    {
        int tp = symprec[sym]; int rp = pprec[arg];
        if (tp > 0 && rp > 0)
        {
            if (rp > tp) { gAct[idx] = 2; gArg[idx] = arg; }
            else if (rp == tp) { if (symassoc[sym] == 1) { gAct[idx] = 2; gArg[idx] = arg; } else if (symassoc[sym] == 3) { gAct[idx] = 0; } }
            return;   /* rp<tp or right-assoc: keep shift */
        }
        nconflict++; return;          /* default: keep shift */
    }
    if (cur == 2 && type == 1)        /* reduce/shift (shift requested over reduce) */
    {
        int tp = symprec[sym]; int rp = pprec[gArg[idx]];
        if (tp > 0 && rp > 0)
        {
            if (rp > tp) return;                       /* keep reduce */
            if (rp == tp && symassoc[sym] == 1) return;/* left: keep reduce */
            if (rp == tp && symassoc[sym] == 3) { gAct[idx] = 0; return; }
            gAct[idx] = 1; gArg[idx] = arg; return;    /* shift wins */
        }
        nconflict++; gAct[idx] = 1; gArg[idx] = arg; return;  /* default shift */
    }
    if (cur == 2 && type == 2)        /* reduce/reduce: keep lower production */
    {
        nconflict++;
        if (arg < gArg[idx]) gArg[idx] = arg;
        return;
    }
    /* accept or others: leave as-is */
}

void build_tables(void)
{
    int sz = nstate * nsym;
    gAct = (int *)malloc(sz * 4); gArg = (int *)malloc(sz * 4); gGo = (int *)malloc(sz * 4);
    int i; for (i = 0; i < sz; i++) { gAct[i] = 0; gArg[i] = 0; gGo[i] = -1; }

    int m;
    for (m = 0; m < nstate; m++)
    {
        int base = m * STRIDE;
        for (i = 0; i < slen[m]; i++)
        {
            int it = pool[base + i];
            int prod = it_prod(it), dot = it_dot(it), la = it_la(it);
            if (dot < plen[prod])
            {
                int X = prhs[prod][dot];
                if (symterm[X]) { int t = trans[m][X]; if (t >= 0) set_action(m, X, 1, t); }
            }
            else
            {
                if (prod == 0 && la == 0) { gAct[m * nsym + 0] = 3; }   /* accept on $end */
                else set_action(m, la, 2, prod);
            }
        }
        int X;
        for (X = 0; X < nsym; X++) if (!symterm[X]) { int t = trans[m][X]; if (t >= 0) gGo[m * nsym + X] = t; }
    }
}

/* ======================= emit ======================= */
void emit_iarray(char *name, int *a, int n) { outs("int "); outs(name); outs("["); outd(n); outs("] = {"); int i; for (i = 0; i < n; i++) { if (i) outs(","); outd(a[i]); } outs("};\n"); }

void emit_action_code(char *s)
{
    int i = 0;
    while (s[i])
    {
        if (s[i] == '$')
        {
            if (s[i + 1] == '$') { outs("yyval"); i = i + 2; continue; }
            if (s[i + 1] >= '0' && s[i + 1] <= '9')
            {
                int n = 0; i++; while (s[i] >= '0' && s[i] <= '9') { n = n * 10 + (s[i] - '0'); i++; }
                outs("yyvs[yybase+"); outd(n - 1); outs("]");
                continue;
            }
        }
        putchar(s[i++]);
    }
}

void emit_parser(void)
{
    outs("/* generated by yacc.c — do not edit */\n");
    int i; for (i = 0; i < ntop; i++) putchar(topcode[i]);
    outs("\n");

    /* token-code enum so the (separately generated) scanner can name tokens */
    for (i = 0; i < nsym; i++)
        if (symterm[i] && i != 0 && isalpha(symname[i][0])) { outs("enum { "); outs(symname[i]); outs(" = "); outd(tokcode[i]); outs(" };\n"); }

    int maxcode = 0;
    for (i = 0; i < nsym; i++) if (symterm[i] && tokcode[i] > maxcode) maxcode = tokcode[i];
    int trn = maxcode + 1;
    int *tr = (int *)malloc(trn * 4);
    for (i = 0; i < trn; i++) tr[i] = -1;
    for (i = 0; i < nsym; i++) if (symterm[i]) tr[tokcode[i]] = i;
    emit_iarray("yytranslate", tr, trn);

    emit_iarray("yyact", gAct, nmerged * nsym);
    emit_iarray("yyarg", gArg, nmerged * nsym);
    emit_iarray("yygoto", gGo, nmerged * nsym);

    int *pl = (int *)malloc(nprod * 4); int *ph = (int *)malloc(nprod * 4);
    for (i = 0; i < nprod; i++) { pl[i] = plen[i]; ph[i] = plhs[i]; }
    emit_iarray("yyplen", pl, nprod);
    emit_iarray("yyplhs", ph, nprod);

    outs("int yyns = "); outd(nsym); outs(";\n");
    outs("int yymaxcode = "); outd(maxcode); outs(";\n");
    outs("int yylval; int yyval;\n");
    outs("int yyss[8192]; int yyvs[8192];\n");
    outs("int yyerror(char *s) { printf(\"%s\\n\", s); return 0; }\n");

    outs("int yyparse(void) {\n");
    outs("  int yysp = 0; yyss[0] = 0; yysp = 1;\n");
    outs("  int tok = yylex();\n");
    outs("  while (1) {\n");
    outs("    int st = yyss[yysp-1];\n");
    outs("    int sym = (tok >= 0 && tok <= yymaxcode) ? yytranslate[tok] : -1;\n");
    outs("    if (sym < 0) { yyerror(\"syntax error: bad token\"); return 1; }\n");
    outs("    int at = yyact[st*yyns + sym];\n");
    outs("    if (at == 1) { yyss[yysp] = yyarg[st*yyns + sym]; yyvs[yysp] = yylval; yysp = yysp + 1; tok = yylex(); }\n");
    outs("    else if (at == 3) { return 0; }\n");
    outs("    else if (at == 2) {\n");
    outs("      int r = yyarg[st*yyns + sym];\n");
    outs("      int len = yyplen[r]; int yybase = yysp - len;\n");
    outs("      if (len > 0) yyval = yyvs[yybase]; else yyval = 0;\n");
    outs("      switch (r) {\n");
    for (i = 1; i < nprod; i++)
        if (pact[i][0]) { outs("        case "); outd(i); outs(": { "); emit_action_code(pact[i]); outs(" } break;\n"); }
    outs("      }\n");
    outs("      yysp = yysp - len;\n");
    outs("      int lhs = yyplhs[r];\n");
    outs("      yyss[yysp] = yygoto[yyss[yysp-1]*yyns + lhs]; yyvs[yysp] = yyval; yysp = yysp + 1;\n");
    outs("    }\n");
    outs("    else { yyerror(\"syntax error\"); return 1; }\n");
    outs("  }\n");
    outs("}\n");

    for (i = 0; i < nuser; i++) putchar(usercode[i]);
}

int verbose;   /* -v: print grammar diagnostics (symbols/states/conflicts) to stderr */

int main(int argc, char **argv)
{
    int ai; for (ai = 1; ai < argc; ai++) if (strcmp((char *)argv[ai], "-v") == 0) verbose = 1;
    int ch; srclen = 0;
    while ((ch = getchar()) >= 0) if (ch != 13) src[srclen++] = (char)ch;
    src[srclen] = 0;

    nsym = 0; addsym("$end", 1); tokcode[0] = 0;   /* symbol 0 = end-of-input */
    nextcode = 257; startsym = -1; preclevel = 0; p = 0;

    read_declarations();
    read_rules();
    read_usercode();

    /* augmented production 0: S' -> startsym */
    int sprime = addsym("$accept", 0);
    int i; for (i = nprod; i > 0; i--) { plhs[i] = plhs[i - 1]; plen[i] = plen[i - 1]; pprec[i] = pprec[i - 1]; int j; for (j = 0; j < 24; j++) prhs[i][j] = prhs[i - 1][j]; j = 0; while (pact[i - 1][j]) { pact[i][j] = pact[i - 1][j]; j++; } pact[i][j] = 0; }
    nprod++;
    plhs[0] = sprime; prhs[0][0] = startsym; plen[0] = 1; pact[0][0] = 0; pprec[0] = 0;

    if (verbose) { eputs("yacc: nsym="); eputn(nsym); eputs(" nprod="); eputn(nprod); eputs("\n"); }
    if (nsym >= 512) die("too many symbols", nsym);
    if (nprod >= 600) die("too many productions", nprod);
    compute_first();
    build_lalr();
    if (verbose) { eputs("yacc: LALR states="); eputn(nstate); eputs("\n"); }
    build_tables();
    if (verbose) { eputs("yacc: conflicts="); eputn(nconflict); eputs("\n"); }
    emit_parser();
    return 0;
}
