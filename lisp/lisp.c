/* Lisp interpreter (written in our C -> IL via cc). A proper little Lisp: cons
 * cells, interned symbols, numbers, strings, lambda CLOSURES, recursion, lexical
 * scope, quote/if/cond/let/define/and/or/set!, ~30 primitives, a small Lisp
 * prelude. Powerful enough to run a metacircular evaluator (Lisp written in Lisp).
 *
 *   lisp prog.lisp      run a file        lisp      interactive REPL (stdin)
 */

/* ---- value model: tagged objects, referenced by int handle ---- */
#define TNIL 0
#define TNUM 1
#define TSYM 2
#define TSTR 3
#define TCONS 4
#define TPRIM 5
#define TCLOS 6
struct Obj { int tag; int car; int cdr; int env; double num; char *str; };
int tag(int x) { return ((struct Obj *)x)->tag; }
int car(int x) { struct Obj *o = (struct Obj *)x; return o->tag == TCONS ? o->car : g_nil(); }
int cdr(int x) { struct Obj *o = (struct Obj *)x; return o->tag == TCONS ? o->cdr : g_nil(); }
double onum(int x) { return ((struct Obj *)x)->num; }
char *ostr(int x) { return ((struct Obj *)x)->str; }

int g_nilv, g_tv;
int g_nil() { return g_nilv; }

int newobj(int t) { struct Obj *o = (struct Obj *)malloc(48); o->tag = t; o->car = g_nilv; o->cdr = g_nilv; o->env = g_nilv; o->num = 0; o->str = ""; return (int)o; }
int mknum(double d) { int o = newobj(TNUM); ((struct Obj *)o)->num = d; return o; }
int mkstr(char *s) { int o = newobj(TSTR); ((struct Obj *)o)->str = s; return o; }
int mkcons(int a, int d) { int o = newobj(TCONS); ((struct Obj *)o)->car = a; ((struct Obj *)o)->cdr = d; return o; }
void setcdr(int p, int v) { ((struct Obj *)p)->cdr = v; }

int cadr(int x) { return car(cdr(x)); }
int caddr(int x) { return car(cdr(cdr(x))); }
int cdddr(int x) { return cdr(cdr(cdr(x))); }
int cddr(int x) { return cdr(cdr(x)); }

/* ---- symbol interning (so eq? on symbols is handle identity) ---- */
char *sy_name[4000]; int sy_obj[4000]; int nsy;
int intern(char *name)
{
    int i; for (i = 0; i < nsy; i++) if (strcmp(sy_name[i], name) == 0) return sy_obj[i];
    int o = newobj(TSYM); ((struct Obj *)o)->str = (char *)strdup((int)name);
    sy_name[nsy] = ((struct Obj *)o)->str; sy_obj[nsy] = o; nsy++; return o;
}

int truthy(int x) { return x != g_nilv; }   /* only nil is false */

int g_quote, g_if, g_cond, g_lambda, g_define, g_let, g_begin, g_and, g_or, g_set, g_else, g_env;

/* ---- reader ---- */
char *g_src; int g_pos, g_len;
void skipws()
{
    while (g_pos < g_len)
    {
        char c = g_src[g_pos];
        if (c == ';') { while (g_pos < g_len && g_src[g_pos] != '\n') g_pos++; }
        else if (c == ' ' || c == '\t' || c == '\r' || c == '\n') g_pos++;
        else break;
    }
}
char *slice(int a, int b) { char *r = (char *)malloc(b - a + 1); int i = 0; while (a < b) r[i++] = g_src[a++]; r[i] = 0; return r; }
int read_expr();
int read_list()
{
    skipws();
    if (g_pos >= g_len || g_src[g_pos] == ')') { if (g_pos < g_len) g_pos++; return g_nilv; }
    int head = read_expr();
    int tail = read_list();
    return mkcons(head, tail);
}
int read_string()
{
    g_pos++; int a = g_pos; while (g_pos < g_len && g_src[g_pos] != '"') g_pos++;
    char *s = slice(a, g_pos); if (g_pos < g_len) g_pos++; return mkstr(s);
}
int read_atom()
{
    int a = g_pos;
    while (g_pos < g_len) { char c = g_src[g_pos]; if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '(' || c == ')' || c == ';' || c == '"') break; g_pos++; }
    char *tok = slice(a, g_pos);
    char c0 = tok[0];
    int isnum = (c0 >= '0' && c0 <= '9') || ((c0 == '-' || c0 == '+' || c0 == '.') && tok[1] >= '0' && tok[1] <= '9');
    if (isnum) return mknum(atof((int)tok));
    return intern(tok);
}
int read_expr()
{
    skipws();
    if (g_pos >= g_len) return -1;            /* EOF */
    char c = g_src[g_pos];
    if (c == '(') { g_pos++; return read_list(); }
    if (c == ')') { g_pos++; return g_nilv; }
    if (c == '\'') { g_pos++; return mkcons(g_quote, mkcons(read_expr(), g_nilv)); }
    if (c == '"') return read_string();
    return read_atom();
}

/* ---- environment: a cons (frame . parent); frame = list of (sym . val) ---- */
void env_define(int env, int sym, int val) { ((struct Obj *)env)->car = mkcons(mkcons(sym, val), car(env)); }
int env_lookup(int sym, int env)
{
    int e = env;
    while (e != g_nilv) { int p = car(e); while (p != g_nilv) { int b = car(p); if (car(b) == sym) return cdr(b); p = cdr(p); } e = cdr(e); }
    printf((int)"lisp: unbound symbol %s\n", (int)ostr(sym)); return g_nilv;
}
void env_set(int sym, int val, int env)
{
    int e = env;
    while (e != g_nilv) { int p = car(e); while (p != g_nilv) { int b = car(p); if (car(b) == sym) { setcdr(b, val); return; } p = cdr(p); } e = cdr(e); }
    env_define(g_env, sym, val);
}
int env_extend(int parent, int params, int args)
{
    int frame = g_nilv;
    while (tag(params) == TCONS) { frame = mkcons(mkcons(car(params), car(args)), frame); params = cdr(params); args = cdr(args); }
    return mkcons(frame, parent);
}

int eval(int x, int env);

/* eval each form in a body list; return the last value */
int eval_body(int body, int env) { int r = g_nilv; while (tag(body) == TCONS) { r = eval(car(body), env); body = cdr(body); } return r; }
int evlist(int l, int env) { if (tag(l) != TCONS) return g_nilv; return mkcons(eval(car(l), env), evlist(cdr(l), env)); }

int eqp(int a, int b)
{
    if (a == b) return 1;
    if (tag(a) == TNUM && tag(b) == TNUM) return onum(a) == onum(b);
    if (tag(a) == TSTR && tag(b) == TSTR) return strcmp(ostr(a), ostr(b)) == 0;
    return 0;
}

/* ---- printer ---- */
char *numstr(double d) { char b[64]; if (d == (double)(int)d) sprintf((int)b, (int)"%d", (int)d); else sprintf((int)b, (int)"%g", d); return (char *)strdup((int)b); }
void writex(int x)
{
    int t = tag(x);
    if (x == g_nilv) { printf((int)"%s", (int)"()"); return; }
    if (t == TNUM) { printf((int)"%s", (int)numstr(onum(x))); return; }
    if (t == TSYM) { printf((int)"%s", (int)ostr(x)); return; }
    if (t == TSTR) { printf((int)"%s", (int)ostr(x)); return; }
    if (t == TPRIM) { printf((int)"%s", (int)"#<prim>"); return; }
    if (t == TCLOS) { printf((int)"%s", (int)"#<closure>"); return; }
    if (t == TCONS)
    {
        printf((int)"%s", (int)"("); int p = x; int first = 1;
        while (tag(p) == TCONS) { if (!first) printf((int)"%s", (int)" "); writex(car(p)); first = 0; p = cdr(p); }
        if (p != g_nilv) { printf((int)"%s", (int)" . "); writex(p); }
        printf((int)"%s", (int)")");
    }
}

/* ---- primitives ---- */
#define P_CAR 1
#define P_CDR 2
#define P_CONS 3
#define P_NULL 4
#define P_PAIR 5
#define P_ATOM 6
#define P_EQ 7
#define P_SYMBOLP 8
#define P_NUMBERP 9
#define P_ADD 10
#define P_SUB 11
#define P_MUL 12
#define P_DIV 13
#define P_NUMEQ 14
#define P_LT 15
#define P_GT 16
#define P_LE 17
#define P_GE 18
#define P_LIST 19
#define P_PRINT 20
#define P_DISPLAY 21
#define P_NEWLINE 22
#define P_APPLY 23
#define P_EVAL 24
#define P_NOT 25
#define P_SETCAR 26
#define P_SETCDR 27
#define P_MOD 28

int apply(int fn, int args);
int do_prim(int id, int args)
{
    int a0 = car(args), a1 = car(cdr(args));
    if (id == P_CAR) return car(a0);
    if (id == P_CDR) return cdr(a0);
    if (id == P_CONS) return mkcons(a0, a1);
    if (id == P_NULL) return a0 == g_nilv ? g_tv : g_nilv;
    if (id == P_PAIR) return tag(a0) == TCONS ? g_tv : g_nilv;
    if (id == P_ATOM) return tag(a0) == TCONS ? g_nilv : g_tv;
    if (id == P_EQ) return eqp(a0, a1) ? g_tv : g_nilv;
    if (id == P_SYMBOLP) return tag(a0) == TSYM ? g_tv : g_nilv;
    if (id == P_NUMBERP) return tag(a0) == TNUM ? g_tv : g_nilv;
    if (id == P_NOT) return truthy(a0) ? g_nilv : g_tv;
    if (id == P_SETCAR) { ((struct Obj *)a0)->car = a1; return a1; }
    if (id == P_SETCDR) { setcdr(a0, a1); return a1; }
    if (id == P_LIST) return args;
    if (id == P_MOD) return mknum((int)onum(a0) % (int)onum(a1));
    if (id == P_ADD) { double s = 0; int p = args; while (tag(p) == TCONS) { s += onum(car(p)); p = cdr(p); } return mknum(s); }
    if (id == P_MUL) { double s = 1; int p = args; while (tag(p) == TCONS) { s *= onum(car(p)); p = cdr(p); } return mknum(s); }
    if (id == P_SUB) { if (cdr(args) == g_nilv) return mknum(-onum(a0)); double s = onum(a0); int p = cdr(args); while (tag(p) == TCONS) { s -= onum(car(p)); p = cdr(p); } return mknum(s); }
    if (id == P_DIV) { double s = onum(a0); int p = cdr(args); while (tag(p) == TCONS) { s /= onum(car(p)); p = cdr(p); } return mknum(s); }
    if (id == P_NUMEQ) return onum(a0) == onum(a1) ? g_tv : g_nilv;
    if (id == P_LT) return onum(a0) < onum(a1) ? g_tv : g_nilv;
    if (id == P_GT) return onum(a0) > onum(a1) ? g_tv : g_nilv;
    if (id == P_LE) return onum(a0) <= onum(a1) ? g_tv : g_nilv;
    if (id == P_GE) return onum(a0) >= onum(a1) ? g_tv : g_nilv;
    if (id == P_PRINT) { writex(a0); printf((int)"%s", (int)"\n"); return a0; }
    if (id == P_DISPLAY) { writex(a0); return a0; }
    if (id == P_NEWLINE) { printf((int)"%s", (int)"\n"); return g_nilv; }
    if (id == P_APPLY) return apply(a0, a1);
    if (id == P_EVAL) return eval(a0, g_env);
    return g_nilv;
}

int apply(int fn, int args)
{
    if (tag(fn) == TPRIM) return do_prim(((struct Obj *)fn)->car, args);
    if (tag(fn) == TCLOS) { int ne = env_extend(((struct Obj *)fn)->env, ((struct Obj *)fn)->car, args); return eval_body(((struct Obj *)fn)->cdr, ne); }
    printf((int)"lisp: not applicable\n"); return g_nilv;
}

int mkclos(int params, int body, int env) { int o = newobj(TCLOS); ((struct Obj *)o)->car = params; ((struct Obj *)o)->cdr = body; ((struct Obj *)o)->env = env; return o; }

int eval(int x, int env)
{
    int t = tag(x);
    if (t == TNUM || t == TSTR || t == TNIL || t == TPRIM || t == TCLOS) return x;
    if (t == TSYM) { if (x == g_tv) return g_tv; return env_lookup(x, env); }
    /* cons -> special form or application */
    int op = car(x);
    if (op == g_quote) return cadr(x);
    if (op == g_if) { if (truthy(eval(cadr(x), env))) return eval(caddr(x), env); return eval(car(cdddr(x)), env); }
    if (op == g_lambda) return mkclos(cadr(x), cddr(x), env);
    if (op == g_begin) return eval_body(cdr(x), env);
    if (op == g_define)
    {
        int target = cadr(x);
        if (tag(target) == TCONS) { int name = car(target); int clos = mkclos(cdr(target), cddr(x), env); env_define(env, name, clos); return name; }
        int val = eval(caddr(x), env); env_define(env, target, val); return target;
    }
    if (op == g_set) { int val = eval(caddr(x), env); env_set(cadr(x), val, env); return val; }
    if (op == g_let)
    {
        int binds = cadr(x); int frame = g_nilv; int p = binds;
        while (tag(p) == TCONS) { int b = car(p); frame = mkcons(mkcons(car(b), eval(cadr(b), env)), frame); p = cdr(p); }
        return eval_body(cddr(x), mkcons(frame, env));
    }
    if (op == g_cond)
    {
        int p = cdr(x);
        while (tag(p) == TCONS)
        {
            int clause = car(p); int test = car(clause);
            if (test == g_else || truthy(eval(test, env))) { if (cdr(clause) == g_nilv) return eval(test, env); return eval_body(cdr(clause), env); }
            p = cdr(p);
        }
        return g_nilv;
    }
    if (op == g_and) { int p = cdr(x); int r = g_tv; while (tag(p) == TCONS) { r = eval(car(p), env); if (!truthy(r)) return g_nilv; p = cdr(p); } return r; }
    if (op == g_or) { int p = cdr(x); while (tag(p) == TCONS) { int r = eval(car(p), env); if (truthy(r)) return r; p = cdr(p); } return g_nilv; }
    /* application */
    int fn = eval(op, env);
    int args = evlist(cdr(x), env);
    return apply(fn, args);
}

void defprim(char *name, int id) { int o = newobj(TPRIM); ((struct Obj *)o)->car = id; env_define(g_env, intern(name), o); }

char *PRELUDE =
"(define (caar x) (car (car x)))"
"(define (cadr x) (car (cdr x)))"
"(define (caddr x) (car (cdr (cdr x))))"
"(define (cadddr x) (car (cdr (cdr (cdr x)))))"
"(define (cdar x) (cdr (car x)))"
"(define (cddr x) (cdr (cdr x)))"
"(define (map f l) (if (null? l) (quote ()) (cons (f (car l)) (map f (cdr l)))))"
"(define (for-each f l) (if (null? l) (quote ()) (begin (f (car l)) (for-each f (cdr l)))))"
"(define (append a b) (if (null? a) b (cons (car a) (append (cdr a) b))))"
"(define (length l) (if (null? l) 0 (+ 1 (length (cdr l)))))"
"(define (reverse l) (if (null? l) (quote ()) (append (reverse (cdr l)) (list (car l)))))"
"(define (assoc k l) (cond ((null? l) (quote ())) ((eq? (caar l) k) (car l)) (else (assoc k (cdr l)))))"
"(define (equal? a b) (cond ((and (pair? a) (pair? b)) (and (equal? (car a) (car b)) (equal? (cdr a) (cdr b)))) (else (eq? a b))))"
"(define (member x l) (cond ((null? l) (quote ())) ((equal? (car l) x) l) (else (member x (cdr l)))))"
"(define (cadar x) (car (cdr (car x))))"
"(define (foldl f z l) (if (null? l) z (foldl f (f z (car l)) (cdr l))))"
"(define (filter p l) (cond ((null? l) (quote ())) ((p (car l)) (cons (car l) (filter p (cdr l)))) (else (filter p (cdr l)))))" ;

void eval_all(char *src)
{
    g_src = src; g_pos = 0; g_len = strlen(src);
    while (1) { int x = read_expr(); if (x == -1) break; eval(x, g_env); }
}

int main(int argc, char **argv)
{
    g_nilv = newobj(TNIL);
    g_tv = intern("t");
    g_env = mkcons(g_nilv, g_nilv);
    g_quote = intern("quote"); g_if = intern("if"); g_cond = intern("cond"); g_lambda = intern("lambda");
    g_define = intern("define"); g_let = intern("let"); g_begin = intern("begin"); g_and = intern("and");
    g_or = intern("or"); g_set = intern("set!"); g_else = intern("else");

    defprim("car", P_CAR); defprim("cdr", P_CDR); defprim("cons", P_CONS);
    defprim("null?", P_NULL); defprim("pair?", P_PAIR); defprim("atom?", P_ATOM);
    defprim("eq?", P_EQ); defprim("symbol?", P_SYMBOLP); defprim("number?", P_NUMBERP);
    defprim("not", P_NOT); defprim("set-car!", P_SETCAR); defprim("set-cdr!", P_SETCDR);
    defprim("+", P_ADD); defprim("-", P_SUB); defprim("*", P_MUL); defprim("/", P_DIV); defprim("modulo", P_MOD);
    defprim("=", P_NUMEQ); defprim("<", P_LT); defprim(">", P_GT); defprim("<=", P_LE); defprim(">=", P_GE);
    defprim("list", P_LIST); defprim("print", P_PRINT); defprim("display", P_DISPLAY); defprim("newline", P_NEWLINE);
    defprim("apply", P_APPLY); defprim("eval", P_EVAL);
    eval_all(PRELUDE);

    char *infile = 0; int i;
    for (i = 1; i < argc; i++) if (((char *)argv[i])[0] != '-') infile = (char *)argv[i];

    if (infile)
    {
        char *src = (char *)rt_slurp((int)infile);
        if (src == 0) { printf((int)"lisp: cannot read %s\n", (int)infile); return 1; }
        eval_all(src);
        return 0;
    }

    /* REPL */
    printf((int)"%s", (int)"lisp> ");
    char buf[8192]; int bp = 0; int ch;
    while ((ch = getchar()) != -1)
    {
        if (ch == '\n')
        {
            buf[bp] = 0;
            if (bp > 0) { g_src = buf; g_pos = 0; g_len = bp; int x = read_expr(); if (x != -1) { int r = eval(x, g_env); writex(r); printf((int)"%s", (int)"\n"); } }
            bp = 0; printf((int)"%s", (int)"lisp> ");
        }
        else if (ch != '\r' && bp < 8191) buf[bp++] = ch;
    }
    return 0;
}
