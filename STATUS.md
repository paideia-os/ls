# ls — status

**Wave:** R50 (Wave 2)
**Current milestone:** M2 (core implementation) — CLOSED. All four
rendering primitives (`-l` long-format, `-a` hidden filter, `-h`
human size, schema/MIME color) ship as pure functions ready for
M3 to compose with the readdir loop. Ready for M3 (semantic-pipe
`PdxFsDirEntry[]` emission + libpdx-audit integration) once the
R42 PdxFS-v1 directory-iterator substrate lands (see kernel-side
gap below).

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

See `design/tooling/r49-r50-plan.md` §5.4 in paideia-os for the full
milestone breakdown (M1–M5) and cross-repo dependencies.

## Local layout

- `design/architecture.md` — internal spec (four modules, .bss shape,
  return-code band, paideia-as conformance, M2 evolution notes).
- `src/ls.pdx` — `Ls` module (KIND mirrors + error band + stats).
- `src/argv_surface.pdx` — `ArgvSurface` module (flag-bit recogniser
  around `libpdx-argv::Parser`).
- `src/runner.pdx` — `Runner` module (`runner_ls` skeleton — validates
  path, returns `LS_RUN_STUB` until the KIND_PDXFS_FILE + KIND_TTY
  substrates land).
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
- `caps.decl` — the four caps ls receives at exec (KIND_USER,
  KIND_TTY, KIND_PDXFS_FILE, KIND_IPC_ENDPOINT).
- `tests/` — empty until `ls.M4-001` lands the fixture matrix.
- `.plans/` — per-milestone implementation notes.

## Kernel-side gap (M2 wave)

The R42 PdxFS-v1 directory-iterator primitives (a userspace
`sys_pdxfs_dir_readnext`-shaped syscall + a `sys_pdxfs_open` that
returns a directory-capable `KIND_PDXFS_FILE`) do NOT exist in
the paideia-os kernel at HEAD (2026-08-21). `Runner::runner_ls`
therefore stays STUB across M2; the M2 rendering primitives are
pure functions ready for M3 to compose with a real readdir loop
once the substrate lands.
