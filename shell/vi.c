/* vi.c — a non-minimal vi, compiled into ilsh.  Modal editing (normal/insert/
 * ex command line), counts, motions (h j k l w b e 0 ^ $ gg G H M L, page),
 * operators (d c y with motions, dd cc yy x X D J r ~ o O i a A I p P), search
 * (/ ? n N), multi-level undo (u), and ex commands (:w :q :wq :q! :w file :N
 * :%s/a/b/ :set nu).  Renders through the terminal (rt_clear/rt_gotoxy/output),
 * reads keys via rt_getkey — so it runs in the ilterm window or any ANSI console. */

#define VMAXLN 8000
#define VUNDO  32

char *vln[VMAXLN]; int vnl;            /* buffer: vnl lines, each strdup'd */
int vtop, vcy, vcx;                    /* viewport top, cursor line/col */
int vmode;                             /* 0 normal, 1 insert, 2 cmdline */
char vfile[1024]; int vdirty; int vquit;
int vshownum;
char vcmd[256]; int vcmdlen;
char vmsg[256];                        /* status message */
char *vyank[VMAXLN]; int vynl; int vylinewise;
char vsearch[256];
int vpend;                             /* pending operator: 'd','c','y' or 0 */
int vcount;                            /* numeric count being typed */

/* undo stack: each entry is a deep copy of the buffer + cursor */
int u_ln[VUNDO][VMAXLN]; int u_nl[VUNDO]; int u_cy[VUNDO]; int u_cx[VUNDO]; int u_sp;

int vmax(int a, int b) { return a > b ? a : b; }
int vmin(int a, int b) { return a < b ? a : b; }

void vfree_line(int i) { /* lines are arena-allocated; we just drop the reference */ }

char *vdup(char *s) { return (char *)strdup((int)s); }
char *vempty(void) { char *e = (char *)malloc(1); e[0] = 0; return e; }

/* ---- undo ---- */
void vpush_undo(void)
{
    int slot = u_sp % VUNDO; u_sp++;
    u_nl[slot] = vnl; u_cy[slot] = vcy; u_cx[slot] = vcx;
    int i; for (i = 0; i < vnl; i++) u_ln[slot][i] = (int)vdup(vln[i]);
}
void vundo(void)
{
    if (u_sp == 0) { strcpy(vmsg, "Already at oldest change"); return; }
    u_sp--; int slot = u_sp % VUNDO;
    vnl = u_nl[slot];
    int i; for (i = 0; i < vnl; i++) vln[i] = (char *)u_ln[slot][i];
    vcy = u_cy[slot]; vcx = u_cx[slot];
    vdirty = 1; strcpy(vmsg, "undo");
}

/* ---- file load / save ---- */
void vi_load(char *path)
{
    vnl = 0;
    char *d = (char *)rt_slurp((int)path);
    if (d == 0) { vln[vnl++] = vempty(); return; }
    int i = 0; int start = 0;
    while (1)
    {
        if (d[i] == '\n' || d[i] == 0)
        {
            int len = i - start;
            char *ln = (char *)malloc(len + 1);
            int k; for (k = 0; k < len; k++) ln[k] = d[start + k];
            if (len > 0 && ln[len - 1] == '\r') len--;     /* strip CR */
            ln[len] = 0;
            if (vnl < VMAXLN) vln[vnl++] = ln;
            if (d[i] == 0) break;
            start = i + 1;
        }
        i++;
    }
    if (vnl == 0) vln[vnl++] = vempty();
}
int vi_save(char *path)
{
    /* build the whole text then write via the shell's > redirection is awkward;
     * write directly through a temp using fopen-style libc */
    int fh = fopen((int)path, (int)"w");
    if (fh == 0) { strcpy(vmsg, "write error"); return 1; }
    int i; for (i = 0; i < vnl; i++) { fputs((int)vln[i], fh); fputc('\n', fh); }
    fclose(fh);
    vdirty = 0;
    sprintf((int)vmsg, (int)"\"%s\" %dL written", (int)path, vnl);
    return 0;
}

/* ---- syntax highlighting ----
 * A line tokenizer that emits ANSI SGR color (the ilterm grid and any VT console render
 * it).  C-style comments/strings/numbers/preprocessor plus a keyword table chosen by file
 * extension.  Block-comment state is carried across lines via *incmt.  Toggle with
 * `:syntax on` / `:syntax off`. */
void vout(char *s);     /* defined just below */
int vsyntax;            /* 1 = highlight (default on) */
char *g_kw;             /* space-delimited keyword set for the current file type */
char *VKW_C   = " auto break case char const continue default do double else enum extern float for goto if int long register return short signed sizeof static struct switch typedef union unsigned void volatile while ";
char *VKW_PAS = " and array begin case const div do downto else end file for function goto if in label mod nil not of or packed procedure program record repeat set then to type until var while with ";
char *VKW_LUA = " and break do else elseif end false for function goto if in local nil not or repeat return then true until while ";

int vi_iskw(char *s, int from, int to)
{
    int len = to - from; if (len <= 0 || len > 20) return 0;
    char w[24]; w[0] = ' '; int k; for (k = 0; k < len; k++) w[k + 1] = s[from + k]; w[len + 1] = ' '; w[len + 2] = 0;
    return strstr((int)g_kw, (int)w) != 0;
}

/* block-comment state entering line `upto` (scans /* *​/, skipping strings and // ) */
int vi_cmt_state_at(int upto)
{
    int in = 0, i;
    for (i = 0; i < upto && i < vnl; i++)
    {
        char *s = vln[i]; int j = 0;
        while (s[j])
        {
            if (in) { if (s[j] == '*' && s[j + 1] == '/') { in = 0; j += 2; continue; } j++; }
            else if (s[j] == '/' && s[j + 1] == '/') break;
            else if (s[j] == '/' && s[j + 1] == '*') { in = 1; j += 2; }
            else if (s[j] == '"' || s[j] == 39) { int q = s[j]; j++; while (s[j] && s[j] != q) { if (s[j] == '\\' && s[j + 1]) j++; j++; } if (s[j]) j++; }
            else j++;
        }
    }
    return in;
}

char hlbuf[16384]; int hloi; int hlvis; int hlavail;
void hl_e(char *esc) { if (hlvis >= hlavail || hloi > 16000) return; int k = 0; while (esc[k]) hlbuf[hloi++] = esc[k++]; }   /* color code: no visible width */
int  hl_c(int c) { if (hlvis >= hlavail || hloi > 16000) return 0; hlbuf[hloi++] = (char)c; hlvis++; return 1; }            /* visible char (capped) */

/* emit one highlighted line (capped to `avail` visible columns); update *incmt */
void vi_hl_line(char *s, int avail, int *incmt)
{
    hloi = 0; hlvis = 0; hlavail = avail;
    int i = 0, len = strlen(s);
    int j = 0; while (s[j] == ' ' || s[j] == '\t') j++;
    if (!*incmt && s[j] == '#') { hl_e("\x1b[33m"); while (i < len) { hl_c(s[i]); i++; } hl_e("\x1b[0m"); hlbuf[hloi] = 0; vout(hlbuf); return; }
    while (i < len)
    {
        if (*incmt)
        {
            hl_e("\x1b[90m");
            while (i < len) { if (s[i] == '*' && s[i + 1] == '/') { hl_c('*'); hl_c('/'); i += 2; *incmt = 0; break; } hl_c(s[i]); i++; }
            hl_e("\x1b[0m"); continue;
        }
        int c = s[i];
        if (c == '/' && s[i + 1] == '/') { hl_e("\x1b[90m"); while (i < len) { hl_c(s[i]); i++; } hl_e("\x1b[0m"); break; }
        if (c == '/' && s[i + 1] == '*') { hl_e("\x1b[90m"); hl_c('/'); hl_c('*'); i += 2; *incmt = 1; continue; }
        if (c == '"' || c == 39)
        {
            int q = c; hl_e("\x1b[32m"); hl_c(c); i++;
            while (i < len) { if (s[i] == '\\' && s[i + 1]) { hl_c(s[i]); i++; hl_c(s[i]); i++; continue; } if (s[i] == q) { hl_c(s[i]); i++; break; } hl_c(s[i]); i++; }
            hl_e("\x1b[0m"); continue;
        }
        if (c >= '0' && c <= '9') { hl_e("\x1b[36m"); while (i < len && (isalnum(s[i]) || s[i] == '.')) { hl_c(s[i]); i++; } hl_e("\x1b[0m"); continue; }
        if (isalpha(c) || c == '_')
        {
            int from = i; while (i < len && (isalnum(s[i]) || s[i] == '_')) i++;
            int kw = vi_iskw(s, from, i);
            if (kw) hl_e("\x1b[1;35m");
            int p; for (p = from; p < i; p++) hl_c(s[p]);
            if (kw) hl_e("\x1b[0m");
            continue;
        }
        hl_c(c); i++;
    }
    if (hloi <= 16000) { hlbuf[hloi++] = 27; hlbuf[hloi++] = '['; hlbuf[hloi++] = '0'; hlbuf[hloi++] = 'm'; }   /* final reset */
    hlbuf[hloi] = 0; vout(hlbuf);
}

/* ---- rendering ---- */
void vout(char *s) { sh_write((int)s); }
void vclampx(void)
{
    int len = strlen(vln[vcy]);
    int maxc = (vmode == 1) ? len : (len > 0 ? len - 1 : 0);
    if (vcx > maxc) vcx = maxc;
    if (vcx < 0) vcx = 0;
}
void vscroll(void)
{
    int rows = rt_rows() - 1;
    if (vcy < vtop) vtop = vcy;
    if (vcy >= vtop + rows) vtop = vcy - rows + 1;
    if (vtop < 0) vtop = 0;
}
void vi_render(void)
{
    int rows = rt_rows(); int cols = rt_cols();
    int textrows = rows - 1;
    int numw = vshownum ? 5 : 0;
    vscroll();
    rt_clear();
    int i;
    int incmt = vsyntax ? vi_cmt_state_at(vtop) : 0;   /* block-comment carry for the first visible line */
    for (i = 0; i < textrows; i++)
    {
        int ln = vtop + i;
        rt_gotoxy(0, i);
        if (ln < vnl)
        {
            if (vshownum) { char nb[8]; sprintf((int)nb, (int)"%4d ", ln + 1); vout(nb); }
            char *s = vln[ln]; int sl = strlen(s); int avail = cols - numw;
            if (vsyntax) vi_hl_line(s, avail, &incmt);    /* updates incmt for the next line */
            else if (sl <= avail) vout(s);
            else { char *t = (char *)malloc(avail + 1); int k; for (k = 0; k < avail; k++) t[k] = s[k]; t[avail] = 0; vout(t); }
        }
        else vout("~");
    }
    rt_gotoxy(0, rows - 1);
    if (vmode == 2) { char cb[300]; sprintf((int)cb, (int)":%s", (int)vcmd); vout(cb); }
    else
    {
        char st[400];
        sprintf((int)st, (int)"%s%s  %d,%d  %s", (int)vfile, vdirty ? (int)" [+]" : (int)"",
                vcy + 1, vcx + 1, (int)(vmode == 1 ? "-- INSERT --" : vmsg));
        vout(st);
    }
    if (vmode != 2) rt_gotoxy(vcx - 0 + numw, vcy - vtop);
}

/* ---- motions ---- */
int visword(int c) { return isalnum(c) || c == '_'; }
void vmove_word_fwd(void)
{
    char *s = vln[vcy]; int len = strlen(s);
    if (vcx < len && visword(s[vcx])) { while (vcx < len && visword(s[vcx])) vcx++; }
    else if (vcx < len) { while (vcx < len && !visword(s[vcx]) && s[vcx] != ' ') vcx++; }
    while (vcx < len && s[vcx] == ' ') vcx++;
    if (vcx >= len && vcy < vnl - 1) { vcy++; vcx = 0; char *n = vln[vcy]; while (n[vcx] == ' ') vcx++; }
}
void vmove_word_back(void)
{
    if (vcx == 0 && vcy > 0) { vcy--; vcx = strlen(vln[vcy]); }
    char *s = vln[vcy];
    if (vcx > 0) vcx--;
    while (vcx > 0 && s[vcx] == ' ') vcx--;
    while (vcx > 0 && visword(s[vcx - 1])) vcx--;
}

/* ---- editing ---- */
void vins_line(int at, char *s) { int i; for (i = vnl; i > at; i--) vln[i] = vln[i - 1]; vln[at] = s; vnl++; }
void vdel_line(int at)
{
    /* save to yank register (single line) */
    vynl = 0; vyank[vynl++] = vdup(vln[at]); vylinewise = 1;
    int i; for (i = at; i < vnl - 1; i++) vln[i] = vln[i + 1];
    vnl--; if (vnl == 0) vln[vnl++] = vempty();
    if (vcy >= vnl) vcy = vnl - 1;
}
void vsplit_line(void)   /* Enter in insert mode */
{
    char *s = vln[vcy]; int len = strlen(s);
    char *left = (char *)malloc(vcx + 1); int k; for (k = 0; k < vcx; k++) left[k] = s[k]; left[vcx] = 0;
    char *right = vdup(s + vcx);
    vln[vcy] = left; vins_line(vcy + 1, right);
    vcy++; vcx = 0;
}
void vins_char(int c)
{
    char *s = vln[vcy]; int len = strlen(s);
    char *n = (char *)malloc(len + 2);
    int k; for (k = 0; k < vcx; k++) n[k] = s[k];
    n[vcx] = (char)c;
    for (k = vcx; k < len; k++) n[k + 1] = s[k];
    n[len + 1] = 0;
    vln[vcy] = n; vcx++;
}
void vdel_char_at(int at)   /* delete char at column 'at' on current line */
{
    char *s = vln[vcy]; int len = strlen(s);
    if (at < 0 || at >= len) return;
    int k; for (k = at; k < len; k++) s[k] = s[k + 1];
}
void vbackspace(void)
{
    if (vcx > 0) { vcx--; vdel_char_at(vcx); }
    else if (vcy > 0)
    {
        char *prev = vln[vcy - 1]; int pl = strlen(prev); char *cur = vln[vcy];
        char *m = (char *)malloc(pl + strlen(cur) + 1); strcpy(m, prev); strcat(m, cur);
        vln[vcy - 1] = m;
        int i; for (i = vcy; i < vnl - 1; i++) vln[i] = vln[i + 1]; vnl--;
        vcy--; vcx = pl;
    }
}
void vjoin(void)
{
    if (vcy >= vnl - 1) return;
    char *a = vln[vcy]; char *b = vln[vcy + 1];
    char *m = (char *)malloc(strlen(a) + strlen(b) + 2);
    strcpy(m, a); strcat(m, " "); strcat(m, b);
    vcx = strlen(a);
    vln[vcy] = m;
    int i; for (i = vcy + 1; i < vnl - 1; i++) vln[i] = vln[i + 1]; vnl--;
}
void vpaste(int after)
{
    if (vynl == 0) return;
    if (vylinewise)
    {
        int at = after ? vcy + 1 : vcy;
        int i; for (i = 0; i < vynl; i++) vins_line(at + i, vdup(vyank[i]));
        vcy = at;
    }
}

/* search: find pattern from (cy,cx+1) forward, wrap */
void vsearch_next(int dir)
{
    if (vsearch[0] == 0) return;
    int n = vnl; int i;
    int cy = vcy;
    for (i = 0; i < n; i++)
    {
        cy = (dir > 0) ? (vcy + 1 + i) % n : (vcy - 1 - i + n * 2) % n;
        int hit = strstr((int)vln[cy], (int)vsearch);
        if (hit) { vcy = cy; vcx = hit - (int)vln[cy]; strcpy(vmsg, "/"); strcat(vmsg, vsearch); return; }
    }
    sprintf((int)vmsg, (int)"Pattern not found: %s", (int)vsearch);
}

/* ---- ex command line (:...) ---- */
void vi_substitute_all(char *pat, char *rep)
{
    int i; int cnt = 0;
    int pl = strlen(pat);
    for (i = 0; i < vnl; i++)
    {
        char out[2048]; int oi = 0; char *s = vln[i]; int j = 0;
        while (s[j])
        {
            if (pl > 0 && strncmp((int)(s + j), (int)pat, pl) == 0)
            { int k = 0; while (rep[k]) out[oi++] = rep[k++]; j += pl; cnt++; }
            else out[oi++] = s[j++];
        }
        out[oi] = 0;
        vln[i] = vdup(out);
    }
    sprintf((int)vmsg, (int)"%d substitutions", cnt);
    if (cnt) vdirty = 1;
}
void vi_excmd(char *c)
{
    while (*c == ' ') c++;
    if (strcmp(c, "w") == 0) { vi_save(vfile); return; }
    if (strncmp((int)c, (int)"w ", 2) == 0) { strcpy(vfile, c + 2); vi_save(vfile); return; }
    if (strcmp(c, "q") == 0) { if (vdirty) { strcpy(vmsg, "No write since last change (use :q!)"); } else vquit = 1; return; }
    if (strcmp(c, "q!") == 0) { vquit = 1; return; }
    if (strcmp(c, "wq") == 0 || strcmp(c, "x") == 0) { vi_save(vfile); vquit = 1; return; }
    if (strcmp(c, "set nu") == 0) { vshownum = 1; return; }
    if (strcmp(c, "set nonu") == 0) { vshownum = 0; return; }
    if (strcmp(c, "syntax on") == 0 || strcmp(c, "syn on") == 0) { vsyntax = 1; return; }
    if (strcmp(c, "syntax off") == 0 || strcmp(c, "syn off") == 0) { vsyntax = 0; return; }
    if (strcmp(c, "syntax") == 0 || strcmp(c, "syn") == 0) { sprintf((int)vmsg, (int)"syntax %s", vsyntax ? (int)"on" : (int)"off"); return; }
    if (c[0] >= '0' && c[0] <= '9') { int ln = atoi(c); if (ln >= 1 && ln <= vnl) vcy = ln - 1; vcx = 0; return; }
    if (c[0] == '%' && c[1] == 's')   /* :%s/old/new/ */
    {
        char sep = c[2]; if (sep == 0) return;
        char pat[256]; char rep[256]; int pi = 0, ri = 0; int i = 3;
        while (c[i] && c[i] != sep) pat[pi++] = c[i++]; pat[pi] = 0;
        if (c[i] == sep) i++;
        while (c[i] && c[i] != sep) rep[ri++] = c[i++]; rep[ri] = 0;
        vpush_undo(); vi_substitute_all(pat, rep);
        return;
    }
    sprintf((int)vmsg, (int)"Not an editor command: %s", (int)c);
}

/* ---- operators (d/c/y + motion) ---- */
void vop_apply(int op, int mk)   /* mk = motion key after operator */
{
    if (mk == op) { /* dd, cc, yy */
        if (op == 'y') { vynl = 0; vyank[vynl++] = vdup(vln[vcy]); vylinewise = 1; strcpy(vmsg, "1 line yanked"); }
        else { vpush_undo(); vdel_line(vcy); if (op == 'c') { vins_line(vcy, vempty()); vmode = 1; } vdirty = 1; }
        return;
    }
    char *s = vln[vcy]; int len = strlen(s); int from = vcx, to = vcx;
    if (mk == 'w' || mk == 'e')
    {
        if (to < len && visword(s[to])) { while (to < len && visword(s[to])) to++; }
        else { while (to < len && !visword(s[to]) && s[to] != ' ') to++; }
        if (mk == 'w') while (to < len && s[to] == ' ') to++;
    }
    else if (mk == '$') to = len;
    else if (mk == '0') { from = 0; to = vcx; }
    else return;
    if (to < from) { int t = from; from = to; to = t; }
    if (op == 'y') { /* charwise yank: store substring as a single non-linewise line */ vynl = 0; char *seg=(char*)malloc(to-from+1); int k; for(k=from;k<to;k++) seg[k-from]=s[k]; seg[to-from]=0; vyank[vynl++]=seg; vylinewise=0; return; }
    vpush_undo();
    char *n = (char *)malloc(len + 1); int k; int oi = 0;
    for (k = 0; k < len; k++) if (k < from || k >= to) n[oi++] = s[k];
    n[oi] = 0; vln[vcy] = n; vcx = from; vdirty = 1;
    if (op == 'c') vmode = 1;
}

/* ---- key handling ---- */
void vnormal_key(int k)
{
    vmsg[0] = 0;
    if (vpend) { vop_apply(vpend, k); vpend = 0; return; }
    int cnt = vcount > 0 ? vcount : 1;
    if (k >= '1' && k <= '9') { vcount = vcount * 10 + (k - '0'); return; }
    if (k == '0' && vcount > 0) { vcount = vcount * 10; return; }
    vcount = 0;
    int i;
    if (k == 'h' || k == -3) { for (i = 0; i < cnt; i++) if (vcx > 0) vcx--; }
    else if (k == 'l' || k == -4) { for (i = 0; i < cnt; i++) vcx++; vclampx(); }
    else if (k == 'j' || k == -2) { for (i = 0; i < cnt; i++) if (vcy < vnl - 1) vcy++; vclampx(); }
    else if (k == 'k' || k == -1) { for (i = 0; i < cnt; i++) if (vcy > 0) vcy--; vclampx(); }
    else if (k == '0') vcx = 0;
    else if (k == '$') { vcx = strlen(vln[vcy]); if (vcx > 0) vcx--; }
    else if (k == '^') { vcx = 0; while (vln[vcy][vcx] == ' ') vcx++; }
    else if (k == 'w') { for (i = 0; i < cnt; i++) vmove_word_fwd(); }
    else if (k == 'b') { for (i = 0; i < cnt; i++) vmove_word_back(); }
    else if (k == 'G') { vcy = (vcount ? cnt - 1 : vnl - 1); if (vcy >= vnl) vcy = vnl - 1; vcx = 0; }
    else if (k == 'g') { int k2 = rt_getkey(); if (k2 == 'g') { vcy = 0; vcx = 0; } }
    else if (k == 'H') vcy = vtop;
    else if (k == 'L') vcy = vmin(vnl - 1, vtop + rt_rows() - 2);
    else if (k == 'M') vcy = vmin(vnl - 1, vtop + (rt_rows() - 1) / 2);
    else if (k == 6) { vcy = vmin(vnl - 1, vcy + (rt_rows() - 2)); vclampx(); }   /* Ctrl-F */
    else if (k == 2) { vcy = vmax(0, vcy - (rt_rows() - 2)); vclampx(); }          /* Ctrl-B */
    else if (k == 4) { vcy = vmin(vnl - 1, vcy + (rt_rows() / 2)); vclampx(); }    /* Ctrl-D */
    else if (k == 21) { vcy = vmax(0, vcy - (rt_rows() / 2)); vclampx(); }         /* Ctrl-U */
    else if (k == 'i') vmode = 1;
    else if (k == 'I') { vcx = 0; while (vln[vcy][vcx] == ' ') vcx++; vmode = 1; }
    else if (k == 'a') { if (strlen(vln[vcy]) > 0) vcx++; vmode = 1; }
    else if (k == 'A') { vcx = strlen(vln[vcy]); vmode = 1; }
    else if (k == 'o') { vpush_undo(); vins_line(vcy + 1, vempty()); vcy++; vcx = 0; vmode = 1; vdirty = 1; }
    else if (k == 'O') { vpush_undo(); vins_line(vcy, vempty()); vcx = 0; vmode = 1; vdirty = 1; }
    else if (k == 'x') { vpush_undo(); for (i = 0; i < cnt; i++) vdel_char_at(vcx); vclampx(); vdirty = 1; }
    else if (k == 'X') { vpush_undo(); for (i = 0; i < cnt; i++) if (vcx > 0) { vcx--; vdel_char_at(vcx); } vdirty = 1; }
    else if (k == 'D') { vpush_undo(); char *s = vln[vcy]; s[vcx] = 0; vdirty = 1; }
    else if (k == 'J') { vpush_undo(); vjoin(); vdirty = 1; }
    else if (k == 'r') { int rc = rt_getkey(); if (rc >= 32) { vpush_undo(); char *s = vln[vcy]; if (vcx < strlen(s)) { s[vcx] = (char)rc; vdirty = 1; } } }
    else if (k == '~') { vpush_undo(); char *s = vln[vcy]; if (vcx < strlen(s)) { int ch = s[vcx]; s[vcx] = isupper(ch) ? tolower(ch) : toupper(ch); vcx++; vclampx(); vdirty = 1; } }
    else if (k == 's') { vpush_undo(); vdel_char_at(vcx); vmode = 1; vdirty = 1; }
    else if (k == 'd' || k == 'c' || k == 'y') vpend = k;
    else if (k == 'p') { vpush_undo(); vpaste(1); vdirty = 1; }
    else if (k == 'P') { vpush_undo(); vpaste(0); vdirty = 1; }
    else if (k == 'u') vundo();
    else if (k == 'n') vsearch_next(1);
    else if (k == 'N') vsearch_next(-1);
    else if (k == ':') { vmode = 2; vcmd[0] = 0; vcmdlen = 0; vpend = 0; }
}
void vinsert_key(int k)
{
    if (k == 27) { vmode = 0; if (vcx > 0) vcx--; vclampx(); return; }   /* ESC */
    if (k == 13) { vpush_undo(); vsplit_line(); vdirty = 1; return; }
    if (k == 8 || k == -5) { vpush_undo(); vbackspace(); vdirty = 1; return; }
    if (k == 9) { vins_char(' '); vins_char(' '); vins_char(' '); vins_char(' '); vdirty = 1; return; }
    if (k >= 32 && k < 127) { vins_char(k); vdirty = 1; }
}
void vcmdline_key(int k)
{
    int searching = (vpend == 1000 || vpend == 1001);
    if (k == 27) { vmode = 0; vpend = 0; vmsg[0] = 0; return; }
    if (k == 13)
    {
        vcmd[vcmdlen] = 0; vmode = 0;
        if (searching) { strcpy(vsearch, vcmd); vsearch_next(vpend == 1000 ? 1 : -1); vpend = 0; }
        else vi_excmd(vcmd);
        return;
    }
    if (k == 8) { if (vcmdlen > 0) vcmdlen--; vcmd[vcmdlen] = 0; return; }
    if (k >= 32 && k < 127) { if (vcmdlen < 250) vcmd[vcmdlen++] = (char)k; vcmd[vcmdlen] = 0; }
}

int vi_main(int n, int *argv, int start)
{
    if (n < 2) { sh_write((int)"usage: vi <file>\n"); return 1; }
    strcpy(vfile, (char *)argv[start + 1]);
    vnl = 0; vtop = 0; vcy = 0; vcx = 0; vmode = 0; vdirty = 0; vquit = 0;
    vshownum = 0; vcmdlen = 0; vmsg[0] = 0; vynl = 0; vsearch[0] = 0; vpend = 0; vcount = 0; u_sp = 0;
    vsyntax = 1; g_kw = VKW_C;                          /* highlight on by default; keyword set by extension */
    char *ext = (char *)strrchr((int)vfile, '.');
    if (ext) { if (streq(ext, ".pas") || streq(ext, ".pp")) g_kw = VKW_PAS; else if (streq(ext, ".lua")) g_kw = VKW_LUA; }
    vi_load(vfile);
    sprintf((int)vmsg, (int)"\"%s\" %dL", (int)vfile, vnl);

    while (!vquit)
    {
        vi_render();
        int k = rt_getkey();
        if (k == -100) break;                 /* EOF -> exit */
        /* command-line search uses vmode 2 with vpend 1000/1001; '/'?' set that */
        if (vmode == 2) { vcmdline_key(k); if (vpend == 1000 || vpend == 1001) { } }
        else if (vmode == 1) vinsert_key(k);
        else
        {
            if (k == '/' || k == '?') { vmode = 2; vcmdlen = 0; vcmd[0] = 0; vpend = (k == '/') ? 1000 : 1001; }
            else vnormal_key(k);
        }
        vclampx();
    }
    rt_clear(); rt_gotoxy(0, 0);
    return 0;
}
