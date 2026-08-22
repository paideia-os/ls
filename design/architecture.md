# ls — architecture

**Wave:** R50 (Wave 2)
**Repo:** github.com/paideia-os/ls
**Upstream design:** `design/tooling/r49-r50-plan.md` §4.4 and §5.4 in
[paideia-os](https://github.com/paideia-os/paideia-os).

This document describes the internal shape of the `ls` binary. It does
not repeat the wave-level rationale from the paideia-os plan doc; read
that first for D2 (semantic pipes), D3 (audit-first), and I4 (exit-code
vocabulary). `ls` renders directory contents as text and as typed
schema records. Behaviour differs from POSIX `ls` in three ways
established by §4.4 of the plan doc — schema output is first-class,
cap-annotations are visible in `--long`, and colorization is driven by
the file's declared MIME/schema, not by POSIX file-type bits.

## 1. Public surface

`ls` is not a library — it is a binary. Its "surface" from a
programmatic point of view is a small set of module entry points the
`_start` frame (M2+) calls in order:

- `Ls` (`src/ls.pdx`) — top-level orchestration, constants shared
  across the ls binary's modules, the tool-level stats table and
  reset/note/stat helpers.
- `ArgvSurface` (`src/argv_surface.pdx`) — the argv-facing wrapper
  around `libpdx-argv::Parser`. Exposes
  `argv_surface_parse(argv, argc) → u64` which resets and drives
  `Parser::parse_argv`, then walks the resulting `ParsedArgs` to
  recognise the six ls-specific flags (`-l`, `-a`, `-h`, `--json`,
  `--schema`, `--color=…`) into a bit-field, and captures the first
  positional argument as the target path. Rejects unknown flags with
  its own error code so the caller can print a specific diagnostic
  without disturbing libpdx-argv's error taxonomy.
- `Runner` (`src/runner.pdx`) — the operation body: `runner_ls(path_ptr,
  flag_bits) → u64` opens KIND_PDXFS_FILE(read) at the path and prints
  each entry name to KIND_TTY(write), one per line. M1 ships the
  SKELETON: path-argument gating returns `LS_RUN_STUB`; the actual
  directory-iteration + KIND_TTY write lands at M2 once the PdxFS v1
  substrate (r49-r50-plan.md §2.4) and the KIND_TTY substrate (still
  provisional at HEAD 2026-08-21, mirrored as `LS_KIND_TTY = 0x196`)
  are ready to service userspace.
- `Dispatch` (`src/dispatch.pdx`) — the composition: `ls_dispatch(argv,
  argc) → u64` calls `ArgvSurface::argv_surface_parse`, propagates
  the parser's rejection as an exit code, then hands the surface's
  stored path + flag bits to `Runner::runner_ls` and returns its
  code. This is the one entry a M2 `_start` calls; every M1 harness
  test exercises the same wiring.

The `_start` frame (not part of M1 — the loader's entry convention
lands in the paideia-os R14b bootstrap) calls `Dispatch` once:

```
1. Ls::ls_reset()                          // clear stats
2. let rc = Dispatch::ls_dispatch(argv, argc)
3. exit rc
```

At M1 both `Runner::runner_ls` and the underlying KIND_TTY write
return their `_STUB` sentinel so the harness in tests/ can call the
composition without blocking on a live TTY or a live directory read.

## 2. `Ls` module (src/ls.pdx)

### 2.1 Constants

The Ls module owns:

- **KIND ordinal mirrors.** The kernel's KIND ordinals ls talks about
  (`LS_KIND_USER = 0x190`, `LS_KIND_IPC_ENDPOINT = 5`,
  `LS_KIND_PDXFS_FILE = 0x195`, `LS_KIND_TTY = 0x196` provisional).
  Redeclared here for the same reason libpdx-elevate mirrors `ELV_*`
  and the shell mirrors `SH_KIND_*` — this repo is not obligated to
  link paideia-os's kernel .o graph at build time. Drift caught at
  M4 by the smoke matrix; the `LS_` prefix documents the mirror
  invariant.
- **Return-code band `0xFFFFEBxx`.** The ls binary's own error-code
  family, disjoint from libpdx-argv's compact `0..5` (see §5). Sits
  between libpdx-elevate's `0xFFFFEAxx` and the shell's `0xFFFFECxx`
  so the high two bytes of the return tell a downstream consumer
  which layer refused. Full table in §5.
- **Tool-level `.bss` singleton.** An 8-slot stats counter table
  (`_ls_stats`), cache-line aligned, mirrors the shape of
  `Shell::_shell_stats` and libpdx-argv's own singletons — one entry
  per observable event class (dispatches issued, parses OK'd, runs
  attempted, entries printed, errors).

### 2.2 `ls_reset()`

Clears the eight-word `_ls_stats` counter table. Called by `_start`
(M2+) before the run loop and by tests before each fixture. Leaf
function; `r10` as base + `rcx` as loop index. Same shape as
`Shell::shell_reset` (paideia-os/shell `src/shell.pdx`) and
`libpdx-argv::ParsedArgs::reset`.

### 2.3 `ls_note(which)` + `ls_stat(which)`

Bounded increment + bounded read for the counter table. `which >=
LS_ST_MAX` is a no-op (increment) or returns 0 (read) — a caller
passing a slot from a newer library version against an older linker
snapshot cannot corrupt live counters. Same shape as
`Shell::shell_note` / `Shell::shell_stat`.

## 3. `ArgvSurface` module (src/argv_surface.pdx)

### 3.1 Contract

```
argv_surface_reset() -> ()
argv_surface_parse(argv: u64, argc: u64) -> u64
```

`argv_surface_parse` returns one of:

- `AS_OK` (`0xFFFFEB10`) on success. Read the recognised flags from
  `_as_flag_bits`, the target path (or 0 → default `.`) from
  `_as_path_ptr`, and the `--color=` value from `_as_color_value_ptr`.
- `AS_ERR_BAD_ARGV` (`0xFFFFEB11`) if `argv == 0` or `argc == 0`.
- `AS_ERR_PARSER_REJECT` (`0xFFFFEB12`) if `libpdx-argv::Parser::
  parse_argv` returned any non-zero code (clustered short flag,
  overflow, malformed long name — the specifics live in
  `libpdx-argv::ParsedArgs::error_code` for the caller's diagnostic).
- `AS_ERR_UNKNOWN_FLAG` (`0xFFFFEB13`) if a long flag is not in
  ls's recognised set (`json`, `schema`, `color`, `pdx-schema`).
- `AS_ERR_UNSUPPORTED_SHORT` (`0xFFFFEB14`) if a short flag is not
  `l`, `a`, or `h`.

Recognised flag bits (public constants):

| bit | flag             | set by                                              |
|-----|------------------|-----------------------------------------------------|
| 0   | `AS_BIT_L`       | `-l`                                                |
| 1   | `AS_BIT_A`       | `-a`                                                |
| 2   | `AS_BIT_H`       | `-h`                                                |
| 3   | `AS_BIT_JSON`    | `--json`                                            |
| 4   | `AS_BIT_SCHEMA`  | `--schema` (and `--pdx-schema` — see §3.3)          |
| 5   | `AS_BIT_COLOR`   | `--color=<value>`; value ptr in `_as_color_value_ptr` |

### 3.2 Flow

`argv_surface_parse` runs in this order:

1. Bump `LS_ST_INVOKES`.
2. Gate: `argv == 0 || argc == 0` → `AS_ERR_BAD_ARGV`.
3. Call `argv_surface_reset()` (zeroes `_as_flag_bits`,
   `_as_path_ptr`, `_as_color_value_ptr`).
4. Call `libpdx-argv::ParsedArgs::parsed_args_reset()`.
5. Call `libpdx-argv::Parser::parse_argv(argv, argc)`. Any non-zero
   return propagates as `AS_ERR_PARSER_REJECT`.
6. Walk `flag_names[0..flag_count]` — for each entry, discriminate
   short (byte1 == 0) from long (byte1 != 0), then dispatch by
   byte0. On a recognised short set the corresponding bit in
   `_as_flag_bits`; on a recognised long, do a byte-by-byte compare
   against the four accepted names (`json`, `schema`, `color`,
   `pdx-schema`) and set the corresponding bit. `--color=<v>`
   additionally stores `flag_values[i]` in `_as_color_value_ptr`.
7. If `pos_count > 0`, store `pos_ptrs[0]` in `_as_path_ptr`.
   `pos_count == 0` leaves `_as_path_ptr = 0`; the caller reads that
   as "default to `.`". Positionals beyond `[0]` are ignored at M1
   (multi-path listing lands with M4 correctness matrix per §5.4).
8. Bump `LS_ST_OKS`. Return `AS_OK`.

### 3.3 Why `--pdx-schema` maps to `AS_BIT_SCHEMA`

`libpdx-argv` v0.1 hard-recognises `--pdx-schema` in its parser (see
`libpdx-argv/src/parser.pdx`) and sets `ParsedArgs::emit_schema = 1`.
It also stores `pdx-schema` in `flag_names[]` as an ordinary long
flag. Ls treats `--pdx-schema` as an alias for its own `--schema`
flag at M1, setting `AS_BIT_SCHEMA` when it walks the flag_names
entry. This gives every tool one uniform way to ask for a schema
dump — the argv record and the ls tool agree on the semantics
without a tool-side branch on `ParsedArgs::emit_schema`. The
standard 9-flag vocabulary (`--help`, `--version`, `--schema`,
`--json`, `--color=`, `--dry-run`, `--verbose`, `--quiet`,
`--no-cap:<name>`) lands with libpdx-argv M2 per r49-r50-plan.md
§5.12; ls will inherit that centralised recognition at ls.M2 and
retire the local `pdx-schema` alias then.

## 4. `Runner` module (src/runner.pdx)

### 4.1 Contract

```
runner_ls(path_ptr: u64, flag_bits: u64) -> u64
```

- Open a KIND_PDXFS_FILE(read) at `path_ptr` (NUL-terminated), iterate
  its directory entries, and write each entry name to KIND_TTY(write),
  one per line.
- `path_ptr == 0` is treated as "default to `.`". At M1 the STUB
  returns `LS_RUN_STUB` regardless.
- Returns `LS_RUN_STUB` (`0xFFFFEB20`) on the M1 happy path (see
  §4.2). Returns `LS_ERR_BAD_PATH` (`0xFFFFEB21`) if `path_ptr` is
  non-zero but points to an empty string (byte0 == 0 — the M1 gate).

### 4.2 M1 skeleton

M1 ships the wrapper shape, the path-argument gating, and the
counter-bumping so the Ls stats table records every run attempt /
error the way the M2 body will. On the happy path it returns
`LS_RUN_STUB` — the "we validated the args, we would open
KIND_PDXFS_FILE(read) and write the entry names to KIND_TTY(write) if
either substrate existed, but neither does yet" signal.

This mirrors libpdx-elevate's `ELVC_STUB` and shell's `LR_STUB` idiom.
The rationale is the same in three parts:

- **`KIND_PDXFS_FILE` has not landed in paideia-os at HEAD (2026-08-21
  pre-substrate-round).** Even though `kind_pdxfs_file.pdx` exists as
  a mirror-only ordinal at `src/kernel/core/cap/kind_pdxfs_file.pdx`,
  the CoW walker + directory-iterate primitives that back it (per
  r49-r50-plan.md §2.4) still ship at R42.

- **`KIND_TTY` has no ordinal at HEAD** — kind_tty.pdx does not exist;
  the `LS_KIND_TTY = 0x196` mirror in Ls is provisional and pinned at
  the KIND_TTY substrate PR.

- **Manufacturing entry names ls did not actually read would defeat
  D3 audit-first.** A tool that "lists" a directory it never opened
  lies to its own audit journal. The STUB return is the correct
  signal that M1 validated everything up to the substrate boundary
  and stopped before manufacturing bytes.

`runner_ls` bumps `LS_ST_RUNS` on every entry and `LS_ST_ERRORS` on
every reject path so the tool's own stats table records the failure
without needing the caller to touch a journal.

### 4.3 M2 evolution

At M2, `runner_ls`:

1. If `path_ptr == 0`, substitute a pointer to the constant `".\0"`.
2. Call the userspace wrapper for `sys_pdxfs_open(path_ptr, R_READ)`
   which returns a KIND_PDXFS_FILE cap slot number, or an errno.
3. Loop: read one directory entry through
   `sys_pdxfs_dir_readnext(slot, entry_buf, entry_buf_len)`; if the
   result is `PDXFS_DIR_EOF`, break. Otherwise, extract the
   NUL-terminated name field and write it (plus `\n`) to KIND_TTY.
4. Close the KIND_PDXFS_FILE cap and return `LS_OK`.

Steps 1 and 2 are single-line replacements of the M1 stub tail. The
loop and the KIND_TTY write are the whole M2 body — the shape of the
call chain is what M1 pins.

## 5. `Dispatch` module (src/dispatch.pdx)

### 5.1 Contract

```
ls_dispatch(argv: u64, argc: u64) -> u64
```

Composition of `ArgvSurface::argv_surface_parse` and
`Runner::runner_ls`:

1. Call `argv_surface_parse(argv, argc)`. If it returns anything but
   `AS_OK`, return that code verbatim to the caller (the caller's
   `_start` at M2 collapses these into I4 exit codes per §5 below).
2. Load `_as_path_ptr` and `_as_flag_bits` from ArgvSurface's .bss.
3. Call `runner_ls(_as_path_ptr, _as_flag_bits)` and return its
   code.

At M1 the composition always ends with `LS_RUN_STUB` on any well-
formed argv. Any malformed argv exits with the appropriate
`AS_ERR_*`.

## 6. Return-code band `0xFFFFEBxx`

```
0xFFFFEB00  LS_OK                    general success sentinel (unused at M1 body)
0xFFFFEB10  AS_OK                    ArgvSurface: parse OK
0xFFFFEB11  AS_ERR_BAD_ARGV          ArgvSurface: argv == 0 or argc == 0
0xFFFFEB12  AS_ERR_PARSER_REJECT     ArgvSurface: libpdx-argv rejected argv
0xFFFFEB13  AS_ERR_UNKNOWN_FLAG      ArgvSurface: long flag not in ls's set
0xFFFFEB14  AS_ERR_UNSUPPORTED_SHORT ArgvSurface: short flag not l/a/h
0xFFFFEB20  LS_RUN_STUB              Runner.M1: validated, no live iterate yet
0xFFFFEB21  LS_ERR_BAD_PATH          Runner: path ptr non-zero but empty string
```

Collapsed to I4 exit codes at M2 by the `_start` frame:

- `AS_OK` and `LS_OK` and `LS_RUN_STUB` → 0 (success)
- `AS_ERR_BAD_ARGV`, `AS_ERR_PARSER_REJECT`,
  `AS_ERR_UNKNOWN_FLAG`, `AS_ERR_UNSUPPORTED_SHORT`,
  `LS_ERR_BAD_PATH` → 2 (usage error)
- KIND_PDXFS_FILE cap denied at M2 → 4 (cap denied)
- Any unexpected `0xFFFFEBxx` → 3 (system error)

The band sits between libpdx-elevate's `0xFFFFEAxx` and the shell's
`0xFFFFECxx` so a downstream consumer can identify the refusing
layer from the high two bytes alone. Cross-repo:

- `0xFFFFFFxx` — libpdx-cap
- `0xFFFFEAxx` — libpdx-elevate
- `0xFFFFEBxx` — ls  (this repo)
- `0xFFFFECxx` — shell
- `0xFFFFEDxx` — kernel KIND failure bands (KIND_USER: EDxx range;
  KIND_PDXFS_FILE: ECxx — overlaps shell's userspace band because
  they travel through different channels)

## 7. paideia-as conformance

Every function in ls src/ obeys the constraints established across
the R49 wave (see `libpdx-argv/design/architecture.md` §5 for the
same list applied to the argv library):

- Module names PascalCase basename (`Ls`, `ArgvSurface`, `Runner`,
  `Dispatch`); no directory prefix.
- No `test` mnemonic; every zero-check uses `cmp reg, 0`.
- Every `cmp reg, imm` uses `imm ≤ 0x7FFFFFFF`. The M1 compares are
  against small immediates only (`cmp rcx, 0`, `cmp rax, 0x2D`,
  `cmp rax, 0x7F`, `cmp rcx, 8`, `cmp r14, flag_count`). The
  0xFFFFEBxx return sentinels are `mov rax, imm64` emissions, not
  compares.
- Byte reads always preceded by `xor rax, rax; mov_b rax, [ptr]`
  (#1248 mitigation).
- SysV push/pop parity preserved in every non-leaf function. See
  each function's `justification:` clause for the specific stack
  arithmetic (padding sub/add so rsp % 16 == 0 at every nested call
  site).

## 8. Testing

Tests land at M4 (per §5.4 M4 in the plan doc). M1 ships
`tests/README.md` as a placeholder describing the fixture matrix M4
will populate:

- Coloring correctness against a known-schema fixture corpus
  (`ls.M4-001`).
- Owner-render correctness for multi-user quota-share subtrees
  (`ls.M4-002`).
- Exit-code matrix: empty=0, missing=2, cap-denied=4 (`ls.M4-003`).
- `ls --schema` output validates against libpdx-semantic-pipe
  golden (`ls.M4-004`).

The M1 first-runnable example (a caller passes a hardcoded argv
through `Dispatch::ls_dispatch` and observes `AS_OK` followed by
`LS_RUN_STUB`) is a harness-only exercise — no automated fixture at
M1. The first live invocation happens once the shell wires exec at
`shell.M2` and the PdxFS v1 substrate at r49-r50-plan.md §2.4 lands.

## 9. What M1 is deliberately NOT

- No `_start` frame. The loader convention that binds argv/envp/
  InitCap lands with the paideia-os R14b bootstrap; ls's `_start`
  lands at M2 alongside the sys_pdxfs_open wrapper.
- No `-l` long-format rendering, no `-a` hidden-file toggle, no
  `-h` human-readable size — those bit flags are set by the argv
  parse but their runtime behaviour lands at M2-001 through M2-003.
- No color output. Bit set at M1; palette + schema-driven dispatch
  land at M2-004.
- No `PdxFsDirEntry[]` emission on stdout. The schema is declared in
  `caps.decl`; the wire binding lands at M3-001.
- No audit-first `DirListRecord`. Journalling lands at M3-003 once
  libpdx-audit reaches M2.
- No test corpus. Fixtures land at M4-001 through M4-004.
- No signed release. Signature + `.pdxdoc` + mirror push land at M5.
