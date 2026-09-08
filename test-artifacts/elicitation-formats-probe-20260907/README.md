# Elicitation format gap, 2026-09-07

The response validator uses general JSON Schema validation, where format is an
annotation. The approved SDK plan additionally requires MCP elicitation format
checks. This probe asserts rejection of four independently invalid values under
valid string schemas: an impossible date, a non-timestamp, a non-email and a
non-URI. The initial run fails all four assertions on Linux/Racket 9.3.

The shared validator is used by workflow, Tasks and upstream response paths.
The interaction runner currently calls elicitation callbacks without applying
that validator. A correction must cover both sides while retaining annotation
semantics for ordinary JSON Schema validation. No runtime correction is included
in this probe. It does not redefine the general schema vocabulary.
