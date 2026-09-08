#lang racket/base
(require rackunit "../../mcp/private/input-response.rkt")
;; These are valid elicitation schemas with independently invalid format values.
(for ([sample '(("date" "2026-02-30") ("date-time" "not-a-timestamp")
                ("email" "not-an-email") ("uri" "not a URI"))])
  (define request
    (hasheq 'mode "form" 'message "Enter a value"
            'requestedSchema
            (hasheq 'type "object" 'properties
                    (hasheq 'value (hasheq 'type "string" 'format (car sample))))))
  (define response (hasheq 'action "accept" 'content (hasheq 'value (cadr sample))))
  (check-exn exn:fail? (lambda () (validate-input-response request response))
             (format "Reject invalid ~a value ~s" (car sample) (cadr sample))))
