# Discovery capability acceptance coverage

Three authored cases pass on Linux Racket 9.2 and 9.3. They exercise all twelve
valid combinations of ordinary tools, resources, prompts and prompt completion;
view removal including dependent completion; and Tasks advertisement with a
workflow versus storage alone. Ordinary handlers remain uninvoked and the Tasks
store remains empty after discovery. Requests pass through dispatch-message.

```sh
raco make tests/discovery-capabilities.rkt
raco test tests/discovery-capabilities.rkt
```

Logs have trailing whitespace trimmed. The same three cases passed again in the main worktree on both versions.
The packaged copy also passed compilation and all three cases. Runtime code is
unchanged from the preceding full 9.3 run (5,969 native checks); that broad run
was not repeated for this test-only addition.
These cases cover the named advertisement behavior, not all optional capability
semantics, authorization policies or upstream task adapters.
