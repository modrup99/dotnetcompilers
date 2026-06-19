\ Forth test program
." Hello, Forth!" CR
5 3 + . CR
10 2 - 4 * . CR
: square DUP * ;
6 square . CR
: fib DUP 2 < IF DROP 1 ELSE DUP 1 - fib SWAP 2 - fib + THEN ;
." fib(10)=" 10 fib . CR
3.5 2.0 + . CR
." mixed " 2 3.0 + . CR
." loop: " 10 0 DO I . LOOP CR
42 CONSTANT answer
." answer=" answer . CR
VARIABLE x
7 x ! x @ . CR
." stack " 1 2 3 .S CR
