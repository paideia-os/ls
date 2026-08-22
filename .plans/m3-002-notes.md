# ls.M3-002 -- implementation notes

**Issue:** #9 -- owner field emits as cap ref, not text uid (D2
literal).
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M3-002 line
495 and §4.4 (`owner:KIND_USER_ref, not a uid integer`).

## What landed

- `src/semantic_emit.pdx` -- extended the emitted wire record from
  128 to 144 bytes:
  - New constants: `SE_OWNER_KIND_USER = 0x190`,
    `SE_OFF_OWNER_KIND = 128`, `SE_OFF_OWNER_TARGET = 136`.
  - `SE_WIRE_RECORD_SIZE = 128` -> `144`.
  - `sem_emit_entry` inserts two qword stores between the copy loop
    and the `send_record` call:
      - `scratch[128..136]` = 0x190 (KIND_USER)
      - `scratch[136..144]` = 0    (placeholder user_row)
  - `send_record` rec_len constant flips 128 -> 144.
  - File header block "Wire record shape (M3-001)" -> "Wire record
    shape (M3-002)", updated with the two-lane owner Cap wire layout
    and the placeholder-vs-live user_row upgrade path.
- `STATUS.md` -- M3-002 row LANDED; current-milestone paragraph
  reflects the D2 literal shape.

## Owner user_row placeholder rationale

At M3-002 the kernel PdxFsDirEntry does not carry an owner field
(the R42-PREP-008 substrate's `pdxfs_dir_iter.pdx` §1 fixes the 128-
byte record shape at inode/kind/name_len/name). The M3-002 upgrade
therefore imprints the D2 literal SHAPE (owner as a Cap wire, not a
text uid) with `owner_target_ptr = 0` as the placeholder user_row.

The concretisation lands in a follow-up round: either
  (a) PdxFsDirEntry grows an owner_ref field (kernel change), or
  (b) sys_pdxfs_stat_by_inode ships (a follow-up syscall the tool
      calls per entry to fetch owner_row from the inode).

Both upgrades are a one-line edit at this file: add an `owner_row`
argument to `sem_emit_entry`, plumb from Runner, and replace the
`xor rax, rax` at `SE_OFF_OWNER_TARGET` with `mov rax, r12` (or the
argument register). The `_se_wire_scratch` .bss was sized 18 lanes
at M3-001 anticipating this upgrade, so no reshape is needed.

## Schema decoder compatibility

Bytes [0..128] are byte-for-byte identical to the M3-001 record --
the M3-002 upgrade only APPENDS. A decoder reading an M3-002 wire
with an M3-001 schema pin (128-byte expectation) still sees a valid
prefix and stops at byte 128 without misreading the appended owner
lane as PdxFsDirEntry fields. This matches the version-tolerance
rules libpdx-semantic-pipe.M3-002 will enforce at the library layer
(per r49-r50-plan.md §5 line 735).

## paideia-as conformance

- Two new qword stores use `mov [r11], rax` (no #1248 concern --
  these are stores, not loads).
- `mov rax, 0x190` fits imm32 sign-extended (0x190 = 400).
- No new `cmp reg, imm > 0x7FFFFFFF`; no new `test` mnemonic.
- Alignment of `sem_emit_entry` unchanged: three callee-save pushes
  + entry rsp % 16 == 8 -> 32 bytes total -> rsp % 16 == 0 at the
  `send_record` call site.
- New immediates (128, 136, 0x190) all fit imm32.
- No new .bss (sized 18 lanes = 144 bytes at M3-001).
