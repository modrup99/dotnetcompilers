/* make.c — a small `make`, compiled into ilsh. Parses a Makefile (variables,
 * rules, recipes), builds the goal by walking prerequisites and comparing
 * timestamps (rt_mtime), and runs recipe lines through the shell (run_string).
 * Supports $(VAR)/${VAR}, automatic vars $@ $< $^, += and := , @ (silent) and
 * - (ignore-error) recipe prefixes, -f, and VAR=val overrides. */

int run_string(char *s);   /* from shell.y */

char mk_vn[128][64]; int mk_vv[128]; int mk_nv;          /* variables (vv = strdup addrs) */
char mk_tgt[128][128]; char mk_pre[128][1024];           /* rule target + prereq string */
int  mk_rec[128][32]; int mk_recn[128]; int mk_nr;       /* recipe lines (strdup addrs) */
int  mk_done[128];                                       /* built this run */
int  mk_built_any;

int  mk_find(char *nm) { int i; for (i = 0; i < mk_nv; i++) if (strcmp(mk_vn[i], nm) == 0) return i; return -1; }
void mk_set(char *nm, char *val) { int k = mk_find(nm); if (k < 0) { k = mk_nv; mk_nv = mk_nv + 1; strcpy(mk_vn[k], nm); } mk_vv[k] = strdup(val); }
char *mk_get(char *nm) { int k = mk_find(nm); return k >= 0 ? (char *)mk_vv[k] : 0; }

void mk_app(char *out, int *oi, char *s) { int k = 0; while (s[k]) { out[*oi] = s[k]; *oi = *oi + 1; k++; } }

/* expand $(VAR) ${VAR} $@ $< $^ $$ in s */
char *mk_expand(char *s, char *tgt, char *first, char *all)
{
    char *out = (char *)malloc(2048); int oi = 0; int i = 0;
    while (s[i])
    {
        if (s[i] == '$')
        {
            char c = s[i + 1];
            if (c == '$') { out[oi++] = '$'; i += 2; continue; }
            if (c == '@') { mk_app(out, &oi, tgt); i += 2; continue; }
            if (c == '<') { mk_app(out, &oi, first); i += 2; continue; }
            if (c == '^') { mk_app(out, &oi, all); i += 2; continue; }
            if (c == '(' || c == '{')
            {
                char close = (c == '(') ? ')' : '}';
                int j = i + 2; char nm[64]; int ni = 0;
                while (s[j] && s[j] != close) { if (ni < 63) nm[ni++] = s[j]; j++; }
                nm[ni] = 0; if (s[j] == close) j++;
                char *v = mk_get(nm); if (v) mk_app(out, &oi, v);
                i = j; continue;
            }
            out[oi++] = '$'; i++; continue;
        }
        out[oi++] = s[i++];
    }
    out[oi] = 0;
    return out;
}

int mk_split(char *s, int *words, int max)
{
    char *c = (char *)strdup((int)s); int n = 0, i = 0, inw = 0;
    while (c[i]) { if (c[i] == ' ' || c[i] == '\t') { c[i] = 0; inw = 0; } else { if (!inw && n < max) words[n++] = (int)(c + i); inw = 1; } i++; }
    return n;
}

void mk_parse(char *buf)
{
    int i = 0, cur = -1;
    while (buf[i])
    {
        char line[2048]; int li = 0;
        while (buf[i] && buf[i] != '\n')
        {
            if (buf[i] == '\\' && buf[i + 1] == '\n') { line[li++] = ' '; i += 2; continue; }
            if (buf[i] == '\r') { i++; continue; }
            line[li++] = buf[i++];
        }
        if (buf[i] == '\n') i++;
        line[li] = 0;

        if (line[0] == '\t') { if (cur >= 0 && mk_recn[cur] < 32) mk_rec[cur][mk_recn[cur]++] = strdup(line + 1); continue; }

        int k = 0; while (line[k]) { if (line[k] == '#') { line[k] = 0; break; } k++; }
        k = strlen(line); while (k > 0 && (line[k - 1] == ' ' || line[k - 1] == '\t')) { line[k - 1] = 0; k--; }
        if (line[0] == 0) { cur = -1; continue; }

        int eq = -1, col = -1;
        for (k = 0; line[k]; k++)
        {
            if (line[k] == '=' && eq < 0) eq = k;
            if (line[k] == ':' && col < 0 && line[k + 1] != '=') col = k;
        }
        if (eq >= 0 && (col < 0 || eq < col))
        {
            char name[64]; int ni = 0, j = 0;
            while (j < eq && (line[j] == ' ' || line[j] == '\t')) j++;
            while (j < eq && (isalnum(line[j]) || line[j] == '_')) name[ni++] = line[j++];
            name[ni] = 0;
            char *val = line + eq + 1; while (*val == ' ' || *val == '\t') val++;
            if (eq > 0 && line[eq - 1] == '+') { char *old = mk_get(name); char comb[2048]; sprintf((int)comb, (int)"%s %s", old ? (int)old : (int)"", (int)val); mk_set(name, comb); }
            else mk_set(name, val);
            cur = -1; continue;
        }
        if (col >= 0)
        {
            char tgt[128]; int ti = 0, j = 0;
            while (j < col && line[j] == ' ') j++;
            while (j < col && line[j] != ' ') tgt[ti++] = line[j++];
            tgt[ti] = 0;
            char *pre = line + col + 1; while (*pre == ' ') pre++;
            char *et = mk_expand(tgt, (char *)"", (char *)"", (char *)"");   /* expand $(VAR) in target */
            cur = mk_nr++; strcpy(mk_tgt[cur], et); strcpy(mk_pre[cur], pre); mk_recn[cur] = 0;
            continue;
        }
        cur = -1;
    }
}

int mk_rule(char *target) { int i; for (i = 0; i < mk_nr; i++) if (strcmp(mk_tgt[i], target) == 0) return i; return -1; }

int mk_build(char *target)
{
    int ri = mk_rule(target);
    if (ri < 0)
    {
        if (rt_exists((int)target)) return 0;
        o("make: no rule to make target '"); o(target); o("'\n"); return 1;
    }
    if (mk_done[ri]) return 0;
    mk_done[ri] = 1;

    char *pre = mk_expand(mk_pre[ri], target, (char *)"", (char *)"");
    int words[64]; int nw = mk_split(pre, words, 64);
    int i;
    for (i = 0; i < nw; i++) if (mk_build((char *)words[i])) return 1;

    long tmt = rt_mtime((int)target);
    int need = (tmt < 0);
    if (!need) for (i = 0; i < nw; i++) { long pmt = rt_mtime(words[i]); if (pmt > tmt) { need = 1; break; } }
    if (!need) return 0;

    char *first = (char *)(nw > 0 ? words[0] : (int)(char *)"");
    int r;
    for (r = 0; r < mk_recn[ri]; r++)
    {
        char *line = (char *)mk_rec[ri][r];
        int silent = 0, ignore = 0;
        while (line[0] == '@' || line[0] == '-') { if (line[0] == '@') silent = 1; else ignore = 1; line++; }
        char *cmd = mk_expand(line, target, first, pre);
        if (cmd[0] == 0) continue;
        if (!silent) { o(cmd); o("\n"); }
        mk_built_any = 1;
        int st = run_string(cmd);
        if (st != 0 && !ignore) { o("make: *** ["); o(target); o("] error "); onum(st); o("\n"); return 1; }
    }
    return 0;
}

int mk_main(int n, int *argv, int start)
{
    mk_nv = 0; mk_nr = 0; mk_built_any = 0;
    int i; for (i = 0; i < 128; i++) mk_done[i] = 0;

    char *goal = 0; char *mfname = 0;
    int ovn[32]; int ovv[32]; int nov = 0;       /* command-line VAR=val overrides */
    for (i = start + 1; i < start + n; i++)
    {
        char *a = (char *)argv[i];
        if (strcmp(a, "-f") == 0 && i + 1 < start + n) mfname = (char *)argv[++i];
        else if (strchr((int)a, '=') && nov < 32)
        {
            char *eq = (char *)strchr((int)a, '=');
            int len = (int)eq - (int)a; char *nm = (char *)malloc(len + 1);
            int j; for (j = 0; j < len; j++) nm[j] = a[j]; nm[j] = 0;
            ovn[nov] = (int)nm; ovv[nov] = (int)(eq + 1); nov++;
        }
        else goal = a;
    }

    char *buf = 0;
    if (mfname) buf = (char *)rt_slurp((int)mfname);
    else if (rt_exists((int)"Makefile")) buf = (char *)rt_slurp((int)"Makefile");
    else if (rt_exists((int)"makefile")) buf = (char *)rt_slurp((int)"makefile");
    if (buf == 0) { o("make: no Makefile found\n"); return 1; }

    mk_parse(buf);
    for (i = 0; i < nov; i++) mk_set((char *)ovn[i], (char *)ovv[i]);   /* overrides win */

    if (goal == 0) { if (mk_nr > 0) goal = mk_tgt[0]; else { o("make: no targets\n"); return 1; } }
    int rc = mk_build(goal);
    if (rc == 0 && !mk_built_any) { o("make: '"); o(goal); o("' is up to date\n"); }
    return rc;
}
