# An AWK file of functions, compiled as a library (awk lib.awk --dll).
# Each function becomes a public static method f_<name> on CProgram, taking and
# returning strings; a C#/VB.NET host calls awk_init() once, then calls them.
function greet(who) {
    return "hello, " who "!"
}

function fib(n) {
    if (n < 2) return n
    return fib(n - 1) + fib(n - 2)
}
