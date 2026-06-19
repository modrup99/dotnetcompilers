; ============================================================
;  A Lisp COMPILER written in Lisp: compiles an arithmetic/if/let
;  sublanguage to flat stack-machine bytecode, plus a VM to run it.
;  (Runs on our C-hosted Lisp interpreter, which runs on .NET IL.)
; ============================================================

(define (op-instr o)
  (cond ((eq? o (quote +)) (quote ADD))
        ((eq? o (quote -)) (quote SUB))
        ((eq? o (quote *)) (quote MUL))
        ((eq? o (quote <)) (quote LT))
        ((eq? o (quote =)) (quote EQ))
        (else (quote NOP))))

; compile an expression to a list of instructions
(define (comp e)
  (cond ((number? e) (list (list (quote PUSH) e)))
        ((symbol? e) (list (list (quote LOAD) e)))
        ((eq? (car e) (quote if))
         (let ((c (comp (cadr e))) (th (comp (caddr e))) (el (comp (cadddr e))))
           (append c
             (append (list (list (quote JZ) (+ (length th) 1)))
               (append th
                 (append (list (list (quote JMP) (length el))) el))))))
        ((eq? (car e) (quote let))
         (let ((b (car (cadr e))))
           (append (comp (cadr b))
             (append (list (list (quote STORE) (car b)))
                     (comp (caddr e))))))
        (else
         (append (comp (cadr e))
           (append (comp (caddr e))
                   (list (list (op-instr (car e)))))))))

; --- the stack VM ---
(define (nth n l) (if (= n 0) (car l) (nth (- n 1) (cdr l))))
(define (run code) (vm code 0 (quote ()) (quote ())))
(define (vm code pc st env)
  (if (>= pc (length code)) (car st)
    (let ((i (nth pc code)))
      (cond
        ((eq? (car i) (quote PUSH))  (vm code (+ pc 1) (cons (cadr i) st) env))
        ((eq? (car i) (quote LOAD))  (vm code (+ pc 1) (cons (cdr (assoc (cadr i) env)) st) env))
        ((eq? (car i) (quote STORE)) (vm code (+ pc 1) (cdr st) (cons (cons (cadr i) (car st)) env)))
        ((eq? (car i) (quote ADD))   (vm code (+ pc 1) (cons (+ (cadr st) (car st)) (cddr st)) env))
        ((eq? (car i) (quote SUB))   (vm code (+ pc 1) (cons (- (cadr st) (car st)) (cddr st)) env))
        ((eq? (car i) (quote MUL))   (vm code (+ pc 1) (cons (* (cadr st) (car st)) (cddr st)) env))
        ((eq? (car i) (quote LT))    (vm code (+ pc 1) (cons (if (< (cadr st) (car st)) 1 0) (cddr st)) env))
        ((eq? (car i) (quote EQ))    (vm code (+ pc 1) (cons (if (= (cadr st) (car st)) 1 0) (cddr st)) env))
        ((eq? (car i) (quote JZ))    (if (= (car st) 0) (vm code (+ pc 1 (cadr i)) (cdr st) env) (vm code (+ pc 1) (cdr st) env)))
        ((eq? (car i) (quote JMP))   (vm code (+ pc 1 (cadr i)) st env))
        (else (car st))))))

(define p1 (quote (let ((x 3))  (if (< x 5) (* x 2) (+ x 100)))))
(define p2 (quote (let ((x 10)) (if (< x 5) (* x 2) (+ x 100)))))
(define p3 (quote (* (+ 2 3) (- 10 4))))
(display "bytecode for p3: ") (print (comp p3))
(display "run p3  = ") (print (run (comp p3)))
(display "run p1 (x=3)  = ") (print (run (comp p1)))
(display "run p2 (x=10) = ") (print (run (comp p2)))
