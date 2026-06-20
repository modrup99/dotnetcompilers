%{
/* ilsh — a small bash/ksh-style shell built with our lex + yacc.
 * The grammar builds a command AST; main() tree-walks it. */
enum { NSEQ = 1, NAND, NOR, NPIPE, NIF, NWHILE, NFOR, NSIMPLE, NELEM, NBG };
int g_bg;
int g_xq;        /* set by expand() when the word contained quotes (suppresses word-splitting) */
struct Node { int kind; int a; int b; int c; };
int root;
int last_status;
char vnames[256][64];
int  vvals[256];
int  nvars;
char anames[64][64];
int  avals[64];
int  naliases;
int  hist[256];
int  nhist;
char dstack[64][1024];
int  ndstack;
%}
%token WORD IF THEN ELSE ELIF FI WHILE DO DONE FOR IN AND_IF OR_IF APPEND
%start program
%%
program : list                   { root = $1; }
        |                        { root = 0; }
        ;
list : cmds                      { $$ = $1; }
     | cmds and_or               { $$ = seqn($1, $3); }
     ;
cmds :                           { $$ = 0; }
     | cmds and_or ';'           { $$ = seqn($1, $2); }
     | cmds and_or '&'           { $$ = seqn($1, mknode(NBG, $2, 0, 0)); }
     | cmds ';'                  { $$ = $1; }
     ;
and_or : and_or AND_IF pipeline  { $$ = mknode(NAND, $1, $3, 0); }
       | and_or OR_IF pipeline   { $$ = mknode(NOR, $1, $3, 0); }
       | pipeline                { $$ = $1; }
       ;
pipeline : command '|' pipeline  { $$ = mknode(NPIPE, $1, $3, 0); }
         | command               { $$ = $1; }
         ;
command : simple                 { $$ = $1; }
        | compound               { $$ = $1; }
        ;
compound : IF list THEN list else_part FI    { $$ = mknode(NIF, $2, $4, $5); }
         | WHILE list DO list DONE           { $$ = mknode(NWHILE, $2, $4, 0); }
         | FOR WORD IN words ';' DO list DONE { $$ = mknode(NFOR, $2, $4, $7); }
         | FOR WORD IN words DO list DONE     { $$ = mknode(NFOR, $2, $4, $6); }
         | '(' list ')'                       { $$ = $2; }
         ;
else_part : ELSE list                       { $$ = $2; }
          | ELIF list THEN list else_part   { $$ = mknode(NIF, $2, $4, $5); }
          |                                 { $$ = 0; }
          ;
simple : elements                { $$ = mknode(NSIMPLE, $1, 0, 0); }
       ;
elements : elements element      { $$ = appendel($1, $2); }
         | element               { $$ = $1; }
         ;
element : WORD                   { $$ = mknode(NELEM, 0, $1, 0); }
        | '>' WORD               { $$ = mknode(NELEM, 1, $2, 0); }
        | APPEND WORD            { $$ = mknode(NELEM, 2, $2, 0); }
        | '<' WORD               { $$ = mknode(NELEM, 3, $2, 0); }
        ;
words : words WORD               { $$ = appendel($1, mknode(NELEM, 0, $2, 0)); }
      | WORD                     { $$ = mknode(NELEM, 0, $1, 0); }
      ;
%%

int printf(int f, ...);

int mknode(int kind, int a, int b, int c)
{
    struct Node *n = (struct Node *)malloc(sizeof(struct Node));
    n->kind = kind; n->a = a; n->b = b; n->c = c;
    return (int)n;
}
int appendel(int head, int el)
{
    struct Node *h = (struct Node *)head;
    while (h->c) h = (struct Node *)h->c;
    h->c = el;
    return head;
}
int seqn(int a, int b) { return a ? mknode(NSEQ, a, b, 0) : b; }

/* ---- variables ---- */
int findvar(char *nm) { int i; for (i = 0; i < nvars; i++) if (strcmp(vnames[i], nm) == 0) return i; return -1; }
void setvar(char *nm, char *val)
{
    int k = findvar(nm);
    if (k < 0) { k = nvars; nvars = nvars + 1; strcpy(vnames[k], nm); }
    vvals[k] = strdup(val);
}
char *getvar(char *nm)   /* shell-local variables only (not the Windows environment) */
{
    int k = findvar(nm);
    if (k >= 0) return (char *)vvals[k];
    return 0;
}

/* ===================== virtual filesystem =====================
 * Off by default (g_vfs == 0): every path passes through unchanged, so scripts that
 * predate the VFS behave exactly as before. Enabled by `--home DIR` or `vfs on`, it
 * presents a Unix-like tree (/home /bin /etc /include /lib /tmp and /home/windows) whose
 * mount points are ordinary shell variables (home, bin, ...), so the layout is fully
 * configurable from .ilshellrc and overridable on the fly. vmap() turns a virtual path
 * into the real Windows path it stands for; lcd/lpwd/lls bypass it to reach the real FS. */
int g_vfs;                 /* 0 = off (default, backward compatible) */
char g_vcwd[1024];         /* virtual working directory, e.g. "/home" */
char *vmount_pfx[10]; char *vmount_var[10]; int n_vmount;
void vmount(char *pfx, char *var) { vmount_pfx[n_vmount] = pfx; vmount_var[n_vmount] = var; n_vmount++; }
void vfs_mounts_init(void)
{
    n_vmount = 0;
    vmount("/home/windows", "windows");   /* longest prefixes first */
    vmount("/home", "home");
    vmount("/bin", "bin");
    vmount("/lib", "lib");
    vmount("/include", "include");
    vmount("/includes", "include");       /* alias */
    vmount("/etc", "etc");
    vmount("/tmp", "tmp");
}
/* sensible default mount targets; any can be overridden in .ilshellrc */
void vfs_defaults(char *homedir)
{
    char *repo = (char *)rt_repo(); char b[1100];
    setvar("home", homedir);
    int up = sh_getenv((int)"USERPROFILE");          /* the real Windows user home, e.g. C:\Users\you */
    setvar("windows", up ? (char *)up : (char *)rt_home());
    sprintf((int)b, (int)"%s\\out", (int)repo);     setvar("bin", b);
    sprintf((int)b, (int)"%s\\out", (int)repo);     setvar("lib", b);
    sprintf((int)b, (int)"%s\\include", (int)repo); setvar("include", b);
    sprintf((int)b, (int)"%s\\etc", (int)repo);     setvar("etc", b);
    sprintf((int)b, (int)"%s\\tmp", (int)repo);     setvar("tmp", b);
}
/* collapse "." and ".." in an absolute virtual path */
void vnorm(char *p, char *out)
{
    char tmp[1024]; strcpy(tmp, p);
    char *segs[256]; int nseg = 0; int i = 0;
    while (tmp[i])
    {
        while (tmp[i] == '/') i++;
        if (!tmp[i]) break;
        int st = i;
        while (tmp[i] && tmp[i] != '/') i++;
        if (tmp[i]) { tmp[i] = 0; i++; }
        char *seg = tmp + st;
        if (strcmp(seg, ".") == 0) continue;
        if (strcmp(seg, "..") == 0) { if (nseg > 0) nseg--; continue; }
        if (nseg < 256) segs[nseg++] = seg;
    }
    int o = 0; out[o++] = '/'; int k;
    for (k = 0; k < nseg; k++) { if (k) out[o++] = '/'; int m = 0; while (segs[k][m]) out[o++] = segs[k][m++]; }
    out[o] = 0;
}
/* resolve vpath (relative to g_vcwd if it doesn't start with '/') to an absolute virtual path */
void vabs(char *vpath, char *out)
{
    char joined[2048];
    if (vpath[0] == '/') strcpy(joined, vpath);
    else { strcpy(joined, g_vcwd); strcat(joined, "/"); strcat(joined, vpath); }
    vnorm(joined, out);
}
/* map a (possibly relative) virtual path to a real Windows path. Identity when VFS off. */
char *vmap(char *vpath)
{
    if (!g_vfs) return vpath;
    if (vpath[0] && vpath[1] == ':') return vpath;   /* already a real Windows path (C:\..) */
    char abs[1024]; vabs(vpath, abs);
    int i;
    for (i = 0; i < n_vmount; i++)
    {
        char *pfx = vmount_pfx[i]; int pl = strlen(pfx);
        if (strncmp(abs, pfx, pl) == 0 && (abs[pl] == 0 || abs[pl] == '/'))
        {
            char *real = getvar(vmount_var[i]); if (real == 0) real = (char *)"";
            char *r = (char *)malloc(strlen(real) + strlen(abs) + 4);
            strcpy(r, real); strcat(r, abs + pl);
            int k; for (k = 0; r[k]; k++) if (r[k] == '/') r[k] = '\\';
            return r;
        }
    }
    return (char *)strdup((int)abs);   /* "/" root or unknown mount: callers handle */
}

/* resolve an external command against the shell's PATH variable */
char *resolve_exec(char *cmd)
{
    if (cmd[0] == '/' && g_vfs) return vmap(cmd);                      /* /bin/foo -> real exe */
    if (strchr((int)cmd, '/') || strchr((int)cmd, '\\')) return cmd;   /* explicit path */
    if (g_vfs)   /* a bare command: look in the /bin mount first */
    {
        char *bin = getvar("bin");
        if (bin)
        {
            char cand[1100];
            sprintf((int)cand, (int)"%s\\%s", (int)bin, (int)cmd);     if (rt_exists((int)cand)) return (char *)strdup((int)cand);
            sprintf((int)cand, (int)"%s\\%s.exe", (int)bin, (int)cmd); if (rt_exists((int)cand)) return (char *)strdup((int)cand);
        }
    }
    char *path = getvar("PATH");
    if (path == 0) return cmd;
    char cand[1100]; char dir[1024];
    int i = 0, s = 0;
    while (1)
    {
        char c = path[i];
        if (c == ';' || c == 0)
        {
            int dl = i - s;
            if (dl > 0 && dl < 1024)
            {
                int k; for (k = 0; k < dl; k++) dir[k] = path[s + k]; dir[k] = 0;
                sprintf((int)cand, (int)"%s\\%s", (int)dir, (int)cmd); if (rt_exists((int)cand)) return (char *)strdup((int)cand);
                sprintf((int)cand, (int)"%s\\%s.exe", (int)dir, (int)cmd); if (rt_exists((int)cand)) return (char *)strdup((int)cand);
                sprintf((int)cand, (int)"%s\\%s.bat", (int)dir, (int)cmd); if (rt_exists((int)cand)) return (char *)strdup((int)cand);
                sprintf((int)cand, (int)"%s\\%s.cmd", (int)dir, (int)cmd); if (rt_exists((int)cand)) return (char *)strdup((int)cand);
            }
            if (c == 0) break;
            s = i + 1;
        }
        i++;
    }
    return cmd;   /* not found in PATH; let the OS try */
}

/* ---- expansion ---- */
int expand_var(char *w, int i, char *out, int *oi)
{
    if (w[i] == '?') { char t[16]; sprintf(t, "%d", last_status); int k = 0; while (t[k]) { out[*oi] = t[k]; *oi = *oi + 1; k++; } return i + 1; }
    int braces = 0;
    if (w[i] == '{') { braces = 1; i++; }
    char name[64]; int j = 0;
    while (w[i] && (isalnum(w[i]) || w[i] == '_')) { name[j] = w[i]; j++; i++; }
    name[j] = 0;
    if (braces && w[i] == '}') i++;
    char *v = getvar(name);
    if (v) { int k = 0; while (v[k]) { out[*oi] = v[k]; *oi = *oi + 1; k++; } }
    return i;
}
void appstr(char *out, int *oi, char *s) { int k = 0; while (s[k]) { out[*oi] = s[k]; *oi = *oi + 1; k++; } }

/* run a command string, capturing its stdout (trailing newlines stripped) */
char *cmd_subst(char *inner)
{
    int save = g_xq;                 /* inner expands clobber g_xq; preserve the caller's quote state */
    sh_capture_begin();
    run_string(inner);
    char *r = (char *)sh_capture_end();
    g_xq = save;
    return r;
}

/* w[i] starts a `...` or $(...) substitution; run it and append; return index past it */
int do_subst(char *w, int i, char *out, int *oi)
{
    int s, e, depth;
    if (w[i] == '`') { i++; s = i; while (w[i] && w[i] != '`') i++; }
    else { i = i + 2; s = i; depth = 1; while (w[i] && depth > 0) { if (w[i] == '(') depth++; else if (w[i] == ')') depth--; if (depth > 0) i++; } }
    e = i;
    char *inner = (char *)malloc(e - s + 1); int k; for (k = s; k < e; k++) inner[k - s] = w[k]; inner[e - s] = 0;
    if (w[i] == '`' || w[i] == ')') i++;
    appstr(out, oi, cmd_subst(inner));
    return i;
}

/* ---- integer arithmetic for $((expr)) (recursive descent; vars via getvar) ---- */
char *g_ap;
void a_sk() { while (*g_ap == ' ' || *g_ap == '\t') g_ap++; }
int a_nm(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || (c >= '0' && c <= '9'); }
int a_expr();
int a_prim()
{
    a_sk();
    if (*g_ap == '(') { g_ap++; int v = a_expr(); a_sk(); if (*g_ap == ')') g_ap++; return v; }
    if (*g_ap == '-') { g_ap++; return -a_prim(); }
    if (*g_ap == '+') { g_ap++; return a_prim(); }
    if (*g_ap == '$') g_ap++;
    if (*g_ap >= '0' && *g_ap <= '9') { int v = 0; while (*g_ap >= '0' && *g_ap <= '9') { v = v * 10 + (*g_ap - '0'); g_ap++; } return v; }
    if ((*g_ap >= 'a' && *g_ap <= 'z') || (*g_ap >= 'A' && *g_ap <= 'Z') || *g_ap == '_')
    { char nm[128]; int k = 0; while (a_nm(*g_ap)) { nm[k++] = *g_ap; g_ap++; } nm[k] = 0; char *v = getvar(nm); return v ? atoi((int)v) : 0; }
    return 0;
}
int a_pow() { int b = a_prim(); a_sk(); while (*g_ap == '*' && g_ap[1] == '*') { g_ap += 2; int e = a_prim(); int r = 1; while (e-- > 0) r = r * b; b = r; a_sk(); } return b; }
int a_term() { int v = a_pow(); a_sk(); while ((*g_ap == '*' && g_ap[1] != '*') || *g_ap == '/' || *g_ap == '%') { int op = *g_ap; g_ap++; int r = a_pow(); if (op == '*') v = v * r; else if (op == '/') v = r ? v / r : 0; else v = r ? v % r : 0; a_sk(); } return v; }
int a_expr() { int v = a_term(); a_sk(); while (*g_ap == '+' || *g_ap == '-') { int op = *g_ap; g_ap++; int r = a_term(); if (op == '+') v = v + r; else v = v - r; a_sk(); } return v; }
int arith_eval(char *s) { g_ap = s; return a_expr(); }

/* w[i] starts $((expr)); evaluate integer arithmetic and append the result */
int arith_subst(char *w, int i, char *out, int *oi)
{
    int j = i + 2, depth = 1, s = j;   /* past "$(" ; the inner span is "(expr)" */
    while (w[j] && depth > 0) { if (w[j] == '(') depth++; else if (w[j] == ')') depth--; if (depth > 0) j++; }
    char *inner = (char *)malloc(j - s + 1); int k; for (k = s; k < j; k++) inner[k - s] = w[k]; inner[j - s] = 0;
    if (w[j] == ')') j++;
    int len = strlen(inner); char *expr = inner;
    if (len >= 2 && inner[0] == '(' && inner[len - 1] == ')') { inner[len - 1] = 0; expr = inner + 1; }
    char buf[32]; sprintf((int)buf, (int)"%d", arith_eval(expr)); appstr(out, oi, buf);
    return j;
}

char *expand(char *w)
{
    char *out = (char *)malloc(4096); int oi = 0; int i = 0;
    g_xq = 0;
    while (w[i])
    {
        int c = w[i];
        if (c == '\'') { g_xq = 1; i++; while (w[i] && w[i] != '\'') { out[oi] = w[i]; oi++; i++; } if (w[i] == '\'') i++; continue; }
        if (c == '`') { i = do_subst(w, i, out, &oi); continue; }
        if (c == '$' && w[i + 1] == '(' && w[i + 2] == '(') { i = arith_subst(w, i, out, &oi); continue; }
        if (c == '$' && w[i + 1] == '(') { i = do_subst(w, i, out, &oi); continue; }
        if (c == '"')
        {
            g_xq = 1; i++;
            while (w[i] && w[i] != '"')
            {
                if (w[i] == '`') i = do_subst(w, i, out, &oi);
                else if (w[i] == '$' && w[i + 1] == '(' && w[i + 2] == '(') i = arith_subst(w, i, out, &oi);
                else if (w[i] == '$' && w[i + 1] == '(') i = do_subst(w, i, out, &oi);
                else if (w[i] == '$') i = expand_var(w, i + 1, out, &oi);
                else { out[oi] = w[i]; oi++; i++; }
            }
            if (w[i] == '"') i++; continue;
        }
        if (c == '$') { i = expand_var(w, i + 1, out, &oi); continue; }
        out[oi] = c; oi++; i++;
    }
    out[oi] = 0;
    return out;
}

/* expand `raw`, then (unless it was quoted or an assignment) split the result on
 * whitespace into separate words; push each onto argv[]. Returns the new count. */
int append_expanded(char *raw, int *argv, int argc)
{
    char *x = expand(raw);
    if (g_xq || is_assign(raw)) { argv[argc] = (int)x; return argc + 1; }
    int p = 0;
    while (x[p])
    {
        while (x[p] == ' ' || x[p] == '\t' || x[p] == '\n') p++;
        if (!x[p]) break;
        int st = p;
        while (x[p] && x[p] != ' ' && x[p] != '\t' && x[p] != '\n') p++;
        int len = p - st; char *wd = (char *)malloc(len + 1);
        int k; for (k = 0; k < len; k++) wd[k] = x[st + k]; wd[len] = 0;
        argv[argc] = (int)wd; argc++;
    }
    return argc;
}

/* ---- aliases ---- */
int findalias(char *nm) { int i; for (i = 0; i < naliases; i++) if (strcmp(anames[i], nm) == 0) return i; return -1; }
void setalias(char *nm, char *val) { int k = findalias(nm); if (k < 0) { k = naliases; naliases = naliases + 1; strcpy(anames[k], nm); } avals[k] = strdup(val); }
int split_words(char *s, int *out, int max)
{
    char *c = (char *)strdup((int)s); int n = 0, i = 0, inw = 0;
    while (c[i]) { if (c[i] == ' ' || c[i] == '\t') { c[i] = 0; inw = 0; } else { if (!inw && n < max) out[n++] = (int)(c + i); inw = 1; } i++; }
    return n;
}
int bi_alias(int n, int *argv, int start)
{
    if (n == 1) { int i; for (i = 0; i < naliases; i++) { sh_write((int)"alias "); sh_write((int)anames[i]); sh_write((int)"='"); sh_write(avals[i]); sh_write((int)"'\n"); } return 0; }
    int i;
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i]; char nm[64]; int j = 0;
        while (a[j] && a[j] != '=') { nm[j] = a[j]; j++; } nm[j] = 0;
        char *val = (a[j] == '=') ? a + j + 1 : (char *)"";
        setalias(nm, val);
    }
    return 0;
}

/* ---- assignments ---- */
int is_assign(char *a)
{
    if (!(isalpha(a[0]) || a[0] == '_')) return 0;
    int i = 0;
    while (a[i] && a[i] != '=') { if (!(isalnum(a[i]) || a[i] == '_')) return 0; i++; }
    return a[i] == '=';
}
void do_assign(char *a)
{
    char name[64]; int i = 0;
    while (a[i] && a[i] != '=') { name[i] = a[i]; i++; }
    name[i] = 0;
    char *val = (a[i] == '=') ? a + i + 1 : (char *)"";
    setvar(name, val);
}

/* ---- builtins ---- */
int bi_echo(int n, int *argv, int start)
{
    int i;
    for (i = start + 1; i < start + n; i++) { if (i > start + 1) sh_write((int)" "); sh_write(argv[i]); }
    sh_write((int)"\n");
    return 0;
}
int bi_cd(int n, int *argv, int start)
{
    if (g_vfs)
    {
        char *arg = (n > 1) ? (char *)argv[start + 1] : (char *)"/home";
        char abs[1024]; vabs(arg, abs);
        if (strcmp(abs, "/") == 0) { strcpy(g_vcwd, "/"); return 0; }   /* the virtual root */
        char *real = vmap(abs);
        if (!rt_isdir((int)real)) { sh_write((int)"cd: "); sh_write((int)arg); sh_write((int)": no such directory\n"); return 1; }
        strcpy(g_vcwd, abs);
        sh_cd((int)real);    /* keep the real cwd aligned so relative paths to tools resolve */
        return 0;
    }
    char *d = (n > 1) ? (char *)argv[start + 1] : getvar("HOME");
    if (d == 0) return 1;
    return sh_cd((int)d);
}
int bi_pwd(void)
{
    if (g_vfs) { sh_write((int)g_vcwd); sh_write((int)"\n"); return 0; }
    char buf[1024]; sh_cwd((int)buf); sh_write((int)buf); sh_write((int)"\n"); return 0;
}
/* lcd / lpwd / lls operate on the REAL Windows filesystem, bypassing the VFS */
int bi_lcd(int n, int *argv, int start)
{
    char *d = (n > 1) ? (char *)argv[start + 1] : (char *)rt_home();
    if (d == 0) return 1;
    int r = sh_cd((int)d);
    if (r) { sh_write((int)"lcd: "); sh_write((int)d); sh_write((int)": no such directory\n"); }
    return r;
}
int bi_lpwd(void) { char buf[1024]; sh_cwd((int)buf); sh_write((int)buf); sh_write((int)"\n"); return 0; }
int bi_lls(int n, int *argv, int start)
{
    int lflag = 0, aflag = 0; char *path = 0; int i;
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i];
        if (a[0] == '-' && a[1]) { int j = 1; while (a[j]) { if (a[j] == 'l') lflag = 1; if (a[j] == 'a') aflag = 1; j++; } }
        else path = a;
    }
    if (path == 0) path = (char *)".";
    int cnt = rt_lsopen((int)path);   /* real path, no vmap */
    if (cnt < 0) { sh_write((int)"lls: "); sh_write((int)path); sh_write((int)": no such file or directory\n"); return 1; }
    for (i = 0; i < cnt; i++)
    {
        char *nm = (char *)rt_lsname(i);
        if (!aflag && nm[0] == '.') continue;
        if (lflag) { char b[24]; sh_write((int)rt_lsmode(i)); sh_write((int)" 1 user group "); sprintf((int)b, (int)"%8ld", rt_lssize(i)); sh_write((int)b); sh_write((int)" "); sh_write((int)rt_lsdate(i)); sh_write((int)" "); sh_write((int)nm); sh_write((int)"\n"); }
        else { sh_write((int)nm); sh_write((int)"  "); }
    }
    if (!lflag && cnt > 0) sh_write((int)"\n");
    return 0;
}
/* vfs on [DIR] | off | status — turn the virtual filesystem on/off and show mounts */
int bi_vfs(int n, int *argv, int start)
{
    char *sub = (n > 1) ? (char *)argv[start + 1] : (char *)"status";
    if (strcmp(sub, "on") == 0)
    {
        char rcwd[1024]; sh_cwd((int)rcwd);
        char *dir = (n > 2) ? (char *)argv[start + 2] : rcwd;
        vfs_mounts_init();
        if (getvar("home") == 0) vfs_defaults(dir); else setvar("home", dir);
        if (getvar("windows") == 0) vfs_defaults(dir);
        g_vfs = 1; strcpy(g_vcwd, "/home");
        char *real = vmap("/home"); sh_cd((int)real);
        return 0;
    }
    if (strcmp(sub, "off") == 0) { g_vfs = 0; return 0; }
    /* status */
    sh_write((int)"vfs: "); sh_write(g_vfs ? (int)"on\n" : (int)"off\n");
    if (g_vfs)
    {
        int i;
        for (i = 0; i < n_vmount; i++)
        {
            char *real = getvar(vmount_var[i]); sh_write((int)vmount_pfx[i]); sh_write((int)"  ->  "); sh_write(real ? (int)real : (int)"(unset)"); sh_write((int)"\n");
        }
    }
    return 0;
}
int bi_set(void)
{
    int i;
    for (i = 0; i < nvars; i++) { sh_write((int)vnames[i]); sh_write((int)"="); sh_write(vvals[i]); sh_write((int)"\n"); }
    return 0;
}
int bi_export(int n, int *argv, int start)
{
    int i;
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i];
        if (is_assign(a)) do_assign(a);
        char nm[64]; int j = 0; while (a[j] && a[j] != '=') { nm[j] = a[j]; j++; } nm[j] = 0;
        char *v = getvar(nm);
        sh_export((int)nm, v ? (int)v : (int)"");
    }
    return 0;
}
int bi_test(int n, int *argv, int start)
{
    int base = start + 1; int cnt = n - 1;
    if (strcmp((char *)argv[start], "[") == 0) { if (cnt > 0 && strcmp((char *)argv[base + cnt - 1], "]") == 0) cnt--; }
    if (cnt == 0) return 1;
    if (cnt == 1) { return strlen((char *)argv[base]) > 0 ? 0 : 1; }
    if (cnt == 2)
    {
        char *op = (char *)argv[base]; char *s = (char *)argv[base + 1];
        if (strcmp(op, "-z") == 0) return strlen(s) == 0 ? 0 : 1;
        if (strcmp(op, "-n") == 0) return strlen(s) > 0 ? 0 : 1;
        return 1;
    }
    char *a = (char *)argv[base]; char *op = (char *)argv[base + 1]; char *b = (char *)argv[base + 2];
    if (strcmp(op, "=") == 0) return strcmp(a, b) == 0 ? 0 : 1;
    if (strcmp(op, "!=") == 0) return strcmp(a, b) != 0 ? 0 : 1;
    int x = atoi(a); int y = atoi(b);
    if (strcmp(op, "-eq") == 0) return x == y ? 0 : 1;
    if (strcmp(op, "-ne") == 0) return x != y ? 0 : 1;
    if (strcmp(op, "-lt") == 0) return x < y ? 0 : 1;
    if (strcmp(op, "-gt") == 0) return x > y ? 0 : 1;
    if (strcmp(op, "-le") == 0) return x <= y ? 0 : 1;
    if (strcmp(op, "-ge") == 0) return x >= y ? 0 : 1;
    return 1;
}

int exec(int node);   /* forward */

/* one-line usage for each internal command; returns 1 if cmd is internal */
int print_usage(char *c)
{
    if (streq(c, "cd")) sh_write((int)"usage: cd [dir]   (no arg = $HOME)\n");
    else if (streq(c, "pwd")) sh_write((int)"usage: pwd\n");
    else if (streq(c, "lcd")) sh_write((int)"usage: lcd [dir]   (change the REAL Windows directory; bypasses the virtual FS)\n");
    else if (streq(c, "lpwd")) sh_write((int)"usage: lpwd   (print the REAL Windows working directory)\n");
    else if (streq(c, "lls")) sh_write((int)"usage: lls [-l] [-a] [path]   (list a REAL Windows directory)\n");
    else if (streq(c, "vfs")) sh_write((int)"usage: vfs on [DIR] | off | status   (virtual filesystem; mounts are the home/bin/etc/... shell vars)\n");
    else if (streq(c, "echo")) sh_write((int)"usage: echo [args...]\n");
    else if (streq(c, "export")) sh_write((int)"usage: export NAME[=value]...\n");
    else if (streq(c, "set")) sh_write((int)"usage: set   (list shell variables)\n");
    else if (streq(c, "alias")) sh_write((int)"usage: alias [name='value']   (no arg lists aliases)\n");
    else if (streq(c, "unalias")) sh_write((int)"usage: unalias name...\n");
    else if (streq(c, "source") || streq(c, ".")) sh_write((int)"usage: source FILE   (run commands from FILE)\n");
    else if (streq(c, "jobs")) sh_write((int)"usage: jobs   (list background jobs)\n");
    else if (streq(c, "push")) sh_write((int)"usage: push <directory>   (cd there, remembering the current dir)\n");
    else if (streq(c, "pop")) sh_write((int)"usage: pop   (return to the directory saved by the last push)\n");
    else if (streq(c, "make")) sh_write((int)"usage: make [-f file] [VAR=val...] [target]\n");
    else if (streq(c, "vi")) sh_write((int)"usage: vi <file>   (modal editor: i/a/o insert, ESC normal, :w :q :wq, / search, u undo, dd/yy/p, :syntax on/off)\n");
    else if (streq(c, "xeyes")) sh_write((int)"usage: xeyes   (open the eyes-follow-the-mouse demo in a graphics window)\n");
    else if (streq(c, "gfx")) sh_write((int)"usage: gfx <program>   (run out\\<program>.dll in a graphics window)\n");
    else if (streq(c, "exit")) sh_write((int)"usage: exit [code]\n");
    else if (streq(c, "help")) sh_write((int)"usage: help\n");
    else if (streq(c, "test") || streq(c, "[")) sh_write((int)"usage: test EXPR   ( -z -n  =  !=  -eq -ne -lt -gt -le -ge )\n");
    else if (streq(c, "ls")) sh_write((int)"usage: ls [-l] [-a] [path]\n");
    else if (streq(c, "cat")) sh_write((int)"usage: cat [file...]\n");
    else if (streq(c, "grep")) sh_write((int)"usage: grep [-i -v -n] pattern [file...]\n");
    else if (streq(c, "sort")) sh_write((int)"usage: sort [file]\n");
    else if (streq(c, "wc")) sh_write((int)"usage: wc [file...]\n");
    else if (streq(c, "head")) sh_write((int)"usage: head [-N] [file]\n");
    else if (streq(c, "tail")) sh_write((int)"usage: tail [-N] [file]\n");
    else if (streq(c, "cut")) sh_write((int)"usage: cut -d C -f N [file]\n");
    else if (streq(c, "paste")) sh_write((int)"usage: paste file...\n");
    else if (streq(c, "find")) sh_write((int)"usage: find [path] [-name glob]\n");
    else if (streq(c, "more")) sh_write((int)"usage: more [file]\n");
    else if (streq(c, "sed")) sh_write((int)"usage: sed [-n] 's/old/new/[g][p]' | '/pat/d' | '/pat/p'  [file]\n");
    else if (streq(c, "date")) sh_write((int)"usage: date [+FORMAT]   (%Y %m %d %H %M %S %A %B %a %b %j %p %y)\n");
    else if (streq(c, "time")) sh_write((int)"usage: time <command> [args...]   (report wall-clock time)\n");
    else if (streq(c, "bc")) sh_write((int)"usage: bc [expr]   (scientific calculator; REPL if no expression)\n");
    else if (streq(c, "man")) sh_write((int)"usage: man <name>   (page a language's reference doc, e.g. man pascal)\n");
    else if (streq(c, "ps")) sh_write((int)"usage: ps [-e]   (list shell jobs; -e also dumps the OS tasklist)\n");
    else if (streq(c, "cp")) sh_write((int)"usage: cp src dst\n");
    else if (streq(c, "mv")) sh_write((int)"usage: mv src dst\n");
    else if (streq(c, "rm")) sh_write((int)"usage: rm file...\n");
    else if (streq(c, "mkdir")) sh_write((int)"usage: mkdir dir...\n");
    else if (streq(c, "touch")) sh_write((int)"usage: touch file...\n");
    else if (streq(c, "ln")) sh_write((int)"usage: ln [-s] target linkname\n");
    else return 0;
    return 1;
}

int bi_unalias(int n, int *argv, int start)
{
    int i;
    for (i = start + 1; i < start + n; i++)
    {
        int k = findalias((char *)argv[i]);
        if (k >= 0) { int j; for (j = k; j < naliases - 1; j++) { strcpy(anames[j], anames[j + 1]); avals[j] = avals[j + 1]; } naliases--; }
    }
    return 0;
}
int bi_help(int n, int *argv, int start)
{
    sh_write((int)"ilsh built-in commands:\n");
    sh_write((int)"  shell:   cd push pop pwd echo export set alias unalias source . jobs help exit true false test [\n");
    sh_write((int)"  files:   ls cat cp mv rm mkdir touch ln find\n");
    sh_write((int)"  vfs:     vfs on [DIR]/off/status  (virtual / + /home + /bin + /etc + /include + /lib + /tmp)\n");
    sh_write((int)"           lcd lpwd lls  reach the REAL Windows filesystem; --home DIR enables it at startup\n");
    sh_write((int)"  build:   make [-f file] [VAR=val] [target]\n");
    sh_write((int)"  text:    grep sort wc head tail cut paste more sed\n");
    sh_write((int)"  tools:   bc date time man ps\n");
    sh_write((int)"  syntax:  if/then/elif/else/fi  while/do/done  for X in .. do .. done\n");
    sh_write((int)"           pipes |   redirect > >> <   sequence ;   && ||   background &\n");
    sh_write((int)"  history: up/down arrows, !!  !n  !prefix\n");
    sh_write((int)"  vars:    NAME=value, $NAME, ${NAME}, $? ; 'set' lists them, PATH resolves commands\n");
    sh_write((int)"Type 'NAME -h' for usage of any built-in.\n");
    return 0;
}
/* push <dir>: remember the current directory, then cd to <dir>.  pop: return to it. */
int bi_push(int n, int *argv, int start)
{
    if (n < 2) { sh_write((int)"usage: push <directory>\n"); return 1; }
    char cwd[1024]; sh_cwd((int)cwd);
    if (sh_cd(argv[start + 1]) != 0) { sh_write((int)"push: "); sh_write(argv[start + 1]); sh_write((int)": no such directory\n"); return 1; }
    if (ndstack < 64) strcpy(dstack[ndstack++], cwd);
    sh_cwd((int)cwd); sh_write((int)cwd); sh_write((int)"\n");
    return 0;
}
int bi_pop(int n, int *argv, int start)
{
    if (ndstack == 0) { sh_write((int)"pop: directory stack is empty\n"); return 1; }
    ndstack--;
    sh_cd((int)dstack[ndstack]);
    char cwd[1024]; sh_cwd((int)cwd); sh_write((int)cwd); sh_write((int)"\n");
    return 0;
}

/* launch a graphics program (a compiled .dll) in the ilgfx window, detached */
int spawn_gfx(char *dllpath)
{
    char *repo = (char *)rt_repo();
    char exe[1100]; sprintf((int)exe, (int)"%s\\src\\ilgfx\\bin\\Release\\net10.0\\ilgfx.exe", (int)repo);
    if (!rt_exists((int)exe)) { sh_write((int)"gfx: ilgfx.exe not built (run build-all)\n"); return 1; }
    if (!rt_exists((int)dllpath)) { sh_write((int)"gfx: "); sh_write((int)dllpath); sh_write((int)": not found\n"); return 1; }
    int arr[2]; arr[0] = (int)exe; arr[1] = (int)dllpath;
    int pid = sh_run_bg((int)arr, 2);
    printf((int)"[gfx] pid %d\n", pid);
    return 0;
}
int bi_xeyes(void)
{
    char *repo = (char *)rt_repo();
    char dll[1100]; sprintf((int)dll, (int)"%s\\out\\xeyes.dll", (int)repo);
    return spawn_gfx(dll);
}
int bi_gfx(int n, int *argv, int start)
{
    if (n < 2) { sh_write((int)"usage: gfx <program>   (runs <repo>\\out\\<program>.dll in a window)\n"); return 1; }
    char *repo = (char *)rt_repo();
    char dll[1100]; sprintf((int)dll, (int)"%s\\out\\%s.dll", (int)repo, argv[start + 1]);
    return spawn_gfx(dll);
}

int u_more(int n, int *argv, int start);   /* defined in coreutils.c (later in the build) */

/* date [+FORMAT] — current date/time; FORMAT uses strftime-style %Y %m %d %H %M %S ... */
int bi_date(int n, int *argv, int start)
{
    char *fmt = 0;
    if (n > 1) { char *a = (char *)argv[start + 1]; if (a[0] == '+') fmt = a + 1; }
    sh_write((int)rt_datefmt(fmt ? (int)fmt : 0)); sh_write((int)"\n");
    return 0;
}
/* bc [expr] — run the bc calculator tool (REPL when given no expression) */
int bi_bc(int n, int *argv, int start)
{
    char *repo = (char *)rt_repo(); char exe[1100];
    sprintf((int)exe, (int)"%s\\out\\bc.exe", (int)repo);
    if (!rt_exists((int)exe)) { sh_write((int)"bc: out\\bc.exe not built (run build_all)\n"); return 1; }
    int *arr = (int *)malloc((n + 1) * 4); int j; arr[0] = (int)exe;
    for (j = 1; j < n; j++) arr[j] = argv[start + j];
    return sh_run((int)arr, n);
}
/* man NAME — page a language's reference doc (<repo>\NAME\NAME.md) through more */
int bi_man(int n, int *argv, int start)
{
    if (n < 2) { sh_write((int)"usage: man <name>   (e.g. man pascal, man lua, man shell)\n"); return 1; }
    char *nm = (char *)argv[start + 1]; char *repo = (char *)rt_repo(); char path[1100];
    sprintf((int)path, (int)"%s\\%s\\%s.md", (int)repo, nm, nm);
    if (!rt_exists((int)path))
    {
        if (streq(nm, "cpp") || streq(nm, "c++") || streq(nm, "tcpp")) sprintf((int)path, (int)"%s\\cpp\\tcpp.md", (int)repo);
        else if (streq(nm, "shell") || streq(nm, "ilsh")) sprintf((int)path, (int)"%s\\shell\\shell.md", (int)repo);
        else if (streq(nm, "fortran") || streq(nm, "f90")) sprintf((int)path, (int)"%s\\fortran\\fortran.md", (int)repo);
    }
    if (!rt_exists((int)path)) { sh_write((int)"man: no manual entry for "); sh_write((int)nm); sh_write((int)"\n"); return 1; }
    int marg[2]; marg[0] = (int)"more"; marg[1] = (int)path;
    return u_more(2, marg, 0);
}
/* ps [-e] — list shell-started background jobs; -e also dumps the OS tasklist */
int bi_ps(int n, int *argv, int start)
{
    int all = 0; int i;
    for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (streq(a, "-e") || streq(a, "-a") || streq(a, "all")) all = 1; }
    sh_write((int)"-- shell jobs --\n");
    sh_jobs();
    if (all) { sh_write((int)"-- tasklist --\n"); sh_write((int)rt_tasklist()); }
    return 0;
}

int source_file(char *path)
{
    char *d = (char *)rt_slurp((int)vmap(path));
    if (d == 0) return 1;
    root = 0; yy_scan_string((int)d); yyparse(); exec(root);
    return last_status;
}
/* run a command string through the shell (used by `make` to execute recipes) */
int run_string(char *s)
{
    char *d = (char *)malloc(strlen(s) + 2);
    strcpy(d, s); strcat(d, "\n");          /* terminate so the parser reduces cleanly */
    sc_cmd = 1; sc_fname = 0; sc_needin = 0; /* reset lexer command-position state for the fresh scan */
    root = 0; yy_scan_string((int)d); yyparse(); exec(root);
    return last_status;
}

int run_command(int n, int *argv, int start)
{
    char *cmd = (char *)argv[start];

    /* -h / --help on any internal command prints its usage */
    {
        int hi;
        for (hi = start + 1; hi < start + n; hi++)
        {
            char *a = (char *)argv[hi];
            if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) { if (print_usage(cmd)) return 0; break; }
        }
    }
    if (strcmp(cmd, "help") == 0) return bi_help(n, argv, start);
    if (strcmp(cmd, "unalias") == 0) return bi_unalias(n, argv, start);
    if (strcmp(cmd, "jobs") == 0) { sh_jobs(); return 0; }
    if (strcmp(cmd, "push") == 0) return bi_push(n, argv, start);
    if (strcmp(cmd, "pop") == 0) return bi_pop(n, argv, start);
    if (strcmp(cmd, "make") == 0) return mk_main(n, argv, start);
    if (strcmp(cmd, "date") == 0) return bi_date(n, argv, start);
    if (strcmp(cmd, "bc") == 0) return bi_bc(n, argv, start);
    if (strcmp(cmd, "man") == 0) return bi_man(n, argv, start);
    if (strcmp(cmd, "ps") == 0) return bi_ps(n, argv, start);
    if (strcmp(cmd, "time") == 0)
    {
        if (n < 2) { sh_write((int)"usage: time <command> [args...]\n"); return 1; }
        long t0 = rt_epoch_ms();
        int st = run_command(n - 1, argv, start + 1);
        long ms = rt_epoch_ms() - t0; char b[64];
        sprintf((int)b, (int)"real\t%ld.%03lds\n", ms / 1000, ms % 1000);
        sh_write((int)b);
        return st;
    }
    if (strcmp(cmd, "vi") == 0) return vi_main(n, argv, start);
    if (strcmp(cmd, "xeyes") == 0) return bi_xeyes();
    if (strcmp(cmd, "gfx") == 0) return bi_gfx(n, argv, start);
    if (strcmp(cmd, "source") == 0 || strcmp(cmd, ".") == 0) { return (n > 1) ? source_file((char *)argv[start + 1]) : 1; }
    if (strcmp(cmd, "echo") == 0) return bi_echo(n, argv, start);
    if (strcmp(cmd, "cd") == 0) return bi_cd(n, argv, start);
    if (strcmp(cmd, "pwd") == 0) return bi_pwd();
    if (strcmp(cmd, "lcd") == 0) return bi_lcd(n, argv, start);
    if (strcmp(cmd, "lpwd") == 0) return bi_lpwd();
    if (strcmp(cmd, "lls") == 0) return bi_lls(n, argv, start);
    if (strcmp(cmd, "vfs") == 0) return bi_vfs(n, argv, start);
    if (strcmp(cmd, "export") == 0) return bi_export(n, argv, start);
    if (strcmp(cmd, "set") == 0) return bi_set();
    if (strcmp(cmd, "true") == 0) return 0;
    if (strcmp(cmd, "false") == 0) return 1;
    if (strcmp(cmd, "test") == 0) return bi_test(n, argv, start);
    if (strcmp(cmd, "[") == 0) return bi_test(n, argv, start);
    if (strcmp(cmd, "exit") == 0) { sh_end(); exit(n > 1 ? atoi((char *)argv[start + 1]) : last_status); }
    if (strcmp(cmd, "alias") == 0) return bi_alias(n, argv, start);
    int rr = util_dispatch(n, argv, start);
    if (rr != -12345) return rr;
    /* external: resolve via shell PATH, run (foreground) or launch (& background) */
    int *arr = (int *)malloc(n * 4); int j;
    arr[0] = (int)resolve_exec(cmd);
    for (j = 1; j < n; j++) { char *a = (char *)argv[start + j]; arr[j] = (g_vfs && a[0] == '/') ? (int)vmap(a) : (int)a; }
    if (g_bg) { int pid = sh_run_bg((int)arr, n); printf((int)"[bg] pid %d\n", pid); return 0; }
    return sh_run((int)arr, n);
}

/* ---- execution ---- */
int exec(int node);

int exec_simple(int node)
{
    struct Node *n = (struct Node *)node;
    int argv[256]; int argc = 0;
    int e = n->a;
    while (e)
    {
        struct Node *en = (struct Node *)e;
        if (en->a == 0) argc = append_expanded((char *)en->b, argv, argc);
        else { char *t = vmap(expand((char *)en->b));
               if (en->a == 1) sh_rout((int)t, 0);
               else if (en->a == 2) sh_rout((int)t, 1);
               else sh_rin((int)t); }
        e = en->c;
    }
    int start = 0;
    while (start < argc && is_assign((char *)argv[start])) start++;
    int st = 0;
    if (start >= argc) { int i; for (i = 0; i < argc; i++) do_assign((char *)argv[i]); }
    else
    {
        int i; for (i = 0; i < start; i++) do_assign((char *)argv[i]);
        int ai = findalias((char *)argv[start]);
        if (ai >= 0)
        {
            /* one-level alias expansion: splice the alias words in place of the command word */
            int argv2[256]; int n2 = 0;
            for (i = 0; i < start; i++) argv2[n2++] = argv[i];
            int aw[64]; int naw = split_words((char *)avals[ai], aw, 64);
            for (i = 0; i < naw; i++) argv2[n2++] = aw[i];
            for (i = start + 1; i < argc; i++) argv2[n2++] = argv[i];
            st = run_command(n2 - start, argv2, start);
        }
        else st = run_command(argc - start, argv, start);
    }
    sh_end();
    last_status = st;
    return st;
}

int exec_pipe(int node)
{
    int stages[64]; int ns = 0;
    int cur = node;
    while (((struct Node *)cur)->kind == NPIPE) { stages[ns] = ((struct Node *)cur)->a; ns++; cur = ((struct Node *)cur)->b; }
    stages[ns] = cur; ns++;
    int i; int st = 0;
    for (i = 0; i < ns; i++)
    {
        sh_clear();
        if (i > 0) sh_pin();
        if (i < ns - 1) sh_pout();
        st = exec(stages[i]);
    }
    return st;
}

int exec_for(int node)
{
    struct Node *n = (struct Node *)node;
    char *var = (char *)n->a;       /* loop variable name (WORD) */
    int w = n->b;                   /* word list */
    int body = n->c; int st = 0;
    int items[1024]; int ni = 0;
    while (w) { struct Node *wn = (struct Node *)w; ni = append_expanded((char *)wn->b, items, ni); w = wn->c; }
    int i;
    for (i = 0; i < ni; i++) { setvar(var, (char *)items[i]); st = exec(body); }
    return st;
}

int exec(int node)
{
    if (node == 0) return 0;
    struct Node *n = (struct Node *)node;
    int k = n->kind;
    if (k == NSEQ) { exec(n->a); return exec(n->b); }
    if (k == NAND) { int s = exec(n->a); if (s == 0) s = exec(n->b); return s; }
    if (k == NOR) { int s = exec(n->a); if (s != 0) s = exec(n->b); return s; }
    if (k == NPIPE) return exec_pipe(node);
    if (k == NBG)   /* '&' : background a simple external command, else run inline */
    {
        struct Node *c = (struct Node *)n->a;
        if (c && c->kind == NSIMPLE) { g_bg = 1; int r = exec(n->a); g_bg = 0; return r; }
        return exec(n->a);
    }
    if (k == NIF) { if (exec(n->a) == 0) return exec(n->b); return exec(n->c); }
    if (k == NWHILE) { int s = 0; while (exec(n->a) == 0) s = exec(n->b); return s; }
    if (k == NFOR) return exec_for(node);
    if (k == NSIMPLE) return exec_simple(node);
    return 0;
}

/* incomplete input? (open quote or unbalanced if/while/for ... fi/done) */
int needs_more(char *buf)
{
    int depth = 0, q = 0, i = 0;
    while (buf[i])
    {
        int c = buf[i];
        if (q) { if (c == q) q = 0; i++; continue; }
        if (c == '\'' || c == '"') { q = c; i++; continue; }
        if (c == '#') { while (buf[i] && buf[i] != '\n') i++; continue; }
        if (isalpha(c))
        {
            char w[16]; int j = 0;
            while (buf[i] && (isalnum(buf[i]) || buf[i] == '_')) { if (j < 15) w[j++] = buf[i]; i++; }
            w[j] = 0;
            if (streq(w, "if") || streq(w, "while") || streq(w, "for")) depth++;
            else if (streq(w, "fi") || streq(w, "done")) depth--;
            continue;
        }
        i++;
    }
    return depth > 0 || q != 0;
}

/* ---- raw line editor with history (up/down recall, left/right/home/end) ---- */
void hist_add(char *s)
{
    if (s[0] == 0) return;
    char *c = (char *)strdup((int)s);
    int n = strlen(c); while (n > 0 && c[n - 1] == '\n') { c[n - 1] = 0; n--; }
    if (n == 0) return;
    if (nhist > 0 && strcmp((char *)hist[nhist - 1], c) == 0) return;
    if (nhist < 256) hist[nhist++] = (int)c;
}
void ledraw(char *prompt, char *buf, int len, int pos)
{
    printf("\r%s%s\x1b[K", (int)prompt, (int)buf);   /* CR, prompt, line, erase to EOL */
    int back = len - pos;
    if (back > 0) printf("\x1b[%dD", back);          /* move cursor left to pos */
}
int read_line(char *prompt, char *out, int max)
{
    int len = 0, pos = 0, hidx = nhist;
    out[0] = 0;
    ledraw(prompt, out, len, pos);
    while (1)
    {
        int k = rt_getkey();
        if (k == -100) return -1;                /* -100 = EOF (arrows are -1..-9) */
        if (k == 13) { putchar('\n'); out[len] = 0; return len; }
        if (k == 8) { if (pos > 0) { int i; for (i = pos - 1; i < len; i++) out[i] = out[i + 1]; len--; pos--; } }
        else if (k == -5) { if (pos < len) { int i; for (i = pos; i < len; i++) out[i] = out[i + 1]; len--; } }
        else if (k == -3) { if (pos > 0) pos--; }
        else if (k == -4) { if (pos < len) pos++; }
        else if (k == -6) pos = 0;
        else if (k == -7) pos = len;
        else if (k == -1) { if (hidx > 0) { hidx--; strcpy(out, (char *)hist[hidx]); len = strlen(out); pos = len; } }
        else if (k == -2) { if (hidx < nhist - 1) { hidx++; strcpy(out, (char *)hist[hidx]); } else { hidx = nhist; out[0] = 0; } len = strlen(out); pos = len; }
        else if (k >= 32 && k < 127) { if (len < max - 1) { int i; for (i = len; i > pos; i--) out[i] = out[i - 1]; out[pos] = k; len++; pos++; out[len] = 0; } }
        else continue;
        ledraw(prompt, out, len, pos);
    }
}
char *hist_expand(char *line)
{
    if (line[0] != '!') return line;
    if (line[1] == '!') return nhist > 0 ? (char *)hist[nhist - 1] : line;
    if (line[1] >= '0' && line[1] <= '9') { int idx = atoi(line + 1); return (idx >= 1 && idx <= nhist) ? (char *)hist[idx - 1] : line; }
    int i; for (i = nhist - 1; i >= 0; i--) if (strncmp((char *)hist[i], line + 1, strlen(line + 1)) == 0) return (char *)hist[i];
    return line;
}

void repl(void)
{
    char line[4096]; char acc[16384]; char prompt[1200]; char cwd[1024];
    acc[0] = 0;
    while (1)
    {
        if (acc[0] == 0) { if (g_vfs) strcpy(cwd, g_vcwd); else sh_cwd((int)cwd); sprintf((int)prompt, (int)"\x1b[36m%s\x1b[0m $ ", (int)cwd); }
        else strcpy(prompt, "> ");
        int r = read_line(prompt, line, 4096);
        if (r < 0) { putchar('\n'); break; }
        char *ex = hist_expand(line);
        if (ex != line) { strcpy(line, ex); printf("%s\n", (int)line); }
        strcat(acc, line); strcat(acc, "\n");
        if (needs_more(acc)) continue;
        hist_add(acc);
        root = 0;
        yy_scan_string((int)acc);
        yyparse();
        exec(root);
        acc[0] = 0;
    }
}

/* bootstrap HOME/PATH as shell variables from %APPDATA%\ilsh\appsettings.json */
void sh_init(void)
{
    setvar("HOME", (char *)rt_home());
    int ps = rt_setting((int)"path");
    setvar("PATH", ps ? (char *)ps : (char *)"C:\\Windows\\System32;C:\\Windows");
}

/* --home DIR on the command line turns the VFS on and points /home at DIR.
 * (Args arrive via rt_argv/rt_argc, populated by cc's emitted Main from the launcher.) */
void parse_args(int ac, int *av)
{
    int i;
    for (i = 1; i < ac; i++)
    {
        char *a = (char *)av[i];
        if (strcmp(a, "--home") == 0 && i + 1 < ac)
        {
            vfs_mounts_init(); vfs_defaults((char *)av[++i]);
            g_vfs = 1; strcpy(g_vcwd, "/home");
        }
        else if (strncmp(a, "--home=", 7) == 0)
        {
            vfs_mounts_init(); vfs_defaults(a + 7);
            g_vfs = 1; strcpy(g_vcwd, "/home");
        }
    }
}

/* interactive (login) shell: start in the home directory and run its startup script.
 * .ilshellrc is the preferred config (run from /home, or ~ when the VFS is off); .bashrc
 * is still honored for backward compatibility. */
void sh_login(void)
{
    if (g_vfs) { char *real = vmap("/home"); sh_cd((int)real); }
    else sh_cd((int)getvar("HOME"));

    char *rcbase = g_vfs ? vmap("/home") : getvar("HOME");
    char rc[1100];
    sprintf((int)rc, (int)"%s\\.ilshellrc", (int)rcbase);
    if (rt_exists((int)rc)) { source_file(rc); return; }
    sprintf((int)rc, (int)"%s\\.bashrc", (int)rcbase);
    if (rt_exists((int)rc)) source_file(rc);
}

int main(int argc, char **argv)
{
    sh_init();
    parse_args(argc, (int *)argv);
    if (rt_isatty()) { sh_login(); repl(); return last_status; }
    yyparse();
    exec(root);
    return last_status;
}
