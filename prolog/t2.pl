max(X, Y, X) :- X >= Y, !.
max(_, Y, Y).
?- max(3, 7, M).
?- max(9, 2, M).
