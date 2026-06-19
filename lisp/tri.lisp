(define (row n) (if (= n 0) (newline) (begin (display (quote *)) (row (- n 1)))))
(define (tri n i) (if (> i n) (quote done) (begin (row i) (tri n (+ i 1)))))
(tri 4 1)
