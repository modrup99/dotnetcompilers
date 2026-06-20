/* Logo interpreter (written in our C -> IL via cc). Arity-directed reader + tree
 * walker (Logo can't be parsed by yacc — you must know each word's arity to know
 * where its arguments end). Turtle graphics render into a CRuntime canvas that can
 * export SVG / PNG / animated GIF, or blit live to the gfx window.
 *
 *   logo prog.logo -png out.png      logo prog.logo -svg out.svg
 *   logo prog.logo -gif out.gif      logo            (interactive REPL)
 */

/* ---- tokens ---- */
#define TNUM 1
#define TWORD 2
#define TQWORD 3
#define TVAR 4
#define TLB 5
#define TRB 6
#define TLP 7
#define TRP 8
#define TOP 9

int tk_kind[40000]; char *tk_s[40000]; double tk_n[40000]; int ntok;
int tp;                      /* current token */

/* ---- values (tagged, by int handle) ---- */
#define VNUM 0
#define VWORD 1
#define VLIST 2
struct V { int kind; double n; char *s; int la; int lb; };
int mkvn(double d) { struct V *v = (struct V *)malloc(48); v->kind = VNUM; v->n = d; v->s = ""; return (int)v; }
int mkvw(char *s) { struct V *v = (struct V *)malloc(48); v->kind = VWORD; v->s = s; v->n = 0; return (int)v; }
int mkvl(int a, int b) { struct V *v = (struct V *)malloc(48); v->kind = VLIST; v->la = a; v->lb = b; v->s = ""; return (int)v; }
int vkind(int h) { return ((struct V *)h)->kind; }
double vnum(int h) { struct V *v = (struct V *)h; if (v->kind == VNUM) return v->n; if (v->kind == VWORD) return atof((int)v->s); return 0; }
char *numstr(double d) { char b[64]; if (d == (double)(int)d) sprintf((int)b, (int)"%d", (int)d); else sprintf((int)b, (int)"%g", d); return (char *)strdup((int)b); }
char *vstr(int h) { struct V *v = (struct V *)h; if (v->kind == VWORD) return v->s; if (v->kind == VNUM) return numstr(v->n); return ""; }

/* ---- variables: globals + a locals stack for procedure params ---- */
char *gv_name[2000]; int gv_val[2000]; int ngv;
char *lv_name[4000]; int lv_val[4000]; int lvn;
int lc(char c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }
int ieq(char *a, char *b) { int i = 0; while (a[i] && b[i]) { if (lc(a[i]) != lc(b[i])) return 0; i++; } return a[i] == 0 && b[i] == 0; }
int getvar(char *name)
{
    int i; for (i = lvn - 1; i >= 0; i--) if (ieq(lv_name[i], name)) return lv_val[i];
    for (i = 0; i < ngv; i++) if (ieq(gv_name[i], name)) return gv_val[i];
    return mkvn(0);
}
void setvar(char *name, int val)
{
    int i; for (i = lvn - 1; i >= 0; i--) if (ieq(lv_name[i], name)) { lv_val[i] = val; return; }
    for (i = 0; i < ngv; i++) if (ieq(gv_name[i], name)) { gv_val[i] = val; return; }
    gv_name[ngv] = (char *)strdup((int)name); gv_val[ngv] = val; ngv++;
}

/* ---- user procedures ---- */
char *pr_name[1000]; int pr_np[1000]; char *pr_param[1000][16]; int pr_body[1000]; int pr_end[1000]; int npr;
int proc_find(char *name) { int i; for (i = 0; i < npr; i++) if (ieq(pr_name[i], name)) return i; return -1; }

/* ---- turtle state ---- */
double tx, ty, theading; int tpen, tcolor, tsize; int g_w, g_h;
int g_pal[16];
int g_gif, g_live; int g_frames;

double PI;
void present_maybe() { if (g_live) tc_present(); }
void frame_maybe() { if (g_gif && g_frames < 400) { tc_frame(4); g_frames++; } }

void t_fd(double d)
{
    double rad = theading * PI / 180.0;
    double nx = tx + d * sin(rad), ny = ty - d * cos(rad);
    if (tpen) tc_line((int)tx, (int)ty, (int)nx, (int)ny, tcolor, tsize);
    tx = nx; ty = ny; frame_maybe(); present_maybe();
}
void t_home() { tx = g_w / 2; ty = g_h / 2; theading = 0; }
void t_setxy(double x, double y)
{
    double nx = g_w / 2 + x, ny = g_h / 2 - y;
    if (tpen) tc_line((int)tx, (int)ty, (int)nx, (int)ny, tcolor, tsize);
    tx = nx; ty = ny; frame_maybe(); present_maybe();
}

int g_stop, g_ret;          /* STOP / OUTPUT control */

int eval_expr();
void run_range(int a, int b);

/* arity of a builtin word (user procs handled separately); -1 = unknown */
int arity(char *w)
{
    if (ieq(w, "fd") || ieq(w, "forward") || ieq(w, "bk") || ieq(w, "back")) return 1;
    if (ieq(w, "rt") || ieq(w, "right") || ieq(w, "lt") || ieq(w, "left")) return 1;
    if (ieq(w, "seth") || ieq(w, "setheading") || ieq(w, "setpc") || ieq(w, "setpencolor") || ieq(w, "setpensize")) return 1;
    if (ieq(w, "pu") || ieq(w, "penup") || ieq(w, "pd") || ieq(w, "pendown") || ieq(w, "home") || ieq(w, "cs") || ieq(w, "clearscreen")) return 0;
    if (ieq(w, "setxy")) return 2;
    if (ieq(w, "print") || ieq(w, "pr") || ieq(w, "show")) return 1;
    if (ieq(w, "repeat") || ieq(w, "if")) return 2;
    if (ieq(w, "ifelse")) return 3;
    if (ieq(w, "make")) return 2;
    if (ieq(w, "output") || ieq(w, "op")) return 1;
    if (ieq(w, "stop")) return 0;
    if (ieq(w, "sum") || ieq(w, "difference") || ieq(w, "product") || ieq(w, "quotient") || ieq(w, "remainder") || ieq(w, "power")) return 2;
    if (ieq(w, "random") || ieq(w, "sqrt") || ieq(w, "sin") || ieq(w, "cos") || ieq(w, "int") || ieq(w, "abs") || ieq(w, "minus")) return 1;
    return -1;
}

/* find matching ']' for the '[' at position lb (returns index of ']') */
int match_rb(int lb) { int d = 0, i = lb; while (i < ntok) { if (tk_kind[i] == TLB) d++; else if (tk_kind[i] == TRB) { d--; if (d == 0) return i; } i++; } return ntok; }

/* apply a command/operation word `w` (its args follow at tp); returns a value */
int apply(char *w)
{
    /* ---- special forms ---- */
    if (ieq(w, "repeat")) { int c = (int)vnum(eval_expr()); int lst = eval_expr(); int k; for (k = 0; k < c && !g_stop; k++) { setvar("repcount", mkvn(k + 1)); run_range(((struct V *)lst)->la, ((struct V *)lst)->lb); } return mkvn(0); }
    if (ieq(w, "if")) { int cnd = (int)vnum(eval_expr()); int lst = eval_expr(); if (cnd) run_range(((struct V *)lst)->la, ((struct V *)lst)->lb); return mkvn(0); }
    if (ieq(w, "ifelse")) { int cnd = (int)vnum(eval_expr()); int t = eval_expr(); int f = eval_expr(); if (cnd) run_range(((struct V *)t)->la, ((struct V *)t)->lb); else run_range(((struct V *)f)->la, ((struct V *)f)->lb); return mkvn(0); }
    if (ieq(w, "make")) { int nm = eval_expr(); int vv = eval_expr(); setvar(vstr(nm), vv); return mkvn(0); }
    if (ieq(w, "output") || ieq(w, "op")) { g_ret = eval_expr(); g_stop = 1; return g_ret; }
    if (ieq(w, "stop")) { g_stop = 1; return mkvn(0); }

    /* ---- turtle / commands ---- */
    if (ieq(w, "fd") || ieq(w, "forward")) { t_fd(vnum(eval_expr())); return mkvn(0); }
    if (ieq(w, "bk") || ieq(w, "back")) { t_fd(-vnum(eval_expr())); return mkvn(0); }
    if (ieq(w, "rt") || ieq(w, "right")) { theading = theading + vnum(eval_expr()); return mkvn(0); }
    if (ieq(w, "lt") || ieq(w, "left")) { theading = theading - vnum(eval_expr()); return mkvn(0); }
    if (ieq(w, "seth") || ieq(w, "setheading")) { theading = vnum(eval_expr()); return mkvn(0); }
    if (ieq(w, "setxy")) { double x = vnum(eval_expr()); double y = vnum(eval_expr()); t_setxy(x, y); return mkvn(0); }
    if (ieq(w, "pu") || ieq(w, "penup")) { tpen = 0; return mkvn(0); }
    if (ieq(w, "pd") || ieq(w, "pendown")) { tpen = 1; return mkvn(0); }
    if (ieq(w, "setpc") || ieq(w, "setpencolor")) { tcolor = g_pal[((int)vnum(eval_expr())) & 15]; return mkvn(0); }
    if (ieq(w, "setpensize")) { tsize = (int)vnum(eval_expr()); if (tsize < 1) tsize = 1; return mkvn(0); }
    if (ieq(w, "home")) { t_home(); return mkvn(0); }
    if (ieq(w, "cs") || ieq(w, "clearscreen")) { tc_clear(0xFFFFFF); t_home(); present_maybe(); return mkvn(0); }
    if (ieq(w, "print") || ieq(w, "pr") || ieq(w, "show"))
    {
        int v = eval_expr();
        if (vkind(v) == VLIST) { struct V *L = (struct V *)v; int i; for (i = L->la; i < L->lb; i++) { if (i > L->la) printf((int)" "); printf((int)"%s", (int)(tk_kind[i] == TNUM ? numstr(tk_n[i]) : tk_s[i])); } printf((int)"\n"); }
        else printf((int)"%s\n", (int)vstr(v));
        return mkvn(0);
    }

    /* ---- operations (return a value) ---- */
    if (ieq(w, "sum")) { double a = vnum(eval_expr()); double b = vnum(eval_expr()); return mkvn(a + b); }
    if (ieq(w, "difference")) { double a = vnum(eval_expr()); double b = vnum(eval_expr()); return mkvn(a - b); }
    if (ieq(w, "product")) { double a = vnum(eval_expr()); double b = vnum(eval_expr()); return mkvn(a * b); }
    if (ieq(w, "quotient")) { double a = vnum(eval_expr()); double b = vnum(eval_expr()); return mkvn(a / b); }
    if (ieq(w, "remainder")) { int a = (int)vnum(eval_expr()); int b = (int)vnum(eval_expr()); return mkvn(a % b); }
    if (ieq(w, "power")) { double a = vnum(eval_expr()); double b = vnum(eval_expr()); return mkvn(pow(a, b)); }
    if (ieq(w, "random")) { int n = (int)vnum(eval_expr()); if (n < 1) n = 1; return mkvn(rand() % n); }
    if (ieq(w, "sqrt")) { return mkvn(sqrt(vnum(eval_expr()))); }
    if (ieq(w, "sin")) { return mkvn(sin(vnum(eval_expr()) * PI / 180.0)); }
    if (ieq(w, "cos")) { return mkvn(cos(vnum(eval_expr()) * PI / 180.0)); }
    if (ieq(w, "int")) { return mkvn((int)vnum(eval_expr())); }
    if (ieq(w, "abs")) { double a = vnum(eval_expr()); return mkvn(a < 0 ? -a : a); }
    if (ieq(w, "minus")) { return mkvn(-vnum(eval_expr())); }

    /* ---- user procedure ---- */
    int pi = proc_find(w);
    if (pi >= 0)
    {
        int args[16]; int k; for (k = 0; k < pr_np[pi]; k++) args[k] = eval_expr();
        int base = lvn; for (k = 0; k < pr_np[pi]; k++) { lv_name[lvn] = pr_param[pi][k]; lv_val[lvn] = args[k]; lvn++; }
        int saveret = g_ret, savestop = g_stop; g_ret = mkvn(0); g_stop = 0;
        run_range(pr_body[pi], pr_end[pi]);
        int rv = g_ret; lvn = base; g_stop = savestop; g_ret = saveret;
        return rv;
    }
    printf((int)"logo: I don't know how to %s\n", (int)w);
    return mkvn(0);
}

/* expression parser with infix precedence; primaries include operation calls */
int eval_prim()
{
    int k = tk_kind[tp];
    if (k == TOP && tk_s[tp][0] == '-') { tp++; return mkvn(-vnum(eval_prim())); }
    if (k == TNUM) { double d = tk_n[tp]; tp++; return mkvn(d); }
    if (k == TQWORD) { char *s = tk_s[tp]; tp++; return mkvw(s); }
    if (k == TVAR) { char *s = tk_s[tp]; tp++; return getvar(s); }
    if (k == TLP) { tp++; int v = eval_expr(); if (tk_kind[tp] == TRP) tp++; return v; }
    if (k == TLB) { int rb = match_rb(tp); int v = mkvl(tp + 1, rb); tp = rb + 1; return v; }
    if (k == TWORD) { char *w = tk_s[tp]; tp++; return apply(w); }
    tp++; return mkvn(0);
}
int eval_mul() { int a = eval_prim(); while (tk_kind[tp] == TOP && (tk_s[tp][0] == '*' || tk_s[tp][0] == '/')) { char op = tk_s[tp][0]; tp++; double b = vnum(eval_prim()); a = mkvn(op == '*' ? vnum(a) * b : vnum(a) / b); } return a; }
int eval_add() { int a = eval_mul(); while (tk_kind[tp] == TOP && (tk_s[tp][0] == '+' || tk_s[tp][0] == '-')) { char op = tk_s[tp][0]; tp++; double b = vnum(eval_mul()); a = mkvn(op == '+' ? vnum(a) + b : vnum(a) - b); } return a; }
int eval_cmp()
{
    int a = eval_add();
    while (tk_kind[tp] == TOP && (tk_s[tp][0] == '<' || tk_s[tp][0] == '>' || tk_s[tp][0] == '=')) { char op = tk_s[tp][0]; tp++; double b = vnum(eval_add()); double x = vnum(a); a = mkvn(op == '<' ? (x < b) : op == '>' ? (x > b) : (x == b)); }
    return a;
}
int eval_expr() { return eval_cmp(); }

/* run commands over a token range [a,b) */
void run_range(int a, int b)
{
    int save = tp; tp = a;
    while (tp < b && !g_stop)
    {
        if (tk_kind[tp] == TRB) { tp++; continue; }
        if (tk_kind[tp] == TWORD && ieq(tk_s[tp], "to")) { int e = tp; while (e < ntok && !(tk_kind[e] == TWORD && ieq(tk_s[e], "end"))) e++; tp = e + 1; continue; }
        if (tk_kind[tp] == TWORD) { char *w = tk_s[tp]; tp++; apply(w); }
        else eval_expr();
    }
    tp = save;
}

/* ---- tokenizer ---- */
int isws(int c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
int isword(int c) { return !isws(c) && c != '[' && c != ']' && c != '(' && c != ')' && c != '+' && c != '-' && c != '*' && c != '/' && c != '<' && c != '>' && c != '=' && c != ';' && c != '"' && c != ':'; }
void push_tok(int kind, char *s, double n) { tk_kind[ntok] = kind; tk_s[ntok] = s; tk_n[ntok] = n; ntok++; }
char *slice(char *src, int a, int b) { char *r = (char *)malloc(b - a + 1); int i = 0; while (a < b) r[i++] = src[a++]; r[i] = 0; return r; }

void tokenize(char *src)
{
    int i = 0, n = strlen(src);
    while (i < n)
    {
        int c = src[i];
        if (isws(c)) { i++; continue; }
        if (c == ';') { while (i < n && src[i] != '\n') i++; continue; }
        if (c == '[') { push_tok(TLB, "[", 0); i++; continue; }
        if (c == ']') { push_tok(TRB, "]", 0); i++; continue; }
        if (c == '(') { push_tok(TLP, "(", 0); i++; continue; }
        if (c == ')') { push_tok(TRP, ")", 0); i++; continue; }
        if (c == '+' || c == '*' || c == '/' || c == '<' || c == '>' || c == '=') { char *s = (char *)malloc(2); s[0] = c; s[1] = 0; push_tok(TOP, s, 0); i++; continue; }
        if (c == '-') { char *s = (char *)malloc(2); s[0] = '-'; s[1] = 0; push_tok(TOP, s, 0); i++; continue; }
        if (c == '"') { i++; int a = i; while (i < n && isword(src[i])) i++; push_tok(TQWORD, slice(src, a, i), 0); continue; }
        if (c == ':') { i++; int a = i; while (i < n && isword(src[i])) i++; push_tok(TVAR, slice(src, a, i), 0); continue; }
        if ((c >= '0' && c <= '9') || (c == '.' && i + 1 < n && src[i + 1] >= '0' && src[i + 1] <= '9'))
        { int a = i; while (i < n && ((src[i] >= '0' && src[i] <= '9') || src[i] == '.')) i++; push_tok(TNUM, slice(src, a, i), atof((int)slice(src, a, i))); continue; }
        int a = i; while (i < n && isword(src[i])) i++; push_tok(TWORD, slice(src, a, i), 0);
    }
}

/* pre-pass: register every TO name :p ... END procedure (so calls resolve) */
void register_procs()
{
    int i = 0;
    while (i < ntok)
    {
        if (tk_kind[i] == TWORD && ieq(tk_s[i], "to"))
        {
            int p = npr; pr_name[p] = tk_s[i + 1]; i += 2; pr_np[p] = 0;
            while (i < ntok && tk_kind[i] == TVAR) { pr_param[p][pr_np[p]] = tk_s[i]; pr_np[p]++; i++; }
            pr_body[p] = i;
            while (i < ntok && !(tk_kind[i] == TWORD && ieq(tk_s[i], "end"))) i++;
            pr_end[p] = i; npr++;
            if (i < ntok) i++;   /* skip END */
            continue;
        }
        i++;
    }
}

void initpal()
{
    g_pal[0] = 0x000000; g_pal[1] = 0x0000FF; g_pal[2] = 0x00C000; g_pal[3] = 0x00C0C0;
    g_pal[4] = 0xFF0000; g_pal[5] = 0xFF00FF; g_pal[6] = 0xC0C000; g_pal[7] = 0x808080;
    g_pal[8] = 0xA52A2A; g_pal[9] = 0xD2B48C; g_pal[10] = 0x228B22; g_pal[11] = 0x40E0D0;
    g_pal[12] = 0xFA8072; g_pal[13] = 0x800080; g_pal[14] = 0xFF8C00; g_pal[15] = 0x404040;
}
void turtle_reset() { tpen = 1; tcolor = 0x000000; tsize = 1; t_home(); }

int main(int argc, char **argv)
{
    PI = 3.14159265358979;
    initpal();
    char *infile = 0; char *outpath = 0; int mode = 0;   /* 0 none, 1 svg, 2 png, 3 gif */
    g_w = 600; g_h = 600;
    int i;
    for (i = 1; i < argc; i++)
        if (strcmp((char *)argv[i], "-h") == 0 || strcmp((char *)argv[i], "--help") == 0)
        { printf((int)"usage: logo [file.logo] [-svg|-png|-gif out]   turtle graphics; no file = interactive REPL\n"); return 0; }
    for (i = 1; i < argc; i++)
    {
        char *a = (char *)argv[i];
        if (strcmp(a, "-svg") == 0 && i + 1 < argc) { mode = 1; outpath = (char *)argv[++i]; }
        else if (strcmp(a, "-png") == 0 && i + 1 < argc) { mode = 2; outpath = (char *)argv[++i]; }
        else if (strcmp(a, "-gif") == 0 && i + 1 < argc) { mode = 3; outpath = (char *)argv[++i]; g_gif = 1; }
        else if (a[0] != '-') infile = a;
    }

    tc_init(g_w, g_h, 0xFFFFFF);
    turtle_reset();

    if (infile)
    {
        char *src = (char *)rt_slurp((int)infile);
        if (src == 0) { printf((int)"logo: cannot read %s\n", (int)infile); return 1; }
        tokenize(src);
        register_procs();
        if (g_gif) { tc_frame(4); g_frames++; }
        run_range(0, ntok);
        if (mode == 3) tc_frame(120);          /* hold the final frame */
        if (mode == 1) { tc_svg((int)outpath); printf((int)"logo: wrote %s\n", (int)outpath); }
        else if (mode == 2) { tc_png((int)outpath); printf((int)"logo: wrote %s\n", (int)outpath); }
        else if (mode == 3) { tc_gif((int)outpath); printf((int)"logo: wrote %s\n", (int)outpath); }
        return 0;
    }

    /* interactive REPL: live drawing via the gfx window (run under ilgfx to view) */
    g_live = 1;
    gfx_open(g_w, g_h, (int)"Logo");
    tc_clear(0xFFFFFF); turtle_reset(); tc_present();
    char line[4096];
    printf((int)"Logo. Type commands; Ctrl-Z/Ctrl-D to exit.\n? ");
    while (1)
    {
        int li = 0, ch;
        while ((ch = getchar()) != -1 && ch != '\n') { if (ch != '\r' && li < 4095) line[li++] = ch; }
        if (ch == -1 && li == 0) break;
        line[li] = 0;
        ntok = 0; g_stop = 0;
        tokenize(line); register_procs(); run_range(0, ntok);
        tc_present();
        printf((int)"? ");
        if (ch == -1) break;
    }
    return 0;
}
