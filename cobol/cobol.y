%{
/* A free-format COBOL subset -> C (yacc); cc lowers the C to .NET IL. The four
 * divisions map cleanly: PROGRAM-ID names the program, WORKING-STORAGE builds the data,
 * PROCEDURE DIVISION becomes the code. Each paragraph is emitted as a C function;
 * main() calls them in source order, so a STOP RUN that halts before fall-through
 * behaves like real COBOL. Two passes: pass 1 registers data items + paragraph names
 * (so PERFORM can see a paragraph defined later); pass 2 emits the C. Our yacc has no
 * mid-rule actions, so ordering is threaded through empty marker non-terminals that
 * read the inherited $0. */

#define C_GROUP 0
#define C_NUM 1
#define C_DEC 2
#define C_ALNUM 3
#define C_EDIT 4
#define C_88 5
#define C_REFMOD 6
#define T_INT 1
#define T_REAL 2
#define T_STR 3
#define T_LOG 4

int g_pass;
char *g_out, *g_data, *g_inits;
int g_movesrc;
char *g_pv, *g_pfrom, *g_pby;
int g_strn, g_strsrc[64], g_strdelim[64], g_strptr;
char *g_unsrc, *g_undelim, *g_setname;
char *g_progid; int g_inlinkage; char *g_using[64]; int g_nusing;
int g_progidx; int g_call[64]; int g_ncall; int g_ctmp;
int prog_parstart[256]; int prog_parcount[256];
char *fl_log[64]; char *fl_phys[64]; char *fl_status[64]; int nfl;
char *g_curfd; char *g_selname; int g_openmode; int g_writefrom; char *g_selstatus;
char *g_readfile; int g_readrec;
int sy_level[4000]; int sy_parent[4000]; char *sy_file[4000]; char *sy_idx[4000];
int g_lvlstk[64]; int g_lvlsp;
char *g_dc_idx; char *g_save; char *g_atendbuf; char *g_searchidx; int g_searchtab;
char *g_atbuf; char *g_notbuf; int g_readinto;
char *g_dc_pic; int g_dc_hasval; int g_dc_val; int g_dc_occ; int g_dc_thru; int g_dc_hasthru;
int g_pcls, g_pdig, g_pdec, g_plen; char *g_pedit;
char *g_lastvar; int g_lastcls;

char *j2(char *a, char *b) { char *r = (char *)malloc(strlen(a) + strlen(b) + 1); strcpy(r, a); strcat(r, b); return r; }
char *j3(char *a, char *b, char *c) { return j2(j2(a, b), c); }
char *j4(char *a, char *b, char *c, char *d) { return j2(j2(a, b), j2(c, d)); }
char *F1(char *f, char *a) { char *r = (char *)malloc(strlen(f) + strlen(a) + 16); sprintf((int)r, (int)f, (int)a); return r; }
char *F2(char *f, char *a, char *b) { char *r = (char *)malloc(strlen(f) + strlen(a) + strlen(b) + 16); sprintf((int)r, (int)f, (int)a, (int)b); return r; }
char *Fi(char *f, int n) { char *r = (char *)malloc(strlen(f) + 24); sprintf((int)r, (int)f, n); return r; }
char *istr(int n) { char b[32]; sprintf((int)b, (int)"%d", n); return (char *)strdup((int)b); }
void ap(char *s) { if (g_pass == 2) g_out = j2(g_out, s); }
void apd(char *s) { if (g_pass == 2) g_data = j2(g_data, s); }

struct E { char *code; int ty; int lval; int cls; int dig; int dec; char *edit; int fig; int idx; char *rms; char *rml; };
int mkE(char *c, int t) { struct E *e = (struct E *)malloc(48); e->code = c; e->ty = t; e->lval = 0; e->cls = -1; e->dig = 0; e->dec = 0; e->edit = ""; e->fig = 0; e->idx = -1; e->rms = ""; e->rml = ""; return (int)e; }
int mkfig(char *c, int t, int fig) { int h = mkE(c, t); ((struct E *)h)->fig = fig; return h; }
int eidx(int h) { return ((struct E *)h)->idx; }
char *ecode(int h) { return ((struct E *)h)->code; }
int etype(int h) { return ((struct E *)h)->ty; }
int ecls(int h) { return ((struct E *)h)->cls; }
int edig(int h) { return ((struct E *)h)->dig; }
int edec(int h) { return ((struct E *)h)->dec; }
char *eedit(int h) { return ((struct E *)h)->edit; }
int efig(int h) { return ((struct E *)h)->fig; }
char *cstr(char *s) { char *r = (char *)malloc(strlen(s) * 2 + 4); int i = 0, j = 0; r[j++] = '"'; while (s[i]) { if (s[i] == '\\' || s[i] == '"') r[j++] = '\\'; r[j++] = s[i++]; } r[j++] = '"'; r[j] = 0; return r; }
char *san(char *nm);
char *istr(int n);
int g_singleprog;
char *cvar(char *nm) { return g_singleprog ? j2("v_", san(nm)) : j4("v", istr(g_progidx), "_", san(nm)); }
char *pgname(char *nm) { return g_singleprog ? j2("pg_", san(nm)) : j4("pg", istr(g_progidx), "_", san(nm)); }
char *mainpar() { return pgname("__main0"); }

char *sy_name[4000]; int sy_cls[4000]; int sy_dig[4000]; int sy_dec[4000]; int sy_len[4000]; int sy_occ[4000]; char *sy_edit[4000]; char *sy_cond[4000]; int sy_ref[4000]; char *sy_cname[4000]; int nsy;
char *san(char *nm) { char *r = (char *)strdup((int)nm); int i = 0; while (r[i]) { if (r[i] == '-') r[i] = '_'; i++; } return r; }
int sy_find(char *n) { int i; for (i = nsy - 1; i >= 0; i--) if (strcmp(sy_name[i], n) == 0) return i; return -1; }
char *par_cn[2000]; int npar;
int cls2ty(int c) { if (c == C_NUM) return T_INT; if (c == C_DEC) return T_REAL; return T_STR; }

void parse_pic(char *p)
{
    int i = 0, nine = 0, x = 0, dec = 0, sawv = 0, edit = 0, width = 0; char prev = 0;
    char exp[256]; int e = 0;
    while (p[i])
    {
        char c = p[i];
        if (c >= 'a' && c <= 'z') c = c - 32;
        if (c == '(') { int k = 0; i++; while (p[i] && p[i] != ')') { k = k * 10 + (p[i] - '0'); i++; } int r; for (r = 1; r < k; r++) { if (e < 250) exp[e++] = prev; } i++; continue; }
        if (e < 250) exp[e++] = c; prev = c; i++;
    }
    exp[e] = 0;
    for (i = 0; i < e; i++)
    {
        char c = exp[i];
        if (c == 'X' || c == 'A') { x++; width++; }
        else if (c == '9') { if (sawv) dec++; else nine++; width++; }
        else if (c == 'V') sawv = 1;
        else if (c == 'Z' || c == '*') { edit = 1; if (sawv) dec++; else nine++; width++; }
        else if (c == '$' || c == ',' || c == '-' || c == '+' || c == 'B' || c == '/') { edit = 1; width++; }
        else if (c == '.') { edit = 1; width++; sawv = 1; }
    }
    g_pdig = nine; g_pdec = dec; g_plen = width; g_pedit = (char *)strdup((int)exp);
    if (x > 0) { g_pcls = C_ALNUM; g_plen = x; }
    else if (edit) g_pcls = C_EDIT;
    else if (dec > 0) g_pcls = C_DEC;
    else g_pcls = C_NUM;
}

int yylex(); void yyerror(char *m);
int bin(int a, char *op, int b); int cmp(int a, char *op, int b);
int name_ref(char *nm); int name_idx(char *nm, int ix);
int ag1(int e); int agA(int h, int e); char *ag_sum(int h);
void def_item(int level, char *nm);
void do_display(int e); void do_move_t(int dst); void do_assign(int dst, int src);
void do_addsub(int srch, int dst, char *op, int give); void do_muldiv(int src, int dst, char *op, int give);
void do_accept(int dst); void do_perf_times(char *nm, int n); void do_perf_vary(char *nm, int v, int from, int by, int cnd);
void proc_start(); void new_para(char *nm); void proc_end();
int refmod(char *nm, int start, int len); int func_call(char *nm, int argh); int classcmp(int e, int code);
void do_init(int e); void do_string(int dest); void do_inspect_tally(int id, int cnt, int lit);
void do_inspect_repl(int id, int from, int to); void do_set_true(char *nm); void do_set_var(char *nm, int e);
void do_set_by(char *nm, int e, int up); void do_perf_thru(char *a, char *b);
void prog_begin(); void do_call_cob(char *name);
void def_file(char *log, char *phys); void def_file_status(char *nm);
void do_open(char *nm); void do_close(char *nm); void do_read_simple(char *nm); void do_read_into2(int tgt); void do_write(char *nm);
int fl_find(char *nm); int rec_for_file(char *log);
void move_group(int src, int dst); void leaves(int rec, int *out, int *n); int leafE(int k);
int refmod_t(char *nm, int start, int len); int round_e(int e);
void do_corr(char *s, char *d, int isadd); void search_begin(char *nm); void searchend();
int qualref(char *field, char *rec); int sy_find_of(char *field, char *rec);
%}
%token NAME INTLIT REALLIT STRLIT PERIOD PICTURE
%token KIDENT KDIVISION KPROGRAMID KENVIRONMENT KCONFIG KDATA KWORKING KLINKAGE KSECTION KPROCEDURE
%token KIS KVALUE KOCCURS KTIMES KDISPLAY KACCEPT KMOVE KTO KFROM KGIVING KADD KSUBTRACT KMULTIPLY KDIVIDE KINTO KBY KCOMPUTE KROUNDED
%token KIF KTHEN KELSE KENDIF KPERFORM KENDPERF KUNTIL KVARYING KEVALUATE KWHEN KOTHER KENDEVAL
%token KSTOP KRUN KGOBACK KGO KNOT KAND KOR KEQUAL KGREATER KLESS KTHAN KTHRU KZERO KSPACES KCONTINUE
%token KGE KLE KNE POW
%token KSTRING KUNSTRING KDELIMITED KDELIMITER KCOUNT KPOINTER KSIZE KWITH KENDSTRING KENDUNSTRING
%token KINSPECT KTALLYING KREPLACING KALL KLEADING KFOR KINITIALIZE KSET KTRUE KFALSE KUP KDOWN
%token KNUMERIC KALPHABETIC KPOSITIVE KNEGATIVE KFUNCTION KHIGHVAL KLOWVAL KQUOTE
%token KCALL KUSING KEXIT KEND KPROGRAM KENDCALL KREFERENCE KCONTENT
%token KSELECT KASSIGN KORGANIZATION KLINE KSEQUENTIAL KRECORD KINPUT KOUTPUT KEXTEND
%token KOPEN KCLOSE KREAD KWRITE KREWRITE KAT KFD KFILE KINPUTOUTPUT KFILECONTROL KSTATUS KENDREAD KENDWRITE KCORR
%token KUSAGE KCOMP KCOMP3 KBINARY KPACKED KINDEXED KSEARCH KENDSEARCH KOF
%left KOR
%left KAND
%right KNOT
%left '+' '-'
%left '*' '/'
%right POW
%right UMINUS
%%
program : progs ;
progs   : prog | progs prog ;
prog    : pbegin ident_div env_opt data_opt proc_div endprog ;
pbegin  : { prog_begin(); } ;
endprog : | KEND KPROGRAM NAME PERIOD | KEND KPROGRAM PERIOD ;

ident_div : KIDENT KDIVISION PERIOD KPROGRAMID PERIOD NAME PERIOD { g_progid = (char *)$6; } ;
env_opt   : | KENVIRONMENT KDIVISION PERIOD iosec ;
iosec     : | KINPUTOUTPUT KSECTION PERIOD KFILECONTROL PERIOD selects ;
selects   : | selects select ;
select    : KSELECT NAME KASSIGN assignto selname orgcls PERIOD { def_file((char *)$2, g_selname); } ;
assignto  : | KTO ;
selname   : STRLIT { g_selname = (char *)$1; } | NAME { g_selname = (char *)$1; } ;
orgcls    : | orgcls orgcl ;
orgcl     : KORGANIZATION isopt KLINE KSEQUENTIAL | KORGANIZATION isopt KSEQUENTIAL | KFILE KSTATUS isopt NAME { def_file_status((char *)$4); } ;
isopt     : | KIS ;

data_opt  : | KDATA KDIVISION PERIOD file_sec ws_opt linkage_opt ;
file_sec  : | KFILE KSECTION PERIOD fds ;
fds       : | fds fd ;
fd        : fdhead ditems ;
fdhead    : KFD NAME PERIOD { g_curfd = (char *)$2; } | KFD NAME fdjunk PERIOD { g_curfd = (char *)$2; } ;
fdjunk    : junktok | fdjunk junktok ;
junktok   : NAME | INTLIT | KRECORD ;
linkage_opt : | KLINKAGE KSECTION PERIOD lkmark ditems ;
lkmark    : { g_inlinkage = 1; g_curfd = 0; } ;
ws_opt    : | KWORKING KSECTION PERIOD wsmark ditems ;
wsmark    : { g_curfd = 0; } ;
ditems    : | ditems ditem ;
ditem     : INTLIT NAME dclauses PERIOD   { def_item($1, (char *)$2); }
          | INTLIT NAME PERIOD            { def_item($1, (char *)$2); } ;
dclauses  : dclause | dclauses dclause ;
dclause   : PICTURE              { g_dc_pic = (char *)$1; }
          | KVALUE val           { g_dc_val = $2; g_dc_hasval = 1; }
          | KVALUE KIS val       { g_dc_val = $3; g_dc_hasval = 1; }
          | KOCCURS INTLIT       { g_dc_occ = $2; }
          | KOCCURS INTLIT KTIMES { g_dc_occ = $2; }
          | KOCCURS INTLIT idxby  { g_dc_occ = $2; }
          | KOCCURS INTLIT KTIMES idxby { g_dc_occ = $2; }
          | KTHRU val            { g_dc_thru = $2; g_dc_hasthru = 1; }
          | KUSAGE isopt usagekind
          | usagekind ;
idxby     : KINDEXED isopt NAME { g_dc_idx = (char *)$3; } ;
usagekind : KCOMP | KCOMP3 | KBINARY | KPACKED | KDISPLAY ;
val       : INTLIT     { $$ = mkE(istr($1), T_INT); }
          | REALLIT    { $$ = mkE((char *)$1, T_REAL); }
          | '-' INTLIT { $$ = mkE(F1("-%s", istr($2)), T_INT); }
          | STRLIT     { $$ = mkE(cstr((char *)$1), T_STR); }
          | KZERO      { $$ = mkE("0", T_INT); }
          | KSPACES    { $$ = mkE("\" \"", T_STR); } ;

proc_div  : KPROCEDURE KDIVISION using_opt PERIOD pstart pbody { proc_end(); } ;
using_opt : | KUSING usingnames ;
usingnames : NAME { g_using[g_nusing++] = (char *)$1; } | usingnames NAME { g_using[g_nusing++] = (char *)$2; } ;
pstart    : { proc_start(); } ;
pbody     : sents pars ;
sents     : | sents sentence ;
pars      : | pars paragraph ;
paragraph : pghead sents ;
pghead    : NAME PERIOD          { new_para((char *)$1); } ;
sentence  : bstmts PERIOD ;
bstmts    : | bstmts stmt ;

stmt : KDISPLAY dlist                                { if (g_pass == 2) ap("printf(\"\\n\");\n"); }
     | KMOVE expr setmv KTO tlist
     | KMOVE KCORR NAME KTO NAME                      { do_corr((char *)$3, (char *)$5, 0); }
     | KADD elist KTO target give                     { do_addsub($2, $4, "+", $5); }
     | KADD KCORR NAME KTO NAME                       { do_corr((char *)$3, (char *)$5, 1); }
     | KSUBTRACT elist KFROM target give              { do_addsub($2, $4, "-", $5); }
     | KMULTIPLY expr KBY target give                 { do_muldiv($2, $4, "*", $5); }
     | KDIVIDE expr KINTO target give                 { do_muldiv($2, $4, "/", $5); }
     | KDIVIDE expr KBY expr KGIVING target           { do_assign($6, bin($2, "/", $4)); }
     | KCOMPUTE target round '=' expr                 { do_assign($2, ($3 && ecls($2) == C_NUM) ? round_e($5) : $5); }
     | KACCEPT target                                { do_accept($2); }
     | KSTOP KRUN                                     { if (g_pass == 2) ap("exit(0);\n"); }
     | KGOBACK                                        { if (g_pass == 2) ap("{ __goback = 1; return; }\n"); }
     | KEXIT KPROGRAM                                 { if (g_pass == 2) ap("{ __goback = 1; return; }\n"); }
     | KEXIT
     | KCALL STRLIT cinit callusing endcall           { do_call_cob((char *)$2); }
     | KOPEN opengrps
     | KCLOSE closelist
     | KREAD NAME rsimple rio                         { }
     | KWRITE NAME writefrom                          { do_write((char *)$2); }
     | KCONTINUE
     | KGO KTO NAME                                   { if (g_pass == 2) ap(F1("%s();\n", pgname((char *)$3))); }
     | KINITIALIZE itlist
     | KSTRING sinit strsrcs KINTO target sptr endstr { do_string($5); }
     | KUNSTRING expr usrc KDELIMITED KBY expr ubeg KINTO utargets enduns { if (g_pass == 2) ap("}\n"); }
     | KINSPECT target KTALLYING target KFOR inspk expr { do_inspect_tally($2, $4, $7); }
     | KINSPECT target KREPLACING inspk expr KBY expr  { do_inspect_repl($2, $5, $7); }
     | KSET NAME smark KTO settv
     | KSET NAME KUP KBY expr                         { do_set_by((char *)$2, $5, 1); }
     | KSET NAME KDOWN KBY expr                       { do_set_by((char *)$2, $5, 0); }
     | KPERFORM perf
     | ifstmt
     | evalstmt ;

itlist : target { do_init($1); } | itlist target { do_init($1); } ;

sinit  : { g_strn = 0; g_strptr = 0; } ;
strsrcs: strsrc | strsrcs strsrc ;
strsrc : expr KDELIMITED KBY sdelim { g_strsrc[g_strn] = $1; g_strdelim[g_strn] = $4; g_strn++; } ;
sdelim : KSIZE { $$ = 0; } | expr { $$ = $1; } ;
sptr   : | KWITH KPOINTER target { g_strptr = $3; } | KPOINTER target { g_strptr = $2; } ;
endstr : | KENDSTRING ;

usrc   : { g_unsrc = ecode($0); } ;
ubeg   : { g_undelim = ecode($0); if (g_pass == 2) ap("{ int __up = 0;\n"); } ;
utargets: utgt | utargets utgt ;
utgt   : target { if (g_pass == 2) { ap(F2("__unstr(%s, %s, &__up, ", g_unsrc, g_undelim)); ap(F1("%s, ", ecode($1))); ap(Fi("%d);\n", edig($1))); } } ;
enduns : | KENDUNSTRING ;

inspk  : KALL | KLEADING ;
smark  : { g_setname = (char *)$0; } ;
settv  : KTRUE { do_set_true(g_setname); } | expr { do_set_var(g_setname, $1); } ;
cinit  : { g_ncall = 0; } ;
callusing : | KUSING cargs ;
cargs  : carg | cargs carg ;
carg   : refmode expr { g_call[g_ncall++] = $2; } ;
refmode: | KBY KREFERENCE | KBY KCONTENT ;
endcall: | KENDCALL ;

opengrps : opengrp | opengrps opengrp ;
opengrp  : openmode openames ;
openmode : KINPUT { g_openmode = 0; } | KOUTPUT { g_openmode = 1; } | KEXTEND { g_openmode = 2; } ;
openames : NAME { do_open((char *)$1); } | openames NAME { do_open((char *)$2); } ;
closelist: NAME { do_close((char *)$1); } | closelist NAME { do_close((char *)$2); } ;
rsimple  : { do_read_simple((char *)$0); } ;
rio      : { if (g_pass == 2) ap("}\n"); }
         | KINTO target { do_read_into2($2); if (g_pass == 2) ap("}\n"); } ;
writefrom: { g_writefrom = 0; } | KFROM target { g_writefrom = $2; } ;

setmv : { g_movesrc = $0; } ;
dlist : ditem_d | dlist ditem_d ;
ditem_d : expr { do_display($1); } ;
tlist : target { do_move_t($1); } | tlist target { do_move_t($1); } ;
target : NAME              { $$ = name_ref((char *)$1); }
       | NAME KOF NAME     { $$ = qualref((char *)$1, (char *)$3); }
       | NAME '(' expr ')' { $$ = name_idx((char *)$1, $3); }
       | NAME '(' expr ':' expr ')' { $$ = refmod_t((char *)$1, $3, $5); } ;
elist : expr { $$ = ag1($1); } | elist expr { $$ = agA($1, $2); } ;
give  : { $$ = 0; } | KGIVING target { $$ = $2; } ;
round : { $$ = 0; } | KROUNDED { $$ = 1; } ;

ifstmt : KIF cond ift thenopt bstmts iftail ;
ift    : { if (g_pass == 2) ap(F1("if (%s) {\n", ecode($0))); } ;
thenopt: | KTHEN ;
iftail : KENDIF                  { if (g_pass == 2) ap("}\n"); }
       | ifelse bstmts KENDIF    { if (g_pass == 2) ap("}\n"); } ;
ifelse : KELSE                   { if (g_pass == 2) ap("} else {\n"); } ;

evalstmt : KEVALUATE expr evbeg whens evdef KENDEVAL { if (g_pass == 2) ap("} }\n"); } ;
evbeg  : { if (g_pass == 2) ap(F1("{ int __ev = %s; if (0) {\n", ecode($0))); } ;
whens  : | whens onewhen ;
onewhen: KWHEN val wopen bstmts ;
wopen  : { if (g_pass == 2) ap(F1("} else if (__ev == %s) {\n", ecode($0))); } ;
evdef  : | KWHEN KOTHER wdef bstmts ;
wdef   : { if (g_pass == 2) ap("} else {\n"); } ;


perf : NAME                                              { if (g_pass == 2) ap(F1("%s();\n", pgname((char *)$1))); }
     | NAME KTHRU NAME                                   { do_perf_thru((char *)$1, (char *)$3); }
     | NAME INTLIT KTIMES                                { do_perf_times((char *)$1, $2); }
     | NAME KUNTIL cond                                  { if (g_pass == 2) ap(F2("while (!(%s)) %s();\n", ecode($3), pgname((char *)$1))); }
     | NAME KVARYING target KFROM expr KBY expr KUNTIL cond { do_perf_vary((char *)$1, $3, $5, $7, $9); }
     | KUNTIL cond pu bstmts KENDPERF                    { if (g_pass == 2) ap("}\n"); }
     | INTLIT pt KTIMES bstmts KENDPERF                  { if (g_pass == 2) ap("} }\n"); }
     | KVARYING target vset KFROM expr vfrom KBY expr vby KUNTIL cond vstart bstmts KENDPERF { if (g_pass == 2) ap(F2("%s += (%s); }\n", g_pv, g_pby)); } ;
pu   : { if (g_pass == 2) ap(F1("while (!(%s)) {\n", ecode($0))); } ;
pt   : { if (g_pass == 2) ap(Fi("{ int __t; for (__t=0; __t<%d; __t++) {\n", $0)); } ;
vset : { g_pv = ecode($0); } ;
vfrom: { g_pfrom = ecode($0); } ;
vby  : { g_pby = ecode($0); } ;
vstart: { if (g_pass == 2) ap(j2(F2("%s = (%s);\n", g_pv, g_pfrom), F1("while (!(%s)) {\n", ecode($0)))); } ;

cond : cond KOR cond2   { $$ = mkE(F2("(%s || %s)", ecode($1), ecode($3)), T_LOG); } | cond2 { $$ = $1; } ;
cond2: cond2 KAND cond3 { $$ = mkE(F2("(%s && %s)", ecode($1), ecode($3)), T_LOG); } | cond3 { $$ = $1; } ;
cond3: KNOT cond3       { $$ = mkE(F1("(!%s)", ecode($2)), T_LOG); } | '(' cond ')' { $$ = $2; } | rel { $$ = $1; } ;
rel  : expr relop expr  { $$ = cmp($1, (char *)$2, $3); }
     | expr KIS clscls   { $$ = classcmp($1, $3); }
     | expr clscls       { $$ = classcmp($1, $2); }
     | expr             { $$ = mkE(ecode($1), T_LOG); } ;
clscls: KNUMERIC          { $$ = 0; }
     | KNOT KNUMERIC      { $$ = 1; }
     | KALPHABETIC        { $$ = 2; }
     | KNOT KALPHABETIC   { $$ = 3; }
     | KPOSITIVE          { $$ = 4; }
     | KNOT KPOSITIVE     { $$ = 5; }
     | KNEGATIVE          { $$ = 6; }
     | KNOT KNEGATIVE     { $$ = 7; }
     | KZERO              { $$ = 8; }
     | KNOT KZERO         { $$ = 9; } ;
relop: '='            { $$ = (int)"=="; }
     | KEQUAL         { $$ = (int)"=="; }
     | KEQUAL KTO     { $$ = (int)"=="; }
     | '<'            { $$ = (int)"<"; }
     | '>'            { $$ = (int)">"; }
     | KGE            { $$ = (int)">="; }
     | KLE            { $$ = (int)"<="; }
     | KNE            { $$ = (int)"!="; }
     | KGREATER       { $$ = (int)">"; }
     | KGREATER KTHAN { $$ = (int)">"; }
     | KLESS          { $$ = (int)"<"; }
     | KLESS KTHAN    { $$ = (int)"<"; }
     | KNOT '='       { $$ = (int)"!="; }
     | KNOT KEQUAL    { $$ = (int)"!="; } ;

expr : expr '+' expr   { $$ = bin($1, "+", $3); }
     | expr '-' expr   { $$ = bin($1, "-", $3); }
     | expr '*' expr   { $$ = bin($1, "*", $3); }
     | expr '/' expr   { $$ = bin($1, "/", $3); }
     | expr POW expr   { $$ = mkE(F2("pow((double)(%s),(double)(%s))", ecode($1), ecode($3)), T_REAL); }
     | '-' expr %prec UMINUS { $$ = mkE(F1("(-%s)", ecode($2)), etype($2)); }
     | '(' expr ')'    { $$ = mkE(F1("(%s)", ecode($2)), etype($2)); }
     | INTLIT          { $$ = mkE(istr($1), T_INT); }
     | REALLIT         { $$ = mkE((char *)$1, T_REAL); }
     | STRLIT          { $$ = mkE(cstr((char *)$1), T_STR); }
     | KZERO           { $$ = mkfig("0", T_INT, '0' + 1); }
     | KSPACES         { $$ = mkfig("\" \"", T_STR, ' ' + 1); }
     | KHIGHVAL        { $$ = mkfig("\"\"", T_STR, 255 + 1); }
     | KLOWVAL         { $$ = mkfig("\"\"", T_STR, 0 + 1); }
     | KQUOTE          { $$ = mkfig("\"\\\"\"", T_STR, '"' + 1); }
     | KALL STRLIT     { $$ = mkfig(cstr((char *)$2), T_STR, ((char *)$2)[0] + 1); }
     | KFUNCTION NAME '(' fargs ')' { $$ = func_call((char *)$2, $4); }
     | NAME            { $$ = name_ref((char *)$1); }
     | NAME KOF NAME   { $$ = qualref((char *)$1, (char *)$3); }
     | NAME '(' expr ')' { $$ = name_idx((char *)$1, $3); }
     | NAME '(' expr ':' expr ')' { $$ = refmod((char *)$1, $3, $5); } ;
fargs : expr { $$ = ag1($1); } | fargs expr { $$ = agA($1, $2); } ;
%%

void yyerror(char *m) { printf((int)"cobol: %s (line %d)\n", (int)m, pline); }

void dc_reset() { g_dc_pic = 0; g_dc_hasval = 0; g_dc_occ = 0; g_dc_hasthru = 0; g_dc_idx = 0; }

void def_item(int level, char *nm)
{
    if (level == 88)
    {
        char *cond;
        if (g_dc_hasthru) cond = j4("(", g_lastvar, F2(" >= %s && %s", ecode(g_dc_val), g_lastvar), F1(" <= %s)", ecode(g_dc_thru)));
        else if (g_lastcls == C_ALNUM || g_lastcls == C_EDIT) cond = F2("(strcmp(%s, %s) == 0)", g_lastvar, ecode(g_dc_val));
        else cond = F2("(%s == %s)", g_lastvar, ecode(g_dc_val));
        sy_name[nsy] = nm; sy_cls[nsy] = C_88; sy_cond[nsy] = cond; sy_occ[nsy] = 0; sy_ref[nsy] = 0;
        sy_level[nsy] = 88; sy_parent[nsy] = (g_lvlsp > 0) ? g_lvlstk[g_lvlsp - 1] : -1; sy_file[nsy] = g_curfd;
        sy_edit[nsy] = (g_lastcls == C_ALNUM || g_lastcls == C_EDIT) ? F2("strcpy(%s, %s)", g_lastvar, ecode(g_dc_val)) : F2("%s = %s", g_lastvar, ecode(g_dc_val));
        nsy++;
        dc_reset(); return;
    }
    int cls = C_GROUP, dig = 0, dec = 0, len = 0; char *edit = "";
    if (g_dc_pic) { parse_pic(g_dc_pic); cls = g_pcls; dig = g_pdig; dec = g_pdec; len = g_plen; edit = g_pedit; }
    int occ = g_dc_occ;
    while (g_lvlsp > 0 && sy_level[g_lvlstk[g_lvlsp - 1]] >= level) g_lvlsp--;
    sy_level[nsy] = level; sy_parent[nsy] = (g_lvlsp > 0) ? g_lvlstk[g_lvlsp - 1] : -1; sy_file[nsy] = g_curfd; sy_idx[nsy] = 0;
    g_lvlstk[g_lvlsp++] = nsy;
    int myi = nsy;
    sy_name[nsy] = nm; sy_cls[nsy] = cls; sy_dig[nsy] = dig; sy_dec[nsy] = dec; sy_len[nsy] = len; sy_occ[nsy] = occ; sy_edit[nsy] = edit; sy_ref[nsy] = g_inlinkage;
    { int a = sy_parent[myi]; int top = myi; while (a >= 0) { top = a; a = sy_parent[a]; } sy_cname[myi] = (top != myi) ? cvar(j3(sy_name[top], "-", nm)) : cvar(nm); }
    nsy++;
    if (g_dc_idx && occ > 0)
    {
        sy_idx[myi] = g_dc_idx;
        sy_name[nsy] = g_dc_idx; sy_cls[nsy] = C_NUM; sy_dig[nsy] = 4; sy_dec[nsy] = 0; sy_len[nsy] = 0; sy_occ[nsy] = 0; sy_edit[nsy] = ""; sy_ref[nsy] = 0;
        sy_level[nsy] = 77; sy_parent[nsy] = -1; sy_file[nsy] = 0; sy_idx[nsy] = 0; sy_cname[nsy] = cvar(g_dc_idx);
        if (g_pass == 2) apd(j3("int ", cvar(g_dc_idx), " = 1;\n"));
        nsy++;
    }
    if (cls != C_GROUP) { g_lastvar = sy_cname[myi]; g_lastcls = cls; }
    if (g_pass == 2 && cls != C_GROUP)
    {
        char *cn = sy_cname[myi]; char *decl;
        if (g_inlinkage)
        {
            char *pt = (cls == C_NUM) ? "int* " : (cls == C_DEC) ? "double* " : "char* ";
            apd(j3(pt, cn, ";\n")); dc_reset(); return;
        }
        if (cls == C_NUM || cls == C_DEC)
        {
            char *t = (cls == C_NUM) ? "int " : "double ";
            decl = (occ > 0) ? j2(j3(t, cn, ""), Fi("[%d];\n", occ)) : j2(j3(t, cn, ""), ";\n");
        }
        else
        {
            decl = (occ > 0) ? j2(j3("char ", cn, ""), j2(Fi("[%d]", occ), Fi("[%d];\n", len + 1)))
                             : j2(j3("char ", cn, ""), Fi("[%d];\n", len + 1));
        }
        apd(decl);
        if (g_dc_hasval && occ == 0)
        {
            if (cls == C_ALNUM || cls == C_EDIT) g_inits = j2(g_inits, j2(F2("__movestr(%s, %s, ", cn, ecode(g_dc_val)), Fi("%d);\n", len)));
            else g_inits = j2(g_inits, F2("%s = %s;\n", cn, ecode(g_dc_val)));
        }
    }
    dc_reset();
}

int name_ref(char *nm)
{
    int i = sy_find(nm);
    if (i < 0) return mkE(cvar(nm), T_INT);
    if (sy_cls[i] == C_88) return mkE(sy_cond[i], T_LOG);
    char *code = sy_cname[i];
    if (sy_ref[i] && (sy_cls[i] == C_NUM || sy_cls[i] == C_DEC)) code = F1("(*%s)", code);
    int h = mkE(code, cls2ty(sy_cls[i]));
    int dg = (sy_cls[i] == C_ALNUM || sy_cls[i] == C_EDIT) ? sy_len[i] : sy_dig[i];
    struct E *e = (struct E *)h; e->lval = 1; e->cls = sy_cls[i]; e->dig = dg; e->dec = sy_dec[i]; e->edit = sy_edit[i]; e->idx = i;
    return h;
}
int name_idx(char *nm, int ix)
{
    int i = sy_find(nm); char *cn = (i >= 0) ? sy_cname[i] : cvar(nm);
    int h = mkE(j2(cn, j4("[(", ecode(ix), ") - 1", "]")), (i >= 0) ? cls2ty(sy_cls[i]) : T_INT);
    if (i >= 0) { int dg = (sy_cls[i] == C_ALNUM || sy_cls[i] == C_EDIT) ? sy_len[i] : sy_dig[i]; struct E *e = (struct E *)h; e->lval = 1; e->cls = sy_cls[i]; e->dig = dg; e->dec = sy_dec[i]; e->edit = sy_edit[i]; }
    return h;
}

int bin(int a, char *op, int b)
{
    int rt = (etype(a) == T_REAL || etype(b) == T_REAL) ? T_REAL : T_INT;
    return mkE(j2("(", j4(ecode(a), op, ecode(b), ")")), rt);
}
int cmp(int a, char *op, int b)
{
    if (etype(a) == T_STR || etype(b) == T_STR)
    {
        char *o = (strcmp(op, "==") == 0) ? "== 0" : (strcmp(op, "!=") == 0) ? "!= 0" : j2(op, " 0");
        return mkE(j3(F2("(strcmp(%s, %s) ", ecode(a), ecode(b)), o, ")"), T_LOG);
    }
    return mkE(j2("(", j4(ecode(a), op, ecode(b), ")")), T_LOG);
}

struct AG { int n; int a[32]; };
int ag1(int e) { struct AG *g = (struct AG *)malloc(132); g->n = 0; g->a[g->n++] = e; return (int)g; }
int agA(int h, int e) { struct AG *g = (struct AG *)h; g->a[g->n++] = e; return h; }
char *ag_sum(int h) { struct AG *g = (struct AG *)h; char *s = ecode(g->a[0]); int i; for (i = 1; i < g->n; i++) s = j3(s, " + ", ecode(g->a[i])); return s; }

void do_display(int e)
{
    if (g_pass != 2) return;
    int c = ecls(e);
    if (c == C_NUM) ap(F2("__disp_num(%s, %s);\n", ecode(e), istr(edig(e))));
    else if (c == C_DEC) ap(F2("__disp_dec((double)(%s), %s);\n", ecode(e), istr(edec(e))));
    else if (c == C_ALNUM || c == C_EDIT) ap(F1("printf(\"%%s\", %s);\n", ecode(e)));
    else if (etype(e) == T_STR) ap(F1("printf(\"%%s\", %s);\n", ecode(e)));
    else if (etype(e) == T_REAL) ap(F1("printf(\"%%g\", (double)(%s));\n", ecode(e)));
    else ap(F1("printf(\"%%d\", %s);\n", ecode(e)));
}

void move_one(int dst, int src)
{
    if (g_pass != 2) return;
    int c = ecls(dst); char *d = ecode(dst); char *s = ecode(src);
    if (c == C_GROUP) { if (eidx(src) >= 0 && eidx(dst) >= 0) move_group(eidx(src), eidx(dst)); return; }
    if (c == C_REFMOD) { struct E *e = (struct E *)dst; ap(j2(F2("__setsub(%s, (%s), ", e->code, e->rms), F2("(%s), %s);\n", e->rml, s))); return; }
    if (efig(src) > 0 && (c == C_ALNUM || c == C_EDIT)) { ap(F2("__fill(%s, %s, ", d, istr(efig(src) - 1))); ap(Fi("%d);\n", edig(dst))); return; }
    if (c == C_ALNUM) ap(j2(F2("__movestr(%s, %s, ", d, s), Fi("%d);\n", edig(dst))));
    else if (c == C_EDIT) ap(j2(F2("__edit(%s, (double)(%s), ", d, s), F1("%s);\n", cstr(eedit(dst)))));
    else if (c == C_DEC) ap(F2("%s = (double)(%s);\n", d, s));
    else ap(F2("%s = (int)(%s);\n", d, s));
}
void do_move_t(int dst) { move_one(dst, g_movesrc); }
void do_assign(int dst, int src) { move_one(dst, src); }

void do_addsub(int srch, int dst, char *op, int give)
{
    if (g_pass != 2) return;
    char *sum = ag_sum(srch); int t = give ? give : dst;
    ap(j2(F2("%s = %s ", ecode(t), ecode(dst)), F2("%s (%s);\n", op, sum)));
}
void do_muldiv(int src, int dst, char *op, int give)
{
    if (g_pass != 2) return;
    int t = give ? give : dst;
    ap(j2(F2("%s = %s ", ecode(t), ecode(dst)), F2("%s (%s);\n", op, ecode(src))));
}
void do_accept(int dst)
{
    if (g_pass != 2) return;
    if (ecls(dst) == C_ALNUM || etype(dst) == T_STR) ap(F1("__accept_str(%s);\n", ecode(dst)));
    else if (ecls(dst) == C_DEC) ap(F1("{ double __x; scanf(\"%%lf\", &__x); %s = __x; }\n", ecode(dst)));
    else ap(F1("{ int __x; scanf(\"%%d\", &__x); %s = __x; }\n", ecode(dst)));
}
void do_perf_times(char *nm, int n) { if (g_pass == 2) ap(j2(Fi("{ int __t; for (__t=0; __t<%d; __t++) ", n), F1("%s(); }\n", pgname(nm)))); }
void do_perf_vary(char *nm, int v, int from, int by, int cnd)
{
    if (g_pass != 2) return;
    ap(F2("%s = (%s);\n", ecode(v), ecode(from)));
    ap(j2(F2("while (!(%s)) { %s(); ", ecode(cnd), pgname(nm)), F2("%s += (%s); }\n", ecode(v), ecode(by))));
}

int refmod(char *nm, int start, int len)
{
    char *cn = cvar(nm);
    return mkE(j2("__substr(", j4(cn, ", (", ecode(start), j4(") - 1, ", ecode(len), ")", ""))), T_STR);
}
int refmod_t(char *nm, int start, int len)
{
    int h = mkE(cvar(nm), T_STR);
    struct E *e = (struct E *)h; e->cls = C_REFMOD; e->rms = ecode(start); e->rml = ecode(len);
    return h;
}
int classcmp(int e, int code)
{
    int neg = code & 1; int kind = code >> 1; char *s = ecode(e); char *c;
    if (kind == 0) c = (etype(e) == T_STR) ? F1("__isnum(%s)", s) : "1";
    else if (kind == 1) c = (etype(e) == T_STR) ? F1("__isalpha(%s)", s) : "0";
    else if (kind == 2) c = F1("((%s) > 0)", s);
    else if (kind == 3) c = F1("((%s) < 0)", s);
    else c = (etype(e) == T_STR) ? F1("(strlen(%s) == 0)", s) : F1("((%s) == 0)", s);
    if (neg) c = F1("(!(%s))", c);
    return mkE(c, T_LOG);
}
int func_call(char *nm, int argh)
{
    struct AG *g = (struct AG *)argh; char *a0 = ecode(g->a[0]); int n = g->n; int i;
    if (strcmp(nm, "UPPER-CASE") == 0) return mkE(F1("__upper(%s)", a0), T_STR);
    if (strcmp(nm, "LOWER-CASE") == 0) return mkE(F1("__lower(%s)", a0), T_STR);
    if (strcmp(nm, "REVERSE") == 0) return mkE(F1("__reverse(%s)", a0), T_STR);
    if (strcmp(nm, "LENGTH") == 0) return mkE(F1("((int)strlen(%s))", a0), T_INT);
    if (strcmp(nm, "NUMVAL") == 0) return mkE(F1("atoi(%s)", a0), T_INT);
    if (strcmp(nm, "INTEGER") == 0) return mkE(F1("((int)(%s))", a0), T_INT);
    if (strcmp(nm, "MOD") == 0) return mkE(F2("((%s) %% (%s))", a0, ecode(g->a[1])), T_INT);
    if (strcmp(nm, "MAX") == 0) { char *r = a0; for (i = 1; i < n; i++) { char *b = ecode(g->a[i]); r = j2("(", j4(r, " > ", b, j4(" ? ", r, " : ", j2(b, ")")))); } return mkE(r, T_INT); }
    if (strcmp(nm, "MIN") == 0) { char *r = a0; for (i = 1; i < n; i++) { char *b = ecode(g->a[i]); r = j2("(", j4(r, " < ", b, j4(" ? ", r, " : ", j2(b, ")")))); } return mkE(r, T_INT); }
    return mkE("0", T_INT);
}
void do_init(int e)
{
    if (g_pass != 2) return;
    int c = ecls(e);
    if (c == C_ALNUM || c == C_EDIT) { ap(F1("__fill(%s, 32, ", ecode(e))); ap(Fi("%d);\n", edig(e))); }
    else ap(F1("%s = 0;\n", ecode(e)));
}
void do_string(int dest)
{
    if (g_pass != 2) return;
    char *d = ecode(dest); int dl = edig(dest); int i;
    ap(j3("{ int __sp = ", g_strptr ? j3("(", ecode(g_strptr), ") - 1") : "0", ";\n"));
    for (i = 0; i < g_strn; i++)
    {
        char *delim = g_strdelim[i] ? ecode(g_strdelim[i]) : "\"\"";
        ap(F2("__strapp(%s, &__sp, %s, ", d, ecode(g_strsrc[i])));
        ap(F1("%s, ", delim));
        ap(Fi("%d);\n", dl));
    }
    if (g_strptr) ap(F1("%s = __sp + 1;\n", ecode(g_strptr)));
    ap("}\n");
}
void do_inspect_tally(int id, int cnt, int lit)
{
    if (g_pass != 2) return;
    ap(F2("%s = %s + ", ecode(cnt), ecode(cnt)));
    ap(F2("__tally(%s, %s);\n", ecode(id), ecode(lit)));
}
void do_inspect_repl(int id, int from, int to)
{
    if (g_pass != 2) return;
    ap(F2("__replace(%s, %s, ", ecode(id), ecode(from)));
    ap(F1("%s);\n", ecode(to)));
}
void do_set_true(char *nm)
{
    if (g_pass != 2) return;
    int i = sy_find(nm);
    if (i >= 0 && sy_cls[i] == C_88) ap(j2(sy_edit[i], ";\n"));
}
void do_set_var(char *nm, int e) { move_one(name_ref(nm), e); }
void do_set_by(char *nm, int e, int up)
{
    if (g_pass != 2) return;
    int t = name_ref(nm);
    ap(F2("%s %s= (", ecode(t), up ? "+" : "-"));
    ap(F1("%s);\n", ecode(e)));
}
void do_perf_thru(char *a, char *b)
{
    if (g_pass != 2) return;
    int s = prog_parstart[g_progidx]; int e = s + prog_parcount[g_progidx];
    int ia = -1, ib = -1, i;
    for (i = s; i < e; i++) { if (strcmp(par_cn[i], a) == 0) ia = i; if (strcmp(par_cn[i], b) == 0) ib = i; }
    if (ia < 0 || ib < 0) return;
    for (i = ia; i <= ib; i++) ap(j3(pgname(par_cn[i]), "();\n", ""));
}

void prog_begin()
{
    g_progidx++; nsy = 0; g_nusing = 0; g_inlinkage = 0; g_progid = "PROG"; g_inits = "";
    g_lvlsp = 0; g_curfd = 0; nfl = 0;
    if (g_pass == 1) prog_parstart[g_progidx] = npar;
}
void proc_start()
{
    if (g_pass == 1) { par_cn[npar++] = "__main0"; return; }
    int i; int s = prog_parstart[g_progidx]; int n = prog_parcount[g_progidx];
    for (i = s; i < s + n; i++) ap(F1("void %s(void);\n", pgname(par_cn[i])));
    ap(j3("void ", mainpar(), "(void) {\n")); ap(g_inits);
}
void new_para(char *nm)
{
    if (g_pass == 1) { par_cn[npar++] = nm; return; }
    ap("}\n"); ap(j3("void ", pgname(nm), "(void) {\n"));
}
void proc_end()
{
    if (g_pass == 1) { prog_parcount[g_progidx] = npar - prog_parstart[g_progidx]; return; }
    ap("}\n");
    int i; int s = prog_parstart[g_progidx]; int n = prog_parcount[g_progidx];
    int ismain = (g_progidx == 0 && g_nusing == 0);
    if (ismain)
    {
        ap("int main(int argc, char** argv) {\n__goback = 0;\n");
        for (i = s; i < s + n; i++) ap(j3(pgname(par_cn[i]), "(); if (__goback) return 0;\n", ""));
        ap("return 0;\n}\n");
    }
    else
    {
        char *sig = "";
        for (i = 0; i < g_nusing; i++) { int si = sy_find(g_using[i]); int c = (si >= 0) ? sy_cls[si] : C_NUM; char *pt = (c == C_NUM) ? "int* " : (c == C_DEC) ? "double* " : "char* "; char *p = j3(pt, "p_", san(g_using[i])); sig = (i == 0) ? p : j3(sig, ", ", p); }
        ap(j4("void cob_", san(g_progid), "(", j3(sig, ") {\n", "")));
        for (i = 0; i < g_nusing; i++) ap(j4(cvar(g_using[i]), " = p_", san(g_using[i]), ";\n"));
        ap("__goback = 0;\n");
        for (i = s; i < s + n; i++) ap(j3(pgname(par_cn[i]), "(); if (__goback) return;\n", ""));
        ap("}\n");
    }
}
void do_call_cob(char *name)
{
    if (g_pass != 2) return;
    char *up = san(name); int i = 0; while (up[i]) { if (up[i] >= 'a' && up[i] <= 'z') up[i] = up[i] - 32; i++; }
    char *args = "";
    for (i = 0; i < g_ncall; i++)
    {
        int e = g_call[i]; char *c = ecode(e); int cl = ecls(e); char *aref;
        if (cl == C_ALNUM || cl == C_EDIT) aref = c;
        else if (((struct E *)e)->lval) aref = F1("&(%s)", c);
        else { char *tn = j2("__cc", istr(g_ctmp++)); apd(j3((etype(e) == T_REAL) ? "double " : "int ", tn, ";\n")); ap(F2("%s = %s;\n", tn, c)); aref = j2("&", tn); }
        args = (i == 0) ? aref : j3(args, ", ", aref);
    }
    ap(j4("cob_", up, "(", j3(args, ");\n", "")));
}

void leaves(int rec, int *out, int *n)
{
    int k; *n = 0;
    for (k = rec + 1; k < nsy && sy_level[k] > sy_level[rec]; k++)
        if (sy_cls[k] != C_GROUP && sy_cls[k] != C_88) out[(*n)++] = k;
}
int leafE(int k)
{
    char *code = sy_cname[k];
    if (sy_ref[k] && (sy_cls[k] == C_NUM || sy_cls[k] == C_DEC)) code = F1("(*%s)", code);
    int h = mkE(code, cls2ty(sy_cls[k]));
    int dg = (sy_cls[k] == C_ALNUM || sy_cls[k] == C_EDIT) ? sy_len[k] : sy_dig[k];
    struct E *e = (struct E *)h; e->lval = 1; e->cls = sy_cls[k]; e->dig = dg; e->dec = sy_dec[k]; e->edit = sy_edit[k]; e->idx = k;
    return h;
}
void move_group(int src, int dst)
{
    int sl[256], dl[256], ns, nd, i; leaves(src, sl, &ns); leaves(dst, dl, &nd);
    int n = (ns < nd) ? ns : nd;
    for (i = 0; i < n; i++) move_one(leafE(dl[i]), leafE(sl[i]));
}
int fwidth(int k) { return (sy_cls[k] == C_NUM) ? sy_dig[k] : (sy_cls[k] == C_DEC) ? sy_dig[k] + sy_dec[k] : sy_len[k]; }

int fl_find(char *nm) { int i; for (i = 0; i < nfl; i++) if (strcmp(fl_log[i], nm) == 0) return i; return -1; }
int rec_for_file(char *log) { int i; for (i = 0; i < nsy; i++) if (sy_file[i] && strcmp(sy_file[i], log) == 0 && sy_level[i] == 1) return i; return -1; }
void def_file(char *log, char *phys)
{
    fl_log[nfl] = log; fl_phys[nfl] = phys; fl_status[nfl] = g_selstatus; g_selstatus = 0; nfl++;
    if (g_pass == 2) { char *s = san(log); apd(j3("int fh_", s, ";\n")); apd(j3("int eof_", s, ";\n")); apd(j3("char ln_", s, "[1024];\n")); }
}
void def_file_status(char *nm) { g_selstatus = nm; }
void do_open(char *nm)
{
    if (g_pass != 2) return;
    int fi = fl_find(nm); if (fi < 0) return;
    char *s = san(nm); char *mode = (g_openmode == 0) ? "\"r\"" : (g_openmode == 1) ? "\"w\"" : "\"a\"";
    ap(j2(F2("fh_%s = fopen(%s, ", s, cstr(fl_phys[fi])), j2(mode, ");\n")));
    ap(F1("eof_%s = 0;\n", s));
}
void do_close(char *nm)
{
    if (g_pass != 2) return;
    char *s = san(nm); ap(F2("if (fh_%s) fclose(fh_%s);\n", s, s));
}
void emit_unpack(int rec, char *s)
{
    int lf[256], n, i; leaves(rec, lf, &n);
    for (i = 0; i < n; i++)
    {
        int k = lf[i]; char *v = sy_cname[k]; int w = fwidth(k);
        if (sy_cls[k] == C_ALNUM || sy_cls[k] == C_EDIT) ap(j2(F2("__rd_str(ln_%s, &__off, %s, ", s, v), Fi("%d);\n", w)));
        else if (sy_cls[k] == C_DEC) { ap(F2("%s = __rd_dec(ln_%s, &__off, ", v, s)); ap(j2(Fi("%d, ", sy_dig[k]), Fi("%d);\n", sy_dec[k]))); }
        else ap(j2(F2("%s = __rd_num(ln_%s, &__off, ", v, s), Fi("%d);\n", w)));
    }
}
void do_read_simple(char *nm)
{
    g_readrec = rec_for_file(nm);
    if (g_pass != 2) return;
    g_readfile = san(nm); char *s = g_readfile;
    ap("{ int __rok;\n");
    ap(F2("__rok = (fgets(ln_%s, 1024, fh_%s) != 0);\n", s, s));
    ap("if (__rok) {\n");
    ap("int __off = 0; int __i = 0;\n");
    ap(F1("while (ln_%s[__i]", s)); ap(F2(" && ln_%s[__i] != 10 && ln_%s[__i] != 13) __i++;\n", s, s)); ap(F1("ln_%s[__i] = 0;\n", s));
    emit_unpack(g_readrec, s);
    ap(F1("eof_%s = 0;\n", s));
    ap(F1("} else { eof_%s = 1; }\n", s));
    int fi = fl_find(nm);
    if (fi >= 0 && fl_status[fi]) { int si = sy_find(fl_status[fi]); if (si >= 0) ap(F1("__movestr(%s, __rok ? \"00\" : \"10\", 2);\n", sy_cname[si])); }
}
void do_read_into2(int tgt)
{
    if (g_pass != 2) return;
    if (eidx(tgt) >= 0 && g_readrec >= 0) { ap("if (__rok) {\n"); move_group(g_readrec, eidx(tgt)); ap("}\n"); }
}
void do_write(char *nm)
{
    if (g_pass != 2) return;
    int ri = sy_find(nm); if (ri < 0 || sy_file[ri] == 0) return;
    char *s = san(sy_file[ri]);
    if (g_writefrom) move_group(eidx(g_writefrom), ri);
    ap("{ char __wl[1024]; int __off = 0;\n");
    int lf[256], n, i; leaves(ri, lf, &n);
    for (i = 0; i < n; i++)
    {
        int k = lf[i]; char *v = sy_cname[k]; int w = fwidth(k);
        if (sy_cls[k] == C_ALNUM || sy_cls[k] == C_EDIT) ap(j2(F1("__wr_str(__wl, &__off, %s, ", v), Fi("%d);\n", w)));
        else if (sy_cls[k] == C_DEC) { ap(F1("__wr_dec(__wl, &__off, %s, ", v)); ap(j2(Fi("%d, ", sy_dig[k]), Fi("%d);\n", sy_dec[k]))); }
        else ap(j2(F1("__wr_num(__wl, &__off, %s, ", v), Fi("%d);\n", w)));
    }
    ap("__wl[__off] = 0;\n");
    ap(F1("fprintf(fh_%s, \"%%s\\n\", __wl);\n", s));
    ap("}\n");
}
int sy_find_of(char *field, char *rec)
{
    int i; for (i = nsy - 1; i >= 0; i--)
        if (strcmp(sy_name[i], field) == 0) { int a = i; while (a >= 0) { if (strcmp(sy_name[a], rec) == 0) return i; a = sy_parent[a]; } }
    return -1;
}
int qualref(char *field, char *rec)
{
    int i = sy_find_of(field, rec);
    if (i < 0) return mkE(cvar(field), T_INT);
    return leafE(i);
}
int round_e(int e)
{
    char *c = ecode(e); char *x = j3("((int)(((", c, ") >= 0) ? ((");
    x = j3(x, c, ") + 0.5) : ((");
    x = j3(x, c, ") - 0.5)))");
    return mkE(x, T_INT);
}
void do_corr(char *s, char *d, int isadd)
{
    if (g_pass != 2) return;
    int si = sy_find(s), di = sy_find(d); if (si < 0 || di < 0) return;
    int sl[256], dl[256], ns, nd, i, j; leaves(si, sl, &ns); leaves(di, dl, &nd);
    for (i = 0; i < ns; i++)
        for (j = 0; j < nd; j++)
            if (strcmp(sy_name[sl[i]], sy_name[dl[j]]) == 0)
            {
                if (isadd) { int de = leafE(dl[j]), se = leafE(sl[i]); ap(F2("%s = %s + ", ecode(de), ecode(de))); ap(F1("(%s);\n", ecode(se))); }
                else move_one(leafE(dl[j]), leafE(sl[i]));
                break;
            }
}
void search_begin(char *nm)
{
    g_searchtab = sy_find(nm);
    if (g_pass != 2) return;
    g_atendbuf = "";
    char *idx = (g_searchtab >= 0) ? sy_idx[g_searchtab] : 0;
    g_searchidx = idx ? cvar(idx) : "__noidx";
    int occ = (g_searchtab >= 0) ? sy_occ[g_searchtab] : 0;
    ap("{ int __found = 0;\n");
    ap(F2("while (%s <= %s && __found == 0) {\n", g_searchidx, istr(occ)));
}
void searchend()
{
    if (g_pass != 2) return;
    ap(F2("if (__found == 0) %s = %s + 1;\n", g_searchidx, g_searchidx));
    ap("}\n");
    ap("if (__found == 0) {\n"); ap(g_atendbuf); ap("}\n");
    ap("}\n");
}

char *PRELUDE =
"int __goback;\n"
"void __disp_num(int v,int d){char t[40];int neg=0;int n=0;if(v<0){neg=1;v=-v;}if(v==0)t[n++]='0';while(v>0){t[n++]='0'+v%10;v/=10;}while(n<d)t[n++]='0';char b[48];int j=0;if(neg)b[j++]='-';while(n>0)b[j++]=t[--n];b[j]=0;printf(\"%s\",b);}\n"
"void __disp_dec(double v,int dec){int neg=v<0;if(neg)v=-v;int sc=1,k;for(k=0;k<dec;k++)sc*=10;int n=(int)(v*sc+0.5);int ip=n/sc;int fp=n%sc;if(neg)printf(\"-\");printf(\"%d\",ip);if(dec>0){char fb[20];int j;for(j=dec-1;j>=0;j--){fb[j]='0'+fp%10;fp/=10;}fb[dec]=0;printf(\".%s\",fb);}}\n"
"void __movestr(char*d,char*s,int len){int i=0;while(i<len&&s[i]){d[i]=s[i];i++;}while(i<len)d[i++]=' ';d[len]=0;}\n"
"void __accept_str(char*d){char b[256];if(fgets(b,256,stdin)){int i=0;while(b[i]&&b[i]!='\\n')i++;b[i]=0;strcpy(d,b);}}\n"
"void __fill(char*d,int c,int len){int i;for(i=0;i<len;i++)d[i]=c;d[len]=0;}\n"
"char* __substr(char*s,int start,int len){static char b[8][256];static int bi=0;char*r=b[bi];bi=(bi+1)&7;int i;int sl=strlen(s);for(i=0;i<len&&start+i<sl;i++)r[i]=s[start+i];r[i]=0;return r;}\n"
"void __strapp(char*d,int*pos,char*s,char*delim,int dl){int i=0;int dn=strlen(delim);while(s[i]&&*pos<dl){if(dn){int k=0;while(k<dn&&s[i+k]==delim[k])k++;if(k==dn)break;}d[*pos]=s[i];(*pos)++;i++;}d[*pos]=0;}\n"
"void __unstr(char*s,char*delim,int*pos,char*d,int dl){int p=*pos;int i=0;int dn=strlen(delim);while(s[p]&&i<dl){if(dn){int k=0;while(k<dn&&s[p+k]==delim[k])k++;if(k==dn)break;}d[i++]=s[p++];}while(i<dl)d[i++]=' ';d[dl]=0;if(s[p]&&dn)p+=dn;*pos=p;}\n"
"int __tally(char*s,char*lit){int n=0,i=0;int ln=strlen(lit);if(!ln)return 0;while(s[i]){int k=0;while(k<ln&&s[i+k]==lit[k])k++;if(k==ln){n++;i+=ln;}else i++;}return n;}\n"
"void __replace(char*s,char*from,char*to){int ln=strlen(from);if(!ln||strlen(to)!=ln)return;int i=0;while(s[i]){int k=0;while(k<ln&&s[i+k]==from[k])k++;if(k==ln){int j;for(j=0;j<ln;j++)s[i+j]=to[j];i+=ln;}else i++;}}\n"
"char* __upper(char*s){static char b[4][256];static int bi=0;char*r=b[bi];bi=(bi+1)&3;int i=0;while(s[i]){r[i]=(s[i]>='a'&&s[i]<='z')?s[i]-32:s[i];i++;}r[i]=0;return r;}\n"
"char* __lower(char*s){static char b[4][256];static int bi=0;char*r=b[bi];bi=(bi+1)&3;int i=0;while(s[i]){r[i]=(s[i]>='A'&&s[i]<='Z')?s[i]+32:s[i];i++;}r[i]=0;return r;}\n"
"char* __reverse(char*s){static char b[4][256];static int bi=0;char*r=b[bi];bi=(bi+1)&3;int n=strlen(s),i;for(i=0;i<n;i++)r[i]=s[n-1-i];r[n]=0;return r;}\n"
"int __isnum(char*s){int i=0,any=0;while(s[i]){if(s[i]!=' '){if(s[i]<'0'||s[i]>'9')return 0;any=1;}i++;}return any;}\n"
"int __isalpha(char*s){int i=0,any=0;while(s[i]){if(s[i]!=' '){if(!((s[i]>='A'&&s[i]<='Z')||(s[i]>='a'&&s[i]<='z')))return 0;any=1;}i++;}return any;}\n"
"void __edit(char*out,double dv,char*pic){int L=strlen(pic);int fd=0,sd=0,i;for(i=0;i<L;i++){if(pic[i]=='.')sd=1;else if(sd&&(pic[i]=='9'||pic[i]=='Z'))fd++;}int idn=0;for(i=0;i<L;i++){if(pic[i]=='.')break;if(pic[i]=='9'||pic[i]=='Z')idn++;}int neg=dv<0;double a=neg?-dv:dv;int sc=1,k;for(k=0;k<fd;k++)sc*=10;int nn=(int)(a*sc+0.5);int ip=nn/sc;int fp=nn%sc;char id[32];int ic=0;if(ip==0)id[ic++]='0';while(ip>0){id[ic++]='0'+ip%10;ip/=10;}char fdg[20];for(k=fd-1;k>=0;k--){fdg[k]='0'+fp%10;fp/=10;}fdg[fd]=0;int o=0,dp=0,started=0;for(i=0;i<L;i++){char c=pic[i];if(c=='.')break;if(c=='9'||c=='Z'){int sl=idn-dp;char dd=(sl<=ic)?id[sl-1]:'0';if(c=='Z'&&!started&&dd=='0'){out[o++]=' ';}else{started=1;out[o++]=dd;}dp++;}else if(c==','){out[o++]=started?',':' ';}else if(c=='$'){out[o++]='$';}else if(c=='-'){out[o++]=neg?'-':' ';}else if(c=='+'){out[o++]=neg?'-':'+';}else{out[o++]=c;}}if(fd>0){out[o++]='.';for(k=0;k<fd;k++)out[o++]=fdg[k];}out[o]=0;}\n"
"void __wr_str(char*b,int*o,char*s,int w){int i=0;while(i<w&&s[i]){b[*o]=s[i];(*o)++;i++;}while(i<w){b[*o]=' ';(*o)++;i++;}}\n"
"void __wr_num(char*b,int*o,int v,int w){char t[32];int i;if(v<0)v=-v;for(i=w-1;i>=0;i--){t[i]='0'+v%10;v/=10;}for(i=0;i<w;i++){b[*o]=t[i];(*o)++;}}\n"
"void __wr_dec(char*b,int*o,double v,int dig,int dec){int sc=1,k;for(k=0;k<dec;k++)sc*=10;int n=(int)(v*sc+0.5);__wr_num(b,o,n,dig+dec);}\n"
"void __rd_str(char*l,int*o,char*d,int w){int i;for(i=0;i<w;i++){d[i]=l[*o]?l[*o]:' ';if(l[*o])(*o)++;}d[w]=0;}\n"
"int __rd_num(char*l,int*o,int w){int v=0,i;for(i=0;i<w;i++){if(l[*o]>='0'&&l[*o]<='9')v=v*10+(l[*o]-'0');if(l[*o])(*o)++;}return v;}\n"
"double __rd_dec(char*l,int*o,int dig,int dec){int n=__rd_num(l,o,dig+dec);int sc=1,k;for(k=0;k<dec;k++)sc*=10;return (double)n/sc;}\n"
"void __setsub(char*b,int start,int len,char*s){int p=start-1;int i=0;while(i<len&&s[i]){b[p+i]=s[i];i++;}while(i<len){b[p+i]=' ';i++;}}\n";

void setext(char *p, char *e) { int n = strlen(p), i = n - 1; while (i > 0 && p[i] != '.' && p[i] != '\\' && p[i] != '/') i--; if (p[i] == '.') p[i + 1] = 0; else strcat(p, "."); strcat(p, e); }

int main(int argc, char **argv)
{
    if (argc < 2) { printf((int)"usage: cobol <file.cob> [-o out] [--dll]\n"); return 1; }
    char *in = (char *)argv[1]; char *o = 0; int dll = 0; int i;
    for (i = 2; i < argc; i++) { if (strcmp((char *)argv[i], "-o") == 0 && i + 1 < argc) o = (char *)argv[++i]; else if (strcmp((char *)argv[i], "--dll") == 0) dll = 1; }
    char outp[1024], cpath[1024];
    if (o) strcpy(outp, o); else { strcpy(outp, in); setext(outp, "exe"); }
    strcpy(cpath, outp); setext(cpath, "c");
    char *src = (char *)rt_slurp((int)in);
    if (src == 0) { printf((int)"cobol: cannot read %s\n", (int)in); return 1; }
    nsy = 0; npar = 0; g_inits = ""; g_progidx = -1; g_ctmp = 0; g_singleprog = 0; g_pass = 1; pline = 1; yy_scan_string((int)src); yyparse();
    g_singleprog = (g_progidx == 0);
    nsy = 0; g_progidx = -1; g_ctmp = 0; g_pass = 2; pline = 1; g_out = ""; g_data = ""; g_inits = ""; yy_scan_string((int)src); yyparse();
    int f = fopen((int)cpath, (int)"w"); fputs((int)PRELUDE, f); fputs((int)g_data, f); fputs((int)g_out, f); fclose(f);
    char cc[1100]; char *repo = (char *)rt_repo();
    sprintf((int)cc, (int)"%s\\src\\Cc\\bin\\Release\\net10.0\\cc.exe", (int)repo);
    int av[8]; char icon[1100]; int n = 0; sprintf((int)icon, (int)"%s\\icons\\cobol.png", (int)repo);
    av[n++] = (int)cc; av[n++] = (int)cpath; av[n++] = (int)"-o"; av[n++] = (int)outp; av[n++] = dll ? (int)"--dll" : (int)"--exe"; av[n++] = (int)"--icon"; av[n++] = (int)icon;
    int rc = sh_run((int)av, n);
    if (rc == 0) printf((int)"cobol: %s -> %s\n", (int)in, (int)outp);
    else printf((int)"cobol: cc failed (%d)\n", rc);
    return rc;
}
