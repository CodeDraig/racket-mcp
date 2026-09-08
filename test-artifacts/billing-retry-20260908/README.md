# Retry after billing update

The user reported updated GitHub billing. Dispatching native.yml on main created
run 34279042543 against commit 277d29c. GitHub created six matrix jobs, but the
Windows 9.3 job annotation explicitly reports:

"The job was not started because an Actions budget is preventing further use."

This establishes an Actions budget block for this retry; no SDK/platform test ran.
The account owner must adjust the blocking Actions budget or allow the billing
change to propagate. No spending limits or billing settings were changed by the
agent. run.json and annotations.json retain the observed status and diagnostic.
