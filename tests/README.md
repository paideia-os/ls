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
- `schema_golden.pdx` — `ls.M4-004` (#14), updated at `ls.ENH-010`
  (#27). Two goldens: the real PdxFsDirEntry@0.1 schema id (pre-BLAKE3
  fold via `libpdx-semantic-pipe::Schema::spipe_schema_id_from_name`,
  byte-identical to that library's own golden) imprinted by
  `SemanticEmit::sem_emit_reset`, and the 144-byte wire-body
  composition via `SemanticEmit::sem_emit_wire_compose` (a compose-
  only sibling of `sem_emit_entry` added at M4-004 so the wire
  spec is testable without a live libpdx-semantic-pipe substrate).
- `long_format_fixtures.pdx` — `ls.ENH-003` (#17). Byte-exact
  goldens for `LongFormat::long_format_line`; 3 cases (file mode
  0o644, dir mode 0o755, symlink mode 0o777) with deterministic
  uid/size/mtime. Pins the six-column `-l` layout (`kind mode owner
  size mtime name\n`, single-space separators). Retires the
  enhancement-plan §2.2 "dead code with no fixture" status ahead
  of ENH-002 (#24) wiring `LongFormat` into the read loop.
- `human_size_fixtures.pdx` — `ls.ENH-003` (#17). Byte-exact
  goldens for `HumanSize::human_size_render`; 6 boundary cases
  spanning the fast path (0, 999) and the slow path (1024→`1.0K`,
  1536→`1.5K`, 1048576→`1.0M`, 1099511627776→`1.0T`). Pins both the
  base-2 unit dispatch and the tenth-digit derivation.
- `json_line_fixtures.pdx` — v1.1.1 post-1.1.0 debugger finding 3.
  Byte-exact goldens for `JsonLine::json_line_render`; 7 cases
  pinning the v1.1.1 RFC 8259 escape overhaul: plain name
  (passthrough), the three shortcut escapes most likely to fire
  in the wild (`"` → `\"`, `\` → `\\`, `0x0A` → `\n`), the six-byte
  `\u00XX` fallback for `0x01`, the 104-byte max-input clamp, and
  the overflow-sentinel path with an undersized `dst_cap`. Retires
  the pre-1.1.1 "no fixture" line for the JSON-lines renderer.
- `schema_dump_fixtures.pdx` — v1.1.1 post-1.1.0 debugger finding 3.
  One byte-diff of `SchemaDump::_sd_catalog_bytes` against a local
  52-byte golden copy. This is the tripwire the `caps.decl`
  invariant note points at (v1.1.1 finding 2): the `SchemaDump`
  catalog literal, the `SemanticEmit` schema-name literals, and
  `caps.decl :: declares_output_schemas` must stay lock-step; any
  drift here fails the diff.
- `goldens/` — human-readable copies of each fixture case's
  expected byte sequence. Not read at build/test time (paideia-as
  fixture modules have no filesystem cap); the `.rodata` tables in
  the `.pdx` fixtures are the authority. See `goldens/README.md`.

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
