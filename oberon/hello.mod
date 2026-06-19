MODULE Hello;
FROM InOut IMPORT WriteString, WriteInt, WriteLn;
VAR i: INTEGER;

PROCEDURE Fact(n: INTEGER): INTEGER;
BEGIN
  IF n <= 1 THEN RETURN 1
  ELSE RETURN n * Fact(n - 1)
  END
END Fact;

BEGIN
  FOR i := 1 TO 5 DO
    WriteString("fact("); WriteInt(i, 0);
    WriteString(") = "); WriteInt(Fact(i), 0); WriteLn
  END
END Hello.
