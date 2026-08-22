# ls — status

**Wave:** R50 (Wave 2)
**Version:** 1.0.0
**Current milestone:** M5 (signed 1.0 release) — CLOSED.
M5-001 landed `manifest.pdxproj` (version bumped 0.4→1.0.0), `CHANGELOG.md`
with the 1.0.0 entry freezing the argv surface + PdxFsDirEntry wire body +
exit-code map + caps.decl at 1.0, `doc/ls.pdxdoc` (man-equivalent per I7
for the `doc ls` back-end), and `design/release-1.0.md` pinning the
`manifest.pdxsig` wire shape KV-record-by-record in the scaffold epoch
(all-zero signature slots → SIG_UNSIGNED_SCAFFOLD verdict per
`design/drivers/blob-policy.md` §1.7 in paideia-os; live re-sign at R32
bumps `created_unix_secs` only). M5-002 landed `design/mirror-push.md`
(mirror tree layout + five-step release-day runbook + four-way byte-
identity invariant across compose/in-tar/mirror-standalone/mirror-in-tar
copies of `manifest.pdxsig` + the ten-step `pkg install ls` end-to-end
path), `tests/pkg_install_e2e.md` (17-row scaffold-epoch/R32-flip matrix
witness), and tagged `v1.0.0` on `main`. Live QEMU smoke is deferred to
pkg-repo M5-002 which reads this repo's matrix row order to compose its
own assertions against a live pkg substrate.

M4 recap: M4-001 landed `tests/color_fixtures.pdx` (10 dispatch + 3 SGR
goldens). M4-002 landed `tests/owner_fixtures.pdx` (7 row + 2
wire-cap cases). M4-003 landed `src/exit_map.pdx` + `tests/
exit_matrix.pdx` (13 cases, the "empty=0/missing=2/cap-denied=4"
line pinned as cases 0/7/8). M4-004 landed
`tests/schema_golden.pdx` with two golden verifiers: the M3-001
schema-hash imprint stub (via `SemanticEmit::sem_emit_reset`) and
the 144-byte wire body (via a new `SemanticEmit::sem_emit_wire
_compose` — the compose-only sibling of `sem_emit_entry` added at
M4-004 so the wire spec is testable without a live libpdx-
semantic-pipe substrate).

## Milestone rollup

| ID              | Title                                                          | State  |
|-----------------|----------------------------------------------------------------|--------|
| M1-001 (#1)     | scaffold + caps.decl                                           | LANDED |
| M1-002 (#2)     | argv surface via libpdx-argv                                   | LANDED |
| M1-003 (#3)     | first runnable: entry-name print to KIND_TTY                   | LANDED |
| M2-001 (#4)     | -l long-format layout (kind, size, mtime, owner)               | LANDED |
| M2-002 (#5)     | owner-column via KIND_USER_ref decode through libpdx-cap       | LANDED |
| M2-003 (#6)     | -a hidden-files toggle + -h human-readable size                | LANDED |
| M2-004 (#7)     | coloring driven by declared schema/MIME (not POSIX bits)       | LANDED |
| M3-001 (#8)     | PdxFsDirEntry[] schema bind + emit on stdout                   | LANDED |
| M3-002 (#9)     | owner field emits as cap ref, not text uid (D2 literal)        | LANDED |
| M3-003 (#10)    | DirListRecord via libpdx-audit before first byte               | LANDED |
| M4-001 (#11)    | coloring test against known-schema fixture corpus              | LANDED |
| M4-002 (#12)    | owner-render correctness for multi-user quota subtree          | LANDED |
| M4-003 (#13)    | exit-code matrix (empty=0, missing=2, cap-denied=4)            | LANDED |
| M4-004 (#14)    | --schema output validates against libpdx-semantic-pipe golden  | LANDED |
| M5-001 (#15)    | dual-signed release + .pdxdoc                                  | LANDED |
| M5-002 (#16)    | mirror push + verify `pkg install ls` works end-to-end         | LANDED |

See `design/tooling/r49-r50-plan.md` §5.4 in paideia-os for the full
milestone breakdown (M1–M5) and cross-repo dependencies.

## Local layout

- `design/architecture.md` — internal spec (four modules, .bss shape,
  return-code band, paideia-as conformance, M2 evolution notes).
- `src/ls.pdx` — `Ls` module (KIND mirrors + error band + stats).
- `src/argv_surface.pdx` — `ArgvSurface` module (flag-bit recogniser
  around `libpdx-argv::Parser`).
- `src/runner.pdx` — `Runner` module (`runner_ls` -- real iteration
  body at M3-001; opens the pre-handed KIND_PDXFS_FILE dir cap,
  loops sys_pdxfs_dir_readnext, writes name+`\n` to KIND_TTY,
  emits one PdxFsDirEntry record per accepted entry. At M3-003
  wraps the whole body in an audit_begin / record_output / commit
  triple).
- `src/dispatch.pdx` — `Dispatch` module (`ls_dispatch` composition
  entry point that wires ArgvSurface into Runner).
- `src/render.pdx` — `Render` module (shared M2 utility:
  `render_dec_u64`, `render_byte_write`). M2-003.
- `src/hidden_filter.pdx` — `HiddenFilter` module (the `-a`
  dot-prefix filter). M2-003.
- `src/human_size.pdx` — `HumanSize` module (the `-h`
  base-2 K/M/G/T/P/E renderer). M2-003.
- `src/owner_col.pdx` — `OwnerCol` module (the `-l` owner
  column: `u:<row>` from a raw row or a KIND_USER wire Cap).
  M2-002. Shim for libpdx-cap.M3-001 (KIND_USER_ref decoder).
- `src/long_format.pdx` — `LongFormat` module (the `-l` line
  renderer: kind, mode, owner, size, mtime, name; composes
  OwnerCol + HumanSize + Render). M2-001.
- `src/color_picker.pdx` — `ColorPicker` module (schema-first
  color palette + ANSI SGR prefix/suffix emit). M2-004.
- `src/pdxfs_shim.pdx` — `PdxfsShim` module (userspace syscall
  trampolines for sysno 71 sys_pdxfs_open + sysno 72
  sys_pdxfs_dir_readnext against the R42-PREP-008 substrate).
  M3-001.
- `src/tty_write.pdx` — `TtyWrite` module (sysno 1 sys_write to
  fd 1 for KIND_TTY text output; M3 compat shim, flips to
  cap_invoke(KIND_TTY, TTY_OP_WRITE) at R49.M1). M3-001.
- `src/semantic_emit.pdx` — `SemanticEmit` module (schema-bound
  PdxFsDirEntry emission on the stdout KIND_IPC_ENDPOINT via
  libpdx-semantic-pipe::Binding + Send). M3-001 (128-byte kernel
  record) + M3-002 (144-byte record: kernel prefix + 16-byte owner
  Cap wire) + M4-004 (`sem_emit_wire_compose` — compose-only
  sibling of `sem_emit_entry` for the schema-golden fixture).
- `src/audit_shim.pdx` — `AuditShim` module (`audit_ls_begin` +
  `audit_ls_commit` wrappers around libpdx-audit's three-call API;
  DirListRecord frame open before any user-visible byte, close in
  the shared Runner epilogue). M3-003.
- `caps.decl` — the four caps ls receives at exec (KIND_USER,
  KIND_TTY, KIND_PDXFS_FILE, KIND_IPC_ENDPOINT).
- `tests/color_fixtures.pdx` — `ColorFixtures` module (M4-001):
  10 dispatch cases + 3 SGR byte-exact goldens for
  `ColorPicker`.
- `tests/owner_fixtures.pdx` — `OwnerFixtures` module (M4-002):
  7 quota-subtree row cases + 2 wire-cap cases for `OwnerCol`.
- `tests/exit_matrix.pdx` — `ExitMatrix` module (M4-003):
  13 cases covering every 0xFFFFEBxx sentinel via `ExitMap`.
- `tests/schema_golden.pdx` — `SchemaGolden` module (M4-004):
  hash-imprint + 144-byte wire-body goldens for `SemanticEmit`.
- `src/exit_map.pdx` — `ExitMap` module (M4-003): pins the ls
  sub-band → I4 exit-code mapping (0 / 2 / 3 / 4). Used by the
  M4-003 fixture and by the eventual R14b `_start` frame.
- `manifest.pdxproj` — paideia-as build manifest at version
  `1.0.0` (M5-001): source list (15 files), test list (4
  fixtures), version-pinned deps, and the `release:` block
  naming `dist/manifest.pdxsig`, the CHANGELOG anchor, the
  `.pdxdoc`, and the mirror target.
- `CHANGELOG.md` — Keep-a-Changelog-style release log (M5-001).
  The `[1.0.0]` entry freezes the 1.0 contract; `[0.1.0]..[0.4.0]`
  roll up M1..M4 close.
- `doc/ls.pdxdoc` — man-equivalent (M5-001) in the `.pdxdoc`
  grammar the doc-repo's PdxdocParser (doc.M1-002) accepts.
  Consumed by `doc ls` per `design/tooling/plan.md` I7 §2.
- `design/release-1.0.md` — release-1.0 specification (M5-001):
  §1 scaffold epoch, §2 `manifest.pdxsig` KV-record-by-record,
  §3 release process, §4 byte-identity invariant with the mirror
  copy, §5 what freezes at 1.0.
- `design/mirror-push.md` — mirror-push runbook + `pkg install
  ls` end-to-end path (M5-002): §1 mirror tree, §2 five-step
  release-day runbook, §3 four-way byte-identity invariant,
  §4 ten-step install path against ls-1.0.0, §5 close criterion
  + deferred live QEMU witness.
- `tests/pkg_install_e2e.md` — 17-row fixture matrix (M5-002):
  one row per observable in the install path; each row records
  the scaffold-epoch expectation and the R32 promotion criterion.
  Bridges to the pkg-repo M5-002 live harness.
- `.plans/` — per-milestone implementation notes.

## Kernel-side substrate (M3 wave)

The R42-PREP-008 substrate landed at paideia-os HEAD (2026-08-21):
sysno 71 `sys_pdxfs_open` mints a KIND_PDXFS_FILE (dir mode) cap
from a KIND_MEMORY parent; sysno 72 `sys_pdxfs_dir_readnext` walks
a per-open cursor over a fixed 3-entry stub set (`.`, `..`,
`hello.pdx`). `KIND_TTY = 0x197` landed at R30-PREP #1631 (mint
gate + rights + row layout; the byte-pump write wire is a
follow-up at R49.M1, so ls.M3-001 writes text through the fd=1
UART fast-path). `Runner::runner_ls` flips to the real iteration
body at M3-001; live emission lights up once shell.M2 InitCap
populates ls's cap_table (LS_DIR_CAP_SLOT = 2 for the pre-narrowed
KIND_PDXFS_FILE(read, `<arg-path>`); LS_STDOUT_ENDPOINT_SLOT = 3
for the KIND_IPC_ENDPOINT stdout sink).
