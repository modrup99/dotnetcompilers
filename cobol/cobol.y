%{
/* A free-format COBOL subset -> C (yacc); cc lowers the C to .NET IL. The four
 * divisions map cleanly: PROGRAM-ID names the program, WORKING-STORAGE builds the data,
 * PROCEDURE DIVISION becomes the code. Each paragraph is emitted as a C function;
 * main() calls them in source order, so a STOP RUN that halts before fall-through
 * behaves like real COBOL. Two passes: pass 1 registers data items + paragraph names
 * (so PERFORM can see a paragraph defined later); pass 2 emits the C. Our yacc has no
 * mid-rule actions, so ordering is threaded through empty marker non-terminals that
 * read the inherited $0. */

#define C_GROUP 0
#define C_NUM 1
#define C_DEC 2
#define C_ALNUM 3
#define C_EDIT 4
#define C_88 5
#define T_INT 1
#define T_REAL 2
#define T_STR 3
#define T_LOG 4

int g_pass;
char *g_out, *g_data, *g_inits;
int g_movesrc;
char *g_pv, *g_pfrom, *g_pby;
char *g_dc_pic; int g_dc_hasval; int g_dc_val; int g_dc_occ; int g_dc_thru; int g_dc_hasthru;
int g_pcls, g_pdig, g_pdec, g_plen; char *g_pedit;
char *g_lastvar; int g_lastcls;

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 16); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 16); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *Fi(char *f, int n) { char *r = (char *)malloc(strlen(f) + 24); sprintf((int)r, (int)f, n); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
void ap(char *s) { if (g_pass == 2) g_out = j2(g_out, s); }
void apd(char *s) { if (g_pass == 2) g_data = j2(g_data, s); }

struct E { char *code; int ty; int lval; int cls; int dig; int dec; char *edit; };
int mkE(char *c, int t) { struct E *e = (struct E *)malloc(28); e->code = c; e->ty = t; e->lval = 0; e->cls = -1; e->dig = 0; e->dec = 0; e->edit = ""; return (int)e; }
char *ecode(int h) { return ((struct E *)h)->code; }
int etype(int h) { return ((struct E *)h)->ty; }
int ecls(int h) { return ((struct E *)h)->cls; }
int edig(int h) { return ((struct E *)h)->dig; }
int edec(int h) { return ((struct E *)h)->dec; }
char *eedit(int h) { return ((struct E *)h)->edit; }
char *cstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"'; while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; r[j++] = s[i++]; } r[j++] = '"'; r[j] = 0; return r; }
char *cvar(char *nm) { char *r = (char *)malloc(strlen(nm) + 4); strcpy(r, "v_"); int i = 0, j = 2; while (nm[i]) { r[j++] = (nm[i] == '-') ? '_' : nm[i]; i++; } r[j] = 0; return r; }

char *sy_name[4000]; int sy_cls[4000]; int sy_dig[4000]; int sy_dec[4000]; int sy_len[4000]; int sy_occ[4000]; char *sy_edit[4000]; char *sy_cond[4000]; int nsy;
int sy_find(char *n) { int i; for (i = nsy - 1; i >= 0; i--) if (strcmp(sy_name[i], n) == 0) return i; return -1; }
char *par_cn[2000]; int npar;
int cls2ty(int c) { if (c == C_NUM) return T_INT; if (c == C_DEC) return T_REAL; return T_STR; }

void parse_pic(char *p)
{
    int i = 0, nine = 0, x = 0, dec = 0, sawv = 0, edit = 0, width = 0; char prev = 0;
    char exp[256]; int e = 0;
    while (p[i])
    {
        char c = p[i];
        if (c >= 'a' && c <= 'z') c = c - 32;
        if (c == '(') { int k = 0; i++; while (p[i] && p[i] != ')') { k = k * 10 + (p[i] - '0'); i++; } int r; for (r = 1; r < k; r++) { if (e < 250) exp[e++] = prev; } i++; continue; }
        if (e < 250) exp[e++] = c; prev = c; i++;
    }
    exp[e] = 0;
    for (i = 0; i < e; i++)
    {
        char c = exp[i];
        if (c == 'X' || c == 'A') { x++; width++; }
        else if (c == '9') { if (sawv) dec++; else nine++; width++; }
        else if (c == 'V') sawv = 1;
        else if (c == 'Z' || c == '*') { edit = 1; if (sawv) dec++; else nine++; width++; }
        else if (c == '$' || c == ',' || c == '-' || c == '+' || c == 'B' || c == '/') { edit = 1; width++; }
        else if (c == '.') { edit = 1; width++; sawv = 1; }
    }
    g_pdig = nine; g_pdec = dec; g_plen = width; g_pedit = (char *)strdup((int)exp);
    if (x > 0) { g_pcls = C_ALNUM; g_plen = x; }
    else if (edit) g_pcls = C_EDIT;
    else if (dec > 0) g_pcls = C_DEC;
    else g_pcls = C_NUM;
}

int yylex(); void yyerror(char *m);
int bin(int a, char *op, int b); int cmp(int a, char *op, int b);
int name_ref(char *nm); int name_idx(char *nm, int ix);
int ag1(int e); int agA(int h, int e); char *ag_sum(int h);
void def_item(int level, char *nm);
void do_display(int e); void do_move_t(int dst); void do_assign(int dst, int src);
void do_addsub(int srch, int dst, char *op, int give); void do_muldiv(int src, int dst, char *op, int give);
void do_accept(int dst); void do_perf_times(char *nm, int n); void do_perf_vary(char *nm, int v, int from, int by, int cnd);
void proc_start(); void new_para(char *nm); void proc_end();
%}
%token NAME INTLIT REALLIT STRLIT PERIOD PICTURE
%token KIDENT KDIVISION KPROGRAMID KENVIRONMENT KCONFIG KDATA KWORKING KLINKAGE KSECTION KPROCEDURE
%token KIS KVALUE KOCCURS KTIMES KDISPLAY KACCEPT KMOVE KTO KFROM KGIVING KADD KSUBTRACT KMULTIPLY KDIVIDE KINTO KBY KCOMPUTE KROUNDED
%token KIF KTHEN KELSE KENDIF KPERFORM KENDPERF KUNTIL KVARYING KEVALUATE KWHEN KOTHER KENDEVAL
%token KSTOP KRUN KGOBACK KGO KNOT KAND KOR KEQUAL KGREATER KLESS KTHAN KTHRU KZERO KSPACES KCONTINUE
%token KGE KLE KNE POW
%left KOR
%left KAND
%right KNOT
%left '+' '-'
%left '*' '/'
%right POW
%right UMINUS
%%
program : ident_div env_opt data_opt proc_div ;

ident_div : KIDENT KDIVISION PERIOD KPROGRAMID PERIOD NAME PERIOD ;
env_opt   : | KENVIRONMENT KDIVISION PERIOD ;

data_opt  : | KDATA KDIVISION PERIOD ws_opt ;
ws_opt    : | KWORKING KSECTION PERIOD ditems ;
ditems    : | ditems ditem ;
ditem     : INTLIT NAME dclauses PERIOD   { def_item($1, (char *)$2); }
          | INTLIT NAME PERIOD            { def_item($1, (char *)$2); } ;
dclauses  : dclause | dclauses dclause ;
dclause   : PICTURE              { g_dc_pic = (char *)$1; }
          | KVALUE val           { g_dc_val = $2; g_dc_hasval = 1; }
          | KVALUE KIS val       { g_dc_val = $3; g_dc_hasval = 1; }
          | KOCCURS INTLIT       { g_dc_occ = $2; }
          | KOCCURS INTLIT KTIMES { g_dc_occ = $2; }
          | KTHRU val            { g_dc_thru = $2; g_dc_hasthru = 1; } ;
val       : INTLIT     { $$ = mkE(istr($1), T_INT); }
          | REALLIT    { $$ = mkE((char *)$1, T_REAL); }
          | '-' INTLIT { $$ = mkE(F1("-%s", istr($2)), T_INT); }
          | STRLIT     { $$ = mkE(cstr((char *)$1), T_STR); }
          | KZERO      { $$ = mkE("0", T_INT); }
          | KSPACES    { $$ = mkE("\" \"", T_STR); } ;

proc_div  : KPROCEDURE KDIVISION PERIOD pstart pbody { proc_end(); } ;
pstart    : { proc_start(); } ;
pbody     : sents pars ;
sents     : | sents sentence ;
pars      : | pars paragraph ;
paragraph : pghead sents ;
pghead    : NAME PERIOD          { new_para((char *)$1); } ;
sentence  : bstmts PERIOD ;
bstmts    : | bstmts stmt ;

stmt : KDISPLAY dlist                                { if (g_pass == 2) ap("printf(\"\\n\");\n"); }
     | KMOVE expr setmv KTO tlist
     | KADD elist KTO target give                    { do_addsub($2, $4, "+", $5); }
     | KSUBTRACT elist KFROM target give             { do_addsub($2, $4, "-", $5); }
     | KMULTIPLY expr KBY target give                { do_muldiv($2, $4, "*", $5); }
     | KDIVIDE expr KINTO target give                { do_muldiv($2, $4, "/", $5); }
     | KDIVIDE expr KBY expr KGIVING target          { do_assign($6, bin($2, "/", $4)); }
     | KCOMPUTE target round '=' expr                { do_assign($2, $5); }
     | KACCEPT target                                { do_accept($2); }
     | KSTOP KRUN                                     { if (g_pass == 2) ap("exit(0);\n"); }
     | KGOBACK                                        { if (g_pass == 2) ap("exit(0);\n"); }
     | KCONTINUE
     | KGO KTO NAME                                   { if (g_pass == 2) ap(F1("pg_%s();\n", cvar((char *)$3) + 2)); }
     | KPERFORM perf
     | ifstmt
     | evalstmt ;

setmv : { g_movesrc = $0; } ;
dlist : ditem_d | dlist ditem_d ;
ditem_d : expr { do_display($1); } ;
tlist : target { do_move_t($1); } | tlist target { do_move_t($1); } ;
target : NAME              { $$ = name_ref((char *)$1); }
       | NAME '(' expr ')' { $$ = name_idx((char *)$1, $3); } ;
elist : expr { $$ = ag1($1); } | elist expr { $$ = agA($1, $2); } ;
give  : { $$ = 0; } | KGIVING target { $$ = $2; } ;
round : | KROUNDED ;

ifstmt : KIF cond ift thenopt bstmts iftail ;
ift    : { if (g_pass == 2) ap(F1("if (%s) {\n", ecode($0))); } ;
thenopt: | KTHEN ;
iftail : KENDIF                  { if (g_pass == 2) ap("}\n"); }
       | ifelse bstmts KENDIF    { if (g_pass == 2) ap("}\n"); } ;
ifelse : KELSE                   { if (g_pass == 2) ap("} else {\n"); } ;

evalstmt : KEVALUATE expr evbeg whens evdef KENDEVAL { if (g_pass == 2) ap("} }\n"); } ;
evbeg  : { if (g_pass == 2) ap(F1("{ int __ev = %s; if (0) {\n", ecode($0))); } ;
whens  : | whens onewhen ;
onewhen: KWHEN val wopen bstmts ;
wopen  : { if (g_pass == 2) ap(F1("} else if (__ev == %s) {\n", ecode($0))); } ;
evdef  : | KWHEN KOTHER wdef bstmts ;
wdef   : { if (g_pass == 2) ap("} else {\n"); } ;

perf : NAME                                              { if (g_pass == 2) ap(F1("pg_%s();\n", cvar((char *)$1) + 2)); }
     | NAME INTLIT KTIMES                                { do_perf_times((char *)$1, $2); }
     | NAME KUNTIL cond                                  { if (g_pass == 2) ap(F2("while (!(%s)) pg_%s();\n", ecode($3), cvar((char *)$1) + 2)); }
     | NAME KVARYING target KFROM expr KBY expr KUNTIL cond { do_perf_vary((char *)$1, $3, $5, $7, $9); }
     | KUNTIL cond pu bstmts KENDPERF                    { if (g_pass == 2) ap("}\n"); }
     | INTLIT pt KTIMES bstmts KENDPERF                  { if (g_pass == 2) ap("} }\n"); }
     | KVARYING target vset KFROM expr vfrom KBY expr vby KUNTIL cond vstart bstmts KENDPERF { if (g_pass == 2) ap(F2("%s += (%s); }\n", g_pv, g_pby)); } ;
pu   : { if (g_pass == 2) ap(F1("while (!(%s)) {\n", ecode($0))); } ;
pt   : { if (g_pass == 2) ap(Fi("{ int __t; for (__t=0; __t<%d; __t++) {\n", $0)); } ;
vset : { g_pv = ecode($0); } ;
vfrom: { g_pfrom = ecode($0); } ;
vby  : { g_pby = ecode($0); } ;
vstart: { if (g_pass == 2) ap(j2(F2("%s = (%s);\n", g_pv, g_pfrom), F1("while (!(%s)) {\n", ecode($0)))); } ;

cond : cond KOR cond2   { $$ = mkE(F2("(%s || %s)", ecode($1), ecode($3)), T_LOG); } | cond2 { $$ = $1; } ;
cond2: cond2 KAND cond3 { $$ = mkE(F2("(%s && %s)", ecode($1), ecode($3)), T_LOG); } | cond3 { $$ = $1; } ;
cond3: KNOT cond3       { $$ = mkE(F1("(!%s)", ecode($2)), T_LOG); } | '(' cond ')' { $$ = $2; } | rel { $$ = $1; } ;
rel  : expr relop expr  { $$ = cmp($1, (char *)$2, $3); }
     | expr             { $$ = mkE(ecode($1), T_LOG); } ;
relop: '='            { $$ = (int)"=="; }
     | KEQUAL         { $$ = (int)"=="; }
     | KEQUAL KTO     { $$ = (int)"=="; }
     | '<'            { $$ = (int)"<"; }
     | '>'            { $$ = (int)">"; }
     | KGE            { $$ = (int)">="; }
     | KLE            { $$ = (int)"<="; }
     | KNE            { $$ = (int)"!="; }
     | KGREATER       { $$ = (int)">"; }
     | KGREATER KTHAN { $$ = (int)">"; }
     | KLESS          { $$ = (int)"<"; }
     | KLESS KTHAN    { $$ = (int)"<"; }
     | KNOT '='       { $$ = (int)"!="; }
     | KNOT KEQUAL    { $$ = (int)"!="; } ;

expr : expr '+' expr   { $$ = bin($1, "+", $3); }
     | expr '-' expr   { $$ = bin($1, "-", $3); }
     | expr '*' expr   { $$ = bin($1, "*", $3); }
     | expr '/' expr   { $$ = bin($1, "/", $3); }
     | expr POW expr   { $$ = mkE(F2("pow((double)(%s),(double)(%s))", ecode($1), ecode($3)), T_REAL); }
     | '-' expr %prec UMINUS { $$ = mkE(F1("(-%s)", ecode($2)), etype($2)); }
     | '(' expr ')'    { $$ = mkE(F1("(%s)", ecode($2)), etype($2)); }
     | INTLIT          { $$ = mkE(istr($1), T_INT); }
     | REALLIT         { $$ = mkE((char *)$1, T_REAL); }
     | STRLIT          { $$ = mkE(cstr((char *)$1), T_STR); }
     | KZERO           { $$ = mkE("0", T_INT); }
     | KSPACES         { $$ = mkE("\" \"", T_STR); }
     | NAME            { $$ = name_ref((char *)$1); }
     | NAME '(' expr ')' { $$ = name_idx((char *)$1, $3); } ;
%%

void yyerror(char *m) { printf((int)"cobol: %s (line %d)\n", (int)m, pline); }

void dc_reset() { g_dc_pic = 0; g_dc_hasval = 0; g_dc_occ = 0; g_dc_hasthru = 0; }

void def_item(int level, char *nm)
{
    if (level == 88)
    {
        char *cond;
        if (g_dc_hasthru) cond = j4("(", g_lastvar, F2(" >= %s && %s", ecode(g_dc_val), g_lastvar), F1(" <= %s)", ecode(g_dc_thru)));
        else if (g_lastcls == C_ALNUM || g_lastcls == C_EDIT) cond = F2("(strcmp(%s, %s) == 0)", g_lastvar, ecode(g_dc_val));
        else cond = F2("(%s == %s)", g_lastvar, ecode(g_dc_val));
        sy_name[nsy] = nm; sy_cls[nsy] = C_88; sy_cond[nsy] = cond; sy_occ[nsy] = 0; nsy++;
        dc_reset(); return;
    }
    int cls = C_GROUP, dig = 0, dec = 0, len = 0; char *edit = "";
    if (g_dc_pic) { parse_pic(g_dc_pic); cls = g_pcls; dig = g_pdig; dec = g_pdec; len = g_plen; edit = g_pedit; }
    int occ = g_dc_occ;
    sy_name[nsy] = nm; sy_cls[nsy] = cls; sy_dig[nsy] = dig; sy_dec[nsy] = dec; sy_len[nsy] = len; sy_occ[nsy] = occ; sy_edit[nsy] = edit; nsy++;
    if (cls != C_GROUP) { g_lastvar = cvar(nm); g_lastcls = cls; }
    if (g_pass == 2 && cls != C_GROUP)
    {
        char *cn = cvar(nm); char *decl;
        if (cls == C_NUM || cls == C_DEC)
        {
            char *t = (cls == C_NUM) ? "int " : "double ";
            decl = (occ > 0) ? j2(j3(t, cn, ""), Fi("[%d];\n", occ)) : j2(j3(t, cn, ""), ";\n");
        }
        else
        {
            decl = (occ > 0) ? j2(j3("char ", cn, ""), j2(Fi("[%d]", occ), Fi("[%d];\n", len + 1)))
                             : j2(j3("char ", cn, ""), Fi("[%d];\n", len + 1));
        }
        apd(decl);
        if (g_dc_hasval && occ == 0)
        {
            if (cls == C_ALNUM || cls == C_EDIT) g_inits = j2(g_inits, j2(F2("__movestr(%s, %s, ", cn, ecode(g_dc_val)), Fi("%d);\n", len)));
            else g_inits = j2(g_inits, F2("%s = %s;\n", cn, ecode(g_dc_val)));
        }
    }
    dc_reset();
}

int name_ref(char *nm)
{
    int i = sy_find(nm);
    if (i < 0) return mkE(cvar(nm), T_INT);
    if (sy_cls[i] == C_88) return mkE(sy_cond[i], T_LOG);
    int h = mkE(cvar(nm), cls2ty(sy_cls[i]));
    struct E *e = (struct E *)h; e->lval = 1; e->cls = sy_cls[i]; e->dig = sy_dig[i]; e->dec = sy_dec[i]; e->edit = sy_edit[i];
    return h;
}
int name_idx(char *nm, int ix)
{
    int i = sy_find(nm); char *cn = cvar(nm);
    int h = mkE(j2(cn, j4("[(", ecode(ix), ") - 1", "]")), (i >= 0) ? cls2ty(sy_cls[i]) : T_INT);
    if (i >= 0) { struct E *e = (struct E *)h; e->lval = 1; e->cls = sy_cls[i]; e->dig = sy_dig[i]; e->dec = sy_dec[i]; e->edit = sy_edit[i]; }
    return h;
}

int bin(int a, char *op, int b)
{
    int rt = (etype(a) == T_REAL || etype(b) == T_REAL) ? T_REAL : T_INT;
    return mkE(j2("(", j4(ecode(a), op, ecode(b), ")")), rt);
}
int cmp(int a, char *op, int b)
{
    if (etype(a) == T_STR || etype(b) == T_STR)
    {
        char *o = (strcmp(op, "==") == 0) ? "== 0" : (strcmp(op, "!=") == 0) ? "!= 0" : j2(op, " 0");
        return mkE(j3(F2("(strcmp(%s, %s) ", ecode(a), ecode(b)), o, ")"), T_LOG);
    }
    return mkE(j2("(", j4(ecode(a), op, ecode(b), ")")), T_LOG);
}

struct AG { int n; int a[32]; };
int ag1(int e) { struct AG *g = (struct AG *)malloc(132); g->n = 0; g->a[g->n++] = e; return (int)g; }
int agA(int h, int e) { struct AG *g = (struct AG *)h; g->a[g->n++] = e; return h; }
char *ag_sum(int h) { struct AG *g = (struct AG *)h; char *s = ecode(g->a[0]); int i; for (i = 1; i < g->n; i++) s = j3(s, " + ", ecode(g->a[i])); return s; }

void do_display(int e)
{
    if (g_pass != 2) return;
    int c = ecls(e);
    if (c == C_NUM) ap(F2("__disp_num(%s, %s);\n", ecode(e), istr(edig(e))));
    else if (c == C_DEC) ap(F2("__disp_dec((double)(%s), %s);\n", ecode(e), istr(edec(e))));
    else if (c == C_ALNUM || c == C_EDIT) ap(F1("printf(\"%%s\", %s);\n", ecode(e)));
    else if (etype(e) == T_STR) ap(F1("printf(\"%%s\", %s);\n", ecode(e)));
    else if (etype(e) == T_REAL) ap(F1("printf(\"%%g\", (double)(%s));\n", ecode(e)));
    else ap(F1("printf(\"%%d\", %s);\n", ecode(e)));
}

void move_one(int dst, int src)
{
    if (g_pass != 2) return;
    int c = ecls(dst); char *d = ecode(dst); char *s = ecode(src);
    if (c == C_ALNUM) ap(j2(F2("__movestr(%s, %s, ", d, s), Fi("%d);\n", edig(dst))));
    else if (c == C_EDIT) ap(j2(F2("__edit(%s, (double)(%s), ", d, s), F1("%s);\n", cstr(eedit(dst)))));
    else if (c == C_DEC) ap(F2("%s = (double)(%s);\n", d, s));
    else ap(F2("%s = (int)(%s);\n", d, s));
}
void do_move_t(int dst) { move_one(dst, g_movesrc); }
void do_assign(int dst, int src) { move_one(dst, src); }

void do_addsub(int srch, int dst, char *op, int give)
{
    if (g_pass != 2) return;
    char *sum = ag_sum(srch); int t = give ? give : dst;
    ap(j2(F2("%s = %s ", ecode(t), ecode(dst)), F2("%s (%s);\n", op, sum)));
}
void do_muldiv(int src, int dst, char *op, int give)
{
    if (g_pass != 2) return;
    int t = give ? give : dst;
    ap(j2(F2("%s = %s ", ecode(t), ecode(dst)), F2("%s (%s);\n", op, ecode(src))));
}
void do_accept(int dst)
{
    if (g_pass != 2) return;
    if (ecls(dst) == C_ALNUM || etype(dst) == T_STR) ap(F1("__accept_str(%s);\n", ecode(dst)));
    else if (ecls(dst) == C_DEC) ap(F1("{ double __x; scanf(\"%%lf\", &__x); %s = __x; }\n", ecode(dst)));
    else ap(F1("{ int __x; scanf(\"%%d\", &__x); %s = __x; }\n", ecode(dst)));
}
void do_perf_times(char *nm, int n) { if (g_pass == 2) ap(j2(Fi("{ int __t; for (__t=0; __t<%d; __t++) ", n), F1("pg_%s(); }\n", cvar(nm) + 2))); }
void do_perf_vary(char *nm, int v, int from, int by, int cnd)
{
    if (g_pass != 2) return;
    ap(F2("%s = (%s);\n", ecode(v), ecode(from)));
    ap(j2(F2("while (!(%s)) { pg_%s(); ", ecode(cnd), cvar(nm) + 2), F2("%s += (%s); }\n", ecode(v), ecode(by))));
}

void proc_start()
{
    if (g_pass == 1) { par_cn[npar++] = "pg___main0"; return; }
    int i; for (i = 0; i < npar; i++) ap(F1("void %s(void);\n", par_cn[i]));
    ap("void pg___main0(void) {\n"); ap(g_inits);
}
void new_para(char *nm)
{
    char *cn = j2("pg_", cvar(nm) + 2);
    if (g_pass == 1) { par_cn[npar++] = cn; return; }
    ap("}\n"); ap(j3("void ", cn, "(void) {\n"));
}
void proc_end()
{
    if (g_pass != 2) return;
    ap("}\n"); ap("int main(int argc, char** argv) {\n");
    int i; for (i = 0; i < npar; i++) ap(j3(par_cn[i], "();\n", ""));
    ap("return 0;\n}\n");
}

char *PRELUDE =
"void __disp_num(int v,int d){char t[40];int neg=0;int n=0;if(v<0){neg=1;v=-v;}if(v==0)t[n++]='0';while(v>0){t[n++]='0'+v%10;v/=10;}while(n<d)t[n++]='0';char b[48];int j=0;if(neg)b[j++]='-';while(n>0)b[j++]=t[--n];b[j]=0;printf(\"%s\",b);}\n"
"void __disp_dec(double v,int dec){int neg=v<0;if(neg)v=-v;int sc=1,k;for(k=0;k<dec;k++)sc*=10;int n=(int)(v*sc+0.5);int ip=n/sc;int fp=n%sc;if(neg)printf(\"-\");printf(\"%d\",ip);if(dec>0){char fb[20];int j;for(j=dec-1;j>=0;j--){fb[j]='0'+fp%10;fp/=10;}fb[dec]=0;printf(\".%s\",fb);}}\n"
"void __movestr(char*d,char*s,int len){int i=0;while(i<len&&s[i]){d[i]=s[i];i++;}while(i<len)d[i++]=' ';d[len]=0;}\n"
"void __accept_str(char*d){char b[256];if(fgets(b,256,stdin)){int i=0;while(b[i]&&b[i]!='\\n')i++;b[i]=0;strcpy(d,b);}}\n"
"void __edit(char*out,double dv,char*pic){int L=strlen(pic);int fd=0,sd=0,i;for(i=0;i<L;i++){if(pic[i]=='.')sd=1;else if(sd&&(pic[i]=='9'||pic[i]=='Z'))fd++;}int idn=0;for(i=0;i<L;i++){if(pic[i]=='.')break;if(pic[i]=='9'||pic[i]=='Z')idn++;}int neg=dv<0;double a=neg?-dv:dv;int sc=1,k;for(k=0;k<fd;k++)sc*=10;int nn=(int)(a*sc+0.5);int ip=nn/sc;int fp=nn%sc;char id[32];int ic=0;if(ip==0)id[ic++]='0';while(ip>0){id[ic++]='0'+ip%10;ip/=10;}char fdg[20];for(k=fd-1;k>=0;k--){fdg[k]='0'+fp%10;fp/=10;}fdg[fd]=0;int o=0,dp=0,started=0;for(i=0;i<L;i++){char c=pic[i];if(c=='.')break;if(c=='9'||c=='Z'){int sl=idn-dp;char dd=(sl<=ic)?id[sl-1]:'0';if(c=='Z'&&!started&&dd=='0'){out[o++]=' ';}else{started=1;out[o++]=dd;}dp++;}else if(c==','){out[o++]=started?',':' ';}else if(c=='$'){out[o++]='$';}else if(c=='-'){out[o++]=neg?'-':' ';}else if(c=='+'){out[o++]=neg?'-':'+';}else{out[o++]=c;}}if(fd>0){out[o++]='.';for(k=0;k<fd;k++)out[o++]=fdg[k];}out[o]=0;}\n";

void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: cobol <file.cob> [-o out] [--dll]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], cpath[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, "exe"); }
    strcpy(cpath, outp); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"cobol: cannot read %s\n", (int)in); return 1; }
    nsy = 0; npar = 0; g_inits = ""; g_pass = 1; pline = 1; yy_scan_string((int)src); yyparse();
    nsy = 0; g_pass = 2; pline = 1; g_out = ""; g_data = ""; g_inits = ""; yy_scan_string((int)src); yyparse();
    int f = fopen((int)cpath, (int)"w"); fputs((int)PRELUDE, f); fputs((int)g_data, f); fputs((int)g_out, f); fclose(f);
    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; int n = 0; av[n++] = (int)cc; av[n++] = (int)cpath; av[n++] = (int)"-o"; av[n++] = (int)outp; av[n++] = dll ? (int)"--dll" : (int)"--exe";
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"cobol: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"cobol: cc failed (%d)\n", rc);
    return rc;
}
