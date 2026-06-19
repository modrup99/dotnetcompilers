/* Prolog interpreter (written in our C -> IL via cc). Hand-written tokenizer +
 * precedence-climbing term reader (Prolog's operator syntax + comma-as-arg-sep-vs-
 * conjunction is cleaner by hand than via yacc), and the engine: structure-sharing
 * terms, unification with a binding trail, SLD resolution with chronological
 * backtracking, and cut. Loads clauses from a file; `:- Goal.` / `?- Goal.` run.
 */

/* ---- terms (tagged objects, int handles) ---- */
#define A_ATOM 0
#define A_NUM 1
#define A_VAR 2
#define A_CMP 3
struct T { int tag; char *fn; int ar; int *args; double num; int ref; };
int ttag(int x) { return ((struct T *)x)->tag; }
char *tfn(int x) { return ((struct T *)x)->fn; }
int tar(int x) { return ((struct T *)x)->ar; }
int targ(int x, int i) { return ((struct T *)x)->args[i]; }
double tnum(int x) { return ((struct T *)x)->num; }

/* interned atoms: one object per name, so atom equality == handle equality */
char *at_name[8000]; int at_obj[8000]; int nat;
int mkatom(char *name)
{
    int i; for (i = 0; i < nat; i++) if (strcmp(at_name[i], name) == 0) return at_obj[i];
    struct T *t = (struct T *)malloc(40); t->tag = A_ATOM; t->fn = (char *)strdup((int)name); t->ar = 0;
    at_name[nat] = t->fn; at_obj[nat] = (int)t; nat++; return (int)t;
}
int mknum(double d) { struct T *t = (struct T *)malloc(40); t->tag = A_NUM; t->num = d; t->fn = ""; return (int)t; }
int mkvar(char *name) { struct T *t = (struct T *)malloc(40); t->tag = A_VAR; t->ref = 0; t->fn = (char *)strdup((int)name); return (int)t; }
int mkcmpv(char *fn, int ar, int *args) { struct T *t = (struct T *)malloc(40); t->tag = A_CMP; t->fn = (char *)strdup((int)fn); t->ar = ar; t->args = args; return (int)t; }
int mkcmp2(char *fn, int a, int b) { int *p = (int *)malloc(8); p[0] = a; p[1] = b; return mkcmpv(fn, 2, p); }
int mkcmp1(char *fn, int a) { int *p = (int *)malloc(4); p[0] = a; return mkcmpv(fn, 1, p); }
int g_nil_, g_true_;
int isnil(int x) { return x == g_nil_; }

int deref(int x) { while (ttag(x) == A_VAR && ((struct T *)x)->ref != 0) x = ((struct T *)x)->ref; return x; }

/* ---- trail (for undoing bindings on backtrack) ---- */
int trail[400000]; int ntrail;
void bindvar(int v, int val) { ((struct T *)v)->ref = val; trail[ntrail++] = v; }
int trail_mark() { return ntrail; }
void undo(int m) { while (ntrail > m) { ntrail--; ((struct T *)trail[ntrail])->ref = 0; } }

int unify(int a, int b)
{
    a = deref(a); b = deref(b);
    if (a == b) return 1;
    if (ttag(a) == A_VAR) { bindvar(a, b); return 1; }
    if (ttag(b) == A_VAR) { bindvar(b, a); return 1; }
    if (ttag(a) == A_NUM && ttag(b) == A_NUM) return tnum(a) == tnum(b);
    if (ttag(a) == A_ATOM && ttag(b) == A_ATOM) return a == b;
    if (ttag(a) == A_CMP && ttag(b) == A_CMP)
    {
        if (strcmp(tfn(a), tfn(b)) != 0 || tar(a) != tar(b)) return 0;
        int i; for (i = 0; i < tar(a); i++) if (!unify(targ(a, i), targ(b, i))) return 0;
        return 1;
    }
    return 0;
}

/* ---- rename a clause: copy with fresh variables ---- */
int rn_old[2000]; int rn_new[2000]; int rn_n;
int copy_term(int x)
{
    x = deref(x);
    int tg = ttag(x);
    if (tg == A_ATOM || tg == A_NUM) return x;
    if (tg == A_VAR) { int i; for (i = 0; i < rn_n; i++) if (rn_old[i] == x) return rn_new[i]; int nv = mkvar(((struct T *)x)->fn); rn_old[rn_n] = x; rn_new[rn_n] = nv; rn_n++; return nv; }
    int n = tar(x); int *p = (int *)malloc(n * 4); int i; for (i = 0; i < n; i++) p[i] = copy_term(targ(x, i)); return mkcmpv(tfn(x), n, p);
}

/* ---- clause database ---- */
int db_head[20000]; int db_body[20000]; int ndb;
void assertz(int head, int body) { db_head[ndb] = head; db_body[ndb] = body; ndb++; }

/* ---- arithmetic ---- */
double evala(int x)
{
    x = deref(x);
    if (ttag(x) == A_NUM) return tnum(x);
    if (ttag(x) == A_CMP)
    {
        char *f = tfn(x);
        if (tar(x) == 2)
        {
            double a = evala(targ(x, 0)), b = evala(targ(x, 1));
            if (strcmp(f, "+") == 0) return a + b;
            if (strcmp(f, "-") == 0) return a - b;
            if (strcmp(f, "*") == 0) return a * b;
            if (strcmp(f, "/") == 0) return a / b;
            if (strcmp(f, "mod") == 0) return (int)a % (int)b;
            if (strcmp(f, "//") == 0) return (int)(a / b);
            if (strcmp(f, "min") == 0) return a < b ? a : b;
            if (strcmp(f, "max") == 0) return a > b ? a : b;
        }
        if (tar(x) == 1) { double a = evala(targ(x, 0)); if (strcmp(f, "-") == 0) return -a; if (strcmp(f, "abs") == 0) return a < 0 ? -a : a; }
    }
    if (ttag(x) == A_ATOM) { if (strcmp(tfn(x), "pi") == 0) return 3.14159265358979; }
    printf((int)"prolog: arithmetic error\n"); return 0;
}

/* ---- writer ---- */
int is_list(int x) { x = deref(x); while (ttag(x) == A_CMP && strcmp(tfn(x), ".") == 0 && tar(x) == 2) x = deref(targ(x, 1)); return x == g_nil_; }
int is_infix(char *f);
void writet(int x)
{
    x = deref(x);
    int tg = ttag(x);
    if (tg == A_NUM) { double d = tnum(x); if (d == (double)(int)d) printf((int)"%d", (int)d); else printf((int)"%g", d); return; }
    if (tg == A_VAR) { printf((int)"_%s", (int)((struct T *)x)->fn); return; }
    if (tg == A_ATOM) { printf((int)"%s", (int)tfn(x)); return; }
    /* compound */
    if (strcmp(tfn(x), ".") == 0 && tar(x) == 2)
    {
        printf((int)"%s", (int)"["); writet(targ(x, 0)); int t = deref(targ(x, 1));
        while (ttag(t) == A_CMP && strcmp(tfn(t), ".") == 0 && tar(t) == 2) { printf((int)"%s", (int)","); writet(targ(t, 0)); t = deref(targ(t, 1)); }
        if (t != g_nil_) { printf((int)"%s", (int)"|"); writet(t); }
        printf((int)"%s", (int)"]"); return;
    }
    if (tar(x) == 2 && is_infix(tfn(x))) { writet(targ(x, 0)); printf((int)"%s", (int)tfn(x)); writet(targ(x, 1)); return; }
    printf((int)"%s(", (int)tfn(x)); int i; for (i = 0; i < tar(x); i++) { if (i) printf((int)"%s", (int)","); writet(targ(x, i)); } printf((int)"%s", (int)")");
}

/* ================= reader ================= */
char *src; int slen; int g_ti;
#define K_ATOM 1
#define K_VAR 2
#define K_NUM 3
#define K_LP 4
#define K_RP 5
#define K_LB 6
#define K_RB 7
#define K_BAR 8
#define K_COMMA 9
#define K_END 10
int tk_kind[60000]; char *tk_s[60000]; double tk_n[60000]; int ntk;

int issym(int c) { return c == '+' || c == '-' || c == '*' || c == '/' || c == '\\' || c == '^' || c == '<' || c == '>' || c == '=' || c == '~' || c == ':' || c == '?' || c == '@' || c == '#' || c == '&'; }
char *sub(int a, int b) { char *r = (char *)malloc(b - a + 1); int i = 0; while (a < b) r[i++] = src[a++]; r[i] = 0; return r; }
void tokenize()
{
    int i = 0; ntk = 0;
    while (i < slen)
    {
        int c = src[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
        if (c == '%') { while (i < slen && src[i] != '\n') i++; continue; }
        if (c == '/' && i + 1 < slen && src[i + 1] == '*') { i += 2; while (i + 1 < slen && !(src[i] == '*' && src[i + 1] == '/')) i++; i += 2; continue; }
        if (c == '.' && (i + 1 >= slen || src[i + 1] == ' ' || src[i + 1] == '\t' || src[i + 1] == '\r' || src[i + 1] == '\n' || src[i + 1] == '%')) { tk_kind[ntk] = K_END; tk_s[ntk] = "."; ntk++; i++; continue; }
        if (c == '(') { tk_kind[ntk] = K_LP; ntk++; i++; continue; }
        if (c == ')') { tk_kind[ntk] = K_RP; ntk++; i++; continue; }
        if (c == '[') { tk_kind[ntk] = K_LB; ntk++; i++; continue; }
        if (c == ']') { tk_kind[ntk] = K_RB; ntk++; i++; continue; }
        if (c == '|') { tk_kind[ntk] = K_BAR; ntk++; i++; continue; }
        if (c == ',') { tk_kind[ntk] = K_COMMA; tk_s[ntk] = ","; ntk++; i++; continue; }
        if (c == '!' || c == ';') { tk_kind[ntk] = K_ATOM; tk_s[ntk] = sub(i, i + 1); ntk++; i++; continue; }
        if (c == '\'') { i++; int a = i; while (i < slen && src[i] != '\'') i++; tk_kind[ntk] = K_ATOM; tk_s[ntk] = sub(a, i); ntk++; i++; continue; }
        if (c == '"') { i++; int a = i; while (i < slen && src[i] != '"') i++; tk_kind[ntk] = K_ATOM; tk_s[ntk] = sub(a, i); ntk++; i++; continue; }
        if (c >= '0' && c <= '9') { int a = i; while (i < slen && src[i] >= '0' && src[i] <= '9') i++; if (i + 1 < slen && src[i] == '.' && src[i + 1] >= '0' && src[i + 1] <= '9') { i++; while (i < slen && src[i] >= '0' && src[i] <= '9') i++; } tk_kind[ntk] = K_NUM; tk_n[ntk] = atof((int)sub(a, i)); ntk++; continue; }
        if ((c >= 'A' && c <= 'Z') || c == '_') { int a = i; while (i < slen && ((src[i] >= 'A' && src[i] <= 'Z') || (src[i] >= 'a' && src[i] <= 'z') || (src[i] >= '0' && src[i] <= '9') || src[i] == '_')) i++; tk_kind[ntk] = K_VAR; tk_s[ntk] = sub(a, i); ntk++; continue; }
        if (c >= 'a' && c <= 'z') { int a = i; while (i < slen && ((src[i] >= 'A' && src[i] <= 'Z') || (src[i] >= 'a' && src[i] <= 'z') || (src[i] >= '0' && src[i] <= '9') || src[i] == '_')) i++; tk_kind[ntk] = K_ATOM; tk_s[ntk] = sub(a, i); ntk++; continue; }
        if (issym(c)) { int a = i; while (i < slen && issym(src[i])) i++; tk_kind[ntk] = K_ATOM; tk_s[ntk] = sub(a, i); ntk++; continue; }
        i++;   /* skip anything else */
    }
}

/* operator tables */
#define XFX 0
#define XFY 1
#define YFX 2
int infix_prec(char *f)
{
    if (strcmp(f, ":-") == 0) return 1200;
    if (strcmp(f, ";") == 0) return 1100;
    if (strcmp(f, "->") == 0) return 1050;
    if (strcmp(f, ",") == 0) return 1000;
    if (strcmp(f, "=") == 0 || strcmp(f, "\\=") == 0 || strcmp(f, "==") == 0 || strcmp(f, "\\==") == 0 || strcmp(f, "is") == 0 ||
        strcmp(f, "<") == 0 || strcmp(f, ">") == 0 || strcmp(f, "=<") == 0 || strcmp(f, ">=") == 0 || strcmp(f, "=:=") == 0 ||
        strcmp(f, "=\\=") == 0 || strcmp(f, "@<") == 0 || strcmp(f, "@>") == 0) return 700;
    if (strcmp(f, "+") == 0 || strcmp(f, "-") == 0) return 500;
    if (strcmp(f, "*") == 0 || strcmp(f, "/") == 0 || strcmp(f, "mod") == 0 || strcmp(f, "//") == 0) return 400;
    return 0;
}
int infix_type(char *f)
{
    if (strcmp(f, ";") == 0 || strcmp(f, "->") == 0 || strcmp(f, ",") == 0) return XFY;
    if (strcmp(f, "+") == 0 || strcmp(f, "-") == 0 || strcmp(f, "*") == 0 || strcmp(f, "/") == 0 || strcmp(f, "mod") == 0 || strcmp(f, "//") == 0) return YFX;
    return XFX;
}
int is_infix(char *f) { return infix_prec(f) > 0 && strcmp(f, ",") != 0; }
int prefix_prec(char *f) { if (strcmp(f, ":-") == 0 || strcmp(f, "?-") == 0) return 1200; if (strcmp(f, "\\+") == 0) return 900; if (strcmp(f, "-") == 0) return 200; return 0; }

/* per-clause variable map */
char *vm_name[2000]; int vm_var[2000]; int nvm;
void reset_vars() { nvm = 0; }
int getvar(char *name)
{
    if (strcmp(name, "_") == 0) return mkvar("_");
    int i; for (i = 0; i < nvm; i++) if (strcmp(vm_name[i], name) == 0) return vm_var[i];
    int v = mkvar(name); vm_name[nvm] = (char *)strdup((int)name); vm_var[nvm] = v; nvm++; return v;
}

int parse_expr(int maxp);
int can_start(int k) { return k == K_NUM || k == K_VAR || k == K_LP || k == K_LB || k == K_ATOM; }
int parse_args(char *fn)
{
    int buf[64]; int n = 0;
    buf[n++] = parse_expr(999);
    while (tk_kind[g_ti] == K_COMMA) { g_ti++; buf[n++] = parse_expr(999); }
    int *p = (int *)malloc(n * 4); int i; for (i = 0; i < n; i++) p[i] = buf[i];
    return mkcmpv(fn, n, p);
}
int parse_list()
{
    g_ti++;   /* [ */
    if (tk_kind[g_ti] == K_RB) { g_ti++; return g_nil_; }
    int buf[256]; int n = 0;
    buf[n++] = parse_expr(999);
    while (tk_kind[g_ti] == K_COMMA) { g_ti++; buf[n++] = parse_expr(999); }
    int tail = g_nil_;
    if (tk_kind[g_ti] == K_BAR) { g_ti++; tail = parse_expr(999); }
    if (tk_kind[g_ti] == K_RB) g_ti++;
    int lst = tail; int i; for (i = n - 1; i >= 0; i--) lst = mkcmp2(".", buf[i], lst);
    return lst;
}
int parse_primary()
{
    int k = tk_kind[g_ti];
    if (k == K_NUM) { double d = tk_n[g_ti]; g_ti++; return mknum(d); }
    if (k == K_VAR) { char *s = tk_s[g_ti]; g_ti++; return getvar(s); }
    if (k == K_LP) { g_ti++; int t = parse_expr(1200); if (tk_kind[g_ti] == K_RP) g_ti++; return t; }
    if (k == K_LB) return parse_list();
    if (k == K_ATOM)
    {
        char *name = tk_s[g_ti]; g_ti++;
        if (tk_kind[g_ti] == K_LP) { g_ti++; int t = parse_args(name); if (tk_kind[g_ti] == K_RP) g_ti++; return t; }
        int pp = prefix_prec(name);
        if (pp > 0 && can_start(tk_kind[g_ti]))
        {
            int arg = parse_expr(pp - 1);
            if (strcmp(name, "-") == 0 && ttag(deref(arg)) == A_NUM) return mknum(-tnum(deref(arg)));
            return mkcmp1(name, arg);
        }
        return mkatom(name);
    }
    return g_nil_;   /* shouldn't happen */
}
int parse_expr(int maxp)
{
    int left = parse_primary();
    while (1)
    {
        int k = tk_kind[g_ti]; char *name = 0;
        if (k == K_COMMA) name = ",";
        else if (k == K_ATOM) name = tk_s[g_ti];
        else break;
        int p = infix_prec(name); if (p == 0 || p > maxp) break;
        int ty = infix_type(name); g_ti++;
        int rp = (ty == XFY) ? p : p - 1;
        int right = parse_expr(rp);
        left = mkcmp2(name, left, right);
    }
    return left;
}

/* ================= engine ================= */
struct GN { int goal; int bar; int next; };
int gn(int goal, int bar, int next) { struct GN *n = (struct GN *)malloc(12); n->goal = goal; n->bar = bar; n->next = next; return (int)n; }

int g_cut, g_barctr, g_nsol, g_stop, g_once, g_onceFound, g_limit;
int g_qvar[200]; char *g_qname[200]; int g_qn;

void solve(int goals);
int prove_once(int goal)
{
    int sm = trail_mark(); int so = g_once, sf = g_onceFound, ss = g_stop, sc = g_cut;
    g_once = 1; g_onceFound = 0; g_stop = 0;
    solve(gn(goal, ++g_barctr, 0));
    int r = g_onceFound;
    g_once = so; g_onceFound = sf; g_stop = ss; g_cut = sc;
    undo(sm); return r;
}
void report()
{
    if (g_once) { g_onceFound = 1; g_stop = 1; return; }
    if (g_qn == 0) printf((int)"%s", (int)"true");
    else { int i; for (i = 0; i < g_qn; i++) { if (i) printf((int)"%s", (int)", "); printf((int)"%s = ", (int)g_qname[i]); writet(g_qvar[i]); } }
    printf((int)"%s", (int)"\n");
    g_nsol++; if (g_nsol >= g_limit) g_stop = 1;
}

void solve(int goals)
{
    if (g_stop) return;
    if (goals == 0) { report(); return; }
    struct GN *node = (struct GN *)goals;
    int g = deref(node->goal); int bar = node->bar; int rest = node->next;
    int tg = ttag(g);
    if (tg == A_ATOM)
    {
        char *f = tfn(g);
        if (strcmp(f, "true") == 0) { solve(rest); return; }
        if (strcmp(f, "fail") == 0 || strcmp(f, "false") == 0) return;
        if (strcmp(f, "!") == 0) { solve(rest); if (g_cut == 0) g_cut = bar; return; }
        if (strcmp(f, "nl") == 0) { printf((int)"%s", (int)"\n"); solve(rest); return; }
        /* 0-arity user predicate falls through */
    }
    if (tg == A_CMP)
    {
        char *f = tfn(g); int n = tar(g);
        if (n == 2 && strcmp(f, ",") == 0) { solve(gn(targ(g, 0), bar, gn(targ(g, 1), bar, rest))); return; }
        if (n == 2 && strcmp(f, ";") == 0)
        {
            int l = deref(targ(g, 0));
            if (ttag(l) == A_CMP && strcmp(tfn(l), "->") == 0 && tar(l) == 2)   /* (C -> T ; E) */
            {
                if (prove_once(targ(l, 0))) solve(gn(targ(l, 1), bar, rest));
                else solve(gn(targ(g, 1), bar, rest));
                return;
            }
            solve(gn(targ(g, 0), bar, rest));
            if (g_cut != 0 && g_cut <= bar) return;
            solve(gn(targ(g, 1), bar, rest)); return;
        }
        if (n == 2 && strcmp(f, "->") == 0) { if (prove_once(targ(g, 0))) solve(gn(targ(g, 1), bar, rest)); return; }
        if (n == 2 && strcmp(f, "=") == 0) { int m = trail_mark(); if (unify(targ(g, 0), targ(g, 1))) solve(rest); undo(m); return; }
        if (n == 2 && strcmp(f, "\\=") == 0) { int m = trail_mark(); int u = unify(targ(g, 0), targ(g, 1)); undo(m); if (!u) solve(rest); return; }
        if (n == 2 && strcmp(f, "==") == 0) { if (deref(targ(g, 0)) == deref(targ(g, 1))) solve(rest); return; }
        if (n == 2 && strcmp(f, "is") == 0) { int m = trail_mark(); if (unify(targ(g, 0), mknum(evala(targ(g, 1))))) solve(rest); undo(m); return; }
        if (n == 2 && (strcmp(f, "<") == 0 || strcmp(f, ">") == 0 || strcmp(f, "=<") == 0 || strcmp(f, ">=") == 0 || strcmp(f, "=:=") == 0 || strcmp(f, "=\\=") == 0))
        {
            double a = evala(targ(g, 0)), b = evala(targ(g, 1)); int ok = 0;
            if (strcmp(f, "<") == 0) ok = a < b; else if (strcmp(f, ">") == 0) ok = a > b;
            else if (strcmp(f, "=<") == 0) ok = a <= b; else if (strcmp(f, ">=") == 0) ok = a >= b;
            else if (strcmp(f, "=:=") == 0) ok = a == b; else ok = a != b;
            if (ok) solve(rest); return;
        }
        if (n == 1 && strcmp(f, "write") == 0) { writet(targ(g, 0)); solve(rest); return; }
        if (n == 1 && strcmp(f, "writeln") == 0) { writet(targ(g, 0)); printf((int)"%s", (int)"\n"); solve(rest); return; }
        if (n == 1 && (strcmp(f, "\\+") == 0 || strcmp(f, "not") == 0)) { if (!prove_once(targ(g, 0))) solve(rest); return; }
        if (n == 1 && strcmp(f, "call") == 0) { solve(gn(targ(g, 0), ++g_barctr, rest)); return; }
        /* else: user predicate */
    }
    /* resolve user predicate g against the database */
    int mybar = ++g_barctr;
    char *gf = (tg == A_ATOM || tg == A_CMP) ? tfn(g) : "";
    int gar = (tg == A_CMP) ? tar(g) : 0;
    int i;
    for (i = 0; i < ndb; i++)
    {
        int h = db_head[i];
        if (ttag(h) == A_ATOM && tg == A_ATOM) { if (h != g) continue; }
        else if (ttag(h) == A_CMP && tg == A_CMP) { if (strcmp(tfn(h), gf) != 0 || tar(h) != gar) continue; }
        else continue;
        int m = trail_mark(); rn_n = 0;
        int hh = copy_term(db_head[i]); int bb = copy_term(db_body[i]);
        if (unify(g, hh))
        {
            if (ttag(bb) == A_ATOM && strcmp(tfn(bb), "true") == 0) solve(rest);
            else solve(gn(bb, mybar, rest));
        }
        undo(m);
        if (g_stop) return;
        if (g_cut != 0 && g_cut <= mybar) { if (g_cut == mybar) g_cut = 0; return; }
    }
}

/* ================= driver ================= */
int read_clause()
{
    if (tk_kind[g_ti] == 0 && g_ti >= ntk) return -1;
    if (g_ti >= ntk) return -1;
    reset_vars();
    int t = parse_expr(1200);
    if (tk_kind[g_ti] == K_END) g_ti++;
    return t;
}
void run_query(int goal)
{
    g_qn = 0; int i; for (i = 0; i < nvm; i++) { char *nm = vm_name[i]; if (nm[0] != '_') { g_qvar[g_qn] = vm_var[i]; g_qname[g_qn] = nm; g_qn++; } }
    printf((int)"?- "); writet(goal); printf((int)"%s", (int)".\n");
    g_nsol = 0; g_stop = 0; g_once = 0; g_cut = 0; g_limit = 100;
    solve(gn(goal, ++g_barctr, 0));
    if (g_nsol == 0) printf((int)"%s", (int)"false.\n");
    printf((int)"%s", (int)"\n");
}
void process(int c)
{
    if (ttag(c) == A_CMP && tar(c) == 1 && (strcmp(tfn(c), ":-") == 0 || strcmp(tfn(c), "?-") == 0)) { run_query(targ(c, 0)); return; }
    if (ttag(c) == A_CMP && tar(c) == 2 && strcmp(tfn(c), ":-") == 0) { assertz(targ(c, 0), targ(c, 1)); return; }
    assertz(c, g_true_);
}
void load(char *text) { src = text; slen = strlen(text); tokenize(); g_ti = 0; while (g_ti < ntk) { int c = read_clause(); if (c == -1) break; process(c); } }

char *PRELUDE =
"append([], L, L).\n"
"append([H|T], L, [H|R]) :- append(T, L, R).\n"
"member(X, [X|_]).\n"
"member(X, [_|T]) :- member(X, T).\n"
"length([], 0).\n"
"length([_|T], N) :- length(T, N0), N is N0 + 1.\n"
"rev([], A, A).\n"
"rev([H|T], A, R) :- rev(T, [H|A], R).\n"
"reverse(L, R) :- rev(L, [], R).\n"
"last([X], X).\n"
"last([_|T], X) :- last(T, X).\n"
"between(L, H, L) :- L =< H.\n"
"between(L, H, X) :- L < H, L1 is L + 1, between(L1, H, X).\n" ;

int main(int argc, char **argv)
{
    g_nil_ = mkatom("[]"); g_true_ = mkatom("true");
    load(PRELUDE);
    char *infile = 0; int i; for (i = 1; i < argc; i++) if (((char *)argv[i])[0] != '-') infile = (char *)argv[i];
    if (infile == 0) { printf((int)"usage: prolog <file.pl>\n"); return 1; }
    char *t = (char *)rt_slurp((int)infile);
    if (t == 0) { printf((int)"prolog: cannot read %s\n", (int)infile); return 1; }
    load(t);
    return 0;
}
