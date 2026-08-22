# ls.M4-002 — implementation notes

**Issue:** #12 — owner-render correctness for multi-user quota
subtree.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M4-002 line
498 (paideia-os).

## What landed

- `tests/owner_fixtures.pdx` — new `OwnerFixtures` module. Two
  sub-matrices:
  - **Row-render matrix (7 cases).** `owner_col_render_from_row`
    across the row-id range a multi-user quota subtree exhibits
    (0, 1, 7, 42, 1000, 65534, 65535). Every case round-trips
    through the "u:" prefix + `render_dec_u64` digit render;
    byte-diff against a packed u64 golden verifies the render
    produces exactly the expected `"u:<row>"` bytes.
  - **Wire-cap matrix (2 cases).** Two 16-byte wire-form Cap
    fixtures constructed to libpdx-cap's cap_pack shape
    (qword0 = slot(low16) | kind(bits16..31) | rights(bits32..63);
    qword1 = target_ptr):
    - `_of_wire_cap_u42` — KIND_USER (0x190), row 42 → expected
      "u:42" (4 bytes).
    - `_of_wire_cap_tty` — KIND_TTY (0x197) → expected
      OC_ERR_NOT_USER (0xFFFFEB30) refusal.

## Entry-point contract

```
owner_fixtures_case_count() -> u64            // 9
owner_fixtures_run(case_idx) -> u64           // 0 = pass; sentinel = fail
owner_fixtures_verify_all() -> u64            // fail-fast walk
```

Case-fail sentinels (case indices for the wire cases are 7 + 8,
mapping to the harness's flat case space):

  - `OF_ERR_LEN_MISMATCH`     (0xFFFFEB80) + case_idx (0..6)
  - `OF_ERR_BYTE_MISMATCH`    (0xFFFFEB90) + case_idx (0..6)
  - `OF_ERR_WIRE_LEN`         (0xFFFFEBA0) + case_idx (7..8)
  - `OF_ERR_WIRE_BYTE`        (0xFFFFEBB0) + case_idx (7..8)
  - `OF_ERR_WIRE_NOT_REFUSED` (0xFFFFEBC0)
  - `OF_ERR_BAD_CASE_IDX`     (0xFFFFEBCF)

## Design decisions

- **Row corpus spans decimal-digit-count edges.** 0/1/7 exercise
  the val==0 special case and the 1-digit render path. 42 is the
  boundary between 1- and 2-digit renders. 1000 crosses the
  3→4-digit boundary. 65534/65535 are the maximum 16-bit values
  the InitCap sidecar can pack into the low 16 bits of a
  KIND_USER cap's target_ptr — a quota subtree with the maximum
  user count exercises exactly this end of the range.
- **Wire-cap "TTY refusal" as first-class case.** Case 8's
  OC_ERR_NOT_USER assertion pins the M2 shim's "kind check
  precedes extract" discipline. If a future libpdx-cap.M3
  upgrade re-orders the checks, case 8 fails immediately —
  before the shell hands ls a real KIND_TTY cap and observes
  garbage.
- **Expected bytes as packed u64 LE lanes.** The widest expected
  is 7 bytes ("u:65534" / "u:65535"), fitting in a single qword.
  The byte-diff loop extracts each byte via
  `(qword >> (idx * 8)) & 0xFF` using a variable shift (`shl cl,
  ...; shr rax, cl`); one qword per case in `.rodata` rather
  than a per-case byte string keeps the fixture data compact
  and 8-aligned.
- **32-byte render scratch.** The widest render is 7 bytes.
  Sized to 32 (4 u64 lanes) so a corrupt oversized render lands
  as a byte-diff mismatch inside the fixed compare window rather
  than an overflow crash.
- **Same 5-push shape for row / wire runners.** Both
  `owner_fixtures_run_row` and `owner_fixtures_run_wire` use the
  same 5-callee-save-push prologue (rbx, r12, r13, r14, r15) so
  the byte-diff loop body shape is identical across the two —
  simplifies future refactors that share the loop.

## paideia-as conformance

- `OwnerFixtures` PascalCase basename.
- No `test` mnemonic. Zero-checks use `cmp reg, 0`.
- `cmp reg, imm` immediates: 7 (row cap), 9 (total cap), 2 (wire
  dispatch), 32 (scratch cap), 0xFF (byte mask). All fit imm32.
  The OC_ERR_NOT_USER (0xFFFFEB30) sentinel stages via r10; the
  OF_ERR_* sentinels are `mov rax, imm64` stores or ADD-relative
  arithmetic.
- Byte reads via `xor rax + mov_b rax, [ptr]` per #1248 for the
  scratch-side byte-diff; the expected-byte extract is a shift
  (`shr rax, cl`) — no byte load.
- `r11` scratch for LEA + wire-cap address; `r10` for compare
  staging.
- Alignment: `owner_fixtures_run_row` + `_run_wire` both 5 pushes
  (40 total, aligned); `owner_fixtures_run` 1 push (16, aligned);
  `owner_fixtures_verify_all` 2 pushes + pad (32, aligned).

## What is NOT in this file

- Round-trip of `cap_pack -> owner_col_render_from_wire` — the
  fixtures encode the wire bytes directly rather than call
  cap_pack first, so a cap_pack regression does not falsely
  fail an OwnerCol test. libpdx-cap has its own M4 round-trip
  fuzz for cap_pack/cap_unpack symmetry.
- Owner name resolution (rendering "alice" instead of "u:1") —
  the R51+ svc.user-directory service is not up; the "u:<row>"
  render is the M2 contract and stays pinned here.
- Multi-owner test WHERE the shell writes real caps into ls's
  cap_table — that's a shell-side M4 concern.
