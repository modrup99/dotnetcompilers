x = 10
y = 20
PRINT "before:"; x; y
CALL Swap(x, y)
PRINT "after:"; x; y
PRINT "cube(3) ="; Cube(3)
z = 5
CALL AddOne(z)
PRINT "addone:"; z

FUNCTION Cube (n)
  Cube = n * n * n
END FUNCTION
SUB Swap (a, b)
  t = a
  a = b
  b = t
END SUB
SUB AddOne (n)
  n = n + 1
END SUB
