# ls.M1-003 — implementation notes

**Issue:** #3 — first runnable: entry-name print to KIND_TTY.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 (paideia-os).

## What landed

- `src/runner.pdx` — `Runner` module:
  - `runner_ls(path_ptr, flag_bits) → u64`. Bumps `LS_ST_RUNS`
    unconditionally, gates on the empty-string case (`path_ptr !=
    0 && path_ptr[0] == 0` → `LS_ERR_BAD_PATH`), and returns
    `LS_RUN_STUB` on the M1 happy path. `flag_bits` is captured
    (r13) but unused at M1 — its inclusion in the signature lets
    the M2 body dispatch `-l`/`-a`/`-h` behaviour without a
    resignature.
- `src/dispatch.pdx` — `Dispatch` module:
  - `ls_dispatch(argv, argc) → u64` — the composition entry point
    a M2 `_start` frame will call. Forwards argv/argc to
    `argv_surface_parse`. On `AS_OK` (staged via r10 because
    0xFFFFEB10 exceeds the sign-extended imm32 window per the
    paideia-as `cmp reg, imm ≤ 0x7FFFFFFF` rule), loads
    `_as_path_ptr` + `_as_flag_bits` from ArgvSurface's .bss and
    calls `runner_ls`. Any argv-parse rejection propagates rax
    verbatim so the caller can collapse the 0xFFFFEBxx family into
    an I4 exit code.
- `.plans/m1-003-notes.md` — this file.
- `STATUS.md` — M1-003 bumped to LANDED; M1 milestone closed.

## Design decisions

- **Runner as a STUB with paideia-as-shaped scaffolding.** Same
  discipline as shell.M1-002's line_reader (`LR_STUB`),
  shell.M1-003's exec (`EX_STUB`), and libpdx-elevate.M1-004's
  elevate_client (`ELVC_STUB`). Rationale (in file header): KIND_
  PDXFS_FILE walker + KIND_TTY have not landed in the paideia-os
  kernel at HEAD (2026-08-21), and manufacturing entry names ls
  never actually read would defeat D3 audit-first (see
  `design/architecture.md` §4). M2 flips one place — the
  `LS_RUN_STUB` tail — to a real `sys_pdxfs_open` + `sys_pdxfs_dir_
  readnext` + `sys_write` loop; every consumer already spells
  `runner_ls` correctly.
- **`flag_bits` in the signature at M1.** Captured (r13) even
  though M1 does not read it. Reason: the M2 body will need it to
  dispatch `-l` (long format), `-a` (hidden), `-h` (human-readable
  sizes), and `--color=`. Including it in the M1 signature makes
  the M2 flip body-only. Same discipline shell.M1 followed with
  `line_reader_read_line`'s `buf_len` — validated at M1, driven
  at M2.
- **`path_ptr == 0` is legal at the Runner interface.** Dispatch
  passes `_as_path_ptr` verbatim, and `_as_path_ptr` is 0 when the
  caller ran `ls` with no positional argument. The M1 stub
  interprets that as "would default to '.'" and short-circuits to
  `LS_RUN_STUB` without dereferencing NULL. The M2 body will
  substitute a pointer to a constant `.\0` string at the same
  point in the function — a single-line replacement.
- **Empty-string reject on non-null path.** `ls "" ` is a caller
  bug — libpdx-argv would classify `""` as a positional, and
  Runner should refuse it before touching the filesystem. The
  M1 byte0 check catches this and returns `LS_ERR_BAD_PATH` with
  an audit-worthy counter bump.
- **Dispatch's r12 push for alignment.** Single `push r12` at
  entry: (a) aligns rsp % 16 → 0 for the two nested call sites
  (`argv_surface_parse`, `runner_ls`), and (b) preserves r12
  across the callees for SysV callee-save discipline even though
  Dispatch does not clobber r12 internally. Same idiom as
  doc.M1-003's `doc_dispatch_from_buf` wrapper
  (paideia-os/doc src/argv_dispatch.pdx L339).
- **Staged AS_OK compare.** 0xFFFFEB10 does not fit in a sign-
  extended imm32 (imm32 0xFFFFEB10 → sign-extends to
  0xFFFFFFFFFFFFEB10, which is not the u64 value we want to
  compare against). Stage via `mov r10, 0xFFFFEB10; cmp rax,
  r10`. Same idiom libpdx-elevate uses for its
  `0xFFFFFFFFFFFFFFFF` sentinel at `elevate_client_lookup_broker`.

## paideia-as conformance

- Module names PascalCase basename (`Runner`, `Dispatch`) with no
  directory prefix.
- No `test` mnemonic anywhere; every zero-check is `cmp reg, 0`.
- Every `cmp reg, imm` uses an immediate ≤ 0x7FFFFFFF. The one
  large-immediate compare (AS_OK) is explicitly staged via r10
  in `Dispatch::ls_dispatch`.
- One byte read in `Runner::runner_ls` (byte0 empty-string check
  on path_ptr); preceded by `xor rax, rax; mov_b rax, [r12]`
  (#1248 mitigation).
- `r11` is scratch for every LEA base; not assumed live across a
  call.
- SysV push/pop parity:
  - `Runner::runner_ls` — two callee-save pushes (r12, r13) +
    `sub rsp, 8` (rsp % 16 → 0 for the `ls_note` call); matching
    `add rsp, 8; pop r13; pop r12` before every ret.
  - `Dispatch::ls_dispatch` — single r12 push (rsp % 16 → 0 for
    the two nested calls); matching `pop r12` before ret.

## Cross-module linkage

- `Runner::runner_ls` calls `ls_note` (from `Ls` in `src/ls.pdx`).
- `Dispatch::ls_dispatch` calls `argv_surface_parse` (from
  `ArgvSurface` in `src/argv_surface.pdx`), `runner_ls` (from
  `Runner` in `src/runner.pdx`), and reads `_as_path_ptr` +
  `_as_flag_bits` (from `ArgvSurface` .bss).
- All resolved by unqualified linker name.

## M1 close

M1's four modules — `Ls`, `ArgvSurface`, `Runner`, `Dispatch` —
are all present, paideia-as conformant, and wired end-to-end. A
harness that calls `Dispatch::ls_dispatch(argv, argc)` with:

- A well-formed `ls .` argv → parses OK, sets AS_OK, calls Runner
  with path_ptr = pointer-to-"." (from pos_ptrs[0]), returns
  LS_RUN_STUB.
- `ls` with no positional → parses OK, sets AS_OK, calls Runner
  with path_ptr = 0 (default '.'), returns LS_RUN_STUB.
- `ls --json .` → sets AS_BIT_JSON + captures path, LS_RUN_STUB.
- `ls -l -a -h /home/alice` → sets AS_BIT_L|A|H + captures path,
  LS_RUN_STUB.
- `ls --pdx-schema .` → sets AS_BIT_SCHEMA (alias) + captures
  path, LS_RUN_STUB.
- `ls --unknown-flag .` → AS_ERR_UNKNOWN_FLAG.
- `ls -x .` → AS_ERR_UNSUPPORTED_SHORT.
- `ls -la .` (clustered) → AS_ERR_PARSER_REJECT (libpdx-argv's
  `ERR_CLUSTERED_SHORT`).
- `ls (empty argv)` → AS_ERR_BAD_ARGV.
- `ls ""` → LS_ERR_BAD_PATH.

M1 milestone CLOSED. Ready for M2 (core implementation: `-l`
long-format rendering, `-a` hidden-file toggle, `-h` human-readable
size, coloring driven by declared schema/MIME).

## What did not land (queued for M2 and beyond)

- Real `sys_pdxfs_open` / `sys_pdxfs_dir_readnext` / `sys_write`
  wrappers — ls.M2 (and depends on the R42 substrate landing per
  r49-r50-plan.md §2.4).
- `-l` long-format rendering (kind, size, mtime, owner) —
  ls.M2-001.
- Owner column via `KIND_USER_ref` decode through libpdx-cap —
  ls.M2-002.
- `-a` hidden-files toggle + `-h` human-readable size — ls.M2-003.
- Coloring driven by declared schema/MIME (not POSIX file-type
  bits) — ls.M2-004.
- `PdxFsDirEntry[]` schema bind + emit on stdout — ls.M3-001.
- Owner field emits as cap ref (not text uid) — ls.M3-002.
- `DirListRecord` via libpdx-audit before first byte — ls.M3-003.
- Test corpus + exit-code matrix + smoke — ls.M4-001 through
  ls.M4-004.
- Dual-signed release + `.pdxdoc` + mirror push + `pkg install ls`
  end-to-end — ls.M5.
