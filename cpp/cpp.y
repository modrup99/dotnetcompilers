%{
/* Tiny C++ (tcpp) -> C compiler (yacc). Backward compatible: a superset of C,
 * so plain C passes through (C->C is near-identity); only C++ constructs
 * (classes, methods, this, new/delete, virtual, references) are rewritten.
 * Output C is compiled by cc -> .NET IL + native exe + PDB. Built with lex+yacc+cc. */

#define T_INT 1
#define T_DBL 2
#define T_CHR 3
#define TK_PTR 12
#define TK_CLASS 11

int out; char *srcname;
int g_cap; char *g_capbuf;                 /* capture method bodies while inside a class */
void raw(char *s) { if (g_pass == 1) return; fputs((int)s, out); }
char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
void e(char *s) { if (g_pass == 1) return; if (g_cap) { if (g_capbuf == 0) g_capbuf = ""; g_capbuf = j2(g_capbuf, s); } else raw(s); }
char *F1(char *fmt, char *a) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + 8); sprintf((int)r, (int)fmt, (int)a); return r; }
char *F2(char *fmt, char *a, char *b) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + strlen(b) + 8); sprintf((int)r, (int)fmt, (int)a, (int)b); return r; }
char *F3(char *fmt, char *a, char *b, char *c) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + strlen(b) + strlen(c) + 8); sprintf((int)r, (int)fmt, (int)a, (int)b, (int)c); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }

int ty_kind[4000]; int ty_a[4000]; int ty_c[4000]; int nty;
int mkty(int k, int a, int c) { ty_kind[nty] = k; ty_a[nty] = a; ty_c[nty] = c; return nty++; }
int ptr_to(int t) { return mkty(TK_PTR, t, 0); }
int mkptr(int t, int n) { while (n-- > 0) t = ptr_to(t); return t; }

char *cls_name[600]; int cls_parent[600]; int ncls;
char cls_fname[9000][48]; int cls_ftype[9000]; int cls_fcls[9000]; int nfld;
int m_cls[6000]; char *m_nm[6000]; int m_ret[6000]; int m_virt[6000]; int m_slot[6000]; char *m_psig[6000]; int m_refmask[6000]; int nm;
char *fn_name[2000]; int fn_refmask[2000]; int nfn;   /* free-function ref-param signatures (call-site & insertion) */
int cls_find(char *n) { int i; for (i = 0; i < ncls; i++) if (strcmp(cls_name[i], n) == 0) return i; return -1; }
char *base_ctype(int t)
{
    int k = ty_kind[t];
    if (k == T_DBL) return "double";
    if (k == T_CHR) return "char";
    if (k == TK_PTR) return j2(base_ctype(ty_a[t]), "*");
    if (k == TK_CLASS) return cls_name[ty_c[t]];
    return "int";
}
int cls_of(int t) { return ty_kind[t] == TK_CLASS ? ty_c[t] : -1; }
char *mname(int c, char *n) { return j4(cls_name[c], "_", n, ""); }
int fld_type(int c, char *nm) { while (c >= 0) { int i; for (i = 0; i < nfld; i++) if (cls_fcls[i] == c && strcmp(cls_fname[i], nm) == 0) return cls_ftype[i]; c = cls_parent[c]; } return -1; }
int meth_find(int c, char *name) { while (c >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == c && strcmp(m_nm[i], name) == 0) return i; c = cls_parent[c]; } return -1; }
int nvirt_of(int c) { int mx = -1, cc = c; while (cc >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == cc && m_virt[i] && m_slot[i] > mx) mx = m_slot[i]; cc = cls_parent[cc]; } return mx + 1; }
int find_slot_impl(int c, int slot) { int cc = c; while (cc >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == cc && m_virt[i] && m_slot[i] == slot) return i; cc = cls_parent[cc]; } return -1; }
char *vcast(int mi) { char *sig = (m_psig[mi] && m_psig[mi][0]) ? j2("void*, ", m_psig[mi]) : "void*"; return j4("(", base_ctype(m_ret[mi]), j3(" (*)(", sig, "))"), ""); }

char *typenames[2000]; int ntypename;
int is_typename(char *s) { int i; for (i = 0; i < ntypename; i++) if (strcmp(typenames[i], s) == 0) return 1; return 0; }
void add_typename(char *s) { if (is_typename(s)) return; typenames[ntypename++] = (char *)strdup((int)s); }

char *sym_n[9000]; int sym_t[9000]; int sym_ref[9000]; int nsym; int saved_nsym;
int sym_find(char *n) { int i; for (i = nsym - 1; i >= 0; i--) if (strcmp(sym_n[i], n) == 0) return i; return -1; }
void sym_add(char *n, int t, int ref) { sym_n[nsym] = n; sym_t[nsym] = t; sym_ref[nsym] = ref; nsym++; }

int curclass; char *pending_cls; int cur_ret; int tokln;
int g_pass;  /* 1 = collect class/method/field signatures (silent); 2 = emit */
int g_basetype; int g_dstars; char *g_dname; char *g_params; int g_np; char g_psig[1024]; char g_ref[64]; int g_mvirt; int g_mret;
char *g_anames;                          /* arg names of the param list being built (to forward to a ctor) */
char *cls_cparams[600]; char *cls_canames[600];  /* per-class ctor param decls / arg names, for __new_<Cls> */
void line(int ln) { e("\n#line "); e(istr(ln)); e(" \""); e(srcname); e("\"\n"); }

struct E { int c; int t; };
int  mkE(char *c, int t) { struct E *p = (struct E *)malloc(8); p->c = (int)c; p->t = t; return (int)p; }
char *etext(int x) { return (char *)((struct E *)x)->c; }
int  etype(int x) { return ((struct E *)x)->t; }
struct AL { int e; int next; };
int mkAL(int ev, int nx) { struct AL *p = (struct AL *)malloc(8); p->e = ev; p->next = nx; return (int)p; }
int append_AL(int l, int ev) { if (l == 0) return mkAL(ev, 0); struct AL *n = (struct AL *)l; while (n->next) n = (struct AL *)n->next; n->next = mkAL(ev, 0); return l; }
char *build_args(int args) { char *acc = ""; int first = 1, a = args; while (a) { struct AL *n = (struct AL *)a; char *x = etext(n->e); acc = first ? x : j3(acc, ", ", x); first = 0; a = n->next; } return acc; }
/* like build_args, but for arg positions flagged in refmask emit `&(arg)` (reference params) */
char *build_args_ref(int args, int rm) { char *acc = ""; int first = 1, i = 0, a = args; while (a) { struct AL *n = (struct AL *)a; char *x = etext(n->e); if ((rm >> i) & 1) x = j3("&(", x, ")"); acc = first ? x : j3(acc, ", ", x); first = 0; i++; a = n->next; } return acc; }
int cur_refmask(void) { int i, m = 0; for (i = 0; i < g_np; i++) if (g_ref[i]) m |= (1 << i); return m; }

int self_call(int mi, char *a);
int emit_ident(char *name)
{
    if (curclass >= 0)
    {
        int ft = fld_type(curclass, name); if (ft >= 0) return mkE(F1("this->%s", name), ft);
        int mi = meth_find(curclass, name); if (mi >= 0) return self_call(mi, "");
    }
    int i = sym_find(name);
    if (i >= 0) { if (sym_ref[i]) return mkE(F1("(*%s)", name), sym_t[i]); return mkE(name, sym_t[i]); }
    return mkE(name, T_INT);
}
int do_member(int base, char *fld, int arrow)
{
    int rec = arrow ? ty_a[etype(base)] : etype(base);
    int cls = cls_of(rec);
    char *acc = arrow ? F2("%s->%s", etext(base), fld) : F2("%s.%s", etext(base), fld);
    if (cls >= 0) { int ft = fld_type(cls, fld); if (ft >= 0) return mkE(acc, ft); }
    return mkE(acc, T_INT);
}
int method_call(int base, char *fld, int arrow, int args)
{
    int rec = arrow ? ty_a[etype(base)] : etype(base);
    int cls = cls_of(rec); int mi = (cls >= 0) ? meth_find(cls, fld) : -1;
    char *selfp = arrow ? etext(base) : F1("&(%s)", etext(base));
    char *a = build_args_ref(args, mi >= 0 ? m_refmask[mi] : 0);
    if (mi >= 0 && m_virt[mi])
    {
        char *fp = j3("(", j2(vcast(mi), F2("(%s)->__vmt[%s]", selfp, istr(m_slot[mi]))), ")");
        return mkE((a[0] == 0) ? F2("%s(%s)", fp, selfp) : j2(j4(fp, "(", selfp, ", "), j2(a, ")")), m_ret[mi]);
    }
    if (mi >= 0) { char *mn = mname(m_cls[mi], fld); return mkE((a[0] == 0) ? F2("%s(%s)", mn, selfp) : j2(j4(mn, "(", selfp, ", "), j2(a, ")")), m_ret[mi]); }
    return mkE(F2("/*?*/%s(%s)", fld, selfp), T_INT);
}
/* nearest ctor up the chain: a method whose name equals its own class name */
int find_ctor(int c) { int cc = c; while (cc >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == cc && strcmp(m_nm[i], cls_name[cc]) == 0) return i; cc = cls_parent[cc]; } return -1; }
/* a bare call name(args): inside a class body it may be a self method call */
int named_call(char *name, int args)
{
    if (curclass >= 0) { int mi = meth_find(curclass, name); if (mi >= 0) return self_call(mi, build_args_ref(args, m_refmask[mi])); }
    int i; for (i = 0; i < nfn; i++) if (strcmp(fn_name[i], name) == 0) return mkE(F2("%s(%s)", name, build_args_ref(args, fn_refmask[i])), T_INT);
    return mkE(F2("%s(%s)", name, build_args(args)), T_INT);
}
int self_call(int mi, char *a)
{
    if (m_virt[mi]) { char *fp = j3("(", j2(vcast(mi), F1("this->__vmt[%s]", istr(m_slot[mi]))), ")"); return mkE((a[0] == 0) ? F1("%s(this)", fp) : j2(j4(fp, "(this, ", a, ")"), ""), m_ret[mi]); }
    return mkE((a[0] == 0) ? F1("%s(this)", mname(m_cls[mi], m_nm[mi])) : j2(j4(mname(m_cls[mi], m_nm[mi]), "(this, ", a, ")"), ""), m_ret[mi]);
}
int newexpr(int t, int args)
{
    int cls = cls_of(t); char *cn = base_ctype(t);
    if (cls >= 0) return mkE(F3("((%s*)__new_%s(%s))", cn, cls_name[cls], build_args(args)), ptr_to(t));
    return mkE(F2("((%s*)malloc(sizeof(%s)))", cn, cn), ptr_to(t));
}
int bin(int a, char *op, int b, int t) { return mkE(j2(j4("(", etext(a), j3(" ", op, " "), etext(b)), ")"), t); }
int aty(int a, int b) { if (ty_kind[etype(a)] == TK_PTR) return etype(a); if (ty_kind[etype(b)] == TK_PTR) return etype(b); return (etype(a) == T_DBL || etype(b) == T_DBL) ? T_DBL : T_INT; }
char *decl_one(int base, int stars, char *name, int arr)
{
    char *t = base_ctype(mkptr(base, stars));
    if (arr > 0) return j4(t, " ", name, F1("[%s]", istr(arr)));
    if (arr == 0) return j4(t, " ", name, "[]");
    return j3(t, " ", name);
}
/* a stack/global object of a class with virtuals needs its vtable installed
 * (C++ does this in the implicit constructor); emit `name.__vmt = __vmt_Cls;` */
void vmt_init_local(char *name, int t, int arr)
{
    if (arr >= 0 || ty_kind[t] != TK_CLASS) return;
    int c = ty_c[t];
    if (nvirt_of(c) > 0) e(j4("; ", name, ".__vmt = __vmt_", j2(cls_name[c], "")));
    int ctor = find_ctor(c);
    if (ctor >= 0) e(j2("; ", j4(mname(m_cls[ctor], m_nm[ctor]), "((", cls_name[m_cls[ctor]], j4("*)&", name, ")", ""))));
}
char *add_param(int base, int stars, int ref, char *name)
{
    int t = mkptr(base, stars);
    sym_add((char *)strdup((int)name), t, ref);
    g_ref[g_np] = ref; g_np++;
    char *pt = (ty_kind[t] == T_DBL) ? "double" : "int"; if (g_psig[0]) strcat(g_psig, ", "); strcat(g_psig, pt);
    char *p = ref ? j4(base_ctype(t), " *", name, "") : decl_one(base, stars, name, -1);
    g_params = (g_params[0]) ? j3(g_params, ", ", p) : p;
    if (g_anames == 0) g_anames = "";
    g_anames = (g_anames[0]) ? j3(g_anames, ", ", name) : name;
    return p;
}
%}

%token KINT KCHAR KVOID KDOUBLE KLONG KBOOL KCONST KIF KELSE KWHILE KFOR KDO
%token KRETURN KBREAK KCONTINUE KSWITCH KCASE KDEFAULT KSTRUCT KCLASS KENUM
%token KTYPEDEF KSIZEOF KPUBLIC KPRIVATE KPROTECTED KVIRTUAL KNEW KDELETE
%token KTRUE KFALSE KTHIS
%token IDENT TYPENAME INTLIT REALLIT STRLIT CHARLIT
%token SCOPE INC DEC ARROW SHL SHR LE GE EQ NE ANDAND OROR
%token PLUSEQ MINUSEQ STAREQ SLASHEQ PCTEQ AMPEQ PIPEEQ CARETEQ

%right '=' PLUSEQ MINUSEQ STAREQ SLASHEQ PCTEQ AMPEQ PIPEEQ CARETEQ
%right '?'
%left OROR
%left ANDAND
%left '|'
%left '^'
%left '&'
%left EQ NE
%left '<' '>' LE GE
%left SHL SHR
%left '+' '-'
%left '*' '/' '%'
%right UNARY
%left INC DEC ARROW '.' '(' '['
%nonassoc LOWELSE
%nonassoc KELSE

%start unit
%%
unit     : phead decllist ;
phead    : /* empty */  { e("char *__sc(char*a,char*b){char*r=(char*)malloc(strlen(a)+strlen(b)+1);strcpy(r,a);strcat(r,b);return r;}\n"); } ;
decllist : /* empty */ | decllist topdecl ;

topdecl  : type setdt declor pscope toprest
         | classdef ';'
         | KTYPEDEF type IDENT ';'      { add_typename((char *)$3); }
         | KTYPEDEF type TYPENAME ';'   { } ;
setdt    : /* empty */ { g_basetype = $0; } ;
declor   : stars IDENT  { g_dstars = $1; g_dname = (char *)$2; } ;
pscope   : /* empty */ { saved_nsym = nsym; g_np = 0; g_psig[0] = 0; g_params = ""; g_anames = ""; } ;
toprest  : '(' params ')' fhdr compound  { nsym = saved_nsym; }
         | '(' params ')' ';'            { e(j4(base_ctype(mkptr(g_basetype, g_dstars)), " ", g_dname, j3("(", g_params, ");\n"))); nsym = saved_nsym; }
         | arr varinit ';'               { e(";\n"); } ;
fhdr     : /* empty */  { if (g_pass == 1) { fn_name[nfn] = (char *)strdup((int)g_dname); fn_refmask[nfn] = cur_refmask(); nfn++; } e(j4(base_ctype(mkptr(g_basetype, g_dstars)), " ", g_dname, j3("(", g_params, ")"))); } ;
arr      : /* empty */ { $$ = -1; } | '[' ']' { $$ = 0; } | '[' asg ']' { $$ = atoi(etext($2)); } ;
varinit  : /* empty */  { int t = ($0 >= 0) ? ptr_to(mkptr(g_basetype, g_dstars)) : mkptr(g_basetype, g_dstars); sym_add(g_dname, t, 0); e(decl_one(g_basetype, g_dstars, g_dname, $0)); vmt_init_local(g_dname, mkptr(g_basetype, g_dstars), $0); }
         | '=' asg       { sym_add(g_dname, mkptr(g_basetype, g_dstars), 0); e(decl_one(g_basetype, g_dstars, g_dname, -1)); e(" = "); e(etext($2)); } ;

type     : KINT { $$ = T_INT; } | KCHAR { $$ = T_CHR; } | KVOID { $$ = T_INT; } | KDOUBLE { $$ = T_DBL; }
         | KLONG { $$ = T_INT; } | KBOOL { $$ = T_INT; } | KCONST type { $$ = $2; }
         | TYPENAME { $$ = mkty(TK_CLASS, 0, cls_find((char *)$1)); }
         | classdef { $$ = $1; } ;
stars    : /* empty */ { $$ = 0; } | stars '*' { $$ = $1 + 1; } ;

classdef : clshdr '{' members '}'  { $$ = close_class(); } ;
clshdr   : clskw cname                       { class_open(-1); }
         | clskw cname ':' KPUBLIC TYPENAME  { class_open(cls_find((char *)$5)); }
         | clskw cname ':' TYPENAME          { class_open(cls_find((char *)$4)); } ;
clskw    : KCLASS | KSTRUCT ;
cname    : IDENT     { pending_cls = (char *)$1; add_typename((char *)$1); }
         | TYPENAME  { pending_cls = (char *)$1; } ;
members  : /* empty */ | members member ;
member   : KPUBLIC ':' | KPRIVATE ':' | KPROTECTED ':'
         | vmemsig memrest
         | nvmemsig memrest
         | ctorhead '(' params ')' mhdr compound  { nsym = saved_nsym; } ;
vmemsig  : KVIRTUAL type stars IDENT  { g_mret = mkptr($2, $3); g_dname = (char *)$4; g_mvirt = 1; } ;
nvmemsig : type stars IDENT           { g_mret = mkptr($1, $2); g_dname = (char *)$3; g_mvirt = 0; } ;
ctorhead : TYPENAME                   { g_mret = T_INT; g_dname = (char *)$1; g_mvirt = 0; saved_nsym = nsym; g_np = 0; g_psig[0] = 0; g_params = ""; g_anames = ""; } ;
memrest  : ';'  { add_field(g_dname, g_mret); }
         | mscope '(' params ')' mhdr compound  { nsym = saved_nsym; } ;
mscope   : /* empty */ { saved_nsym = nsym; g_np = 0; g_psig[0] = 0; g_params = ""; g_anames = ""; } ;
mhdr     : /* empty */ { begin_method(g_dname, g_mret); } ;

params   : /* empty */ { $$ = (int)""; } | KVOID { $$ = (int)""; } | plist { $$ = $1; } ;
plist    : param | plist ',' param ;
param    : type stars IDENT          { $$ = (int)add_param($1, $2, 0, (char *)$3); }
         | type stars '&' IDENT      { $$ = (int)add_param($1, $2, 1, (char *)$4); }
         | type stars IDENT '[' ']'  { $$ = (int)add_param(ptr_to($1), $2, 0, (char *)$3); }
         | type                      { $$ = (int)base_ctype($1); } ;

compound : cb stmtlist '}'  { e("}\n"); } ;
cb       : '{' { e("{\n"); } ;
stmtlist : /* empty */ | stmtlist stmt ;
stmt     : ';' | smark realstmt ;
smark    : /* empty */ { line(tokln); } ;
realstmt : compound
         | type setdt2 ldeclor ';'  { e(";\n"); }
         | asg ';'                  { e(etext($1)); e(";\n"); }
         | KRETURN asg ';'          { e(F1("return %s;\n", etext($2))); }
         | KRETURN ';'              { e("return;\n"); }
         | KBREAK ';'               { e("break;\n"); }
         | KCONTINUE ';'            { e("continue;\n"); }
         | KDELETE asg ';'          { e(F1("free(%s);\n", etext($2))); }
         | ifhead realstmt %prec LOWELSE
         | ifhead realstmt elsehead realstmt
         | whilehead realstmt
         | forhead realstmt ;
setdt2   : /* empty */ { g_basetype = $0; } ;
ldeclor  : ldecl1 | ldeclor ',' lsep ldecl1 ;
lsep     : /* empty */ { e("; "); } ;
ldecl1   : ldname arr lvinit ;
ldname   : stars IDENT  { g_dstars = $1; g_dname = (char *)$2; } ;
lvinit   : /* empty */  { int t = ($0 >= 0) ? ptr_to(mkptr(g_basetype, g_dstars)) : mkptr(g_basetype, g_dstars); sym_add(g_dname, t, 0); e(decl_one(g_basetype, g_dstars, g_dname, $0)); vmt_init_local(g_dname, mkptr(g_basetype, g_dstars), $0); }
         | '=' asg      { sym_add(g_dname, mkptr(g_basetype, g_dstars), 0); e(decl_one(g_basetype, g_dstars, g_dname, -1)); e(" = "); e(etext($2)); } ;
ifhead   : KIF '(' asg ')'    { e(F1("if (%s) ", etext($3))); } ;
elsehead : KELSE  { e(" else "); } ;
whilehead: KWHILE '(' asg ')' { e(F1("while (%s) ", etext($3))); } ;
forhead  : KFOR '(' fexpr ';' fexpr ';' fexpr ')'  { e(j4("for (", (char *)$3, j3("; ", (char *)$5, "; "), j3((char *)$7, ") ", ""))); } ;
fexpr    : /* empty */ { $$ = (int)""; } | asg { $$ = (int)etext($1); } ;

arglist  : /* empty */ { $$ = 0; } | argne { $$ = $1; } ;
argne    : asg { $$ = mkAL($1, 0); } | argne ',' asg { $$ = append_AL($1, $3); } ;

asg : asg '=' asg { $$ = bin($1, "=", $3, etype($1)); }
    | asg PLUSEQ asg { $$ = bin($1, "+=", $3, etype($1)); }
    | asg MINUSEQ asg { $$ = bin($1, "-=", $3, etype($1)); }
    | asg STAREQ asg { $$ = bin($1, "*=", $3, etype($1)); }
    | asg SLASHEQ asg { $$ = bin($1, "/=", $3, etype($1)); }
    | asg '?' asg ':' asg { $$ = mkE(j4("(", etext($1), j4(" ? ", etext($3), " : ", etext($5)), ")"), etype($3)); }
    | expr ;
expr : expr OROR expr { $$ = bin($1, "||", $3, T_INT); }
     | expr ANDAND expr { $$ = bin($1, "&&", $3, T_INT); }
     | expr '|' expr { $$ = bin($1, "|", $3, T_INT); }
     | expr '^' expr { $$ = bin($1, "^", $3, T_INT); }
     | expr '&' expr { $$ = bin($1, "&", $3, T_INT); }
     | expr EQ expr { $$ = bin($1, "==", $3, T_INT); }
     | expr NE expr { $$ = bin($1, "!=", $3, T_INT); }
     | expr '<' expr { $$ = bin($1, "<", $3, T_INT); }
     | expr '>' expr { $$ = bin($1, ">", $3, T_INT); }
     | expr LE expr { $$ = bin($1, "<=", $3, T_INT); }
     | expr GE expr { $$ = bin($1, ">=", $3, T_INT); }
     | expr SHL expr { $$ = bin($1, "<<", $3, T_INT); }
     | expr SHR expr { $$ = bin($1, ">>", $3, T_INT); }
     | expr '+' expr { $$ = bin($1, "+", $3, aty($1, $3)); }
     | expr '-' expr { $$ = bin($1, "-", $3, aty($1, $3)); }
     | expr '*' expr { $$ = bin($1, "*", $3, aty($1, $3)); }
     | expr '/' expr { $$ = bin($1, "/", $3, aty($1, $3)); }
     | expr '%' expr { $$ = bin($1, "%", $3, T_INT); }
     | '-' expr %prec UNARY { $$ = mkE(F1("(-%s)", etext($2)), etype($2)); }
     | '!' expr %prec UNARY { $$ = mkE(F1("(!%s)", etext($2)), T_INT); }
     | '~' expr %prec UNARY { $$ = mkE(F1("(~%s)", etext($2)), T_INT); }
     | '*' expr %prec UNARY { $$ = mkE(F1("(*%s)", etext($2)), ty_kind[etype($2)] == TK_PTR ? ty_a[etype($2)] : T_INT); }
     | '&' expr %prec UNARY { $$ = mkE(F1("(&%s)", etext($2)), ptr_to(etype($2))); }
     | INC expr %prec UNARY { $$ = mkE(F1("(++%s)", etext($2)), etype($2)); }
     | DEC expr %prec UNARY { $$ = mkE(F1("(--%s)", etext($2)), etype($2)); }
     | KSIZEOF '(' type stars ')' { $$ = mkE(F1("sizeof(%s)", base_ctype(mkptr($3, $4))), T_INT); }
     | KNEW type { $$ = newexpr($2, 0); }
     | KNEW type '(' arglist ')' { $$ = newexpr($2, $4); }
     | post ;
post : post '.' IDENT { $$ = do_member($1, (char *)$3, 0); }
     | post ARROW IDENT { $$ = do_member($1, (char *)$3, 1); }
     | post '.' IDENT '(' arglist ')' { $$ = method_call($1, (char *)$3, 0, $5); }
     | post ARROW IDENT '(' arglist ')' { $$ = method_call($1, (char *)$3, 1, $5); }
     | post '[' asg ']' { $$ = mkE(F2("%s[%s]", etext($1), etext($3)), ty_kind[etype($1)] == TK_PTR ? ty_a[etype($1)] : T_INT); }
     | post INC { $$ = mkE(F1("(%s++)", etext($1)), etype($1)); }
     | post DEC { $$ = mkE(F1("(%s--)", etext($1)), etype($1)); }
     | IDENT '(' arglist ')' { $$ = named_call((char *)$1, $3); }
     | prim ;
prim : INTLIT { $$ = mkE((char *)$1, T_INT); }
     | REALLIT { $$ = mkE((char *)$1, T_DBL); }
     | CHARLIT { $$ = mkE((char *)$1, T_CHR); }
     | STRLIT { $$ = mkE((char *)$1, ptr_to(T_CHR)); }
     | KTRUE { $$ = mkE("1", T_INT); }
     | KFALSE { $$ = mkE("0", T_INT); }
     | KTHIS { $$ = mkE("this", curclass >= 0 ? ptr_to(mkty(TK_CLASS, 0, curclass)) : T_INT); }
     | IDENT { $$ = emit_ident((char *)$1); }
     | '(' asg ')' { $$ = mkE(F1("(%s)", etext($2)), etype($2)); } ;
%%

int cls_fstart[600]; int cls_stack[64]; int csp;
void reg_func(char *n, int r) { (void)n; (void)r; }
void class_open(int parent)
{
    if (g_pass == 2)   /* tables already built in pass 1; just re-enter the class */
    {
        int i, c = -1; for (i = 0; i < ncls; i++) if (strcmp(cls_name[i], pending_cls) == 0) c = i;
        curclass = c; cls_stack[csp++] = c; g_cap = 1; g_capbuf = ""; return;
    }
    int c = ncls; cls_name[c] = pending_cls; cls_parent[c] = parent; cls_fstart[c] = nfld;
    if (parent >= 0) { int i; int pn = nfld; for (i = 0; i < pn; i++) if (cls_fcls[i] == parent) { strcpy(cls_fname[nfld], cls_fname[i]); cls_ftype[nfld] = cls_ftype[i]; cls_fcls[nfld] = c; nfld++; } }
    ncls++; curclass = c; cls_stack[csp++] = c; g_cap = 1; g_capbuf = "";
}
void add_field(char *nm, int t) { if (g_pass == 2) return; strcpy(cls_fname[nfld], nm); cls_ftype[nfld] = t; cls_fcls[nfld] = curclass; nfld++; }
void reg_method(int cls, char *name, int ret, int virt)
{
    if (g_pass == 2) return;   /* method table is fixed after pass 1 */
    m_cls[nm] = cls; m_nm[nm] = name; m_ret[nm] = ret; m_virt[nm] = virt; m_psig[nm] = (char *)strdup((int)g_psig); m_slot[nm] = -1; m_refmask[nm] = cur_refmask();
    if (virt) { int p = cls_parent[cls]; int pm = (p >= 0) ? meth_find(p, name) : -1; m_slot[nm] = (pm >= 0) ? m_slot[pm] : nvirt_of(cls); }
    nm++;
}
void begin_method(char *name, int ret)
{
    reg_method(curclass, name, ret, g_mvirt); cur_ret = ret;
    if (strcmp(name, cls_name[curclass]) == 0) { cls_cparams[curclass] = g_params; cls_canames[curclass] = g_anames; }  /* it's the ctor */
    e(base_ctype(ret)); e(" "); e(mname(curclass, name)); e("(");
    e(j2(cls_name[curclass], "* this")); if (g_params[0]) { e(", "); e(g_params); }
    e(")");
}
int close_class(void)
{
    int c = cls_stack[--csp]; int t = mkty(TK_CLASS, 0, c);
    char *meths = g_capbuf; g_cap = (csp > 0) ? 1 : 0; g_capbuf = "";
    e("typedef struct { int* __vmt; ");
    int i; for (i = cls_fstart[c]; i < nfld; i++) if (cls_fcls[i] == c) { e(base_ctype(cls_ftype[i])); e(" "); e(cls_fname[i]); e("; "); }
    e(j3("} ", cls_name[c], ";\n"));
    raw(meths);
    /* per-class allocator: malloc + install vtable + run default ctor if present */
    int nv = nvirt_of(c); int ctor = find_ctor(c);
    if (nv > 0)
    {
        e(j3("int __vmt_", cls_name[c], "[] = { "));
        int k; for (k = 0; k < nv; k++) { int mi = find_slot_impl(c, k); if (k) e(", "); e(mi >= 0 ? j2("(int)", mname(m_cls[mi], m_nm[mi])) : (char *)"0"); }
        e(" };\n");
    }
    char *cp = (ctor >= 0 && cls_cparams[m_cls[ctor]]) ? cls_cparams[m_cls[ctor]] : "";
    char *an = (ctor >= 0 && cls_canames[m_cls[ctor]]) ? cls_canames[m_cls[ctor]] : "";
    e(j4(cls_name[c], "* __new_", cls_name[c], "(")); e(cp);
    e(j4(") { ", cls_name[c], "* p = (", cls_name[c])); e(j2("*)malloc(sizeof(", j3(cls_name[c], ")); ", "")));
    if (nv > 0) e(j3("p->__vmt = __vmt_", cls_name[c], "; "));
    if (ctor >= 0) { e(j4(mname(m_cls[ctor], m_nm[ctor]), "((", cls_name[m_cls[ctor]], "*)p")); if (an[0]) { e(", "); e(an); } e("); "); }
    e("return p; }\n");
    curclass = (csp > 0) ? cls_stack[csp - 1] : -1;
    return t;
}

void strip_comments(char *s)
{
    int i = 0;
    while (s[i])
    {
        if (s[i] == '"' || s[i] == '\'') { int q = s[i]; i++; while (s[i] && s[i] != q) { if (s[i] == '\\' && s[i + 1]) i++; i++; } if (s[i]) i++; continue; }
        if (s[i] == '/' && s[i + 1] == '/') { while (s[i] && s[i] != '\n') { s[i] = ' '; i++; } continue; }
        if (s[i] == '/' && s[i + 1] == '*') { s[i] = ' '; s[i + 1] = ' '; i += 2; while (s[i] && !(s[i] == '*' && s[i + 1] == '/')) { if (s[i] != '\n') s[i] = ' '; i++; } if (s[i]) { s[i] = ' '; s[i + 1] = ' '; i += 2; } continue; }
        if (s[i] == '#') { while (s[i] && s[i] != '\n') { s[i] = ' '; i++; } continue; }   /* drop preprocessor lines (cc has built-in libc) */
        i++;
    }
}
void setext(char *path, char *ext) { int n = strlen(path), i = n - 1; while (i > 0 && path[i] != '.' && path[i] != '\\' && path[i] != '/') i--; if (path[i] == '.') path[i + 1] = 0; else strcat(path, "."); strcat(path, ext); }
void yyerror(char *m) { printf((int)"tcpp: %s near line %d\n", (int)m, pline); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: tcpp <file> [-o <out.exe>]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int i;
    for (i = 2; i < argc; i++) if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) { o = (char *)argv[i + 1]; i++; }
    char outexe[1024]; char cpath[1024];
    if (o) strcpy(outexe, o); else { strcpy(outexe, in); setext(outexe, "exe"); }
    strcpy(cpath, outexe); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"tcpp: cannot read %s\n", (int)in); return 1; }
    strip_comments(src);
    srcname = in; g_params = ""; g_capbuf = ""; curclass = -1; nty = 0; for (i = 0; i <= TK_CLASS; i++) mkty(0, 0, 0);
    ty_kind[T_INT] = T_INT; ty_kind[T_DBL] = T_DBL; ty_kind[T_CHR] = T_CHR; ty_kind[TK_PTR] = TK_PTR; ty_kind[TK_CLASS] = TK_CLASS;
    out = fopen((int)cpath, (int)"w");
    if (out == 0) { printf((int)"tcpp: cannot write %s\n", (int)cpath); return 1; }
    /* pass 1: collect every class/method/field signature so a method body may
     * refer to members declared later in the class; pass 2 emits with full info */
    g_pass = 1; yy_scan_string((int)src); yyparse();
    csp = 0; curclass = -1; g_cap = 0; g_capbuf = ""; g_params = ""; nsym = 0; pline = 1;
    g_pass = 2; yy_scan_string((int)src); yyparse();
    fclose(out);
    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; av[0] = (int)cc; av[1] = (int)cpath; av[2] = (int)"-o"; av[3] = (int)outexe; av[4] = (int)"--exe";
    int rc = sh_run((int)av, 5);
    if (rc == 0) printf((int)"tcpp: %s -> %s\n", (int)in, (int)outexe);
    else printf((int)"tcpp: cc failed (%d)\n", rc);
    return rc;
}
