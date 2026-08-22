# ls.M4-001 — implementation notes

**Issue:** #11 — coloring test against known-schema fixture corpus.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M4-001 line
497 (paideia-os).

## What landed

- `tests/color_fixtures.pdx` — new `ColorFixtures` module. Two
  sub-matrices exercised through a uniform (`case_count`, `run`,
  `verify_all`) entry-point trio:
  - **Dispatch matrix (10 cases).** Every branch of the plan-doc
    §4.4 schema-first / kind-fallback palette dispatch:
    dir(0x4→1), symlink(0xA→2), exec(0x8 mode 0x40→3), non-exec
    file, non-owner-exec file, unknown kind, schema-wins-over-none,
    schema-wins-over-dir, unknown-kind, schema-wins-over-exec.
  - **SGR byte-exact goldens (3 cases).** Palette 0 (empty output),
    palette 1 (`ESC[34m`, 5 bytes), palette 5 (`ESC[95m`, 5 bytes)
    — the latter additionally exercises the suffix (`ESC[0m`, 4
    bytes). Goldens are packed as u64 LE lanes for compact
    `.rodata`; the verifier reads them as bytes via `xor rax +
    mov_b rax, [ptr]` per #1248.

## Entry-point contract

```
color_fixtures_case_count() -> u64            // 13
color_fixtures_run(case_idx) -> u64           // 0 = pass; sub-band sentinel = fail
color_fixtures_verify_all() -> u64            // fail-fast walk
```

Case-fail sentinels:

  - `CF_ERR_DISPATCH_MISMATCH` (0xFFFFEB40) + case_idx (0..9)
  - `CF_ERR_SGR_LEN_MISMATCH`  (0xFFFFEB50) + case_idx (10..12)
  - `CF_ERR_SGR_BYTE_MISMATCH` (0xFFFFEB60) + case_idx (10..12)
  - `CF_ERR_SUFFIX_MISMATCH`   (0xFFFFEB70)
  - `CF_ERR_BAD_CASE_IDX`      (0xFFFFEB7F)

## Design decisions

- **Schema-first coverage.** Cases 6, 7, 9 assert that
  `schema_id != 0` wins over every kind-nibble branch (none, dir,
  exec). This is the plan-doc §4.4 load-bearing invariant. If a
  future ColorPicker upgrade demotes schema to secondary (a
  regression), any of these three cases fails at M4-001 before
  M5 ships.
- **Two-digit SGR coverage.** Every palette in the M2 table uses
  a two-digit SGR code (34, 36, 32, 35, 95, 33, 92, 94, 37). One
  golden under 50 (palette 1 = code 34) and one over 50 (palette
  5 = code 95) proves `render_dec_u64` dispatches both digit-count
  paths correctly. A future third-digit palette (e.g. 256-color
  extensions) would add a new SGR golden.
- **Suffix inline with palette-5 case.** The suffix (`ESC[0m`) is
  a single fixed 4-byte sequence; exercising it once inside
  case 12 (rather than as a separate 13th case) keeps the case
  count small and colocates the suffix diff with a prefix diff.
- **`_cf_sgr_scratch` sized to 16 bytes.** The widest emission is
  5 bytes (2-digit SGR prefix); 16-byte scratch keeps the emit-
  then-diff loop reading naturally aligned qwords with slack
  behind the payload.

## paideia-as conformance

- `ColorFixtures` PascalCase basename.
- No `test` mnemonic. Zero-checks use `cmp reg, 0`.
- `cmp reg, imm` immediates: 13 (case cap), 10 (dispatch cap), 5
  (SGR len), 3 (SGR dispatch), 16 (scratch cap), 32 (row stride).
  All fit imm32. The 0xFFFFEBxx sentinels are `mov rax, imm64`
  stores or add-relative arithmetic.
- Byte reads via `xor rax + mov_b rax, [ptr]` per #1248.
- `r11` scratch for LEA; `r10` for compare staging.
- Prologues + alignment: `color_fixtures_run_dispatch` 3 pushes
  + `sub rsp, 16` pad (48 total, aligned); `color_fixtures_run_sgr`
  5 pushes (40 total, aligned); `color_fixtures_run` 1 push
  (16 total, aligned); `color_fixtures_verify_all` 2 pushes + pad
  (32 total, aligned).

## What is NOT in this file

- Live QEMU render (a terminal actually printing the colors) —
  visual verification is deferred to the shell-side M4 smoke.
- The M3 registry-driven schema branch (palette 4/6/7/8 —
  image / audio / code / doc) — libpdx-semantic-pipe M3 has
  not shipped, so ColorPicker's schema route always returns
  palette 9 (unknown). When M3 lands, ColorFixtures gains new
  cases against real schema hashes without reshaping the entry-
  point contract.
