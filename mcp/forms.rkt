#lang racket/base
(require racket/match "descriptor.rkt" "schema.rkt" "json.rkt" "workflow.rkt" "completion.rkt" "authorization.rkt" "codec.rkt" "private/domain-bindings.rkt" "private/extensions.rkt" "private/handler.rkt" "private/registration.rkt"
         (for-syntax racket/base racket/list racket/syntax syntax/parse "private/workflow-ir.rkt" "private/resource-binding.rkt" "private/prompt-binding.rkt" "uri-template.rkt" (only-in "schema.rkt" check-schema!)))
(provide server tool resource prompt schema shape workflow checkpoint await-input perform completion scenario define-mcp-extension)
(begin-for-syntax
  (define (check-literal-uri! uri ids)
    (define text (syntax-parse uri #:literals (quote)
                   [text:str (syntax-e #'text)] [(quote text:str) (syntax-e #'text)] [_ #f]))
    (when text
      (with-handlers ([exn:fail? (lambda (e) (raise-syntax-error 'resource (exn-message e) uri))])
        (for ([variable (in-list (uri-template-variables text))])
          (unless (memq variable (map syntax-e ids))
            (error 'resource "URI template references an undeclared argument: ~a" variable))))))
  ;; Inspect only reader literals and the lexically bound Racket quote form.
  ;; Computed schemas retain ordinary expression evaluation at instantiation.
  (define (check-literal-schema! value)
    (define datum (syntax-e value))
    (define literal
      (syntax-parse value #:literals (quote)
        [(quote datum) (cons #t (syntax->datum #'datum))]
        [_ (and (or (boolean? datum) (hash? datum) (string? datum) (number? datum)
                    (bytes? datum) (char? datum) (vector? datum))
                (cons #t (syntax->datum value)))]))
    (when literal
      (with-handlers ([exn:fail? (lambda (e) (raise-syntax-error 'schema (exn-message e) value))])
        (check-schema! (cdr literal)))))
  (define-syntax-class arg
    #:attributes (id spec optional default)
    (pattern [id:id spec:expr] #:attr optional #'#f #:attr default #f)
    (pattern [id:id spec:expr #:optional] #:attr optional #'#t #:attr default #f)
    (pattern [id:id spec:expr #:default default:expr] #:attr optional #'#t))
  (define-syntax-class prompt-arg
    #:attributes (id spec optional default codec)
    (pattern a:arg #:attr id #'a.id #:attr spec #'a.spec #:attr optional #'a.optional #:attr default (attribute a.default) #:attr codec #f)
    (pattern [id:id spec:expr #:codec codec:expr] #:attr optional #'#f #:attr default #f)
    (pattern [id:id spec:expr #:codec codec:expr #:optional] #:attr optional #'#t #:attr default #f)
    (pattern [id:id spec:expr #:codec codec:expr #:default default:expr] #:attr optional #'#t))
  (define (argument-code ids specs opts defaults [codecs (make-list (length ids) #f)])
    (for/list ([id ids] [spec specs] [opt opts] [default defaults] [codec codecs] [i (in-naturals)])
      (check-literal-schema! spec)
      #`(#,(if codec #'prompt-argument #'argument) '#,id (checked-schema-expression #,spec) #,opt
                  #,(if default
                        #`(lambda (previous)
                            (let (#,@(for/list ([earlier (in-list (take ids i))]) #`[#,earlier (hash-ref previous '#,earlier)])) #,default)) #'#f) #,@(if codec (list codec) '()))))
  (define (check-binders ids stx)
    (define duplicate (check-duplicate-identifier ids))
    (when duplicate (raise-syntax-error #f "duplicate argument binder" stx duplicate)))
)
(define-syntax (server stx)
  (syntax-parse stx
    [(_ #:name name:expr #:version version:expr (~optional (~seq #:instructions instructions:expr) #:defaults ([instructions #'""])))
     #`(begin
         (register-declaration #f #:declaration server name #,stx)
         (let ([descriptor (server-descriptor name version instructions)])
           (register-declaration descriptor) descriptor))]))
(define-syntax (schema stx)
  (syntax-parse stx
    [(_ name:id value:expr)
     (check-literal-schema! #'value)
     #`(begin (define-schema-value name (check-schema! (checked-schema-expression value)))
              (register-declaration #f #:declaration schema name #,stx))]))
(define-syntax (tool stx)
  (syntax-parse stx
    [(_ (name:id a:arg ...) (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        (~optional (~seq #:output output:expr) #:defaults ([output #'#f]))
        (~optional (~seq #:annotations annotations:expr) #:defaults ([annotations #'(hasheq)]))
        (~optional (~seq #:changes [outcome:id changes:expr]) #:defaults ([outcome #'committed] [changes #''()]))
        body:expr ...+)
     (define ids (syntax->list #'(a.id ...)))
     (check-binders (append ids (list #'outcome)) stx)
     (check-literal-schema! #'output)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default)))
     #`(begin (define-operation-value name
         (make-tool (symbol->string 'name) (list #,@args)
                    (mcp-bound-handler (a.id ...) body ...)
                    #:description description #:output (checked-schema-expression output) #:annotations annotations
                    #:changes (lambda (bound outcome)
                                (let (#,@(for/list ([id ids]) #`[#,id (hash-ref bound '#,id)])) changes)))) (register-declaration name #:declaration tool name #,stx))]))
(define-syntax (resource stx)
  (syntax-parse stx
    [(_ (name:id a:arg ...) #:uri uri:expr
        (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        (~optional (~seq #:mime-type mime:expr) #:defaults ([mime #'#f]))
        (~optional (~seq #:render renderer:expr) #:defaults ([renderer #'#f]))
        (~optional (~seq #:matcher matcher:expr) #:defaults ([matcher #'#f]))
        (~optional (~seq #:depends-on dependencies:expr) #:defaults ([dependencies #''()]))
        (~optional (~seq #:ttl-ms ttl:expr) #:defaults ([ttl #'0]))
        #:workflow version:str body ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (check-literal-uri! #'uri ids)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default)))
     (define hidden (car (generate-temporaries #'(name))))
     (define-values (program summaries)
       (compile-workflow #'(workflow-program (name a ...) #:version version body ...) #t #:summaries? #t))
     #`(begin
         (define-resource-value #,hidden (make-resource (symbol->string 'name) uri #f #:description description #:mime-type mime #:render renderer
                                        #:arguments (list #,@args) #:matcher matcher #:ttl-ms ttl
                                        #:depends-on (lambda (bound) (let (#,@(for/list ([id ids]) #`[#,id (hash-ref bound '#,id)])) dependencies))
                                        #:workflow #,program))
         (define-syntax name (resource-binding (quote-syntax #,hidden) #,(length ids) 'name '(a.id ...)))
         (register-declaration name #:declaration resource name #,stx #:workflow-nodes (#,@summaries)))]
    [(_ (name:id a:arg ...) #:uri uri:expr
        (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        (~optional (~seq #:mime-type mime:expr) #:defaults ([mime #'#f]))
        (~optional (~seq #:render renderer:expr) #:defaults ([renderer #'#f]))
        (~optional (~seq #:matcher matcher:expr) #:defaults ([matcher #'#f]))
        (~optional (~seq #:depends-on dependencies:expr) #:defaults ([dependencies #''()]))
        (~optional (~seq #:ttl-ms ttl:expr) #:defaults ([ttl #'0])) body:expr ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (check-literal-uri! #'uri ids)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default)))
     (define hidden (car (generate-temporaries #'(name))))
     #`(begin (define-resource-value #,hidden (make-resource (symbol->string 'name) uri (mcp-handler (a.id ...) body ...) #:description description #:mime-type mime #:render renderer #:arguments (list #,@args) #:matcher matcher #:ttl-ms ttl
                                        #:depends-on (lambda (bound) (let (#,@(for/list ([id ids]) #`[#,id (hash-ref bound '#,id)])) dependencies))))
              (define-syntax name (resource-binding (quote-syntax #,hidden) #,(length ids) 'name '(a.id ...)))
              (register-declaration name #:declaration resource name #,stx))]))

(define-syntax (shape stx)
  (syntax-parse stx
    [(_ name:id [field:id spec:expr] ...)
     (check-binders (syntax->list #'(field ...)) stx)
     (for-each check-literal-schema! (syntax->list #'(spec ...)))
     (define internal (car (generate-temporaries #'(name))))
     (with-syntax ([record internal] [constructor (format-id #'name "make-~a" #'name)]
                   [encoder (format-id #'name "~a->json" #'name)] [decoder (format-id #'name "json->~a" #'name)] [codec (format-id #'name "~a-codec" #'name)]
                   [(accessor ...) (for/list ([f (in-list (syntax->list #'(field ...)))]) (format-id #'name "~a-~a" #'name f))]
                   [(internal-accessor ...) (for/list ([f (in-list (syntax->list #'(field ...)))]) (format-id internal "~a-~a" internal f))])
       #`(begin (struct record (field ...) #:transparent)
                (define-schema-value name (object-schema (make-immutable-hasheq (list (cons 'field (checked-schema-expression spec)) ...))))
                (define (constructor field ...)
                  (define v (record field ...)) (encoder v) v)
                (define accessor internal-accessor) ...
                (define (encoder v)
                  (define data (make-immutable-hasheq (list (cons 'field (internal-accessor v)) ...)))
                  (unless (valid? name data) (error 'encoder "shape failed its schema")) data)
                (define (decoder data)
                  (unless (valid? name data) (error 'decoder "shape failed its schema"))
                  (record (hash-ref data 'field) ...))
                (define codec (make-value-codec (symbol->string 'name) "1" name encoder decoder))
                (register-declaration #f #:declaration shape name #,stx)))]))
(define-syntax (prompt stx)
  (syntax-parse stx
    [(_ (name:id a:prompt-arg ...) (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        #:workflow version:str body ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default) (attribute a.codec)))
     (define-values (program summaries)
       (compile-workflow #'(workflow-program (name [a.id a.spec] ...) #:version version body ...) #t #:summaries? #t))
     (define hidden (car (generate-temporaries #'(name))))
     #`(begin
         (define-operation-value #,hidden (make-prompt (symbol->string 'name) (list #,@args) #f #:description description
                                   #:workflow #,program))
         (define-syntax name (prompt-binding (quote-syntax #,hidden) 'name '(a.id ...)))
         (register-declaration name #:declaration prompt name #,stx #:workflow-nodes (#,@summaries)))]
    [(_ (name:id a:prompt-arg ...) (~optional (~seq #:description description:expr) #:defaults ([description #'""])) body:expr ...+)
     (define ids (syntax->list #'(a.id ...))) (check-binders ids stx)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default) (attribute a.codec)))
     (define hidden (car (generate-temporaries #'(name))))
     #`(begin (define-operation-value #,hidden (make-prompt (symbol->string 'name) (list #,@args)
                                (mcp-bound-handler (a.id ...) body ...)
                                #:description description)) (define-syntax name (prompt-binding (quote-syntax #,hidden) 'name '(a.id ...)))
         (register-declaration name #:declaration prompt name #,stx))]))

(define-syntax (checkpoint stx) (raise-syntax-error #f "only valid as a workflow stage" stx))
(define-syntax (completion stx)
  (syntax-parse stx
    [(_ (target:id argument:id) handler:expr)
     (define binding (or (lookup-resource-binding #'target) (lookup-prompt-binding #'target)))
     (when (and binding
                (not (memq (syntax-e #'argument)
                           (if (resource-binding? binding) (resource-binding-arguments binding) (prompt-binding-arguments binding)))))
       (raise-syntax-error 'completion "unknown target argument" stx #'argument))
     #`(begin
         (register-declaration #f #:declaration completion target #,stx)
         (let ([descriptor (completion-descriptor target 'argument handler)])
           (register-declaration descriptor)
           descriptor))]))
(define-syntax (scenario stx)
  (syntax-parse stx [(_ name:id body ...+) #'(module+ test (require rackunit) (test-case (symbol->string 'name) body ...))]))
(define-syntax (define-mcp-extension stx)
  (syntax-parse stx
    [(_ name:id #:workflow transformer:expr)
     #'(define-syntax name (workflow-extension transformer))]
    [(_ name:id #:declaration transformer:expr)
     (define hidden (car (generate-temporaries #'(name))))
     (with-syntax ([internal hidden])
       #'(begin
           (define-syntax internal (declaration-extension transformer))
           (define-syntax (name use)
             (syntax-case use ()
               [(_ . tail) (expand-declaration-extension #'(internal . tail))]))))]
    [(_ name:id transformer:expr)
     #'(define-mcp-extension name #:declaration transformer)]))
(define-syntax (await-input stx) (raise-syntax-error #f "only valid as a workflow stage" stx))
(define-syntax (perform stx) (raise-syntax-error #f "only valid as a workflow stage" stx))
(define-syntax (workflow stx) (compile-workflow stx #f))
(define-syntax (workflow-program stx) (compile-workflow stx #t))
(define-for-syntax (compile-workflow stx program-only? #:summaries? [summaries? #f])
  (syntax-parse stx
    [(_ (name:id a:arg ...) #:version version:str
        (~optional (~seq #:execution execution:id) #:defaults ([execution #'mrtr]))
        (~optional (~seq #:description description:expr) #:defaults ([description #'""]))
        (~optional (~seq #:key key:expr) #:defaults ([key #'#f]))
        (~optional (~seq #:changes [outcome:id changes:expr]) #:defaults ([outcome #'committed] [changes #''()]))
        stage ...+)
     (unless (memq (syntax-e #'execution) '(mrtr task task-optional))
       (raise-syntax-error #f "execution must be mrtr, task, or task-optional" stx #'execution))
     (define ids (syntax->list #'(a.id ...))) (check-binders (append ids (list #'outcome)) stx)
     (define args (argument-code ids (syntax->list #'(a.spec ...)) (syntax->list #'(a.optional ...)) (attribute a.default)))
     (define (stage-key prefix id) (string->symbol (string-append prefix (symbol->string (syntax-e id)))))
     (define (block body) (syntax-parse body #:literals (begin) [(begin form ...+) (syntax->list #'(form ...))] [_ (list body)]))
     (define (compile-sequence forms bound prefix wrap [join #f])
       (when (null? forms) (raise-syntax-error #f "workflow requires a completion expression" stx))
       (define (proc expression)
         #`(mcp-handler (env) (workflow-environment (#,@(for/list ([binding (in-list bound)]) #`[#,(car binding) (hash-ref env '#,(cdr binding) missing)])) #,(wrap expression))))
       (define first (expand-workflow-extension (car forms))) (define tail (cdr forms))
       (define (node id kind schema procedure [adapter #f] [policy #f])
         (check-literal-schema! schema)
         (workflow-node id kind schema procedure adapter policy first))
       (define (continuation)
         (if (null? tail) '() (compile-sequence tail bound (string-append prefix "after/") wrap join)))
       (define (destination after) (if (null? after) join (workflow-node-id (car after))))
       (syntax-parse first #:literals (checkpoint await-input perform if match let begin)
         [(await-input ([id:id spec:expr request:expr] ...+))
          (define names (syntax->list #'(id ...)))
          (check-binders (append (map car bound) names) stx)
          (define keys (map (lambda (id) (stage-key prefix id)) names))
          (define group-id (string->symbol (string-append prefix "$inputs/" (symbol->string (car keys)))))
          (define specs (syntax->list #'(spec ...)))
          (for-each check-literal-schema! specs)
          (define requests (syntax->list #'(request ...)))
          (cons (node group-id 'input-group
                      #`(object-schema (hasheq #,@(append-map (lambda (key spec) (list #`'#,key spec)) keys specs)))
                      (proc #`(hasheq #,@(append-map (lambda (key request) (list #`'#,key request)) keys requests))) keys)
                (compile-sequence tail (append bound (map cons names keys)) prefix wrap join))]
         [((~and kind (~or checkpoint await-input)) [id:id spec:expr] value:expr)
          (check-binders (append (map car bound) (list #'id)) stx)
          (define wire-id (stage-key prefix #'id))
          (cons (node wire-id (if (free-identifier=? #'kind #'checkpoint) 'checkpoint 'input) #'spec (proc #'value))
                (compile-sequence tail (append bound (list (cons #'id wire-id))) prefix wrap join))]
         [(perform [id:id spec:expr] #:adapter adapter:id #:policy policy:id value:expr)
          (unless (memq (syntax-e #'policy) '(transactional idempotent manual)) (raise-syntax-error #f "unknown effect policy" stx #'policy))
          (check-binders (append (map car bound) (list #'id)) stx)
          (define wire-id (stage-key prefix #'id))
          (cons (node wire-id 'effect #'spec (proc #'value) #'adapter (syntax-e #'policy))
                (compile-sequence tail (append bound (list (cons #'id wire-id))) prefix wrap join))]
         [(begin body ...+)
          (compile-sequence (append (syntax->list #'(body ...)) tail) bound prefix wrap join)]
         [(let ([id:id value:expr] ...) body ...+)
          (define names (syntax->list #'(id ...)))
          (check-binders names stx)
          (define after (continuation))
          (define inner-prefix (string-append prefix "let/"))
          (define keys (map (lambda (id) (stage-key inner-prefix id)) names))
          (define bindings
            (for/list ([id names] [value (syntax->list #'(value ...))] [key keys])
              (node key 'checkpoint #'Any (proc value))))
          (define outer
            (filter (lambda (binding) (not (ormap (lambda (id) (bound-identifier=? id (car binding))) names))) bound))
          (append bindings
                  (compile-sequence (syntax->list #'(body ...)) (append outer (map cons names keys))
                                    inner-prefix wrap (destination after))
                  after)]
         [(if condition then otherwise)
          (define after (continuation))
          (define branch-id (string->symbol (string-append prefix "$branch")))
          (define yes (compile-sequence (block #'then) bound (string-append prefix "then/") wrap (destination after)))
          (define no (compile-sequence (block #'otherwise) bound (string-append prefix "else/") wrap (destination after)))
          (cons (node branch-id 'branch #'Integer (proc #'(if condition 0 1))
                      (list (workflow-node-id (car yes)) (workflow-node-id (car no))))
                (append yes no after))]
         [(match subject [pattern body ...+] ...+)
          (define after (continuation))
          (define subject-id (string->symbol (string-append prefix "$subject")))
          (define branch-id (string->symbol (string-append prefix "$match")))
          (define patterns (syntax->list #'(pattern ...)))
          (define bodies (map syntax->list (syntax->list #'((body ...) ...))))
          (define branches
            (for/list ([pattern (in-list patterns)] [body (in-list bodies)] [i (in-naturals)])
              (compile-sequence body bound (format "~acase~a/" prefix i)
                                (lambda (expr) (wrap #`(match (hash-ref env '#,subject-id) [#,pattern #,expr]))) (destination after))))
          (define selector #`(match (hash-ref env '#,subject-id) #,@(for/list ([pattern (in-list patterns)] [i (in-naturals)]) #`[#,pattern #,i])))
          (define targets (map (lambda (branch) (workflow-node-id (car branch))) branches))
          (append (list (node subject-id 'checkpoint #'Any (proc #'subject))
                        (node branch-id 'branch #'Integer (proc selector) targets))
                  (apply append branches) after)]
         [value:expr
          (unless (null? tail) (raise-syntax-error #f "expected a persistent stage or final result" stx first))
          (list (node (string->symbol (string-append prefix "completion")) (if join 'jump 'complete)
                      #'Any (proc (if join #'(begin value json-null) #'value)) join))]))
     (define nodes (compile-sequence (syntax->list #'(stage ...)) (map (lambda (id) (cons id (syntax-e id))) ids) "" values))
     (define effect-nodes (filter (lambda (node) (eq? (workflow-node-kind node) 'effect)) nodes))
     (define policies (make-hasheq))
     (for ([node (in-list effect-nodes)])
       (define key (syntax-e (workflow-node-adapter node)))
       (when (and (hash-has-key? policies key) (not (eq? (hash-ref policies key) (workflow-node-policy node))))
         (raise-syntax-error 'perform "conflicting policies for the same effect adapter" (workflow-node-source node) (workflow-node-adapter node)))
       (hash-set! policies key (workflow-node-policy node)))
     (define effect-ids (remove-duplicates (map workflow-node-adapter effect-nodes) free-identifier=?))
     (define stages (emit-workflow-nodes nodes))
     (define stage-summaries
       (for/list ([node (in-list nodes)])
         #`(#,(workflow-node-id node) #,(workflow-node-kind node) #,(workflow-node-schema node)
             #,(workflow-node-adapter node) #,(workflow-node-policy node) #,(workflow-node-source node))))
     ;; Include normalized emitted stages so extension expansion changes affect
     ;; compatibility even when the caller's source is unchanged.
     (define fingerprint (format "mcp-workflow/3:~s:~s" (syntax->datum stx) (map syntax->datum stages)))
     (define program-code
       #`(workflow-effects (#,@(for/list ([id (in-list effect-ids)]) #`[#,id '#,id]))
           (make-workflow (symbol->string 'name) version #,fingerprint (list #,@stages) #:key key
                          #:changes (lambda (arguments outcome)
                                      (let (#,@(for/list ([id ids]) #`[#,id (hash-ref arguments '#,id missing)])) changes)))))
     (if program-only?
         (if summaries? (values program-code stage-summaries) program-code)
     #`(begin (define-operation-value name
         (let ([program #,program-code])
           (make-tool (symbol->string 'name) (list #,@args)
                      (lambda (bound)
                        (unless (current-workflow-store) (error 'workflow "a configured workflow store is required"))
                        (run-workflow program (current-workflow-store) (for/hasheq ([(k v) (in-hash bound)] #:unless (missing? v)) (values k v))
                                      #:principal (principal-key (request-context-principal (current-request-context)))
                                      #:state (current-workflow-state) #:responses (current-workflow-responses)
                                      #:adapters (current-workflow-adapters))) #:description description #:workflow program #:execution 'execution))) (register-declaration name #:declaration workflow name #,stx #:workflow-nodes (#,@stage-summaries))))]))
