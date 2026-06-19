likes(sam, pizza).
likes(sam, sushi).
likes(deb, sushi).
agree(X, Y, F) :- likes(X, F), likes(Y, F).
?- likes(sam, What).
?- agree(sam, deb, Food).
