%{
/* Combined Modula-2 / Oberon-2 -> C compiler (yacc). Emits C (+#line), which cc
 * lowers to .NET IL + native exe + PDB. Reuses the Pascal backend patterns:
 * a type table, E (text+type) expression values, and syntax-directed emission.
 * Built with our own lex + yacc + cc. */

#define T_VOID 0
#define T_INT  1
#define T_REAL 2
#define T_CHR  3
#define T_BOOL 4
#define T_STR  5
#define T_SET  6
#define T_MOD  7          /* a built-in pseudo-module (Out, InOut, ...) */
#define TK_ARRAY 10
#define TK_RECORD 11
#define TK_PTR 12

#define K_VAR 1
#define K_VARP 2
#define K_CONST 3

int out;
char *srcname;
void e(char *s) { fputs((int)s, out); }

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *fmt, char *a) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + 8); sprintf((int)r, (int)fmt, (int)a); return r; }
char *F2(char *fmt, char *a, char *b) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + strlen(b) + 8); sprintf((int)r, (int)fmt, (int)a, (int)b); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *cname(char *id) { return j2("o_", id); }   /* prefix to dodge C keywords/runtime names */

/* type table */
int ty_kind[3000]; int ty_a[3000]; int ty_b[3000]; int ty_c[3000]; int nty;
int mkty(int k, int a, int b, int c) { ty_kind[nty] = k; ty_a[nty] = a; ty_b[nty] = b; ty_c[nty] = c; return nty++; }
char *rf_name[6000]; int rf_type[6000]; int nrf; int n_struct;

int eff(int t) { return ty_kind[t]; }
int is_real(int t) { return eff(t) == T_REAL; }
int is_str(int t) { return ty_kind[t] == T_STR; }
char *struct_name(int t) { return j2("R", istr(ty_c[t])); }
char *cscalar(int t)
{
    int k = ty_kind[t];
    if (k == T_INT || k == T_BOOL || k == T_SET) return "int";
    if (k == T_REAL) return "double";
    if (k == T_CHR) return "char";
    if (k == T_STR) return "char*";
    if (k == TK_PTR) return j2(cscalar(ty_a[t]), "*");
    if (k == TK_RECORD) return struct_name(t);
    if (k == TK_ARRAY) return cscalar(ty_a[t]);
    return "int";
}
char *decl_one(int t, char *name)
{
    if (ty_kind[t] == TK_ARRAY)
    {
        char dims[256]; dims[0] = 0; int el = t;
        while (ty_kind[el] == TK_ARRAY) { int len = ty_b[el]; char d[32]; sprintf((int)d, (int)"[%d]", len > 0 ? len : 1); strcat(dims, d); el = ty_a[el]; }
        return j4(cscalar(el), " ", name, dims);
    }
    if (ty_kind[t] == T_STR) return j3("char ", name, "[256]");
    return j3(cscalar(t), " ", name);
}

/* symbols (vars/params/consts) */
char *sym_n[6000]; int sym_k[6000]; int sym_t[6000]; int nsym; int saved_nsym;
int sym_find(char *n) { int i; for (i = nsym - 1; i >= 0; i--) if (strcmp(sym_n[i], n) == 0) return i; return -1; }
void sym_add(char *n, int k, int t) { sym_n[nsym] = n; sym_k[nsym] = k; sym_t[nsym] = t; nsym++; }

/* named types */
char *tn_name[2000]; int tn_type[2000]; int ntn;
int tn_find(char *n) { int i; for (i = 0; i < ntn; i++) if (strcmp(tn_name[i], n) == 0) return tn_type[i]; return -1; }

/* procedures */
char *f_n[2000]; int f_ret[2000]; int f_np[2000]; char f_ref[2000][32]; int nf;
int g_np; char g_ref[64];
int cur_ret;
int f_find(char *n) { int i; for (i = 0; i < nf; i++) if (strcmp(f_n[i], n) == 0) return i; return -1; }
void reg_func(char *n, int ret) { f_n[nf] = n; f_ret[nf] = ret; f_np[nf] = g_np; int k; for (k = 0; k < g_np; k++) f_ref[nf][k] = g_ref[k]; nf++; }

int is_module(char *id)
{
    return strcmp(id, "Out") == 0 || strcmp(id, "InOut") == 0 || strcmp(id, "Terminal") == 0 ||
           strcmp(id, "Texts") == 0 || strcmp(id, "Files") == 0 || strcmp(id, "Strings") == 0 || strcmp(id, "Math") == 0;
}
int base_type(char *id)
{
    if (strcmp(id, "INTEGER") == 0 || strcmp(id, "LONGINT") == 0 || strcmp(id, "SHORTINT") == 0 || strcmp(id, "CARDINAL") == 0) return T_INT;
    if (strcmp(id, "REAL") == 0 || strcmp(id, "LONGREAL") == 0) return T_REAL;
    if (strcmp(id, "CHAR") == 0) return T_CHR;
    if (strcmp(id, "BOOLEAN") == 0) return T_BOOL;
    return -1;
}
int name_type(char *id)   /* unknown name -> a forward placeholder type, filled when defined */
{
    int b = base_type(id); if (b >= 0) return b;
    int u = tn_find(id); if (u >= 0) return u;
    int t = mkty(0, 0, 0, 0); tn_name[ntn] = (char *)strdup((int)id); tn_type[ntn] = t; ntn++; return t;
}

/* --- OOP: record extension + type-bound procedures (all virtual) --- */
char *cls_name[400]; int cls_rtype[400]; int cls_parent[400]; int cls_nvirt[400]; int ncls;
int m_cls[5000]; char *m_nm[5000]; int m_ret[5000]; int m_slot[5000]; char *m_psig[5000]; int nm;
int curclass; char *pending_typename; char *cur_recv; char *g_psig;
int cls_find(char *n) { int i; for (i = 0; i < ncls; i++) if (cls_name[i] && strcmp(cls_name[i], n) == 0) return i; return -1; }
int cls_of_type(int t) { int i; for (i = 0; i < ncls; i++) if (cls_rtype[i] == t) return i; return -1; }
char *mname(int c, char *n) { return j4("m_", cls_name[c], "_", n); }
int meth_find(int c, char *name) { while (c >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == c && strcmp(m_nm[i], name) == 0) return i; c = cls_parent[c]; } return -1; }
int nvirt_so_far(int cls) { int mx = -1, c = cls; while (c >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == c && m_slot[i] > mx) mx = m_slot[i]; c = cls_parent[c]; } return mx + 1; }
void assign_slot(int mi) { int cls = m_cls[mi]; int p = cls_parent[cls]; int pm = (p >= 0) ? meth_find(p, m_nm[mi]) : -1; if (pm >= 0) m_slot[mi] = m_slot[pm]; else m_slot[mi] = nvirt_so_far(cls); }
int find_slot_impl(int cls, int slot) { int c = cls; while (c >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == c && m_slot[i] == slot) return i; c = cls_parent[c]; } return -1; }
char *vcast(int mi) { char *sig = (m_psig[mi] && m_psig[mi][0]) ? j2("void*, ", m_psig[mi]) : "void*"; return j4("(", cscalar(m_ret[mi]), j3(" (*)(", sig, "))"), ""); }

int tokln;
void line(int ln) { e("\n#line "); e(istr(ln)); e(" \""); e(srcname); e("\"\n"); }

struct E { int c; int t; };
int  mkE(char *c, int t) { struct E *p = (struct E *)malloc(8); p->c = (int)c; p->t = t; return (int)p; }
char *etext(int x) { return (char *)((struct E *)x)->c; }
int  etype(int x) { return ((struct E *)x)->t; }

struct AL { int e; int w; int next; };
int mkAL(int ev, int w, int nx) { struct AL *p = (struct AL *)malloc(12); p->e = ev; p->w = w; p->next = nx; return (int)p; }
int append_AL(int list, int node) { if (list == 0) return node; struct AL *n = (struct AL *)list; while (n->next) n = (struct AL *)n->next; n->next = node; return list; }

void decl_vars(char *list, int type)
{
    char buf[2048]; strcpy(buf, list); int i = 0, st = 0;
    while (1)
    {
        if (buf[i] == ',' || buf[i] == 0)
        {
            int end = buf[i]; buf[i] = 0; char *nm = buf + st;
            sym_add((char *)strdup((int)nm), K_VAR, type);
            e(decl_one(type, cname(nm))); e(";\n");
            if (end == 0) break; st = i + 1;
        }
        i++;
    }
}
char *param_text(char *list, int type, int isvar)
{
    char buf[2048]; strcpy(buf, list); char *acc = ""; int first = 1, i = 0, st = 0;
    while (1)
    {
        if (buf[i] == ',' || buf[i] == 0)
        {
            int end = buf[i]; buf[i] = 0; char *nm = buf + st;
            sym_add((char *)strdup((int)nm), isvar ? K_VARP : K_VAR, type);
            g_ref[g_np] = isvar; g_np++;
            char *pt = (isvar || !is_real(type)) ? "int" : "double";
            g_psig = (g_psig && g_psig[0]) ? j3(g_psig, ", ", pt) : pt;
            char *p = isvar ? j2(j2(cscalar(type), " *"), cname(nm)) : decl_one(type, cname(nm));
            acc = first ? p : j3(acc, ", ", p); first = 0;
            if (end == 0) break; st = i + 1;
        }
        i++;
    }
    return acc;
}

int bin(int a, char *op, int b, int t) { return mkE(F2(j3("(%s ", op, " %s)"), etext(a), etext(b)), t); }
int arith(int a, char *op, int b) { int t = (is_real(etype(a)) || is_real(etype(b))) ? T_REAL : T_INT; return bin(a, op, b, t); }
int logic(int a, char *op, int b) { return bin(a, op, b, T_BOOL); }
int rel(int a, char *op, char *sop, int b)
{
    if (is_str(etype(a)) || is_str(etype(b))) return mkE(F2(j3("(strcmp(%s, %s) ", sop, " 0)"), etext(a), etext(b)), T_BOOL);
    return bin(a, op, b, T_BOOL);
}
char *cstrlit(char *s) { char *b = (char *)malloc(strlen(s) * 2 + 3); int i = 0, j = 0; b[j++] = '"'; while (s[i]) { if (s[i] == '"' || s[i] == '\\') b[j++] = '\\'; b[j++] = s[i]; i++; } b[j++] = '"'; b[j] = 0; return b; }

char *self_call(int mi, char *a);
int emit_ident(char *name)
{
    if (is_module(name)) return mkE(name, T_MOD);
    if (cur_recv && strcmp(name, cur_recv) == 0) return mkE("(*self)", cls_rtype[curclass]);   /* receiver = self */
    int i = sym_find(name);
    if (i >= 0) { if (sym_k[i] == K_VARP) return mkE(F1("(*%s)", cname(name)), sym_t[i]); return mkE(cname(name), sym_t[i]); }
    int f = f_find(name);
    if (f >= 0) return mkE(F1("%s()", cname(name)), f_ret[f]);
    if (curclass >= 0)    /* inside a method: unqualified field / method = self.X */
    {
        int rt = cls_rtype[curclass]; int fi;
        for (fi = ty_a[rt]; fi < ty_a[rt] + ty_b[rt]; fi++) if (strcmp(rf_name[fi], name) == 0) return mkE(F1("self->%s", cname(name)), rf_type[fi]);
        int mi = meth_find(curclass, name);
        if (mi >= 0) return mkE(self_call(mi, ""), m_ret[mi]);
    }
    return mkE(cname(name), T_INT);
}
int do_index(int base, int idx)
{
    int t = etype(base);
    if (ty_kind[t] == TK_ARRAY) return mkE(F2(j3("%s[(%s)-(", istr(ty_c[t]), ")]"), etext(base), etext(idx)), ty_a[t]);
    if (ty_kind[t] == T_STR) return mkE(F2("%s[%s]", etext(base), etext(idx)), T_CHR);
    return mkE(F2("%s[%s]", etext(base), etext(idx)), T_INT);
}
int method_call(int base, char *name, int args);
int do_field(int base, char *fld)
{
    int t = etype(base);
    if (ty_kind[t] == TK_PTR) { base = do_deref(base); t = etype(base); }   /* p.f auto-derefs */
    int cls = cls_of_type(t);
    if (cls >= 0 && meth_find(cls, fld) >= 0) return method_call(base, fld, 0);   /* paramless method */
    if (ty_kind[t] == TK_RECORD) { int i; for (i = ty_a[t]; i < ty_a[t] + ty_b[t]; i++) if (strcmp(rf_name[i], fld) == 0) return mkE(F2("%s.%s", etext(base), cname(fld)), rf_type[i]); }
    return mkE(F2("%s.%s", etext(base), cname(fld)), T_INT);
}
int do_deref(int base) { int t = etype(base); int el = (ty_kind[t] == TK_PTR) ? ty_a[t] : T_INT; return mkE(F1("(*%s)", etext(base)), el); }

char *build_args(char *name, int args, int f)
{
    char *acc = ""; int k = 0, first = 1, a = args;
    while (a) { struct AL *n = (struct AL *)a; char *x = etext(n->e); char *piece = (f >= 0 && k < f_np[f] && f_ref[f][k]) ? F1("&(%s)", x) : x; acc = first ? piece : j3(acc, ", ", piece); first = 0; k++; a = n->next; }
    return acc;
}

/* write one I/O argument by type; w (optional width E) handled for Int/Real */
void io_write(int ev, int w, int real_default)
{
    int t = etype(ev); char *x = etext(ev);
    if (t == T_STR) e(F1("printf(\"%%s\", %s);\n", x));
    else if (t == T_CHR) e(F1("printf(\"%%c\", %s);\n", x));
    else if (eff(t) == T_REAL || real_default) { if (w) e(j2(F1("printf(\"%%*g\", %s, ", etext(w)), j2(x, ");\n"))); else e(F1("printf(\"%%g\", %s);\n", x)); }
    else if (t == T_BOOL) e(F1("printf(\"%%s\", (%s)?\"TRUE\":\"FALSE\");\n", x));
    else { if (w) e(j2(F1("printf(\"%%*d\", %s, ", etext(w)), j2(x, ");\n"))); else e(F1("printf(\"%%d\", %s);\n", x)); }
}
int arg_n(int args, int i) { int a = args; while (i-- > 0 && a) a = ((struct AL *)a)->next; return a; }

/* standard functions used in expressions */
int std_func(char *name, int args)
{
    struct AL *a1 = (struct AL *)args; int e1 = a1 ? a1->e : 0; char *x = e1 ? etext(e1) : "";
    if (strcmp(name, "ORD") == 0)  return mkE(F1("((int)(%s))", x), T_INT);
    if (strcmp(name, "CHR") == 0)  return mkE(F1("((char)(%s))", x), T_CHR);
    if (strcmp(name, "ABS") == 0)  return mkE(F1(is_real(etype(e1)) ? "fabs(%s)" : "abs(%s)", x), etype(e1));
    if (strcmp(name, "ODD") == 0)  return mkE(F1("(((%s)&1)!=0)", x), T_BOOL);
    if (strcmp(name, "CAP") == 0)  return mkE(F1("((char)toupper(%s))", x), T_CHR);
    if (strcmp(name, "LEN") == 0)  return mkE(F1("((int)strlen(%s))", x), T_INT);
    if (strcmp(name, "SHORT") == 0 || strcmp(name, "LONG") == 0) return mkE(x, etype(e1));
    if (strcmp(name, "ENTIER") == 0 || strcmp(name, "TRUNC") == 0) return mkE(F1("((int)(%s))", x), T_INT);
    if (strcmp(name, "FLOAT") == 0) return mkE(F1("((double)(%s))", x), T_REAL);
    return -1;
}
int emit_fcall(char *name, int args)
{
    int s = std_func(name, args);
    if (s >= 0) return s;
    int f = f_find(name);
    return mkE(F2("%s(%s)", cname(name), build_args(name, args, f)), f >= 0 ? f_ret[f] : T_INT);
}

/* built-in I/O procedures: Modula-2 (WriteString..) and Oberon (Out.String..) */
int io_proc(char *name, char *proc, int args)   /* proc=="" for unqualified M2 calls */
{
    char *p = proc[0] ? proc : name;
    struct AL *a1 = (struct AL *)args;
    if (strcmp(p, "WriteString") == 0 || strcmp(p, "String") == 0) { io_write(a1->e, 0, 0); return 1; }
    if (strcmp(p, "WriteInt") == 0 || strcmp(p, "Int") == 0 || strcmp(p, "WriteCard") == 0) { io_write(a1->e, a1->next ? ((struct AL *)a1->next)->e : 0, 0); return 1; }
    if (strcmp(p, "WriteReal") == 0 || strcmp(p, "Real") == 0) { io_write(a1->e, a1->next ? ((struct AL *)a1->next)->e : 0, 1); return 1; }
    if (strcmp(p, "Write") == 0 || strcmp(p, "WriteChar") == 0 || strcmp(p, "Char") == 0) { e(F1("printf(\"%%c\", %s);\n", etext(a1->e))); return 1; }
    if (strcmp(p, "WriteLn") == 0 || strcmp(p, "Ln") == 0) { e("printf(\"\\n\");\n"); return 1; }
    return 0;
}
void do_call(char *name, int args)   /* unqualified statement call: builtin, std, or user proc */
{
    if (io_proc(name, "", args)) return;
    if (strcmp(name, "INC") == 0 || strcmp(name, "DEC") == 0)
    {
        struct AL *n = (struct AL *)args; char *x = etext(n->e); char *op = strcmp(name, "INC") == 0 ? "+" : "-";
        if (n->next) e(j2(F2("%s = %s ", x, x), j4(op, " ", etext(((struct AL *)n->next)->e), ";\n")));
        else e(j2(F2("%s = %s ", x, x), j3(op, " 1", ";\n")));
        return;
    }
    if (strcmp(name, "NEW") == 0)
    {
        struct AL *n = (struct AL *)args; int el = ty_a[etype(n->e)];
        e(F2("%s = malloc(sizeof(%s));\n", etext(n->e), cscalar(el)));
        int cls = cls_of_type(el); if (cls >= 0 && nvirt_so_far(cls) > 0) e(j3("(", etext(n->e), j3(")->__vmt = VMT_", cls_name[cls], ";\n")));
        return;
    }
    if (strcmp(name, "HALT") == 0) { struct AL *n = (struct AL *)args; e(F1("exit(%s);\n", n ? etext(n->e) : (char *)"0")); return; }
    if (strcmp(name, "INCL") == 0) { struct AL *n = (struct AL *)args; e(F2("ps_incl(%s, %s);\n", etext(n->e), etext(((struct AL *)n->next)->e))); return; }
    if (strcmp(name, "EXCL") == 0) { struct AL *n = (struct AL *)args; e(F2("ps_excl(%s, %s);\n", etext(n->e), etext(((struct AL *)n->next)->e))); return; }
    int f = f_find(name);
    e(F2("%s(%s);\n", cname(name), build_args(name, args, f)));
}
/* type-bound procedures dispatch through the object's __vmt (all are virtual) */
int method_call(int base, char *name, int args)
{
    if (ty_kind[etype(base)] == TK_PTR) base = do_deref(base);
    int cls = cls_of_type(etype(base));
    int mi = meth_find(cls, name);
    char *a = build_args(name, args, -1);
    char *self = F1("&(%s)", etext(base));
    if (mi >= 0)
    {
        char *fp = j3("(", j2(vcast(mi), F2("(%s).__vmt[%s]", etext(base), istr(m_slot[mi]))), ")");
        char *call = (a[0] == 0) ? F2("%s(%s)", fp, self) : j2(j4(fp, "(", self, ", "), j2(a, ")"));
        return mkE(call, m_ret[mi]);
    }
    return mkE(F2("m_unknown_%s(%s)", name, self), T_INT);
}
char *self_call(int mi, char *a)   /* call on `self` inside a method body (virtual) */
{
    char *fp = j3("(", j2(vcast(mi), F1("self->__vmt[%s]", istr(m_slot[mi]))), ")");
    return (a[0] == 0) ? F1("%s(self)", fp) : j2(j4(fp, "(self, ", a, ")"), "");
}
void do_qcall(int base, char *proc, int args)   /* obj.Method(args) or Module.Proc(args) */
{
    if (etype(base) == T_MOD) { if (io_proc("", proc, args)) return; }
    int t = etype(base); int bt = (ty_kind[t] == TK_PTR) ? ty_a[t] : t;
    int cls = cls_of_type(bt);
    if (cls >= 0 && meth_find(cls, proc) >= 0) { int r = method_call(base, proc, args); e(etext(r)); e(";\n"); return; }
    e(F2("%s(%s)", etext(do_field(base, proc)), build_args(proc, args, -1))); e(";\n");
}
void reg_method_on(int cls, char *name, int ret, char *psig)
{
    m_cls[nm] = cls; m_nm[nm] = name; m_ret[nm] = ret; m_psig[nm] = psig; m_slot[nm] = -1; nm++;
    assign_slot(nm - 1);
}
int recv_class(char *tn) { int t = name_type(tn); if (ty_kind[t] == TK_PTR) t = ty_a[t]; return cls_of_type(t); }
void begin_method(int cls, char *methn, int ret, char *params, char *recv)
{
    curclass = cls; cur_recv = recv; cur_ret = ret;
    char *self = j2(cscalar(cls_rtype[cls]), " *self");
    e(j4(cscalar(ret), " ", mname(cls, methn), "("));
    if (params[0]) e(j3(self, ", ", params)); else e(self);
    e("){\n");
}
void do_assign(int lv, int ev)
{
    if (is_str(etype(lv))) { e(F2("strcpy(%s, %s);\n", etext(lv), etext(ev))); return; }
    e(F2("%s = %s;\n", etext(lv), etext(ev)));
}
%}

%token KMODULE KBEGIN KEND KCONST KTYPE KVAR KPROCEDURE KIF KTHEN KELSIF KELSE
%token KWHILE KDO KREPEAT KUNTIL KFOR KTO KBY KCASE KOF KLOOP KEXIT KRETURN
%token KARRAY KRECORD KPOINTER KSET KDIV KMOD KAND KOR KNOT KIN KNIL KTRUE KFALSE
%token KWITH KIMPORT KFROM KDEF KIMPL
%token IDENT INTLIT REALLIT STRLIT ASSIGN DOTDOT LE GE NE

%nonassoc '=' NE '<' '>' LE GE KIN
%left '+' '-' KOR
%left '*' '/' KDIV KMOD KAND
%right KNOT
%right UMINUS

%start module
%%
module    : KMODULE IDENT ';' phead imports decl_seq mainhdr opt_body KEND IDENT '.'  { e("\nreturn 0;\n}\n"); } ;
phead     : /* empty */  { e("char *__sc(char*a,char*b){char*r=(char*)malloc(strlen(a)+strlen(b)+1);strcpy(r,a);strcat(r,b);return r;}\n"); } ;
mainhdr   : /* empty */  { emit_vtables(); e("\nint main(void){\n"); } ;
opt_body  : /* empty */ | KBEGIN stmt_seq ;

imports   : /* empty */ | imports impclause ;
impclause : KIMPORT implist ';' | KFROM IDENT KIMPORT implist ';' ;
implist   : impitem | implist ',' impitem ;
impitem   : IDENT | IDENT ASSIGN IDENT ;

decl_seq  : /* empty */ | decl_seq decl ;
decl      : KCONST clist | KTYPE tlist | KVAR vlist | proc_decl ;

clist     : /* empty */ | clist identdef '=' expr ';'  { e(j4(cscalar(etype($4)), " ", cname((char *)$2), j3(" = ", etext($4), ";\n"))); sym_add((char *)$2, K_CONST, etype($4)); } ;
tlist     : /* empty */ | tlist tdname '=' typ ';'
            { char *nm = (char *)$2; int ty = $4; int idx = tn_find(nm);
              if (idx >= 0) { ty_kind[idx] = ty_kind[ty]; ty_a[idx] = ty_a[ty]; ty_b[idx] = ty_b[ty]; ty_c[idx] = ty_c[ty]; int c = cls_of_type(ty); if (c >= 0) cls_rtype[c] = idx; }
              else { tn_name[ntn] = nm; tn_type[ntn] = ty; ntn++; } } ;
tdname    : IDENT star  { pending_typename = (char *)$1; $$ = $1; } ;
vlist     : /* empty */ | vlist idlist ':' typ ';'     { decl_vars((char *)$2, $4); } ;

identdef  : IDENT star  { $$ = $1; } ;
star      : /* empty */ | '*' ;
idlist    : identdef               { $$ = $1; }
          | idlist ',' identdef    { $$ = (int)j3((char *)$1, ",", (char *)$3); } ;

typ       : IDENT                         { $$ = name_type((char *)$1); }
          | KARRAY arrlen KOF typ         { $$ = mkty(TK_ARRAY, $4, $2, 0); }   /* a=elem, b=len, c=lo(0) */
          | KARRAY KOF typ                { $$ = mkty(TK_ARRAY, $3, 0, 0); }    /* open array */
          | recbase rec_open field_seq KEND   { $$ = close_record(); }
          | KPOINTER KTO typ              { $$ = mkty(TK_PTR, $3, 0, 0); }
          | KSET                          { $$ = T_SET; } ;
recbase   : KRECORD                  { g_recbase = -1; }
          | KRECORD '(' IDENT ')'    { g_recbase = cls_find((char *)$3); } ;
arrlen    : INTLIT  { $$ = $1; } | IDENT { $$ = 64; } ;   /* const-named lengths approx */
rec_open  : /* empty */  { rec_push(); } ;
field_seq : field | field_seq ';' field | field_seq ';' ;
field     : idlist ':' typ  { add_fields((char *)$1, $3); } ;

proc_decl : phdr decl_seq opt_body KEND IDENT ';'  { e("}\n"); nsym = saved_nsym; cur_ret = T_VOID; }
          | mhdr decl_seq opt_body KEND IDENT ';'  { e("}\n"); nsym = saved_nsym; curclass = -1; cur_recv = 0; cur_ret = T_VOID; } ;
phdr      : KPROCEDURE identdef pscope formals ';'
            { reg_func((char *)$2, cur_ret); e(j4(cscalar(cur_ret), " ", cname((char *)$2), j3("(", g_params, "){\n"))); } ;
mhdr      : KPROCEDURE '(' recv ')' identdef pscope formals ';'
            { begin_method(g_recvcls, (char *)$5, cur_ret, g_params, g_recvname); reg_method_on(g_recvcls, (char *)$5, cur_ret, g_psig); } ;
recv      : IDENT ':' IDENT       { g_recvname = (char *)$1; g_recvcls = recv_class((char *)$3); }
          | KVAR IDENT ':' IDENT  { g_recvname = (char *)$2; g_recvcls = recv_class((char *)$4); } ;
pscope    : /* empty */  { saved_nsym = nsym; g_np = 0; cur_ret = T_VOID; g_params = ""; g_psig = ""; } ;
formals   : /* empty */                 { g_params = ""; }
          | '(' ')' optret              { g_params = ""; }
          | '(' fplist ')' optret       { g_params = (char *)$2; } ;
optret    : /* empty */ | ':' typ  { cur_ret = $2; } ;
fplist    : fpsec                { $$ = $1; }
          | fplist ';' fpsec     { $$ = (int)j3((char *)$1, ", ", (char *)$3); } ;
fpsec     : idlist ':' typ        { $$ = (int)param_text((char *)$1, $3, 0); }
          | KVAR idlist ':' typ   { $$ = (int)param_text((char *)$2, $4, 1); } ;

stmt_seq  : stmt | stmt_seq ';' stmt ;
stmt      : /* empty */ | smark real_stmt ;
smark     : /* empty */  { line(tokln); } ;

real_stmt : assign | call | if_stmt | while_stmt | repeat_stmt | for_stmt | loop_stmt | case_stmt
          | KEXIT          { e("break;\n"); }
          | KRETURN expr   { e(F1("return %s;\n", etext($2))); }
          | KRETURN        { e("return;\n"); } ;

assign    : desig ASSIGN expr             { do_assign($1, $3); }
          | desig ASSIGN '{' setlist '}'  { e(F2("%s = %s;\n", etext($1), build_setval($4))); } ;

call      : IDENT                          { if (!io_proc((char*)$1, "", 0)) do_call((char *)$1, 0); }
          | IDENT '(' arglist ')'          { do_call((char *)$1, $3); }
          | desig '.' IDENT                { do_qcall($1, (char *)$3, 0); }
          | desig '.' IDENT '(' arglist ')'{ do_qcall($1, (char *)$3, $5); } ;

desig     : IDENT                  { $$ = emit_ident((char *)$1); }
          | desig '.' IDENT        { $$ = do_field($1, (char *)$3); }
          | desig '[' idxlist ']'  { $$ = fold_index($1, $3); }
          | desig '^'              { $$ = do_deref($1); } ;
idxlist   : expr               { $$ = mkAL($1, 0, 0); }
          | idxlist ',' expr   { $$ = append_AL($1, mkAL($3, 0, 0)); } ;

if_stmt   : ifh stmt_seq elifs elsepart KEND  { e("}\n"); } ;
ifh       : KIF expr KTHEN  { e(F1("if (%s) {\n", etext($2))); } ;
elifs     : /* empty */ | elifs elifclause ;
elifclause: elifh stmt_seq ;
elifh     : KELSIF expr KTHEN  { e(F1("} else if (%s) {\n", etext($2))); } ;
elsepart  : /* empty */ | elseh stmt_seq ;
elseh     : KELSE  { e("} else {\n"); } ;

while_stmt: wh stmt_seq KEND  { e("}\n"); } ;
wh        : KWHILE expr KDO  { e(F1("while (%s) {\n", etext($2))); } ;

repeat_stmt: reph stmt_seq KUNTIL expr  { e(F1("} while (!(%s));\n", etext($4))); } ;
reph      : KREPEAT  { e("do {\n"); } ;

for_stmt  : forh stmt_seq KEND  { e("}\n"); } ;
forh      : KFOR IDENT ASSIGN expr KTO expr forby KDO
            { char *v = cname((char *)$2); e("for ("); e(v); e(" = "); e(etext($4)); e("; "); e(v); e(" <= "); e(etext($6)); e("; "); e(v); e(g_byneg ? " -= " : " += "); e(g_bystep); e(") {\n"); } ;
forby     : /* empty */  { g_bystep = "1"; g_byneg = 0; }
          | KBY INTLIT   { g_bystep = istr($2); g_byneg = 0; }
          | KBY '-' INTLIT { g_bystep = istr($3); g_byneg = 1; } ;

loop_stmt : looph stmt_seq KEND  { e("}\n"); } ;
looph     : KLOOP  { e("while (1) {\n"); } ;

case_stmt : caseh caselist caseend ;
caseh     : KCASE expr KOF  { e(F1("switch (%s) {\n", etext($2))); } ;
caselist  : casearm | caselist '|' casearm ;
casearm   : /* empty */ | caselabset stmt_seq  { e("break;\n"); } ;
caselabset: labels ':' ;
labels    : caselabel | labels ',' caselabel ;
caselabel : INTLIT                 { e(F1("case %s:\n", istr($1))); }
          | INTLIT DOTDOT INTLIT   { int v; for (v = $1; v <= $3; v++) e(F1("case %s:\n", istr(v))); } ;
caseend   : KEND  { e("}\n"); }
          | caseelse stmt_seq KEND  { e("}\n"); } ;
caseelse  : KELSE  { e("default:\n"); } ;

arglist   : /* empty */  { $$ = 0; }
          | argne        { $$ = $1; } ;
argne     : expr             { $$ = mkAL($1, 0, 0); }
          | argne ',' expr   { $$ = append_AL($1, mkAL($3, 0, 0)); } ;

setlist   : /* empty */ { $$ = 0; } | setne { $$ = $1; } ;
setne     : setel             { $$ = $1; }
          | setne ',' setel   { $$ = append_AL($1, $3); } ;
setel     : expr             { $$ = mkAL($1, 0, 0); }
          | expr DOTDOT expr { $$ = mkAL($1, $3, 0); } ;

expr : expr '=' expr   { $$ = rel($1, "==", "==", $3); }
     | expr NE expr    { $$ = rel($1, "!=", "!=", $3); }
     | expr '<' expr   { $$ = rel($1, "<", "<", $3); }
     | expr '>' expr   { $$ = rel($1, ">", ">", $3); }
     | expr LE expr    { $$ = rel($1, "<=", "<=", $3); }
     | expr GE expr    { $$ = rel($1, ">=", ">=", $3); }
     | expr KIN expr   { $$ = mkE(F2("(ps_in(%s, %s) != 0)", etext($3), etext($1)), T_BOOL); }
     | expr '+' expr   { if (etype($1) == T_SET) $$ = mkE(F2("ps_or(%s, %s)", etext($1), etext($3)), T_SET); else if (is_str(etype($1))) $$ = mkE(F2("__sc(%s, %s)", etext($1), etext($3)), T_STR); else $$ = arith($1, "+", $3); }
     | expr '-' expr   { if (etype($1) == T_SET) $$ = mkE(F2("ps_sub(%s, %s)", etext($1), etext($3)), T_SET); else $$ = arith($1, "-", $3); }
     | expr KOR expr   { $$ = logic($1, "||", $3); }
     | expr '*' expr   { if (etype($1) == T_SET) $$ = mkE(F2("ps_and(%s, %s)", etext($1), etext($3)), T_SET); else $$ = arith($1, "*", $3); }
     | expr '/' expr   { $$ = mkE(F2("((double)(%s)/(double)(%s))", etext($1), etext($3)), T_REAL); }
     | expr KDIV expr  { $$ = bin($1, "/", $3, T_INT); }
     | expr KMOD expr  { $$ = bin($1, "%", $3, T_INT); }
     | expr KAND expr  { $$ = logic($1, "&&", $3); }
     | KNOT expr       { $$ = mkE(F1("(!%s)", etext($2)), T_BOOL); }
     | '-' expr %prec UMINUS  { $$ = mkE(F1("(-%s)", etext($2)), etype($2)); }
     | '+' expr %prec UMINUS  { $$ = $2; }
     | '(' expr ')'    { $$ = mkE(F1("(%s)", etext($2)), etype($2)); }
     | '{' setlist '}' { $$ = mkE(build_setval($2), T_SET); }
     | INTLIT          { $$ = mkE(istr($1), T_INT); }
     | REALLIT         { $$ = mkE((char *)$1, T_REAL); }
     | STRLIT          { $$ = mkE(cstrlit((char *)$1), T_STR); }
     | KTRUE           { $$ = mkE("1", T_BOOL); }
     | KFALSE          { $$ = mkE("0", T_BOOL); }
     | KNIL            { $$ = mkE("0", T_INT); }
     | desig           { $$ = $1; }
     | IDENT '(' arglist ')'  { $$ = emit_fcall((char *)$1, $3); }
     | desig '.' IDENT '(' arglist ')'  { $$ = method_call($1, (char *)$3, $5); } ;
%%

char *g_params; char *g_bystep; int g_byneg; int g_recbase; char *g_recvname; int g_recvcls;
int fold_index(int base, int list) { int a = list; while (a) { struct AL *n = (struct AL *)a; base = do_index(base, n->e); a = n->next; } return base; }
int rec_stack[64]; int rec_sp;
void rec_push(void)
{
    rec_stack[rec_sp++] = nrf;
    if (g_recbase >= 0) { int rt = cls_rtype[g_recbase]; int i; for (i = ty_a[rt]; i < ty_a[rt] + ty_b[rt]; i++) { rf_name[nrf] = rf_name[i]; rf_type[nrf] = rf_type[i]; nrf++; } }
}
int close_record(void)
{
    int start = rec_stack[--rec_sp]; int n = nrf - start; int sid = n_struct++;
    int t = mkty(TK_RECORD, start, n, sid);
    int cls = ncls;   /* every record is a class (single inheritance via extension) */
    cls_name[cls] = pending_typename ? pending_typename : j2("Anon", istr(sid));
    cls_parent[cls] = g_recbase; cls_rtype[cls] = t;
    cls_nvirt[cls] = (g_recbase >= 0) ? cls_nvirt[g_recbase] : 0;
    ncls++; pending_typename = 0;
    e("typedef struct { int* __vmt; ");
    int i; for (i = start; i < start + n; i++) { e(decl_one(rf_type[i], cname(rf_name[i]))); e("; "); }
    e(j3("} R", istr(sid), ";\n"));
    return t;
}
void emit_vtables(void)   /* after all decls/methods are known, before main */
{
    int c; for (c = 0; c < ncls; c++) { int nv = nvirt_so_far(c); if (nv > 0)
    {
        e(j3("int VMT_", cls_name[c], "[] = { "));
        int k; for (k = 0; k < nv; k++) { int mi = find_slot_impl(c, k); if (k) e(", "); e(mi >= 0 ? j2("(int)", mname(m_cls[mi], m_nm[mi])) : (char *)"0"); }
        e(" };\n");
    } }
}
void add_fields(char *list, int type)
{
    char buf[2048]; strcpy(buf, list); int i = 0, st = 0;
    while (1)
    {
        if (buf[i] == ',' || buf[i] == 0) { int end = buf[i]; buf[i] = 0; rf_name[nrf] = (char *)strdup((int)(buf + st)); rf_type[nrf] = type; nrf++; if (end == 0) break; st = i + 1; }
        i++;
    }
}
char *build_setval(int list)
{
    int n = 0, a = list; while (a) { n++; a = ((struct AL *)a)->next; }
    char *args = istr(n); a = list;
    while (a) { struct AL *nn = (struct AL *)a; char *lo = etext(nn->e); char *hi = nn->w ? etext(nn->w) : lo; args = j2(args, j4(", ", lo, ", ", hi)); a = nn->next; }
    return F1("ps_lit(%s)", args);
}

/* strip nested (* *) comments, preserving newlines; leave string literals alone */
void strip_comments(char *s)
{
    int i = 0;
    while (s[i])
    {
        if (s[i] == '"' || s[i] == '\'') { int q = s[i]; i++; while (s[i] && s[i] != q) i++; if (s[i]) i++; continue; }
        if (s[i] == '(' && s[i + 1] == '*')
        {
            int depth = 1; s[i] = ' '; s[i + 1] = ' '; i += 2;
            while (s[i] && depth > 0)
            {
                if (s[i] == '(' && s[i + 1] == '*') { depth++; s[i] = ' '; s[i + 1] = ' '; i += 2; continue; }
                if (s[i] == '*' && s[i + 1] == ')') { depth--; s[i] = ' '; s[i + 1] = ' '; i += 2; continue; }
                if (s[i] != '\n') s[i] = ' '; i++;
            }
            continue;
        }
        i++;
    }
}
void setext(char *path, char *ext)
{
    int n = strlen(path), i = n - 1;
    while (i > 0 && path[i] != '.' && path[i] != '\\' && path[i] != '/') i--;
    if (path[i] == '.') path[i + 1] = 0; else strcat(path, ".");
    strcat(path, ext);
}
void yyerror(char *m) { printf((int)"oberon: %s near line %d\n", (int)m, pline); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: oberon <file> [-o <out.exe>]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int i;
    for (i = 2; i < argc; i++) if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) { o = (char *)argv[i + 1]; i++; }
    char outexe[1024]; char cpath[1024];
    if (o) strcpy(outexe, o); else { strcpy(outexe, in); setext(outexe, "exe"); }
    strcpy(cpath, outexe); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"oberon: cannot read %s\n", (int)in); return 1; }
    strip_comments(src);
    srcname = in; g_params = ""; g_bystep = "1"; g_psig = ""; g_recbase = -1; curclass = -1; cur_recv = 0; pending_typename = 0;
    nty = 0; int rsv; for (rsv = 0; rsv <= T_MOD; rsv++) mkty(0, 0, 0, 0);
    ty_kind[T_INT] = T_INT; ty_kind[T_REAL] = T_REAL; ty_kind[T_CHR] = T_CHR; ty_kind[T_BOOL] = T_BOOL; ty_kind[T_STR] = T_STR; ty_kind[T_SET] = T_SET; ty_kind[T_MOD] = T_MOD;
    out = fopen((int)cpath, (int)"w");
    if (out == 0) { printf((int)"oberon: cannot write %s\n", (int)cpath); return 1; }
    yy_scan_string((int)src);
    yyparse();
    fclose(out);
    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; av[0] = (int)cc; av[1] = (int)cpath; av[2] = (int)"-o"; av[3] = (int)outexe; av[4] = (int)"--exe";
    int rc = sh_run((int)av, 5);
    if (rc == 0) printf((int)"oberon: %s -> %s\n", (int)in, (int)outexe);
    else printf((int)"oberon: cc failed (%d)\n", rc);
    return rc;
}
