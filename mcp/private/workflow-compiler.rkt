#lang racket/base
(require racket/match
         "../descriptor.rkt"
         "../schema.rkt"
         "../json.rkt"
         "../workflow.rkt"
         "../authorization.rkt"
         "domain-bindings.rkt"
         "extensions.rkt"
         "handler.rkt"
         "registration.rkt"
         "module-build-context.rkt"
         "workflow-stage-forms.rkt"
         (for-syntax
          racket/base
          racket/list
          syntax/parse
          "declaration-syntax.rkt"
          "workflow-match.rkt"
          "workflow-binding-context.rkt"
          "workflow-ir.rkt"))
(provide (for-syntax compile-workflow))
(begin-for-syntax (struct match-binding (record index)))
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
     (define (compile-sequence forms bound prefix wrap [join #f] [effects '()])
       (when (null? forms) (raise-syntax-error #f "workflow requires a completion expression" stx))
       (define (proc expression [visible-effects effects])
         #`(mcp-owned-handler name (env)
             (workflow-environment
              (#,@(for/list ([binding (in-list bound)])
                    (define reference (cdr binding))
                    #`[#,(car binding)
                       #,(if (match-binding? reference)
                             #`(list-ref (cadr (hash-ref env '#,(match-binding-record reference))) #,(match-binding-index reference))
                             #`(hash-ref env '#,reference missing))]))
              (workflow-effects (#,@(for/list ([id (in-list visible-effects)]) #`[#,id '#,id]))
                #,(wrap expression)))))
       (define first
         (call-with-workflow-binding-context (map car bound)
           (lambda () (expand-workflow-extension (car forms))) #:effects effects))
       (define tail (cdr forms))
       (define (node id kind schema procedure [adapter #f] [policy #f])
         (check-literal-schema! schema)
         (workflow-node id kind schema procedure adapter policy first))
       (define (continuation)
         (if (null? tail) '() (compile-sequence tail bound (string-append prefix "after/") wrap join effects)))
       (define (destination after) (if (null? after) join (workflow-node-id (car after))))
       (syntax-parse first #:literals (checkpoint await-input perform task-boundary if match let begin)
         [(task-boundary id:id)
          (cons (node (stage-key prefix #'id) 'task-boundary #'Any (proc #'json-null))
                (compile-sequence tail bound prefix wrap join effects))]
         [(await-input ([id:id spec:expr request:expr] ...+))
          (define names (map syntax-local-identifier-as-binding (syntax->list #'(id ...))))
          (check-binders (append (map car bound) names) stx)
          (define keys (map (lambda (id) (stage-key prefix id)) names))
          (define group-id (string->symbol (string-append prefix "$inputs/" (symbol->string (car keys)))))
          (define specs (syntax->list #'(spec ...)))
          (for-each check-literal-schema! specs)
          (define requests (syntax->list #'(request ...)))
          (cons (node group-id 'input-group
                      #`(object-schema (hasheq #,@(append-map (lambda (key spec) (list #`'#,key spec)) keys specs)))
                      (proc #`(hasheq #,@(append-map (lambda (key request) (list #`'#,key request)) keys requests))) keys)
                (compile-sequence tail (append bound (map cons names keys)) prefix wrap join effects))]
         [((~and kind (~or checkpoint await-input)) [id:id spec:expr] value:expr)
          (define binder (syntax-local-identifier-as-binding #'id))
          (check-binders (append (map car bound) (list binder)) stx)
          (define wire-id (stage-key prefix #'id))
          (cons (node wire-id (if (free-identifier=? #'kind #'checkpoint) 'checkpoint 'input) #'spec (proc #'value))
                (compile-sequence tail (append bound (list (cons binder wire-id))) prefix wrap join effects))]
         [(perform [id:id spec:expr] #:adapter adapter:id #:policy policy:id value:expr)
          (unless (memq (syntax-e #'policy) '(transactional idempotent manual)) (raise-syntax-error #f "unknown effect policy" stx #'policy))
          (define binder (syntax-local-identifier-as-binding #'id))
          (check-binders (append (map car bound) (list binder)) stx)
          (define wire-id (stage-key prefix #'id))
          (define adapter-id (syntax-local-identifier-as-binding #'adapter))
          (define next-effects
            (if (ormap (lambda (id) (bound-identifier=? id adapter-id)) effects)
                effects (append effects (list adapter-id))))
          (cons (node wire-id 'effect #'spec (proc #'value next-effects) adapter-id (syntax-e #'policy))
                (compile-sequence tail (append bound (list (cons binder wire-id))) prefix wrap join next-effects))]
         [(begin body ...+)
          (compile-sequence (append (syntax->list #'(body ...)) tail) bound prefix wrap join effects)]
         [(let ([id:id value:expr] ...) body ...+)
          (define names (map syntax-local-identifier-as-binding (syntax->list #'(id ...))))
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
                                    inner-prefix wrap (destination after) effects)
                  after)]
         [(if condition then otherwise)
          (define after (continuation))
          (define branch-id (string->symbol (string-append prefix "$branch")))
          (define yes (compile-sequence (block #'then) bound (string-append prefix "then/") wrap (destination after) effects))
          (define no (compile-sequence (block #'otherwise) bound (string-append prefix "else/") wrap (destination after) effects))
          (cons (node branch-id 'branch #'Integer (proc #'(if condition 0 1))
                      (list (workflow-node-id (car yes)) (workflow-node-id (car no))))
                (append yes no after))]
         [(match subject [pattern body ...+] ...+)
          (define after (continuation))
          (define subject-id (string->symbol (string-append prefix "$subject")))
          (define capture-id (string->symbol (string-append prefix "$match-values")))
          (define branch-id (string->symbol (string-append prefix "$match")))
          (define patterns (syntax->list #'(pattern ...)))
          (define bodies (map syntax->list (syntax->list #'((body ...) ...))))
          (define-values (capture pattern-bindings)
            (compile-match-capture first #`(hash-ref env '#,subject-id) patterns))
          (define branches
            (for/list ([names (in-list pattern-bindings)] [body (in-list bodies)] [i (in-naturals)])
              (define binders (map syntax-local-identifier-as-binding names))
              (define outer
                (filter (lambda (binding)
                          (not (ormap (lambda (id) (bound-identifier=? id (car binding))) binders))) bound))
              (define captured
                (for/list ([id (in-list binders)] [index (in-naturals)])
                  (cons id (match-binding capture-id index))))
              (compile-sequence body (append outer captured) (format "~acase~a/" prefix i)
                                wrap (destination after) effects)))
          (define selector #`(car (hash-ref env '#,capture-id)))
          (define targets (map (lambda (branch) (workflow-node-id (car branch))) branches))
          (append (list (node subject-id 'checkpoint #'Any (proc #'subject))
                        (node capture-id 'checkpoint #'Any (proc capture))
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
     (define stages (emit-workflow-nodes nodes))
     (define stage-summaries
       (for/list ([node (in-list nodes)])
         #`(#,(workflow-node-id node) #,(workflow-node-kind node) #,(workflow-node-schema node)
             #,(workflow-node-adapter node) #,(workflow-node-policy node) #,(workflow-node-source node))))
     ;; Include normalized emitted stages so extension expansion changes affect
     ;; compatibility even when the caller's source is unchanged.
     (define fingerprint (format "mcp-workflow/3:~s:~s" (syntax->datum stx) (map syntax->datum stages)))
     (define program-code
       #`(with-enclosing-module-build-context
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
