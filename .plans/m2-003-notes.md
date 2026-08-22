# ls.M2-003 — implementation notes

**Issue:** #6 — `-a` hidden-files toggle + `-h` human-readable size.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 (paideia-os).

## What landed

- `src/render.pdx` — new `Render` module (M2 shared utility):
  - `render_dec_u64(dst, cap, val) -> bytes | RENDER_ERR_OVERFLOW`
    — two-pass decimal render (count digits, write MSB-first from
    `dst + n - 1`). Overflow leaves dst untouched, mirroring
    `cap_pack`'s fail-fast discipline.
  - `render_byte_write(dst, cap, byte) -> 1 | RENDER_ERR_OVERFLOW`
    — the one-byte-append primitive every M2 layout module uses
    for column separators and single-character suffixes.
- `src/hidden_filter.pdx` — new `HiddenFilter` module:
  - `hidden_filter_accept(name_ptr, show_hidden) -> 1|0`
    — POSIX dot-prefix filter with the `-a` short-circuit before any
    byte load.
- `src/human_size.pdx` — new `HumanSize` module:
  - `human_size_render(dst, cap, bytes) -> bytes | HS_ERR_OVERFLOW`
    — GNU-`ls -h`-compatible base-2 render (K/M/G/T/P/E). Precompute-
    then-emit phase separation keeps `prev` off the live-across-call
    set; the tenth digit derives from `(prev & 0x3FF) * 10 >> 10`.
- `src/ls.pdx` — three new named stat slots (5 `LS_ST_HIDDEN`,
  6 `LS_ST_LONG`, 7 `LS_ST_COLOR`). The `_ls_stats` array size stays
  8; these were the "5..7 reserved" slots M1 called out. M2
  primitives do NOT bump these -- pure-function discipline. M3
  wires the bumps when Runner composes the primitives with the
  readdir loop.

## Design decisions

- **Base-2 (1024) over base-10 (1000) in HumanSize.** Same choice
  GNU `ls -h` defaults to.  R42 PdxFS-v1 block sizes are power-of-
  two aligned; a base-10 render would show 4096 as "4.1K" whereas
  base-2 gives "4.0K", which is the value the user sees in every
  filesystem tool.
- **Precompute-then-emit in HumanSize.** The alternative — emit as
  we walk the /1024 loop — would keep `prev` alive across the
  `render_dec_u64` and `render_byte_write` calls, forcing an extra
  callee-save slot. Precomputing gives a clean phase separation:
  loop state stays in caller-save regs, only the final six values
  (anchor, cursor, cap, integer, tenth, letter) live across the
  emit sequence.
- **Overflow sentinel `0xFFFFFFFFFFFFFFFF`.** Chosen so the
  high-bit test alone distinguishes an error return from a byte
  count. Same sentinel Render exports; propagates verbatim through
  HumanSize's nested-call chain via the `mov r11, sentinel; cmp
  rax, r11` idiom (the immediate does not sign-extend from imm32,
  so it stages through r11).
- **HiddenFilter fast path before byte load.** `-a` is common
  enough that skipping the read on that branch measurably reduces
  work across a large directory. The byte load only runs when the
  user asked to hide dotfiles.
- **Runner is still STUB.** M2 primitives land as pure functions
  because the R42 PdxFS-v1 directory-iterator substrate has not
  landed. `runner_ls` continues to return `LS_RUN_STUB` on the
  happy path. M3 wires the primitives into a real readdir loop
  once the substrate arrives. This matches the M1 stance (see
  `src/runner.pdx` §4.2) — the shape of the call chain froze at
  M1; M2 lands the leaves; M3 wires the tree.

## Kernel-side gap (recorded)

The R42 PdxFS-v1 directory-iterator primitives (a userspace
`sys_pdxfs_dir_readnext`-shaped syscall, plus a `sys_pdxfs_open`
that returns a directory-capable `KIND_PDXFS_FILE`) do NOT exist
in the paideia-os kernel at HEAD (2026-08-21). Runner cannot
iterate a real directory without them. This gates the M3 wiring
of the M2 primitives into a live listing. Blocker recorded here
for the M2 wave summary.

## paideia-as conformance

- Every function declared with `justification:` clause including
  rsp-alignment arithmetic and register-plan rationale.
- Byte writes via `mov_b [dst], reg`; byte reads via
  `xor rax; mov_b rax, [ptr]` (#1248 mitigation).
- `cmp reg, imm` always uses `imm <= 0x7FFFFFFF`. Large sentinels
  (`0xFFFFFFFFFFFFFFFF`) stage into r11 before compare.
- SysV push/pop parity preserved in every non-leaf.
- `r11` is scratch and not assumed live across calls.

## Tests

Deferred to M4 (per §5.4 M4 in the plan doc). The following M4
fixtures land against the M2 primitives:

- `human_size_render` known-answer table: 0, 1, 512, 1023, 1024,
  1025, 1536 (1.5K), 1048576 (1.0M), 4194304 (4.0M), 1073741824
  (1.0G), maximum u64.
- `hidden_filter_accept` truth table: null name, empty name, "a",
  ".", ".hidden", "..", "..." with show_hidden = 0 and = 1.
- `render_dec_u64` boundary cases: 0, 1, 9, 10, 99, 100,
  9999999999999999999 (near 2^64).
- `render_byte_write` overflow: dst_cap == 0 refused.
