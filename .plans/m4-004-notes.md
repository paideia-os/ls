# ls.M4-004 — implementation notes

**Issue:** #14 — `--schema` output validates against libpdx-semantic-
pipe golden.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M4-004 line
500 (paideia-os).

## What landed

- `src/semantic_emit.pdx` — extended:
  - New `sem_emit_wire_compose(kernel_entry_ptr) -> wire_len`.
    Same body as `sem_emit_entry` steps (1) + (2) — copy the
    128-byte kernel record into `_se_wire_scratch`, append the
    16-byte owner Cap wire (KIND_USER at offset 128; placeholder
    user_row 0 at offset 136) — but SKIPS step (3)
    (Send::send_record). Callers get the byte-exact wire body
    in `_se_wire_scratch` without needing a live libpdx-
    semantic-pipe substrate. Two callee-save pushes + `sub rsp,
    8` pad; returns 144 (SE_WIRE_RECORD_SIZE) on success or 0 on
    a defensive kernel_entry_ptr == 0 refusal.
- `tests/schema_golden.pdx` — new `SchemaGolden` module. Two
  goldens:
  - **Case 0: schema-hash imprint.** Call `sem_emit_reset`;
    walk 4 u64 lanes of `_se_pdxfsdirentry_hash` against
    `_sg_hash_golden` (lane 0 = 1, lanes 1..3 = 0 — byte-exact
    the M3-001 first-byte-0x01 stub).
  - **Case 1: 144-byte wire body.** Call
    `sem_emit_wire_compose(&_sg_kernel_input)` (canned entry:
    inode=42, kind=8, name_len=5, name="hello"); assert return
    == 144; walk 18 u64 lanes of `_se_wire_scratch` against
    `_sg_wire_golden`.

## Entry-point contract

```
schema_golden_case_count() -> u64            // 2
schema_golden_run(case_idx) -> u64           // 0 = pass; sentinel = fail
schema_golden_verify_all() -> u64            // fail-fast walk
```

Case-fail sentinels:

  - `SG_ERR_HASH_LEN`     (0xFFFFEBE0)
  - `SG_ERR_HASH`         (0xFFFFEBE1) + lane_idx (0..3)
  - `SG_ERR_WIRE_LEN`     (0xFFFFEBE5)
  - `SG_ERR_WIRE`         (0xFFFFEBE6) + lane_idx (0..17)
  - `SG_ERR_COMPOSE`      (0xFFFFEBEE)
  - `SG_ERR_BAD_CASE_IDX` (0xFFFFEBEF)

## Design decisions

- **`sem_emit_wire_compose` as a new function rather than a
  refactor of `sem_emit_entry`.** Extracting the copy+append into
  a shared helper would change the register plan around
  `sem_emit_entry`'s existing send_record call site; the compose
  loop is small enough that duplicating ~30 instructions
  preserves the M3-001 hot-path shape without churn. Both call
  sites read the same `_se_wire_scratch` .bss — a byte-diff in
  the compose function surfaces as a byte-diff in the send path
  too.
- **Canned kernel entry as u64 lanes, not a byte string.** All
  three fixed fields (inode, kind, name_len) are naturally
  qword; the name "hello" fits in a single qword LE-packed
  (0x0000006F6C6C6568). Twelve trailing zero lanes cover the
  remaining 96 bytes of the 104-byte name array. Total 16 u64
  lanes = 128 bytes — matches the kernel record exactly.
- **Qword-wide compare (not byte-by-byte).** The `.bss`
  `_se_wire_scratch` and `_se_pdxfsdirentry_hash` are 8-aligned,
  as are the goldens (`.rodata` u64 arrays). One qword compare
  per lane — 4 compares for the hash, 18 for the wire body —
  is faster than 32 or 144 byte compares AND makes the fixture
  ~2× shorter. A byte-diff would only be needed if the record
  had non-8-aligned fields; PdxFsDirEntry does not.
- **Schema-golden stays lane 0 = 1 while libpdx-schema-registry
  is unshipped.** When registry.M1 ships (R51+),
  `sem_emit_reset` overwrites `_se_pdxfsdirentry_hash` with a
  real BLAKE3-truncated hash; the golden lane values bump in
  lock-step (a single `.rodata` edit) and the fixture continues
  to pin the imprint invariant. The M4 shape (a fixed 4-lane
  compare) is stable across the swap.
- **Wire body lane 17 = 0 (placeholder user_row).** M3-002's
  `sem_emit_entry` writes 0 for the owner target_ptr because
  PdxFsDirEntry does not yet carry an owner field. When either
  (a) PdxFsDirEntry grows an owner field or (b)
  `sys_pdxfs_stat_by_inode` ships, the placeholder becomes the
  real row id and the wire golden bumps to `<row>` in lane 17.
  The fixture and the SUT change together — a mismatch at M4
  surfaces the drift.

## paideia-as conformance

- `SchemaGolden` PascalCase basename. `SemanticEmit` extended
  with `sem_emit_wire_compose` (already PascalCase-safe).
- No `test` mnemonic. Zero-checks use `cmp reg, 0`.
- `cmp reg, imm` immediates: 144 (wire len), 18 (lane cap for
  wire), 4 (lane cap for hash), 2 (case cap), 128 (kernel copy
  len). All fit imm32. The 0xFFFFEBxx sentinels are `mov rax,
  imm64` stores.
- Byte reads: none in `SchemaGolden` (qword-wide diff);
  `sem_emit_wire_compose` uses the same byte-by-byte copy loop
  as `sem_emit_entry` with `xor rax + mov_b rax, [ptr]` per
  #1248.
- `r11` scratch for LEA + address staging.
- Prologues + alignment: `sem_emit_wire_compose` 2 pushes + pad
  (32, aligned — no nested calls but parity with `sem_emit_entry`);
  `schema_golden_run_hash` + `_run_wire` both 4 pushes + pad
  (48, aligned); `schema_golden_run` 1 push (16, aligned);
  `schema_golden_verify_all` 2 pushes + pad (32, aligned).

## What is NOT in this file

- Live send + recv round-trip. The M4-004 fixture pins the
  compose half; a live-substrate M5 harness will bind an
  endpoint, `sem_emit_entry`, and `Recv::recv_record` against
  the same bound hash to verify the send path adds the 32-byte
  hash prefix. The Recv-side fixture will live in libpdx-
  semantic-pipe's own M4 tree.
- Multi-entry stream (walk N entries through
  `sem_emit_entry`; verify all N records appear on the
  receiver). Deferred to the shell.M4 pipeline correctness
  matrix which needs a live pipeline substrate.
- Cross-version wire-format tolerance (M4 of libpdx-semantic-
  pipe covers the version-tolerance matrix; ls's wire is
  version 0.1 and stays pinned here).
