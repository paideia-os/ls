# ls.M3-001 -- implementation notes

**Issue:** #8 -- `PdxFsDirEntry[]` schema bind + emit on stdout.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M3-001 (paideia-os).

## What landed

- `src/pdxfs_shim.pdx` -- new `PdxfsShim` module (userspace syscall
  trampolines):
  - `pdxfs_open_dir(parent_slot, mode_flags)` -- sysno 71
    (architectural symmetry; Runner does not call this at M3 --
    shell.M2 InitCap hands ls a pre-narrowed dir cap per §4.4).
  - `pdxfs_dir_readnext(dir_cap_slot, entry_buf_va)` -- sysno 72
    (the M3 hot path). Returns 1 (entry) / 0 (EOD) / -errno.
- `src/tty_write.pdx` -- new `TtyWrite` module:
  - `tty_write(buf_ptr, len)` -- sysno 1 to `LS_TTY_STDOUT_FD` = 1
    (UART fast-path per paideia-os dispatch.pdx L515). M3 compat
    shim; flips to cap_invoke(KIND_TTY, TTY_OP_WRITE) at R49.M1.
- `src/semantic_emit.pdx` -- new `SemanticEmit` module:
  - `sem_emit_reset()` -- imprint the M3-001 stub schema hash into
    `_se_pdxfsdirentry_hash` (first byte 0x01, remaining 31 zero).
  - `sem_emit_bind_stdout()` -- delegate to libpdx-semantic-pipe's
    `libpdx_semantic_pipe_bind(LS_STDOUT_ENDPOINT_SLOT, &hash)`.
  - `sem_emit_entry(kernel_entry_ptr)` -- copy the 128-byte kernel
    record into `_se_wire_scratch` and delegate to libpdx-semantic-
    pipe's `send_record(fd, ptr, len)`.
- `src/runner.pdx` -- Runner FLIPS from `LS_RUN_STUB` to the real
  iteration body:
  - Bumps `LS_ST_RUNS` on entry.
  - Runs `sem_emit_reset` + `sem_emit_bind_stdout` before the loop.
  - Loop: `pdxfs_dir_readnext(LS_DIR_CAP_SLOT, &_rn_entry_buf)` ->
    on entry, extract name_len (offset 16) + name_ptr (offset 24),
    apply `hidden_filter_accept`, then compose `name + '\n'` into
    `_rn_line_buf` (byte copy with #1248 mitigation), `tty_write`
    it, `sem_emit_entry` the record, bump `LS_ST_ENTRIES`, loop.
  - Bumps `LS_ST_HIDDEN` on `-a`-filtered entries.
  - Returns one of `LS_OK` / `LS_ERR_READDIR` / `LS_ERR_TTY_WRITE`
    / `LS_ERR_EMIT_BIND` / `LS_ERR_EMIT_SEND` (new sub-band codes
    allocated in `Ls`).
- `src/ls.pdx` -- two edits:
  - `LS_KIND_TTY = 0x196` -> `0x197` (real ordinal from paideia-os
    R30-PREP #1631 kind_tty.pdx; retires the M2 provisional value
    that collided with `KIND_PDXFS_TXN`).
  - Return-code band extended with `LS_ERR_READDIR` (0xFFFFEB22),
    `LS_ERR_TTY_WRITE` (0xFFFFEB23), `LS_ERR_EMIT_BIND` (0xFFFFEB24),
    `LS_ERR_EMIT_SEND` (0xFFFFEB25), `LS_ERR_AUDIT` (0xFFFFEB26 --
    reserved for M3-003).

## Cap slot convention (pinned by shell.M2 InitCap)

Runner reads from `LS_DIR_CAP_SLOT = 2` (matches caps.decl order:
slot 0 = KIND_USER, 1 = KIND_TTY, 2 = KIND_PDXFS_FILE, 3 =
KIND_IPC_ENDPOINT). SemanticEmit binds `LS_STDOUT_ENDPOINT_SLOT =
3` for the semantic-pipe emission. At M3 without a live InitCap
handoff, `sys_pdxfs_dir_readnext(2, ...)` returns `-EBADF` and
Runner surfaces `LS_ERR_READDIR` -- the substrate wiring is
correct; live iteration lights up once shell.M2 InitCap populates
the cap_table.

## Wire record shape (M3-001)

M3-001 emits the kernel PdxFsDirEntry (128 bytes) verbatim:

  offset  field      type
  0       inode      u64
  8       kind       u64 (PDXFS_ENT_KIND_*)
  16      name_len   u64
  24      name       u8[104]

M3-002 (#9) extends this to 144 bytes with a 16-byte owner Cap
wire (kind = KIND_USER, target_ptr = user_row) at [128..144] --
the owner-as-cap-ref D2 literal.

## Schema hash (M3-001 stub)

`_se_pdxfsdirentry_hash` = { 0x01, 0x00, 0x00, ... } (32 bytes;
first byte 0x01, remaining 31 zero). The stub passes libpdx-
semantic-pipe's SP_ERR_NULL_HASH gate (binding.pdx §40).  M4
fixtures pin the same stub so wire prefixes round-trip.  Real
BLAKE3-truncated("PdxFsDirEntry@0.1") arrives with libpdx-schema-
registry.M1 (R51+); at that point `sem_emit_reset` fetches from
the registry.

## paideia-as conformance

- PascalCase module basenames (`PdxfsShim`, `TtyWrite`,
  `SemanticEmit`, `Runner`); no directory prefix.
- No `test` mnemonic; every zero-check is `cmp reg, 0`.
- Every `cmp reg, imm` uses `imm <= 0x7FFFFFFF` (largest 128 =
  RN_ENT_SIZE); the 0xFFFFEB2x sentinels are `mov rax, imm64`
  emissions, not compares.
- Byte reads (kernel-entry copy loop + name copy loop) use
  `xor rax, rax; mov_b rax, [ptr]` per #1248.
- `r11` reserved as scratch (LEA + address staging); `r10` used
  as ephemeral byte-address holder in copy loops.
- Runner has a 6-push callee-save prologue (rbx, r12, r13, r14,
  r15, rbp) + `sub rsp, 8` pad = 56 bytes; entry rsp % 16 == 8;
  8 + 56 = 64; 64 % 16 == 0 at every nested-call site. Matched
  `add rsp, 8` + 6 pops through the single `rn_ls_epilogue` label
  before every ret.
- `sem_emit_entry` has a 3-push prologue (r12, r13, r14) = 24
  bytes; entry rsp % 16 == 8; 8 + 24 = 32; aligned.
- `sem_emit_bind_stdout` has a 1-push prologue (r12 for
  alignment) = 8 bytes; entry rsp % 16 == 8; 8 + 8 = 16; aligned.
- Both PdxfsShim and TtyWrite trampolines are LEAF -- no
  callee-save touched.

## What M3-001 is NOT

- Not M3-002 (#9). M3-001 emits 128-byte kernel records; owner
  as cap-ref extension lands with the M3-002 commit.
- Not M3-003 (#10). Audit journalling (`audit_begin` /
  `audit_record_output` / `audit_commit`) lands with the M3-003
  commit -- Runner then calls them at the entry, before first
  record emit, and at the return.
- Not the KIND_TTY(write) cap-invoke wire (paideia-os R49.M1).
  M3-001 uses the fd=1 UART fast-path; the flip is a body-only
  edit of `TtyWrite::tty_write` at the substrate landing.
- Not a real BLAKE3-computed schema hash (libpdx-schema-registry.
  M1 at R51+); M3-001 imprints a first-byte-0x01 stub.
- Not real path resolution. The shell narrows the dir cap at
  exec-time (r49-r50-plan.md §4.4); ls does not walk paths at M3.

## Tests

Deferred to M4:
- `pdxfs_dir_readnext` return-code discrimination (1 / 0 /
  -EBADF / -EFAULT) against a fixture with a live dir cap.
- `sem_emit_entry` byte-perfect record on the wire (M4 fixture
  reads back through libpdx-semantic-pipe::Recv).
- `hidden_filter_accept` filtering of `.` / `..` / `hello.pdx`
  under the M3 stub-set and the `LS_ST_HIDDEN` counter bump.
- Runner exit-code matrix for the M3 substrate errors.
