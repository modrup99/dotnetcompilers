/* coreutils.c — shell builtins for ilsh, compiled into the shell by cc.
 * They read input from pipe/redirect (rt_input) or file args (rt_slurp) and
 * write through sh_write, so they pipe and redirect like any command. */

int printf(int f, ...);

void o(char *s) { sh_write((int)s); }
void onl(void) { sh_write((int)"\n"); }
void onum(long v) { char b[32]; sprintf((int)b, (int)"%ld", v); sh_write((int)b); }
int  streq(char *a, char *b) { return strcmp(a, b) == 0; }

/* split a text buffer into lines (NUL-terminating each); fills starts[] with
 * char* addresses; returns line count. Mutates buf. */
int splitlines(char *buf, int *starts, int max)
{
    int n = 0, i = 0;
    if (buf[0]) starts[n++] = (int)buf;
    while (buf[i])
    {
        if (buf[i] == '\n') { buf[i] = 0; if (buf[i + 1] && n < max) starts[n++] = (int)(buf + i + 1); }
        i++;
    }
    return n;
}

char *get_input(void) { return (char *)rt_input(); }

/* ---- cat ---- */
int u_cat(int n, int *argv, int start)
{
    int i, any = 0;
    for (i = start + 1; i < start + n; i++)
    {
        char *f = (char *)argv[i];
        if (f[0] == '-' && f[1]) continue;
        any = 1;
        char *d = (char *)rt_slurp((int)f);
        if (d == 0) { o("cat: "); o(f); o(": cannot open\n"); continue; }
        o(d);
    }
    if (!any) o(get_input());
    return 0;
}

/* ---- ls [-l] [-a] [path] ---- */
int u_ls(int n, int *argv, int start)
{
    int lflag = 0, aflag = 0; char *path = 0; int i;
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i];
        if (a[0] == '-' && a[1]) { int j = 1; while (a[j]) { if (a[j] == 'l') lflag = 1; if (a[j] == 'a') aflag = 1; j++; } }
        else path = a;
    }
    if (path == 0) path = (char *)".";
    int cnt = rt_lsopen((int)path);
    if (cnt < 0) { o("ls: "); o(path); o(": no such file or directory\n"); return 1; }
    for (i = 0; i < cnt; i++)
    {
        char *nm = (char *)rt_lsname(i);
        if (!aflag && nm[0] == '.') continue;
        if (lflag)
        {
            char buf[24];
            o((char *)rt_lsmode(i)); o(" 1 user group ");
            sprintf((int)buf, (int)"%8ld", rt_lssize(i)); o(buf);
            o(" "); o((char *)rt_lsdate(i)); o(" "); o(nm); onl();
        }
        else { o(nm); o("  "); }
    }
    if (!lflag && cnt > 0) onl();
    return 0;
}

/* ---- grep [-i -v -n] pattern [files] ---- */
int contains_ci(char *hay, char *needle, int ci)
{
    if (!ci) return strstr(hay, needle) != 0;
    char lh[4096]; char ln[256]; int i = 0;
    while (hay[i] && i < 4095) { lh[i] = tolower(hay[i]); i++; } lh[i] = 0;
    i = 0; while (needle[i] && i < 255) { ln[i] = tolower(needle[i]); i++; } ln[i] = 0;
    return strstr(lh, ln) != 0;
}
int grep_buf(char *buf, char *pat, int iflag, int vflag, int nflag)
{
    int lines[20000]; int nl = splitlines(buf, lines, 20000); int i; int hits = 0;
    for (i = 0; i < nl; i++)
    {
        char *ln = (char *)lines[i];
        int m = contains_ci(ln, pat, iflag);
        if (m != vflag) { if (nflag) { onum(i + 1); o(":"); } o(ln); onl(); hits++; }
    }
    return hits;
}
int u_grep(int n, int *argv, int start)
{
    int iflag = 0, vflag = 0, nflag = 0; char *pat = 0; int files[64]; int nf = 0; int i;
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i];
        if (a[0] == '-' && a[1]) { int j = 1; while (a[j]) { if (a[j] == 'i') iflag = 1; if (a[j] == 'v') vflag = 1; if (a[j] == 'n') nflag = 1; j++; } }
        else if (pat == 0) pat = a; else files[nf++] = (int)a;
    }
    if (pat == 0) { o("usage: grep pattern [file...]\n"); return 2; }
    int hits = 0;
    if (nf == 0) hits = grep_buf(get_input(), pat, iflag, vflag, nflag);
    else for (i = 0; i < nf; i++) { char *d = (char *)rt_slurp(files[i]); if (d) hits += grep_buf(d, pat, iflag, vflag, nflag); }
    return hits > 0 ? 0 : 1;
}

/* ---- wc [files] ---- */
void wc_buf(char *d, char *name)
{
    int lines = 0, words = 0, chars = 0, inword = 0, i = 0;
    while (d[i]) { chars++; if (d[i] == '\n') lines++; if (d[i] == ' ' || d[i] == '\t' || d[i] == '\n') inword = 0; else { if (!inword) words++; inword = 1; } i++; }
    o(" "); onum(lines); o(" "); onum(words); o(" "); onum(chars); if (name) { o(" "); o(name); } onl();
}
int u_wc(int n, int *argv, int start)
{
    int i, any = 0;
    for (i = start + 1; i < start + n; i++) { char *f = (char *)argv[i]; if (f[0] == '-' && f[1]) continue; any = 1; char *d = (char *)rt_slurp((int)f); if (d) wc_buf(d, f); }
    if (!any) wc_buf(get_input(), 0);
    return 0;
}

/* ---- head / tail [-N] [file] ---- */
int u_headtail(int n, int *argv, int start, int tail)
{
    int count = 10; char *file = 0; int i;
    for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (a[0] == '-' && a[1]) count = atoi(a + 1); else file = a; }
    char *d = file ? (char *)rt_slurp((int)file) : get_input();
    if (d == 0) return 1;
    int lines[20000]; int nl = splitlines(d, lines, 20000);
    int lo = tail ? (nl - count) : 0; int hi = tail ? nl : count;
    if (lo < 0) lo = 0; if (hi > nl) hi = nl;
    for (i = lo; i < hi; i++) { o((char *)lines[i]); onl(); }
    return 0;
}

/* ---- sort [file] ---- */
int u_sort(int n, int *argv, int start)
{
    char *file = 0; int i;
    for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (!(a[0] == '-' && a[1])) file = a; }
    char *d = file ? (char *)rt_slurp((int)file) : get_input();
    if (d == 0) return 1;
    int lines[20000]; int nl = splitlines(d, lines, 20000);
    int a2, b2;
    for (a2 = 1; a2 < nl; a2++) { int v = lines[a2]; b2 = a2 - 1; while (b2 >= 0 && strcmp((char *)lines[b2], (char *)v) > 0) { lines[b2 + 1] = lines[b2]; b2--; } lines[b2 + 1] = v; }
    for (i = 0; i < nl; i++) { o((char *)lines[i]); onl(); }
    return 0;
}

/* ---- cut -d C -f N [file] ---- */
int u_cut(int n, int *argv, int start)
{
    int delim = 9; int field = 1; char *file = 0; int i;
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i];
        if (streq(a, "-d") && i + 1 < start + n) { delim = ((char *)argv[++i])[0]; }
        else if (streq(a, "-f") && i + 1 < start + n) { field = atoi((char *)argv[++i]); }
        else if (a[0] != '-') file = a;
    }
    char *d = file ? (char *)rt_slurp((int)file) : get_input();
    if (d == 0) return 1;
    int lines[20000]; int nl = splitlines(d, lines, 20000);
    for (i = 0; i < nl; i++)
    {
        char *ln = (char *)lines[i]; int fld = 1; int j = 0; int startj = 0;
        while (1)
        {
            if (ln[j] == delim || ln[j] == 0)
            {
                if (fld == field) { int k; for (k = startj; k < j; k++) { char c[2]; c[0] = ln[k]; c[1] = 0; o(c); } onl(); break; }
                if (ln[j] == 0) { onl(); break; }
                fld++; startj = j + 1;
            }
            j++;
        }
    }
    return 0;
}

/* ---- paste file1 file2 ... (tab-join line by line) ---- */
int u_paste(int n, int *argv, int start)
{
    int files[16]; int nf = 0; int i;
    for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (a[0] != '-') files[nf++] = (int)a; }
    int starts[16]; int counts[16]; int bufs[16];
    int maxl = 0;
    for (i = 0; i < nf; i++) { char *d = (char *)rt_slurp(files[i]); bufs[i] = (int)d; int *ls = (int *)malloc(20000 * 4); counts[i] = d ? splitlines(d, ls, 20000) : 0; starts[i] = (int)ls; if (counts[i] > maxl) maxl = counts[i]; }
    int r;
    for (r = 0; r < maxl; r++)
    {
        for (i = 0; i < nf; i++) { if (i) o("\t"); int *ls = (int *)starts[i]; if (r < counts[i]) o((char *)ls[r]); }
        onl();
    }
    return 0;
}

/* ---- find [path] [-name pat] ---- */
int u_find(int n, int *argv, int start)
{
    char *path = (char *)"."; char *pat = 0; int i;
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i];
        if (streq(a, "-name") && i + 1 < start + n) pat = (char *)argv[++i];
        else if (a[0] != '-') path = a;
    }
    int cnt = rt_find((int)path, pat ? (int)pat : 0);
    for (i = 0; i < cnt; i++) { o((char *)rt_findname(i)); onl(); }
    return 0;
}

/* ---- file ops ---- */
int u_cp(int n, int *argv, int start) { if (n < 3) return 1; return rt_copy(argv[start + 1], argv[start + 2]); }
int u_mv(int n, int *argv, int start) { if (n < 3) return 1; return rt_move(argv[start + 1], argv[start + 2]); }
int u_rm(int n, int *argv, int start) { int i, r = 0; for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (a[0] == '-') continue; if (rt_remove((int)a)) r = 1; } return r; }
int u_mkdir(int n, int *argv, int start) { int i, r = 0; for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (a[0] == '-') continue; if (rt_mkdir((int)a)) r = 1; } return r; }
int u_touch(int n, int *argv, int start) { int i, r = 0; for (i = start + 1; i < start + n; i++) if (rt_touch(argv[i])) r = 1; return r; }
int u_ln(int n, int *argv, int start)
{
    int sym = 0; int a1 = 0, a2 = 0; int i;
    for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (streq(a, "-s")) sym = 1; else if (a1 == 0) a1 = (int)a; else a2 = (int)a; }
    if (a1 == 0 || a2 == 0) return 1;
    return rt_link(a1, a2, sym);
}

/* ---- more (paginate) ---- */
int u_more(int n, int *argv, int start)
{
    char *file = 0; int i;
    for (i = start + 1; i < start + n; i++) { char *a = (char *)argv[i]; if (a[0] != '-') file = a; }
    char *d = file ? (char *)rt_slurp((int)file) : get_input();
    if (d == 0) return 1;
    int lines[20000]; int nl = splitlines(d, lines, 20000);
    int tty = rt_isatty();
    int rows = rt_rows() - 1; if (rows < 2) rows = 23;
    int shown = 0;
    for (i = 0; i < nl; i++)
    {
        o((char *)lines[i]); onl(); shown++;
        if (tty && shown >= rows && i + 1 < nl)   /* only paginate at a real terminal */
        {
            o("--More--"); int k = rt_getkey(); o("\r        \r");
            if (k == 'q' || k == 27 || k < 0) break;
            shown = (k == 13) ? rows - 1 : 0;   /* Enter = one line, else page */
        }
    }
    return 0;
}

/* dispatch: returns -12345 if cmd is not a coreutil */
int util_dispatch(int n, int *argv, int start)
{
    char *c = (char *)argv[start];
    if (streq(c, "cat")) return u_cat(n, argv, start);
    if (streq(c, "ls")) return u_ls(n, argv, start);
    if (streq(c, "grep")) return u_grep(n, argv, start);
    if (streq(c, "wc")) return u_wc(n, argv, start);
    if (streq(c, "head")) return u_headtail(n, argv, start, 0);
    if (streq(c, "tail")) return u_headtail(n, argv, start, 1);
    if (streq(c, "sort")) return u_sort(n, argv, start);
    if (streq(c, "cut")) return u_cut(n, argv, start);
    if (streq(c, "paste")) return u_paste(n, argv, start);
    if (streq(c, "find")) return u_find(n, argv, start);
    if (streq(c, "cp")) return u_cp(n, argv, start);
    if (streq(c, "mv")) return u_mv(n, argv, start);
    if (streq(c, "rm")) return u_rm(n, argv, start);
    if (streq(c, "mkdir")) return u_mkdir(n, argv, start);
    if (streq(c, "touch")) return u_touch(n, argv, start);
    if (streq(c, "ln")) return u_ln(n, argv, start);
    if (streq(c, "more")) return u_more(n, argv, start);
    return -12345;
}
