%{
/* Forth -> C compiler (yacc). Each `: word ... ;` becomes a real C function
 * (w_<name>) that cc lowers to an IL method -- a DIRECT translation, no inner
 * interpreter / threaded code. The data stack is a .NET Stack<object> living in
 * CRuntime (f_* primitives), so any cell type (int/double/string) can be pushed.
 * Control words map to C control flow. Top-level words run in main(); definitions
 * emit straight to the file. */

int out;                 /* output FILE* (int handle) */
char *forthfile;
int g_indef;             /* inside a : ... ; definition? */
char *mainbuf;           /* top-level words, wrapped in main() at the end */
int g_loopctr; int g_loopstk[64]; int g_loopn;   /* DO/LOOP nesting -> unique C loop vars */
int g_cellctr;           /* VARIABLE cell index allocator */

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 8); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 8); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
char *uc(char *s) { char *r = (char *)strdup((int)s); int i = 0; while (r[i]) { if (r[i] >= 'a' && r[i] <= 'z') r[i] = r[i] - 32; i++; } return r; }

void ef(char *s) { fputs((int)s, out); }              /* always to file (definitions) */
void e(char *s) { if (g_indef) ef(s); else { if (mainbuf == 0) mainbuf = ""; mainbuf = j2(mainbuf, s); } }

/* a C string literal from raw text (escape \ and ") */
char *cstr(char *s)
{
    char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"';
    while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; r[j++] = s[i++]; }
    r[j++] = '"'; r[j] = 0; return r;
}

/* a Forth word name -> a C identifier (lowercase alnum/_, others -> _HH hex) */
char *mangle(char *w)
{
    char *r = (char *)malloc(strlen(w) * 3 + 4); int i = 0, j = 0;
    while (w[i])
    {
        char c = w[i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_') r[j++] = c;
        else if (c >= 'A' && c <= 'Z') r[j++] = c + 32;
        else { int hi = (c >> 4) & 15, lo = c & 15; r[j++] = '_'; r[j++] = hi < 10 ? '0' + hi : 'a' + hi - 10; r[j++] = lo < 10 ? '0' + lo : 'a' + lo - 10; }
        i++;
    }
    r[j] = 0; return r;
}

/* emit one (non-literal) word: a primitive's inline C, or a call to a user word */
void emit_word(char *w)
{
    char *u = uc(w);
    if (strcmp(u, "+") == 0) { e("f_add();\n"); return; }
    if (strcmp(u, "-") == 0) { e("f_sub();\n"); return; }
    if (strcmp(u, "*") == 0) { e("f_mul();\n"); return; }
    if (strcmp(u, "/") == 0) { e("f_div();\n"); return; }
    if (strcmp(u, "MOD") == 0) { e("f_mod();\n"); return; }
    if (strcmp(u, "NEGATE") == 0) { e("f_negate();\n"); return; }
    if (strcmp(u, "ABS") == 0) { e("f_abs();\n"); return; }
    if (strcmp(u, "MIN") == 0) { e("f_min();\n"); return; }
    if (strcmp(u, "MAX") == 0) { e("f_max();\n"); return; }
    if (strcmp(u, "1+") == 0) { e("f_pushi(1); f_add();\n"); return; }
    if (strcmp(u, "1-") == 0) { e("f_pushi(1); f_sub();\n"); return; }
    if (strcmp(u, "2*") == 0) { e("f_pushi(2); f_mul();\n"); return; }
    if (strcmp(u, "2/") == 0) { e("f_pushi(2); f_div();\n"); return; }
    if (strcmp(u, "DUP") == 0) { e("f_dup();\n"); return; }
    if (strcmp(u, "DROP") == 0) { e("f_drop();\n"); return; }
    if (strcmp(u, "SWAP") == 0) { e("f_swap();\n"); return; }
    if (strcmp(u, "OVER") == 0) { e("f_over();\n"); return; }
    if (strcmp(u, "ROT") == 0) { e("f_rot();\n"); return; }
    if (strcmp(u, "?DUP") == 0) { e("f_qdup();\n"); return; }
    if (strcmp(u, "NIP") == 0) { e("f_nip();\n"); return; }
    if (strcmp(u, "TUCK") == 0) { e("f_tuck();\n"); return; }
    if (strcmp(u, "2DUP") == 0) { e("f_2dup();\n"); return; }
    if (strcmp(u, "2DROP") == 0) { e("f_2drop();\n"); return; }
    if (strcmp(u, "DEPTH") == 0) { e("f_depth();\n"); return; }
    if (strcmp(u, "=") == 0) { e("f_eq();\n"); return; }
    if (strcmp(u, "<>") == 0) { e("f_ne();\n"); return; }
    if (strcmp(u, "<") == 0) { e("f_lt();\n"); return; }
    if (strcmp(u, ">") == 0) { e("f_gt();\n"); return; }
    if (strcmp(u, "<=") == 0) { e("f_le();\n"); return; }
    if (strcmp(u, ">=") == 0) { e("f_ge();\n"); return; }
    if (strcmp(u, "0=") == 0) { e("f_0eq();\n"); return; }
    if (strcmp(u, "0<") == 0) { e("f_0lt();\n"); return; }
    if (strcmp(u, "0>") == 0) { e("f_0gt();\n"); return; }
    if (strcmp(u, "AND") == 0) { e("f_and();\n"); return; }
    if (strcmp(u, "OR") == 0) { e("f_or();\n"); return; }
    if (strcmp(u, "XOR") == 0) { e("f_xor();\n"); return; }
    if (strcmp(u, "INVERT") == 0) { e("f_invert();\n"); return; }
    if (strcmp(u, ".") == 0) { e("f_dot();\n"); return; }
    if (strcmp(u, ".S") == 0) { e("f_dots();\n"); return; }
    if (strcmp(u, "EMIT") == 0) { e("f_emit();\n"); return; }
    if (strcmp(u, "CR") == 0) { e("f_cr();\n"); return; }
    if (strcmp(u, "SPACE") == 0) { e("f_space();\n"); return; }
    if (strcmp(u, "SPACES") == 0) { e("f_spaces();\n"); return; }
    if (strcmp(u, "TYPE") == 0) { e("f_type();\n"); return; }
    if (strcmp(u, "@") == 0) { e("f_fetch();\n"); return; }
    if (strcmp(u, "!") == 0) { e("f_store();\n"); return; }
    if (strcmp(u, "I") == 0) { e(F1("f_pushi(__i%s);\n", istr(g_loopstk[g_loopn - 1]))); return; }
    if (strcmp(u, "J") == 0) { e(F1("f_pushi(__i%s);\n", istr(g_loopstk[g_loopn - 2]))); return; }
    e(F1("w_%s();\n", mangle(w)));   /* user word */
}

int yylex();
void yyerror(char *m);
%}
%token INT FLOAT WORD DOTQ SQ
%token COLON SEMI KIF KELSE KTHEN KBEGIN KUNTIL KWHILE KREPEAT KDO KLOOP KPLUSLOOP KVARIABLE KCONSTANT
%%

program : items ;
items   : /* empty */ | items item ;
item    : defn
        | KVARIABLE WORD   { ef(F2("void w_%s(void) { f_pushi(%s); }\n", mangle((char *)$2), istr(g_cellctr))); g_cellctr++; }
        | KCONSTANT WORD   { char *m = mangle((char *)$2); ef(F1("int c_%s;\n", m)); ef(F2("void w_%s(void) { f_pushi(c_%s); }\n", m, m)); e(F1("c_%s = f_popi();\n", m)); }
        | elem
        ;

defn    : defhead body SEMI  { e("}\n"); g_indef = 0; } ;
defhead : COLON WORD  { g_indef = 1; ef(F1("void w_%s(void) {\n", mangle((char *)$2))); } ;

body    : /* empty */ | body elem ;

elem    : INT     { e(F1("f_pushi(%s);\n", istr($1))); }
        | FLOAT   { e(F1("f_pushd(%s);\n", (char *)$1)); }
        | DOTQ    { e(F1("printf(\"%%s\", %s);\n", cstr((char *)$1))); }
        | SQ      { e(F1("f_pushs(%s);\n", cstr((char *)$1))); }
        | WORD    { emit_word((char *)$1); }
        | ifstmt | beginstmt | dostmt
        ;

ifstmt  : ifh body KTHEN              { e("}\n"); }
        | ifh body elh body KTHEN     { e("}\n"); }
        ;
ifh     : KIF    { e("if (f_popi()) {\n"); } ;
elh     : KELSE  { e("} else {\n"); } ;

beginstmt : bh body KUNTIL                    { e("if (f_popi()) break; }\n"); }
          | bh body wh body KREPEAT           { e("}\n"); }
          ;
bh      : KBEGIN { e("while (1) {\n"); } ;
wh      : KWHILE { e("if (!f_popi()) break;\n"); } ;

dostmt  : doh body KLOOP      { int d = g_loopstk[--g_loopn]; e(F1("__i%s++; } }\n", istr(d))); }
        | doh body KPLUSLOOP  { int d = g_loopstk[--g_loopn]; e(F1("__i%s += f_popi(); } }\n", istr(d))); }
        ;
doh     : KDO
          { int d = g_loopctr++; g_loopstk[g_loopn++] = d;
            e(F1("{ int __i%s = f_popi();", istr(d)));
            e(F1(" int __lim%s = f_popi(); ", istr(d)));
            e(F2("while (__i%s < __lim%s) {\n", istr(d), istr(d))); } ;
%%

void yyerror(char *m) { printf((int)"forth: %s near line %d\n", (int)m, pline); }
void setext(char *path, char *ext) { int n = strlen(path), i = n - 1; while (i > 0 && path[i] != '.' && path[i] != '\\' && path[i] != '/') i--; if (path[i] == '.') path[i + 1] = 0; else strcat(path, "."); strcat(path, ext); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: forth <file.fth> [-o <out.exe>]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int i;
    for (i = 2; i < argc; i++) if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) { o = (char *)argv[i + 1]; i++; }
    char outexe[1024]; char cpath[1024];
    if (o) strcpy(outexe, o); else { strcpy(outexe, in); setext(outexe, "exe"); }
    strcpy(cpath, outexe); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"forth: cannot read %s\n", (int)in); return 1; }
    forthfile = in; mainbuf = ""; g_indef = 0;

    out = fopen((int)cpath, (int)"w");
    if (out == 0) { printf((int)"forth: cannot write %s\n", (int)cpath); return 1; }
    yy_scan_string((int)src);
    yyparse();
    ef("int main(int argc, char **argv) {\n");
    ef(mainbuf);
    ef("  return 0;\n}\n");
    fclose(out);

    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; av[0] = (int)cc; av[1] = (int)cpath; av[2] = (int)"-o"; av[3] = (int)outexe; av[4] = (int)"--exe";
    int rc = sh_run((int)av, 5);
    if (rc == 0) printf((int)"forth: %s -> %s\n", (int)in, (int)outexe);
    else printf((int)"forth: cc failed (%d)\n", rc);
    return rc;
}
