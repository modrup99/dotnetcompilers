# demo script for ilsh   (run: dotnet out/ilsh.dll < shell/demo.sh)
echo hello world
X=42
NAME=ilsh
echo $NAME says X is $X

if test $X -eq 42; then echo "answer correct"; else echo wrong; fi
if [ "$NAME" = "ilsh" ]; then echo name-ok; fi

for f in alpha beta gamma; do echo item: $f; done

echo single 'quotes $X stay literal'
echo double "quotes $X expand"

true && echo and-works
false || echo or-works

# aliases (so `vi file` opens your editor, `ll` is `ls -l`)
alias ll='ls -l'
alias vi='notepad++'

# built-in coreutils + pipelines (all in-process)
echo banana >  out/fruit.txt
echo apple  >> out/fruit.txt
echo cherry >> out/fruit.txt
ll out
cat out/fruit.txt | sort | grep a
wc out/fruit.txt
find . -name "*.txt"
