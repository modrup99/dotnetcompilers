%{
/* minishell — read a line, parse it into a command tree, walk the tree and run it.
 *
 * Grammar in one breath:   list -> andlist (';' andlist)*
 *                          andlist -> cmd ('&&' cmd)*
 *                          cmd -> WORD+
 *
 * The parser builds no output text at all; it builds a tiny AST and main()
 * interprets it. That split (parse -> tree -> walk) is the same shape as
 * shell/shell.y, just with ten productions instead of forty.
 *
 * External commands go through sh_run(argv, argc) from CRuntime: argv is the
 * address of an array of int, each int being a char* to a NUL-terminated
 * argument, argv[0] the program. sh_run does Process.Start + WaitForExit and
 * returns the child's exit code (127 if the program was not found).
 */

enum { NSEQ = 1, NAND, NCMD };

struct Node  { int kind; int a; int b; };     /* NSEQ/NAND: a,b = children. NCMD: a = word list */
struct Words { int n; int w[64]; };           /* w[i] holds a char* as an int */

int root;                                     /* the tree the current line parsed to */

int mknode(int kind, int a, int b)
{
    struct Node *n = (struct Node *)malloc(sizeof(struct Node));
    n->kind = kind; n->a = a; n->b = b;
    return (int)n;
}
int wnew(void)
{
    struct Words *w = (struct Words *)malloc(sizeof(struct Words));
    w->n = 0;
    return (int)w;
}
int wadd(int h, int s)
{
    struct Words *w = (struct Words *)h;
    if (w->n < 64) w->w[w->n++] = s;
    return h;
}

int yylex();
%}

%token WORD AND_IF
%start line
%%
line    : /* empty */          { root = 0; }          /* a blank line runs nothing */
        | list                 { root = $1; }
        ;

list    : andlist              { $$ = $1; }
        | list ';' andlist     { $$ = mknode(NSEQ, $1, $3); }
        | list ';'             { $$ = $1; }           /* tolerate a trailing ';' */
        ;

andlist : cmd                  { $$ = $1; }
        | andlist AND_IF cmd   { $$ = mknode(NAND, $1, $3); }
        ;

cmd     : words                { $$ = mknode(NCMD, $1, 0); }
        ;

words   : WORD                 { $$ = wadd(wnew(), $1); }
        | words WORD           { $$ = wadd($1, $2); }
        ;
%%

/* ---- execution ---- */

/* Run one simple command. This is also where builtins belong: anything that has
 * to change the shell's own state (cd, exit, variable assignment) cannot be a
 * child process, so it is handled before sh_run is reached. */
int run_cmd(int wl)
{
    struct Words *w = (struct Words *)wl;
    if (w->n == 0) return 0;

    char *cmd = (char *)w->w[0];
    if (strcmp(cmd, "exit") == 0) exit(0);            /* the one builtin we keep */

    int *av = (int *)malloc(w->n * 4);                /* argv: array of char* as int */
    int i;
    for (i = 0; i < w->n; i++) av[i] = w->w[i];
    return sh_run((int)av, w->n);                     /* returns the child's exit code */
}

/* Walk the tree. The return value is the exit status, which is what makes &&
 * work: the right-hand side only runs if the left-hand side succeeded (0). */
int exec(int node)
{
    if (node == 0) return 0;
    struct Node *n = (struct Node *)node;
    if (n->kind == NSEQ) { exec(n->a); return exec(n->b); }
    if (n->kind == NAND) { int s = exec(n->a); if (s != 0) return s; return exec(n->b); }
    return run_cmd(n->a);
}

int main(int argc, char **argv)
{
    char line[4096];
    while (1)
    {
        int n = 0; int ch;
        while ((ch = getchar()) != -1 && ch != '\n') { if (ch != 13 && n < 4090) line[n++] = (char)ch; }
        if (ch == -1 && n == 0) break;
        line[n++] = '\n'; line[n] = 0;

        root = 0;
        yy_scan_string((int)line);                    /* point the scanner at this line */
        if (yyparse() == 0) exec(root);               /* parse, then interpret */
        if (ch == -1) break;
    }
    return 0;
}
