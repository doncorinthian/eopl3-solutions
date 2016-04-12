#lang eopl
(provide (all-defined-out))

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
  '((program
     ((arbno module-definition)
      expression)
     a-program)

    (module-definition
     ("module" identifier
      "interface" interface
      "body" module-body)
     a-module-definition)


    (interface
     ("[" (arbno declaration) "]")
     simple-iface)


    (declaration
     ("opaque" identifier)
     opaque-type-decl)

    (declaration
     ("transparent" identifier "=" type)
     transparent-type-decl)

    (declaration
     (identifier ":" type)
     val-decl)


    (module-body
     ("[" (arbno definition) "]")
     defns-module-body)


    (definition
      (identifier "=" expression)
      val-defn)

    (definition
      ("type" identifier "=" type)
      type-defn)

    ;; new expression:

    (expression
     ("from" identifier "take" identifier)
     qualified-var-exp)

    ;; new types

    (type
     (identifier)
     named-type)

    (type
     ("from" identifier "take" identifier)
     qualified-type)

    (expression (number) const-exp)

    (expression
     (identifier)
     var-exp)

    (expression
     ("-" "(" expression "," expression ")")
     diff-exp)

    (expression
     ("zero?" "(" expression ")")
     zero?-exp)

    (expression
     ("if" expression "then" expression "else" expression)
     if-exp)

    ;; 首先支持多个let声明吧!
    (expression
     ("let" (arbno identifier "=" expression )"in" expression) ;; 要支持多个let声明
     let-exp)
     ;; 接下来要实现多重参数的函数
   (expression
     ("proc" "(" (separated-list identifier ":" type ",")")" expression)
     proc-exp)
    ;; 这个部分算是一个重头戏,那就是调用多个参数
    (expression
     ("(" expression (arbno expression) ")")
     call-exp)

    ;(expression
    ; ("letrec"
    ;  type identifier "(" identifier ":" type ")"
    ;  "=" expression "in" expression)
    ; letrec-exp)
    ;; 多重letrec,好吧!
    (expression
     ("letrec"
      (separated-list type identifier "(" (separated-list identifier ":" type ",") ")"
      "=" expression ",")"in" expression)
     letrec-exp)

    (type
     ("int")
     int-type)

    (type
     ("bool")
     bool-type)

    (type
     ("(" (arbno type) "->" type ")")
     proc-type)

    ))

  ;;;;;;;;;;;;;;;; sllgen boilerplate ;;;;;;;;;;;;;;;;

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define show-the-datatypes
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))

(define just-scan
  (sllgen:make-string-scanner the-lexical-spec the-grammar))

  ;;;;;;;;;;;;;;;; syntactic tests and observers ;;;;;;;;;;;;;;;;

;;; for types
(define atomic-type?
  (lambda (ty)
    (cases type ty
      (proc-type (ty1 ty2) #f)
      (else #t))))

(define proc-type?
  (lambda (ty)
    (cases type ty
	   (proc-type (t1 t2) #t)
	   (else #f))))

(define proc-type->arg-type
  (lambda (ty)
    (cases type ty
	   (proc-type (arg-type result-type) arg-type)
	   (else (eopl:error 'proc-type->arg-type
			     "Not a proc type: ~s" ty)))))

(define proc-type->result-type
  (lambda (ty)
    (cases type ty
	   (proc-type (arg-type result-type) result-type)
	   (else (eopl:error 'proc-type->result-types
			     "Not a proc type: ~s" ty)))))

(define type-to-external-form
  (lambda (ty)
    (cases type ty
	   (int-type () 'int)
	   (bool-type () 'bool)
	   (proc-type (arg-type result-type)
		      (list
		       (type-to-external-form arg-type)
		       '->
		       (type-to-external-form result-type)))
	   (named-type (name) name)
	   (qualified-type (modname varname)
			   (list 'from modname 'take varname))
	   )))

;;; for module definitions

;; maybe-lookup-module-in-list : Sym * Listof(Defn) -> Maybe(Defn)
(define maybe-lookup-module-in-list
  (lambda (name module-defs)
    (if (null? module-defs)
        #f
        (let ([name1 (module-definition->name (car module-defs))])
          (if (eqv? name1 name)
              (car module-defs)
              (maybe-lookup-module-in-list name (cdr module-defs)))))))

;; maybe-lookup-module-in-list : Sym * Listof(Defn) -> Defn OR Error
(define lookup-module-in-list
  (lambda (name module-defs)
    (cond
      [(maybe-lookup-module-in-list name module-defs) => (lambda (mdef) mdef)]
      [else (eopl:error 'lookup-module-in-list
		  "unknown module ~s"
		  name)])))

(define module-definition->name
  (lambda (m-defn)
    (cases module-definition m-defn
	   (a-module-definition (m-name m-type m-body)
				m-name))))

(define module-definition->interface
  (lambda (m-defn)
    (cases module-definition m-defn
	   (a-module-definition (m-name m-type m-body)
				m-type))))

(define module-definition->body
  (lambda (m-defn)
    (cases module-definition m-defn
	   (a-module-definition (m-name m-type m-body)
				m-body))))

(define val-decl?
  (lambda (decl)
    (cases declaration decl
	   (val-decl (name ty) #t)
	   (else #f))))

(define transparent-type-decl?
  (lambda (decl)
    (cases declaration decl
	   (transparent-type-decl (name ty) #t)
	   (else #f))))

(define opaque-type-decl?
  (lambda (decl)
    (cases declaration decl
	   (opaque-type-decl (name) #t)
	   (else #f))))

(define decl->name
  (lambda (decl)
    (cases declaration decl
	   (opaque-type-decl (name) name)
	   (transparent-type-decl (name ty) name)
	   (val-decl (name ty) name))))

(define decl->type
  (lambda (decl)
    (cases declaration decl
	   (transparent-type-decl (name ty) ty)
	   (val-decl (name ty) ty)
	   (opaque-type-decl (name)
			     (eopl:error 'decl->type
					 "can't take type of abstract type declaration ~s"
					 decl)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 在这里的话,我们算是看到了划分模块的好处了。
;; 让一些类型相近的东西放置在一块,使得文件更好的划分。
;; 这个文件里面主要是关于data-strucure的一些事情。
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; data structures ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype expval expval? ;; 值的类型
  (num-val
   (value number?))
  (bool-val
   (boolean boolean?))
  (proc-val
   (proc proc?)))

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

(define expval-extractor-error
  (lambda (variant value)
    (eopl:error 'expval-extractors "Looking for a ~s, found ~s"
                variant value)))

;;;;;;;;;;;;;;;; procedures ;;;;;;;;;;;;;;;;
(define-datatype proc proc? ;; 好吧,所谓的过程
  (procedure
   (bvar (list-of symbol?))
   (body expression?)
   (env environment?)))

;;;;;;;;;;;;;;;; module values ;;;;;;;;;;;;;;;;
(define-datatype typed-module typed-module? ;; 模块类型
  (simple-module
   (bindings environment?))
  (proc-module
   (bvar symbol?)
   (body module-body?)
   (saved-env environment?))
  )

;;;;;;;;;;;;;;;; environments ;;;;;;;;;;;;;;;;
(define-datatype environment environment?
  (empty-env)
  (extend-env
   (bvar symbol?)
   (bval expval?)
   (saved-env environment?))
  (extend-env-recursively
   (ids (list-of symbol?))
   (bvars (list-of (list-of symbol?)))
   (body (list-of expression?))
   (saved-env environment?))
  (extend-env-with-module
   (m-name symbol?)
   (m-val typed-module?)
   (saved-env environment?)
   ))

;;;;;;;;;;;;;;;; initial environment ;;;;;;;;;;;;;;;;

;; initial-value-env : module-env -> environment

;; (init-env m-env) builds an environment in which i is bound to the
;; expressed value 1, v is bound to the expressed value 5, and x is
;; bound to the expressed value 10, and in which m-env is the module
;; environment.
(define inital-value-env
  (lambda (m-env)
    (extend-env
     'i (num-val 1)
     (extend-env
      'v (num-val 5)
      (extend-env
       'x (num-val 10)
       (empty-env m-env))))))

;;;;;;;;;;;;;;;; environment constructors and observers ;;;;;;;;;;;;;;;;

;; for variables bound by extend-env or extend-env-recursively

(define apply-env ;; 查找对应的值 
  (lambda (env search-sym)
    (cases environment env
	   (empty-env ()
		      (eopl:error 'apply-env "No value binding for ~s" search-sym))
	   (extend-env (bvar bval saved-env)
		       (if (eqv? search-sym bvar)
			   bval
			   (apply-env saved-env search-sym)))
	   (extend-env-recursively
	    (ids bvars bodies saved-env) ;; id 表示函数的名字
            (let ([maybe-answer (lookup-id-in-ids search-sym ids bvars bodies)])
              (if maybe-answer
                  (let ([vars (car maybe-answer)]
                        [body (cdr maybe-answer)])
                    (proc-val (procedure vars body env)))
                  (apply-env saved-env search-sym))))
     
	   (extend-env-with-module (m-name m-val saved-env)
				   (begin
				     (eopl:printf "\nhaha: ~s ~s\n" m-name search-sym)
				     (apply-env saved-env search-sym)) ))))

;; for names bound by extend-env-with-module
 (define lookup-id-in-ids
        (lambda (id ids bvars bodies)
          (if (null? id) #f
              (if (eqv? id (car ids)) (cons (car bvars) (car bodies))
                  (lookup-id-in-ids id (cdr ids) (cdr bvars) (cdr bodies)))))) 

;; lookup-module-name-in-env : Sym * Env -> Typed-Module
(define lookup-module-name-in-env 
  (lambda (m-name env)
    (cases environment env
	   (empty-env ()
		      (eopl:error 'lookup-module-name-in-env
				  "No module binding for ~s" m-name))
	   (extend-env (bvar bval saved-env)
		       (lookup-module-name-in-env m-name saved-env))
	   (extend-env-recursively  (id bvar body saved-env)
				    (lookup-module-name-in-env m-name saved-env))
	   (extend-env-with-module (m-name1 m-val saved-env)
	    (if (eqv? m-name1 m-name)
		m-val
		(lookup-module-name-in-env m-name saved-env))))))

;; lookup-qualified-var-in-env : Sym * Sym * Env -> ExpVal
(define lookup-qualified-var-in-env ;; qualified var究竟是什么鬼? 有意思啊。
  (lambda (m-name var-name env) 
    (let ((m-val (lookup-module-name-in-env m-name env)))
					; (pretty-print m-val)
      (cases typed-module m-val
	     (simple-module (bindings)
			    (apply-env bindings var-name))
	     (proc-module (bvar body saved-env)
			  (eopl:error 'lookup-qualified-var
				      "can't retrieve variable from ~s take ~s from proc module"
				      m-name var-name))))))

;(define expand-type (lambda (ty tenv) ty))
;(define expand-iface (lambda (m-name iface tenv) iface))


;;;;;;;;;;;;;;;; expand-type ;;;;;;;;;;;;;;;;

;; expand-type expands a type so that it contains no type
;; abbreviations. (类型的别名或者说缩写)

;; For example, if tenv contains a declaration for a module

;;   module m1
;;    interface
;;     [abstract-type t
;;      type-abbrev u = int
;;      type-abbrev v = (t -> u)]

;; then calling expand-type on from m1 take v should return
;; (from m1 take t -> int)

;; this relies on the invariant that every type returned by
;; lookup-type-name-in-tenv is already expanded.


;; expand-type : Type * Tenv -> ExpandedType
(define expand-type
  (lambda (ty tenv)
    (cases type ty
      (int-type () (int-type))
      (bool-type () (bool-type))
      (proc-type (args-type result-type)
                 (proc-type
                  (map (lambda (arg-type) (expand-type arg-type tenv)) args-type)
                  (expand-type result-type tenv)))
      (named-type (name)
                  (lookup-type-name-in-tenv tenv name))
      (qualified-type (m-name t-name)
                      (lookup-qualified-type-in-tenv m-name t-name tenv))
      )))

;; creates new interface with all types expanded
;; expand-iface : Sym * Iface * Tenv -> Iface
(define expand-iface
  (lambda (m-name iface tenv)
    (cases interface iface
      (simple-iface (decls)
                    (simple-iface
                     (expand-decls m-name decls tenv))))))

;; expand-decls : Sym * Listof(Decl) * Tenv -> Listof(Decl)
(define expand-decls
  (lambda (m-name decls internal-tenv)
    (if (null? decls) '()
        (cases declaration (car decls)
          (opaque-type-decl (t-name)
                            ;; here the expanded type is m.t
                            (let ([expanded-type (qualified-type m-name t-name)])
                              (let ([new-env (extend-tenv-with-type
                                              t-name
                                              expanded-type
                                              internal-tenv)])
                                (cons
                                 (transparent-type-decl t-name expanded-type)
                                 (expand-decls m-name (cdr decls) new-env)))))
          (transparent-type-decl (t-name ty)
                                 (let ([expanded-type (expand-type ty internal-tenv)])
                                   (let ([new-env (extend-tenv-with-type
                                                   t-name
                                                   expanded-type
                                                   internal-tenv)])
                                     (cons
                                      (transparent-type-decl t-name expanded-type)
                                      (expand-decls m-name (cdr decls) new-env)))))
          (val-decl (var-name ty)
                    (let ([expanded-type
                           (expand-type ty internal-tenv)])
                      (cons
                       (val-decl var-name expanded-type)
                       (expand-decls m-name (cdr decls) internal-tenv))))))))


(define rename-in-iface
  (lambda (m-type old new)
    (cases interface m-type
      (simple-iface (decls)
                    (simple-iface
                     (rename-in-decls decls old new))))))

;; this is not a map because we have let* scoping in a list of declarations
(define rename-in-decls
  (lambda (decls old new)
    (if (null? decls) '()
        (let ([decl (car decls)]
              [decls (cdr decls)])
          (cases declaration decl
            (val-decl (name ty)
                      (cons
                       (val-decl name (rename-in-type ty old new))
                       (rename-in-decls decls old new)))
            (opaque-type-decl (name)
                              (cons
                               (opaque-type-decl name)
                               (if (eqv? name old)
                                   decls
                                   (rename-in-decls decls old new))))
            (transparent-type-decl (name ty)
                                   (cons
                                    (transparent-type-decl
                                     name
                                     (rename-in-type ty old new))
                                    (if (eqv? name old)
                                        decls
                                        (rename-in-decls decls old new))))
            )))))

(define rename-in-type
  (lambda (ty old new)
    (let recur ((ty ty))
      (cases type ty
        (named-type (id)
                    (named-type (rename-name id old new)))
        (qualified-type (m-name name)
                        (qualified-type
                         (rename-name m-name old new)
                         name))
        (proc-type (t1 t2)
                   (proc-type (recur t1) (recur t2)))
        (else ty)
        ))))

(define rename-name
  (lambda (name old new)
    (if (eqv? name old) new name)))

(define fresh-module-name
  (let ((sn 0))
    (lambda (module-name)
      (set! sn (+ sn 1))
      (string->symbol
       (string-append
	(symbol->string module-name)
	"%"             ; this can't appear in an input identifier
	(number->string sn))))))

;; <:-iface : Iface * Iface * Tenv -> Bool
(define <:-iface
  (lambda (iface1 iface2 tenv)
    (cases interface iface1
	   (simple-iface (decls1)
			 (cases interface iface2
				(simple-iface (decls2)
					      (<:-decls decls1 decls2 tenv)))))))

;; s1 <: s2 iff s1 has at least as much stuff as s2, and in the same
;; order.  We walk down s1 until we find a declaration that declares
;; the same name as the first component of s2.  If we run off the
;; end of s1, then we fail.  As we walk down s1, we record any type
;; bindings in the tenv

;; <:-decls : Listof(Decl) * Listof(Decl) * Tenv -> Bool
(define <:-decls
  (lambda (decls1 decls2 tenv)
    (cond
     ;; if nothing in decls2, any decls1 will do
     ((null? decls2) #t)
     ;; nothing in decls1 to match, so false
     ((null? decls1) #f)
     (else
      ;; at this point we know both decls1 and decls2 are non-empty.
      (let ([name1 (decl->name (car decls1))]
            [name2 (decl->name (car decls2))])
	(if (eqv? name1 name2)
	    ;; same name.  They'd better match
	    (and
             (<:-decl (car decls1) (car decls2) tenv)
             (<:-decls (cdr decls1) (cdr decls2)
                       (extend-tenv-with-decl (car decls1) tenv)))
            ;; different names.  OK to skip, but record decl1 in the tenv.
            (<:-decls (cdr decls1) decls2
                      (extend-tenv-with-decl (car decls1) tenv))))))))

;; extend-tenv-with-decl : Decl * Tenv -> Tenv
(define extend-tenv-with-decl
  (lambda (decl tenv)
    (cases declaration decl
      ;; don't need to record val declarations
      (val-decl (name ty) tenv)
      (transparent-type-decl (name ty)
				  (extend-tenv-with-type
				   name
				   (expand-type ty tenv)
				   tenv))
	   (opaque-type-decl (name)
			     (extend-tenv-with-type
			      name
			      ;; the module name doesn't matter, since the only
			      ;; operation on qualified types is equal?
			      (qualified-type (fresh-module-name '%abstype) name)
			      tenv)))))

;; <:-decl : Decl * Decl * Tenv -> Bool
(define <:-decl
  (lambda (decl1 decl2 tenv)
    (or
     (and
      (val-decl? decl1)
      (val-decl? decl2)
      (equiv-type? (decl->type decl1) (decl->type decl2) tenv))
     (and
      (transparent-type-decl? decl1)
      (transparent-type-decl? decl2)
      (equiv-type? (decl->type decl1) (decl->type decl2) tenv))
     (and
      (transparent-type-decl? decl1)
      (opaque-type-decl? decl2))
     (and
      (opaque-type-decl? decl1)
      (opaque-type-decl? decl2))
     )))

;; equiv-type? : Type * Type * Tenv -> Bool
(define equiv-type?
  (lambda (ty1 ty2 tenv)
    (equal?
     (expand-type ty1 tenv)
     (expand-type ty2 tenv))))

(define type-of-program
  (lambda (pgm)
    (cases program pgm
      (a-program (module-defs body)
                 (type-of body
                          (add-module-defns-to-tenv module-defs (empty-tenv)))))))

;; value-of-program : Program -> Expval
(define value-of-program
  (lambda (pgm)
    (cases program pgm
      (a-program (module-defs body)
                 (let ([env (add-module-defns-to-env module-defs (empty-env))])
                   (value-of body env))))))

;; add-module-defns-to-env : Listof (Defn) * Env -> Env
(define add-module-defns-to-env
  (lambda (defs env)
    (if (null? defs) env
        (cases module-definition (car defs)
          (a-module-definition (m-name iface m-body)
                               (add-module-defns-to-env
                                (cdr defs)
                                (extend-env-with-module
                                 m-name
                                 (value-of-module-body m-body env)
                                 env)))))))
;; We will have let* scoping inside a module body.
;; We put all the values in the environment, not just the ones
;; that are in the interface.  But the typechecker will prevent
;; anybody from using the extras.

;; value-of-module-body : ModuleBody * Env -> TypedModule
(define value-of-module-body
  (lambda (m-body env)
    (cases module-body m-body
      (defns-module-body (defns)
        (simple-module
         (defns-to-env defns env))))))

(define raise-cant-apply-non-proc-module!
  (lambda (rator-val)
    (eopl:error 'value-of-module-body
                "can't apply non-proc-module-value ~s" rator-val)))


;; defns-to-env : Listof(Defn) * Env -> Env
(define defns-to-env
  (lambda (defns env)
    (if (null? defns)
        (empty-env)
        (cases definition (car defns)
          (val-defn (var exp)
                    (let ([val (value-of exp env)])
                      (let ([new-env (extend-env var val env)])
                        (defns-to-env
                          (cdr defns) new-env))))
          ;; type definitions are ignored at run time
          [else ;; 好吧,这里的这个type-defn直接被忽略了
           (defns-to-env (cdr defns) env)]
          ))))

;; value-of : Exp * Env -> ExpVal
(define value-of
  (lambda (exp env)
    (cases expression exp
      (const-exp (num) (num-val num))
      (var-exp (var) (apply-env env var))
      (qualified-var-exp (m-name var-name) ;; 模块的名字,变量的名字
                         (lookup-qualified-var-in-env m-name var-name env))
      (diff-exp (exp1 exp2)
                (let ((val1
                       (expval->num
                        (value-of exp1 env)))
                      (val2
                       (expval->num
                        (value-of exp2 env))))
                  (num-val
                   (- val1 val2))))
      (zero?-exp (exp1)
                 (let ((val1 (expval->num (value-of exp1 env))))
                   (if (zero? val1)
                       (bool-val #t)
                       (bool-val #f))))
      
      (if-exp (exp0 exp1 exp2)
              (if (expval->bool (value-of exp0 env))
                  (value-of exp1 env)
                  (value-of exp2 env)))
      
      (let-exp (vars exps body)
               (let ((new-env (extend-env* vars exps env)))
                 (value-of body new-env)))
      
      (proc-exp (bvars tys body)
                (proc-val
                 (procedure bvars body env)))
      
      (call-exp (rator rands) ;; 有多个参数
                (let ([proc (expval->proc (value-of rator env))])
                  (apply-procedure proc rands)))
      
      (letrec-exp (tys1 procs-name bvars tys2 procs-bodies letrec-body)
                  (value-of letrec-body
                            (extend-env-recursively procs-name bvars procs-bodies env)))
      )))
;; 这是一个辅助函数
(define extend-env*
  (lambda (vars exps new-env)
    (if (null? vars) new-env
        (extend-env* (cdr vars) (cdr exps)
                     (extend-env (car vars) (value-of (car exps) new-env) new-env)))))

;; apply-procedure : Proc * ExpVal -> ExpVal
(define apply-procedure
  (lambda (proc1 args)
    (cases proc proc1
           (procedure (vars body saved-env)
                      (value-of body (extend-env* vars args saved-env))))))

;; add-module-defns-to-tenv : Listof (ModuleDefn) * Tenv -> Tenv
(define add-module-defns-to-tenv
  (lambda (defns tenv)
    (if (null? defns)
        tenv
        (cases module-definition (car defns)
          (a-module-definition (m-name expected-iface m-body)
                               (let ([actual-iface (interface-of m-body tenv)])
                                 (if (<:-iface actual-iface expected-iface tenv)
                                     ;; ok, continue in extended tenv
                                     (let ([new-env (extend-tenv-with-module
                                                     m-name
                                                     (expand-iface m-name expected-iface tenv))])
                                       (add-module-defns-to-tenv (cdr defns) new-env))
                                     ;; no, raise error
                                     (report-module-doesnt-satisfy-iface m-name
                                                                         expected-iface actual-iface))))))))

;; interface-of : ModuleBody * Tenv -> Iface
(define interface-of
  (lambda (m-body tenv)
    (cases module-body m-body
      (defns-module-body (defns)
        (simple-iface
         (defns-to-decls defns tenv))))))
;; defns-to-decls : Listof(Defn) * Tenv -> Listof(Decl)
;; Convert defns to a set of declarations for just the names defined
;; in defns.  Do this in the context of tenv.  The tenv is extended
;; at every step, so we get the correct let* scoping
(define defns-to-decls
  (lambda (defns tenv)
    (if (null? defns)
        '()
        (cases definition (car defns)
          (val-defn (var-name exp)
                    (let ([ty (type-of exp tenv)])
                      (let ([new-tenv (extend-tenv var-name ty tenv)])
                        (cons
                         (val-decl var-name ty)
                         (defns-to-decls (cdr defns) new-tenv)))))
          (type-defn (name ty)
                     (let ([new-tenv (extend-tenv-with-type
                                      name
                                      (expand-type ty tenv)
                                      tenv)])
                       (cons
                        (transparent-type-decl name ty)
                        (defns-to-decls (cdr defns) new-tenv))))))))

(define raise-bad-module-application-error!
  (lambda (expected-type rand-type body)
    (eopl:pretty-print
     (list 'bad-module-application body
	   'actual-rand-interface: rand-type
	   'expected-rand-interface: expected-type))
    (eopl:error 'interface-of
		"Bad module application ~s" body)))

(define report-module-doesnt-satisfy-iface
  (lambda (m-name expected-type actual-type)
    (eopl:pretty-print
     (list 'error-in-defn-of-module: m-name
	   'expected-type: expected-type
	   'actual-type: actual-type))
    (eopl:error 'type-of-module-defn)))

;; check-equal-type! : Type * Type * Exp -> Unspecified
(define check-equal-type!
  (lambda (ty1 ty2 exp)
    (if (not (equal? ty1 ty2))
        (report-unequal-types ty1 ty2 exp)
        #f
        )))

;; report-unequal-types : Type * Type * Exp -> Unspecified
(define report-unequal-types
  (lambda (ty1 ty2 exp)
    (eopl:error 'check-equal-type!
		"Types didn't match: ~s != ~a in~%~a"
		(type-to-external-form ty1)
		(type-to-external-form ty2)
		exp)))


;;;;;;;;;;;;; The Type Checker ;;;;;;;;;;;;;;;;;;;;;;;
;; type-of : Exp * Tenv -> Type
(define type-of
  (lambda (exp tenv)
    (cases expression exp
      (const-exp (num) (int-type))
      (diff-exp (exp1 exp2)
                (let ((type1 (type-of exp1 tenv))
                      (type2 (type-of exp2 tenv)))
                  (check-equal-type! type1 (int-type) exp1)
                  (check-equal-type! type2 (int-type) exp2)
                  (int-type)))
      (zero?-exp (exp1)
                 (let ((type1 (type-of exp1 tenv)))
                   (check-equal-type! type1 (int-type) exp1)
                   (bool-type)))
      (if-exp (exp1 exp2 exp3)
              (let ((ty1 (type-of exp1 tenv))
                    (ty2 (type-of exp2 tenv))
                    (ty3 (type-of exp3 tenv)))
                (check-equal-type! ty1 (bool-type) exp1)
                (check-equal-type! ty2 ty3 exp)
                ty2))
      (var-exp (var) (apply-tenv tenv var))

      ;; lookup-qualified-var-in-tenv 
      (qualified-var-exp (m-name var-name)
                         (lookup-qualified-var-in-tenv m-name var-name tenv))

      (let-exp (vars exps body)
               (let ([types (map (lambda (exp) (type-of exp tenv)) exps)]) 
                 (let ([new-tenv (extend-tenv* vars types tenv)])
                   (type-of body new-tenv))))
                      
      
     ; (let-exp (var exp1 body)
	  ;	    (let ([rhs-type (type-of exp1 tenv)])
	  ;	      (type-of body (extend-tenv var rhs-type tenv))))
      
      (proc-exp (bvars bvars-type body)
                (let ([expanded-bvars-type
                       (map (lambda (bvars-type) (expand-type bvars-type tenv)) bvars-type)]) ;; 特别注意这里的这个expand-type
                  (let ([result-type
                         (type-of body
                                  (extend-tenv* bvars expanded-bvars-type tenv))])
                    (proc-type expanded-bvars-type result-type))))
      
      (call-exp (rator rands)
                (let ([rator-type (type-of rator tenv)]
                      [rands-type (map (lambda (rand) (type-of rand tenv)) rands)])
                  (cases type rator-type
                    (proc-type (args-type result-type)
                               (begin
                                 (check-equal-type-list! args-type rands-type rands)
                                 result-type))
                    (else
                     (eopl:error 'type-of
                                 "Rator not a proc type:~%~s~%had rator type ~s"
                                 rator (type-to-external-form rator-type))))))
      
       (letrec-exp (proc-result-types proc-names
					 bvars bvars-type
					 proc-bodies
					 letrec-body)
                   (letrec ([extend-tenv**
                             (lambda (proc-names bvars-type proc-result-types tenv)
                               (if (null? bvars-type) tenv
                                   (extend-tenv** (cdr proc-names) (cdr bvars-type) (cdr proc-result-types)
                                                 (extend-tenv (car proc-names)
                                                              (expand-type
                                                               (proc-type (car bvars-type) (car proc-result-types)) tenv)
                                                              tenv))))])
                     (let ([tenv-for-letrec-body
                            (extend-tenv** proc-names bvars-type proc-result-types tenv)])
                    ;; 说实话，我挺讨厌写这种代码的，纯体力活
                       (letrec ([check-letrec!
                                 (lambda (bvars bvar-types proc-result-types proc-bodies)
                                   (if (null? bvars) #t
                                       (let ([proc-result-type (expand-type (car proc-result-types) tenv)]
                                             [proc-body-type
                                              (type-of (car proc-bodies)
                                                       (extend-tenv* (car bvars)
                                                                     (map (lambda (bvar-type) (expand-type bvar-type tenv)) (car bvar-types))
                                                                     tenv-for-letrec-body))]) 
                                         (check-equal-type!  proc-body-type proc-result-type (car proc-bodies))
                                         (check-letrec! (cdr bvars) (cdr bvar-types) (cdr proc-result-types) (cdr proc-bodies)))))])
                       (let ([check-result
                              (check-letrec! bvars bvars-type proc-result-types proc-bodies)])
                              
                         (type-of letrec-body tenv-for-letrec-body))))))
                   )))
(define check-equal-type-list!
        (lambda (args rands-type rands)
          (if (null? args) #t
              (begin
                (check-equal-type! (car args) (car rands-type) (car rands))
                (check-equal-type-list! (cdr args) (cdr rands-type) (cdr rands))))))
(define extend-tenv*
        (lambda (vars types tenv)
          (if (null? vars) tenv
              (extend-tenv* (cdr vars) (cdr types)
                            (extend-tenv (car vars) (car types) tenv)))))


(define-datatype type-environment type-environment?
  (empty-tenv)
  (extend-tenv
   (bvar symbol?)
   (bval type?)
   (saved-tenv type-environment?))
  (extend-tenv-with-module
   (name symbol?)
   (interface interface?)
   (saved-env type-environment?))
  (extend-tenv-with-type
   (t-name symbol?)
   (t-type type?) ;; invariant : this must always be expanded 
   (saved-tenv type-environment?))
  )

;;;;;;;;;;;;;;;;;;;; procedures for looking things up tenvs ;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;; lookup or die

;; lookup-qualified-var-in-tenv : Sym * Sym * Tenv -> Type
(define lookup-qualified-var-in-tenv
  (lambda (m-name var-name tenv)
    (let ([iface (lookup-module-name-in-tenv tenv m-name)])
      (cases interface iface
        (simple-iface (decls)
                      (lookup-variable-name-in-decls var-name decls))))))

(define lookup-variable-name-in-tenv
  (lambda (tenv search-sym)
    (let ([maybe-answer
           (variable-name->maybe-binding-in-tenv tenv search-sym)])
      (if maybe-answer maybe-answer
          (raise-tenv-lookup-failure-error 'variable search-sym tenv)))))

(define lookup-module-name-in-tenv
  (lambda (tenv search-sym)
    (let ([maybe-answer
           (module-name->maybe-binding-in-tenv tenv search-sym)])
      (if maybe-answer maybe-answer
          (raise-tenv-lookup-failure-error 'module search-sym tenv)))))

(define lookup-type-name-in-tenv
  (lambda (tenv search-sym)
    (let ((maybe-answer
	   (type-name->maybe-binding-in-tenv tenv search-sym)))
      (if maybe-answer maybe-answer
          (raise-tenv-lookup-failure-error 'type search-sym tenv)))))


(define lookup-qualified-type-in-tenv
  (lambda (m-name t-name tenv)
    (let ([iface (lookup-module-name-in-tenv tenv m-name)])
      (cases interface iface
        (simple-iface (decls)
                      ;; this is not right, because it doesn't distinguish
                      ;; between type and variable declarations.  Exercise: fix
                      ;; this so that it raises an error if t-name is declared
                      ;; in a val-decl.
                      (lookup-variable-name-in-decls t-name decls))))))

(define apply-tenv lookup-variable-name-in-tenv)

(define raise-tenv-lookup-failure-error
  (lambda (kind var tenv)
    (eopl:pretty-print
     (list 'tenv-lookup-failure: (list 'missing: kind var) 'in:
	   tenv))
    (eopl:error 'lookup-variable-name-in-tenv)))

;; this is not right, because it doesn't distinguish
;; between type and variable declarations.  But it will do
;; for now.  Exercise: refine this do that it raises an error if
;; var-name is declared as something other than a val-decl.

;; 下面的过程其实非常简单,那就是在define中查找对应的变量名,找到了则返回
;; 对应的类型,否则报异常
(define lookup-variable-name-in-decls
  (lambda (var-name decls0)
    (let loop ((decls decls0))
      (cond
        [(null? decls) (raise-lookup-variable-in-decls-error! var-name decls0)]
        [(eqv? var-name (decl->name (car decls))) (decl->type (car decls))]
        [else (loop (cdr decls))]))))

(define raise-lookup-variable-in-decls-error!
  (lambda (var-name decls)
    (eopl:pretty-print
     (list 'lookup-variable-decls-failure:
	   (list 'missing-variable var-name)
	   'in:
	   decls))))

;;;;;;;;;;;;;;;;;; lookup or return #f

;; variable-name->maybe-binding-in-tenv : Tenv * Sym -> Maybe(Type)
(define variable-name->maybe-binding-in-tenv
  (lambda (tenv search-sym)
    (let recur ((tenv tenv))
      (cases type-environment tenv
        (empty-tenv () #f)
        (extend-tenv (name ty saved-tenv)
                     (if (eqv? name search-sym)
                         ty
                         (recur saved-tenv)))
        (else (recur (tenv->saved-tenv tenv)))))))

;; module-name->maybe-binding-in-tenv : Tenv * Sym -> Maybe (Iface)
(define module-name->maybe-binding-in-tenv
  (lambda (tenv search-sym)
    (let recur ((tenv tenv)) ;; 话说,用这种方式来写代码,还是挺方便的啊
      (cases type-environment tenv
        (empty-tenv () #f)
        (extend-tenv-with-module (name m-type saved-tenv)
                                 (if (eqv? name search-sym)
                                     m-type
                                     (recur saved-tenv)))
        (else (recur (tenv->saved-tenv tenv)))))))

;; type-name->maybe-binding-in-tenv : Tenv * Sym -> Maybe(Iface)
(define type-name->maybe-binding-in-tenv
  (lambda (tenv search-sym)
    (let recur ((tenv tenv))
      (cases type-environment tenv
        (empty-tenv () #f)
        (extend-tenv-with-type (name type saved-tenv)
                               (if (eqv? name search-sym)
                                   type
                                   (recur saved-tenv)))
        (else (recur (tenv->saved-tenv tenv)))))))

;; assume tenv is non-empty
(define tenv->saved-tenv
  (lambda (tenv)
    (cases type-environment tenv
      (empty-tenv ()
                  (eopl:error 'tenv->saved-tenv
                              "tenv->saved-tenv called on empty tenv"))
      (extend-tenv (name ty saved-tenv) saved-tenv)
      (extend-tenv-with-module (name m-type saved-tenv) saved-tenv)
      (extend-tenv-with-type (name ty saved-tenv) saved-tenv))))

(define run
  (lambda (string)
    (value-of-program (scan&parse string))))
(define ck
  (lambda (string)
    (type-of-program (scan&parse string))))
;; test code

(run "let a = 1 b = 2 in -(a, b)")
(ck "let f = proc (x:int, y:int) -(x, y) in (f 3 4)")
(ck "letrec int f (x:int, y:int) = -(x,y) in (f 3 4)")
(ck "letrec int f (x:int, y:int) = -(x,y) , int g (x:int) = x in (g 3)")

                              




                        




                                        
            
                    


                 





