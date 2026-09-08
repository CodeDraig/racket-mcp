#lang racket/base
(require rackunit mcp)
(define calls 0)
(define (callback . _) (set! calls (add1 calls)) "done")
(define done (workflow-stage 'done 'complete Any callback #f #f))
(define (with-stage stage) (make-workflow "flow" "1" "build" (list stage)))
(define invalid-builders
  (list (lambda () (make-workflow 42 "1" "build" (list done)))
        (lambda () (make-workflow "flow" #f "build" (list done)))
        (lambda () (make-workflow "flow" "1" #f (list done)))
        (lambda () (make-workflow "flow" "1" "build" (list done) #:key 42))
        (lambda () (make-workflow "flow" "1" "build" (list done) #:key (lambda () "wrong")))
        (lambda () (with-stage (struct-copy workflow-stage done [id 42])))
        (lambda () (with-stage (struct-copy workflow-stage done [id (string->uninterned-symbol "done")])))
        (lambda () (with-stage (struct-copy workflow-stage done [procedure 42])))
        (lambda () (with-stage (struct-copy workflow-stage done [procedure (lambda () "wrong")])))))
(for ([build (in-list invalid-builders)]) (check-exn exn:fail? build))
(for ([codec (in-list
       (list (value-codec #f "1" Any callback callback)
             (value-codec "codec" #f Any callback callback)
             (value-codec "codec" "1" (hasheq 'type "invalid") callback callback)
             (value-codec "codec" "1" Any 42 callback)
             (value-codec "codec" "1" Any callback (lambda () "wrong"))))])
  (check-exn exn:fail? (lambda () (make-codec-registry (list codec)))))
(define invalid (workflow-descriptor "raw" "1" "build"
  (list (struct-copy workflow-stage done [procedure #f])) #f callback))
(check-exn exn:fail? (lambda () (make-tool "raw" '() callback #:workflow invalid)))
(check-equal? calls 0)

(define store (open-memory-store))
(dynamic-wind void
  (lambda ()
    (check-exn exn:fail? (lambda () (run-workflow invalid store (hasheq) #:principal "test")))
    (check-equal? (list-instances store) '())
    (check-equal? calls 0))
  (lambda () (close-store! store)))

(define wrong-keyword (lambda (_ #:required x) x))
(check-exn #rx"procedure" (lambda () (with-stage (struct-copy workflow-stage done [procedure wrong-keyword]))))
(check-exn #rx"key" (lambda () (make-workflow "flow" "1" "build" (list done) #:key wrong-keyword)))
(check-exn #rx"nonempty" (lambda () (make-workflow "flow" "1" "build" '())) )
(check-exn #rx"completion" (lambda () (with-stage (workflow-stage 'save 'checkpoint Any callback #f #f))))
(check-exn #rx"destination" (lambda () (with-stage (workflow-stage 'select 'branch Integer callback '() #f))))
(check-exn #rx"completion" (lambda () (make-workflow "flow" "1" "build"
  (list (workflow-stage 'select 'branch Integer (lambda (_) 0) '(done save) #f)
        done (workflow-stage 'save 'checkpoint Any callback #f #f)))))
(check-exn #rx"completion" (lambda () (make-workflow "flow" "1" "build"
  (list (workflow-stage 'again 'jump Any callback 'again #f) done))))
;; A branch with real completion destinations is valid and construction does not
;; call its selector, the stage procedures, or its invocation-key procedure.
(check-not-exn (lambda () (make-workflow "flow" "1" "build"
  (list (workflow-stage 'select 'branch Integer callback '(done) #f) done) #:key callback)))
(check-equal? calls 0)

(define malformed-string (string-codec "codec" "1" String callback #f))
(check-exn exn:fail? (lambda () (make-prompt "bad" (list (prompt-argument 'x String #f #f malformed-string)) callback)))
(check-exn exn:fail? (lambda () (decode-string-value malformed-string "input")))
(check-exn exn:fail? (lambda () (encode-string-value malformed-string "input")))
(define malformed-value (value-codec "codec" "1" String callback #f))
(check-exn exn:fail? (lambda () (encode-value malformed-value "input")))
(check-exn exn:fail? (lambda () (codec-storage-schema malformed-value)))
(check-exn exn:fail? (lambda () (make-workflow "flow" "1" "build"
  (list (workflow-stage 'save 'checkpoint malformed-value callback #f #f) done))))
(check-equal? calls 0)

(check-exn #rx"policy" (lambda () (with-stage (struct-copy workflow-stage done [policy 'manual]))))
(check-exn #rx"adapter" (lambda () (with-stage (struct-copy workflow-stage done [adapter 'unused]))))
(define valid-codec (make-value-codec "valid" "1" String values values))
(define raw-string (string-codec "valid" "1" String values values))
(check-equal? (decode-value valid-codec (encode-value valid-codec "value")) "value")
(check-equal? (decode-string-value raw-string (encode-string-value raw-string "value")) "value")
(define valid-store (open-memory-store))
(dynamic-wind void
  (lambda ()
    (define valid (workflow-descriptor "raw-valid" "1" "build" (list done) callback (lambda (_args _result) '())))
    (check-equal? calls 0)
    (check-equal? (run-workflow valid valid-store (hasheq) #:principal "test") "done")
    (check-equal? calls 2) ; one key callback and one completion, after validation
    (check-equal? (length (list-instances valid-store)) 1))
  (lambda () (close-store! valid-store)))
