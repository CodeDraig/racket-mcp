#lang mcp
(require net/base64 mcp/subscription)
(server #:name "racket-mcp-conformance" #:version "0.1.0")
(define png "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")
(define wav "UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YQIAAAAAAA==")
(define (contents . items) (hasheq 'resultType "complete" 'content items))
(resource (static-text) #:uri "test://static-text" #:description "Static test text"
  "This is the content of the static text resource.")
(resource (static-binary) #:uri "test://static-binary" #:description "Static test image" #:mime-type "image/png"
  (base64-decode (string->bytes/utf-8 png)))
(resource (template [id String]) #:uri "test://template/{id}/data" #:description "Parameterized test resource" #:mime-type "application/json"
  (json->string (hasheq 'id id 'templateTest #t 'data (string-append "Data for ID: " id))))
(resource (embedded) #:uri "test://embedded-resource" #:description "Embedded text"
  "This is an embedded resource content.")
(tool (test_simple_text) #:description "Return simple text."
  (text-result "This is a simple text response for testing."))
(tool (test_header [region (hash-set String 'x-mcp-header "Region")]) #:description "Mirror a region parameter into its declared header."
  (text-result region))
(tool (test_image_content) #:description "Return a test PNG." (contents (image-content png "image/png")))
(tool (test_audio_content) #:description "Return a test WAV." (contents (audio-content wav "audio/wav")))
(tool (test_embedded_resource) #:description "Embed a resource." (contents (embed (embedded))))
(tool (test_multiple_content_types) #:description "Return several content types."
  (contents (text-content "Multiple content types test:") (image-content png "image/png") (embed (embedded))))
(tool (test_error_handling) #:description "Return an execution error." (error-result "This is an intentional error for testing."))
(tool (test_tool_with_progress) #:description "Report progress on the request stream."
  (when (current-progress-token)
    (for ([i '(0 50 100)]) (progress! (current-progress-token) i #:total 100)))
  (text-result "Progress complete."))
(tool (test_logging_tool) #:description "Write diagnostics outside the protocol stream."
  (displayln "Diagnostic log fixture") (text-result "Done."))
;; This fixture tests capability rejection only. It neither advertises nor
;; implements deprecated sampling.
(tool (test_missing_capability) #:description "Exercise a missing-capability error."
  (mcp-error -32021 "Sampling is unavailable for this diagnostic" (hasheq 'requiredCapabilities (hasheq 'sampling (hasheq)))))
(workflow (test_streaming_elicitation) #:version "1" #:description "Request form input through MRTR."
  (await-input [answer Any] (hasheq 'mode "form" 'message "Continue?" 'requestedSchema (object-schema (hasheq 'answer String))))
  (text-result "Input received."))
(workflow (test_input_required_result_elicitation) #:version "1" #:description "Ask for a name through MRTR."
  (await-input [user_name Any] (hasheq 'mode "form" 'message "What is your name?" 'requestedSchema (object-schema (hasheq 'name String))))
  (text-result (format "Hello, ~a!" (hash-ref (hash-ref user_name 'content (hasheq)) 'name "visitor"))))
(workflow (test_input_required_result_request_state) #:version "1" #:description "Validate an opaque continuation."
  (checkpoint [prepared Integer] 42)
  (await-input [confirm Any] (hasheq 'mode "form" 'message "Please confirm" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (text-result "state-ok"))
(workflow (test_input_required_result_tampered_state) #:version "1" #:description "Reject unknown opaque continuations."
  (await-input [confirm Any] (hasheq 'mode "form" 'message "Please confirm" 'requestedSchema (object-schema (hasheq 'ok Boolean))))
  (text-result "state-ok"))
(define preservation-schema
  (hasheq '$schema "https://json-schema.org/draft/2020-12/schema" 'type "object"
          '$defs (hasheq 'address (hasheq '$anchor "addressDef" 'type "object"
                                        'properties (hasheq 'street String 'city String)))
          'properties (hasheq 'name String 'address (hasheq '$ref "#/$defs/address")
                              'contactMethod (hasheq 'type "string" 'enum '("phone" "email"))
                              'phone String 'email String)
          'allOf (list (hasheq 'anyOf (list (hasheq 'required '("phone")) (hasheq 'required '("email")))))
          'if (hasheq 'properties (hasheq 'contactMethod (hasheq 'const "phone")) 'required '("contactMethod"))
          'then (hasheq 'required '("phone")) 'else (hasheq 'required '("email"))
          'additionalProperties #f))
(mount (make-interface #:tools
                       (list (make-tool "json_schema_2020_12_tool" '() (lambda (arguments) (text-result "Valid."))
                                        #:description "Preserve the JSON Schema 2020-12 vocabulary."
                                        #:input-schema preservation-schema #:raw? #t))))
(prompt (test_simple_prompt) #:description "A simple prompt."
  (role "user" (text-content "This is a simple prompt for testing.")))
(prompt (test_prompt_with_arguments [arg1 String] [arg2 String]) #:description "A prompt with arguments."
  (role "user" (text-content (format "Prompt with arguments: arg1='~a', arg2='~a'" arg1 arg2))))
(completion (test_prompt_with_arguments arg1)
  (lambda (prefix context) (filter (lambda (s) (regexp-match? (regexp (string-append "^" (regexp-quote prefix))) s)) '("test" "testing" "paris" "park"))))
(prompt (test_prompt_with_embedded_resource [resourceUri String]) #:description "A prompt with an embedded resource."
  (role "user" (hasheq 'type "resource" 'resource (hasheq 'uri resourceUri 'mimeType "text/plain" 'text "Embedded resource content for testing."))))
(prompt (test_prompt_with_image) #:description "A prompt with an image."
  (role "user" (image-content png "image/png") (text-content "Describe this image.")))
