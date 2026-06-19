." until: " 0 BEGIN DUP . 1+ DUP 5 > UNTIL DROP CR
." while: " 1 BEGIN DUP 4 <= WHILE DUP . 1+ REPEAT DROP CR
S" string via S-quote" TYPE CR
." 2x2 grid:" CR
3 1 DO
  3 1 DO
    I J * .
  LOOP CR
LOOP
: greet ." Hi, " TYPE ." !" CR ;
S" Ada" greet
