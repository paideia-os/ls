# ls — status

**Wave:** R50 (Wave 2)
**Current milestone:** M4 (tests + smoke matrix) — IN PROGRESS.
M4-001 landed `tests/color_fixtures.pdx` with 10 palette-dispatch
cases covering every branch of the plan-doc §4.4 schema-first /
kind-fallback table plus 3 byte-exact SGR goldens for the ANSI
prefix / suffix emitters. Fixture entry-point contract
(`<name>_case_count`, `<name>_run`, `<name>_verify_all`) is pinned
for the remaining M4 modules to inherit. M4-002 through M4-004
follow.

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
  Cap wire).
- `src/audit_shim.pdx` — `AuditShim` module (`audit_ls_begin` +
  `audit_ls_commit` wrappers around libpdx-audit's three-call API;
  DirListRecord frame open before any user-visible byte, close in
  the shared Runner epilogue). M3-003.
- `caps.decl` — the four caps ls receives at exec (KIND_USER,
  KIND_TTY, KIND_PDXFS_FILE, KIND_IPC_ENDPOINT).
- `tests/color_fixtures.pdx` — `ColorFixtures` module (M4-001):
  10 dispatch cases + 3 SGR byte-exact goldens for
  `ColorPicker`.
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
