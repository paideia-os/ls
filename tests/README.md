# tests/

Empty at M1 by design. The correctness matrix —

- coloring correctness against a known-schema fixture corpus,
- owner-render correctness for multi-user quota-share subtrees,
- exit-code matrix (empty=0, missing=2, cap-denied=4),
- `ls --schema` output validated against the libpdx-semantic-pipe
  golden emit,

— lands with `ls.M4-001` through `ls.M4-004` per
`design/tooling/r49-r50-plan.md` §5.4 in paideia-os.

The M1 first-runnable example (a caller passes a hardcoded argv
through `Dispatch::ls_dispatch` and observes `AS_OK` followed by
`LS_RUN_STUB`) is a harness-only exercise — no automated fixture at
M1. The first live invocation happens once the shell wires exec at
`shell.M2` and the PdxFS v1 substrate at r49-r50-plan.md §2.4 lands.
