%{
/* An Ada subset -> C (yacc); cc lowers the C to .NET IL. The main procedure becomes
 * main(); other (incl. nested) subprograms are hoisted to C functions, so a compiled
 * Ada program's subprograms are public static methods on CProgram for C#/VB interop.
 * Parameter modes: `in` (default) is by value; `out`/`in out` are by reference. Local
 * names are prefixed v<subid>_ so same-named locals in different subprograms don't
 * collide. Single pass (Ada requires declaration before use). */
#define T_VOID 0
#define T_INT 1
#define T_FLOAT 2
#define T_BOOL 3
#define T_CHAR 4
#define T_STR 5

int g_subctr;
char *g_dcl, *g_cod, *g_funcs, *g_paramsig;
char *g_curname; int g_curret, g_curismain, g_cursubid; int g_nparam;
int ss_subid[16]; char *ss_dcl[16]; char *ss_cod[16]; char *ss_ps[16]; char *ss_name[16]; int ss_ret[16]; int ss_main[16]; int g_sp;
int g_lbl, g_lstk[256], g_lsp;

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 16); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 16); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *istr(int n) { char b[24]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
void apd(char *s) { g_dcl = j2(g_dcl, s); }
void apc(char *s) { g_cod = j2(g_cod, s); }
char *ctype(int t) { if (t == T_FLOAT) return "double"; if (t == T_STR) return "char*"; return "int"; }
char *cstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"'; while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; r[j++] = s[i++]; } r[j++] = '"'; r[j] = 0; return r; }

struct E { char *code; int ty; };
int mkE(char *c, int t) { struct E *e = (struct E *)malloc(8); e->code = c; e->ty = t; return (int)e; }
char *ecode(int h) { return ((struct E *)h)->code; }
int etype(int h) { return ((struct E *)h)->ty; }

/* variables (flat, prefixed by subid); k 0 local,1 by-ref param */
char *sv_name[4000]; int sv_subid[4000]; int sv_ty[4000]; int sv_ref[4000]; int sv_arr[4000]; int sv_lo[4000]; int sv_n[4000]; int nsv;
int sv_find(char *n) { int i; for (i = nsv - 1; i >= 0; i--) if (sv_subid[i] == g_cursubid && strcmp(sv_name[i], n) == 0) return i; return -1; }
/* enum constants + named numbers (global), and types */
char *en_name[2000]; int en_val[2000]; int nen;
int en_find(char *n) { int i; for (i = 0; i < nen; i++) if (strcmp(en_name[i], n) == 0) return i; return -1; }
char *ty_name[500]; int ty_kind[500]; int ty_lo[500]; int ty_n[500]; int ty_elem[500]; int nty;   /* kind: 1 enum(->int), 2 array */
int ty_find(char *n) { int i; for (i = 0; i < nty; i++) if (strcmp(ty_name[i], n) == 0) return i; return -1; }
/* subprograms */
char *fn_name[1000]; int fn_ret[1000]; int fn_np[1000]; int fn_ref[1000][16]; int fn_ty[1000][16]; int nfn;
int fn_find(char *n) { int i; for (i = 0; i < nfn; i++) if (strcmp(fn_name[i], n) == 0) return i; return -1; }

char *cvar(char *nm) { return j4("v", istr(g_cursubid), "_", nm); }

int typeref(char *n)   /* type name -> base type code (enums/arrays handled by caller) */
{
    if (strcmp(n, "integer") == 0 || strcmp(n, "natural") == 0 || strcmp(n, "positive") == 0) return T_INT;
    if (strcmp(n, "float") == 0 || strcmp(n, "long_float") == 0 || strcmp(n, "duration") == 0) return T_FLOAT;
    if (strcmp(n, "boolean") == 0) return T_BOOL;
    if (strcmp(n, "character") == 0) return T_CHAR;
    if (strcmp(n, "string") == 0) return T_STR;
    int ti = ty_find(n); if (ti >= 0) return (ty_kind[ti] == 2) ? ty_elem[ti] : T_INT;   /* enum -> int */
    return T_INT;
}

int yylex(); void yyerror(char *m);
int bin(int a, char *op, int b); int name_ref(char *nm); int name_idx(char *nm, int ix); int name_call(char *nm, int argh);
int cmp(int a, char *op, int b); int attr_arg(char *attr, int arg); int attr_no(int base, char *attr); char *lc2(char *s);
void sub_begin(char *nm, int isfunc); void sub_end(); char *subname(char *nm);
void do_assign(int lv, int rv); void do_call(char *nm, int argh); void do_for(char *v); void do_objdecl(int nlh, int isconst, int tsh, int inith);
void def_enum(char *nm, int nlh); void def_enum_range(char *nm); void def_arrtype(char *nm, int lo, int hi, char *elem); void add_params(int nlh, int ref, char *tyname);
int mktype_named(char *nm); int mktype_arr(int lo, int hi, char *elem); int nl1(char *s); int nlA(int h, char *s); int ag_new(); int ag_add(int h, int e);
%}
%token NAME INTLIT FLOATLIT STRINGLIT CHARLIT
%token KWITH KUSE KPROCEDURE KFUNCTION KIS KBEGIN KEND KRETURN KIF KTHEN KELSIF KELSE KCASE KWHEN
%token KLOOP KWHILE KFOR KIN KOUT KREVERSE KEXIT KAND KOR KNOT KMOD KREM KABS KNULL KCONSTANT KTYPE KARRAY KOF KRANGE KOTHERS KTRUE KFALSE
%token ASSIGN NE LE GE POW ARROW DOTDOT TICK
%left KOR
%left KAND
%right KNOT
%nonassoc '=' NE '<' '>' LE GE
%left '&'
%left '+' '-'
%left '*' '/' KMOD KREM
%right KABS UMINUS
%right POW
%left TICK
%%
unit    : withs subprograms ;
withs   : | withs withcl ;
withcl  : KWITH dname ';' | KUSE dname ';' ;
dname   : NAME | dname '.' NAME ;
subprograms : subprogram | subprograms subprogram ;

subprogram : phproc formals KIS declpart KBEGIN stmts KEND endopt ';'   { sub_end(); }
           | phfunc formals KRETURN NAME KIS { g_curret = typeref((char *)$4); } declpart KBEGIN stmts KEND endopt ';' { sub_end(); } ;
phproc  : KPROCEDURE NAME   { sub_begin((char *)$2, 0); } ;
phfunc  : KFUNCTION NAME    { sub_begin((char *)$2, 1); } ;
endopt  : | NAME ;

formals : | '(' params ')' ;
params  : param | params ';' param ;
param   : namelist ':' mode NAME   { add_params($1, $3, (char *)$4); } ;
mode    : { $$ = 0; } | KIN { $$ = 0; } | KOUT { $$ = 1; } | KIN KOUT { $$ = 1; } ;
namelist: NAME { $$ = nl1((char *)$1); } | namelist ',' NAME { $$ = nlA($1, (char *)$3); } ;

declpart : | declpart decl ;
decl    : objdecl | typedecl | subprogram ;
objdecl : namelist ':' constopt typespec initopt ';'   { do_objdecl($1, $3, $4, $5); } ;
constopt: { $$ = 0; } | KCONSTANT { $$ = 1; } ;
typespec: NAME                         { $$ = mktype_named((char *)$1); }
        | KARRAY '(' INTLIT DOTDOT INTLIT ')' KOF NAME { $$ = mktype_arr($3, $5, (char *)$8); } ;
initopt : { $$ = 0; } | ASSIGN expr { $$ = $2; } ;
typedecl: KTYPE NAME KIS '(' enumlist ')' ';'   { def_enum((char *)$2, $5); }
        | KTYPE NAME KIS KARRAY '(' INTLIT DOTDOT INTLIT ')' KOF NAME ';' { def_arrtype((char *)$2, $6, $8, (char *)$11); }
        | KTYPE NAME KIS KRANGE INTLIT DOTDOT INTLIT ';' { def_enum_range((char *)$2); } ;
enumlist: NAME { $$ = nl1((char *)$1); } | enumlist ',' NAME { $$ = nlA($1, (char *)$3); } ;

stmts   : | stmts stmt ;
stmt    : NAME ASSIGN expr ';'          { do_assign(name_ref((char *)$1), $3); }
        | callstmt
        | KNULL ';'
        | KRETURN ';'                   { apc("return;\n"); }
        | KRETURN expr ';'              { apc(F1("return %s;\n", ecode($2))); }
        | KEXIT ';'                     { apc("break;\n"); }
        | KEXIT KWHEN expr ';'          { apc(F1("if (%s) break;\n", ecode($3))); }
        | NAME ';'                      { apc(F1("%s();\n", subname((char *)$1))); }
        | ifstmt | casestmt | loopstmt ;
callstmt: NAME cn '(' arglist aget ')' cstail ;
cn      : { g_callname = (char *)$0; } ;
aget    : { g_callargs = $0; } ;
cstail  : ';'             { do_call(g_callname, g_callargs); }
        | ASSIGN expr ';' { do_assign(name_idx(g_callname, ag_first(g_callargs)), $2); } ;

ifstmt  : KIF expr ift KTHEN stmts ifrest ;
ift     : { apc(F1("if (%s) {\n", ecode($0))); } ;
ifrest  : KEND KIF ';'                  { apc("}\n"); }
        | elsk stmts KEND KIF ';'       { apc("}\n"); }
        | elsifk expr eift KTHEN stmts ifrest ;
elsk    : KELSE                         { apc("} else {\n"); } ;
elsifk  : KELSIF                        { apc("} else "); } ;
eift    : { apc(F1("if (%s) {\n", ecode($0))); } ;

casestmt: KCASE expr cb KIS whens KEND KCASE ';'   { apc("} }\n"); } ;
cb      : { apc(F1("{ int __cv = %s; if (0) {\n", ecode($0))); } ;
whens   : | whens onewhen ;
onewhen : KWHEN choices ARROW stmts | KWHEN KOTHERS owk ARROW stmts ;
choices : choice | choices '|' choice ;
choice  : expr { apc(F1("} else if (__cv == %s) {\n", ecode($1))); } ;
owk     : { apc("} else {\n"); } ;

loopstmt: KLOOP lo stmts KEND KLOOP ';'                      { apc("}\n"); }
        | KWHILE expr wlo KLOOP stmts KEND KLOOP ';'         { apc("}\n"); }
        | KFOR NAME fvar KIN forrange flo KLOOP stmts KEND KLOOP ';' { apc("}\n"); } ;
lo      : { apc("while (1) {\n"); } ;
wlo     : { apc(F1("while (%s) {\n", ecode($0))); } ;
fvar    : { g_forvar = (char *)$0; } ;
forrange: revopt expr DOTDOT expr   { g_frev = $1; g_flo = ecode($2); g_fhi = ecode($4); } ;
revopt  : { $$ = 0; } | KREVERSE { $$ = 1; } ;
flo     : { do_for(g_forvar); } ;

expr    : expr '+' expr   { $$ = bin($1, "+", $3); }
        | expr '-' expr   { $$ = bin($1, "-", $3); }
        | expr '*' expr   { $$ = bin($1, "*", $3); }
        | expr '/' expr   { $$ = bin($1, "/", $3); }
        | expr KMOD expr  { $$ = mkE(F2("(%s %% %s)", ecode($1), ecode($3)), T_INT); }
        | expr KREM expr  { $$ = mkE(F2("(%s %% %s)", ecode($1), ecode($3)), T_INT); }
        | expr POW expr   { $$ = mkE(F2("((int)pow((double)(%s),(double)(%s)))", ecode($1), ecode($3)), T_INT); }
        | KABS expr       { $$ = mkE(F1("abs(%s)", ecode($2)), etype($2)); }
        | '-' expr %prec UMINUS { $$ = mkE(F1("(-%s)", ecode($2)), etype($2)); }
        | expr '&' expr   { $$ = mkE(F2("acat(%s, %s)", ecode($1), ecode($3)), T_STR); }
        | expr '=' expr   { $$ = cmp($1, "==", $3); }
        | expr NE expr    { $$ = cmp($1, "!=", $3); }
        | expr '<' expr   { $$ = cmp($1, "<", $3); }
        | expr LE expr    { $$ = cmp($1, "<=", $3); }
        | expr '>' expr   { $$ = cmp($1, ">", $3); }
        | expr GE expr    { $$ = cmp($1, ">=", $3); }
        | expr KAND expr  { $$ = mkE(F2("(%s && %s)", ecode($1), ecode($3)), T_BOOL); }
        | expr KOR expr   { $$ = mkE(F2("(%s || %s)", ecode($1), ecode($3)), T_BOOL); }
        | expr KAND KTHEN expr { $$ = mkE(F2("(%s && %s)", ecode($1), ecode($4)), T_BOOL); }
        | expr KOR KELSE expr  { $$ = mkE(F2("(%s || %s)", ecode($1), ecode($4)), T_BOOL); }
        | KNOT expr       { $$ = mkE(F1("(!%s)", ecode($2)), T_BOOL); }
        | '(' expr ')'    { $$ = mkE(F1("(%s)", ecode($2)), etype($2)); }
        | expr TICK NAME '(' expr ')' { $$ = attr_arg((char *)$3, $5); }
        | expr TICK NAME              { $$ = attr_no($1, (char *)$3); }
        | INTLIT          { $$ = mkE(istr($1), T_INT); }
        | FLOATLIT        { $$ = mkE((char *)$1, T_FLOAT); }
        | STRINGLIT       { $$ = mkE(cstr((char *)$1), T_STR); }
        | CHARLIT         { $$ = mkE(istr($1), T_CHAR); }
        | KTRUE           { $$ = mkE("1", T_BOOL); }
        | KFALSE          { $$ = mkE("0", T_BOOL); }
        | NAME            { $$ = name_ref((char *)$1); }
        | NAME '(' arglist ')' { $$ = name_call((char *)$1, $3); } ;

arglist : { $$ = ag_new(); } | args ;
args    : expr { $$ = ag_add(ag_new(), $1); } | args ',' expr { $$ = ag_add($1, $3); } ;
%%

void yyerror(char *m) { printf((int)"ada: %s (line %d)\n", (int)m, pline); }

/* name lists */
struct NL { int n; char *a[64]; };
int nl1(char *s) { struct NL *l = (struct NL *)malloc(260); l->n = 0; l->a[l->n++] = s; return (int)l; }
int nlA(int h, char *s) { struct NL *l = (struct NL *)h; l->a[l->n++] = s; return h; }
struct AG { int n; int a[64]; };
int ag_new() { struct AG *g = (struct AG *)malloc(260); g->n = 0; return (int)g; }
int ag_add(int h, int e) { struct AG *g = (struct AG *)h; g->a[g->n++] = e; return h; }

int g_frev; char *g_flo; char *g_fhi; char *g_forvar; char *g_callname; int g_callargs;
int ag_first(int h) { struct AG *g = (struct AG *)h; return g->a[0]; }

char *subname(char *nm) { return j2("ada_", nm); }

void sub_begin(char *nm, int isfunc)
{
    ss_subid[g_sp] = g_cursubid; ss_dcl[g_sp] = g_dcl; ss_cod[g_sp] = g_cod; ss_ps[g_sp] = g_paramsig; ss_name[g_sp] = g_curname; ss_ret[g_sp] = g_curret; ss_main[g_sp] = g_curismain;
    g_curismain = (g_sp == 0 && !isfunc);
    g_sp++;
    g_cursubid = ++g_subctr; g_dcl = ""; g_cod = ""; g_paramsig = ""; g_curname = nm; g_curret = T_VOID; g_nparam = 0;
}
void sub_end()
{
    int p = fn_find(g_curname); if (p < 0) p = nfn++;   /* register signature */
    char *fn;
    if (g_curismain) fn = j3("int main(int argc, char** argv) {\n", g_dcl, j2(g_cod, "return 0;\n}\n"));
    else
    {
        char *ct = ctype(g_curret);
        fn = j3(j4(ct, " ", subname(g_curname), "("), g_paramsig, j3(") {\n", g_dcl, j2(g_cod, "}\n")));
    }
    g_funcs = j2(g_funcs, fn);
    g_sp--;
    g_cursubid = ss_subid[g_sp]; g_dcl = ss_dcl[g_sp]; g_cod = ss_cod[g_sp]; g_paramsig = ss_ps[g_sp]; g_curname = ss_name[g_sp]; g_curret = ss_ret[g_sp]; g_curismain = ss_main[g_sp];
}

void add_params(int nlh, int ref, char *tyname)
{
    struct NL *l = (struct NL *)nlh; int i; int ty = typeref(tyname); int p = fn_find(g_curname); if (p < 0) { p = nfn; fn_name[nfn] = g_curname; fn_ret[nfn] = g_curret; fn_np[nfn] = 0; nfn++; }
    for (i = 0; i < l->n; i++)
    {
        sv_name[nsv] = l->a[i]; sv_subid[nsv] = g_cursubid; sv_ty[nsv] = ty; sv_ref[nsv] = ref; sv_arr[nsv] = 0; nsv++;
        fn_ref[p][fn_np[p]] = ref; fn_ty[p][fn_np[p]] = ty; fn_np[p]++; g_nparam++;
        char *pc = j3(ctype(ty), ref ? "* " : " ", cvar(l->a[i]));
        g_paramsig = (strlen(g_paramsig) == 0) ? pc : j3(g_paramsig, ", ", pc);
    }
}

/* type spec handle: {kind: 0 scalar/named, 2 array; ty; lo; n; elem} */
struct TS { int kind; int ty; int lo; int n; int elem; };
int mktype_named(char *nm) { struct TS *t = (struct TS *)malloc(20); int ti = ty_find(nm); if (ti >= 0 && ty_kind[ti] == 2) { t->kind = 2; t->elem = ty_elem[ti]; t->lo = ty_lo[ti]; t->n = ty_n[ti]; t->ty = ty_elem[ti]; } else { t->kind = 0; t->ty = typeref(nm); } return (int)t; }
int mktype_arr(int lo, int hi, char *elem) { struct TS *t = (struct TS *)malloc(20); t->kind = 2; t->elem = typeref(elem); t->lo = lo; t->n = hi - lo + 1; t->ty = t->elem; return (int)t; }

void do_objdecl(int nlh, int isconst, int tsh, int inith)
{
    struct NL *l = (struct NL *)nlh; struct TS *t = (struct TS *)tsh; int i;
    for (i = 0; i < l->n; i++)
    {
        char *cn = cvar(l->a[i]);
        sv_name[nsv] = l->a[i]; sv_subid[nsv] = g_cursubid; sv_ty[nsv] = t->ty; sv_ref[nsv] = 0;
        if (t->kind == 2) { sv_arr[nsv] = 1; sv_lo[nsv] = t->lo; sv_n[nsv] = t->n; nsv++; apd(j3(ctype(t->elem), " ", j2(cn, F1("[%s];\n", istr(t->n))))); }
        else { sv_arr[nsv] = 0; nsv++; apd(j4(ctype(t->ty), " ", cn, ";\n")); if (inith) apc(F2("%s = %s;\n", cn, ecode(inith))); else if (t->ty == T_STR) apc(F1("%s = \"\";\n", cn)); }
    }
}
void def_enum(char *nm, int nlh)
{
    struct NL *l = (struct NL *)nlh; int i; ty_name[nty] = nm; ty_kind[nty] = 1; nty++;
    for (i = 0; i < l->n; i++) { en_name[nen] = l->a[i]; en_val[nen] = i; nen++; }
}
void def_enum_range(char *nm) { ty_name[nty] = nm; ty_kind[nty] = 1; nty++; }
void def_arrtype(char *nm, int lo, int hi, char *elem) { ty_name[nty] = nm; ty_kind[nty] = 2; ty_lo[nty] = lo; ty_n[nty] = hi - lo + 1; ty_elem[nty] = typeref(elem); nty++; }

int name_ref(char *nm)
{
    int i = sv_find(nm);
    if (i >= 0) { char *c = cvar(nm); if (sv_ref[i]) c = F1("(*%s)", c); return mkE(c, sv_ty[i]); }
    int e = en_find(nm); if (e >= 0) return mkE(istr(en_val[e]), T_INT);
    return mkE(cvar(nm), T_INT);
}
int name_idx(char *nm, int ix)
{
    int i = sv_find(nm);
    if (i >= 0 && sv_arr[i]) return mkE(j2(cvar(nm), j4("[(", ecode(ix), ") - ", j2(istr(sv_lo[i]), "]"))), sv_ty[i]);
    return name_call(nm, ag_add(ag_new(), ix));
}
int name_call(char *nm, int argh)
{
    struct AG *g = (struct AG *)argh; int si = sv_find(nm);
    if (si >= 0 && sv_arr[si]) return mkE(j2(cvar(nm), j4("[(", ecode(g->a[0]), ") - ", j2(istr(sv_lo[si]), "]"))), sv_ty[si]);
    int fi = fn_find(nm); int rt = (fi >= 0) ? fn_ret[fi] : T_INT; char *args = ""; int i;
    for (i = 0; i < g->n; i++) { char *c = ecode(g->a[i]); args = (i == 0) ? c : j3(args, ", ", c); }
    return mkE(F2("%s(%s)", subname(nm), args), rt);
}
void do_call(char *nm, int argh)
{
    struct AG *g = (struct AG *)argh; int i;
    if (strcmp(nm, "put_line") == 0 || strcmp(nm, "put") == 0)
    {
        char *e = g->n ? ecode(g->a[0]) : "\"\""; int t = g->n ? etype(g->a[0]) : T_STR;
        char *s = (t == T_STR) ? e : (t == T_CHAR) ? F1("ada_imgc(%s)", e) : (t == T_FLOAT) ? F1("ada_imgf(%s)", e) : F1("ada_imgi(%s)", e);
        apc(F1(strcmp(nm, "put_line") == 0 ? "printf(\"%%s\\n\", %s);\n" : "printf(\"%%s\", %s);\n", s));
        return;
    }
    if (strcmp(nm, "new_line") == 0) { apc("printf(\"\\n\");\n"); return; }
    int fi = fn_find(nm); char *args = "";
    for (i = 0; i < g->n; i++)
    {
        char *c = ecode(g->a[i]); int ref = (fi >= 0 && i < fn_np[fi]) ? fn_ref[fi][i] : 0;
        char *a = ref ? F1("&(%s)", c) : c; args = (i == 0) ? a : j3(args, ", ", a);
    }
    apc(F2("%s(%s);\n", subname(nm), args));
}
void do_assign(int lv, int rv)
{
    int lt = etype(lv); char *rc = ecode(rv);
    if (lt == T_FLOAT && etype(rv) == T_INT) rc = F1("(double)(%s)", rc);
    if (lt == T_STR) apc(F2("%s = %s;\n", ecode(lv), rc));
    else apc(F2("%s = %s;\n", ecode(lv), rc));
}
void do_for(char *v)
{
    int i = sv_find(v); char *cv;
    if (i < 0) { sv_name[nsv] = v; sv_subid[nsv] = g_cursubid; sv_ty[nsv] = T_INT; sv_ref[nsv] = 0; sv_arr[nsv] = 0; nsv++; apd(j3("int ", cvar(v), ";\n")); }
    cv = cvar(v);
    if (g_frev) apc(j2(F2("for (%s = %s; ", cv, g_fhi), j4(cv, " >= ", g_flo, j3("; ", cv, " -= 1) {\n"))));
    else apc(j2(F2("for (%s = %s; ", cv, g_flo), j4(cv, " <= ", g_fhi, j3("; ", cv, " += 1) {\n"))));
}
int bin(int a, char *op, int b)
{
    int rt = (etype(a) == T_FLOAT || etype(b) == T_FLOAT) ? T_FLOAT : T_INT;
    char *la = ecode(a), *lb = ecode(b);
    if (rt == T_FLOAT) { if (etype(a) == T_INT) la = F1("(double)(%s)", la); if (etype(b) == T_INT) lb = F1("(double)(%s)", lb); }
    return mkE(j2("(", j4(la, op, lb, ")")), rt);
}
int cmp(int a, char *op, int b)
{
    if (etype(a) == T_STR || etype(b) == T_STR) { char *o = (strcmp(op, "==") == 0) ? "== 0" : (strcmp(op, "!=") == 0) ? "!= 0" : j2(op, " 0"); return mkE(j3(F2("(strcmp(%s, %s) ", ecode(a), ecode(b)), o, ")"), T_BOOL); }
    return mkE(j2("(", j4(ecode(a), op, ecode(b), ")")), T_BOOL);
}
int attr_arg(char *attr, int arg)
{
    char *a = lc2(attr);
    if (strcmp(a, "image") == 0) return mkE(etype(arg) == T_FLOAT ? F1("ada_imgf(%s)", ecode(arg)) : F1("ada_imgi(%s)", ecode(arg)), T_STR);
    return mkE(ecode(arg), etype(arg));
}
int attr_no(int base, char *attr)
{
    char *a = lc2(attr);
    if (strcmp(a, "image") == 0) return mkE(etype(base) == T_FLOAT ? F1("ada_imgf(%s)", ecode(base)) : F1("ada_imgi(%s)", ecode(base)), T_STR);
    return mkE(ecode(base), etype(base));
}
char *lc2(char *s) { char *r = (char *)strdup((int)s); int i = 0; while (r[i]) { if (r[i] >= 'A' && r[i] <= 'Z') r[i] += 32; i++; } return r; }

char *PRELUDE =
"char* acat(char*a,char*b){ char*r=(char*)malloc(strlen(a)+strlen(b)+1); strcpy(r,a); strcat(r,b); return r; }\n"
"char* ada_imgi(int v){ char b[24]; if(v>=0) sprintf(b,\" %d\",v); else sprintf(b,\"%d\",v); return strdup(b); }\n"
"char* ada_imgf(double v){ char b[40]; if(v>=0) sprintf(b,\" %g\",v); else sprintf(b,\"%g\",v); return strdup(b); }\n"
"char* ada_imgc(int c){ char b[2]; b[0]=(char)c; b[1]=0; return strdup(b); }\n";

void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: ada <file.adb> [-o out]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], cpath[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, "exe"); }
    strcpy(cpath, outp); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (!src) { printf((int)"ada: cannot read %s\n", (int)in); return 1; }
    nsv = 0; nen = 0; nty = 0; nfn = 0; g_subctr = 0; g_sp = 0; g_funcs = ""; g_dcl = ""; g_cod = ""; g_paramsig = ""; g_cursubid = 0;
    yy_scan_string((int)src); yyparse();

    int f = fopen((int)cpath, (int)"w"); fputs((int)PRELUDE, f); fputs((int)g_funcs, f); fclose(f);
    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; int n = 0; av[n++] = (int)cc; av[n++] = (int)cpath; av[n++] = (int)"-o"; av[n++] = (int)outp; av[n++] = dll ? (int)"--dll" : (int)"--exe";
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"ada: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"ada: cc failed (%d)\n", rc);
    return rc;
}
