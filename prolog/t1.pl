parent(tom, bob).
parent(bob, ann).
parent(bob, pat).
parent(pat, jim).
grandparent(X, Z) :- parent(X, Y), parent(Y, Z).
fact(0, 1).
fact(N, F) :- N > 0, N1 is N - 1, fact(N1, F1), F is N * F1.

?- grandparent(tom, Who).
?- append(A, B, [1,2,3]).
?- member(M, [a,b,c]).
?- fact(6, F).
?- reverse([1,2,3,4], R).
?- between(1, 5, X).
?- length([a,b,c,d], N).
