# Durable workflow match bindings, 2026-09-07

The initial replay probe called its match `app` expression three times before
suspension and a fourth time after resume. The binding probe also failed to
recognize a pattern variable through the public workflow extension query API.
Both failures are retained.

The compiler now captures the selected branch and all its bound values in a
checkpoint before branching. Later stages read those saved values; they do not
re-run the pattern. This preserves predicate decisions and transformed values
across input boundaries and restart. Pattern computations must remain replay-safe
until that checkpoint commits, and bound values use the built-in JSON codec.
Non-JSON values fail before entering the branch. This is not an exactly-once
promise for host effects before checkpoint persistence.

A small private adapter uses Racket's match parser, bound-variable query and code
generator. Each pattern is parsed once; the same private representation supplies
the bindings and generated matcher. No Racket pattern IR is exposed by the public
extension API. The adapter needs verification on each supported Racket release.
Binding slots preserve lexical identities independently of wire names. Branch
bindings shadow outer values and stay out of the following join.

Tests cover extension binding queries, ellipses, nested matches, shadowing,
alternatives, repeated variables, imported/renamed match expanders, macro-private
temporaries, expansion count, shifted phases, fingerprint equality, and SQLite
reopen after changing a predicate so re-matching would select a different branch.
A child-process fixture refuses to run its matcher in a resumed process and
checks an independent counter file. The ordinary compiled restart passed six
checks. The source-only restart uses Racket's `-c` flag in each child to cover
fresh expansion, not just reuse of a compiled artifact.

The final focused selection passed 194 checks on Linux/Racket 9.3. The Racket
9.2 selection passed 31 checks, including fresh-source process restart. All 14 Go
probes and installed dependency setup passed. The installed package also passed
31 checks, including fresh-source restart. The final full 9.3 run passed 5,778
native checks, 1,301 core schema cases, 86 optional regex cases and Scribble.
The separate language probe passed five checks for expansion/execution count and
manifest access without parent instantiation. Logs have trailing whitespace
trimmed. This does not close the complete SDK release or platform gates.
