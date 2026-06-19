/* lex.c — a clean-room minimal lex, written in the C subset compiled by `cc`.
 *
 * Reads a .l specification from stdin, writes a C scanner to stdout:
 *     dotnet lex.dll < grammar.l > scanner.c
 *     dotnet cc.dll scanner.c -o scanner.dll --exe
 *
 * Regex features: literals, . [] (ranges, ^neg) * + ? | () "strings" escapes,
 * and {NAME} definition expansion. Longest-match, first-rule-wins on ties.
 *
 * The generated scanner simulates a Thompson NFA (regex VM): each rule compiles
 * to instructions CHAR/ANY/CLASS/SPLIT/JMP/MATCH; yylex() runs all rules in
 * parallel and picks the longest match, then runs that rule's action.
 */

/* ---- input ---- */
char src[400000];
int srclen;

/* ---- definitions / rules ---- */
char defname[128][64];
char defpat[128][512];
int ndef;

char rulepat[256][512];
char ruleact[256][2048];
int nrule;

char topcode[20000];   int ntop;
char usercode[40000];   int nuser;

/* ---- regex VM program ---- */
int yyop[40000];
int yyx[40000];
int yyy[40000];
int np;

int clstab[4096];   /* class bitsets: class k uses clstab[k*8 .. k*8+7] */
int nclass;

/* ---- output helpers ---- */
void outc(int c) { putchar(c); }
void outs(char *s) { int i = 0; while (s[i]) putchar(s[i++]); }
void outd(int n)
{
    char t[16]; int i = 0;
    if (n < 0) { putchar('-'); n = -n; }
    if (n == 0) { putchar('0'); return; }
    while (n > 0) { t[i++] = '0' + (n % 10); n = n / 10; }
    while (i > 0) putchar(t[--i]);
}

/* ======================= reading the .l file ======================= */
int spos;

int line_is_sep(int p)   /* is the line at p exactly "%%"? */
{
    return src[p] == '%' && src[p + 1] == '%' && (src[p + 2] == '\n' || src[p + 2] == 0);
}

int next_line(int p) { while (p < srclen && src[p] != '\n') p++; if (p < srclen) p++; return p; }

void read_definitions(void)
{
    while (spos < srclen)
    {
        if (line_is_sep(spos)) { spos = next_line(spos); return; }
        /* %{ ... %} verbatim block */
        if (src[spos] == '%' && src[spos + 1] == '{')
        {
            spos = next_line(spos);
            while (spos < srclen && !(src[spos] == '%' && src[spos + 1] == '}'))
            {
                int e = next_line(spos);
                int i = spos;
                while (i < e) topcode[ntop++] = src[i++];
                spos = e;
            }
            spos = next_line(spos);
            continue;
        }
        if (src[spos] == '%') { spos = next_line(spos); continue; }       /* %option etc. */
        if (src[spos] == '\n' || src[spos] == ' ' || src[spos] == '\t') { spos = next_line(spos); continue; }

        /* NAME  pattern */
        int i = spos; int j = 0;
        while (i < srclen && (isalnum(src[i]) || src[i] == '_')) defname[ndef][j++] = src[i++];
        defname[ndef][j] = 0;
        while (i < srclen && (src[i] == ' ' || src[i] == '\t')) i++;
        int e = next_line(spos); int k = 0;
        while (i < e && src[i] != '\n') defpat[ndef][k++] = src[i++];
        defpat[ndef][k] = 0;
        ndef++;
        spos = e;
    }
}

/* read a rule pattern starting at spos; stop at top-level whitespace */
int read_pattern(char *out)
{
    int i = spos; int k = 0; int inclass = 0; int instr = 0;
    while (i < srclen)
    {
        int c = src[i];
        if (c == '\n') break;
        if (!inclass && !instr && (c == ' ' || c == '\t')) break;
        if (c == '\\') { out[k++] = c; out[k++] = src[i + 1]; i = i + 2; continue; }
        if (c == '"') instr = !instr;
        if (!instr && c == '[') inclass = 1;
        if (!instr && c == ']') inclass = 0;
        out[k++] = c;
        i++;
    }
    out[k] = 0;
    spos = i;
    return k;
}

void read_action(char *out)
{
    while (spos < srclen && (src[spos] == ' ' || src[spos] == '\t')) spos++;
    int k = 0;
    if (src[spos] == '{')
    {
        int depth = 0; spos++;            /* strip outer { } */
        while (spos < srclen)
        {
            int c = src[spos];
            if (c == '{') depth++;
            if (c == '}') { if (depth == 0) { spos++; break; } depth--; }
            out[k++] = c; spos++;
        }
    }
    else
    {
        while (spos < srclen && src[spos] != '\n') out[k++] = src[spos++];
    }
    out[k] = 0;
    spos = next_line(spos);
}

void read_rules(void)
{
    while (spos < srclen)
    {
        if (line_is_sep(spos)) { spos = next_line(spos); return; }
        if (src[spos] == '\n' || src[spos] == ' ' || src[spos] == '\t') { spos = next_line(spos); continue; }
        read_pattern(rulepat[nrule]);
        read_action(ruleact[nrule]);
        nrule++;
    }
}

void read_usercode(void)
{
    while (spos < srclen) usercode[nuser++] = src[spos++];
    usercode[nuser] = 0;
}

/* ======================= regex -> VM ======================= */
struct Re { int kind; int ch; int cls; struct Re *a; struct Re *b; };
/* kinds: 0 char, 1 any, 2 class, 3 concat, 4 alt, 5 star, 6 plus, 7 quest, 8 empty */

char *P; int Pi;   /* the pattern being parsed */

struct Re *newre(int kind)
{
    struct Re *r = (struct Re *)malloc(sizeof(struct Re));
    r->kind = kind; r->ch = 0; r->cls = 0; r->a = 0; r->b = 0;
    return r;
}

int esc_char(int c)
{
    if (c == 'n') return 10;
    if (c == 't') return 9;
    if (c == 'r') return 13;
    if (c == 'f') return 12;
    if (c == 'v') return 11;
    if (c == '0') return 0;
    return c;
}

void setbit(int k, int c) { clstab[k * 8 + (c >> 5)] = clstab[k * 8 + (c >> 5)] | (1 << (c & 31)); }

struct Re *parse_alt(void);

struct Re *parse_class(void)
{
    int k = nclass++;
    int i;
    for (i = 0; i < 8; i++) clstab[k * 8 + i] = 0;
    Pi++;                       /* skip '[' */
    int neg = 0;
    if (P[Pi] == '^') { neg = 1; Pi++; }
    while (P[Pi] && P[Pi] != ']')
    {
        int lo;
        if (P[Pi] == '\\') { Pi++; lo = esc_char(P[Pi]); Pi++; }
        else lo = P[Pi++];
        if (P[Pi] == '-' && P[Pi + 1] != ']')
        {
            Pi++; int hi;
            if (P[Pi] == '\\') { Pi++; hi = esc_char(P[Pi]); Pi++; }
            else hi = P[Pi++];
            int c; for (c = lo; c <= hi; c++) setbit(k, c);
        }
        else setbit(k, lo);
    }
    if (P[Pi] == ']') Pi++;
    if (neg) { for (i = 0; i < 8; i++) clstab[k * 8 + i] = ~clstab[k * 8 + i]; }
    struct Re *r = newre(2);
    r->cls = k;
    return r;
}

struct Re *parse_atom(void)
{
    int c = P[Pi];
    if (c == '(') { Pi++; struct Re *r = parse_alt(); if (P[Pi] == ')') Pi++; return r; }
    if (c == '[') return parse_class();
    if (c == '.') { Pi++; return newre(1); }
    if (c == '"')
    {
        Pi++;
        struct Re *r = newre(8);   /* empty, then concat literals */
        while (P[Pi] && P[Pi] != '"')
        {
            int ch;
            if (P[Pi] == '\\') { Pi++; ch = esc_char(P[Pi]); Pi++; }
            else ch = P[Pi++];
            struct Re *lit = newre(0); lit->ch = ch;
            struct Re *cat = newre(3); cat->a = r; cat->b = lit; r = cat;
        }
        if (P[Pi] == '"') Pi++;
        return r;
    }
    if (c == '\\') { Pi++; struct Re *r = newre(0); r->ch = esc_char(P[Pi]); Pi++; return r; }
    struct Re *r = newre(0); r->ch = c; Pi++;
    return r;
}

struct Re *parse_rep(void)
{
    struct Re *r = parse_atom();
    while (P[Pi] == '*' || P[Pi] == '+' || P[Pi] == '?')
    {
        struct Re *n;
        if (P[Pi] == '*') n = newre(5);
        else if (P[Pi] == '+') n = newre(6);
        else n = newre(7);
        n->a = r; r = n; Pi++;
    }
    return r;
}

int at_end(void) { int c = P[Pi]; return c == 0 || c == '|' || c == ')'; }

struct Re *parse_concat(void)
{
    if (at_end()) return newre(8);
    struct Re *r = parse_rep();
    while (!at_end())
    {
        struct Re *cat = newre(3); cat->a = r; cat->b = parse_rep(); r = cat;
    }
    return r;
}

struct Re *parse_alt(void)
{
    struct Re *r = parse_concat();
    while (P[Pi] == '|')
    {
        Pi++;
        struct Re *alt = newre(4); alt->a = r; alt->b = parse_concat(); r = alt;
    }
    return r;
}

int emit(int op, int x, int y) { yyop[np] = op; yyx[np] = x; yyy[np] = y; return np++; }

void compile_re(struct Re *r)
{
    int k = r->kind;
    if (k == 0) emit(0, r->ch, 0);
    else if (k == 1) emit(1, 0, 0);
    else if (k == 2) emit(2, r->cls, 0);
    else if (k == 3) { compile_re(r->a); compile_re(r->b); }
    else if (k == 4)
    {
        int s = emit(3, 0, 0);
        int l1 = np; compile_re(r->a);
        int j = emit(4, 0, 0);
        int l2 = np; compile_re(r->b);
        yyx[s] = l1; yyy[s] = l2; yyx[j] = np;
    }
    else if (k == 5)
    {
        int s = emit(3, 0, 0);
        int l2 = np; compile_re(r->a);
        emit(4, s, 0);
        yyx[s] = l2; yyy[s] = np;
    }
    else if (k == 6)
    {
        int l1 = np; compile_re(r->a);
        int s = emit(3, l1, 0); yyy[s] = np;
    }
    else if (k == 7)
    {
        int s = emit(3, 0, 0);
        int l1 = np; compile_re(r->a);
        yyx[s] = l1; yyy[s] = np;
    }
    /* k==8 empty: nothing */
}

/* expand {NAME} references in a pattern into (definition) */
void expand_pattern(char *in, char *out)
{
    int i = 0; int k = 0;
    while (in[i])
    {
        if (in[i] == '\\') { out[k++] = in[i++]; out[k++] = in[i++]; continue; }
        if (in[i] == '{')
        {
            char nm[64]; int j = 0; int p = i + 1;
            while (in[p] && in[p] != '}') nm[j++] = in[p++];
            nm[j] = 0;
            int d; int found = -1;
            for (d = 0; d < ndef; d++) if (strcmp(nm, defname[d]) == 0) found = d;
            if (found >= 0 && in[p] == '}')
            {
                out[k++] = '(';
                int q = 0; while (defpat[found][q]) out[k++] = defpat[found][q++];
                out[k++] = ')';
                i = p + 1;
                continue;
            }
        }
        out[k++] = in[i++];
    }
    out[k] = 0;
}

/* ======================= emit the scanner ======================= */
void emit_table(char *name, int *arr, int n)
{
    outs("int "); outs(name); outs("["); outd(n); outs("] = {");
    int i;
    for (i = 0; i < n; i++) { if (i) outs(","); outd(arr[i]); }
    outs("};\n");
}

void emit_scanner(void)
{
    outs("/* generated by lex.c — do not edit */\n");
    int i; for (i = 0; i < ntop; i++) putchar(topcode[i]);
    outs("\n");

    emit_table("yyop", yyop, np);
    emit_table("yyx", yyx, np);
    emit_table("yyy", yyy, np);
    emit_table("yycls", clstab, nclass * 8);

    outs("int yynp = "); outd(np); outs(";\n");
    outs("char *yytext; int yyleng;\n");
    outs("char *yy_buf; int yy_pos; int yy_len; int yy_started;\n");
    outs("char yy_textbuf[8192];\n");
    outs("int yy_clist[40000]; int yy_nlist[40000]; int yy_seen[40000];\n");
    outs("int yy_listn; int yy_k; int yy_bestlen; int yy_bestrule;\n");

    outs("int yy_inclass(int k, int c) { return (yycls[k*8 + (c>>5)] >> (c&31)) & 1; }\n");
    outs("void yy_clearseen(void) { int i; for (i=0;i<yynp;i++) yy_seen[i]=0; }\n");
    outs("void yy_add(int *list, int pc) {\n");
    outs("  if (yy_seen[pc]) return; yy_seen[pc]=1;\n");
    outs("  int op = yyop[pc];\n");
    outs("  if (op==3) { yy_add(list, yyx[pc]); yy_add(list, yyy[pc]); }\n");
    outs("  else if (op==4) { yy_add(list, yyx[pc]); }\n");
    outs("  else if (op==5) { int r=yyx[pc]; if (yy_k>yy_bestlen || (yy_k==yy_bestlen && r<yy_bestrule)) { yy_bestlen=yy_k; yy_bestrule=r; } }\n");
    outs("  else { list[yy_listn]=pc; yy_listn=yy_listn+1; }\n");
    outs("}\n");

    outs("void yy_scan_string(char *s) { yy_buf=s; yy_pos=0; yy_len=strlen(s); yy_started=1; }\n");
    outs("void yy_init(void) {\n");
    outs("  if (yy_started) return; yy_started=1;\n");
    outs("  int cap=1024; char *b=(char*)malloc(cap); int n=0; int ch;\n");
    outs("  while ((ch=getchar())>=0) { if (n+1>=cap) { cap=cap*2; b=(char*)realloc(b,cap); } b[n]=(char)ch; n=n+1; }\n");
    outs("  b[n]=0; yy_buf=b; yy_len=n; yy_pos=0;\n");
    outs("}\n");

    outs("int yylex(void) {\n");
    outs("  if (!yy_started) yy_init();\n");
    outs("  while (yy_pos < yy_len) {\n");
    outs("    int start=yy_pos; int step=0; int clistn; int i;\n");
    outs("    yy_bestlen=-1; yy_bestrule=-1;\n");
    outs("    yy_clearseen(); yy_listn=0; yy_k=0; yy_add(yy_clist, 0); clistn=yy_listn;\n");
    outs("    while (clistn>0 && start+step < yy_len) {\n");
    outs("      int c = yy_buf[start+step];\n");
    outs("      yy_clearseen(); yy_listn=0; yy_k=step+1;\n");
    outs("      for (i=0;i<clistn;i++) {\n");
    outs("        int pc=yy_clist[i]; int op=yyop[pc]; int mt=0;\n");
    outs("        if (op==0) { if (yyx[pc]==c) mt=1; }\n");
    outs("        else if (op==1) { if (c!=10) mt=1; }\n");
    outs("        else if (op==2) { if (yy_inclass(yyx[pc],c)) mt=1; }\n");
    outs("        if (mt) yy_add(yy_nlist, pc+1);\n");
    outs("      }\n");
    outs("      for (i=0;i<yy_listn;i++) yy_clist[i]=yy_nlist[i];\n");
    outs("      clistn=yy_listn; step=step+1;\n");
    outs("    }\n");
    outs("    if (yy_bestlen < 1) { yy_pos=start+1; continue; }\n");
    outs("    yyleng=yy_bestlen;\n");
    outs("    for (i=0;i<yy_bestlen;i++) yy_textbuf[i]=yy_buf[start+i];\n");
    outs("    yy_textbuf[yy_bestlen]=0; yytext=yy_textbuf;\n");
    outs("    yy_pos=start+yy_bestlen;\n");
    outs("    switch (yy_bestrule) {\n");
    for (i = 0; i < nrule; i++)
    {
        outs("      case "); outd(i); outs(": { ");
        outs(ruleact[i]);
        outs(" } break;\n");
    }
    outs("    }\n");
    outs("  }\n");
    outs("  return 0;\n");
    outs("}\n");

    int j; for (j = 0; j < nuser; j++) putchar(usercode[j]);
}

int main(void)
{
    int ch;
    srclen = 0;
    while ((ch = getchar()) >= 0) if (ch != 13) src[srclen++] = (char)ch;  /* tolerate CRLF */
    src[srclen] = 0;

    spos = 0;
    read_definitions();
    read_rules();
    read_usercode();

    /* compile every rule into one VM program: SPLIT-chain of alternatives */
    char expanded[1024];
    int i;
    for (i = 0; i < nrule; i++)
    {
        int s = -1;
        if (i < nrule - 1) s = emit(3, 0, 0);  /* split: this rule | rest */
        int rulestart = np;
        expand_pattern(rulepat[i], expanded);
        P = expanded; Pi = 0;
        struct Re *re = parse_alt();
        compile_re(re);
        emit(5, i, 0);                          /* MATCH i */
        if (s >= 0) { yyx[s] = rulestart; yyy[s] = np; }
    }

    emit_scanner();
    return 0;
}
