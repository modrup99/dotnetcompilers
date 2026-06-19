%{
/* Coil -> stack-IL IR (yacc front end). Parses + type-checks Coil and lowers every
 * construct to a flat stack-machine IR that is essentially textual CIL
 * (ldc.i / ldarg / add / call / brfalse / ret ...). The C# `coilasm` turns the IR
 * into a real .NET assembly via Reflection.Emit, so Coil functions become
 * `public static` typed methods callable from C#/VB.NET.
 *
 * Two passes: pass 1 registers every function signature (so forward calls
 * type-check); pass 2 emits the IR. */

#define T_VOID 0
#define T_INT 1
#define T_DBL 2
#define T_BOOL 3
#define T_STR 4

int g_pass;
char *g_ir, *g_code, *g_locals, *g_plines, *g_fname; int g_ret, g_lbl;
int g_curpty[32]; int g_curpn;
int g_lstk[512]; int g_lsp;            /* label stack for nested if/while */

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 8); sprintf((int)r, (int)f, (int)a); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *Ln(char *pfx, int n) { return F1(pfx, istr(n)); }
char *tyname(int t) { if (t == T_INT) return "int"; if (t == T_DBL) return "double"; if (t == T_BOOL) return "bool"; if (t == T_STR) return "string"; return "void"; }
void ap(char *s) { if (g_pass == 2) g_code = j2(g_code, s); }

struct E { char *code; int ty; };
int mkE(char *code, int ty) { struct E *e = (struct E *)malloc(12); e->code = code; e->ty = ty; return (int)e; }
char *ecode(int h) { return ((struct E *)h)->code; }
int etype(int h) { return ((struct E *)h)->ty; }

char *escstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 2); int i = 0, j = 0; while (s[i]) { char c = s[i]; if (c == '\\') { r[j++] = '\\'; r[j++] = '\\'; } else if (c == '\n') { r[j++] = '\\'; r[j++] = 'n'; } else if (c == '\t') { r[j++] = '\\'; r[j++] = 't'; } else if (c == '\r') { r[j++] = '\\'; r[j++] = 'r'; } else r[j++] = c; i++; } r[j] = 0; return r; }

char *fn_name[2000]; int fn_ret[2000]; int fn_np[2000]; int fn_pty[2000][32]; int nfn;
int fn_find(char *n) { int i; for (i = 0; i < nfn; i++) if (strcmp(fn_name[i], n) == 0) return i; return -1; }

char *sv_name[1000]; int sv_ty[1000]; int sv_kind[1000]; int nsv;   /* 0=local 1=param */
int sv_find(char *n) { int i; for (i = nsv - 1; i >= 0; i--) if (strcmp(sv_name[i], n) == 0) return i; return -1; }

char *boxop(int t) { if (t == T_INT) return "box.i\n"; if (t == T_DBL) return "box.r\n"; if (t == T_BOOL) return "box.b\n"; return ""; }
char *convs(int from, int to) { return (from == T_INT && to == T_DBL) ? "conv.r8\n" : ""; }

int bin(int a, char *op, int b)
{
    int at = etype(a), bt = etype(b);
    if (strcmp(op, "+") == 0 && (at == T_STR || bt == T_STR))
        return mkE(j2(j2(ecode(a), boxop(at)), j2(ecode(b), j2(boxop(bt), "concat\n"))), T_STR);
    if (strcmp(op, "+") == 0 || strcmp(op, "-") == 0 || strcmp(op, "*") == 0 || strcmp(op, "/") == 0 || strcmp(op, "%") == 0)
    {
        int rt = (at == T_DBL || bt == T_DBL) ? T_DBL : T_INT;
        char *opn = strcmp(op, "+") == 0 ? "add\n" : strcmp(op, "-") == 0 ? "sub\n" : strcmp(op, "*") == 0 ? "mul\n" : strcmp(op, "/") == 0 ? "div\n" : "rem\n";
        return mkE(j2(j2(ecode(a), convs(at, rt)), j2(ecode(b), j2(convs(bt, rt), opn))), rt);
    }
    if (at == T_STR && bt == T_STR)
        return mkE(j2(ecode(a), j2(ecode(b), strcmp(op, "!=") == 0 ? "streq\nnot\n" : "streq\n")), T_BOOL);
    int rt = (at == T_DBL || bt == T_DBL) ? T_DBL : T_INT;
    char *cmp = "ceq\n";
    if (strcmp(op, "!=") == 0) cmp = "ceq\nnot\n"; else if (strcmp(op, "<") == 0) cmp = "clt\n"; else if (strcmp(op, ">") == 0) cmp = "cgt\n";
    else if (strcmp(op, "<=") == 0) cmp = "cgt\nnot\n"; else if (strcmp(op, ">=") == 0) cmp = "clt\nnot\n";
    return mkE(j2(j2(ecode(a), convs(at, rt)), j2(ecode(b), j2(convs(bt, rt), cmp))), T_BOOL);
}
int logic(int a, int isand, int b)
{
    int l1 = g_lbl++, l2 = g_lbl++;
    char *code = j2(ecode(a), Ln(isand ? "brfalse L%s\n" : "brtrue L%s\n", l1));
    code = j2(code, ecode(b));
    code = j2(code, Ln("br L%s\n", l2));
    code = j2(code, Ln("label L%s\n", l1));
    code = j2(code, isand ? "ldc.i 0\n" : "ldc.i 1\n");
    code = j2(code, Ln("label L%s\n", l2));
    return mkE(code, T_BOOL);
}

/* argument list: keep each arg's code + type separate so the call can insert
 * int->double promotion per parameter. */
struct AG { int n; int code[32]; int ty[32]; };
int ag_new() { struct AG *g = (struct AG *)malloc(260); g->n = 0; return (int)g; }
int ag_add(int h, int code, int ty) { struct AG *g = (struct AG *)h; g->code[g->n] = code; g->ty[g->n] = ty; g->n++; return h; }
int call_fn(char *name, int agh)
{
    struct AG *g = (struct AG *)agh;
    int fi = fn_find(name); int rt = (fi >= 0) ? fn_ret[fi] : T_INT;
    char *code = ""; int i;
    for (i = 0; i < g->n; i++) { code = j2(code, (char *)g->code[i]); int pt = (fi >= 0 && i < fn_np[fi]) ? fn_pty[fi][i] : g->ty[i]; code = j2(code, convs(g->ty[i], pt)); }
    char *callop = (char *)malloc(strlen(name) + 24); sprintf((int)callop, (int)"call %s %d\n", (int)name, g->n);
    return mkE(j2(code, callop), rt);
}

int yylex(); void yyerror(char *m);
%}
%token IDENT INTLIT DBLLIT STRLIT
%token KFUNC KVAR KRETURN KIF KELSE KWHILE KPRINT KPRINTLN KTRUE KFALSE KINT KDBL KBOOL KSTR KVOID
%token ARROW EQ NE LE GE ANDAND OROR
%left OROR
%left ANDAND
%left EQ NE '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'
%right UMINUS '!'
%%
program : funcs ;
funcs   : | funcs func ;

func    : fhead '(' params ')' ret block
          { if (g_pass == 1) { fn_name[nfn] = g_fname; fn_ret[nfn] = g_ret; fn_np[nfn] = g_curpn; int i; for (i = 0; i < g_curpn; i++) fn_pty[nfn][i] = g_curpty[i]; nfn++; }
            else { g_ir = j2(g_ir, j3("method ", g_fname, j3(" ", tyname(g_ret), "\n"))); g_ir = j2(g_ir, g_plines); g_ir = j2(g_ir, g_locals); g_ir = j2(g_ir, j3("code\n", g_code, "endmethod\n")); } } ;
fhead   : KFUNC IDENT  { g_fname = (char *)$2; nsv = 0; g_curpn = 0; g_code = ""; g_locals = ""; g_plines = ""; } ;
ret     : { g_ret = T_VOID; } | ARROW typ { g_ret = $2; } ;
typ     : KINT { $$ = T_INT; } | KDBL { $$ = T_DBL; } | KBOOL { $$ = T_BOOL; } | KSTR { $$ = T_STR; } | KVOID { $$ = T_VOID; } ;

params  : | plist ;
plist   : param | plist ',' param ;
param   : typ IDENT
          { sv_name[nsv] = (char *)$2; sv_ty[nsv] = $1; sv_kind[nsv] = 1; nsv++; g_curpty[g_curpn++] = $1;
            if (g_pass == 2) g_plines = j2(g_plines, j3("param ", tyname($1), j3(" ", (char *)$2, "\n"))); } ;

block   : '{' stmts '}' ;
stmts   : | stmts stmt ;

stmt    : typ IDENT '=' expr ';'
          { sv_name[nsv] = (char *)$2; sv_ty[nsv] = $1; sv_kind[nsv] = 0; nsv++;
            if (g_pass == 2) { g_locals = j2(g_locals, j3("local ", tyname($1), j3(" ", (char *)$2, "\n"))); ap(ecode($4)); ap(convs(etype($4), $1)); ap(F1("stloc %s\n", (char *)$2)); } }
        | KVAR IDENT '=' expr ';'
          { int t = etype($4); sv_name[nsv] = (char *)$2; sv_ty[nsv] = t; sv_kind[nsv] = 0; nsv++;
            if (g_pass == 2) { g_locals = j2(g_locals, j3("local ", tyname(t), j3(" ", (char *)$2, "\n"))); ap(ecode($4)); ap(F1("stloc %s\n", (char *)$2)); } }
        | IDENT '=' expr ';'
          { int i = sv_find((char *)$1); int kind = (i >= 0) ? sv_kind[i] : 0; int vt = (i >= 0) ? sv_ty[i] : etype($3);
            if (g_pass == 2) { ap(ecode($3)); ap(convs(etype($3), vt)); ap(F1(kind == 1 ? "starg %s\n" : "stloc %s\n", (char *)$1)); } }
        | KPRINT '(' expr ')' ';'    { if (g_pass == 2) { ap(ecode($3)); ap(F1("print %s 0\n", tyname(etype($3)))); } }
        | KPRINTLN '(' expr ')' ';'  { if (g_pass == 2) { ap(ecode($3)); ap(F1("print %s 1\n", tyname(etype($3)))); } }
        | KRETURN expr ';'           { if (g_pass == 2) { ap(ecode($2)); ap(convs(etype($2), g_ret)); ap("ret\n"); } }
        | KRETURN ';'                { if (g_pass == 2) ap("ret\n"); }
        | ifstmt
        | whilestmt
        | expr ';'                   { if (g_pass == 2) { ap(ecode($1)); if (etype($1) != T_VOID) ap("pop\n"); } }
        ;

ifstmt   : ifhead block ifrest ;
ifhead   : KIF '(' expr ')'  { int b = g_lbl; g_lbl += 2; g_lstk[g_lsp++] = b; if (g_pass == 2) { ap(ecode($3)); ap(Ln("brfalse L%s\n", b)); } } ;
ifrest   : /* no else */     { int b = g_lstk[--g_lsp]; if (g_pass == 2) ap(Ln("label L%s\n", b)); }
         | KELSE elsemk elsebody  { int b = g_lstk[--g_lsp]; if (g_pass == 2) ap(Ln("label L%s\n", b + 1)); } ;
elsemk   : /* empty */       { int b = g_lstk[g_lsp - 1]; if (g_pass == 2) { ap(Ln("br L%s\n", b + 1)); ap(Ln("label L%s\n", b)); } } ;
elsebody : block | ifstmt ;

whilestmt : whilehead block  { int b = g_lstk[--g_lsp]; if (g_pass == 2) { ap(Ln("br L%s\n", b)); ap(Ln("label L%s\n", b + 1)); } } ;
whilehead : KWHILE '(' expr ')'  { int b = g_lbl; g_lbl += 2; g_lstk[g_lsp++] = b; if (g_pass == 2) { ap(Ln("label L%s\n", b)); ap(ecode($3)); ap(Ln("brfalse L%s\n", b + 1)); } } ;

expr    : expr '+' expr   { $$ = bin($1, "+", $3); }
        | expr '-' expr   { $$ = bin($1, "-", $3); }
        | expr '*' expr   { $$ = bin($1, "*", $3); }
        | expr '/' expr   { $$ = bin($1, "/", $3); }
        | expr '%' expr   { $$ = bin($1, "%", $3); }
        | expr EQ expr    { $$ = bin($1, "==", $3); }
        | expr NE expr    { $$ = bin($1, "!=", $3); }
        | expr '<' expr   { $$ = bin($1, "<", $3); }
        | expr '>' expr   { $$ = bin($1, ">", $3); }
        | expr LE expr    { $$ = bin($1, "<=", $3); }
        | expr GE expr    { $$ = bin($1, ">=", $3); }
        | expr ANDAND expr { $$ = logic($1, 1, $3); }
        | expr OROR expr   { $$ = logic($1, 0, $3); }
        | '-' expr %prec UMINUS  { $$ = mkE(j2(ecode($2), "neg\n"), etype($2)); }
        | '!' expr               { $$ = mkE(j2(ecode($2), "not\n"), T_BOOL); }
        | '(' expr ')'    { $$ = $2; }
        | INTLIT          { $$ = mkE(Ln("ldc.i %s\n", $1), T_INT); }
        | DBLLIT          { $$ = mkE(F1("ldc.r %s\n", (char *)$1), T_DBL); }
        | STRLIT          { $$ = mkE(F1("ldstr %s\n", escstr((char *)$1)), T_STR); }
        | KTRUE           { $$ = mkE("ldc.i 1\n", T_BOOL); }
        | KFALSE          { $$ = mkE("ldc.i 0\n", T_BOOL); }
        | IDENT           { int i = sv_find((char *)$1); int t = (i >= 0) ? sv_ty[i] : T_INT; $$ = mkE(F1((i >= 0 && sv_kind[i] == 1) ? "ldarg %s\n" : "ldloc %s\n", (char *)$1), t); }
        | IDENT '(' arglist ')'  { $$ = call_fn((char *)$1, $3); }
        ;
arglist : /* empty */ { $$ = ag_new(); } | args { $$ = $1; } ;
args    : expr            { $$ = ag_add(ag_new(), $1 == 0 ? 0 : (int)ecode($1), etype($1)); }
        | args ',' expr   { $$ = ag_add($1, (int)ecode($3), etype($3)); } ;
%%

void yyerror(char *m) { fputs((int)"coil: ", (int)2); fputs((int)m, (int)2); fputs((int)"\n", (int)2); }
void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: coilfe <file.coil> [-o out] [--dll]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], irp[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, dll ? "dll" : "exe"); }
    strcpy(irp, outp); setext(irp, "ir");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"coil: cannot read %s\n", (int)in); return 1; }

    g_pass = 1; yy_scan_string((int)src); yyparse();
    g_pass = 2; pline = 1; g_lsp = 0; g_lbl = 0; g_ir = ""; yy_scan_string((int)src); yyparse();

    int f = fopen((int)irp, (int)"w"); fputs((int)g_ir, f); fclose(f);

    char as[1100]; char *repo = (char *)rt_repo();
    sprintf((int)as, (int)"%s\\src\\CoilAsm\\bin\\Release\\net10.0\\coilasm.exe", (int)repo);
    int av[8]; int n = 0; av[n++] = (int)as; av[n++] = (int)irp; av[n++] = (int)"-o"; av[n++] = (int)outp; if (dll) av[n++] = (int)"--dll";
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"coil: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"coil: assembler failed (%d)\n", rc);
    return rc;
}
