#lang racket/base
(require racket/port racket/string racket/list racket/tcp openssl)
(provide bounded-http-sendrecv)
;; HTTP/1.1 framing per RFC 9112. No allocation uses a peer-supplied length.
(define (line! in budget)
  (define out (open-output-bytes))
  (let loop ()
    (when (zero? (unbox budget)) (error 'http-wire "HTTP framing byte limit exceeded"))
    (define b (read-byte in))
    (when (eof-object? b) (error 'http-wire "Truncated HTTP framing"))
    (set-box! budget (sub1 (unbox budget)))
    (cond [(= b 13)
           (when (zero? (unbox budget)) (error 'http-wire "HTTP framing byte limit exceeded"))
           (set-box! budget (sub1 (unbox budget)))
           (unless (eqv? (read-byte in) 10) (error 'http-wire "Expected HTTP CRLF"))
           (get-output-bytes out)]
          [(= b 10) (error 'http-wire "Expected HTTP CRLF")]
          [else (write-byte b out) (loop)])))
(define field-pattern #px#"^([!#$%&'*+.^_`|~0-9A-Za-z-]+):[\t ]*([^\x00-\x08\x0A-\x1F\x7F]*)$")
(define (headers! in budget)
  (let loop ([headers '()])
    (define line (line! in budget))
    (cond [(bytes=? line #"") (reverse headers)]
          [(regexp-match? field-pattern line) (loop (cons line headers))]
          [else (error 'http-wire "Invalid HTTP header field")])) )
(define (field-values headers name)
  (for/list ([line (in-list headers)]
             #:do [(define match (regexp-match field-pattern line))]
             #:when (string-ci=? (bytes->string/latin-1 (cadr match)) name))
    (string-trim (bytes->string/latin-1 (caddr match)))))
(define (bounded-http-sendrecv host target #:ssl? [tls? #f] #:port [port (if tls? 443 80)]
                               #:method [method "POST"] #:headers [headers '()] #:data [data ""]
                               #:max-header-bytes [limit 65536])
  (unless (exact-positive-integer? limit) (raise-argument-error 'bounded-http-sendrecv "exact-positive-integer?" limit))
  (unless (and (string? host) (not (regexp-match? #px"[\r\n\x00]" host))
               (regexp-match? #px"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$" method)
               (regexp-match? #px"^/[^\x00-\x20\x7F]*$" target))
    (error 'http-wire "Invalid HTTP request target or authority"))
  (for ([h (in-list headers)])
    (unless (and (string? h) (regexp-match? field-pattern (string->bytes/utf-8 h)))
      (error 'http-wire "Invalid outgoing HTTP header"))
    (when (regexp-match? #px"(?i:^(?:host|content-length|transfer-encoding|connection|accept-encoding):)" h)
      (error 'http-wire "Caller cannot replace HTTP framing headers")))
  (define payload (if (bytes? data) data (string->bytes/utf-8 data)))
  (define-values (in out) (if tls? (ssl-connect host port 'secure) (tcp-connect host port)))
  (define (close!)
    ;; Both halves must be attempted even when the peer already reset TLS/TCP.
    (with-handlers ([exn:fail? void]) (close-input-port in))
    (with-handlers ([exn:fail? void]) (close-output-port out)))
  (with-handlers ([(lambda (_) #t) (lambda (e) (close!) (raise e))])
    (fprintf out "~a ~a HTTP/1.1\r\nHost: ~a:~a\r\nConnection: close\r\nAccept-Encoding: identity\r\nContent-Length: ~a\r\n"
             method target (if (string-contains? host ":") (format "[~a]" host) host) port (bytes-length payload))
    (for ([h (in-list headers)]) (fprintf out "~a\r\n" h))
    (display "\r\n" out) (write-bytes payload out) (flush-output out)
    (define budget (box limit))
    (define-values (status code response-headers)
      (let loop ()
        (define status (line! in budget))
        (define match (regexp-match #px#"^HTTP/1[.][01] ([0-9]{3}) [^\x00-\x1F\x7F]*$" status))
        (unless match (error 'http-wire "Invalid HTTP status line"))
        (define code (string->number (bytes->string/latin-1 (cadr match))))
        (unless (<= 100 code 599) (error 'http-wire "Invalid HTTP status code"))
        (define fields (headers! in budget))
        (cond [(= code 101) (error 'http-wire "HTTP upgrade is unsupported")]
              [(< code 200) (loop)]
              [else (values status code fields)])))
    (define encodings (field-values response-headers "Content-Encoding"))
    (unless (andmap (lambda (v) (string-ci=? v "identity")) encodings)
      (error 'http-wire "Unrequested HTTP content encoding"))
    (define lengths (append-map (lambda (v) (map string-trim (string-split v "," #:trim? #f))) (field-values response-headers "Content-Length")))
    (define transfers (field-values response-headers "Transfer-Encoding"))
    (when (and (pair? lengths) (pair? transfers)) (error 'http-wire "Ambiguous HTTP response framing"))
    (unless (or (null? lengths) (and (andmap (lambda (v) (regexp-match? #px"^[0-9]+$" v)) lengths)
                                   (andmap (lambda (v) (= (string->number v) (string->number (car lengths)))) lengths)))
      (error 'http-wire "Invalid or conflicting Content-Length"))
    (unless (or (null? transfers) (and (= (length transfers) 1) (string-ci=? (car transfers) "chunked")))
      (error 'http-wire "Unsupported HTTP transfer coding"))
    (define-values (body-in body-out) (make-pipe 65536))
    (define failure (box #f))
    (define copier
      (thread
       (lambda ()
         (with-handlers ([(lambda (_) #t) (lambda (e) (set-box! failure e))])
           (define buffer (make-bytes 8192))
           (define (copy! count)
             (let loop ([remaining count])
               (unless (equal? remaining 0)
                 (define n (read-bytes-avail! buffer in 0 (if remaining (min remaining 8192) 8192)))
                 (cond [(eof-object? n) (when remaining (error 'http-wire "Truncated HTTP body"))]
                       [else (write-bytes buffer body-out 0 n) (loop (and remaining (- remaining n)))]))))
           (cond [(or (equal? method "HEAD") (memv code '(204 304))) (void)]
                 [(pair? transfers)
                  (let loop ()
                    (define line (line! in (box 8192)))
                    (define match (regexp-match #px#"^([0-9A-Fa-f]+)(?:;[^\x00-\x1F\x7F]*)?$" line))
                    (unless match (error 'http-wire "Invalid HTTP chunk size"))
                    (define size (string->number (bytes->string/latin-1 (cadr match)) 16))
                    (cond [(zero? size) (headers! in (box limit)) (void)]
                          [else (copy! size)
                                (unless (bytes=? (line! in (box 2)) #"") (error 'http-wire "Invalid HTTP chunk terminator"))
                                (loop)]))]
                 [(pair? lengths) (copy! (string->number (car lengths)))]
                 [else (copy! #f)]))
         (close!) (close-output-port body-out))))
    (define body
      (make-input-port 'bounded-http-body
        (lambda (bytes)
          (define n (read-bytes-avail!* bytes body-in))
          (cond [(eqv? n 0) (wrap-evt body-in (lambda (_) 0))]
                [(and (eof-object? n) (unbox failure)) (raise (unbox failure))]
                [else n])) #f
        (lambda () (close-input-port body-in) (close!) (kill-thread copier))))
    (values status response-headers body)))
