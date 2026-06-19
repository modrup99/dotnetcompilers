PRINT "Hello, QBasic!"
DIM i AS INTEGER
FOR i = 1 TO 5
  PRINT i; "squared ="; i * i
NEXT i
x = 3.5
y = 2
PRINT "x + y ="; x + y
a$ = "hello"
b$ = "world"
PRINT a$ + " " + b$
PRINT "UCASE:"; UCASE$(a$); " LEN:"; LEN(a$)
PRINT "cube(3) ="; cube(3)
IF x > y THEN
  PRINT "x is bigger"
ELSE
  PRINT "y is bigger"
END IF
n = 1
WHILE n <= 3
  PRINT "n ="; n
  n = n + 1
WEND
FOR j = 10 TO 1 STEP -3
  PRINT "down"; j
NEXT j
SELECT CASE i
  CASE 1, 2
    PRINT "small"
  CASE 6
    PRINT "it is six"
  CASE ELSE
    PRINT "other"
END SELECT

FUNCTION cube (n)
  cube = n * n * n
END FUNCTION
