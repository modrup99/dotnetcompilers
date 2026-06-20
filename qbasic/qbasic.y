%{
/* QBasic -> C compiler (yacc). Syntax-directed translation emitting C, which cc
 * lowers to .NET IL + native exe. Built with our own lex + yacc + cc.
 *
 * Two passes: pass 1 registers every variable (type from $%!#& suffix or DIM),
 * label, and SUB/FUNCTION signature; pass 2 emits. Module-level variables become
 * C globals (so SUBs can see them); top-level statements accumulate into a buffer
 * emitted inside main() at the end, while SUB/FUNCTION bodies go straight to file. */

#define T_INT 1
#define T_DBL 2
#define T_STR 3

int out;                 /* output FILE* (int handle) */
char *qbfile;
int g_pass;              /* 1 = collect symbols (silent); 2 = emit */
int g_infunc;            /* inside a SUB/FUNCTION body? (emit to file vs mainbuf) */
char *mainbuf;           /* top-level program statements, wrapped in main() at the end */
char *g_funcbase;        /* lowercased base name of the FUNCTION being compiled (for return) */
int g_hasscreen;         /* a SCREEN statement was seen -> graphics mode (CLS clears the canvas) */

/* --- string builders --- */
char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 8); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 8); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *F3(char *f, char *a, char *b, char *c) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + strlen(c) + 8); sprintf((int)r, (int)f, (int)a, (int)b, (int)c); return r; }
char *F4(char *f, char *a, char *b, char *c, char *d) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + strlen(c) + strlen(d) + 8); sprintf((int)r, (int)f, (int)a, (int)b, (int)c, (int)d); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *lc(char *s) { char *r = (char *)strdup((int)s); int i = 0; while (r[i]) { if (r[i] >= 'A' && r[i] <= 'Z') r[i] = r[i] + 32; i++; } return r; }
char *uc(char *s) { char *r = (char *)strdup((int)s); int i = 0; while (r[i]) { if (r[i] >= 'a' && r[i] <= 'z') r[i] = r[i] - 32; i++; } return r; }

/* emit to the current target (mainbuf at top level, file inside a SUB/FUNCTION) */
void e(char *s) { if (g_pass == 1) return; if (g_infunc) fputs((int)s, out); else { if (mainbuf == 0) mainbuf = ""; mainbuf = j2(mainbuf, s); } }
void ef(char *s) { if (g_pass == 1) return; fputs((int)s, out); }   /* always straight to file */

char *ctype(int t) { if (t == T_STR) return "char*"; if (t == T_DBL) return "double"; return "int"; }

/* --- expression handles: text + type + is-lvalue (a plain variable/array elem,
 *     so a by-ref argument can pass its address) --- */
struct E { char *t; int ty; int lv; };
int mkE(char *t, int ty) { struct E *p = (struct E *)malloc(12); p->t = t; p->ty = ty; p->lv = 0; return (int)p; }
int mkEl(char *t, int ty) { int e = mkE(t, ty); ((struct E *)e)->lv = 1; return e; }
char *etext(int x) { return ((struct E *)x)->t; }
int etype(int x) { return ((struct E *)x)->ty; }
int elv(int x) { return ((struct E *)x)->lv; }

/* --- argument lists (for calls / array indices / builtins) --- */
struct AL { int e; int next; };
int mkAL(int ev, int nx) { struct AL *p = (struct AL *)malloc(8); p->e = ev; p->next = nx; return (int)p; }
int app_AL(int l, int ev) { if (l == 0) return mkAL(ev, 0); struct AL *n = (struct AL *)l; while (n->next) n = (struct AL *)n->next; n->next = mkAL(ev, 0); return l; }
int al_len(int l) { int n = 0; struct AL *p = (struct AL *)l; while (p) { n++; p = (struct AL *)p->next; } return n; }
int al_get(int l, int i) { struct AL *p = (struct AL *)l; while (i-- && p) p = (struct AL *)p->next; return p ? p->e : 0; }
char *al_join(int l) { char *a = ""; struct AL *p = (struct AL *)l; int first = 1; while (p) { a = first ? etext(p->e) : j3(a, ", ", etext(p->e)); first = 0; p = (struct AL *)p->next; } return a; }

/* --- variable table (mangled C name -> type; arrays carry bounds) --- */
char *vt_name[4000]; int vt_type[4000]; int vt_isarr[4000]; int vt_lo1[4000]; int vt_n1[4000]; int vt_lo2[4000]; int vt_n2[4000]; int nv;
int var_find(char *cn) { int i; for (i = 0; i < nv; i++) if (strcmp(vt_name[i], cn) == 0) return i; return -1; }

/* split an identifier into its C name (v_<base><suffixcode>) and type */
char *mangle(char *id, int *pty)
{
    int n = strlen(id); char last = (n > 0) ? id[n - 1] : 0; int ty = T_DBL; char *sfx = "";
    if (last == '$') { ty = T_STR; sfx = "_s"; n--; }
    else if (last == '%') { ty = T_INT; sfx = "_i"; n--; }
    else if (last == '&') { ty = T_INT; sfx = "_l"; n--; }
    else if (last == '!') { ty = T_DBL; sfx = "_f"; n--; }
    else if (last == '#') { ty = T_DBL; sfx = "_d"; n--; }
    char *base = (char *)malloc(n + 1); strncpy((int)base, (int)id, n); base[n] = 0;
    *pty = ty;
    return j3("v_", lc(base), sfx);
}
int var_use(char *id)   /* register (pass 1) / look up a scalar var; returns table index */
{
    int ty; char *cn = mangle(id, &ty); int i = var_find(cn);
    if (i < 0 && g_pass == 1) { i = nv; vt_name[nv] = cn; vt_type[nv] = ty; vt_isarr[nv] = 0; vt_lo1[nv] = 0; vt_n1[nv] = 0; vt_n2[nv] = 0; nv++; }
    if (i < 0) { i = nv; vt_name[nv] = cn; vt_type[nv] = ty; vt_isarr[nv] = 0; nv++; }   /* safety: pass-2 only */
    return i;
}

/* --- SUB/FUNCTION table (params are by reference, QBasic default) --- */
char *sf_base[400]; int sf_isfunc[400]; int sf_ret[400]; int sf_np[400]; int sf_pty[400][16]; int nsf;
int func_find(char *base) { int i; char *b = lc(base); for (i = 0; i < nsf; i++) if (sf_isfunc[i] && strcmp(sf_base[i], b) == 0) return i; return -1; }
int sub_find(char *base) { int i; char *b = lc(base); for (i = 0; i < nsf; i++) if (!sf_isfunc[i] && strcmp(sf_base[i], b) == 0) return i; return -1; }
int sf_find_base(char *b) { int i; for (i = 0; i < nsf; i++) if (strcmp(sf_base[i], b) == 0) return i; return -1; }
/* strip a trailing type-suffix from a name, return lowercased base */
char *basename_of(char *id) { int n = strlen(id); char last = id[n - 1]; if (last == '$' || last == '%' || last == '&' || last == '!' || last == '#') n--; char *b = (char *)malloc(n + 1); strncpy((int)b, (int)id, n); b[n] = 0; return lc(b); }
int suffix_type(char *id) { int n = strlen(id); char last = id[n - 1]; if (last == '$') return T_STR; if (last == '%' || last == '&') return T_INT; return T_DBL; }

void reg_func(char *id, int isfunc) { if (g_pass != 1) return; sf_base[nsf] = basename_of(id); sf_isfunc[nsf] = isfunc; sf_ret[nsf] = isfunc ? suffix_type(id) : 0; sf_np[nsf] = 0; nsf++; }

/* parameters of the function currently being compiled (so body uses deref `(*p)`) */
char *pp_name[64]; int pp_ty[64]; int pp_n; int g_curfn;
int param_ty(char *cn) { int i; for (i = 0; i < pp_n; i++) if (strcmp(pp_name[i], cn) == 0) return pp_ty[i]; return -1; }

int yylex();
void yyerror(char *m);
int line(int n);
int builtin_call(char *id, int args);
int name_ref(char *id, int args, int hasp);

/* --- expression code generators --- */
char *to_int(int x) { return (etype(x) == T_INT) ? etext(x) : F1("(int)(%s)", etext(x)); }
char *to_dbl(int x) { return (etype(x) == T_DBL) ? etext(x) : F1("(double)(%s)", etext(x)); }
int bin(int a, char *op, int b)
{
    if (strcmp(op, "+") == 0 && (etype(a) == T_STR || etype(b) == T_STR)) return mkE(F2("__bcat(%s, %s)", etext(a), etext(b)), T_STR);
    int rt = (etype(a) == T_DBL || etype(b) == T_DBL) ? T_DBL : T_INT;
    return mkE(F3("(%s %s %s)", etext(a), op, etext(b)), rt);
}
int rel(int a, char *op, int b)
{
    if (etype(a) == T_STR || etype(b) == T_STR) return mkE(F3("(strcmp(%s, %s) %s 0)", etext(a), etext(b), op), T_INT);
    return mkE(F3("(%s %s %s)", etext(a), op, etext(b)), T_INT);
}
%}
%token IDENT INTLIT REALLIT STRLIT EOL
%token KPRINT KINPUT KLET KDIM KAS KIF KTHEN KELSE KELSEIF KEND KENDIF
%token KFOR KTO KSTEP KNEXT KWHILE KWEND KDO KLOOP KUNTIL KSELECT KCASE KIST
%token KGOTO KSUB KFUNCTION KCALL KSTOP KREM KENDSUB KENDFUNCTION KENDSELECT KEXITFOR KEXITDO
%token KMOD KAND KOR KXOR KNOT
%token KCLS KSCREEN KPSET KLINE KCIRCLE KCOLOR KPAINT KSLEEP KRANDOMIZE
%token KINTEGER KLONG KSINGLE KDOUBLE KSTRINGT
%token LE GE NE
%left KOR KXOR
%left KAND
%right KNOT
%left '=' '<' '>' LE GE NE
%left '+' '-'
%left '*' '/'
%left '\\'
%left KMOD
%right UMINUS
%right '^'
%%

program  : block ;
block    : /* empty */ | block bitem ;
bitem    : term
         | labeldef
         | simplestmt term
         | ifblock | forblock | whileblock | doblock | selectblock
         | subdef | funcdef ;
term     : EOL { line(tokln); } | ':' ;   /* tokln = next statement's line (lookahead) -> #line */
labeldef : INTLIT     { e(F1("L%s: ;\n", istr($1))); }
         | IDENT ':'   { e(F1("%s: ;\n", lc((char *)$1))); } ;

/* ---------------- simple statements ---------------- */
simplestmt
         : assignment
         | KPRINT pbody
         | KINPUT inbody
         | KDIM dimlist
         | KGOTO INTLIT          { e(F1("goto L%s;\n", istr($2))); }
         | KGOTO IDENT           { e(F1("goto %s;\n", lc((char *)$2))); }
         | KSTOP                 { e("exit(0);\n"); }
         | KEND                  { e("exit(0);\n"); }
         | KEXITFOR              { e("break;\n"); }
         | KEXITDO               { e("break;\n"); }
         | KCLS                  { e(g_hasscreen ? (char *)"gfx_clear(0); gfx_present();\n" : (char *)"printf(\"\\x1b[2J\\x1b[H\");\n"); }
         | KSCREEN expr          { g_hasscreen = 1; e("gfx_open(640, 480, (int)\"QBasic\");\n"); }
         | KCOLOR expr           { e(F1("__qcolor = __qbcolor(%s);\n", to_int($2))); }
         | KCOLOR expr ',' expr  { e(F1("__qcolor = __qbcolor(%s);\n", to_int($2))); }
         | KPSET '(' expr ',' expr ')'           { e(F2("gfx_fill_rect(%s, %s, 1, 1, __qcolor); gfx_present();\n", to_int($3), to_int($5))); }
         | KPSET '(' expr ',' expr ')' ',' expr  { e(F3("__qcolor = __qbcolor(%s); gfx_fill_rect(%s, %s, 1, 1, __qcolor); gfx_present();\n", to_int($8), to_int($3), to_int($5))); }
         | KLINE '(' expr ',' expr ')' '-' '(' expr ',' expr ')'              { e(F4("gfx_line(%s, %s, %s, %s, __qcolor); gfx_present();\n", to_int($3), to_int($5), to_int($9), to_int($11))); }
         | KLINE '(' expr ',' expr ')' '-' '(' expr ',' expr ')' ',' expr     { e(F4("__qcolor = __qbcolor(%s); gfx_line(%s, %s, %s, ", to_int($14), to_int($3), to_int($5), to_int($9))); e(F1("%s, __qcolor); gfx_present();\n", to_int($11))); }
         | KLINE '(' expr ',' expr ')' '-' '(' expr ',' expr ')' ',' expr ',' IDENT  { e(F4("__qcolor = __qbcolor(%s); __linebox(%s, %s, %s, ", to_int($14), to_int($3), to_int($5), to_int($9))); e(F2("%s, __qcolor, %s); gfx_present();\n", to_int($11), (uc((char *)$16)[1] == 'F') ? (char *)"1" : (char *)"0")); }
         | KCIRCLE '(' expr ',' expr ')' ',' expr            { e(F3("gfx_draw_ellipse(%s, %s, %s, ", to_int($3), to_int($5), to_int($8))); e(F1("%s, __qcolor); gfx_present();\n", to_int($8))); }
         | KCIRCLE '(' expr ',' expr ')' ',' expr ',' expr   { e(F2("__qcolor = __qbcolor(%s); gfx_draw_ellipse(%s, ", to_int($10), to_int($3))); e(F3("%s, %s, %s, __qcolor); gfx_present();\n", to_int($5), to_int($8), to_int($8))); }
         | KSLEEP                { e("gfx_present(); while (!gfx_poll()) gfx_sleep(30);\n"); }
         | KSLEEP expr           { e(g_hasscreen ? (char *)"gfx_present(); while (!gfx_poll()) gfx_sleep(30);\n" : (char *)";\n"); }
         | KRANDOMIZE            { e("srand(1);\n"); }
         | KRANDOMIZE expr       { e(F1("srand(%s);\n", to_int($2))); }
         | KCALL IDENT '(' arglist ')'  { e(F2("s_%s(%s);\n", basename_of((char *)$2), build_call_args($4, sub_find(basename_of((char *)$2))))); }
         | KCALL IDENT                  { e(F1("s_%s();\n", basename_of((char *)$2))); }
         ;

assignment
         : KLET lvalue '=' expr   { e(F2("%s = %s;\n", etext($2), conv($2, $4))); }
         | lvalue '=' expr        { e(F2("%s = %s;\n", etext($1), conv($1, $3))); }
         ;

/* an assignable target: scalar var, array element, or (inside a FUNCTION) its name */
lvalue   : IDENT                       { $$ = lval_name((char *)$1, 0, 0); }
         | IDENT '(' arglist ')'       { $$ = lval_name((char *)$1, $3, 1); }
         ;

/* ---------------- PRINT ---------------- */
pbody    : /* empty */        { e("printf(\"\\n\");\n"); }
         | pitems             { e("printf(\"\\n\");\n"); }
         | pitems ';'         { }
         | pitems ','         { e("printf(\"\\t\");\n"); }
         ;
pitems   : pitem
         | pitems ';' pitem
         | pitems ',' ptab pitem
         ;
ptab     : /* empty */ { e("printf(\"\\t\");\n"); } ;
pitem    : expr  { int t = etype($1); if (t == T_STR) e(F1("printf(\"%%s\", %s);\n", etext($1))); else if (t == T_INT) e(F1("__pni(%s);\n", etext($1))); else e(F1("__pn(%s);\n", to_dbl($1))); } ;

/* ---------------- INPUT ---------------- */
inbody   : invars
         | STRLIT ';' invars   { e(F1("printf(\"%%s? \", (int)%s);\n", cstr((char *)$1))); inflush(); }
         | STRLIT ',' invars   { e(F1("printf(\"%%s\", (int)%s);\n", cstr((char *)$1))); inflush(); }
         ;
invars   : invar | invars ',' invar ;
invar    : lvalue  { int t = etype($1); if (t == T_STR) e(F1("%s = __inputline();\n", etext($1))); else if (t == T_INT) e(F1("%s = atoi(__inputline());\n", etext($1))); else e(F1("%s = atof(__inputline());\n", etext($1))); } ;

/* ---------------- DIM ---------------- */
dimlist  : dimitem | dimlist ',' dimitem ;
dimitem  : IDENT                                  { var_use((char *)$1); }
         | IDENT KAS typ                           { dim_typed((char *)$1, $3); }
         | IDENT '(' bounds ')'                    { /* bounds already recorded into g_d* */ dim_array((char *)$1, -1); }
         | IDENT '(' bounds ')' KAS typ            { dim_array((char *)$1, $6); }
         ;
bounds   : bnd | bounds ',' bnd ;
bnd      : INTLIT                 { dim_bound(0, $1); }
         | INTLIT KTO INTLIT      { dim_bound($1, $3); }
         ;
typ      : KINTEGER { $$ = T_INT; } | KLONG { $$ = T_INT; } | KSINGLE { $$ = T_DBL; }
         | KDOUBLE { $$ = T_DBL; } | KSTRINGT { $$ = T_STR; } ;

/* ---------------- IF ---------------- */
ifblock  : ifhd EOL block elifs elsep endif        { e("}\n"); }
         | ifhd slcons                              { e("}\n"); }
         | ifhd slcons KELSE elsemk slcons2         { e("}\n"); }
         ;
ifhd     : KIF expr KTHEN  { e(F1("if (%s) {\n", to_int($2))); } ;
elsemk   : /* empty */ { e("} else {\n"); } ;
slcons   : slstmt | slcons ':' slstmt ;
slcons2  : slstmt | slcons2 ':' slstmt ;
slstmt   : simplestmt ;
elifs    : /* empty */ | elifs elif ;
elif     : elifhd elifterm block ;
elifhd   : KELSEIF expr KTHEN  { e(F1("} else if (%s)", to_int($2))); } ;
elifterm : term  { e(" {\n"); } ;
elsep    : /* empty */ | KELSE elseterm block ;
elseterm : term  { e("} else {\n"); } ;
endif    : KENDIF | KEND KIF ;

/* ---------------- FOR ---------------- */
forblock : forhd block KNEXT optid     { e("} }\n"); } ;
forhd    : KFOR lvalue '=' expr KTO expr forstep term
           { char *v = etext($2);
             e("{ double __fe = ("); e(to_dbl($6)); e("); double __fs = ("); e(to_dbl($7)); e(");\n");
             e("for ("); e(v); e(" = "); e(conv($2, $4)); e("; (__fs >= 0) ? (");
             e(v); e(" <= __fe) : ("); e(v); e(" >= __fe); ");
             e(v); e(" += __fs) {\n"); } ;
forstep  : /* empty */    { $$ = mkE("1", T_INT); }
         | KSTEP expr     { $$ = $2; }
         ;
optid    : /* empty */ | IDENT ;

/* ---------------- WHILE / DO ---------------- */
whileblock : whilehd block KWEND  { e("}\n"); } ;
whilehd    : KWHILE expr term     { e(F1("while (%s) {\n", to_int($2))); } ;
doblock  : dohd block looptail     { e("}\n"); }
         ;
dohd     : KDO term                       { e("while (1) {\n"); }
         | KDO KWHILE expr term           { e(F1("while (%s) {\n", to_int($3))); }
         | KDO KUNTIL expr term           { e(F1("while (!(%s)) {\n", to_int($3))); }
         ;
looptail : KLOOP                  { }
         | KLOOP KWHILE expr      { e(F1("if (!(%s)) break;\n", to_int($3))); }
         | KLOOP KUNTIL expr      { e(F1("if (%s) break;\n", to_int($3))); }
         ;

/* ---------------- SELECT CASE ---------------- */
selectblock : selhd cases endsel  { e("} }\n"); } ;
selhd    : KSELECT KCASE expr term { e(F1("{ double __sel = %s; if (0) {\n", to_dbl($3))); } ;
cases    : /* empty */ | cases onecase ;
onecase  : KCASE caseopen caselist caseterm block
         | KCASE KELSE elseterm block
         ;
caseopen : /* empty */ { e("} else if ("); } ;
caseterm : term { e(") {\n"); } ;
caselist : caseval | caselist casesep caseval ;
casesep  : ',' { e(" || "); } ;
caseval  : expr               { e(F1("__sel == (%s)", to_dbl($1))); }
         | expr KTO expr      { e(F2("(__sel >= (%s) && __sel <= (%s))", to_dbl($1), to_dbl($3))); }
         | KIST '<' expr      { e(F1("__sel < (%s)", to_dbl($3))); }
         | KIST '>' expr      { e(F1("__sel > (%s)", to_dbl($3))); }
         | KIST LE expr       { e(F1("__sel <= (%s)", to_dbl($3))); }
         | KIST GE expr       { e(F1("__sel >= (%s)", to_dbl($3))); }
         | KIST NE expr       { e(F1("__sel != (%s)", to_dbl($3))); }
         | KIST '=' expr      { e(F1("__sel == (%s)", to_dbl($3))); }
         ;
endsel   : KENDSELECT | KEND KSELECT ;

/* ---------------- SUB / FUNCTION ---------------- */
/* markers (yacc has no mid-rule actions): subname/funcname capture the name and
 * enter the body; subsig/funcsig emit the C signature once params are known. */
subdef   : KSUB subname params subsig block KENDSUB    { e("}\n"); g_infunc = 0; pp_n = 0; } ;
subname  : IDENT  { g_subname = basename_of((char *)$1); reg_func((char *)$1, 0); g_curfn = sf_find_base(g_subname); g_infunc = 1; g_funcbase = ""; g_params = ""; pp_n = 0; nv_save(); } ;
subsig   : term   { ef(F2("void s_%s(%s) {\n", g_subname, g_params)); } ;
funcdef  : KFUNCTION funcname params funcsig block KENDFUNCTION  { e("return __result; }\n"); g_infunc = 0; g_funcbase = ""; pp_n = 0; } ;
funcname : IDENT  { g_funcname = basename_of((char *)$1); reg_func((char *)$1, 1); g_curfn = sf_find_base(g_funcname); g_infunc = 1; g_funcbase = basename_of((char *)$1); g_functy = suffix_type((char *)$1); g_params = ""; pp_n = 0; nv_save(); } ;
funcsig  : term   { ef(F4("%s f_%s(%s) {\n  %s __result = ", ctype(g_functy), g_funcname, g_params, ctype(g_functy))); ef(g_functy == T_STR ? (char *)"(char*)\"\";\n" : (char *)"0;\n"); } ;
params   : /* empty */              { g_params = ""; }
         | '(' ')'                  { g_params = ""; }
         | '(' plist ')'            { }
         ;
plist    : param | plist ',' param ;
param    : IDENT          { addparam((char *)$1, suffix_type((char *)$1)); }
         | IDENT KAS typ  { addparam((char *)$1, $3); }
         ;

/* ---------------- expressions ---------------- */
expr     : expr '+' expr     { $$ = bin($1, "+", $3); }
         | expr '-' expr     { $$ = bin($1, "-", $3); }
         | expr '*' expr     { $$ = bin($1, "*", $3); }
         | expr '/' expr     { $$ = mkE(F2("(%s / %s)", to_dbl($1), to_dbl($3)), T_DBL); }
         | expr '\\' expr    { $$ = mkE(F2("(%s / %s)", to_int($1), to_int($3)), T_INT); }
         | expr KMOD expr    { $$ = mkE(F2("(%s %% %s)", to_int($1), to_int($3)), T_INT); }
         | expr '^' expr     { $$ = mkE(F2("pow(%s, %s)", to_dbl($1), to_dbl($3)), T_DBL); }
         | expr '=' expr     { $$ = rel($1, "==", $3); }
         | expr '<' expr     { $$ = rel($1, "<", $3); }
         | expr '>' expr     { $$ = rel($1, ">", $3); }
         | expr LE expr      { $$ = rel($1, "<=", $3); }
         | expr GE expr      { $$ = rel($1, ">=", $3); }
         | expr NE expr      { $$ = rel($1, "!=", $3); }
         | expr KAND expr    { $$ = mkE(F2("(%s && %s)", to_int($1), to_int($3)), T_INT); }
         | expr KOR expr     { $$ = mkE(F2("(%s || %s)", to_int($1), to_int($3)), T_INT); }
         | expr KXOR expr    { $$ = mkE(F2("(%s ^ %s)", to_int($1), to_int($3)), T_INT); }
         | KNOT expr         { $$ = mkE(F1("(!%s)", to_int($2)), T_INT); }
         | '-' expr %prec UMINUS { $$ = mkE(F1("(-%s)", etext($2)), etype($2)); }
         | '(' expr ')'      { $$ = mkE(F1("(%s)", etext($2)), etype($2)); }
         | INTLIT            { $$ = mkE(istr($1), T_INT); }
         | REALLIT           { $$ = mkE((char *)$1, T_DBL); }
         | STRLIT            { $$ = mkE(cstr((char *)$1), T_STR); }
         | IDENT             { $$ = name_ref((char *)$1, 0, 0); }
         | IDENT '(' arglist ')'  { $$ = name_ref((char *)$1, $3, 1); }
         ;
arglist  : /* empty */ { $$ = 0; } | arglist1 { $$ = $1; } ;
arglist1 : expr               { $$ = app_AL(0, $1); }
         | arglist1 ',' expr  { $$ = app_AL($1, $3); }
         ;
%%

char *g_params; char *g_forvar; char *g_forstep; int g_stepneg; char *g_funcres; int g_functy; char *g_subname; char *g_funcname;
int saved_nv;
void nv_save(void) { saved_nv = nv; }

/* a C string literal from a collapsed source string (escape \ and ") */
char *cstr(char *s)
{
    char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"';
    while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; if (s[i] == '\n') { r[j++] = '\\'; r[j++] = 'n'; i++; continue; } r[j++] = s[i++]; }
    r[j++] = '"'; r[j] = 0; return r;
}

/* DIM bound bookkeeping (one or two dimensions) */
int g_dlo1, g_dn1, g_dlo2, g_dn2, g_dndim;
int dim_bound(int lo, int hi) { if (g_dndim == 0) { g_dlo1 = lo; g_dn1 = hi - lo + 1; } else { g_dlo2 = lo; g_dn2 = hi - lo + 1; } g_dndim++; return 0; }
int dim_array(char *id, int astype)
{
    int ty; char *cn = mangle(id, &ty); if (astype >= 0) ty = astype;
    int i = var_find(cn);
    if (i < 0) { i = nv; vt_name[nv] = cn; nv++; }
    vt_type[i] = ty; vt_isarr[i] = 1; vt_lo1[i] = g_dlo1; vt_n1[i] = g_dn1; vt_lo2[i] = (g_dndim > 1) ? g_dlo2 : 0; vt_n2[i] = (g_dndim > 1) ? g_dn2 : 0;
    g_dndim = 0; g_dlo1 = 0; g_dn1 = 0; g_dlo2 = 0; g_dn2 = 0;
    return 0;
}
int dim_typed(char *id, int astype) { int ty; char *cn = mangle(id, &ty); int i = var_find(cn); if (i < 0) { i = nv; vt_name[nv] = cn; vt_isarr[nv] = 0; nv++; } vt_type[i] = astype; return 0; }

/* bounds rule starts: clear the per-DIM dimension state before collecting */
/* (called implicitly: dim_bound resets g_dndim to 0 in dim_array after use) */

/* assignment target -> E(text,type); handles array element + FUNCTION result */
int lval_name(char *id, int args, int hasp)
{
    char *base = basename_of(id);
    if (g_funcbase && g_funcbase[0] && strcmp(base, g_funcbase) == 0 && !hasp) return mkE("__result", g_functy);
    int ty; char *cn = mangle(id, &ty);
    int i = var_find(cn);
    if (hasp)
    {
        if (i < 0 && g_pass == 1) { i = nv; vt_name[nv] = cn; vt_type[nv] = ty; vt_isarr[nv] = 1; vt_lo1[nv] = 0; vt_n1[nv] = 11; vt_n2[nv] = 0; nv++; }   /* auto-dim 0..10 */
        if (i < 0) { return mkEl(F2("%s[%s]", cn, to_int(al_get(args, 0))), ty); }
        return arr_elem(i, args);
    }
    int pty = param_ty(cn);
    if (pty >= 0) return mkEl(F1("(*%s)", cn), pty);   /* by-ref param: assign through the pointer */
    if (i < 0) i = var_use(id);
    return mkEl(vt_name[i], vt_type[i]);
}
int arr_elem(int i, int args)
{
    char *cn = vt_name[i];
    if (vt_n2[i] > 0) return mkEl(F4("%s[%s - %s][%s", cn, to_int(al_get(args, 0)), istr(vt_lo1[i]), F3("%s - %s]", to_int(al_get(args, 1)), istr(vt_lo2[i]), "")), vt_type[i]);
    return mkEl(F3("%s[%s - %s]", cn, to_int(al_get(args, 0)), istr(vt_lo1[i])), vt_type[i]);
}

/* conversion of rhs to lhs type on assignment (mostly numeric int<->double) */
char *conv(int lhs, int rhs)
{
    int lt = etype(lhs), rt = etype(rhs);
    if (lt == T_STR) return etext(rhs);
    if (lt == T_INT && rt == T_DBL) return F1("(int)(%s)", etext(rhs));
    if (lt == T_DBL && rt == T_INT) return F1("(double)(%s)", etext(rhs));
    return etext(rhs);
}

/* a by-ref parameter: emit a pointer decl `T* cn`; record it so body uses deref it,
 * and record its type in the function signature (pass 1) for call-site arg passing */
void addparam(char *id, int ty)
{
    int t2; char *cn = mangle(id, &t2);
    pp_name[pp_n] = cn; pp_ty[pp_n] = ty; pp_n++;
    if (g_pass == 1 && g_curfn >= 0) { sf_pty[g_curfn][sf_np[g_curfn]] = ty; sf_np[g_curfn]++; }
    char *d = j3(ctype(ty), "* ", cn);
    if (g_params == 0 || g_params[0] == 0) g_params = d; else g_params = j3(g_params, ", ", d);
}
/* one argument for a by-ref param of type pty: pass the variable's address when it
 * is a matching-type lvalue (so changes propagate); otherwise a fresh temp cell */
char *pass_arg(int e, int pty)
{
    if (elv(e) && etype(e) == pty) return F1("&(%s)", etext(e));
    if (pty == T_STR) return F1("__refs(%s)", etext(e));
    if (pty == T_INT) return F1("__refi(%s)", to_int(e));
    return F1("__refd(%s)", to_dbl(e));
}
char *build_call_args(int args, int fi)
{
    char *acc = ""; int i = 0, first = 1; struct AL *p = (struct AL *)args;
    while (p)
    {
        int pty = (fi >= 0 && i < sf_np[fi]) ? sf_pty[fi][i] : etype(p->e);
        char *a = pass_arg(p->e, pty);
        acc = first ? a : j3(acc, ", ", a); first = 0; i++; p = (struct AL *)p->next;
    }
    return acc;
}

/* a name in an expression: builtin, array element, function call, or scalar var */
int name_ref(char *id, int args, int hasp)
{
    if (hasp) { int b = builtin_call(id, args); if (b) return b; }
    char *base = basename_of(id);
    int ty; char *cn = mangle(id, &ty);
    int vi = var_find(cn);
    if (hasp && vi >= 0 && vt_isarr[vi]) return arr_elem(vi, args);
    int fi = func_find(base);
    if (fi >= 0) return mkE(F2("f_%s(%s)", base, build_call_args(args, fi)), sf_ret[fi]);
    if (hasp && (vi < 0 || !vt_isarr[vi])) return mkE(F2("f_%s(%s)", base, build_call_args(args, -1)), T_DBL);   /* forward/unknown call */
    int pty = param_ty(cn);
    if (pty >= 0) return mkEl(F1("(*%s)", cn), pty);   /* by-ref param: dereference */
    if (vi < 0) vi = var_use(id);
    return mkEl(vt_name[vi], vt_type[vi]);
}

/* INPUT prompt with no trailing var separator handling */
void inflush(void) { }

/* built-in functions; returns an E handle or 0 if `id` is not a builtin */
int builtin_call(char *id, int args)
{
    char *u = uc(id); int n = al_len(args);
    int a0 = (n > 0) ? args : 0;
    char *p0 = (n > 0) ? etext(al_get(args, 0)) : "";
    if (strcmp(u, "LEN") == 0) return mkE(F1("((int)strlen(%s))", p0), T_INT);
    if (strcmp(u, "LEFT$") == 0) return mkE(F2("__left(%s, %s)", p0, to_int(al_get(args, 1))), T_STR);
    if (strcmp(u, "RIGHT$") == 0) return mkE(F2("__right(%s, %s)", p0, to_int(al_get(args, 1))), T_STR);
    if (strcmp(u, "MID$") == 0) { char *third = (n > 2) ? to_int(al_get(args, 2)) : (char *)"-1"; return mkE(F3("__mid(%s, %s, %s)", p0, to_int(al_get(args, 1)), third), T_STR); }
    if (strcmp(u, "CHR$") == 0) return mkE(F1("__chr(%s)", to_int(al_get(args, 0))), T_STR);
    if (strcmp(u, "ASC") == 0) return mkE(F1("((int)(%s)[0])", p0), T_INT);
    if (strcmp(u, "STR$") == 0) return mkE(F1("__str(%s)", to_dbl(al_get(args, 0))), T_STR);
    if (strcmp(u, "VAL") == 0) return mkE(F1("atof(%s)", p0), T_DBL);
    if (strcmp(u, "INSTR") == 0) { if (n > 2) return mkE(F3("__instr2(%s, %s, %s)", to_int(al_get(args, 0)), etext(al_get(args, 1)), etext(al_get(args, 2))), T_INT); return mkE(F2("__instr(%s, %s)", p0, etext(al_get(args, 1))), T_INT); }
    if (strcmp(u, "UCASE$") == 0) return mkE(F1("__ucase(%s)", p0), T_STR);
    if (strcmp(u, "LCASE$") == 0) return mkE(F1("__lcase(%s)", p0), T_STR);
    if (strcmp(u, "SPACE$") == 0) return mkE(F1("__spacef(%s)", to_int(al_get(args, 0))), T_STR);
    if (strcmp(u, "STRING$") == 0) return mkE(F2("__stringf(%s, %s)", to_int(al_get(args, 0)), to_int(al_get(args, 1))), T_STR);
    if (strcmp(u, "ABS") == 0) return mkE(F1("fabs(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "INT") == 0) return mkE(F1("floor(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "FIX") == 0) return mkE(F1("((double)(int)(%s))", to_dbl(a0)), T_DBL);
    if (strcmp(u, "SGN") == 0) return mkE(F1("__sgn(%s)", to_dbl(a0)), T_INT);
    if (strcmp(u, "SQR") == 0) return mkE(F1("sqrt(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "SIN") == 0) return mkE(F1("sin(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "COS") == 0) return mkE(F1("cos(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "TAN") == 0) return mkE(F1("tan(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "ATN") == 0) return mkE(F1("atan(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "EXP") == 0) return mkE(F1("exp(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "LOG") == 0) return mkE(F1("log(%s)", to_dbl(a0)), T_DBL);
    if (strcmp(u, "RND") == 0) return mkE("(((double)rand()) / 2147483648.0)", T_DBL);
    return 0;
}

int line(int n) { e(F2("#line %s \"%s\"\n", istr(n), qbfile)); return 0; }
void yyerror(char *m) { printf((int)"qbasic: %s near line %d\n", (int)m, pline); }

/* --- C prelude: string + math + graphics helpers used by emitted code --- */
char *PRELUDE =
"char* __bcat(char*a,char*b){char*r=(char*)malloc(strlen(a)+strlen(b)+1);strcpy(r,a);strcat(r,b);return r;}\n"
"char* __left(char*s,int n){int L=strlen(s);if(n<0)n=0;if(n>L)n=L;char*r=(char*)malloc(n+1);memcpy(r,s,n);r[n]=0;return r;}\n"
"char* __right(char*s,int n){int L=strlen(s);if(n<0)n=0;if(n>L)n=L;char*r=(char*)malloc(n+1);memcpy(r,s+L-n,n);r[n]=0;return r;}\n"
"char* __mid(char*s,int i,int n){int L=strlen(s);i--;if(i<0)i=0;if(i>L)i=L;if(n<0||i+n>L)n=L-i;char*r=(char*)malloc(n+1);memcpy(r,s+i,n);r[n]=0;return r;}\n"
"char* __chr(int c){char*r=(char*)malloc(2);r[0]=(char)c;r[1]=0;return r;}\n"
"char* __str(double d){char*r=(char*)malloc(40);if(d==(double)(int)d)sprintf(r,\" %d\",(int)d);else sprintf(r,\" %g\",d);return r;}\n"
"char* __ucase(char*s){char*r=(char*)malloc(strlen(s)+1);int i=0;while(s[i]){char c=s[i];if(c>='a'&&c<='z')c-=32;r[i]=c;i++;}r[i]=0;return r;}\n"
"char* __lcase(char*s){char*r=(char*)malloc(strlen(s)+1);int i=0;while(s[i]){char c=s[i];if(c>='A'&&c<='Z')c+=32;r[i]=c;i++;}r[i]=0;return r;}\n"
"char* __spacef(int n){if(n<0)n=0;char*r=(char*)malloc(n+1);int i;for(i=0;i<n;i++)r[i]=' ';r[n]=0;return r;}\n"
"char* __stringf(int n,int c){if(n<0)n=0;char*r=(char*)malloc(n+1);int i;for(i=0;i<n;i++)r[i]=(char)c;r[n]=0;return r;}\n"
"int __instr(char*h,char*n){char*p=strstr(h,n);return p?(int)(p-h)+1:0;}\n"
"int __instr2(int st,char*h,char*n){if(st<1)st=1;char*p=strstr(h+st-1,n);return p?(int)(p-h)+1:0;}\n"
"char* __inputline(){char*b=(char*)malloc(1024);int i=0,c;while((c=getchar())!=-1&&c!=10){if(c!=13&&i<1023)b[i++]=(char)c;}b[i]=0;return b;}\n"
"void __pn(double d){printf(d<0?\"%g \":\" %g \",d);}\n"
"void __pni(int n){printf(n<0?\"%d \":\" %d \",n);}\n"
"int __sgn(double d){return d>0?1:(d<0?-1:0);}\n"
"double* __refd(double v){double* p=(double*)malloc(8); *p=v; return p;}\n"   /* by-ref temp cells (non-lvalue args) */
"int* __refi(int v){int* p=(int*)malloc(4); *p=v; return p;}\n"
"char** __refs(char* v){char** p=(char**)malloc(8); *p=v; return p;}\n"
"int __qcolor=0xFFFFFF;\n"
"int __qbcolor(int c){int p[16];p[0]=0;p[1]=0x0000AA;p[2]=0x00AA00;p[3]=0x00AAAA;p[4]=0xAA0000;p[5]=0xAA00AA;p[6]=0xAA5500;p[7]=0xAAAAAA;p[8]=0x555555;p[9]=0x5555FF;p[10]=0x55FF55;p[11]=0x55FFFF;p[12]=0xFF5555;p[13]=0xFF55FF;p[14]=0xFFFF55;p[15]=0xFFFFFF;if(c<0)c=0;if(c>15)c=15;return p[c];}\n"
"void __linebox(int x0,int y0,int x1,int y1,int col,int fill){if(fill){int y;for(y=y0;y<=y1;y++)gfx_line(x0,y,x1,y,col);}else{gfx_line(x0,y0,x1,y0,col);gfx_line(x0,y1,x1,y1,col);gfx_line(x0,y0,x0,y1,col);gfx_line(x1,y0,x1,y1,col);}}\n";

void emit_globals(void)
{
    int i;
    for (i = 0; i < nv; i++)
    {
        if (vt_isarr[i])
        {
            if (vt_n2[i] > 0) ef(F4("%s %s[%s][%s];\n", ctype(vt_type[i]), vt_name[i], istr(vt_n1[i]), istr(vt_n2[i])));
            else ef(F3("%s %s[%s];\n", ctype(vt_type[i]), vt_name[i], istr(vt_n1[i] > 0 ? vt_n1[i] : 11)));
        }
        else
        {
            ef(F3("%s %s = %s;\n", ctype(vt_type[i]), vt_name[i], vt_type[i] == T_STR ? (char *)"(char*)\"\"" : (char *)"0"));
        }
    }
    /* initialize string array elements to "" so PRINT never hits a NULL */
    for (i = 0; i < nv; i++)
        if (vt_isarr[i] && vt_type[i] == T_STR)
        {
            int tot = (vt_n1[i] > 0 ? vt_n1[i] : 11) * (vt_n2[i] > 0 ? vt_n2[i] : 1);
            ef(F2("int __gi_%s; char** __gp_%s = (char**)", istr(i), istr(i)));
            ef(F1("%s;\n", vt_name[i]));
            ef(F3("void __ginit_%s(){for(__gi_%s=0;__gi_%s<", istr(i), istr(i), istr(i)));
            ef(F2("%s;__gi_%s++)", istr(tot), istr(i)));
            ef(F2("__gp_%s[__gi_%s]=(char*)\"\";}\n", istr(i), istr(i)));
        }
}

void emit_strarr_init(void)
{
    int i;
    for (i = 0; i < nv; i++)
        if (vt_isarr[i] && vt_type[i] == T_STR) ef(F1("  __ginit_%s();\n", istr(i)));
}

void setext(char *path, char *ext) { int n = strlen(path), i = n - 1; while (i > 0 && path[i] != '.' && path[i] != '\\' && path[i] != '/') i--; if (path[i] == '.') path[i + 1] = 0; else strcat(path, "."); strcat(path, ext); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: qbasic <file.bas> [-o <out.exe>]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int i;
    for (i = 2; i < argc; i++) if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) { o = (char *)argv[i + 1]; i++; }
    char outexe[1024]; char cpath[1024];
    if (o) strcpy(outexe, o); else { strcpy(outexe, in); setext(outexe, "exe"); }
    strcpy(cpath, outexe); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"qbasic: cannot read %s\n", (int)in); return 1; }
    qbfile = in; mainbuf = ""; g_params = ""; g_funcbase = "";

    /* pass 1: collect symbols */
    g_pass = 1; g_infunc = 0; yy_scan_string((int)src); yyparse();

    out = fopen((int)cpath, (int)"w");
    if (out == 0) { printf((int)"qbasic: cannot write %s\n", (int)cpath); return 1; }

    /* pass 2: emit (functions go straight to file; top-level code -> mainbuf) */
    g_pass = 2; g_infunc = 0; pline = 1; tokln = 1; mainbuf = "";
    ef(F1("#line 1 \"%s\"\n", qbfile));   /* make the .bas the PDB's primary document (cc maps line #s but not filename per-#line) */
    ef(PRELUDE);
    emit_globals();
    yy_scan_string((int)src); yyparse();

    ef("int main(int __argc, char** __argv) {\n");
    emit_strarr_init();
    ef(mainbuf);
    ef("  return 0;\n}\n");
    fclose(out);

    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; char icon[1100]; sprintf((int)icon, (int)"%s\\icons\\qbasic.png", (int)repo);
    av[0] = (int)cc; av[1] = (int)cpath; av[2] = (int)"-o"; av[3] = (int)outexe; av[4] = (int)"--exe"; av[5] = (int)"--icon"; av[6] = (int)icon;
    int rc = sh_run((int)av, 7);
    if (rc == 0) printf((int)"qbasic: %s -> %s\n", (int)in, (int)outexe);
    else printf((int)"qbasic: cc failed (%d)\n", rc);
    return rc;
}
