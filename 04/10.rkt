#lang eopl
;; Implement the begin expression.
(require "./base/store.rkt")

;;;;;;;;;;;;;;;; expressed values ;;;;;;;;;;;;;;;;
(define the-lexical-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier
     (letter (arbno (or letter digit "_" "-" "?")))
     symbol)
    (number (digit (arbno digit)) number)
    (number ("-" digit (arbno digit)) number)
    ))

(define the-grammar
  '((program (expression) a-program)

    (expression (number) const-exp)
    (expression ("-" "(" expression "," expression ")") diff-exp)

    (expression ("zero?" "(" expression ")") zero?-exp)

    (expression ("if" expression "then" expression "else" expression) if-exp)

    (expression (identifier) var-exp)

    (expression ("let" identifier "=" expression "in" expression) let-exp)

    (expression  ("proc" "(" identifier ")" expression) proc-exp)

    (expression ("(" expression expression ")") call-exp)

    (expression ("letrec"  (arbno identifier "(" identifier ")" "=" expression) "in" expression) letrec-exp)

    ;; new stuff
    (expression ("begin" expression (arbno ";" expression) "end") begin-exp)

    (expression ("newref" "(" expression ")") newref-exp)

    (expression ("deref" "(" expression ")") deref-exp)

    (expression ("setref" "(" expression "," expression ")") setref-exp)
    ))

  ;;;;;;;;;;;;;;;; sllgen boilerplate ;;;;;;;;;;;;;;;;

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define show-the-datatypes
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))


;;; an expressed value is either a number, a boolean, a procval, or a
;;; reference.
(define-datatype expval expval?
  (num-val
   (value number?))
  (bool-val
   (boolean boolean?))
  (proc-val
   (proc proc?))
  (ref-val ;; 引用类型
   (ref reference?))
  )

;;; extractors:
(define expval->num
  (lambda (v)
    (cases expval v
	   (num-val (num) num)
	   (else (expval-extractor-error 'num v)))))

(define expval->bool
  (lambda (v)
    (cases expval v
	   (bool-val (bool) bool)
	   (else (expval-extractor-error 'bool v)))))

(define expval->proc
  (lambda (v)
    (cases expval v
	   (proc-val (proc) proc)
	   (else (expval-extractor-error 'proc v)))))

(define expval->ref
  (lambda (v)
    (cases expval v
	   (ref-val (ref) ref)
	   (else (expval-extractor-error 'reference v)))))

(define expval-extractor-error
  (lambda (variant value)
    (eopl:error 'expval-extractors "Looking for a ~s, found ~s"
		variant value)))

;;;;;;;;;;;;;;;; procedures ;;;;;;;;;;;;;;;;

(define-datatype proc proc? ;; 函数类型
  (procedure
   (bvar symbol?)
   (body expression?)
   (env environment?)))

(define-datatype environment environment?
  (empty-env)
  (extend-env
   (bvar symbol?)
   (bval expval?)
   (saved-env environment?))
  (extend-env-rec*
   (proc-names (list-of symbol?)) ;; 好吧，不得不说，这个玩意还是很厉害的。
   (b-vars (list-of symbol?))
   (proc-bodies (list-of expression?))
   (saved-env environment?)))

(define init-env
  (lambda ()
    (empty-env)))

;;;;;;;;;;;;;;;; environment constructors and observers ;;;;;;;;;;;;;;;;
(define apply-env
  (lambda (env search-sym)
    (cases environment env
           (empty-env ()
                      (eopl:error 'apply-env "No binding for ~s" search-sym))
           (extend-env (bvar bval saved-env)
                       (if (eqv? search-sym bvar)
                           bval
                           (apply-env saved-env search-sym)))
           (extend-env-rec* (p-names b-vars p-bodies saved-env)
                            (cond
                             ((location search-sym p-names) ;; 查找函数名
                              => (lambda (n) ;; 如果前面的location函数返回了一个数
                                   (proc-val ;; 构造出一个函数
                                    (procedure
                                     (list-ref b-vars n) ;; 我没有看错吧，居然直接调用list的函数来取形式参数
                                     (list-ref p-bodies n) ;; 和对应的函数体
                                     env))))
                             (else (apply-env saved-env search-sym)))))))

(define location
  (lambda (sym syms) ;; sym是要搜寻的东西
    (cond
     ((null? syms) #f)
     ((eqv? sym (car syms)) 0)
     ((location sym (cdr syms)) ;; 继续往下找，总之location函数要么返回false，要么返回一个数嘛
      => (lambda (n) ;; 如果返回了一个数,说明要查找的这个玩意的深度要在返回的深度的基础上加1
           (+ n 1)))
     (else #f))))


;; value-of-program : Program -> ExpVal
;; Page: 110
(define value-of-program
  (lambda (pgm)
    (initialize-store!)               ; new for explicit refs.
    (cases program pgm
	   (a-program (exp1)
		      (value-of exp1 (init-env))))))

;; value-of : Exp * Env -> ExpVal
;; Page: 113
(define value-of
  (lambda (exp env)
    (cases expression exp
	   (const-exp (num) (num-val num))
	   (var-exp (var) (apply-env env var))

	   (diff-exp (exp1 exp2)
		     (let ((val1 (value-of exp1 env))
			   (val2 (value-of exp2 env)))
		       (let ((num1 (expval->num val1))
			     (num2 (expval->num val2)))
			 (num-val
			  (- num1 num2)))))

	   (zero?-exp (exp1)
		      (let ((val1 (value-of exp1 env)))
			(let ((num1 (expval->num val1)))
			  (if (zero? num1)
			      (bool-val #t)
			      (bool-val #f)))))

	   (if-exp (exp1 exp2 exp3)
		   (let ((val1 (value-of exp1 env)))
		     (if (expval->bool val1)
			 (value-of exp2 env)
			 (value-of exp3 env))))

	   (let-exp (var exp1 body)
		    (let ((val1 (value-of exp1 env)))
		      (value-of body
				(extend-env var val1 env))))

	   (proc-exp (var body)
		     (proc-val (procedure var body env)))

	   (call-exp (rator rand)
		     (let ((proc (expval->proc (value-of rator env)))
			   (arg (value-of rand env)))
		       (apply-procedure proc arg)))

	   (letrec-exp (p-names b-vars p-bodies letrec-body)
		       (value-of letrec-body
				 (extend-env-rec* p-names b-vars p-bodies env)))

	   (begin-exp (exp1 exps) ;; 这个式子只做了一件事情，从左至右执行begin的各个语句，最后将最后的语句的执行结果返回
		      (letrec
			  ((value-of-begins
			    (lambda (e1 es)
			      (let ((v1 (value-of e1 env)))
				(if (null? es)
				    v1
				    (value-of-begins (car es) (cdr es)))))))
			(value-of-begins exp1 exps)))

	   (newref-exp (exp1)
		       (let ((v1 (value-of exp1 env)))
			 (ref-val (newref v1)))) ;; 返回引用值

	   (deref-exp (exp1)
		      (let ((v1 (value-of exp1 env)))
			(let ((ref1 (expval->ref v1)))
			  (deref ref1))))

	   (setref-exp (exp1 exp2)
	   	       (let ((ref1 (expval->ref (value-of exp1 env)))
	   		     (v2 (value-of exp2 env)))
	   		 (begin
	   		   (setref! ref1 v2)
	   		   (num-val 23))))
	   )))

;; instrumented version
(define apply-procedure
  (lambda (proc1 arg)
    (cases proc proc1
	   (procedure (var body saved-env) ;; var表示变量名
		      (let ((r arg))
			(let ((new-env (extend-env var r saved-env)))
			  (value-of body new-env)))))))



(define run
  (lambda (string)
    (value-of-program (scan&parse string))))

;; test code
(run "begin if zero?(1) then 0 else 1 end")


