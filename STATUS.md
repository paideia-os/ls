# ls — status

**Wave:** R50 (Wave 2)
**Current milestone:** M1 (design + skeleton) — in progress

## Milestone rollup

| ID              | Title                                                          | State  |
|-----------------|----------------------------------------------------------------|--------|
| M1-001 (#1)     | scaffold + caps.decl                                           | LANDED |
| M1-002 (#2)     | argv surface via libpdx-argv                                   | LANDED |
| M1-003 (#3)     | first runnable: entry-name print to KIND_TTY                   | OPEN   |

See `design/tooling/r49-r50-plan.md` §5.4 in paideia-os for the full
milestone breakdown (M1–M5) and cross-repo dependencies.

## Local layout

- `design/architecture.md` — internal spec (four modules, .bss shape,
  return-code band, paideia-as conformance, M2 evolution notes).
- `src/ls.pdx` — `Ls` module (KIND mirrors + error band + stats).
- `src/argv_surface.pdx` — `ArgvSurface` module (flag-bit recogniser
  around `libpdx-argv::Parser`).
- `caps.decl` — the four caps ls receives at exec (KIND_USER,
  KIND_TTY, KIND_PDXFS_FILE, KIND_IPC_ENDPOINT).
- `tests/` — empty until `ls.M4-001` lands the fixture matrix.
- `.plans/` — per-milestone implementation notes.
