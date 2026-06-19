DIM a(5)
FOR i = 0 TO 5
  a(i) = i * i
NEXT i
FOR i = 0 TO 5
  PRINT a(i);
NEXT i
PRINT
DIM grid(3, 3)
grid(1, 2) = 99
grid(2, 1) = 42
PRINT "grid:"; grid(1, 2); grid(2, 1)
k = 0
DO
  k = k + 1
  PRINT "k ="; k
LOOP UNTIL k >= 3
s$ = "QBasic"
PRINT MID$(s$, 2, 3); " "; RIGHT$(s$, 3); " "; LEFT$(s$, 1)
PRINT "instr:"; INSTR(s$, "as")
