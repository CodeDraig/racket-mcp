# Refresh-capable client metadata, 2026-09-08

Pinned authorization/index.mdx lines 305-309 recommend advertising refresh_token
in grant_types for clients that want refresh tokens. The native runner implements
refresh, but the metadata constructor previously advertised authorization_code
alone. It now advertises both by default. An explicit authorization-code-only
grant_types override remains supported through #:extra. Advertising support does
not require an authorization server to issue a refresh token. The optional
offline_access scope is not inferred or added automatically.

The focused Racket 9.3 run passed 163 registration, flow, authentication and policy
checks, followed by Scribble. The Racket 9.2 registration/flow run passed 74 checks.
The unchanged pinned basic-cimd harness scenario passed 12 checks, zero failures
or warnings. That scenario verifies the CIMD flow; the authored native metadata
checks verify the actual grant_types default and override, which that harness
scenario does not inspect. The fixture does not host a real client metadata URL.

Commands: raco make and raco test on the named suites in the retained logs;
raco scribble +m --htmls; pinned conformance client --scenario auth/basic-cimd
--spec-version 2026-07-28. Logs have trailing whitespace trimmed. The full native
suite passed on the immediately preceding OAuth commit; it was not repeated for
this metadata-default follow-up. Full SDK release gates remain open.
