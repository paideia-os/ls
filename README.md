# ls

paideia-os directory listing — writes entry names to the terminal, resolves a
relative argument against the live kernel cwd, and, under `-R`, recurses into
subdirectories.

## v1.1-A/B real body (current, `manifest.pdxproj` `version = 1.1-C`)

The cap-based architecture described lower in this file (`KIND_PDXFS_FILE`
handed at exec, `sys_pdxfs_dir_readnext`, `SemanticEmit`'s per-entry
`PdxFsDirEntry@0.1` wire) was the M1–M4/1.0–1.1.10 design. It never actually
enumerated a real directory end-to-end: the shell's `InitCap` handoff never
populated the pre-narrowed cap slot the readnext trampoline needed, so every
invocation returned `LS_ERR_READDIR`. v1.1-A (commit `5b8b3ff`) retired that
STUB body and replaced it with a real, path-addressed one; v1.1-B (this
release) widens it further. The sections below marked **(retired)** describe
the pre-rewrite architecture and stay for historical/schema reference
(`SemanticEmit`'s 144-byte wire body is unchanged code, just not on the live
call path); everything else in this section is what `ls` actually does today.

### Synopsis

```
ls [-R] [<path>]
ls                       # <path> defaults to "."
```

`<path>` is resolved against the kernel's live cwd (`sys_getcwd`, sysno 86)
before use: a relative path becomes `cwd + '/' + path`; an absolute path
(leading `/`) and the bare default `.` both resolve to the cwd itself, or pass
through unchanged. `-R` recurses into every subdirectory found (depth-capped
at 32), printing a `<path>/<name>:` header ahead of each nested listing.
The `-l`/`-a`/`-h`/`--json`/`--schema`/`--color=` flags described below are
still recognised by `ArgvSurface` (so a caller passing them does not get
`AS_ERR_UNKNOWN_FLAG`) but are READ-PAST by the real v1.1-A/B body — see
`src/runner.pdx`'s own §SCOPE note for the full list of what re-engages in a
later round. Positionals beyond `[0]` are handled by `Dispatch`'s own
per-positional loop (`ls a b c`), independent of this file's `-R` recursion.

### Description

`ls` reaches the filesystem through the path-addressed POSIX-compatibility
primitives `sys_stat` (77, an existence check), `sys_open` (2), a
`sys_getdents` (78) batch loop, and `sys_close` (3) — no capability is minted
or consumed for the primary listing at all. Each accepted entry's name plus
`\n` is written to fd 1 via the UART fast-path (`TtyWrite::tty_write`, sysno
1). On success, once per top-level invocation, `ls` also sends one 128-byte
`LsListRecord@0.1` summary record (`entry_count`, `path_hash`,
`filter_flags`) directly into the kernel's semantic-pipe producer ring via
`sys_semantic_send` (sysno 115) — see `src/pipe_emit.pdx`. This is a
different, simpler wire than the per-entry `PdxFsDirEntry@0.1` mechanism
described below, which remains shipped code but is not on the live call path.

The semantic-pipe emission is the point of the tool. Downstream consumers filter
and plot by field name rather than by column-slicing text, and two paideia-os
literals show up directly in the record: the owner field is a `KIND_USER`
capability reference, not a text uid (there is no `/etc/passwd` to resolve), and
coloring is chosen from the entry's declared schema/MIME rather than from POSIX
file-type bits. The text layer renders an owner as `u:<row>` — the row index in
the founder-provisioned user table — precisely so a text-layer reader can tell
"owner: row N" from "size: N".

Before the first user-visible byte reaches either sink, `Runner` opens a
`DirListRecord` audit frame through `libpdx-audit` and commits it in the shared
epilogue with the tool's exit code (invariant I5, audit-first). If the audit
broker is unavailable, `ls` exits 3 having emitted nothing. Capabilities:
`KIND_USER`, `KIND_TTY(write)`, `KIND_PDXFS_FILE(read, <arg-path>)`,
`KIND_IPC_ENDPOINT` — see [Capabilities](#capabilities).

At 1.0 the read loop honours `-a` directly; `-l`, `-h` and `--color=` are parsed
into flag bits and their renderers ship as tested primitives (`LongFormat`,
`HumanSize`, `OwnerCol`, `ColorPicker`) that the loop does not yet call, and
`--json` / `--schema` set their bits without a consumer in this repo. The
[Options](#options) table marks each row. This is deliberate: the argv surface,
the exit-code map, and the 144-byte wire body are frozen at 1.0, so wiring a
renderer into the loop later is additive and needs no re-sign.

## Options (argv-surface recognition; body wiring status noted per flag)

Flags are recognised by `ArgvSurface::argv_surface_parse` (`src/argv_surface.pdx`)
over `libpdx-argv::Parser`, and OR'd into a bit-field. A short
flag that is not `l`/`a`/`h`/`t`/`S`/`r`/`R`/`1`/`C`/`F` returns
`AS_ERR_UNSUPPORTED_SHORT`; a long flag outside the recognised set returns
`AS_ERR_UNKNOWN_FLAG`. Both are exit 2. Clustered short flags (`-la`) are
rejected upstream by `parse_argv` and surface as `AS_ERR_PARSER_REJECT`, also
exit 2 — write `-l -a`. **`-R` is the one flag the real v1.1-A/B `Runner` body
actually consumes** (real recursive descent, depth-capped at 32 — see this
file's own top section); every other row below reflects the pre-rewrite
**(retired)** cap-based body's intended wiring, not what the current
`Runner::runner_ls` executes.

### Listing

| Flag | Bit | Default | Description | 1.0 status |
|------|-----|---------|-------------|------------|
| `-l` | `AS_BIT_L` (0x1) | off | Long format: `kind mode owner size mtime name`, single-space separated. `kind` is one letter from the PdxFS-v1 type nibble (`d` dir, `-` file, `l` symlink, `s` special, `?` unknown); `mode` is three raw octal digits from `mode_bits[8:0]`; `owner` is `u:<row>`; `mtime` renders as `ns:<decimal>` until `pdx-time` ships. | parsed; `LongFormat::long_format_line` shipped, not called by the read loop |
| `-a` | `AS_BIT_A` (0x2) | off | Include dot-prefix entries. `.` and `..` are ordinary dot-prefix names and follow the same rule. | live in the read loop (`HiddenFilter::hidden_filter_accept`) |
| `-h` | `AS_BIT_H` (0x4) | off | Render the `-l` size column as base-2 units: `<1024` raw digits, otherwise `N.dK` / `M` / `G` / `T` / `P` / `E`. | parsed; `HumanSize::human_size_render` shipped, consumed by `long_format_line` |

### Output mode

| Flag | Arg | Bit | Default | Description | 1.0 status |
|------|-----|-----|---------|-------------|------------|
| `--json` | — | `AS_BIT_JSON` (0x8) | off | Request one JSON object per row on stdout. | bit set; no consumer in this repo at 1.0 |
| `--schema` | — | `AS_BIT_SCHEMA` (0x10) | off | Request a dump of the declared output schemas (`PdxFsDirEntry@0.1`). | bit set; no consumer in this repo at 1.0 |
| `--pdx-schema` | — | `AS_BIT_SCHEMA` (0x10) | off | Alias of `--schema`, kept because `libpdx-argv` hard-recognises the spelling. | same as `--schema` |
| `--color=<v>` | `<v>` string | `AS_BIT_COLOR` (0x20) | off | Colorize by the entry's declared schema/MIME, not by file-type bits. The value pointer is captured to `_as_color_value_ptr` verbatim; `0` there means `--color` was given with no value. | bit + value captured; `ColorPicker` palette and SGR emitters shipped, not called by the read loop |

`ColorPicker`'s palette (`color_pick` → SGR code): 0 none, 1 dir `34`, 2 symlink
`36`, 3 exec `32`, 4 image `35`, 5 video `95`, 6 audio `33`, 7 code `92`,
8 doc `94`, 9 unknown-schema `37`. A non-zero `schema_id` routes to palette 9
until the schema registry lands; only then does the kind/mode fallback retire.

## Semantic pipe output (`PdxFsDirEntry@0.1`, retired call path)

`SemanticEmit`'s per-entry wire below is shipped code, byte-pinned by
`tests/schema_golden.pdx`, but is NOT called by the live v1.1-A/B `Runner`
body — the real `LsListRecord@0.1` summary wire (`src/pipe_emit.pdx`, one
record per top-level invocation, sent via raw `sys_semantic_send`) is
described in this file's own top section instead.

**Schema:** `PdxFsDirEntry@0.1` (declared in `caps.decl` under
`declares_output_schemas`). **Body:** 144 bytes, composed by
`SemanticEmit::sem_emit_entry` and sent via `libpdx-semantic-pipe::Send::send_record`
on the endpoint bound at slot 3. `send_record` prepends its own 32-byte
schema-hash prefix; the 144 bytes below are what `ls` itself composes, and are
pinned byte-exact by `tests/schema_golden.pdx`.

| Offset | Field | Type | Source | Notes |
|--------|-------|------|--------|-------|
| 0 | `inode` | `u64` | kernel record | copied verbatim from `sys_pdxfs_dir_readnext` |
| 8 | `kind` | `u64` | kernel record | PdxFS-v1 entry kind |
| 16 | `name_len` | `u64` | kernel record | clamped to 104 by `Runner` before the text write |
| 24 | `name` | `[u8; 104]` | kernel record | entry name bytes; no escaping at 1.0 |
| 128 | `owner_kind` | `u64` | `ls` | always `KIND_USER` = `0x190` |
| 136 | `owner_target_ptr` | `u64` | `ls` | `user_row` from `OwnerCol::owner_col_owner_row_from_entry`; `0` today (honest gap -- `PdxFsDirEntry` carries no owner field) until `sys_pdxfs_stat_by_inode` ships (ls.ENH-008, #28) |

Bytes `[0..128)` are the M3-001 record unchanged, so a decoder pinned to the
128-byte shape still reads a valid prefix of a 144-byte record. Field additions
follow the `libpdx-semantic-pipe` version-tolerance rules and are additive on the
1.x line; changing the meaning of an existing field is a 2.0.

## Exit codes

`src/exit_map.pdx` folds the internal `0xFFFFEBxx` band into the I4 vocabulary.
An unclassified code routes to 3, never to 0. `Dispatch::ls_dispatch` — this
repo ships no `_start` frame, so `ls_dispatch` is `manifest.pdxproj`'s
`entry` — calls `exit_map` on its way out (`ls.ENH-004`, #18), so every
caller of `ls_dispatch` sees 0/2/3/4, never a raw `0xFFFFEBxx` sentinel.

| Code | Meaning | Internal sentinels |
|------|---------|--------------------|
| `0` | Success, including an empty directory | `LS_OK` `0xFFFFEB00`, `AS_OK` `0xFFFFEB10`, `LS_RUN_STUB` `0xFFFFEB20` |
| `2` | Usage error — invoker fixable | `AS_ERR_BAD_ARGV` `..11`, `AS_ERR_PARSER_REJECT` `..12`, `AS_ERR_UNKNOWN_FLAG` `..13`, `AS_ERR_UNSUPPORTED_SHORT` `..14`, `LS_ERR_BAD_PATH` `..21` |
| `3` | System / substrate error — library or broker failure | `LS_ERR_EMIT_BIND` `..24`, `LS_ERR_EMIT_SEND` `..25`, `LS_ERR_AUDIT` `..26`, plus any unrecognised code |
| `4` | Capability denied | `LS_ERR_READDIR` `..22` (includes `-EBADF` when the cap slot was never populated), `LS_ERR_TTY_WRITE` `..23` |

The three rows `tests/exit_matrix.pdx` pins as invariant: empty directory = 0,
missing/ill-formed path = 2, cap-denied = 4.

## Capabilities

`caps.decl`, verbatim — the shell validates this manifest at exec and hands `ls`
exactly these four, no more:

```
requires:
  - KIND_USER
  - KIND_TTY(write)
  - KIND_PDXFS_FILE(read, <arg-path>)
  - KIND_IPC_ENDPOINT

declares_output_schemas:
  - PdxFsDirEntry@0.1
```

`<arg-path>` is a template: the shell's `cap_manifest_verify` binds the concrete
argument path when it narrows the cap. Missing caps → exit 4; extra caps are
refused shell-side before `ls` runs. Effect/capability signatures on the path
from entry point to sinks:

```
Dispatch::ls_dispatch            : (u64, u64) -> u64  !{mem}          @{}
ArgvSurface::argv_surface_parse  : (u64, u64) -> u64  !{mem}          @{}
Runner::runner_ls                : (u64, u64) -> u64  !{mem, sysreg}  @{cap}
PdxfsShim::pdxfs_dir_readnext    : (u64, u64) -> u64  !{mem, sysreg}  @{cap}
TtyWrite::tty_write              : (u64, u64) -> u64  !{mem, sysreg}  @{}
SemanticEmit::sem_emit_entry     : (u64)      -> u64  !{mem, sysreg}  @{cap}
AuditShim::audit_ls_begin        : (u64, u64) -> u64  !{mem, sysreg}  @{cap}
ExitMap::exit_map                : (u64)      -> u64  !{}             @{}
```

## Examples

List the working directory — one name per line, dot-prefix entries dropped:

```
$ ls
argv_surface.pdx
runner.pdx
semantic_emit.pdx
```

List a given path. The shell narrows the `KIND_PDXFS_FILE` cap to exactly this
path before `ls` starts:

```
$ ls /bin
cat
doc
ls
```

Include dot-prefix entries. Note the separate short flags — `-l -a`, not `-la`:

```
$ ls -l -a /etc
```

Long format with base-2 sizes. This is the layout `LongFormat::long_format_line`
renders — kind letter, three octal mode digits, `u:<row>`, size, `ns:`-prefixed
mtime, name. The 1.0 read loop still writes bare names, so this is the shape a
consumer binds against, not yet what the loop prints:

```
$ ls -l -h
- 644 u:0 11.8K ns:1755808140000000000 argv_surface.pdx
- 644 u:0 21.6K ns:1755850440000000000 runner.pdx
d 755 u:0 4.0K ns:1755850440000000000 tests
```

Consume the record stream by field name instead of by column slicing — the whole
reason the emitter exists:

```
$ ls | grep --schema PdxFsDirEntry --field name --pattern '.pdx$'
argv_surface.pdx
runner.pdx
semantic_emit.pdx
```

## See also

- [libpdx-semantic-pipe](https://github.com/paideia-os/libpdx-semantic-pipe) — schema bind/send and the version-tolerance rules governing `PdxFsDirEntry@0.1`.
- [libpdx-argv](https://github.com/paideia-os/libpdx-argv) — the parser behind the flag surface.
- [libpdx-audit](https://github.com/paideia-os/libpdx-audit) — the `DirListRecord` frame opened before the first byte.
- [libpdx-cap](https://github.com/paideia-os/libpdx-cap) — `KIND_USER` wire decode behind the `u:<row>` owner column.
- [cat](https://github.com/paideia-os/cat) · [doc](https://github.com/paideia-os/doc) — sibling core utilities; `doc ls` renders `doc/ls.pdxdoc`.

Tag `v1.3.0` / `manifest.pdxproj` `version = 1.1-C` (the v1.1-A/B real-body wave
closer). `CHANGELOG.md` records the 0.1→1.0 progression, the 1.x additive-only
rules, and the `v1.1-A/B/C` real-body landing; `design/release-1.0.md` pins the
1.0-era `manifest.pdxsig` shape and `design/mirror-push.md` the `pkg install ls`
path. MIT — see `LICENSE`.
