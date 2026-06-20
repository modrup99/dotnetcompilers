%{
/* A Lua subset -> C (yacc); cc lowers the C to .NET IL. Lua is dynamically typed: every
 * value is a boxed Val* (nil/bool/number/string/table/function). The one data structure
 * is the table (array + hash together). Functions are first-class values: each function
 * body is lambda-lifted to a top-level C function and reached through a numeric id, so
 * functions can be stored in tables and passed around. The top-level chunk becomes main().
 * Functions see globals (a global table) but not enclosing-function locals -- the closure
 * boundary. No $-N negative stack use (our yacc lacks it); inherited values are captured
 * with empty marker rules that read $0. */
int g_fnid, g_depth;
char *g_funcs, *g_dispatch, *g_code[40], *g_decls[40];
int g_fnid_stack[40], g_localbase[40];
char *g_fvar, *g_flo, *g_fhi, *g_fstep;              /* numeric for */
char *g_fk, *g_fv, *g_fiter;                         /* generic for */
char *g_tname; int g_tctr; char *g_tnstk[40]; int g_tpstk[40]; int g_tsp; int g_tpos;
int g_method;

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 16); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 16); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *F3(char *f, char *a, char *b, char *c) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + strlen(c) + 16); sprintf((int)r, (int)f, (int)a, (int)b, (int)c); return r; }
char *istr(int n) { char b[24]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *cstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"'; while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; if (s[i] == 10) { r[j++] = '\\'; r[j++] = 'n'; i++; continue; } r[j++] = s[i++]; } r[j++] = '"'; r[j] = 0; return r; }
void apc(char *s) { g_code[g_depth] = j2(g_code[g_depth], s); }

int mkE(char *c) { int *e = (int *)malloc(4); *e = (int)c; return (int)e; }
char *ec(int h) { return (char *)*((int *)h); }

struct L { int a[64]; int n; };
int mkL() { struct L *l = (struct L *)malloc(sizeof(struct L)); l->n = 0; return (int)l; }
int Ladd(int h, int v) { struct L *l = (struct L *)h; l->a[l->n++] = v; return h; }
int Ln(int h) { return ((struct L *)h)->n; }
int Lat(int h, int i) { return ((struct L *)h)->a[i]; }

char *loc[4000]; int nloc;
int is_local(char *n) { int i; for (i = nloc - 1; i >= g_localbase[g_depth]; i--) if (strcmp(loc[i], n) == 0) return 1; return 0; }
void decl_local(char *nm) { g_decls[g_depth] = j2(g_decls[g_depth], j3("Val* l_", nm, " = thenil;\n")); }
void decl_raw(char *nm) { g_decls[g_depth] = j2(g_decls[g_depth], j3("Val* ", nm, " = thenil;\n")); }
void add_local(char *n) { if (!is_local(n)) { loc[nloc++] = n; decl_local(n); } }

struct LV { int kind; char *name; char *tab; char *key; };
int LVname(char *n) { struct LV *v = (struct LV *)malloc(sizeof(struct LV)); v->kind = 0; v->name = n; return (int)v; }
int LVidx(char *t, char *k) { struct LV *v = (struct LV *)malloc(sizeof(struct LV)); v->kind = 1; v->tab = t; v->key = k; return (int)v; }

int yylex(); void yyerror(char *m);
char *nameref(char *n);
void fbegin(int parl); int fend();
void emit_assign(int vl, int el); void emit_local(int nl, int el); void emit_fnstat(int lv, int fe);
int callexpr(char *fcode, int argl); int prepend(int el, char *self);
void do_numfor(); void do_forin();
void emit_prelude(int f);
%}
%token NAME NUMBER STRING
%token AND BREAK DO ELSE ELSEIF END FALSE FOR FUNCTION IF IN LOCAL NIL NOT OR REPEAT RETURN THEN TRUE UNTIL WHILE
%token CONCAT EQ NE LE GE
%left OR
%left AND
%left EQ NE LE GE '<' '>'
%right CONCAT
%left '+' '-'
%left '*' '/' '%'
%right NOT '#' UMINUS
%right '^'
%%
chunk   : block ;
block   : stmts | stmts laststmt ;
stmts   : | stmts stmt ;
stmt    : ';'
        | assign
        | callstmt
        | DO doo block END                  { apc("}\n"); }
        | WHILE expr wdo block END           { apc("}\n"); }
        | REPEAT rdo block UNTIL expr        { apc(F1("} while (!truthy(%s));\n", ec($5))); }
        | IF expr ifthen block elifs END     { apc("}\n"); }
        | FOR NAME feq expr fcomma expr fhi fstep DO fdo block END   { apc("} }\n"); }
        | FOR NAME fink IN expr fiter DO frdo block END              { apc("} }\n"); }
        | FUNCTION funcname funcbody         { emit_fnstat($2, $3); }
        | LOCAL FUNCTION lfname funcbody     { apc(F2("gset(%s, %s);\n", cstr((char *)$3), ec($4))); }
        | LOCAL namelist                     { emit_local($2, 0); }
        | LOCAL namelist '=' exprlist        { emit_local($2, $4); } ;
laststmt: RETURN                             { apc("return thenil;\n"); }
        | RETURN exprlist                    { apc(F1("return %s;\n", Ln($2) ? ec(Lat($2, 0)) : "thenil")); }
        | BREAK                              { apc("break;\n"); } ;

doo     : { apc("{\n"); } ;
wdo     : DO { apc(F1("while (truthy(%s)) {\n", ec($0))); } ;
rdo     : { apc("do {\n"); } ;
ifthen  : THEN { apc(F1("if (truthy(%s)) {\n", ec($0))); } ;
elifs   : | elifs ELSEIF expr eithen block | elifs elsm block ;
eithen  : THEN { apc(F1("} else if (truthy(%s)) {\n", ec($0))); } ;
elsm    : ELSE { apc("} else {\n"); } ;

feq     : '='   { g_fvar = (char *)$0; } ;
fcomma  : ','   { g_flo = ec($0); } ;
fhi     :       { g_fhi = ec($0); } ;
fstep   :       { g_fstep = "mknum(1)"; } | ',' expr { g_fstep = ec($2); } ;
fdo     :       { do_numfor(); } ;
fink    :       { g_fk = (char *)$0; g_fv = (char *)0; }
        | ',' NAME { g_fk = (char *)$0; g_fv = (char *)$2; } ;
fiter   :       { g_fiter = ec($0); } ;
frdo    :       { do_forin(); } ;

assign  : varlist '=' exprlist               { emit_assign($1, $3); } ;
varlist : var                                { $$ = Ladd(mkL(), $1); }
        | varlist ',' var                    { $$ = Ladd($1, $3); } ;
var     : NAME                               { $$ = LVname((char *)$1); }
        | pexp '[' expr ']'                  { $$ = LVidx(ec($1), ec($3)); }
        | pexp '.' NAME                      { $$ = LVidx(ec($1), F1("mkstr(%s)", cstr((char *)$3))); } ;

callstmt: pexp args                          { apc(F1("%s;\n", callexpr(ec($1), $2))); }
        | pexp ':' NAME args                 { apc(F1("%s;\n", callexpr(F2("tget(%s, mkstr(%s))", ec($1), cstr((char *)$3)), prepend($4, ec($1))))); } ;

exprlist: expr                               { $$ = Ladd(mkL(), $1); }
        | exprlist ',' expr                  { $$ = Ladd($1, $3); } ;
namelist: NAME                               { $$ = Ladd(mkL(), (int)(char *)$1); }
        | namelist ',' NAME                  { $$ = Ladd($1, (int)(char *)$3); } ;

pexp    : var                                { struct LV *v = (struct LV *)$1; if (v->kind == 0) $$ = mkE(nameref(v->name)); else $$ = mkE(F2("tget(%s, %s)", v->tab, v->key)); }
        | '(' expr ')'                       { $$ = mkE(F1("(%s)", ec($2))); }
        | pexp args                          { $$ = mkE(callexpr(ec($1), $2)); }
        | pexp ':' NAME args                 { $$ = mkE(callexpr(F2("tget(%s, mkstr(%s))", ec($1), cstr((char *)$3)), prepend($4, ec($1)))); } ;

args    : '(' ')'                            { $$ = mkL(); }
        | '(' exprlist ')'                   { $$ = $2; }
        | STRING                             { $$ = Ladd(mkL(), mkE(F1("mkstr(%s)", cstr((char *)$1)))); } ;

expr    : NIL                                { $$ = mkE("thenil"); }
        | TRUE                               { $$ = mkE("thetrue"); }
        | FALSE                              { $$ = mkE("thefalse"); }
        | NUMBER                             { $$ = mkE(F1("mknum(%s)", (char *)$1)); }
        | STRING                             { $$ = mkE(F1("mkstr(%s)", cstr((char *)$1))); }
        | pexp                               { $$ = $1; }
        | tablecons                          { $$ = $1; }
        | FUNCTION funcbody                  { $$ = $2; }
        | expr '+' expr                      { $$ = mkE(F2("ar(%s,'+',%s)", ec($1), ec($3))); }
        | expr '-' expr                      { $$ = mkE(F2("ar(%s,'-',%s)", ec($1), ec($3))); }
        | expr '*' expr                      { $$ = mkE(F2("ar(%s,'*',%s)", ec($1), ec($3))); }
        | expr '/' expr                      { $$ = mkE(F2("ar(%s,'/',%s)", ec($1), ec($3))); }
        | expr '%' expr                      { $$ = mkE(F2("ar(%s,37,%s)", ec($1), ec($3))); }
        | expr '^' expr                      { $$ = mkE(F2("ar(%s,'^',%s)", ec($1), ec($3))); }
        | expr CONCAT expr                   { $$ = mkE(F2("vcat(%s,%s)", ec($1), ec($3))); }
        | expr EQ expr                       { $$ = mkE(F2("mkbool(veq(%s,%s))", ec($1), ec($3))); }
        | expr NE expr                       { $$ = mkE(F2("mkbool(!veq(%s,%s))", ec($1), ec($3))); }
        | expr '<' expr                      { $$ = mkE(F2("cmp(%s,'<',%s)", ec($1), ec($3))); }
        | expr '>' expr                      { $$ = mkE(F2("cmp(%s,'>',%s)", ec($1), ec($3))); }
        | expr LE expr                       { $$ = mkE(F2("cmp(%s,'l',%s)", ec($1), ec($3))); }
        | expr GE expr                       { $$ = mkE(F2("cmp(%s,'g',%s)", ec($1), ec($3))); }
        | expr AND expr                      { $$ = mkE(F2("vand(%s,%s)", ec($1), ec($3))); }
        | expr OR expr                       { $$ = mkE(F2("vor(%s,%s)", ec($1), ec($3))); }
        | NOT expr                           { $$ = mkE(F1("mkbool(!truthy(%s))", ec($2))); }
        | '#' expr                           { $$ = mkE(F1("vlen(%s)", ec($2))); }
        | '-' expr %prec UMINUS              { $$ = mkE(F1("ar(mknum(0),'-',%s)", ec($2))); } ;

tablecons : '{' tcb fields '}'               { $$ = mkE(g_tname); g_tname = g_tnstk[--g_tsp]; g_tpos = g_tpstk[g_tsp]; } ;
tcb     : { g_tnstk[g_tsp] = g_tname; g_tpstk[g_tsp] = g_tpos; g_tsp++; g_tname = j2("__t", istr(g_tctr++)); g_tpos = 1; decl_raw(g_tname); apc(F1("%s = mktab();\n", g_tname)); } ;
fields  : | field | fields fsep field ;
fsep    : ',' | ';' ;
field   : expr                               { apc(F3("tset(%s, mknum(%s), %s);\n", g_tname, istr(g_tpos), ec($1))); g_tpos++; }
        | NAME '=' expr                      { apc(F3("tset(%s, mkstr(%s), %s);\n", g_tname, cstr((char *)$1), ec($3))); }
        | '[' expr ']' '=' expr              { apc(F3("tset(%s, %s, %s);\n", g_tname, ec($2), ec($5))); } ;

funcname: NAME                               { $$ = LVname((char *)$1); g_method = 0; }
        | NAME '.' NAME                      { $$ = LVidx(nameref((char *)$1), F1("mkstr(%s)", cstr((char *)$3))); g_method = 0; }
        | NAME ':' NAME                      { $$ = LVidx(nameref((char *)$1), F1("mkstr(%s)", cstr((char *)$3))); g_method = 1; } ;
lfname  : NAME                               { $$ = $1; } ;
funcbody: '(' parlist fbeg ')' block END     { $$ = fend(); } ;
parlist : { $$ = mkL(); } | namelist { $$ = $1; } ;
fbeg    : { fbegin($0); } ;
%%

void yyerror(char *m) { printf((int)"lua: %s (line %d)\n", (int)m, pline); }

char *nameref(char *n) { if (is_local(n)) return j2("l_", n); return F1("gget(%s)", cstr(n)); }

int prepend(int el, char *self)
{
    struct L *l = (struct L *)el; struct L *r = (struct L *)mkL(); int i;
    r->a[r->n++] = mkE(self); for (i = 0; i < l->n; i++) r->a[r->n++] = l->a[i]; return (int)r;
}
void fbegin(int parl)
{
    int id = g_fnid++; g_depth++; g_code[g_depth] = ""; g_decls[g_depth] = "";
    g_localbase[g_depth] = nloc; g_fnid_stack[g_depth] = id;
    apc(j3("Val* luaf_", istr(id), "(Val** A, int nA) {\n"));
    int off = 0;
    if (g_method) { add_local("self"); apc("l_self = (nA>0)?A[0]:thenil;\n"); off = 1; }
    int i; struct L *l = (struct L *)parl;
    for (i = 0; i < l->n; i++) { char *nm = (char *)l->a[i]; add_local(nm); apc(F3("l_%s = (nA>%s)?A[%s]:thenil;\n", nm, istr(i + off), istr(i + off))); }
    g_method = 0;
}
int fend()
{
    int id = g_fnid_stack[g_depth];
    char *body = j4("Val* luaf_", istr(id), "(Val** A, int nA) {\n", j2(g_decls[g_depth],
                    /* the header (params) was emitted into g_code after the signature line; rebuild */ ""));
    /* g_code[g_depth] already starts with the signature + param binds; just append decls after it.
       Simpler: reconstruct = signature line is first; we instead prepend decls right after '{'. */
    char *full = g_code[g_depth];
    /* inject decls: find first "\n" (end of signature) and insert decls */
    int p = 0; while (full[p] && full[p] != 10) p++;
    char *head = (char *)malloc(p + 2); strncpy((int)head, (int)full, p + 1); head[p + 1] = 0;
    char *rest = full + p + 1;
    g_funcs = j2(g_funcs, j4(head, g_decls[g_depth], rest, "return thenil;\n}\n"));
    g_dispatch = j2(g_dispatch, F2("  if (id == %s) return luaf_%s(A, nA);\n", istr(id), istr(id)));
    nloc = g_localbase[g_depth]; g_depth--;
    return mkE(F1("mkfunc(%s)", istr(id)));
}
void emit_fnstat(int lv, int fe)
{
    struct LV *v = (struct LV *)lv;
    if (v->kind == 0) { if (is_local(v->name)) apc(F2("l_%s = %s;\n", v->name, ec(fe))); else apc(F2("gset(%s, %s);\n", cstr(v->name), ec(fe))); }
    else apc(F3("tset(%s, %s, %s);\n", v->tab, v->key, ec(fe)));
}
void emit_assign(int vl, int el)
{
    int nv = Ln(vl), ne = Ln(el), i; char *pre = "{\n"; char *body = "";
    for (i = 0; i < ne; i++) pre = j2(pre, F2("Val* __r%s = %s;\n", istr(i), ec(Lat(el, i))));
    for (i = 0; i < nv; i++) {
        char *rhs = (i < ne) ? j2("__r", istr(i)) : "thenil";
        struct LV *v = (struct LV *)Lat(vl, i);
        if (v->kind == 0) { if (is_local(v->name)) body = j2(body, F2("l_%s = %s;\n", v->name, rhs)); else body = j2(body, F2("gset(%s, %s);\n", cstr(v->name), rhs)); }
        else body = j2(body, F3("tset(%s, %s, %s);\n", v->tab, v->key, rhs));
    }
    apc(j3(pre, body, "}\n"));
}
void emit_local(int nl, int el)
{
    int nn = Ln(nl), ne = el ? Ln(el) : 0, i; char *pre = "{\n";
    for (i = 0; i < ne; i++) pre = j2(pre, F2("Val* __q%s = %s;\n", istr(i), ec(Lat(el, i))));
    char *body = "";
    for (i = 0; i < nn; i++) {
        char *nm = (char *)Lat(nl, i); char *rhs = (i < ne) ? j2("__q", istr(i)) : "thenil";
        add_local(nm); body = j2(body, F2("l_%s = %s;\n", nm, rhs));
    }
    apc(j3(pre, body, "}\n"));
}
int callexpr(char *fcode, int argl)
{
    int n = Ln(argl), i; char *a = "";
    for (i = 0; i < n; i++) a = j2(a, j2(", ", ec(Lat(argl, i))));
    return (int)F3("call%s(%s%s)", istr(n), fcode, a);
}
void do_numfor()
{
    add_local(g_fvar);
    apc(F3("{ double __lo=numval(%s); double __hi=numval(%s); double __st=numval(%s);\n", g_flo, g_fhi, g_fstep));
    apc(F3("for (l_%s = mknum(__lo); (__st>=0)?(numval(l_%s)<=__hi):(numval(l_%s)>=__hi); ", g_fvar, g_fvar, g_fvar));
    apc(F2("l_%s = mknum(numval(l_%s)+__st)) {\n", g_fvar, g_fvar));
}
void do_forin()
{
    add_local(g_fk); if (g_fv) add_local(g_fv);
    apc(F1("{ Val* __it = %s; int __ii; for (__ii=0; __ii<tcount(__it); __ii++) {\n", g_fiter));
    apc(F2("l_%s = tkeyat(__it, __ii);", g_fk, ""));
    if (g_fv) apc(F1(" l_%s = tvalat(__it, __ii);", g_fv));
    apc("\n");
}

void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: lua <file.lua> [-o out]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], cpath[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, "exe"); }
    strcpy(cpath, outp); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (!src) { printf((int)"lua: cannot read %s\n", (int)in); return 1; }
    g_fnid = 0; g_depth = 0; g_code[0] = ""; g_decls[0] = ""; nloc = 0; g_localbase[0] = 0; g_funcs = ""; g_dispatch = ""; g_tctr = 0; g_tsp = 0; g_tpos = 1; g_tname = "";
    yy_scan_string((int)src); yyparse();

    int f = fopen((int)cpath, (int)"w");
    emit_prelude(f);
    fputs((int)g_funcs, f);
    fputs((int)"Val* lua_dispatch(int id, Val** A, int nA) {\n", f);
    fputs((int)g_dispatch, f);
    fputs((int)"  return builtin(id, A, nA);\n}\n", f);
    fputs((int)"int main(int argc, char** argv) {\n", f);
    fputs((int)"lua_boot();\n", f);
    fputs((int)g_decls[0], f);
    fputs((int)g_code[0], f);
    fputs((int)"return 0;\n}\n", f);
    fclose(f);

    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; char icon[1100]; int n = 0; sprintf((int)icon, (int)"%s\\icons\\lua.png", (int)repo);
    av[n++] = (int)cc; av[n++] = (int)cpath; av[n++] = (int)"-o"; av[n++] = (int)outp; av[n++] = dll ? (int)"--dll" : (int)"--exe"; av[n++] = (int)"--icon"; av[n++] = (int)icon;
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"lua: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"lua: cc failed (%d)\n", rc);
    return rc;
}

void emit_prelude(int f)
{
    fputs((int)"typedef struct Val { int t; double n; char* s; struct Tab* tab; int fn; } Val;\n", f);
    fputs((int)"typedef struct Ent { char* nk; Val* k; Val* v; } Ent;\n", f);
    fputs((int)"typedef struct Tab { Ent* e; int cap; int len; } Tab;\n", f);
    fputs((int)"Val* thenil; Val* thetrue; Val* thefalse;\n", f);
    fputs((int)"Val* mkv(int t){ Val* v=(Val*)malloc(sizeof(Val)); v->t=t; v->n=0; v->s=0; v->tab=0; v->fn=0; return v; }\n", f);
    fputs((int)"Val* mknum(double x){ Val* v=mkv(2); v->n=x; return v; }\n", f);
    fputs((int)"Val* mkstr(char* s){ Val* v=mkv(3); v->s=s; return v; }\n", f);
    fputs((int)"Val* mkbool(int b){ return b?thetrue:thefalse; }\n", f);
    fputs((int)"Val* mkfunc(int id){ Val* v=mkv(5); v->fn=id; return v; }\n", f);
    fputs((int)"Val* mktab(){ Val* v=mkv(4); v->tab=(Tab*)malloc(sizeof(Tab)); v->tab->cap=8; v->tab->len=0; v->tab->e=(Ent*)malloc(sizeof(Ent)*8); return v; }\n", f);
    fputs((int)"int truthy(Val* v){ if(v->t==0)return 0; if(v->t==1)return (int)v->n; return 1; }\n", f);
    fputs((int)"double numval(Val* v){ if(v->t==2)return v->n; if(v->t==3)return atof(v->s); return 0; }\n", f);
    fputs((int)"char* numstr(double x){ char b[40]; if(x==(int)x) sprintf(b,\"%d\",(int)x); else sprintf(b,\"%.14g\",x); return strdup(b); }\n", f);
    fputs((int)"char* j2x(char* a,char* b){ char* r=(char*)malloc(strlen(a)+strlen(b)+1); strcpy(r,a); strcat(r,b); return r; }\n", f);
    fputs((int)"char* tostr(Val* v){ char b[40]; if(v->t==0)return \"nil\"; if(v->t==1)return v->n?\"true\":\"false\"; if(v->t==2)return numstr(v->n); if(v->t==3)return v->s; if(v->t==4){sprintf(b,\"table: 0x%d\",(int)v->tab);return strdup(b);} sprintf(b,\"function: %d\",v->fn); return strdup(b); }\n", f);
    fputs((int)"char* knorm(Val* k){ if(k->t==2)return j2x(\"#\",numstr(k->n)); return j2x(\"$\",tostr(k)); }\n", f);
    fputs((int)"void tset(Val* t,Val* k,Val* v){ char* nk=knorm(k); int i; Tab* T=t->tab; for(i=0;i<T->len;i++) if(strcmp(T->e[i].nk,nk)==0){ T->e[i].v=v; return; } if(T->len>=T->cap){ T->cap*=2; Ent* ne=(Ent*)malloc(sizeof(Ent)*T->cap); for(i=0;i<T->len;i++)ne[i]=T->e[i]; T->e=ne; } T->e[T->len].nk=nk; T->e[T->len].k=k; T->e[T->len].v=v; T->len++; }\n", f);
    fputs((int)"Val* tget(Val* t,Val* k){ if(t->t!=4)return thenil; char* nk=knorm(k); int i; Tab* T=t->tab; for(i=0;i<T->len;i++) if(strcmp(T->e[i].nk,nk)==0)return T->e[i].v; return thenil; }\n", f);
    fputs((int)"int tcount(Val* t){ return t->t==4?t->tab->len:0; }\n", f);
    fputs((int)"Val* tkeyat(Val* t,int i){ return t->tab->e[i].k; }\n", f);
    fputs((int)"Val* tvalat(Val* t,int i){ return t->tab->e[i].v; }\n", f);
    fputs((int)"Val* vlen(Val* v){ if(v->t==3)return mknum((double)strlen(v->s)); if(v->t==4){ int n=0; while(1){ Val* x=tget(v,mknum((double)(n+1))); if(x->t==0)break; n++; } return mknum((double)n); } return mknum(0); }\n", f);
    fputs((int)"Val* ar(Val* a,int op,Val* b){ double x=numval(a),y=numval(b),r=0; if(op=='+')r=x+y; else if(op=='-')r=x-y; else if(op=='*')r=x*y; else if(op=='/')r=x/y; else if(op==37){ r=(double)((int)x%(int)y); } else if(op=='^'){ r=1; int k; for(k=0;k<(int)y;k++)r*=x; } return mknum(r); }\n", f);
    fputs((int)"Val* vcat(Val* a,Val* b){ return mkstr(j2x(tostr(a),tostr(b))); }\n", f);
    fputs((int)"int veq(Val* a,Val* b){ if(a->t!=b->t)return 0; if(a->t==2)return a->n==b->n; if(a->t==3)return strcmp(a->s,b->s)==0; if(a->t==1)return a->n==b->n; if(a->t==0)return 1; if(a->t==4)return a->tab==b->tab; if(a->t==5)return a->fn==b->fn; return 0; }\n", f);
    fputs((int)"Val* cmp(Val* a,int op,Val* b){ int r=0; if(a->t==3&&b->t==3){ int c=strcmp(a->s,b->s); if(op=='<')r=c<0; else if(op=='>')r=c>0; else if(op=='l')r=c<=0; else r=c>=0; } else { double x=numval(a),y=numval(b); if(op=='<')r=x<y; else if(op=='>')r=x>y; else if(op=='l')r=x<=y; else r=x>=y; } return mkbool(r); }\n", f);
    fputs((int)"Val* vand(Val* a,Val* b){ return truthy(a)?b:a; }\n", f);
    fputs((int)"Val* vor(Val* a,Val* b){ return truthy(a)?a:b; }\n", f);
    fputs((int)"Tab* gtab;\n", f);
    fputs((int)"Val* gget(char* n){ Val* k=mkstr(n); int i; for(i=0;i<gtab->len;i++) if(strcmp(gtab->e[i].nk,knorm(k))==0)return gtab->e[i].v; return thenil; }\n", f);
    fputs((int)"void gset(char* n,Val* v){ Val gt; gt.t=4; gt.tab=gtab; tset(&gt,mkstr(n),v); }\n", f);
    fputs((int)"Val* lua_dispatch(int id, Val** A, int nA);\n", f);
    fputs((int)"Val* lua_call(Val* f, Val** A, int nA){ if(f->t!=5){ printf(\"attempt to call a non-function\\n\"); return thenil; } return lua_dispatch(f->fn, A, nA); }\n", f);
    fputs((int)"Val* call0(Val* f){ Val* A[1]; return lua_call(f,A,0); }\n", f);
    fputs((int)"Val* call1(Val* f,Val* a){ Val* A[1]; A[0]=a; return lua_call(f,A,1); }\n", f);
    fputs((int)"Val* call2(Val* f,Val* a,Val* b){ Val* A[2]; A[0]=a; A[1]=b; return lua_call(f,A,2); }\n", f);
    fputs((int)"Val* call3(Val* f,Val* a,Val* b,Val* c){ Val* A[3]; A[0]=a; A[1]=b; A[2]=c; return lua_call(f,A,3); }\n", f);
    fputs((int)"Val* call4(Val* f,Val* a,Val* b,Val* c,Val* d){ Val* A[4]; A[0]=a;A[1]=b;A[2]=c;A[3]=d; return lua_call(f,A,4); }\n", f);
    fputs((int)"Val* builtin(int id, Val** A, int nA){\n", f);
    fputs((int)"  if(id==900){ int i; for(i=0;i<nA;i++){ if(i)printf(\"\\t\"); printf(\"%s\",tostr(A[i])); } printf(\"\\n\"); return thenil; }\n", f);
    fputs((int)"  if(id==901){ Val* v=nA?A[0]:thenil; char* t=\"nil\"; if(v->t==1)t=\"boolean\"; else if(v->t==2)t=\"number\"; else if(v->t==3)t=\"string\"; else if(v->t==4)t=\"table\"; else if(v->t==5)t=\"function\"; return mkstr(t); }\n", f);
    fputs((int)"  if(id==902){ return mkstr(tostr(nA?A[0]:thenil)); }\n", f);
    fputs((int)"  if(id==903){ Val* v=nA?A[0]:thenil; if(v->t==2)return v; if(v->t==3)return mknum(atof(v->s)); return thenil; }\n", f);
    fputs((int)"  if(id==904||id==905){ return nA?A[0]:thenil; }\n", f);   /* pairs/ipairs: identity (for-in iterates the table) */
    fputs((int)"  return thenil;\n}\n", f);
    fputs((int)"void lua_boot(){ thenil=mkv(0); thetrue=mkv(1); thetrue->n=1; thefalse=mkv(1); thefalse->n=0; gtab=(Tab*)malloc(sizeof(Tab)); gtab->cap=16; gtab->len=0; gtab->e=(Ent*)malloc(sizeof(Ent)*16);\n", f);
    fputs((int)"  gset(\"print\",mkfunc(900)); gset(\"type\",mkfunc(901)); gset(\"tostring\",mkfunc(902)); gset(\"tonumber\",mkfunc(903)); gset(\"pairs\",mkfunc(904)); gset(\"ipairs\",mkfunc(905)); }\n", f);
}
