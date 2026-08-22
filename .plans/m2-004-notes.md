# ls.M2-004 — implementation notes

**Issue:** #7 — coloring driven by declared schema/MIME (not POSIX file-type bits).
**Upstream doc:** `design/tooling/r49-r50-plan.md` §4.4 + §5.4 (paideia-os).

## What landed

- `src/color_picker.pdx` — new `ColorPicker` module:
  - `color_pick(kind_nibble, mode_bits, schema_id) -> palette_id`
    — schema-first dispatch (schema_id != 0 wins), falling back to
    kind_nibble + exec-bit heuristic when no schema is known.
  - `color_sgr_prefix(dst, cap, palette_id) -> bytes | overflow`
    — emits `ESC [ N m` (1- or 2-digit code). Palette 0 emits 0
    bytes so a caller can call unconditionally.
  - `color_sgr_suffix(dst, cap) -> 4 | overflow` — emits `ESC [ 0 m`.

## Palette

Ten slots (0..9). SGR codes in `_cp_sgr_codes`:

  id  role              SGR     ANSI meaning
  0   none              (none)  default
  1   dir               34      blue
  2   symlink           36      cyan
  3   exec-file         32      green
  4   image             35      magenta
  5   video             95      bright magenta
  6   audio             33      yellow
  7   code              92      bright green
  8   doc               94      bright blue
  9   unknown-schema    37      white

## Design decisions

- **Schema-first dispatch (plan doc §4.4 load-bearing rule).**
  When `schema_id != 0`, the schema route wins over the kind-nibble
  route. This is the "coloring driven by declared schema/MIME, not
  POSIX file-type bits" invariant. At M2, non-zero schema_ids
  route to palette 9 (unknown-schema, white) because the schema
  registry (`svc.schema-registry`, libpdx-semantic-pipe M3) is not
  up. M3 replaces the "non-zero -> 9" branch with a real registry
  lookup by BLAKE3 hash; the dispatch shape (schema_id -> palette
  integer) is stable across the swap.
- **Kind-nibble fallback only when schema is absent.** The plan
  doc §4.4 rule prohibits using POSIX file-type bits AS THE
  PRIMARY signal; it does not prohibit them as a fallback when no
  schema is declared. Dir + symlink + exec fallbacks preserve
  something useful for pre-schema entries (which will be common
  during the R42 substrate migration).
- **Small palette + 2-digit SGR max.** Keeps the emit path
  bounded: prefix is always 4 or 5 bytes (`ESC [ N m` or
  `ESC [ N N m`). No need for the general u64->decimal cost
  beyond what render_dec_u64 already gives, and callers can size
  a per-entry color buffer at 5 bytes plus 4 (suffix) = 9 bytes
  worst case.
- **Palette 0 emits 0 bytes.** A caller composing a per-entry
  emit sequence calls `color_sgr_prefix` unconditionally without a
  pre-branch on palette == 0. The prefix returns 0, no dst
  bytes touched, cursor unchanged. The pairing `color_sgr_suffix`
  is skipped by the caller when palette == 0 (or is called with
  the same effect: `dst_cap == 0 || palette == 0` -> no work).
- **`_cp_sgr_codes` slot 0 = 0 sentinel.** Ensures the palette-0
  short-circuit never dereferences the table's real code region.
  Defensive: even if a caller passes palette_id = 0 into
  color_sgr_prefix without the pre-check, the load returns 0
  which is a valid no-color code.
- **Owner-exec bit for the exec fallback.** `mode_bits & 0x40`
  matches the POSIX "owner-execute" bit that historic `ls`
  colorizers use. Not perfect (group/other-exec files render as
  non-exec) but consistent with the muscle memory of every UNIX
  user, and the schema route overrides this anyway when a
  declared exec schema arrives.

## Runner integration

Runner is still STUB pending the R42 directory-iterator kernel
gap. ColorPicker is a pure primitive tested at M4; M3 wires
`color_pick` + `color_sgr_prefix` + `color_sgr_suffix` into
Runner around each entry emit when the substrate lands.

## paideia-as conformance

- Byte reads via `xor rax; mov_b rax, [ptr]` (#1248) for
  `_cp_sgr_codes[palette_id]`.
- Byte writes via `mov_b [dst], reg` through render_byte_write.
- No `test`; every zero-check is `cmp reg, 0`.
- Largest immediate 0x40 (owner-exec bit) or 0x5B ('[').
- Sentinel `0xFFFFFFFFFFFFFFFF` stages into r11.
- SysV push/pop parity: `color_sgr_prefix` = 4 pushes + 8 pad =
  40; entry rsp % 16 == 8; 8+40 = 48; aligned. `color_sgr_suffix`
  = 3 pushes + 16 pad = 40; entry rsp % 16 == 8; 8+40 = 48;
  aligned.

## Tests

Deferred to M4:
- `color_pick` truth table over (kind_nibble, mode_bits, schema_id):
  - schema_id != 0 -> palette 9 (regardless of kind/mode)
  - dir + no schema -> palette 1
  - symlink + no schema -> palette 2
  - file + exec bit + no schema -> palette 3
  - file + no exec + no schema -> palette 0
  - unknown nibble + no schema -> palette 0
- `color_sgr_prefix` byte-for-byte output for each palette
  (`\e[34m`, `\e[36m`, ..., `\e[37m`).
- `color_sgr_prefix` overflow at dst_cap = 0, 3, 4 (should emit 0
  for pal 0; refuse for pal 1 with cap 3; success at cap 4).
- `color_sgr_suffix` always 4 bytes: `\e[0m`.
- `color_sgr_suffix` overflow at dst_cap = 3.

## M2 wave — kernel-side gap summary

`ls` M2 closes with all four rendering primitives shipped as pure
functions. `Runner::runner_ls` remains STUB because the R42
PdxFS-v1 directory-iterator substrate (a userspace
`sys_pdxfs_dir_readnext`-shaped syscall + a `sys_pdxfs_open` that
returns a directory-capable `KIND_PDXFS_FILE`) does not exist in
the paideia-os kernel at HEAD (2026-08-21). Neither does
`KIND_TTY` (mirrored as `LS_KIND_TTY = 0x196` provisionally).

These are the R42 + KIND_TTY substrate rounds. M3 (`PdxFsDirEntry`
semantic record emit + libpdx-audit integration) is blocked on
them.
