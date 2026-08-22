# ls.M1-001 — implementation notes

**Issue:** #1 — scaffold + caps.decl
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 (paideia-os).

## What landed

- `caps.decl` — the four caps ls holds at exec time: `KIND_USER`,
  `KIND_TTY(write)`, `KIND_PDXFS_FILE(read, <arg-path>)`, and
  `KIND_IPC_ENDPOINT`. Declares the `PdxFsDirEntry@0.1` output schema
  for the M3 semantic-pipe integration.
- `design/architecture.md` — full internal spec across all four
  modules the ls binary will host at M1 close (Ls, ArgvSurface,
  Runner, Dispatch), the M1 skeleton discipline, the return-code
  band 0xFFFFEBxx table, paideia-as conformance, and explicit
  non-goals for M1.
- `src/ls.pdx` — `Ls` module: KIND ordinal mirrors, error-code
  constants (both `AS_*` for ArgvSurface at M1-002 and `LS_RUN_*` for
  Runner at M1-003 pre-declared so those two follow-on issues are
  body-only edits), tool-level `.bss` stats singleton, `ls_reset()`,
  `ls_note(which)`, `ls_stat(which)`.
- `.plans/README.md` — pointer to per-milestone notes.
- `STATUS.md` — bumped to reflect M1-001 landed.
- `tests/README.md` — pointer to `ls.M4-001` for the actual test
  matrix (empty at M1 by design).

## Design decisions

- **Singleton `.bss` stats table.** Follows the `Shell::_shell_stats`
  / `libpdx-argv::ParsedArgs` / `ElevateBroker._elevate_broker_stats`
  precedent. Zero heap, one instance per process is enough for R50
  tools. Cache-line aligned so an SMP future does not force a
  relayout.
- **Return-code band 0xFFFFEBxx.** Chosen to sit between
  libpdx-elevate's 0xFFFFEAxx and the shell's 0xFFFFECxx so the
  layer identification from the high two bytes is unambiguous.
  Sub-bands: 0xFFFFEB1x = ArgvSurface, 0xFFFFEB2x = Runner. LS_OK
  reserved at 0xFFFFEB00 for the future Runner success return.
- **KIND_TTY provisional ordinal 0x196.** Same treatment as
  shell.M1-001's `SH_KIND_TTY`. kind_tty.pdx has not landed in
  paideia-os at HEAD; the mirror is pinned when the substrate PR
  lands, and the M4 smoke matrix catches drift.
- **Pre-declared AS_* and LS_RUN_* codes.** Both live in `Ls` (this
  file) rather than in their own modules so the consuming Dispatch
  module can spell them without cross-module import ceremony, and so
  M1-002 / M1-003 are body-only additions rather than constant
  reshuffles. Same pattern the shell used: SH_KIND_*, LR_*, EX_* all
  live in `Shell` even though `LR_*` are consumed by LineReader and
  `EX_*` by Exec.
- **caps.decl path narrowing template.** `KIND_PDXFS_FILE(read,
  <arg-path>)` is a template: the concrete argument path is bound by
  the shell's exec-time cap_manifest_verify at ls.M2 when it hands
  the narrowed cap. The template shape here is what the shell has to
  satisfy — never ambient authority on the whole filesystem.

## paideia-as conformance

- Module name PascalCase basename (`Ls`) with no directory prefix.
- No `test` mnemonic anywhere; every zero-check is `cmp reg, 0`.
- Every `cmp reg, imm` uses an immediate ≤ 0x7FFFFFFF (max value
  seen: `8` — the counter table bound in ls_reset / ls_note /
  ls_stat).
- `r10` used as base pointer for the `.bss` counter table (loaded
  once via lea); never assumed live across a call.
- No byte reads in this module — the `xor rax, rax; mov_b rax, [ptr]`
  pattern lands at ls.M1-002 in ArgvSurface when it walks
  flag_names.
- All three functions are LEAF — no push/pop parity to preserve.

## Cross-module linkage

M1-001 defines no externals. M1-002's ArgvSurface will call
`ls_note` (and read `LS_ST_*` slot constants); M1-003's Runner will
do the same; M1-003's Dispatch will read `AS_OK` / `AS_ERR_*` /
`LS_RUN_*` constants. All resolved by unqualified linker name — the
same pattern libpdx-argv's `Parser` uses to reach `flag_names` /
`flag_values` in `ParsedArgs`.

## What did not land (queued for M1-002 and beyond)

- ArgvSurface module + flag-bit recognition + path capture —
  ls.M1-002.
- Runner module + stub body + path-argument gating — ls.M1-003.
- Dispatch composition module + `ls_dispatch(argv, argc)` —
  ls.M1-003.
- `-l` long-format rendering, `-a` hidden-file toggle, `-h` human-
  readable size — ls.M2-001 through ls.M2-003.
- Coloring driven by declared schema/MIME — ls.M2-004.
- PdxFsDirEntry[] emission on stdout — ls.M3-001.
- Owner column via KIND_USER_ref decode through libpdx-cap —
  ls.M2-002.
- DirListRecord via libpdx-audit — ls.M3-003.
- Test corpus + exit-code matrix + smoke — ls.M4-001 through
  ls.M4-004.
- Dual-signed release + `.pdxdoc` + mirror push — ls.M5.

## Build note

ls M1 has no local build script yet. paideia-as ≥ v0.33 (for the
`mov_b` narrow-load mnemonic + the `@align` attribute) will build
this module and its M1-002 / M1-003 companions once main invokes
`paideia-as build src/ls.pdx src/argv_surface.pdx src/runner.pdx
src/dispatch.pdx -o build/ls.pdx` — the exact invocation is an
ls.M2 concern, not M1.
