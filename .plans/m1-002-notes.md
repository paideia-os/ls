# ls.M1-002 — implementation notes

**Issue:** #2 — argv surface via libpdx-argv
(`ls [-l|-a|-h|--json|--schema] <path>...`).
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 (paideia-os).

## What landed

- `src/argv_surface.pdx` — `ArgvSurface` module:
  - `AS_BIT_*` public constants (six flag bits: L, A, H, JSON,
    SCHEMA, COLOR).
  - `_as_flag_bits`, `_as_path_ptr`, `_as_color_value_ptr` .bss
    singletons.
  - `argv_surface_reset()` — leaf helper that zeroes the three .bss
    slots. Same shape as `ParsedArgs::reset` in libpdx-argv.
  - `argv_surface_parse(argv, argc) → u64` — the entry point.
    Bumps `LS_ST_INVOKES`, gates argv/argc, resets both .bss
    singletons, drives `Parser::parse_argv`, walks `flag_names[]`
    to set the recognised bits (including the `--pdx-schema` M1
    alias for `--schema`), captures `pos_ptrs[0]` as the target
    path, bumps `LS_ST_OKS`, and returns `AS_OK`. Any recognised
    error path bumps `LS_ST_ERRORS` and returns the corresponding
    `AS_ERR_*`.
- `.plans/m1-002-notes.md` — this file.
- `STATUS.md` — bumped to reflect M1-002 landed.

## Design decisions

- **Flag-name dispatch by first byte.** All four recognised long
  names have distinct first characters (`json` → 'j', `schema` →
  's', `color` → 'c', `pdx-schema` → 'p'), so byte0 alone routes
  the compare arm. A byte-by-byte compare per arm — same 30-line
  pattern libpdx-argv uses for its own `--pdx-schema` well-known
  compare in `src/parser.pdx`. No string library exists at M1.
- **Short-flag single-letter contract.** libpdx-argv v0.1 already
  rejects clustered short flags (`-la`) with `ERR_CLUSTERED_SHORT`.
  By the time we walk `flag_names[]` every short-flag entry is
  guaranteed to be a single letter + NUL, so `byte1 == 0` is a
  reliable "short vs long" discriminator without a second pass.
- **`--pdx-schema` as `--schema` alias.** libpdx-argv v0.1
  hard-recognises the flag via its `emit_schema` slot; the tool
  side of the same recognition maps it into `AS_BIT_SCHEMA` so the
  caller only needs to test one bit. When libpdx-argv M2 lands
  the 9-flag standard vocabulary (`--help`, `--version`,
  `--schema`, `--json`, `--color=`, `--dry-run`, `--verbose`,
  `--quiet`, `--no-cap:<name>`) the alias retires — ls.M2 will
  drop the `try_pdx_schema` arm and inherit the centralised
  recognition.
- **Reuse r12/r13 after parse_argv.** After the parse returns,
  the input argv/argc are not read again. r12 becomes the loop
  index `i`, r13 becomes the loop bound `flag_count`. Saves two
  additional callee-save pushes (r14, r15) with no correctness
  cost. Same "reuse after single-use" pattern doc's
  `DocDispatch::doc_dispatch` uses for its `r12` (repurposed
  from argv loop counter to name-length accumulator at
  `doc_dispatch_measure_name`).
- **Bump LS_ST_INVOKES unconditionally.** Shell/line_reader
  precedent: count every attempt, not just the successes. Lets
  the M4 smoke matrix distinguish "call site attempted the parse
  and hit a bad-argv gate" from "call site never reached
  ArgvSurface at all".
- **Ignore positional[1..]** at M1. Multi-path listing is the
  M4-002 corpus + M2's `-a`/`-l` rendering behaviour — the M1
  wire captures the first path only so a well-formed `ls .` /
  `ls /` / `ls /home/alice` invocation drives the composition
  end-to-end. `--` sentinel handling is queued for libpdx-argv
  M2-003 per r49-r50-plan.md §5.12.

## paideia-as conformance

- Module name PascalCase basename (`ArgvSurface`) with no
  directory prefix.
- No `test` mnemonic anywhere; every zero-check is `cmp reg, 0`.
- Every `cmp reg, imm` uses an immediate ≤ 0x7FFFFFFF. Max
  values seen: 0x7F (the ASCII range for character byte compares),
  0 (the NUL check and zero-slot gates). The 0xFFFFEBxx return
  sentinels are `mov rax, imm64` emissions, not compares.
- Every byte read is preceded by `xor rax, rax; mov_b rax, [ptr]`
  (#1248 mitigation).
- `r11` is scratch for every LEA base; `r10` is scratch for the
  current-flag-name pointer inside the walk. Neither is assumed
  live across a call.
- SysV push/pop parity: two callee-save pushes (r12, r13) +
  `sub rsp, 8` on entry (rsp % 16 → 0 for the four nested call
  sites: `ls_note`, `argv_surface_reset`, `parsed_args_reset`,
  `parse_argv`). Every ret is preceded by `add rsp, 8; pop r13;
  pop r12`.

## Cross-module linkage

- Read: `flag_names`, `flag_values`, `flag_count`, `pos_ptrs`,
  `pos_count` from libpdx-argv's `ParsedArgs`. Resolved by
  unqualified linker name (the paideia-as toolchain convention).
- Called: `parsed_args_reset` and `parse_argv` from libpdx-argv;
  `ls_note` from `Ls` in `src/ls.pdx`.

## What did not land (queued for M1-003 and beyond)

- Runner module + stub body + path-argument gating —
  ls.M1-003.
- Dispatch composition module + `ls_dispatch(argv, argc)` —
  ls.M1-003.
- `-l` long-format rendering (setting `AS_BIT_L` is not the same
  as rendering it) — ls.M2-001.
- `-a` hidden-file behaviour — ls.M2-003.
- `-h` human-readable size — ls.M2-003.
- `--color=<value>` palette dispatch — ls.M2-004.
- `PdxFsDirEntry[]` schema emission on `--schema` — ls.M3-001.
- Multi-path listing (positional[1..]) — ls.M4-002 corpus + M2's
  rendering behaviour.
- Standard 9-flag vocabulary (retiring the local `pdx-schema`
  alias) — inherited at ls.M2 from libpdx-argv.M2.
