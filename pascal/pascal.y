%{
/* Pascal -> C compiler (yacc). Syntax-directed translation emitting C (+#line),
 * which cc lowers to .NET IL + native exe + PDB. Built with our own lex+yacc+cc.
 *
 * Type system: every type is an index into a type table. Base types occupy 1..5
 * (so legacy T_INT..T_STR are valid indices); composite kinds are 10+. */

#define T_VOID 0
#define T_INT  1
#define T_REAL 2
#define T_CHR  3
#define T_BOOL 4
#define T_STR  5
#define T_FILE 6
#define T_SET  7
#define TK_ARRAY 10
#define TK_RECORD 11
#define TK_PTR 12
#define TK_ENUM 13
#define TK_SUB 14

#define K_VAR   1
#define K_VARP  2     /* var parameter (by reference) */
#define K_CONST 3

int out;            /* output FILE* (int handle) */
char *pasfile;

void e(char *s) { fputs((int)s, out); }

/* --- string builders --- */
char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *fmt, char *a) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + 8); sprintf((int)r, (int)fmt, (int)a); return r; }
char *F2(char *fmt, char *a, char *b) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + strlen(b) + 8); sprintf((int)r, (int)fmt, (int)a, (int)b); return r; }
char *F4(char *fmt, char *a, char *b, char *c, char *d) { char *r = (char *)malloc(strlen(fmt) + strlen(a) + strlen(b) + strlen(c) + strlen(d) + 8); sprintf((int)r, (int)fmt, (int)a, (int)b, (int)c, (int)d); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *cname(char *id) { return j2("p_", id); }

/* --- type table --- */
int ty_kind[3000]; int ty_a[3000]; int ty_b[3000]; int ty_c[3000];   /* a/b/c: array elem,lo,hi | ptr elem | sub base,lo,hi | rec fieldstart,nfields,structid | enum first,count */
int nty;
int mkty(int k, int a, int b, int c) { ty_kind[nty] = k; ty_a[nty] = a; ty_b[nty] = b; ty_c[nty] = c; return nty++; }

/* record fields */
char *rf_name[6000]; int rf_type[6000]; int nrf; int n_struct;

int eff(int t) { int k = ty_kind[t]; if (k == TK_SUB) return eff(ty_a[t]); if (k == TK_ENUM) return T_INT; return k; }
int is_real(int t) { return eff(t) == T_REAL; }
int is_str(int t) { return ty_kind[t] == T_STR; }

char *struct_name(int t) { return j2("R", istr(ty_c[t])); }

char *cscalar(int t)    /* C type for a scalar/pointer/record/string slot */
{
    int k = ty_kind[t];
    if (k == T_INT || k == T_BOOL || k == TK_ENUM || k == TK_SUB) return "int";
    if (k == T_REAL) return "double";
    if (k == T_CHR) return "char";
    if (k == T_STR) return "char*";
    if (k == TK_PTR) return j2(cscalar(ty_a[t]), "*");
    if (k == TK_RECORD) return struct_name(t);
    if (k == TK_ARRAY) return cscalar(ty_a[t]);
    return "int";
}

/* full C declaration for `name` of type t (arrays get [n] suffixes; strings [256]) */
char *decl_one(int t, char *name)
{
    if (ty_kind[t] == TK_ARRAY)
    {
        char dims[256]; dims[0] = 0; int el = t;
        while (ty_kind[el] == TK_ARRAY) { int len = ty_c[el] - ty_b[el] + 1; char d[32]; sprintf((int)d, (int)"[%d]", len); strcat(dims, d); el = ty_a[el]; }
        return j4(cscalar(el), " ", name, dims);
    }
    if (ty_kind[t] == T_STR) return j3("char ", name, "[256]");
    return j3(cscalar(t), " ", name);
}

/* --- symbol table (vars/params/consts), saved/restored per proc scope --- */
char *sym_n[6000]; int sym_k[6000]; int sym_t[6000]; int sym_v[6000]; int nsym;
int saved_nsym;
int sym_find(char *n) { int i; for (i = nsym - 1; i >= 0; i--) if (strcmp(sym_n[i], n) == 0) return i; return -1; }
void sym_add(char *n, int k, int t) { sym_n[nsym] = n; sym_k[nsym] = k; sym_t[nsym] = t; sym_v[nsym] = 0; nsym++; }

/* --- named types --- */
char *tn_name[2000]; int tn_type[2000]; int ntn;
int tn_find(char *n) { int i; for (i = 0; i < ntn; i++) if (strcmp(tn_name[i], n) == 0) return tn_type[i]; return -1; }

/* --- functions/procedures (persist) --- */
char *f_n[2000]; int f_ret[2000]; int f_np[2000]; char f_ref[2000][32]; int nf;
int g_np; char g_ref[64];
char *curfunc; int cur_ret;
int f_find(char *n) { int i; for (i = 0; i < nf; i++) if (strcmp(f_n[i], n) == 0) return i; return -1; }
void reg_func(char *n, int ret) { f_n[nf] = n; f_ret[nf] = ret; f_np[nf] = g_np; int k; for (k = 0; k < g_np; k++) f_ref[nf][k] = g_ref[k]; nf++; }

int base_type(char *id)
{
    if (strcmp(id, "integer") == 0) return T_INT;
    if (strcmp(id, "real") == 0) return T_REAL;
    if (strcmp(id, "char") == 0) return T_CHR;
    if (strcmp(id, "boolean") == 0) return T_BOOL;
    if (strcmp(id, "string") == 0) return T_STR;
    if (strcmp(id, "text") == 0 || strcmp(id, "file") == 0) return T_FILE;
    return -1;
}
int name_type(char *id) { int b = base_type(id); if (b >= 0) return b; int u = tn_find(id); if (u >= 0) return u; return T_INT; }

/* --- OOP: object types (single inheritance), methods, virtual dispatch --- */
char *cls_name[400]; int cls_rtype[400]; int cls_parent[400]; int cls_nvirt[400]; int ncls;
int m_cls[5000]; char *m_nm[5000]; int m_ret[5000]; int m_virt[5000]; int m_ctor[5000]; int m_slot[5000]; char *m_psig[5000]; int nm;
int curclass; char *pending_typename; char *g_psig;
int cls_find(char *n) { int i; for (i = 0; i < ncls; i++) if (strcmp(cls_name[i], n) == 0) return i; return -1; }
int cls_of_type(int t) { int i; for (i = 0; i < ncls; i++) if (cls_rtype[i] == t) return i; return -1; }
char *mname(int c, char *n) { return j4("m_", cls_name[c], "_", n); }
int meth_find(int c, char *name) { while (c >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == c && strcmp(m_nm[i], name) == 0) return i; c = cls_parent[c]; } return -1; }
void reg_method(char *name, int ret, char *psig) { m_cls[nm] = ncls - 1; m_nm[nm] = name; m_ret[nm] = ret; m_psig[nm] = psig; m_virt[nm] = 0; m_ctor[nm] = 0; m_slot[nm] = -1; nm++; }
/* assign a vtable slot: overrides reuse the parent's slot; new virtuals get a fresh one */
void assign_slot(int mi)
{
    int cls = m_cls[mi]; int p = cls_parent[cls];
    int pm = (p >= 0) ? meth_find(p, m_nm[mi]) : -1;
    if (pm >= 0) m_slot[mi] = m_slot[pm]; else m_slot[mi] = cls_nvirt[cls]++;
}
int find_slot_impl(int cls, int slot) { int c = cls; while (c >= 0) { int i; for (i = 0; i < nm; i++) if (m_cls[i] == c && m_virt[i] && m_slot[i] == slot) return i; c = cls_parent[c]; } return -1; }
char *vcast(int mi)    /* "(ret (*)(void*, psig))" for a virtual call site */
{
    char *sig = (m_psig[mi] && m_psig[mi][0]) ? j2("void*, ", m_psig[mi]) : "void*";
    return j4("(", cscalar(m_ret[mi]), j3(" (*)(", sig, "))"), "");
}

int tokln;
void line(int ln) { e("\n#line "); e(istr(ln)); e(" \""); e(pasfile); e("\"\n"); }

/* with-statement scope: unqualified names resolve to fields of these records */
char *with_rec[16]; int with_ty[16]; int nwith;

/* --- expression value: C text + type --- */
struct E { int c; int t; };
int  mkE(char *c, int t) { struct E *p = (struct E *)malloc(8); p->c = (int)c; p->t = t; return (int)p; }
char *etext(int x) { return (char *)((struct E *)x)->c; }
int  etype(int x) { return ((struct E *)x)->t; }

/* --- call argument node (carries optional :width:dec for write) --- */
struct AL { int e; int w; int d; int next; };
int mkAL(int ev, int w, int d, int nx) { struct AL *p = (struct AL *)malloc(16); p->e = ev; p->w = w; p->d = d; p->next = nx; return (int)p; }
int append_AL(int list, int node) { if (list == 0) return node; struct AL *n = (struct AL *)list; while (n->next) n = (struct AL *)n->next; n->next = node; return list; }

/* declare vars (comma list) of a type; emit C decls + register symbols */
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
            char *pt = (isvar || !is_real(type)) ? "int" : "double";   /* cast-signature param type (refs/ptrs are int-width) */
            g_psig = (g_psig && g_psig[0]) ? j3(g_psig, ", ", pt) : pt;
            char *p;
            if (isvar) p = j2(j2(cscalar(type), " *"), cname(nm));   /* by reference */
            else p = decl_one(type, cname(nm));                      /* by value (arrays/strings decay) */
            acc = first ? p : j3(acc, ", ", p); first = 0;
            if (end == 0) break; st = i + 1;
        }
        i++;
    }
    return acc;
}

/* --- expression helpers --- */
int bin(int a, char *op, int b, int t) { return mkE(F2(j3("(%s ", op, " %s)"), etext(a), etext(b)), t); }
int arith(int a, char *op, int b) { int t = (is_real(etype(a)) || is_real(etype(b))) ? T_REAL : T_INT; return bin(a, op, b, t); }
int logic(int a, char *bop, char *iop, int b) { int bo = (eff(etype(a)) == T_BOOL); return bin(a, bo ? bop : iop, b, bo ? T_BOOL : T_INT); }
int rel(int a, char *op, char *sop, int b)     /* strings compare via strcmp */
{
    if (is_str(etype(a)) || is_str(etype(b))) return mkE(F2(j3("(strcmp(%s, %s) ", sop, " 0)"), etext(a), etext(b)), T_BOOL);
    return bin(a, op, b, T_BOOL);
}

char *cstrlit(char *s) { char *b = (char *)malloc(strlen(s) * 2 + 3); int i = 0, j = 0; b[j++] = '"'; while (s[i]) { if (s[i] == '"' || s[i] == '\\') b[j++] = '\\'; b[j++] = s[i]; i++; } b[j++] = '"'; b[j] = 0; return b; }
char *cchrlit(char *s) { char *b = (char *)malloc(8); int j = 0; b[j++] = '\''; if (s[0] == '\'' || s[0] == '\\') b[j++] = '\\'; b[j++] = s[0]; b[j++] = '\''; b[j] = 0; return b; }

int emit_ident(char *name)
{
    if (curfunc && strcmp(name, curfunc) == 0) return mkE("__result", cur_ret);
    int w; for (w = nwith - 1; w >= 0; w--)   /* with-fields shadow outer names */
    {
        int rt = with_ty[w];
        if (ty_kind[rt] == TK_RECORD) { int fi; for (fi = ty_a[rt]; fi < ty_a[rt] + ty_b[rt]; fi++) if (strcmp(rf_name[fi], name) == 0) return mkE(F2("%s.%s", with_rec[w], cname(name)), rf_type[fi]); }
    }
    int i = sym_find(name);
    if (i >= 0)
    {
        if (sym_k[i] == K_CONST) return mkE(cname(name), sym_t[i]);
        if (sym_k[i] == K_VARP) return mkE(F1("(*%s)", cname(name)), sym_t[i]);
        return mkE(cname(name), sym_t[i]);
    }
    int f = f_find(name);
    if (f >= 0) return mkE(F1("%s()", cname(name)), f_ret[f]);
    if (curclass >= 0)    /* inside a method: unqualified field / paramless method = self.X */
    {
        int rt = cls_rtype[curclass]; int fi;
        for (fi = ty_a[rt]; fi < ty_a[rt] + ty_b[rt]; fi++) if (strcmp(rf_name[fi], name) == 0) return mkE(F1("self->%s", cname(name)), rf_type[fi]);
        int mi = meth_find(curclass, name);
        if (mi >= 0) return mkE(self_call(mi, ""), m_ret[mi]);
    }
    return mkE(cname(name), T_INT);
}
char *self_call(int mi, char *a);

/* index a designator: arrays use lower-bound offset; strings are 1-based char access */
int do_index(int base, int idx)
{
    int t = etype(base);
    if (ty_kind[t] == TK_ARRAY)
        return mkE(F2(j3("%s[(%s)-(", istr(ty_b[t]), ")]"), etext(base), etext(idx)), ty_a[t]);
    if (ty_kind[t] == T_STR)
        return mkE(F2("%s[(%s)-1]", etext(base), etext(idx)), T_CHR);
    return mkE(F2("%s[%s]", etext(base), etext(idx)), T_INT);
}
int method_call(int base, char *name, int args);
int do_field(int base, char *fld)
{
    int t = etype(base);
    int cls = cls_of_type(t);
    if (cls >= 0 && meth_find(cls, fld) >= 0) return method_call(base, fld, 0);   /* paramless method */
    if (ty_kind[t] == TK_RECORD)
    {
        int i; for (i = ty_a[t]; i < ty_a[t] + ty_b[t]; i++) if (strcmp(rf_name[i], fld) == 0) return mkE(F2("%s.%s", etext(base), cname(fld)), rf_type[i]);
    }
    return mkE(F2("%s.%s", etext(base), cname(fld)), T_INT);
}
int do_deref(int base) { int t = etype(base); int el = (ty_kind[t] == TK_PTR) ? ty_a[t] : T_INT; return mkE(F1("(*%s)", etext(base)), el); }

char *build_args(char *name, int args, int f)
{
    char *acc = ""; int k = 0, first = 1, a = args;
    while (a)
    {
        struct AL *n = (struct AL *)a; char *x = etext(n->e);
        char *piece = (f >= 0 && k < f_np[f] && f_ref[f][k]) ? F1("&(%s)", x) : x;
        acc = first ? piece : j3(acc, ", ", piece); first = 0;
        k++; a = n->next;
    }
    return acc;
}

/* standard functions used in expressions */
int std_func(char *name, int args)
{
    struct AL *a1 = (struct AL *)args;
    int e1 = a1 ? a1->e : 0;
    char *x = e1 ? etext(e1) : "";
    if (strcmp(name, "ord") == 0)  return mkE(F1("((int)(%s))", x), T_INT);
    if (strcmp(name, "chr") == 0)  return mkE(F1("((char)(%s))", x), T_CHR);
    if (strcmp(name, "abs") == 0)  return mkE(F1(is_real(etype(e1)) ? "fabs(%s)" : "abs(%s)", x), etype(e1));
    if (strcmp(name, "sqr") == 0)  return mkE(F2("((%s)*(%s))", x, x), etype(e1));
    if (strcmp(name, "sqrt") == 0) return mkE(F1("sqrt(%s)", x), T_REAL);
    if (strcmp(name, "sin") == 0)  return mkE(F1("sin(%s)", x), T_REAL);
    if (strcmp(name, "cos") == 0)  return mkE(F1("cos(%s)", x), T_REAL);
    if (strcmp(name, "exp") == 0)  return mkE(F1("exp(%s)", x), T_REAL);
    if (strcmp(name, "ln") == 0)   return mkE(F1("log(%s)", x), T_REAL);
    if (strcmp(name, "round") == 0) return mkE(F1("((int)((%s)<0?(%s)-0.5:(%s)+0.5))", x), T_INT);
    if (strcmp(name, "trunc") == 0) return mkE(F1("((int)(%s))", x), T_INT);
    if (strcmp(name, "odd") == 0)  return mkE(F1("(((%s)&1)!=0)", x), T_BOOL);
    if (strcmp(name, "succ") == 0) return mkE(F1("((%s)+1)", x), etype(e1));
    if (strcmp(name, "pred") == 0) return mkE(F1("((%s)-1)", x), etype(e1));
    if (strcmp(name, "length") == 0) return mkE(F1("((int)strlen(%s))", x), T_INT);
    if (strcmp(name, "upcase") == 0) return mkE(F1("((char)toupper(%s))", x), T_CHR);
    if (strcmp(name, "eof") == 0) return mkE(F1("(pf_eof(%s) != 0)", x), T_BOOL);
    if (strcmp(name, "pos") == 0)  { struct AL *a2 = (struct AL *)a1->next; return mkE(F2("__ppos(%s, %s)", x, etext(a2->e)), T_INT); }
    if (strcmp(name, "copy") == 0) { struct AL *a2 = (struct AL *)a1->next; struct AL *a3 = (struct AL *)a2->next; return mkE(j2("__pcopy(", j4(x, ", ", etext(a2->e), j3(", ", etext(a3->e), ")"))), T_STR); }
    if (strcmp(name, "concat") == 0) { struct AL *a2 = (struct AL *)a1->next; return mkE(F2("__pscat(%s, %s)", x, etext(a2->e)), T_STR); }
    return -1;
}
int emit_fcall(char *name, int args)
{
    int s = std_func(name, args);
    if (s >= 0) return s;
    if (curclass >= 0)    /* unqualified method call with args inside a method */
    {
        int mi = meth_find(curclass, name);
        if (mi >= 0) return mkE(self_call(mi, build_args(name, args, -1)), m_ret[mi]);
    }
    int f = f_find(name);
    return mkE(F2("%s(%s)", cname(name), build_args(name, args, f)), f >= 0 ? f_ret[f] : T_INT);
}

/* qualified method call:  obj.M(args).  Virtual -> dispatch through obj.__vmt;
 * otherwise a direct call to the statically-known implementation. */
int method_call(int base, char *name, int args)
{
    int cls = cls_of_type(etype(base));
    int mi = meth_find(cls, name);
    char *a = build_args(name, args, -1);
    char *self = F1("&(%s)", etext(base));
    if (mi >= 0 && m_virt[mi])
    {
        char *fp = j3("(", j2(vcast(mi), F2("(%s).__vmt[%s]", etext(base), istr(m_slot[mi]))), ")");
        char *call = (a[0] == 0) ? F2("%s(%s)", fp, self) : j2(j4(fp, "(", self, ", "), j2(a, ")"));
        return mkE(call, m_ret[mi]);
    }
    char *mn = (mi >= 0) ? mname(m_cls[mi], name) : j2("m_unknown_", name);
    char *call = (a[0] == 0) ? F2("%s(%s)", mn, self) : j2(j4(mn, "(", self, ", "), j2(a, ")"));
    return mkE(call, mi >= 0 ? m_ret[mi] : T_INT);
}
/* method call on `self` inside a method body (virtual goes through self->__vmt) */
char *self_call(int mi, char *a)
{
    if (m_virt[mi])
    {
        char *fp = j3("(", j2(vcast(mi), F1("self->__vmt[%s]", istr(m_slot[mi]))), ")");
        return (a[0] == 0) ? F1("%s(self)", fp) : j2(j4(fp, "(self, ", a, ")"), "");
    }
    return (a[0] == 0) ? F1("%s(self)", mname(m_cls[mi], m_nm[mi])) : j2(j4(mname(m_cls[mi], m_nm[mi]), "(self, ", a, ")"), "");
}

/* x in [ set elements ] -> a boolean OR of equality/range tests */
int build_in(int xe, int list)
{
    char *x = etext(xe); char *acc = ""; int first = 1, a = list;
    while (a)
    {
        struct AL *n = (struct AL *)a;
        char *test = n->d ? F4("((%s) >= (%s) && (%s) <= (%s))", x, etext(n->e), x, etext(n->w))
                          : F2("((%s) == (%s))", x, etext(n->e));
        acc = first ? test : j3(acc, " || ", test); first = 0;
        a = n->next;
    }
    if (first) acc = "0";   /* empty set */
    return mkE(j3("(", acc, ")"), T_BOOL);
}
/* a set literal as a value -> ps_lit(count, lo1,hi1, lo2,hi2, ...) */
char *build_setval(int list)
{
    int n = 0, a = list; while (a) { n++; a = ((struct AL *)a)->next; }
    char *args = istr(n); a = list;
    while (a) { struct AL *nn = (struct AL *)a; char *lo = etext(nn->e); char *hi = nn->d ? etext(nn->w) : lo; args = j2(args, j4(", ", lo, ", ", hi)); a = nn->next; }
    return F1("ps_lit(%s)", args);
}

void do_assign(int lv, int ev)
{
    if (is_str(etype(lv))) { e(F2("strcpy(%s, %s);\n", etext(lv), etext(ev))); return; }
    e(F2("%s = %s;\n", etext(lv), etext(ev)));
}
void call_noargs(char *name)
{
    if (strcmp(name, "writeln") == 0) { e("printf(\"\\n\");\n"); return; }
    if (strcmp(name, "write") == 0 || strcmp(name, "readln") == 0 || strcmp(name, "read") == 0) return;
    e(F1("%s();\n", cname(name)));
}
void wr_one(struct AL *n)        /* one write argument, honoring :w:d */
{
    int t = etype(n->e); char *x = etext(n->e);
    if (eff(t) == T_REAL)
    {
        if (n->w && n->d) e(j2(F2("printf(\"%%*.*f\", %s, %s, ", etext(n->w), etext(n->d)), j2(x, ");\n")));
        else if (n->w) e(j2(F1("printf(\"%%*g\", %s, ", etext(n->w)), j2(x, ");\n")));
        else e(F1("printf(\"%%g\", %s);\n", x));
    }
    else if (eff(t) == T_INT)
    {
        if (n->w) e(j2(F1("printf(\"%%*d\", %s, ", etext(n->w)), j2(x, ");\n")));
        else e(F1("printf(\"%%d\", %s);\n", x));
    }
    else if (t == T_CHR) e(F1("printf(\"%%c\", %s);\n", x));
    else if (t == T_BOOL) e(F1("printf(\"%%s\", (%s)?\"TRUE\":\"FALSE\");\n", x));
    else e(F1("printf(\"%%s\", %s);\n", x));
}
void emit_call_stmt(char *name, int args)
{
    if (strcmp(name, "assign") == 0)  { struct AL *n = (struct AL *)args; e(F2("%s = pf_assign(%s);\n", etext(n->e), etext(((struct AL *)n->next)->e))); return; }
    if (strcmp(name, "reset") == 0)   { e(F1("pf_reset(%s);\n",   etext(((struct AL *)args)->e))); return; }
    if (strcmp(name, "rewrite") == 0) { e(F1("pf_rewrite(%s);\n", etext(((struct AL *)args)->e))); return; }
    if (strcmp(name, "append") == 0)  { e(F1("pf_append(%s);\n",  etext(((struct AL *)args)->e))); return; }
    if (strcmp(name, "close") == 0)   { e(F1("pf_close(%s);\n",   etext(((struct AL *)args)->e))); return; }
    if (strcmp(name, "writeln") == 0 || strcmp(name, "write") == 0)
    {
        int a = args; int fid = 0;
        if (a && etype(((struct AL *)a)->e) == T_FILE) { fid = ((struct AL *)a)->e; a = ((struct AL *)a)->next; }
        if (fid)
        {
            char *f = etext(fid);
            while (a) { struct AL *n = (struct AL *)a; int t = etype(n->e); char *x = etext(n->e);
                if (eff(t) == T_REAL) e(F2("pf_writer(%s, %s);\n", f, x));
                else if (t == T_CHR) e(F2("pf_writec(%s, %s);\n", f, x));
                else if (eff(t) == T_INT) e(F2("pf_writei(%s, %s);\n", f, x));
                else if (t == T_BOOL) e(j2(F1("pf_writes(%s, ", f), F1("(%s)?\"TRUE\":\"FALSE\");\n", x)));
                else e(F2("pf_writes(%s, %s);\n", f, x));
                a = n->next; }
            if (strcmp(name, "writeln") == 0) e(F1("pf_writeln(%s);\n", f));
            return;
        }
        while (a) { wr_one((struct AL *)a); a = ((struct AL *)a)->next; }
        if (strcmp(name, "writeln") == 0) e("printf(\"\\n\");\n");
        return;
    }
    if (strcmp(name, "readln") == 0 || strcmp(name, "read") == 0)
    {
        int a = args;
        if (a && etype(((struct AL *)a)->e) == T_FILE)
        {
            char *f = etext(((struct AL *)a)->e); a = ((struct AL *)a)->next;
            while (a) { struct AL *n = (struct AL *)a; int t = etype(n->e); char *x = etext(n->e);
                if (is_str(t)) e(F2("strcpy(%s, (char*)pf_readln(%s));\n", x, f));
                else if (eff(t) == T_REAL) e(F2("%s = atof((char*)pf_readln(%s));\n", x, f));
                else e(F2("%s = atoi((char*)pf_readln(%s));\n", x, f));
                a = n->next; }
            return;
        }
        while (a) { struct AL *n = (struct AL *)a; int t = etype(n->e); char *x = etext(n->e);
            if (is_str(t)) e(F1("scanf(\"%%255s\", %s);\n", x));
            else { char *f = eff(t) == T_REAL ? "%lf" : (t == T_CHR ? " %c" : "%d"); e(F2("scanf(\"%s\", &(%s));\n", f, x)); }
            a = n->next; }
        return;
    }
    if (strcmp(name, "inc") == 0 || strcmp(name, "dec") == 0)
    {
        struct AL *n = (struct AL *)args; char *x = etext(n->e); char *op = strcmp(name, "inc") == 0 ? "+" : "-";
        if (n->next) e(j2(F2("%s = %s ", x, x), j4(op, " ", etext(((struct AL *)n->next)->e), ";\n")));
        else e(j2(F2("%s = %s ", x, x), j3(op, " 1", ";\n")));
        return;
    }
    if (strcmp(name, "new") == 0)  { struct AL *n = (struct AL *)args; int el = ty_a[etype(n->e)]; e(F2("%s = malloc(sizeof(%s));\n", etext(n->e), cscalar(el))); return; }
    if (strcmp(name, "dispose") == 0) { struct AL *n = (struct AL *)args; e(F1("free(%s);\n", etext(n->e))); return; }
    if (strcmp(name, "halt") == 0) { struct AL *n = (struct AL *)args; e(F1("exit(%s);\n", n ? etext(n->e) : (char *)"0")); return; }
    int f = f_find(name);
    e(F2("%s(%s);\n", cname(name), build_args(name, args, f)));
}

/* a record/array/string variable declared inside a record (field decl) */
void add_fields(char *list, int type)
{
    char buf[2048]; strcpy(buf, list); int i = 0, st = 0;
    while (1)
    {
        if (buf[i] == ',' || buf[i] == 0)
        {
            int end = buf[i]; buf[i] = 0;
            rf_name[nrf] = (char *)strdup((int)(buf + st)); rf_type[nrf] = type; nrf++;
            if (end == 0) break; st = i + 1;
        }
        i++;
    }
}
%}

%token KPROGRAM KVAR KCONST KTYPE KBEGIN KEND KIF KTHEN KELSE KWHILE KDO
%token KFOR KTO KDOWNTO KREPEAT KUNTIL KCASE KOF KPROCEDURE KFUNCTION
%token KAND KOR KNOT KDIV KMOD KTRUE KFALSE KARRAY KRECORD KNIL KGOTO KLABEL KWITH KFORWARD KIN
%token KOBJECT KCONSTRUCTOR KDESTRUCTOR KVIRTUAL KSET
%token IDENT INTLIT REALLIT STRLIT CHARLIT ASSIGN DOTDOT LE GE NE

%nonassoc '=' NE '<' '>' LE GE KIN
%left '+' '-' KOR
%left '*' '/' KDIV KMOD KAND
%right KNOT
%right UMINUS

%start program
%%
program   : KPROGRAM IDENT ';' phead decl_list mainhdr compound '.'  { e("\nreturn 0;\n}\n"); } ;
phead     : /* empty */  { e("char *__pscat(char*a,char*b){char*r=(char*)malloc(strlen(a)+strlen(b)+1);strcpy(r,a);strcat(r,b);return r;}\n");
                           e("char *__pcopy(char*s,int i,int n){char*r=(char*)malloc(n+1);int k=0;int L=strlen(s);while(k<n&&(i-1+k)<L){r[k]=s[i-1+k];k++;}r[k]=0;return r;}\n");
                           e("int __ppos(char*sub,char*s){int i=0;int sl=strlen(s);int bl=strlen(sub);while(i+bl<=sl){int j=0;while(j<bl&&s[i+j]==sub[j])j++;if(j==bl)return i+1;i++;}return 0;}\n"); } ;
mainhdr   : /* empty */  { e("\nint main(void){\n"); } ;

decl_list : /* empty */ | decl_list decl ;
decl      : const_sect | var_sect | type_sect | label_sect | proc_decl | func_decl ;

label_sect : KLABEL labels ';' ;
labels     : INTLIT | labels ',' INTLIT ;

const_sect : KCONST const_defs ;
const_defs : const_def | const_defs const_def ;
const_def  : IDENT '=' INTLIT ';'   { sym_add((char *)$1, K_CONST, T_INT);  e(F2("int %s = %s;\n",    cname((char *)$1), istr($3))); }
           | IDENT '=' REALLIT ';'  { sym_add((char *)$1, K_CONST, T_REAL); e(F2("double %s = %s;\n", cname((char *)$1), (char *)$3)); }
           | IDENT '=' STRLIT ';'   { sym_add((char *)$1, K_CONST, T_STR);  e(F2("char *%s = %s;\n",  cname((char *)$1), cstrlit((char *)$3))); }
           | IDENT '=' CHARLIT ';'  { sym_add((char *)$1, K_CONST, T_CHR);  e(F2("char %s = %s;\n",   cname((char *)$1), cchrlit((char *)$3))); }
           ;

type_sect  : KTYPE type_defs ;
type_defs  : type_def | type_defs type_def ;
type_def   : tdname '=' typ ';'  { tn_name[ntn] = (char *)$1; tn_type[ntn] = $3; ntn++; } ;
tdname     : IDENT  { pending_typename = (char *)$1; $$ = $1; } ;

var_sect   : KVAR var_decls ;
var_decls  : var_decl | var_decls var_decl ;
var_decl   : id_list ':' typ ';'  { decl_vars((char *)$1, $3); } ;

id_list    : IDENT                 { $$ = $1; }
           | id_list ',' IDENT     { $$ = (int)j3((char *)$1, ",", (char *)$3); } ;

typ        : IDENT                                   { $$ = name_type((char *)$1); }
           | '^' IDENT                               { $$ = mkty(TK_PTR, name_type((char *)$2), 0, 0); }
           | KARRAY '[' ranges ']' KOF typ           { $$ = build_array($3, $6); }
           | KRECORD rec_open field_list KEND        { $$ = close_record(); }
           | objtype                                 { $$ = $1; }
           | '(' id_list ')'                         { $$ = build_enum((char *)$2); }
           | KSET KOF typ                            { $$ = T_SET; }
           | constval DOTDOT constval                { $$ = mkty(TK_SUB, T_INT, $1, $3); }
           ;

objtype    : objhead members KEND  { $$ = obj_close(); } ;
objhead    : KOBJECT                { obj_begin(-1); }
           | KOBJECT '(' IDENT ')'  { obj_begin(cls_find((char *)$3)); } ;
members    : /* empty */ | members member_item ;
member_item: id_list ':' typ ';'          { add_fields((char *)$1, $3); }
           | method_head ';'
           | method_head ';' KVIRTUAL ';'  { m_virt[nm - 1] = 1; assign_slot(nm - 1); } ;
method_head: KPROCEDURE IDENT params       { reg_method((char *)$2, T_VOID, g_psig); }
           | KFUNCTION IDENT params ':' typ { reg_method((char *)$2, $5, g_psig); }
           | KCONSTRUCTOR IDENT params     { reg_method((char *)$2, T_VOID, g_psig); m_ctor[nm - 1] = 1; }
           | KDESTRUCTOR IDENT params      { reg_method((char *)$2, T_VOID, g_psig); } ;
constval   : INTLIT   { $$ = $1; }
           | CHARLIT  { $$ = ((char *)$1)[0]; }
           | '-' INTLIT { $$ = -$2; } ;

ranges     : range            { $$ = $1; }
           | ranges ',' range { $$ = (int)j3((char *)$1, "|", (char *)$3); } ;   /* dims joined by | */
range      : constval DOTDOT constval  { $$ = (int)j3(istr($1), ":", istr($3)); } ;

rec_open   : /* empty */  { rec_push(); } ;
field_list : field_decl | field_list ';' field_decl | field_list ';' ;
field_decl : id_list ':' typ  { add_fields((char *)$1, $3); } ;

proc_decl  : proc_sig local_decls compound ';'  { e("}\n"); nsym = saved_nsym; curfunc = 0; }
           | proc_sig KFORWARD ';'              { e("}\n"); nsym = saved_nsym; curfunc = 0; }
           | meth_body ;
meth_body  : meth_psig local_decls compound ';'  { if (curfunc) e("return __result;\n}\n"); else e("}\n"); nsym = saved_nsym; curfunc = 0; curclass = -1; } ;
meth_psig  : KPROCEDURE IDENT '.' IDENT pscope params ';'          { begin_method((char *)$2, (char *)$4, T_VOID, (char *)$6); }
           | KFUNCTION IDENT '.' IDENT pscope params ':' typ ';'   { begin_method((char *)$2, (char *)$4, $8, (char *)$6); }
           | KCONSTRUCTOR IDENT '.' IDENT pscope params ';'        { begin_method((char *)$2, (char *)$4, T_VOID, (char *)$6); }
           | KDESTRUCTOR IDENT '.' IDENT pscope params ';'         { begin_method((char *)$2, (char *)$4, T_VOID, (char *)$6); } ;
proc_sig   : KPROCEDURE IDENT pscope params ';'
             { reg_func((char *)$2, T_VOID); e(F2("void %s(%s){\n", cname((char *)$2), (char *)$4)); curfunc = 0; } ;

func_decl  : func_sig local_decls compound ';'  { e("return __result;\n}\n"); nsym = saved_nsym; curfunc = 0; } ;
func_sig   : KFUNCTION IDENT pscope params ':' typ ';'
             { reg_func((char *)$2, $6);
               e(j4(cscalar($6), " ", cname((char *)$2), F1("(%s){\n", (char *)$4)));
               e(j3(cscalar($6), " __result;\n", "")); curfunc = (char *)$2; cur_ret = $6; } ;

pscope     : /* empty */  { saved_nsym = nsym; g_np = 0; } ;

local_decls: /* empty */ | local_decls local_one ;
local_one  : const_sect | var_sect | type_sect | label_sect ;

params     : /* empty */          { $$ = (int)""; g_psig = ""; g_np = 0; }
           | lparen pgroups ')'   { $$ = $2; } ;
lparen     : '('                  { g_psig = ""; g_np = 0; } ;
pgroups    : pgroup               { $$ = $1; }
           | pgroups ';' pgroup   { $$ = (int)j3((char *)$1, ", ", (char *)$3); } ;
pgroup     : id_list ':' typ        { $$ = (int)param_text((char *)$1, $3, 0); }
           | KVAR id_list ':' typ   { $$ = (int)param_text((char *)$2, $4, 1); } ;

compound   : cbeg stmt_list KEND  { e("}\n"); } ;
cbeg       : KBEGIN  { e("{\n"); } ;

stmt_list  : stmt | stmt_list ';' stmt ;
stmt       : /* empty */ | smark real_stmt ;
smark      : /* empty */  { line(tokln); } ;

real_stmt  : assign | proc_call | if_stmt | while_stmt | for_stmt | repeat_stmt | case_stmt | with_stmt | compound
           | KGOTO INTLIT     { e(F1("goto L%s;\n", istr($2))); }
           | labelpfx real_stmt ;
labelpfx   : INTLIT ':'  { e(F1("L%s:\n", istr($1))); } ;

assign     : lvalue ASSIGN expr             { do_assign($1, $3); }
           | lvalue ASSIGN '[' setlist ']'  { e(F2("%s = %s;\n", etext($1), build_setval($4))); } ;

lvalue     : IDENT                  { $$ = emit_ident((char *)$1); }
           | lvalue '[' idxlist ']' { $$ = fold_index($1, $3); }
           | lvalue '.' IDENT       { $$ = do_field($1, (char *)$3); }
           | lvalue '^'             { $$ = do_deref($1); } ;
idxlist    : expr                   { $$ = mkAL($1, 0, 0, 0); }
           | idxlist ',' expr       { $$ = append_AL($1, mkAL($3, 0, 0, 0)); } ;

proc_call  : IDENT                       { call_noargs((char *)$1); }
           | IDENT '(' arg_list ')'      { emit_call_stmt((char *)$1, $3); }
           | lvalue '.' IDENT '(' arg_list ')'  { int r = method_call($1, (char *)$3, $5); e(etext(r)); e(";\n"); } ;

if_stmt    : ifhead thenpart | ifhead thenpart elsepart ;
ifhead     : KIF expr KTHEN  { e(F1("if (%s) {\n", etext($2))); } ;
thenpart   : stmt  { e("}\n"); } ;
elsepart   : elsehead stmt  { e("}\n"); } ;
elsehead   : KELSE  { e("else {\n"); } ;

while_stmt : whilehead stmt  { e("}\n"); } ;
whilehead  : KWHILE expr KDO  { e(F1("while (%s) {\n", etext($2))); } ;

for_stmt   : forup stmt    { e("}\n"); } | fordown stmt  { e("}\n"); } ;
forup      : KFOR IDENT ASSIGN expr KTO expr KDO     { char *v = cname((char *)$2); e("for ("); e(v); e(" = "); e(etext($4)); e("; "); e(v); e(" <= "); e(etext($6)); e("; "); e(v); e("++) {\n"); } ;
fordown    : KFOR IDENT ASSIGN expr KDOWNTO expr KDO { char *v = cname((char *)$2); e("for ("); e(v); e(" = "); e(etext($4)); e("; "); e(v); e(" >= "); e(etext($6)); e("; "); e(v); e("--) {\n"); } ;

repeat_stmt: rephead stmt_list KUNTIL expr  { e(F1("} while (!(%s));\n", etext($4))); } ;
rephead    : KREPEAT  { e("do {\n"); } ;

with_stmt  : withhead stmt  { e("}\n"); nwith--; } ;
withhead   : KWITH lvalue KDO  { e("{\n"); with_rec[nwith] = etext($2); with_ty[nwith] = etype($2); nwith++; } ;

case_stmt  : casehead case_arms caseend ;
casehead   : KCASE expr KOF  { e(F1("switch (%s) {\n", etext($2))); } ;
case_arms  : case_arm | case_arms ';' case_arm | case_arms ';' ;
case_arm   : caselabs stmt  { e("break;\n"); } ;
caselabs   : labset ':' ;
labset     : case_one | labset ',' case_one ;
case_one   : constval                  { e(F1("case %s:\n", istr($1))); }
           | constval DOTDOT constval   { int v; for (v = $1; v <= $3; v++) e(F1("case %s:\n", istr(v))); } ;
caseend    : KEND  { e("}\n"); } | caseelse stmt_list KEND  { e("}\n"); } ;
caseelse   : KELSE  { e("default:\n"); } ;

arg_list   : /* empty */  { $$ = 0; } | arg_ne { $$ = $1; } ;
arg_ne     : warg             { $$ = $1; } | arg_ne ',' warg { $$ = append_AL($1, $3); } ;
warg       : expr                       { $$ = mkAL($1, 0, 0, 0); }
           | expr ':' expr              { $$ = mkAL($1, $3, 0, 0); }
           | expr ':' expr ':' expr     { $$ = mkAL($1, $3, $5, 0); } ;

expr : expr '=' expr   { $$ = rel($1, "==", "==", $3); }
     | expr NE expr    { $$ = rel($1, "!=", "!=", $3); }
     | expr '<' expr   { $$ = rel($1, "<", "<", $3); }
     | expr '>' expr   { $$ = rel($1, ">", ">", $3); }
     | expr LE expr    { $$ = rel($1, "<=", "<=", $3); }
     | expr GE expr    { $$ = rel($1, ">=", ">=", $3); }
     | expr '+' expr   { if (is_str(etype($1))) $$ = mkE(F2("__pscat(%s, %s)", etext($1), etext($3)), T_STR); else if (etype($1) == T_SET) $$ = mkE(F2("ps_or(%s, %s)", etext($1), etext($3)), T_SET); else $$ = arith($1, "+", $3); }
     | expr '-' expr   { if (etype($1) == T_SET) $$ = mkE(F2("ps_sub(%s, %s)", etext($1), etext($3)), T_SET); else $$ = arith($1, "-", $3); }
     | expr KOR expr   { $$ = logic($1, "||", "|", $3); }
     | expr '*' expr   { if (etype($1) == T_SET) $$ = mkE(F2("ps_and(%s, %s)", etext($1), etext($3)), T_SET); else $$ = arith($1, "*", $3); }
     | expr '/' expr   { $$ = mkE(F2("((double)(%s)/(double)(%s))", etext($1), etext($3)), T_REAL); }
     | expr KDIV expr  { $$ = bin($1, "/", $3, T_INT); }
     | expr KMOD expr  { $$ = bin($1, "%", $3, T_INT); }
     | expr KAND expr  { $$ = logic($1, "&&", "&", $3); }
     | KNOT expr       { int t = eff(etype($2)); $$ = mkE(F1(t == T_BOOL ? "(!%s)" : "(~%s)", etext($2)), etype($2)); }
     | '-' expr %prec UMINUS  { $$ = mkE(F1("(-%s)", etext($2)), etype($2)); }
     | '+' expr %prec UMINUS  { $$ = $2; }
     | '(' expr ')'    { $$ = mkE(F1("(%s)", etext($2)), etype($2)); }
     | '@' lvalue %prec UMINUS  { $$ = mkE(F1("(&%s)", etext($2)), mkty(TK_PTR, etype($2), 0, 0)); }
     | INTLIT          { $$ = mkE(istr($1), T_INT); }
     | REALLIT         { $$ = mkE((char *)$1, T_REAL); }
     | STRLIT          { $$ = mkE(cstrlit((char *)$1), T_STR); }
     | CHARLIT         { $$ = mkE(cchrlit((char *)$1), T_CHR); }
     | KTRUE           { $$ = mkE("1", T_BOOL); }
     | KFALSE          { $$ = mkE("0", T_BOOL); }
     | KNIL            { $$ = mkE("0", T_INT); }
     | expr KIN '[' setlist ']' { $$ = build_in($1, $4); }
     | expr KIN expr            { $$ = mkE(F2("(ps_in(%s, %s) != 0)", etext($3), etext($1)), T_BOOL); }
     | lvalue          { $$ = $1; }
     | IDENT '(' arg_list ')'   { $$ = emit_fcall((char *)$1, $3); }
     | lvalue '.' IDENT '(' arg_list ')'  { $$ = method_call($1, (char *)$3, $5); }
     ;
setlist  : setel              { $$ = $1; }
         | setlist ',' setel  { $$ = append_AL($1, $3); } ;
setel    : expr               { $$ = mkAL($1, 0, 0, 0); }
         | expr DOTDOT expr   { $$ = mkAL($1, $3, 1, 0); } ;
%%

/* ---- helpers that need the grammar's types (defined after %%) ---- */
int fold_index(int base, int list) { int a = list; while (a) { struct AL *n = (struct AL *)a; base = do_index(base, n->e); a = n->next; } return base; }

void obj_begin(int parent)
{
    rec_push();
    if (parent >= 0) { int rt = cls_rtype[parent]; int i; for (i = ty_a[rt]; i < ty_a[rt] + ty_b[rt]; i++) { rf_name[nrf] = rf_name[i]; rf_type[nrf] = rf_type[i]; nrf++; } }
    cls_name[ncls] = pending_typename; cls_parent[ncls] = parent;
    cls_nvirt[ncls] = (parent >= 0) ? cls_nvirt[parent] : 0;   /* inherit the parent's vtable slots */
    cls_rtype[ncls] = 0; ncls++;
}
int obj_close(void)
{
    int cls = ncls - 1;
    int start = rec_stack[--rec_sp]; int n = nrf - start; int sid = n_struct++;
    int t = mkty(TK_RECORD, start, n, sid); cls_rtype[cls] = t;
    /* struct: a vtable pointer at offset 0 (prefix-compatible across inheritance), then fields */
    e("typedef struct { int* __vmt; ");
    int i; for (i = start; i < start + n; i++) { e(decl_one(rf_type[i], cname(rf_name[i]))); e("; "); }
    e(j3("} R", istr(sid), ";\n"));
    /* per-class vtable: slot -> most-derived implementation */
    int nv = cls_nvirt[cls];
    if (nv > 0)
    {
        e(j3("int VMT_", cls_name[cls], "[] = { "));
        int k; for (k = 0; k < nv; k++) { int mi = find_slot_impl(cls, k); if (k) e(", "); e(mi >= 0 ? j2("(int)", mname(m_cls[mi], m_nm[mi])) : (char *)"0"); }
        e(" };\n");
    }
    return t;
}
void begin_method(char *clsn, char *methn, int ret, char *params)
{
    int cls = cls_find(clsn); curclass = cls;
    char *self = j2(cscalar(cls_rtype[cls]), " *self");
    e(j4(cscalar(ret), " ", mname(cls, methn), "("));
    if (params[0]) e(j3(self, ", ", params)); else e(self);
    e("){\n");
    if (ret != T_VOID) { e(j3(cscalar(ret), " __result;\n", "")); curfunc = methn; cur_ret = ret; }
    else curfunc = 0;
    int mi = meth_find(cls, methn);   /* a constructor installs the vtable pointer */
    if (mi >= 0 && m_ctor[mi] && cls_nvirt[cls] > 0) e(j3("self->__vmt = VMT_", cls_name[cls], ";\n"));
}

int rec_stack[64]; int rec_sp;     /* nested record field-start markers */
void rec_push(void) { rec_stack[rec_sp++] = nrf; }
int close_record(void)
{
    int start = rec_stack[--rec_sp]; int n = nrf - start; int sid = n_struct++;
    int t = mkty(TK_RECORD, start, n, sid);
    /* emit the C struct now (types come before use in Pascal) */
    e(j3("typedef struct { ", "", ""));
    int i; for (i = start; i < start + n; i++) { e(decl_one(rf_type[i], cname(rf_name[i]))); e("; "); }
    e(j3("} R", istr(sid), ";\n"));
    return t;
}
int build_array(char *spec, int elem)
{
    /* spec: "lo:hi" dims joined by '|', innermost last; build nested array types */
    char buf[512]; strcpy(buf, spec);
    /* split into dims */
    int los[16]; int his[16]; int nd = 0;
    int i = 0, st = 0;
    while (1)
    {
        if (buf[i] == '|' || buf[i] == 0)
        {
            int end = buf[i]; buf[i] = 0; char *d = buf + st;
            int c = 0; while (d[c] && d[c] != ':') c++; d[c] = 0;
            los[nd] = atoi((int)d); his[nd] = atoi((int)(d + c + 1)); nd++;
            if (end == 0) break; st = i + 1;
        }
        i++;
    }
    int t = elem; int k;
    for (k = nd - 1; k >= 0; k--) t = mkty(TK_ARRAY, t, los[k], his[k]);
    return t;
}
int build_enum(char *list)
{
    char buf[1024]; strcpy(buf, list); int i = 0, st = 0, v = 0; int first = nty;
    int et = mkty(TK_ENUM, 0, 0, 0);
    while (1)
    {
        if (buf[i] == ',' || buf[i] == 0)
        {
            int end = buf[i]; buf[i] = 0; char *nm = buf + st;
            sym_add((char *)strdup((int)nm), K_CONST, et);
            e(F2("int %s = %s;\n", cname(nm), istr(v)));
            v++;
            if (end == 0) break; st = i + 1;
        }
        i++;
    }
    ty_b[et] = v; return et;
}

void strip_comments(char *s)
{
    int i = 0;
    while (s[i])
    {
        if (s[i] == '\'') { i++; while (s[i] && !(s[i] == '\'' && s[i + 1] != '\'')) { if (s[i] == '\'' && s[i + 1] == '\'') i++; i++; } if (s[i]) i++; continue; }
        if (s[i] == '{') { while (s[i] && s[i] != '}') { if (s[i] != '\n') s[i] = ' '; i++; } if (s[i]) s[i] = ' '; i++; continue; }
        if (s[i] == '(' && s[i + 1] == '*') { s[i] = ' '; s[i + 1] = ' '; i += 2; while (s[i] && !(s[i] == '*' && s[i + 1] == ')')) { if (s[i] != '\n') s[i] = ' '; i++; } if (s[i]) { s[i] = ' '; s[i + 1] = ' '; i += 2; } continue; }
        if (s[i] == '/' && s[i + 1] == '/') { while (s[i] && s[i] != '\n') { s[i] = ' '; i++; } continue; }
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
void yyerror(char *m) { printf((int)"pascal: %s near line %d\n", (int)m, pline); }

/* ---- units (whole-program inlining): `uses Foo` inlines Foo.pas's decls ---- */
int lower1(int c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }
int idchar(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'; }
int kw_at(char *s, int i, char *kw)   /* whole-word, case-insensitive */
{
    if (i > 0 && idchar(s[i - 1])) return 0;
    int k = 0; while (kw[k]) { if (lower1(s[i + k]) != kw[k]) return 0; k++; }
    return idchar(s[i + k]) ? 0 : 1;
}
int find_kw(char *s, char *kw, int from) { int i = from; while (s[i]) { if (kw_at(s, i, kw)) return i; i++; } return -1; }
char *substr(char *s, int a, int b) { char *r = (char *)malloc(b - a + 1); int k; for (k = a; k < b; k++) r[k - a] = s[k]; r[b - a] = 0; return r; }
void blank_end_dot(char *s)           /* blank the final "end ." */
{
    int i = strlen(s) - 1; while (i >= 0 && s[i] != '.') i--;
    if (i < 0) return; s[i] = ' '; i--;
    while (i >= 0 && (s[i] == ' ' || s[i] == '\n' || s[i] == '\t' || s[i] == '\r')) i--;
    if (i >= 2 && lower1(s[i]) == 'd' && lower1(s[i - 1]) == 'n' && lower1(s[i - 2]) == 'e') { s[i] = ' '; s[i - 1] = ' '; s[i - 2] = ' '; }
}
char *strip_sigs(char *s)             /* blank interface procedure/function signatures */
{
    char *r = (char *)strdup((int)s); int i = 0;
    while (r[i])
    {
        if (kw_at(r, i, "procedure") || kw_at(r, i, "function") || kw_at(r, i, "constructor") || kw_at(r, i, "destructor"))
        {
            int depth = 0;
            while (r[i]) { if (r[i] == '(') depth++; else if (r[i] == ')') depth--; else if (r[i] == ';' && depth <= 0) { r[i] = ' '; i++; break; } r[i] = ' '; i++; }
        }
        else i++;
    }
    return r;
}
char *extract_unit(char *src)         /* return the inlinable declaration text of a unit */
{
    int n = strlen(src);
    int ifc = find_kw(src, "interface", 0);
    int impl = find_kw(src, "implementation", 0);
    if (ifc >= 0 && impl >= 0)
    {
        char *iface = strip_sigs(substr(src, ifc + 9, impl));
        char *imp = substr(src, impl + 14, n);
        blank_end_dot(imp);
        return j2(iface, imp);
    }
    int semi = 0; while (src[semi] && src[semi] != ';') semi++;   /* flat unit: after "unit Name;" */
    char *body = substr(src, semi + 1, n);
    blank_end_dot(body);
    return body;
}

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: pascal <file.pas> [-o <out.exe>]\n"); return 1; }
    char *in = (char *)argv[1];
    char *o = 0; int i;
    for (i = 2; i < argc; i++) if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) { o = (char *)argv[i + 1]; i++; }

    char outexe[1024]; char cpath[1024];
    if (o) strcpy(outexe, o); else { strcpy(outexe, in); setext(outexe, "exe"); }
    strcpy(cpath, outexe); setext(cpath, "c");

    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"pascal: cannot read %s\n", (int)in); return 1; }
    strip_comments(src);

    /* units: `uses A, B;` inlines each unit's declarations before the program body */
    int up = find_kw(src, "uses", 0);
    if (up >= 0)
    {
        char dir[1024]; strcpy(dir, in); int d = strlen(dir) - 1; while (d >= 0 && dir[d] != '/' && dir[d] != '\\') d--; dir[d + 1] = 0;
        int ue = up; while (src[ue] && src[ue] != ';') ue++;
        char *names = substr(src, up + 4, ue);
        char *udecls = "";
        int i = 0, st = 0;
        while (1)
        {
            if (names[i] == ',' || names[i] == 0)
            {
                int end = names[i]; names[i] = 0;
                char nm[256]; int j = 0, k = st; while (k < i && (names[k] == ' ' || names[k] == '\t' || names[k] == '\n')) k++;
                while (k < i && names[k] != ' ' && names[k] != '\t' && names[k] != '\n') nm[j++] = names[k++]; nm[j] = 0;
                if (j > 0)
                {
                    char path[1100]; sprintf((int)path, (int)"%s%s.pas", (int)dir, (int)nm);
                    char *us = (char *)rt_slurp((int)path);
                    if (us == 0) { printf((int)"pascal: cannot find unit %s (%s)\n", (int)nm, (int)path); return 1; }
                    strip_comments(us);
                    udecls = j2(udecls, extract_unit(us));
                }
                if (end == 0) break; st = i + 1;
            }
            i++;
        }
        int k2; for (k2 = up; k2 <= ue; k2++) src[k2] = ' ';     /* remove the uses clause */
        int ph = 0; while (src[ph] && src[ph] != ';') ph++;       /* after "program X;" */
        src = j3(substr(src, 0, ph + 1), udecls, src + ph + 1);
    }
    pasfile = in;
    curclass = -1; g_psig = "";
    nty = 0; int rsv; for (rsv = 0; rsv <= T_SET; rsv++) mkty(0, 0, 0, 0);   /* reserve base-type indices 0..7 */
    ty_kind[T_INT] = T_INT; ty_kind[T_REAL] = T_REAL; ty_kind[T_CHR] = T_CHR; ty_kind[T_BOOL] = T_BOOL; ty_kind[T_STR] = T_STR; ty_kind[T_FILE] = T_FILE; ty_kind[T_SET] = T_SET;

    out = fopen((int)cpath, (int)"w");
    if (out == 0) { printf((int)"pascal: cannot write %s\n", (int)cpath); return 1; }
    yy_scan_string((int)src);
    yyparse();
    fclose(out);

    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; char icon[1100]; sprintf((int)icon, (int)"%s\\icons\\pascal.png", (int)repo);
    av[0] = (int)cc; av[1] = (int)cpath; av[2] = (int)"-o"; av[3] = (int)outexe; av[4] = (int)"--exe"; av[5] = (int)"--icon"; av[6] = (int)icon;
    int rc = sh_run((int)av, 7);
    if (rc == 0) printf((int)"pascal: %s -> %s\n", (int)in, (int)outexe);
    else printf((int)"pascal: cc failed (%d)\n", rc);
    return rc;
}
