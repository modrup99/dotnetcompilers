%{
/* Fortran 90 (free-form subset) -> C (yacc); cc lowers the C to .NET IL. PROGRAM
 * becomes main(); SUBROUTINE/FUNCTION become C functions (public static methods, so
 * C#/VB.NET can call them). Function arguments are by value (clean interop); subroutine
 * arguments are by reference (Fortran semantics). Two passes: pass 1 registers every
 * subprogram signature, pass 2 emits the C. */

#define T_VOID 0
#define T_INT 1
#define T_REAL 2
#define T_LOG 3
#define T_CHR 4
#define K_LOCAL 0
#define K_PVAL 1
#define K_PREF 2

int g_pass;
char *g_out, *g_decls, *g_code;
char *g_uname; int g_uret, g_ukind;
char *g_argnm[32]; int g_argn;
int g_lbl, g_lstk[256], g_lsp;
int g_dty, g_charlen, g_dparam;
int g_dlo1, g_dn1, g_dlo2, g_dn2, g_dnd;     /* current item's array dims */

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 8); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 8); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
void ap(char *s) { if (g_pass == 2) g_code = j2(g_code, s); }
char *ctype(int t) { if (t == T_REAL) return "double"; if (t == T_CHR) return "char*"; return "int"; }

struct E { char *code; int ty; int lval; };
int mkE(char *c, int t) { struct E *e = (struct E *)malloc(16); e->code = c; e->ty = t; e->lval = 0; return (int)e; }
int mkLV(char *c, int t) { int h = mkE(c, t); ((struct E *)h)->lval = 1; return h; }
char *ecode(int h) { return ((struct E *)h)->code; }
int etype(int h) { return ((struct E *)h)->ty; }
int elval(int h) { return ((struct E *)h)->lval; }
int g_ntmp;
char *cstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"'; while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; r[j++] = s[i++]; } r[j++] = '"'; r[j] = 0; return r; }

char *sv_name[2000]; int sv_ty[2000]; int sv_kind[2000]; int sv_isarr[2000]; int sv_lo1[2000]; int sv_n1[2000]; int sv_lo2[2000]; int sv_n2[2000]; int nsv;
int sv_find(char *n) { int i; for (i = nsv - 1; i >= 0; i--) if (strcmp(sv_name[i], n) == 0) return i; return -1; }
char *fn_name[1000]; int fn_ret[1000]; int fn_issub[1000]; int fn_np[1000]; int fn_pty[1000][32]; int nfn;
int fn_find(char *n) { int i; for (i = 0; i < nfn; i++) if (strcmp(fn_name[i], n) == 0) return i; return -1; }
int is_arg(char *n) { int i; for (i = 0; i < g_argn; i++) if (strcmp(g_argnm[i], n) == 0) return 1; return 0; }
char *vref(char *cn, int kind) { return (kind == K_PREF) ? F1("(*%s)", cn) : cn; }

struct AG { int n; int a[32]; };
int ag_new() { struct AG *g = (struct AG *)malloc(132); g->n = 0; return (int)g; }
int ag_add(int h, int e) { struct AG *g = (struct AG *)h; g->a[g->n++] = e; return h; }

int bin(int a, char *op, int b);
int name_ref(char *nm, int agh, int hasp);
void declstart(); void decldim(int lo, int n); void declvar(char *nm, int arr, int init);
char *vlookup(char *nm);
int yylex(); void yyerror(char *m);
%}
%token NAME INTLIT REALLIT STRLIT EOL
%token KPROGRAM KSUBROUTINE KFUNCTION KEND ENDPROG ENDSUB ENDFUNC
%token KINTEGER KREAL KLOGICAL KCHARACTER KPARAMETER KDIMENSION KLEN KRESULT IMPLICITNONE
%token KIF KTHEN KELSE ELSEIF ENDIF KDO DOWHILE ENDDO SELECTCASE KCASE CASEDEFAULT ENDSELECT
%token KCALL KRETURN KSTOP KEXIT KCYCLE KPRINT KREAD
%token TRUE FALSE POW CONCAT DCOLON EQ NE LT LE GT GE AND OR NOT
%left OR
%left AND
%right NOT
%nonassoc EQ NE LT LE GT GE
%left CONCAT
%left '+' '-'
%left '*' '/'
%right POW
%right UMINUS
%%
program : units ;
units   : | units unit | units EOL ;
unit    : prog | sub | func ;

prog    : phead body endu      { emit_unit(); } ;
phead   : KPROGRAM NAME EOL     { begin_unit((char *)$2, 0, T_VOID); } ;
sub     : subhead body endu     { emit_unit(); } ;
subhead : KSUBROUTINE NAME EOL                 { begin_unit((char *)$2, 1, T_VOID); }
        | KSUBROUTINE NAME '(' arglist ')' EOL { begin_unit((char *)$2, 1, T_VOID); } ;
func    : funchead body endu    { emit_unit(); } ;
funchead: typ KFUNCTION NAME '(' arglist ')' EOL  { begin_unit((char *)$3, 2, $1); } ;
endu    : KEND EOL | KEND NAME EOL | ENDPROG optn EOL | ENDSUB optn EOL | ENDFUNC optn EOL ;
optn    : | NAME ;
arglist : | argnames ;
argnames: NAME              { g_argnm[g_argn++] = (char *)$1; }
        | argnames ',' NAME { g_argnm[g_argn++] = (char *)$3; } ;

body    : | body bstmt ;
bstmt   : EOL | decl EOL | exec EOL ;

decl    : IMPLICITNONE
        | typ DCOLON declist
        | typ ',' KPARAMETER DCOLON { g_dparam = 1; } declist
        | typ declist ;
typ     : KINTEGER             { declstart(); g_dty = T_INT; $$ = T_INT; }
        | KREAL                { declstart(); g_dty = T_REAL; $$ = T_REAL; }
        | KLOGICAL             { declstart(); g_dty = T_LOG; $$ = T_LOG; }
        | KCHARACTER charlen   { declstart(); g_dty = T_CHR; $$ = T_CHR; } ;
charlen : { g_charlen = 255; } | '(' KLEN '=' INTLIT ')' { g_charlen = $4; } | '(' INTLIT ')' { g_charlen = $2; } ;
declist : declitem | declist ',' declitem ;
declitem: NAME arrspec initopt { declvar((char *)$1, $2, $3); } ;
arrspec : { $$ = 0; } | adlp dims ')' { $$ = 1; } ;
adlp    : '(' { g_dnd = 0; g_dlo1 = 1; g_dn1 = 0; g_dlo2 = 0; g_dn2 = 0; } ;
dims    : dim | dims ',' dim ;
dim     : INTLIT            { decldim(1, $1); }
        | INTLIT ':' INTLIT { decldim($1, $3 - $1 + 1); } ;
initopt : { $$ = 0; } | '=' expr { $$ = $2; } ;

exec    : lvalue '=' expr                  { do_assign($1, $3); }
        | KCALL NAME '(' callargs ')'      { do_call((char *)$2, $4); }
        | KCALL NAME                       { if (g_pass == 2) ap(F1("f_%s();\n", (char *)$2)); }
        | KPRINT '*' ',' printlist         { if (g_pass == 2) ap("printf(\"\\n\");\n"); }
        | KPRINT '*'                       { if (g_pass == 2) ap("printf(\"\\n\");\n"); }
        | KREAD '*' ',' readlist
        | KRETURN                          { if (g_pass == 2) ap(g_ukind == 2 ? "return __ret;\n" : "return;\n"); }
        | KSTOP                            { if (g_pass == 2) ap("exit(0);\n"); }
        | KEXIT                            { if (g_pass == 2) ap("break;\n"); }
        | KCYCLE                           { if (g_pass == 2) ap("continue;\n"); }
        | ifstmt | dostmt | selstmt ;

printlist : pitem | printlist ',' pitem ;
pitem   : expr { if (g_pass == 2) { int t = etype($1); if (t == T_CHR) ap(F1("printf(\"%%s\", %s);\n", ecode($1))); else if (t == T_REAL) ap(F1("printf(\" %%g\", %s);\n", ecode($1))); else if (t == T_LOG) ap(F1("printf((%s)?\" T\":\" F\");\n", ecode($1))); else ap(F1("printf(\" %%d\", %s);\n", ecode($1))); } } ;
readlist : ritem | readlist ',' ritem ;
ritem   : lvalue { if (g_pass == 2) { int t = etype($1); ap(F1((t == T_REAL) ? "scanf((int)\"%%lf\", (int)&%s);\n" : "scanf((int)\"%%d\", (int)&%s);\n", ecode($1))); } } ;

ifstmt  : ifhead body ifrest ;
ifhead  : KIF '(' expr ')' KTHEN EOL  { g_lstk[g_lsp++] = g_lbl++; if (g_pass == 2) ap(F1("if (%s) {\n", ecode($3))); } ;
ifrest  : ENDIF                       { g_lsp--; if (g_pass == 2) ap("}\n"); }
        | elsekw body ENDIF           { g_lsp--; if (g_pass == 2) ap("}\n"); }
        | elifhead body ifrest ;
elsekw  : KELSE EOL                   { if (g_pass == 2) ap("} else {\n"); } ;
elifhead: ELSEIF '(' expr ')' KTHEN EOL { if (g_pass == 2) ap(F1("} else if (%s) {\n", ecode($3))); } ;

dostmt  : dohead body ENDDO          { g_lsp--; if (g_pass == 2) ap("}\n"); } ;
dohead  : KDO NAME '=' expr ',' expr EOL
          { g_lstk[g_lsp++] = g_lbl++; if (g_pass == 2) { char *v = vlookup((char *)$2); ap(j3("for (", v, " = ")); ap(ecode($4)); ap(j3("; ", v, " <= (")); ap(ecode($6)); ap(j3("); ", v, " += 1) {\n")); } }
        | KDO NAME '=' expr ',' expr ',' expr EOL
          { g_lstk[g_lsp++] = g_lbl++; if (g_pass == 2) { char *v = vlookup((char *)$2); char *st = ecode($8); ap(j3("for (", v, " = ")); ap(ecode($4)); ap(j3("; ((", st, ")>=0)?(")); ap(v); ap(j3(" <= (", ecode($6), ")):(")); ap(v); ap(j3(" >= (", ecode($6), "))); ")); ap(j3(v, " += (", st)); ap(")) {\n"); } }
        | DOWHILE '(' expr ')' EOL
          { g_lstk[g_lsp++] = g_lbl++; if (g_pass == 2) ap(F1("while (%s) {\n", ecode($3))); } ;

selstmt : selhead cases ENDSELECT    { if (g_pass == 2) ap("} }\n"); } ;
selhead : SELECTCASE '(' expr ')' EOL { if (g_pass == 2) ap(F1("{ int __sel = %s; if (0) {\n", ecode($3))); } ;
cases   : | cases onecase ;
onecase : KCASE caseopen '(' caselist ')' caseterm EOL casebody
        | CASEDEFAULT defopen EOL casebody ;
caseopen: { if (g_pass == 2) ap("} else if ("); } ;
caseterm: { if (g_pass == 2) ap(") {\n"); } ;
defopen : { if (g_pass == 2) ap("} else {\n"); } ;
caselist: caseval | caselist ',' casesep caseval ;
casesep : { if (g_pass == 2) ap(" || "); } ;
caseval : expr { if (g_pass == 2) ap(F1("__sel == (%s)", ecode($1))); } ;
casebody: | casebody bstmt ;

lvalue  : NAME                    { $$ = name_ref((char *)$1, 0, 0); }
        | NAME '(' callargs ')'   { $$ = name_ref((char *)$1, $3, 1); } ;

expr    : expr '+' expr   { $$ = bin($1, "+", $3); }
        | expr '-' expr   { $$ = bin($1, "-", $3); }
        | expr '*' expr   { $$ = bin($1, "*", $3); }
        | expr '/' expr   { $$ = bin($1, "/", $3); }
        | expr POW expr   { $$ = mkE(F2("pow((double)(%s),(double)(%s))", ecode($1), ecode($3)), (etype($1) == T_REAL || etype($3) == T_REAL) ? T_REAL : T_INT); }
        | expr CONCAT expr { $$ = mkE(F2("__fcat(%s, %s)", ecode($1), ecode($3)), T_CHR); }
        | expr EQ expr    { $$ = bin($1, "==", $3); }
        | expr NE expr    { $$ = bin($1, "!=", $3); }
        | expr LT expr    { $$ = bin($1, "<", $3); }
        | expr LE expr    { $$ = bin($1, "<=", $3); }
        | expr GT expr    { $$ = bin($1, ">", $3); }
        | expr GE expr    { $$ = bin($1, ">=", $3); }
        | expr AND expr   { $$ = mkE(F2("(%s && %s)", ecode($1), ecode($3)), T_LOG); }
        | expr OR expr    { $$ = mkE(F2("(%s || %s)", ecode($1), ecode($3)), T_LOG); }
        | NOT expr        { $$ = mkE(F1("(!%s)", ecode($2)), T_LOG); }
        | '-' expr %prec UMINUS  { $$ = mkE(F1("(-%s)", ecode($2)), etype($2)); }
        | '(' expr ')'    { $$ = mkE(F1("(%s)", ecode($2)), etype($2)); }
        | INTLIT          { $$ = mkE(istr($1), T_INT); }
        | REALLIT         { $$ = mkE((char *)$1, T_REAL); }
        | STRLIT          { $$ = mkE(cstr((char *)$1), T_CHR); }
        | TRUE            { $$ = mkE("1", T_LOG); }
        | FALSE           { $$ = mkE("0", T_LOG); }
        | NAME            { $$ = name_ref((char *)$1, 0, 0); }
        | NAME '(' callargs ')'  { $$ = name_ref((char *)$1, $3, 1); }
        | KREAL '(' expr ')'     { $$ = mkE(F1("((double)(%s))", ecode($3)), T_REAL); } ;

callargs : { $$ = ag_new(); } | arglist2 { $$ = $1; } ;
arglist2 : expr            { $$ = ag_add(ag_new(), $1); }
         | arglist2 ',' expr { $$ = ag_add($1, $3); } ;
%%

void yyerror(char *m) { fputs((int)"fortran: ", (int)2); fputs((int)m, (int)2); fputs((int)"\n", (int)2); }

void declstart() { g_dparam = 0; g_dnd = 0; g_dlo1 = 1; g_dn1 = 0; g_dlo2 = 0; g_dn2 = 0; }
void decldim(int lo, int n) { if (g_dnd == 0) { g_dlo1 = lo; g_dn1 = n; } else { g_dlo2 = lo; g_dn2 = n; } g_dnd++; }
void declvar(char *nm, int arr, int init)
{
    int idx = nsv;
    sv_name[nsv] = nm; sv_ty[nsv] = g_dty; sv_isarr[nsv] = arr; sv_lo1[nsv] = arr ? g_dlo1 : 0; sv_n1[nsv] = arr ? g_dn1 : 0;
    sv_lo2[nsv] = (arr && g_dnd > 1) ? g_dlo2 : 0; sv_n2[nsv] = (arr && g_dnd > 1) ? g_dn2 : 0;
    sv_kind[nsv] = is_arg(nm) ? ((g_ukind == 1) ? K_PREF : K_PVAL) : K_LOCAL;
    int kind = sv_kind[nsv]; int t = g_dty; nsv++;
    g_dnd = 0;
    if (g_pass != 2 || kind != K_LOCAL) return;
    char *cn = j2("v_", nm);
    if (arr)
    {
        if (sv_n2[idx] > 0) g_decls = j2(g_decls, j3(ctype(t), " ", j3(cn, F1("[%s]", istr(sv_n1[idx])), F1("[%s];\n", istr(sv_n2[idx])))));
        else g_decls = j2(g_decls, j3(ctype(t), " ", j2(cn, F1("[%s];\n", istr(sv_n1[idx])))));
    }
    else if (t == T_CHR) g_decls = j2(g_decls, j3("char ", cn, F1("[%s];\n", istr(g_charlen + 1))));
    else g_decls = j2(g_decls, j4(ctype(t), " ", cn, " = 0;\n"));
    if (init) { if (t == T_CHR) ap(F2("strcpy(%s, %s);\n", cn, ecode(init))); else ap(F2("%s = %s;\n", cn, ecode(init))); }
}

char *vlookup(char *nm) { int i = sv_find(nm); if (i >= 0) return vref(j2("v_", nm), sv_kind[i]); return j2("v_", nm); }

int bin(int a, char *op, int b)
{
    int at = etype(a), bt = etype(b);
    int arith = (strcmp(op, "+") == 0 || strcmp(op, "-") == 0 || strcmp(op, "*") == 0 || strcmp(op, "/") == 0);
    int rt = (at == T_REAL || bt == T_REAL) ? T_REAL : T_INT;
    char *la = ecode(a), *lb = ecode(b);
    if (rt == T_REAL) { if (at == T_INT) la = F1("(double)(%s)", la); if (bt == T_INT) lb = F1("(double)(%s)", lb); }
    return mkE(j2("(", j4(la, op, lb, ")")), arith ? rt : T_LOG);
}

int isintrin(char *n) { return strcmp(n, "mod") == 0 || strcmp(n, "abs") == 0 || strcmp(n, "sqrt") == 0 || strcmp(n, "sin") == 0 || strcmp(n, "cos") == 0 || strcmp(n, "exp") == 0 || strcmp(n, "log") == 0 || strcmp(n, "real") == 0 || strcmp(n, "int") == 0 || strcmp(n, "max") == 0 || strcmp(n, "min") == 0 || strcmp(n, "len") == 0; }

int intrin(char *nm, struct AG *g)
{
    char *a0 = (g->n > 0) ? ecode(g->a[0]) : "0"; char *a1 = (g->n > 1) ? ecode(g->a[1]) : "0";
    int t0 = (g->n > 0) ? etype(g->a[0]) : T_INT;
    if (strcmp(nm, "mod") == 0) return mkE(F2("(%s %% %s)", a0, a1), T_INT);
    if (strcmp(nm, "abs") == 0) return (t0 == T_REAL) ? mkE(F1("fabs(%s)", a0), T_REAL) : mkE(F1("abs(%s)", a0), T_INT);
    if (strcmp(nm, "sqrt") == 0) return mkE(F1("sqrt((double)(%s))", a0), T_REAL);
    if (strcmp(nm, "sin") == 0) return mkE(F1("sin((double)(%s))", a0), T_REAL);
    if (strcmp(nm, "cos") == 0) return mkE(F1("cos((double)(%s))", a0), T_REAL);
    if (strcmp(nm, "exp") == 0) return mkE(F1("exp((double)(%s))", a0), T_REAL);
    if (strcmp(nm, "log") == 0) return mkE(F1("log((double)(%s))", a0), T_REAL);
    if (strcmp(nm, "real") == 0) return mkE(F1("((double)(%s))", a0), T_REAL);
    if (strcmp(nm, "int") == 0) return mkE(F1("((int)(%s))", a0), T_INT);
    if (strcmp(nm, "len") == 0) return mkE(F1("((int)strlen(%s))", a0), T_INT);
    if (strcmp(nm, "max") == 0) { int rt = (etype(g->a[0]) == T_REAL || etype(g->a[1]) == T_REAL) ? T_REAL : T_INT; return mkE(j2("(", j4(a0, ">", a1, j4("?", a0, ":", j2(a1, ")")))), rt); }
    if (strcmp(nm, "min") == 0) { int rt = (etype(g->a[0]) == T_REAL || etype(g->a[1]) == T_REAL) ? T_REAL : T_INT; return mkE(j2("(", j4(a0, "<", a1, j4("?", a0, ":", j2(a1, ")")))), rt); }
    return mkE("0", T_INT);
}

/* a NAME, NAME(args): variable, array element, intrinsic, or user function */
int name_ref(char *nm, int agh, int hasp)
{
    if (g_ukind == 2 && !hasp && strcmp(nm, g_uname) == 0) return mkE("__ret", g_uret);
    int si = sv_find(nm);
    if (!hasp)
    {
        if (si < 0) return mkLV(j2("v_", nm), T_INT);
        return mkLV(vref(j2("v_", nm), sv_kind[si]), sv_ty[si]);
    }
    struct AG *g = (struct AG *)agh;
    if (si >= 0 && sv_isarr[si])
    {
        char *cn = j2("v_", nm);
        if (sv_n2[si] > 0) return mkLV(j2(cn, j2(j4("[(", ecode(g->a[0]), ") - ", j2(istr(sv_lo1[si]), "]")), j4("[(", ecode(g->a[1]), ") - ", j2(istr(sv_lo2[si]), "]")))), sv_ty[si]);
        return mkLV(j2(cn, j4("[(", ecode(g->a[0]), ") - ", j2(istr(sv_lo1[si]), "]"))), sv_ty[si]);
    }
    if (isintrin(nm)) return intrin(nm, g);
    int fi = fn_find(nm); int rt = (fi >= 0) ? fn_ret[fi] : T_INT;
    char *args = ""; int i;
    for (i = 0; i < g->n; i++) { char *c = ecode(g->a[i]); int at = etype(g->a[i]); int pt = (fi >= 0 && i < fn_np[fi]) ? fn_pty[fi][i] : at; if (pt == T_REAL && at == T_INT) c = F1("(double)(%s)", c); args = (i == 0) ? c : j3(args, ", ", c); }
    return mkE(F2("f_%s(%s)", nm, args), rt);
}

void do_assign(int lv, int rv)
{
    if (g_pass != 2) return;
    int lt = etype(lv); char *rc = ecode(rv);
    if (lt == T_REAL && etype(rv) == T_INT) rc = F1("(double)(%s)", rc);
    if (lt == T_CHR) ap(F2("strcpy(%s, %s);\n", ecode(lv), rc));
    else ap(F2("%s = %s;\n", ecode(lv), rc));
}
void do_call(char *nm, int agh)
{
    if (g_pass != 2) return;
    struct AG *g = (struct AG *)agh; int fi = fn_find(nm); char *args = ""; int i;
    for (i = 0; i < g->n; i++)
    {
        int at = etype(g->a[i]); int pt = (fi >= 0 && i < fn_np[fi]) ? fn_pty[fi][i] : at;
        char *c = ecode(g->a[i]); char *aref;
        if (elval(g->a[i]) && at == pt) aref = F1("&(%s)", c);          /* a real variable: address it so writes propagate */
        else                                                            /* literal/expression: stage in a temp */
        {
            if (pt == T_REAL && at == T_INT) c = F1("(double)(%s)", c);
            char *tn = j2("__tc", istr(g_ntmp++));
            g_decls = j2(g_decls, j3(ctype(pt), " ", j2(tn, ";\n")));
            ap(F2("%s = %s;\n", tn, c)); aref = j2("&", tn);
        }
        args = (i == 0) ? aref : j3(args, ", ", aref);
    }
    ap(F2("f_%s(%s);\n", nm, args));
}

void begin_unit(char *nm, int kind, int ret)
{
    g_uname = nm; g_ukind = kind; g_uret = ret; nsv = 0; g_decls = ""; g_code = ""; g_lsp = 0; g_ntmp = 0;
    if (kind == 0) g_argn = 0;
}
char *param_sig()
{
    char *s = ""; int i;
    for (i = 0; i < g_argn; i++)
    {
        int si = sv_find(g_argnm[i]); int t = (si >= 0) ? sv_ty[si] : T_INT; int arr = (si >= 0) ? sv_isarr[si] : 0;
        char *cn = j2("v_", g_argnm[i]);
        char *p = (g_ukind == 1 || arr) ? j3(ctype(t), "* ", cn) : j3(ctype(t), " ", cn);
        s = (i == 0) ? p : j3(s, ", ", p);
    }
    return s;
}
void emit_unit()
{
    if (g_pass == 1)
    {
        int p = nfn; fn_name[p] = g_uname; fn_issub[p] = (g_ukind == 1); fn_ret[p] = g_uret; fn_np[p] = g_argn;
        int i; for (i = 0; i < g_argn; i++) { int si = sv_find(g_argnm[i]); fn_pty[p][i] = (si >= 0) ? sv_ty[si] : T_INT; }
        nfn++; g_argn = 0; return;
    }
    char *sig = param_sig();
    if (g_ukind == 0) g_out = j2(g_out, j3("int main(int argc, char** argv) {\n", g_decls, j2(g_code, "return 0;\n}\n")));
    else if (g_ukind == 1) g_out = j2(g_out, j3(j4("void f_", g_uname, "(", sig), ") {\n", j3(g_decls, g_code, "}\n")));
    else { char *ct = ctype(g_uret); g_out = j2(g_out, j3(j4(ct, " f_", g_uname, "("), sig, j3(") {\n", j3(ct, " __ret = 0;\n", g_decls), j2(g_code, "return __ret;\n}\n")))); }
    g_argn = 0;
}

char *PRELUDE = "char* __fcat(char*a,char*b){char*r=(char*)malloc(strlen(a)+strlen(b)+1);strcpy(r,a);strcat(r,b);return r;}\n";

void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: fortran <file.f90> [-o out] [--dll]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], cpath[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, "exe"); }
    strcpy(cpath, outp); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"fortran: cannot read %s\n", (int)in); return 1; }
    g_pass = 1; g_argn = 0; yy_scan_string((int)src); yyparse();
    g_pass = 2; pline = 1; g_argn = 0; g_out = ""; yy_scan_string((int)src); yyparse();
    int f = fopen((int)cpath, (int)"w"); fputs((int)PRELUDE, f); fputs((int)g_out, f); fclose(f);
    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; char icon[1100]; int n = 0; sprintf((int)icon, (int)"%s\\icons\\fortran.png", (int)repo);
    av[n++] = (int)cc; av[n++] = (int)cpath; av[n++] = (int)"-o"; av[n++] = (int)outp; av[n++] = dll ? (int)"--dll" : (int)"--exe"; av[n++] = (int)"--icon"; av[n++] = (int)icon;
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"fortran: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"fortran: cc failed (%d)\n", rc);
    return rc;
}
