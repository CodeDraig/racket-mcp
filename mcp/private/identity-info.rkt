(module identity-info '#%kernel
  (#%provide get-info)
  ;; Racket queries this provider before running configure-runtime. Loading an
  ;; ordinary Racket library here would defeat a kernel-only startup boundary.
  (define-values (fail)
    (lambda (message) (raise (exn:fail message (current-continuation-marks)))))
  (define-values (get-info)
    (lambda (data)
      (if (if (vector? data)
              (if (= (vector-length data) 3)
                  (if (eq? (vector-ref data 0) 'mcp-compiled/1)
                      (box? (vector-ref data 2)) #f) #f) #f)
          (let-values ([(id) (unbox (vector-ref data 2))]
                       [(original) (vector-ref data 1)]
                       [(delegate) #f])
            (if (if (string? id) (regexp-match? #px"^mcp-compiled/1:[0-9a-f]{64}$" id) #f)
                (let-values ([(id) (string->immutable-string id)])
                  (lambda (key default)
                    (if (eq? key 'mcp-executable-identity) id
                        (if original
                            (begin
                              (if delegate (void)
                                  (set! delegate
                                    ((dynamic-require (vector-ref original 0) (vector-ref original 1))
                                     (vector-ref original 2))))
                              (delegate key default))
                            default))))
                (fail "compiled-identity: producer identity is incomplete or malformed")))
          (fail "compiled-identity: malformed producer metadata")))))
