i = 0
top:
i = i + 1
PRINT "i ="; i
IF i < 3 THEN GOTO top
PRINT "loop done"
GOTO 100
PRINT "this should be skipped"
100
PRINT "jumped to line 100"
