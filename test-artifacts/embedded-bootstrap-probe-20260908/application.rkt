#lang mcp
(require mcp/private/module-observation mcp/private/module-imports
         mcp/private/declared-code-capture mcp/private/executable-capture)
(server #:name "command-observation" #:version "1")
(define-namespace-anchor home)
(define owner (variable-reference->resolved-module-path (#%variable-reference)))
(tool (observed-build)
  #:description "Report observation coverage for this running module graph."
  (define visited (make-hasheq))
  (define missing '())
  (define ordinary 0)
  (define predefined 0)
  (define (visit identity)
    (unless (hash-ref visited identity #f)
      (hash-set! visited identity #t)
      (cond [(module-predefined? identity) (set! predefined (add1 predefined))]
            [else
             (set! ordinary (add1 ordinary))
             (unless (observed-module-code identity)
               (set! missing (cons (format "~a" (resolved-module-path-name identity)) missing)))])
      (when (module-declared? identity #f)
        (for-each visit (resolved-module-imports identity)))))
  (parameterize ([current-namespace (namespace-anchor->namespace home)]) (visit owner))
  (text-result (format "~s" (list ordinary predefined missing))))

(tool (capture-baseline)
  #:description "Report dependencies without executable identities in the frozen graph."
  (define capture
    (capture-declared-module-code owner #:namespace (namespace-anchor->namespace home)))
  (define missing (module-code-capture-unobserved capture))
  (define predefined (module-code-capture-predefined capture))
  (text-result
    (format "~s" (list missing predefined
                       (filter (lambda (name) (not (member name predefined))) missing)))))

(module configure-runtime '#%kernel
  (#%require '#%paramz)
  ;; Keep this module in the kernel language: importing racket/base here would
  ;; load the runtime libraries before observation could begin.
  (define-values (entries)
    (lambda (table)
      (letrec-values ([(loop)
                       (lambda (i out)
                         (if i
                             (loop (hash-iterate-next table i)
                               (cons (cons (hash-iterate-key table i)
                                           (hash-iterate-value table i)) out))
                             out))])
        (loop (hash-iterate-first table) '()))))
  (define-values (code-identity)
    (lambda (identity code)
      (let-values ([(name) (module-compiled-name code)]
                   [(owner) (resolved-module-path-name identity)])
        (if (pair? name)
            (make-resolved-module-path
              (cons (if (pair? owner) (car owner) owner) (cdr name)))
            identity))))
  (define-values (make-observer)
    (lambda ()
      (let-values ([(registries) (make-hasheq)]
                   [(lock) (make-semaphore 1)]
                   [(active?) #t]
                   [(closed?) #f]
                   [(receiver) #f]
                   [(original-eval) (current-eval)])
        (letrec-values
          ([(observe)
            (lambda (expression)
              (if (if active? #t receiver)
                  (let-values ([(code) (if (compiled-expression? expression)
                                          expression (compile expression))]
                               [(identity) (current-module-declare-name)]
                               [(namespace) (current-namespace)])
                    (begin0 (original-eval code)
                      (if (if identity (compiled-module-expression? code) #f)
                          (call-with-semaphore lock
                            (lambda ()
                              (if active?
                                  (let-values ([(registry) (namespace-module-registry namespace)])
                                    (let-values ([(record) (hash-ref registries registry #f)])
                                      (let-values ([(record) (if record record
                                                                (cons namespace (make-hasheq)))])
                                        (hash-set! registries registry record)
                                        (hash-set! (cdr record) (code-identity identity code) code))))
                                  (if receiver (receiver identity code namespace) (void)))))
                          (void))))
                  (original-eval expression)))]
           [(transfer!)
            (case-lambda
              [() (transfer! #f)]
              [(next-receiver)
              (call-with-semaphore lock
                (lambda ()
                  (if active?
                      (let-values ([(snapshot)
                                     (map (lambda (entry)
                                            (let-values ([(record) (cdr entry)])
                                              (cons (car record) (entries (cdr record)))))
                                          (entries registries))])
                        (set! receiver next-receiver)
                        (set! active? #f)
                        (hash-clear! registries)
                        snapshot)
                      (raise (exn:fail (if closed? "kernel observation scope is closed"
                                           "kernel observation has already been transferred")
                                       (current-continuation-marks))))))])])
          (values observe transfer!
            (lambda ()
              (call-with-semaphore lock
                (lambda ()
                  (set! closed? #t) (set! active? #f) (set! receiver #f)
                  (hash-clear! registries))))
            (lambda ()
              (if closed?
                  (raise (exn:fail "kernel observation scope is closed"
                                  (current-continuation-marks)))
                  (void)))
            original-eval)))))
  (define-values (call-with-kernel-observation)
    (lambda (proc)
      (let-values ([(observe transfer! close! check-open original) (make-observer)])
        (with-continuation-mark parameterization-key
          (extend-parameterization (continuation-mark-set-first #f parameterization-key)
            current-eval observe current-compile (current-compile))
          (dynamic-wind check-open (lambda () (proc transfer!)) close!)))))
  ;; Installed observation outlives reader loading. After transfer, retained
  ;; resolver callbacks continue forwarding to the ordinary installed observer.
  (define-values (install-kernel-observation!)
    (lambda ()
      (let-values ([(observe transfer! close! check-open original) (make-observer)])
        (current-eval observe)
        transfer!)))
  (define-values (parent)
    (module-path-index-resolve
      (module-path-index-join '(submod "..")
        (variable-reference->module-path-index (#%variable-reference)))))
  (#%app call-with-kernel-observation
    (lambda (transfer!)
      (let-values ([(scoped) (dynamic-require 'mcp/private/module-observation 'call-with-module-observation)]
                   [(keyword-call) (dynamic-require 'racket/base 'keyword-apply)]
                   [(snapshot) (dynamic-require 'mcp/private/module-observation 'module-observation-snapshot)]
                   [(pairs) (dynamic-require 'racket/base 'hash->list)])
        (keyword-call scoped '(#:handoff #:seed)
          (list transfer! (list (cons (current-namespace) (pairs (snapshot)))))
          (list (lambda () (dynamic-require parent #f))))))))
