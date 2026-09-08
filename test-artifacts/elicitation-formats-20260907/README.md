# MCP elicitation format assertions, 2026-09-07

The earlier four failing assertions are retained in
`../elicitation-formats-probe-20260907`. The shared response validator now applies
MCP's date, date-time, email and URI assertions after normal schema validation.
It is used by workflow, Tasks and upstream response handling. The interaction
runner validates requests before callbacks and responses before automatic MRTR
retries or Tasks updates. Workflow request construction validates both individual
and grouped elicitation requests before pending-state persistence. URL-mode
requests must contain a syntactically valid URI.

The private native implementation follows RFC 3339 date/time syntax and calendar
bounds, RFC 3986 generic URI syntax, and RFC 5321 mailbox syntax with IPv4/IPv6
address literals. It performs no DNS, network or local-time-zone operations.
Leap-second checking validates possible UTC month-end placement after offset
conversion; it does not consult historical or predicted leap-second bulletins.
Ordinary JSON Schema format stays an annotation. Application navigation and
scope policies remain independent of generic URI syntax.

All 242 pinned optional date/date-time/email/URI cases pass through this private
assertion layer. This result is a subset of the native suite, not an additional
242 cases on top of its total, and does not enable the full format-assertion
vocabulary. Authored regressions also cover empty URI authorities, malformed
IPv6 compression, escaped mailbox locals, zero/omitted/null/false distinctions,
invalid callback output before retries, invalid requests before callbacks,
SQLite reopen after rejected input, unchanged Tasks state, and malformed requests
before pending-state persistence.

The first quoted-mailbox regex had an invalid native character class, followed
by a reader parenthesis error; a direct character scanner replaced that regex.
A separate URI probe exposed an exception for empty authorities, which is fixed
and covered by authored cases. Three durable-test fixture errors were corrected:
work was moved into an ordinary helper, grouped schemas received named response
fields, and the group stage and input received distinct identities. Their failed
logs are retained; none is a passing verification claim.

The focused integration selection passed 533 checks on Linux/Racket 9.3. The focused Racket 9.2 and installed-package selections each passed 448 checks.
All 14 Go probes and installed dependency setup passed. Final full validation passed 5,747 native checks, 1,301 core schema cases,
86 optional regex cases and Scribble on Linux/Racket 9.3; see `full.log`.

Five pinned independent MCP scenarios passed all 16 checks: basic elicitation,
multi-round input, non-tool input, request state and malformed responses. The
279 vendored harness files were hash-verified before copying. Project-filesystem
npm extraction left a missing module despite exiting successfully; its log is
retained. A fresh temporary copy installed correctly with `npm ci --ignore-scripts`
and the CLI startup check passed before scenarios ran. The fixture server on
loopback port 18837 was stopped after validation. No runtime dependency changed.
These targeted scenarios do not establish complete conformance. Saved
logs have trailing whitespace trimmed. The complete SDK release remains open.

Primary references:
- https://www.rfc-editor.org/rfc/rfc3339.html
- https://www.rfc-editor.org/rfc/rfc3986.html
- https://www.rfc-editor.org/rfc/rfc5321.html
