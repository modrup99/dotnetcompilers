stars(0) :- !.
stars(N) :- write(*), N1 is N - 1, stars(N1).
tri(Max, Max).
tri(Max, I) :- I < Max, stars(I), nl, I1 is I + 1, tri(Max, I1).
?- tri(5, 1).
