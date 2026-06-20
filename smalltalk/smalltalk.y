%{
/* A Smalltalk subset -> C (yacc); cc lowers the C to .NET IL. Everything is an object:
 * every value is a boxed Obj* (nil/int/bool/string/user-instance) and computation is
 * message-sending via a runtime send(). Unary/binary/keyword precedence is the classic
 * Smalltalk one. The control-flow messages (ifTrue:/whileTrue:/timesRepeat:/to:do:) are
 * compiled inline. User classes get an id; their methods become C functions dispatched
 * by class id + selector string. Top-level statements form a script -> main(). */
int g_clsid;            /* next user class id (>=10) */
int g_tgt;              /* 0 script (g_main), 1 method (g_methods) */
char *g_main, *g_methods, *g_dispatch;
int g_inmethod; int g_curcls;                 /* class id being defined */
char *g_iv[64]; int g_niv;                    /* current class instance-var names */
char *g_mp[4]; int g_nmp;                     /* current method param names */
int g_methidx;
char *g_tolo, *g_tohi, *g_doidx, *g_wcond, *g_selbuf;

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 16); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 16); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *istr(int n) { char b[24]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *cstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"'; while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; if (s[i] == 10) { r[j++] = '\\'; r[j++] = 'n'; i++; continue; } r[j++] = s[i++]; } r[j++] = '"'; r[j] = 0; return r; }
void apc(char *s) { if (g_tgt == 1) g_methods = j2(g_methods, s); else g_main = j2(g_main, s); }

struct E { char *code; int clsref; };
int mkE(char *c) { struct E *e = (struct E *)malloc(8); e->code = c; e->clsref = -1; return (int)e; }
int mkEC(char *c, int cr) { int h = mkE(c); ((struct E *)h)->clsref = cr; return h; }
char *ecode(int h) { return ((struct E *)h)->code; }
int eclsref(int h) { return ((struct E *)h)->clsref; }

/* classes */
char *cl_name[256]; int cl_id[256]; int cl_nin; int ncl;
char *cl_iv[256][64]; int cl_niv[256];        /* instance var names per class slot */
int cl_find(char *n) { int i; for (i = 0; i < ncl; i++) if (strcmp(cl_name[i], n) == 0) return i; return -1; }
int cl_slot_byid(int id) { int i; for (i = 0; i < ncl; i++) if (cl_id[i] == id) return i; return -1; }

/* current-scope variables (script globals or method temps); flat with a kind */
char *vr_name[2000]; int vr_kind[2000]; int vr_idx[2000]; int nvr;   /* kind: 0 global,1 param(idx 0/1),2 ivar(idx),3 methtemp */
int g_basevr;   /* vr table base for current method (reset on method end) */
int vr_find(char *n) { int i; for (i = nvr - 1; i >= 0; i--) if (strcmp(vr_name[i], n) == 0) return i; return -1; }

int yylex(); void yyerror(char *m);
int unary(int r, char *sel); int binary(int r, char *op, int a); int keysend(int r, char *sel, int a0, int a1, int n);
int name_ref(char *nm); void decl_global(char *nm); int gv(char *nm);
%}
%token NAME KEYWORD BINSEL INTLIT FLOATLIT STRING SYMBOL
%token ASSIGN PIPE COLON CARET BANG
%token KW_IFTRUE KW_IFFALSE KW_WHILETRUE KW_WHILEFALSE KW_TIMESREPEAT KW_TO KW_DO KW_AND KW_OR KW_SUBCLASS
%token KSELF KSUPER KNIL KTRUE KFALSE
%%
program : items ;
items   : | items item ;
item    : classdef
        | PIPE gtemps PIPE
        | stmt '.'
        | stmt
        | BANG ;
gtemps  : | gtemps NAME { decl_global((char *)$2); } ;

classdef : NAME KW_SUBCLASS NAME clhead '[' members ']'   { g_inmethod = 0; g_curcls = -1; g_tgt = 0; } ;
clhead  : { cls_begin((char *)$0); } ;
members : | members member ;
member  : PIPE ivars PIPE | methoddef ;
ivars   : | ivars NAME { add_ivar((char *)$2); } ;
methoddef : mpat mbeg '[' mtemps stmts ']'   { meth_end(); } ;
mpat    : NAME                 { meth_pat((char *)$1); }
        | BINSEL NAME          { meth_pat((char *)$1); g_mp[g_nmp++] = (char *)$2; }
        | keyparts             { meth_pat(g_selbuf); } ;
keyparts: KEYWORD NAME         { g_selbuf = (char *)$1; g_mp[g_nmp++] = (char *)$2; }
        | keyparts KEYWORD NAME { g_selbuf = j2(g_selbuf, (char *)$2); g_mp[g_nmp++] = (char *)$3; } ;
mbeg    : { meth_begin(); } ;
mtemps  : | PIPE mtlist PIPE ;
mtlist  : | mtlist NAME { add_temp((char *)$2); } ;

stmts   : | stmts stmt seps ;
seps    : | seps '.' ;
stmt    : NAME ASSIGN expr      { do_assign((char *)$1, $3); }
        | CARET expr            { if (g_tgt == 1) apc(F1("return %s;\n", ecode($2))); }
        | cfstmt
        | expr                  { apc(F1("send(%s, \"yourself\", 0, 0);\n", ecode($1))); } ;

cfstmt  : expr ifk blk                  { apc("}\n"); }
        | expr ifk blk elsk blk         { apc("}\n"); }
        | expr iffk blk                 { apc("}\n"); }
        | wcond blk                     { apc("}\n"); }
        | expr trk blk                  { apc("} }\n"); }
        | expr tolo KW_TO expr tohi KW_DO dblk { apc("} }\n"); } ;
ifk     : KW_IFTRUE   { apc(F1("if (truthy(%s)) {\n", ecode($0))); } ;
iffk    : KW_IFFALSE  { apc(F1("if (!truthy(%s)) {\n", ecode($0))); } ;
elsk    : KW_IFFALSE  { apc("} else {\n"); } ;
trk     : KW_TIMESREPEAT { apc(F1("{ int __n = intval(%s); int __k; for (__k = 0; __k < __n; __k++) {\n", ecode($0))); } ;
tolo    : { g_tolo = ecode($0); } ;
tohi    : { g_tohi = ecode($0); } ;
wcond   : '[' expr ']' KW_WHILETRUE { apc(F1("while (truthy(%s)) {\n", ecode($2))); } ;
blk     : '[' stmts ']' ;
dblk    : '[' COLON NAME dvar PIPE dgo stmts ']' ;
dvar    : { g_doidx = (char *)$0; } ;
dgo     : { do_todo(); } ;

expr    : kexpr | NAME ASSIGN expr { do_assign((char *)$1, $3); $$ = name_ref((char *)$1); } ;
kexpr   : bexpr | bexpr keymsg { $$ = keyfin($1, $2); } ;
keymsg  : KEYWORD bexpr        { $$ = km1((char *)$1, $2); }
        | keymsg KEYWORD bexpr { $$ = kmA($1, (char *)$2, $3); } ;
bexpr   : uexpr | bexpr BINSEL uexpr { $$ = binary($1, (char *)$2, $3); } ;
uexpr   : primary | uexpr NAME { $$ = unary($1, (char *)$2); } ;
primary : INTLIT       { $$ = mkE(F1("mkint(%s)", istr($1))); }
        | FLOATLIT     { $$ = mkE(F1("mkint((int)%s)", (char *)$1)); }
        | STRING       { $$ = mkE(F1("mkstr(%s)", cstr((char *)$1))); }
        | SYMBOL       { $$ = mkE(F1("mkstr(%s)", cstr((char *)$1))); }
        | KSELF        { $$ = mkE("self"); }
        | KSUPER       { $$ = mkE("self"); }
        | KNIL         { $$ = mkE("the_nil"); }
        | KTRUE        { $$ = mkE("the_true"); }
        | KFALSE       { $$ = mkE("the_false"); }
        | NAME         { $$ = name_ref((char *)$1); }
        | '(' expr ')' { $$ = mkE(F1("(%s)", ecode($2))); } ;
%%

void yyerror(char *m) { printf((int)"smalltalk: %s (line %d)\n", (int)m, pline); }

char *clsfn(int id, int idx) { return j3("m", istr(id), j2("_", istr(idx))); }

void cls_begin(char *nm)
{
    int id = g_clsid++; cl_name[ncl] = nm; cl_id[ncl] = id; cl_niv[ncl] = 0; ncl++;
    g_curcls = id; g_inmethod = 0; g_methidx = 0;
}
void add_ivar(char *nm) { int s = cl_slot_byid(g_curcls); cl_iv[s][cl_niv[s]++] = nm; }
void meth_pat(char *sel) { g_selbuf = sel; }
void meth_begin()
{
    g_inmethod = 1; g_tgt = 1; g_basevr = nvr;
    int s = cl_slot_byid(g_curcls); int i;
    /* instance vars in scope */
    for (i = 0; i < cl_niv[s]; i++) { vr_name[nvr] = cl_iv[s][i]; vr_kind[nvr] = 2; vr_idx[nvr] = i; nvr++; }
    for (i = 0; i < g_nmp; i++) { vr_name[nvr] = g_mp[i]; vr_kind[nvr] = 1; vr_idx[nvr] = i; nvr++; }
    g_methods = j2(g_methods, j3("Obj* ", clsfn(g_curcls, g_methidx), "(Obj* self, Obj* a0, Obj* a1) {\n"));
    /* register dispatch */
    g_dispatch = j2(g_dispatch, j4("  if (r->cls == ", istr(g_curcls), j3(" && strcmp(sel, ", cstr(g_selbuf), ") == 0) return "), j3(clsfn(g_curcls, g_methidx), "(r, a0, a1);\n", "")));
}
void add_temp(char *nm) { vr_name[nvr] = nm; vr_kind[nvr] = 3; vr_idx[nvr] = 0; nvr++; if (g_tgt == 1) g_methods = j2(g_methods, j3("Obj* v_", nm, " = the_nil;\n")); }
void meth_end()
{
    g_methods = j2(g_methods, "return self;\n}\n");
    g_methidx++; nvr = g_basevr; g_nmp = 0; g_inmethod = 0;
    g_tgt = 1;   /* still inside the class body; classdef resets to script at the end */
}

int name_ref(char *nm)
{
    int i = vr_find(nm);
    if (i >= 0)
    {
        if (vr_kind[i] == 2) return mkE(F1("self->iv[%s]", istr(vr_idx[i])));
        if (vr_kind[i] == 1) return mkE(vr_idx[i] == 0 ? "a0" : "a1");
        if (vr_kind[i] == 3) return mkE(j2("v_", nm));
        return mkE(j2("g_", nm));
    }
    int c = cl_find(nm); if (c >= 0) return mkEC("the_nil", cl_id[c]);   /* class reference */
    /* auto global */
    decl_global(nm); return mkE(j2("g_", nm));
}
char *g_globals;
void decl_global(char *nm) { if (vr_find(nm) >= 0) return; vr_name[nvr] = nm; vr_kind[nvr] = 0; nvr++; g_globals = j2(g_globals, j3("Obj* g_", nm, " = 0;\n")); }
int gv(char *nm) { return 0; }

void do_assign(char *nm, int rv)
{
    int i = vr_find(nm); char *lhs;
    if (i >= 0 && vr_kind[i] == 2) lhs = F1("self->iv[%s]", istr(vr_idx[i]));
    else if (i >= 0 && vr_kind[i] == 1) lhs = vr_idx[i] == 0 ? "a0" : "a1";
    else if (i >= 0 && vr_kind[i] == 3) lhs = j2("v_", nm);
    else { decl_global(nm); lhs = j2("g_", nm); }
    apc(F2("%s = %s;\n", lhs, ecode(rv)));
}

int unary(int r, char *sel)
{
    if (eclsref(r) >= 0 && strcmp(sel, "new") == 0) { int s = cl_slot_byid(eclsref(r)); return mkE(F2("mknew(%s, %s)", istr(eclsref(r)), istr(cl_niv[s]))); }
    return mkE(F2("send(%s, %s, 0, 0)", ecode(r), cstr(sel)));
}
int binary(int r, char *op, int a) { return mkE(j2("send(", j4(ecode(r), ", ", cstr(op), j4(", ", ecode(a), ", 0)", "")))); }

/* keyword message accumulation: a small list of (selpart, arg) */
struct KM { char *sel; int a0; int a1; int n; };
int km1(char *k, int a) { struct KM *m = (struct KM *)malloc(20); m->sel = k; m->a0 = a; m->a1 = 0; m->n = 1; return (int)m; }
int kmA(int h, char *k, int a) { struct KM *m = (struct KM *)h; m->sel = j2(m->sel, k); if (m->n == 1) m->a1 = a; m->n++; return h; }
int keyfin(int r, int kmh)
{
    struct KM *m = (struct KM *)kmh;
    char *a0 = ecode(m->a0); char *a1 = (m->n >= 2) ? ecode(m->a1) : "0";
    return mkE(j2("send(", j4(ecode(r), ", ", cstr(m->sel), j4(", ", a0, ", ", j2(a1, ")")))));
}

void do_todo()
{
    int i = vr_find(g_doidx); if (i < 0) { vr_name[nvr] = g_doidx; vr_kind[nvr] = (g_tgt == 1) ? 3 : 0; vr_idx[nvr] = 0; nvr++; if (g_tgt == 1) g_methods = j2(g_methods, j3("Obj* v_", g_doidx, " = the_nil;\n")); else g_globals = j2(g_globals, j3("Obj* g_", g_doidx, " = 0;\n")); }
    char *vv = (g_tgt == 1) ? j2("v_", g_doidx) : j2("g_", g_doidx);
    apc(j2(F2("{ int __lo = intval(%s); int __hi = intval(%s); int __k; ", g_tolo, g_tohi), j3("for (__k = __lo; __k <= __hi; __k++) { ", F1("%s = mkint(__k);\n", vv), "")));
}

char *PRELUDE =
"typedef struct Obj { int cls; int i; char* s; struct Obj** iv; } Obj;\n"
"Obj* the_nil; Obj* the_true; Obj* the_false;\n"
"Obj* mkint(int v){ Obj* o=(Obj*)malloc(sizeof(Obj)); o->cls=1; o->i=v; o->s=0; o->iv=0; return o; }\n"
"Obj* mkstr(char* s){ Obj* o=(Obj*)malloc(sizeof(Obj)); o->cls=3; o->s=s; o->i=0; o->iv=0; return o; }\n"
"Obj* mkbool(int b){ return b?the_true:the_false; }\n"
"Obj* mknew(int cls,int nv){ Obj* o=(Obj*)malloc(sizeof(Obj)); o->cls=cls; o->i=0; o->s=0; o->iv=(Obj**)malloc(sizeof(Obj*)*(nv+1)); int i; for(i=0;i<nv;i++)o->iv[i]=the_nil; return o; }\n"
"int truthy(Obj* o){ if(o->cls==2)return o->i; return o->cls!=0; }\n"
"int intval(Obj* o){ return o->cls==1?o->i:0; }\n"
"char* pstr(Obj* o){ char b[48]; if(o->cls==0)return \"nil\"; if(o->cls==1){sprintf(b,\"%d\",o->i);return strdup(b);} if(o->cls==2)return o->i?\"true\":\"false\"; if(o->cls==3)return o->s; sprintf(b,\"a <class %d>\",o->cls); return strdup(b); }\n"
"Obj* send(Obj* r, char* sel, Obj* a0, Obj* a1);\n";

void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: smalltalk <file.st> [-o out]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], cpath[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, "exe"); }
    strcpy(cpath, outp); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (!src) { printf((int)"smalltalk: cannot read %s\n", (int)in); return 1; }
    g_clsid = 10; ncl = 0; nvr = 0; g_tgt = 0; g_main = ""; g_methods = ""; g_dispatch = ""; g_globals = ""; g_inmethod = 0; g_curcls = -1;
    yy_scan_string((int)src); yyparse();

    int f = fopen((int)cpath, (int)"w");
    fputs((int)PRELUDE, f);
    fputs((int)g_globals, f);
    fputs((int)"void st_boot(){ the_nil=(Obj*)malloc(sizeof(Obj)); the_nil->cls=0; the_true=(Obj*)malloc(sizeof(Obj)); the_true->cls=2; the_true->i=1; the_false=(Obj*)malloc(sizeof(Obj)); the_false->cls=2; the_false->i=0; }\n", f);
    fputs((int)g_methods, f);
    /* send(): built-ins + user dispatch */
    fputs((int)"Obj* send(Obj* r, char* sel, Obj* a0, Obj* a1) {\n", f);
    fputs((int)"if (strcmp(sel,\"printNl\")==0){ printf(\"%s\\n\", pstr(r)); return r; }\n", f);
    fputs((int)"if (strcmp(sel,\"displayNl\")==0){ printf(\"%s\\n\", pstr(r)); return r; }\n", f);
    fputs((int)"if (strcmp(sel,\"print\")==0||strcmp(sel,\"display\")==0){ printf(\"%s\", pstr(r)); return r; }\n", f);
    fputs((int)"if (strcmp(sel,\"asString\")==0||strcmp(sel,\"printString\")==0) return mkstr(pstr(r));\n", f);
    fputs((int)"if (strcmp(sel,\"yourself\")==0) return r;\n", f);
    fputs((int)"if (r->cls==1){\n", f);
    fputs((int)"  if(strcmp(sel,\"+\")==0)return mkint(r->i+a0->i); if(strcmp(sel,\"-\")==0)return mkint(r->i-a0->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"*\")==0)return mkint(r->i*a0->i); if(strcmp(sel,\"//\")==0)return mkint(r->i/a0->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"\\\\\\\\\")==0)return mkint(r->i%a0->i); if(strcmp(sel,\"/\")==0)return mkint(r->i/a0->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"<\")==0)return mkbool(r->i<a0->i); if(strcmp(sel,\">\")==0)return mkbool(r->i>a0->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"<=\")==0)return mkbool(r->i<=a0->i); if(strcmp(sel,\">=\")==0)return mkbool(r->i>=a0->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"=\")==0)return mkbool(r->i==a0->i); if(strcmp(sel,\"~=\")==0)return mkbool(r->i!=a0->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"max:\")==0)return mkint(r->i>a0->i?r->i:a0->i); if(strcmp(sel,\"min:\")==0)return mkint(r->i<a0->i?r->i:a0->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"abs\")==0)return mkint(r->i<0?-r->i:r->i); if(strcmp(sel,\"negated\")==0)return mkint(-r->i);\n", f);
    fputs((int)"  if(strcmp(sel,\"even\")==0)return mkbool(r->i%2==0); if(strcmp(sel,\"odd\")==0)return mkbool(r->i%2!=0);\n", f);
    fputs((int)"  if(strcmp(sel,\"factorial\")==0){ int n=1,k; for(k=2;k<=r->i;k++)n*=k; return mkint(n); }\n", f);
    fputs((int)"}\n", f);
    fputs((int)"if (r->cls==3){\n", f);
    fputs((int)"  if(strcmp(sel,\",\")==0){ char* x=(char*)malloc(strlen(r->s)+strlen(a0->s)+1); strcpy(x,r->s); strcat(x,a0->s); return mkstr(x); }\n", f);
    fputs((int)"  if(strcmp(sel,\"size\")==0)return mkint((int)strlen(r->s));\n", f);
    fputs((int)"  if(strcmp(sel,\"=\")==0)return mkbool(strcmp(r->s,a0->s)==0);\n", f);
    fputs((int)"}\n", f);
    fputs((int)"if (r->cls==2){ if(strcmp(sel,\"not\")==0)return mkbool(!r->i); if(strcmp(sel,\"=\")==0)return mkbool(r->i==a0->i); }\n", f);
    fputs((int)"if (r->cls==0){ if(strcmp(sel,\"isNil\")==0)return the_true; }\n", f);
    fputs((int)g_dispatch, f);
    fputs((int)"printf(\"doesNotUnderstand: %s\\n\", sel); return the_nil;\n}\n", f);
    /* main */
    fputs((int)"int main(int argc, char** argv) {\n", f);
    fputs((int)"st_boot();\n", f);
    fputs((int)g_main, f);
    fputs((int)"return 0;\n}\n", f);
    fclose(f);

    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; char icon[1100]; int n = 0; sprintf((int)icon, (int)"%s\\icons\\smalltalk.png", (int)repo);
    av[n++] = (int)cc; av[n++] = (int)cpath; av[n++] = (int)"-o"; av[n++] = (int)outp; av[n++] = dll ? (int)"--dll" : (int)"--exe"; av[n++] = (int)"--icon"; av[n++] = (int)icon;
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"smalltalk: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"smalltalk: cc failed (%d)\n", rc);
    return rc;
}
