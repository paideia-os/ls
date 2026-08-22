# tests/

M4 fixtures land here as paideia-as `.pdx` modules that a future M5
smoke harness invokes. Each fixture ships golden data (`.rodata`
tables of expected inputs / outputs) plus verifier functions that
call the SUT (system under test) and return 0 on pass or a
sub-band sentinel on fail.

## Layout

- `color_fixtures.pdx` — `ls.M4-001` (#11). 10 dispatch cases
  (`ColorPicker::color_pick`) + 3 SGR byte-exact goldens
  (`color_sgr_prefix` and `color_sgr_suffix`). Every branch of the
  plan-doc §4.4 schema-first / kind-fallback palette dispatch is
  exercised, and the byte-perfect ANSI SGR bytes (`ESC [ N m`,
  `ESC [ 0 m`) are pinned as `.rodata` u64-packed goldens.
- `owner_fixtures.pdx` — `ls.M4-002` (#12). 7 multi-user quota
  subtree row-cases (rows 0, 1, 7, 42, 1000, 65534, 65535) through
  `OwnerCol::owner_col_render_from_row` + 2 wire-cap cases through
  `OwnerCol::owner_col_render_from_wire` (a KIND_USER cap round-
  trip and a KIND_TTY cap refusal).
- `exit_matrix.pdx` — `ls.M4-003` (#13). 13 rows covering every
  0xFFFFEBxx sentinel Ls declares against `ExitMap::exit_map`
  (`src/exit_map.pdx`, added at M4-003). The three lines the issue
  text pins ("empty=0", "missing=2", "cap-denied=4") are cases 0,
  7, 8 respectively.
- `schema_golden.pdx` — `ls.M4-004` (#14). Two goldens: the M3-001
  schema-hash imprint stub (first byte 0x01, rest zero) via
  `SemanticEmit::sem_emit_reset`, and the 144-byte wire-body
  composition via `SemanticEmit::sem_emit_wire_compose` (a compose-
  only sibling of `sem_emit_entry` added at M4-004 so the wire
  spec is testable without a live libpdx-semantic-pipe substrate).

## Public entry-point convention

Each fixture module exposes three uniform entry points:

```
<fixture>_case_count() -> u64            // total case count
<fixture>_run(case_idx) -> u64           // 0 on pass, sub-band sentinel on fail
<fixture>_verify_all() -> u64            // fail-fast walk over all cases
```

A future M5 smoke harness iterates through each module's
`<fixture>_verify_all` and treats a non-zero return as the case
index of the first drift.

## What is NOT in this tree

- The QEMU interactive smoke (`ls . | cat`, cross-shell history
  persistence) lands in the `shell` repo's M4-003.
- End-to-end run of `sem_emit_entry` against a live libpdx-
  semantic-pipe Recv is deferred to M5 (needs a bound endpoint
  substrate); the M4-004 fixture pins the compose-shape half of
  the round-trip so any drift is caught before M5.
- Live invocation from `_start` (paideia-os R14b bootstrap) is
  outside ls's M4 scope; the M2 `_start` design (see
  `design/architecture.md` §1) uses `ExitMap::exit_map` from
  `src/exit_map.pdx` — the module the M4-003 fixture verifies.
