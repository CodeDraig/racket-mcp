(module command-go-server '#%kernel
  (#%require (file "/srv/data/code/racket-mcp/mcp/command.rkt"))
  (current-command-line-arguments
    (vector "serve" "/srv/data/code/racket-mcp/examples/greeter.rkt"))
  (main))
