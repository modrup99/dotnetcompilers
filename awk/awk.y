%{
/* AWK -> C (yacc); cc lowers the C to .NET IL. AWK values are dynamically typed
 * (number or string), so every value is represented as a char* with numeric coercion on
 * demand (an() parses, as() formats with %.6g / integer form) -- the same "boxed any"
 * idea Forth used with a .NET stack. Records split into fields ($0..$NF); arrays are
 * string-keyed hash maps; a compact backtracking matcher provides regex. Two passes:
 * pass 1 classifies each name as scalar vs array (used with []); pass 2 emits. The
 * program is assembled into BEGIN / per-record main / END sections + functions. */
int g_pass;
int g_tgt;                 /* 0 main, 1 BEGIN, 2 END, 3 functions */
char *g_begin, *g_main, *g_end, *g_funcs;
int g_infunc; char *g_params[64]; int g_nparam;
char *g_fiv, *g_fia;       /* for-in: loop variable + array names (safe as globals: no
                            * nested loop can be parsed between their markers and use) */

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 8); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 8); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *istr(int n) { char b[24]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *cstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"'; while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; if (s[i] == 10) { r[j++] = '\\'; r[j++] = 'n'; i++; continue; } r[j++] = s[i++]; } r[j++] = '"'; r[j] = 0; return r; }
void ap(char *s) { if (g_pass != 2) return; if (g_tgt == 1) g_begin = j2(g_begin, s); else if (g_tgt == 2) g_end = j2(g_end, s); else if (g_tgt == 3) g_funcs = j2(g_funcs, s); else g_main = j2(g_main, s); }

/* symbol table: variables (scalar/array) and function names */
char *sy_name[2000]; int sy_arr[2000]; int nsy;
int sy_find(char *n) { int i; for (i = 0; i < nsy; i++) if (strcmp(sy_name[i], n) == 0) return i; return -1; }
void sy_mark(char *n, int arr) { int i = sy_find(n); if (i < 0) { sy_name[nsy] = n; sy_arr[nsy] = arr; nsy++; } else if (arr) sy_arr[i] = 1; }
char *fn_name[500]; int nfn;
int fn_find(char *n) { int i; for (i = 0; i < nfn; i++) if (strcmp(fn_name[i], n) == 0) return i; return -1; }
int is_param(char *n) { int i; for (i = 0; i < g_nparam; i++) if (strcmp(g_params[i], n) == 0) return 1; return 0; }

char *cvar(char *nm) { char *r = (char *)malloc(strlen(nm) + 4); strcpy(r, "v_"); strcat(r, nm); return r; }
char *carr(char *nm) { char *r = (char *)malloc(strlen(nm) + 4); strcpy(r, "a_"); strcat(r, nm); return r; }
void sy_mark(char *n, int arr);
char *arrref(char *nm) { sy_mark((char *)strdup((int)nm), 1); return carr(nm); }   /* an array passed by reference (split's target) */

int isbuiltin(char *n) { return strcmp(n, "length") == 0 || strcmp(n, "substr") == 0 || strcmp(n, "index") == 0 || strcmp(n, "split") == 0 || strcmp(n, "sub") == 0 || strcmp(n, "gsub") == 0 || strcmp(n, "match") == 0 || strcmp(n, "sprintf") == 0 || strcmp(n, "sin") == 0 || strcmp(n, "cos") == 0 || strcmp(n, "sqrt") == 0 || strcmp(n, "exp") == 0 || strcmp(n, "log") == 0 || strcmp(n, "int") == 0 || strcmp(n, "atan2") == 0 || strcmp(n, "toupper") == 0 || strcmp(n, "tolower") == 0 || strcmp(n, "rand") == 0 || strcmp(n, "srand") == 0; }

int yylex(); void yyerror(char *m);
struct AG { int n; int a[64]; };
int ag_new(); int ag_add(int h, int e);
%}
%token NUMBER STRING REGEX NAME NEWLINE
%token KBEGIN KEND KFUNCTION KIF KELSE KWHILE KFOR KDO KBREAK KCONTINUE KNEXT KEXIT KRETURN KDELETE KIN KPRINT KPRINTF KSPLIT
%token ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN POW_ASSIGN
%token EQ NE LE GE APPEND AND OR NOMATCH INCR DECR
%right '=' ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN POW_ASSIGN
%right '?' ':'
%left OR
%left AND
%left KIN
%left '~' NOMATCH
%nonassoc EQ NE '<' '>' LE GE
%left CONCAT
%left '+' '-'
%left '*' '/' '%'
%right '!' UMINUS
%right '^'
%left '$'
%%
program : items ;
items   : | items item | items NEWLINE | items ';' ;
item    : KBEGIN tbeg block       { g_tgt = 0; }
        | KEND tend block         { g_tgt = 0; }
        | block
        | expr lbrg stmts '}'     { if (g_pass == 2) ap("}\n"); }
        | expr                    { if (g_pass == 2) ap(F1("if (atruth(%s)) awkp0();\n", ecode($1))); }
        | KFUNCTION fhead block   { if (g_pass == 2) ap("return _emptys;\n}\n"); g_tgt = 0; g_infunc = 0; } ;
tbeg    : { g_tgt = 1; } ;
tend    : { g_tgt = 2; } ;
/* pattern-action: guard emitted when the '{' is shifted (no empty marker after expr, so
 * no reduce/reduce against the pattern-only `item: expr`); the parser shifts '{' here and
 * reduces `item: expr` only on a statement terminator. */
lbrg    : '{'                     { if (g_pass == 2) ap(F1("if (atruth(%s)) {\n", ecode($0))); } ;
fhead   : NAME freset '(' params ')'     { fn_begin((char *)$1); } ;
freset  : { g_nparam = 0; } ;
params  : | plist ;
plist   : NAME { g_params[g_nparam++] = (char *)$1; } | plist ',' NAME { g_params[g_nparam++] = (char *)$3; } ;

block   : lbr stmts '}'           { if (g_pass == 2) ap("}\n"); } ;
lbr     : '{'                     { if (g_pass == 2) ap("{\n"); } ;
stmts   : | stmts stmt | stmts NEWLINE | stmts ';' ;

stmt : simple
     | simple term
     | KIF '(' expr ifg ')' stmt                  { if (g_pass == 2) ap("}\n"); }
     | KIF '(' expr ifg ')' stmt KELSE elo stmt   { if (g_pass == 2) ap("}\n"); }
     | KWHILE '(' expr wg ')' stmt                { if (g_pass == 2) ap("}\n"); }
     | KDO doo stmt KWHILE '(' expr ')'        { if (g_pass == 2) ap(F1("} while (atruth(%s));\n", ecode($6))); }
     | KFOR '(' foropt finit ';' expr fcond ';' foropt ')' stmt
         { if (g_pass == 2) { char *ic = ecode($9); if (ic[0]) ap(F1("%s;\n", ic)); ap("}\n}\n"); } }
     | KFOR '(' NAME fivar KIN NAME fiarr ')' fibody stmt
         { if (g_pass == 2) ap("} }\n"); }
     | block ;
term : NEWLINE | ';' ;
ifg  : { if (g_pass == 2) ap(F1("if (atruth(%s)) {\n", ecode($0))); } ;   /* $0 = expr (marker sits right after it) */
elo  : { if (g_pass == 2) ap("} else {\n"); } ;
wg   : { if (g_pass == 2) ap(F1("while (atruth(%s)) {\n", ecode($0))); } ;   /* $0 = expr */
doo  : { if (g_pass == 2) ap("do {\n"); } ;
foropt : { $$ = mkE(""); } | expr { $$ = $1; } ;
finit  : { if (g_pass == 2) { char *ic = ecode($0); ap("{\n"); if (ic[0]) ap(F1("%s;\n", ic)); } } ;
fcond  : { if (g_pass == 2) ap(F1("while (atruth(%s)) {\n", ecode($0))); } ;
fivar  : { g_fiv = (char *)$0; } ;
fiarr  : { g_fia = (char *)$0; } ;
fibody : { if (g_pass == 2) do_forin(g_fiv, g_fia); } ;

simple : KPRINT prlist               { do_print($2); }
       | KPRINT                      { if (g_pass == 2) ap("awkp0();\n"); }
       | KPRINTF prlist              { do_printf($2); }
       | KDELETE NAME '[' expr ']'   { if (g_pass == 2) ap(F2("adel(%s, %s);\n", carr((char *)$2), ecode($4))); }
       | KNEXT                       { if (g_pass == 2) ap("goto __next;\n"); }
       | KEXIT                       { if (g_pass == 2) ap("exit(0);\n"); }
       | KEXIT expr                  { if (g_pass == 2) ap(F1("exit((int)an(%s));\n", ecode($2))); }
       | KRETURN                     { if (g_pass == 2) ap("return _emptys;\n"); }
       | KRETURN expr                { if (g_pass == 2) ap(F1("return %s;\n", ecode($2))); }
       | KBREAK                      { if (g_pass == 2) ap("break;\n"); }
       | KCONTINUE                   { if (g_pass == 2) ap("continue;\n"); }
       | expr                        { if (g_pass == 2) ap(F1("%s;\n", ecode($1))); } ;

prlist : expr { $$ = ag_add(ag_new(), $1); } | prlist ',' expr { $$ = ag_add($1, $3); } | { $$ = ag_new(); } ;

expr : expr expr %prec CONCAT { $$ = mkE(F2("acat(%s, %s)", ecode($1), ecode($2))); }
     | expr '+' expr   { $$ = bin($1, "an(%s) + an(%s)", $3); }
     | expr '-' expr   { $$ = bin($1, "an(%s) - an(%s)", $3); }
     | expr '*' expr   { $$ = bin($1, "an(%s) * an(%s)", $3); }
     | expr '/' expr   { $$ = bin($1, "an(%s) / an(%s)", $3); }
     | expr '%' expr   { $$ = mkE(F2("as(fmod(an(%s), an(%s)))", ecode($1), ecode($3))); }
     | expr '^' expr   { $$ = mkE(F2("as(pow(an(%s), an(%s)))", ecode($1), ecode($3))); }
     | '-' expr %prec UMINUS { $$ = mkE(F1("as(-an(%s))", ecode($2))); }
     | '!' expr        { $$ = mkE(F1("(atruth(%s) ? _zero : _one)", ecode($2))); }
     | expr '<' expr   { $$ = rel($1, "< 0", $3); }
     | expr LE expr    { $$ = rel($1, "<= 0", $3); }
     | expr '>' expr   { $$ = rel($1, "> 0", $3); }
     | expr GE expr    { $$ = rel($1, ">= 0", $3); }
     | expr EQ expr    { $$ = rel($1, "== 0", $3); }
     | expr NE expr    { $$ = rel($1, "!= 0", $3); }
     | expr AND expr   { $$ = mkE(F2("((atruth(%s) && atruth(%s)) ? _one : _zero)", ecode($1), ecode($3))); }
     | expr OR expr    { $$ = mkE(F2("((atruth(%s) || atruth(%s)) ? _one : _zero)", ecode($1), ecode($3))); }
     | expr '~' expr   { $$ = mkE(F2("(re_match(%s, %s) ? _one : _zero)", ecode($1), ecode($3))); }
     | expr NOMATCH expr { $$ = mkE(F2("(re_match(%s, %s) ? _zero : _one)", ecode($1), ecode($3))); }
     | expr '~' REGEX  { $$ = mkE(F2("(re_match(%s, %s) ? _one : _zero)", ecode($1), cstr((char *)$3))); }
     | expr NOMATCH REGEX { $$ = mkE(F2("(re_match(%s, %s) ? _zero : _one)", ecode($1), cstr((char *)$3))); }
     | expr '?' expr ':' expr { $$ = mkE(j2(F1("(atruth(%s) ? ", ecode($1)), j4(ecode($3), " : ", ecode($5), ")"))); }
     | expr KIN NAME   { $$ = mkE(F2("(ahas(%s, %s) ? _one : _zero)", carr((char *)$3), ecode($1))); }
     | '(' expr ')'    { $$ = mkE(F1("(%s)", ecode($2))); }
     | lvalue '=' expr        { $$ = asgn($1, ecode($3)); }
     | lvalue ADD_ASSIGN expr { $$ = asgn($1, F2("as(an(%s) + an(%s))", lcode($1), ecode($3))); }
     | lvalue SUB_ASSIGN expr { $$ = asgn($1, F2("as(an(%s) - an(%s))", lcode($1), ecode($3))); }
     | lvalue MUL_ASSIGN expr { $$ = asgn($1, F2("as(an(%s) * an(%s))", lcode($1), ecode($3))); }
     | lvalue DIV_ASSIGN expr { $$ = asgn($1, F2("as(an(%s) / an(%s))", lcode($1), ecode($3))); }
     | lvalue MOD_ASSIGN expr { $$ = asgn($1, F2("as(fmod(an(%s), an(%s)))", lcode($1), ecode($3))); }
     | INCR lvalue     { $$ = asgn($2, F1("as(an(%s) + 1)", lcode($2))); }
     | DECR lvalue     { $$ = asgn($2, F1("as(an(%s) - 1)", lcode($2))); }
     | lvalue INCR     { $$ = asgn($1, F1("as(an(%s) + 1)", lcode($1))); }
     | lvalue DECR     { $$ = asgn($1, F1("as(an(%s) - 1)", lcode($1))); }
     | NUMBER          { $$ = mkE(cstr((char *)$1)); }
     | STRING          { $$ = mkE(cstr((char *)$1)); }
     | REGEX           { $$ = mkE(F1("(re_match(getfield(0), %s) ? _one : _zero)", cstr((char *)$1))); }
     | NAME '(' args ')' { $$ = callf((char *)$1, $3); }
     | KSPLIT '(' expr ',' NAME ')'          { $$ = mkE(F2("as((double)awksplit(%s, %s, _fs))", ecode($3), arrref((char *)$5))); }
     | KSPLIT '(' expr ',' NAME ',' expr ')' { $$ = mkE(j3(F2("as((double)awksplit(%s, %s, ", ecode($3), arrref((char *)$5)), ecode($7), "))")); }
     | lvalue          { $$ = mkE(lcode($1)); } ;

lvalue : NAME              { $$ = lv((char *)$1, 0); }
       | NAME '[' expr ']' { $$ = lv((char *)$1, $3); }
       | '$' expr          { $$ = lvf($2); } ;

args : { $$ = ag_new(); } | arglist ;
arglist : expr { $$ = ag_add(ag_new(), $1); } | arglist ',' expr { $$ = ag_add($1, $3); } ;
%%

void yyerror(char *m) { printf((int)"awk: %s (line %d)\n", (int)m, pline); }

struct E { char *code; };
int mkE(char *c) { struct E *e = (struct E *)malloc(4); e->code = c; return (int)e; }
char *ecode(int h) { return ((struct E *)h)->code; }
int bin(int a, char *f, int b) { return mkE(j3("as(", F2(f, ecode(a), ecode(b)), ")")); }
int rel(int a, char *op, int b) { return mkE(j2("(acmp(", j4(ecode(a), ", ", ecode(b), j3(") ", op, " ? _one : _zero)")))); }

/* lvalue handle: kind 0 scalar, 1 array, 2 field */
struct LV { int kind; char *base; char *key; };
int lv(char *nm, int keyh) { struct LV *l = (struct LV *)malloc(12); if (keyh) { l->kind = 1; l->base = carr(nm); l->key = ecode(keyh); sy_mark(strdup(nm), 1); } else { l->kind = 0; l->base = cvar(nm); l->key = 0; sy_mark(strdup(nm), 0); } return (int)l; }
int lvf(int idxh) { struct LV *l = (struct LV *)malloc(12); l->kind = 2; l->base = 0; l->key = ecode(idxh); return (int)l; }
char *lcode(int h) { struct LV *l = (struct LV *)h; if (l->kind == 0) return l->base; if (l->kind == 1) return F2("aget(%s, %s)", l->base, l->key); return F1("getfield((int)an(%s))", l->key); }
int asgn(int h, char *rv) { struct LV *l = (struct LV *)h; if (g_pass != 2) return mkE("_emptys"); if (l->kind == 0) return mkE(F2("(%s = %s)", l->base, rv)); if (l->kind == 1) return mkE(j2(F2("aset(%s, %s, ", l->base, l->key), j2(rv, ")"))); return mkE(F2("setfield((int)an(%s), %s)", l->key, rv)); }

struct AG { int n; int a[64]; };
int ag_new() { struct AG *g = (struct AG *)malloc(260); g->n = 0; return (int)g; }
int ag_add(int h, int e) { struct AG *g = (struct AG *)h; g->a[g->n++] = e; return h; }

char *arglist_code(struct AG *g, int from) { char *s = ""; int i; for (i = from; i < g->n; i++) s = j3(s, ", ", ecode(g->a[i])); return s; }
char *eight(struct AG *g, int from) { char *s = ""; int i; for (i = 0; i < 8; i++) { char *a = (from + i < g->n) ? ecode(g->a[from + i]) : "_emptys"; s = j3(s, ", ", a); } return s; }
int callf(char *nm, int argh)
{
    struct AG *g = (struct AG *)argh; int i;
    if (strcmp(nm, "length") == 0) return mkE(g->n ? F1("as((double)strlen(%s))", ecode(g->a[0])) : (char *)"as((double)strlen(getfield(0)))");
    if (strcmp(nm, "substr") == 0)
    {
        if (g->n >= 3) return mkE(j2(F2("awksubstr(%s, (int)an(%s), ", ecode(g->a[0]), ecode(g->a[1])), F1("(int)an(%s))", ecode(g->a[2]))));
        return mkE(F2("awksubstr(%s, (int)an(%s), 1000000)", ecode(g->a[0]), ecode(g->a[1])));
    }
    if (strcmp(nm, "index") == 0) return mkE(F2("as((double)awkindex(%s, %s))", ecode(g->a[0]), ecode(g->a[1])));
    if (strcmp(nm, "toupper") == 0) return mkE(F1("awkupper(%s)", ecode(g->a[0])));
    if (strcmp(nm, "tolower") == 0) return mkE(F1("awklower(%s)", ecode(g->a[0])));
    if (strcmp(nm, "int") == 0) return mkE(F1("as((double)(int)an(%s))", ecode(g->a[0])));
    if (strcmp(nm, "sqrt") == 0) return mkE(F1("as(sqrt(an(%s)))", ecode(g->a[0])));
    if (strcmp(nm, "sin") == 0) return mkE(F1("as(sin(an(%s)))", ecode(g->a[0])));
    if (strcmp(nm, "cos") == 0) return mkE(F1("as(cos(an(%s)))", ecode(g->a[0])));
    if (strcmp(nm, "exp") == 0) return mkE(F1("as(exp(an(%s)))", ecode(g->a[0])));
    if (strcmp(nm, "log") == 0) return mkE(F1("as(log(an(%s)))", ecode(g->a[0])));
    if (strcmp(nm, "atan2") == 0) return mkE(F2("as(atan2(an(%s), an(%s)))", ecode(g->a[0]), ecode(g->a[1])));
    if (strcmp(nm, "sprintf") == 0) return mkE(j4("awkfmt(", ecode(g->a[0]), j2(", ", istr(g->n - 1)), j2(eight(g, 1), ")")));
    return mkE(j4("f_", nm, "(", j2((g->n ? arglist_code(g, 0) + 2 : ""), ")")));
}

void do_print(int argh)
{
    if (g_pass != 2) return;
    struct AG *g = (struct AG *)argh; int i;
    if (g->n == 0) { ap("awkp0();\n"); return; }
    for (i = 0; i < g->n; i++) { ap(F1("awkout(%s);\n", ecode(g->a[i]))); if (i + 1 < g->n) ap("awkout(_ofs);\n"); }
    ap("awkout(_ors);\n");
}
void do_printf(int argh)
{
    if (g_pass != 2) return;
    struct AG *g = (struct AG *)argh;
    ap(j2(F2("awkout(awkfmt(%s, %s", ecode(g->a[0]), istr(g->n - 1)), j2(eight(g, 1), "));\n")));
}
void do_forin(char *v, char *arr)
{
    if (g_pass != 2) return;
    ap(j2(F2("{ AwkIter __it; for (aiter_init(&__it, %s); aiter_next(&__it); )", carr(arr), ""), F1(" { %s = aiter_key(&__it);\n", cvar(v))));
}
void fn_begin(char *nm)
{
    if (g_pass == 1) { fn_name[nfn++] = nm; return; }
    g_tgt = 3; g_infunc = 1;
    char *sig = ""; int i;
    for (i = 0; i < g_nparam; i++) sig = (i == 0) ? j2("char* ", cvar(g_params[i])) : j3(sig, ", char* ", cvar(g_params[i]));
    ap(j4("char* f_", nm, "(", j3(sig, ") {\n", "")));
}

char *PRELUDE =
"char* _emptys; char* _one; char* _zero; char* _ofs; char* _ors; char* _fs;\n"
"char* getfield(int i); char* setfield(int i,char*v);\n"
"double an(char*s){ if(!s)return 0; return strtod(s,0); }\n"
"char* as(double d){ char b[48]; if(d==(double)(int)d && d<2100000000.0 && d>-2100000000.0) sprintf(b,\"%d\",(int)d); else sprintf(b,\"%.6g\",d); return strdup(b); }\n"
"int isnum(char*s){ if(!s||!*s)return 0; char*e; while(*s==' '||*s==9)s++; if(!*s)return 0; strtod(s,&e); while(*e==' '||*e==9)e++; return *e==0; }\n"
"int atruth(char*s){ if(!s)return 0; if(isnum(s))return an(s)!=0.0; return s[0]!=0; }\n"
"int acmp(char*a,char*b){ if(isnum(a)&&isnum(b)){ double x=an(a),y=an(b); return x<y?-1:(x>y?1:0);} int c=strcmp(a,b); return c<0?-1:(c>0?1:0); }\n"
"char* acat(char*a,char*b){ char*r=(char*)malloc(strlen(a)+strlen(b)+1); strcpy(r,a); strcat(r,b); return r; }\n"
"char* awkupper(char*s){ char*r=strdup(s); int i=0; while(r[i]){ if(r[i]>='a'&&r[i]<='z')r[i]-=32; i++; } return r; }\n"
"char* awklower(char*s){ char*r=strdup(s); int i=0; while(r[i]){ if(r[i]>='A'&&r[i]<='Z')r[i]+=32; i++; } return r; }\n"
"int awkindex(char*s,char*t){ int i=0,j; if(!*t)return 0; while(s[i]){ j=0; while(t[j]&&s[i+j]==t[j])j++; if(!t[j])return i+1; i++; } return 0; }\n"
"char* awksubstr(char*s,int m,int n){ int L=strlen(s); if(m<1)m=1; int st=m-1; if(st>L)st=L; int len=n; if(len<0)len=0; if(st+len>L)len=L-st; char*r=(char*)malloc(len+1); int i; for(i=0;i<len;i++)r[i]=s[st+i]; r[len]=0; return r; }\n"
/* regex: literals . * + ? [] ^ $ \\  (no alternation/groups) */
"int re_one(char p,char c){ return p=='.' ? c!=0 : p==c; }\n"
"int re_here(char*p,char*s);\n"
"int re_star(char*p1,char*p,char*s){ do{ if(re_here(p,s))return 1; }while(*s && re_one(*p1,*s++)); return 0; }\n"
"int re_class(char**pp,char c){ char*p=*pp+1; int neg=0,m=0; if(*p=='^'){neg=1;p++;} while(*p&&*p!=']'){ if(p[1]=='-'&&p[2]&&p[2]!=']'){ if(c>=p[0]&&c<=p[2])m=1; p+=3; } else { if(c==*p)m=1; p++; } } if(*p==']')p++; *pp=p; return neg?!m:m; }\n"
"int re_here(char*p,char*s){ if(p[0]==0)return 1; if(p[0]=='$'&&p[1]==0)return *s==0; if(p[0]=='['){ char*pp=p; int ok=re_class(&pp,*s); if(*s&&ok){ if(*pp=='*')return re_here(pp,s)||re_here(pp+1,s+1); if(*pp=='+')return re_here(pp,s+1); if(*pp=='?')return re_here(pp+1,s+1)||re_here(pp+1,s); return re_here(pp,s+1);} if(*pp=='*'||*pp=='?')return re_here(pp+1,s); return 0; } char pc=p[0]; if(pc=='\\\\'&&p[1]){pc=p[1];p++;} if(p[1]=='*')return re_star(p,p+2,s); if(p[1]=='+')return *s&&re_one(pc,*s)?re_star(p,p+2,s+1):0; if(p[1]=='?'){ if(*s&&re_one(pc,*s)&&re_here(p+2,s+1))return 1; return re_here(p+2,s);} if(*s&&re_one(pc,*s))return re_here(p+1,s+1); return 0; }\n"
"int re_match(char*s,char*re){ if(re[0]=='^')return re_here(re+1,s); do{ if(re_here(re,s))return 1; }while(*s++); return 0; }\n"
/* arrays */
"typedef struct Cell{char*k;char*v;struct Cell*nx;}Cell; typedef struct{Cell*b[211];}Arr;\n"
"int ahash(char*s){ unsigned h=0; while(*s)h=h*31+(unsigned char)*s++; return h%211; }\n"
"char* aset(Arr*a,char*k,char*v){ int h=ahash(k); Cell*c=a->b[h]; while(c){ if(strcmp(c->k,k)==0){c->v=strdup(v);return v;} c=c->nx; } c=(Cell*)malloc(sizeof(Cell)); c->k=strdup(k); c->v=strdup(v); c->nx=a->b[h]; a->b[h]=c; return v; }\n"
"char* aget(Arr*a,char*k){ Cell*c=a->b[ahash(k)]; while(c){ if(strcmp(c->k,k)==0)return c->v; c=c->nx; } aset(a,k,_emptys); return _emptys; }\n"
"int ahas(Arr*a,char*k){ Cell*c=a->b[ahash(k)]; while(c){ if(strcmp(c->k,k)==0)return 1; c=c->nx; } return 0; }\n"
"void adel(Arr*a,char*k){ int h=ahash(k); Cell*c=a->b[h],*p=0; while(c){ if(strcmp(c->k,k)==0){ if(p)p->nx=c->nx; else a->b[h]=c->nx; return; } p=c; c=c->nx; } }\n"
"typedef struct{Arr*a;int bi;Cell*c;}AwkIter; void aiter_init(AwkIter*it,Arr*a){it->a=a;it->bi=-1;it->c=0;} int aiter_next(AwkIter*it){ if(it->c)it->c=it->c->nx; while(!it->c){ it->bi++; if(it->bi>=211)return 0; it->c=it->a->b[it->bi]; } return 1; } char* aiter_key(AwkIter*it){ return it->c->k; }\n"
"int awksplit(char*s,Arr*a,char*fs){ int n=0; char buf[4096]; int bi=0; int i=0; char sep=fs[0]; while(1){ char c=s[i]; if(c==0||(sep==' '?(c==' '||c==9):(c==sep))){ if(sep!=' '||bi>0||c==0){ if(!(sep==' '&&bi==0&&c==0)){ buf[bi]=0; n++; char kb[16]; sprintf(kb,\"%d\",n); aset(a,kb,buf); bi=0; } } if(sep==' '){ while(s[i]==' '||s[i]==9)i++; if(s[i]==0)break; continue; } if(c==0)break; i++; } else buf[bi++]=c, i++; } return n; }\n"
"int awkisconv(char c){ return c=='d'||c=='i'||c=='o'||c=='u'||c=='x'||c=='X'||c=='e'||c=='E'||c=='f'||c=='g'||c=='G'||c=='c'||c=='s'; }\n"
"char* awkfmt(char*fmt,int n,char*a0,char*a1,char*a2,char*a3,char*a4,char*a5,char*a6,char*a7){ char* args[8]; args[0]=a0;args[1]=a1;args[2]=a2;args[3]=a3;args[4]=a4;args[5]=a5;args[6]=a6;args[7]=a7; char* out=(char*)malloc(8192); int o=0,ai=0,i=0; while(fmt[i]){ if(fmt[i]!='%'){ out[o++]=fmt[i++]; continue; } if(fmt[i+1]=='%'){ out[o++]='%'; i+=2; continue; } char spec[40]; int si=0; spec[si++]=fmt[i++]; while(fmt[i]&&!awkisconv(fmt[i])&&si<38){ spec[si++]=fmt[i++]; } char conv=fmt[i]; spec[si++]=conv; spec[si]=0; if(fmt[i])i++; char* arg=(ai<8&&ai<n)?args[ai]:_emptys; ai++; char tmp[512]; if(conv=='d'||conv=='i'||conv=='o'||conv=='u'||conv=='x'||conv=='X'){ sprintf(tmp,spec,(int)an(arg)); } else if(conv=='c'){ sprintf(tmp,spec, isnum(arg)?(int)an(arg):(int)arg[0]); } else if(conv=='e'||conv=='E'||conv=='f'||conv=='g'||conv=='G'){ sprintf(tmp,spec,an(arg)); } else { sprintf(tmp,spec,arg); } int k=0; while(tmp[k])out[o++]=tmp[k++]; } out[o]=0; return out; }\n"
"void awkout(char*s){ printf(\"%s\",s); }\n"
"void awkp0(void){ printf(\"%s%s\", getfield(0), _ors); }\n";

char *FIELDS =
"char* g_f0; char* g_field[256]; int g_nf;\n"
"char* getfield(int i){ if(i==0)return g_f0?g_f0:_emptys; if(i>=1&&i<=g_nf)return g_field[i]; return _emptys; }\n"
"char* setfield(int i,char*v){ if(i>=1&&i<256){ g_field[i]=strdup(v); if(i>g_nf)g_nf=i; } return v; }\n"
"void setrec(char*line){ g_f0=line; g_nf=0; int i=0; char sep=_fs[0]; char buf[4096]; int bi=0; while(1){ char c=line[i]; if(c==0||(sep==' '?(c==' '||c==9):c==sep)){ if(sep==' '){ if(bi>0){ buf[bi]=0; g_field[++g_nf]=strdup(buf); bi=0; } while(line[i]==' '||line[i]==9)i++; if(line[i]==0)break; continue; } else { buf[bi]=0; g_field[++g_nf]=strdup(buf); bi=0; if(c==0)break; i++; } } else { buf[bi++]=c; i++; } } }\n";

void awkprintf_decl() {}

void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: awk <prog.awk> [-o out]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], cpath[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, "exe"); }
    strcpy(cpath, outp); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (!src) { printf((int)"awk: cannot read %s\n", (int)in); return 1; }
    nsy = 0; nfn = 0;
    sy_mark((char *)"NR", 0); sy_mark((char *)"NF", 0); sy_mark((char *)"FS", 0); sy_mark((char *)"OFS", 0); sy_mark((char *)"ORS", 0);
    g_pass = 1; yy_scan_string((int)src); yyparse();
    g_pass = 2; g_begin = ""; g_main = ""; g_end = ""; g_funcs = ""; g_tgt = 0; pline = 1; yy_scan_string((int)src); yyparse();

    int f = fopen((int)cpath, (int)"w");
    fputs((int)PRELUDE, f); fputs((int)FIELDS, f);
    /* declare scalar + array variables */
    for (i = 0; i < nsy; i++) { if (sy_arr[i]) { fputs((int)j3("Arr* ", carr(sy_name[i]), ";\n"), f); } else { fputs((int)j3("char* ", cvar(sy_name[i]), ";\n"), f); } }
    /* awk_init: set up the special vars + globals. main() calls it; a C#/VB.NET host
     * calls it once before invoking any compiled awk function (f_<name>) directly. */
    fputs((int)"void awk_init() {\n", f);
    fputs((int)"_emptys=\"\"; _one=\"1\"; _zero=\"0\"; _ofs=\" \"; _ors=\"\\n\"; _fs=\" \";\n", f);
    for (i = 0; i < nsy; i++) { if (sy_arr[i]) fputs((int)j3(carr(sy_name[i]), "=(Arr*)calloc(1,sizeof(Arr));\n", ""), f); else fputs((int)j3(cvar(sy_name[i]), "=_emptys;\n", ""), f); }
    fputs((int)"v_NR=\"0\"; v_NF=\"0\"; v_FS=_fs; v_OFS=_ofs; v_ORS=_ors;\n}\n", f);
    fputs((int)g_funcs, f);
    fputs((int)"int main(int argc, char** argv) {\n", f);
    fputs((int)"awk_init();\n", f);
    fputs((int)g_begin, f);
    fputs((int)"{ char __ln[8192]; while (fgets(__ln, 8192, stdin)) { int __k=0; while(__ln[__k]&&__ln[__k]!=10&&__ln[__k]!=13)__k++; __ln[__k]=0;\n", f);
    fputs((int)"v_NR=as(an(v_NR)+1); _fs=v_FS; setrec(strdup(__ln)); v_NF=as((double)g_nf); _ofs=v_OFS; _ors=v_ORS;\n", f);
    fputs((int)g_main, f);
    fputs((int)"__next: ; } }\n", f);
    fputs((int)g_end, f);
    fputs((int)"return 0;\n}\n", f);
    fclose(f);

    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; int n = 0; av[n++] = (int)cc; av[n++] = (int)cpath; av[n++] = (int)"-o"; av[n++] = (int)outp; av[n++] = dll ? (int)"--dll" : (int)"--exe";
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"awk: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"awk: cc failed (%d)\n", rc);
    return rc;
}
