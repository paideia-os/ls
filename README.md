# ls

paideia-os directory listing — writes entry names to the terminal and emits one
typed `PdxFsDirEntry@0.1` record per entry on the semantic pipe.

## Synopsis

```
ls [-l] [-a] [-h] [--json] [--schema] [--color=<v>] [<path>]
ls                       # <path> defaults to "."
```

Exactly one positional path is consumed (`pos_ptrs[0]`); positionals beyond
`[0]` are ignored at 1.0 and become a multi-path list at 1.1. Short flags are
passed one per argument.

## Description

`ls` iterates a directory through a pre-narrowed `KIND_PDXFS_FILE(read, <arg-path>)`
capability the shell hands it at exec (cap slot 2), calling `sys_pdxfs_dir_readnext`
(sysno 72) once per entry. Each accepted entry's name plus `\n` is written to the
terminal, and the entry's 128-byte kernel record — extended with a 16-byte owner
capability wire — is sent as one 144-byte `PdxFsDirEntry@0.1` record on the stdout
`KIND_IPC_ENDPOINT`. `ls` never mints a filesystem capability of its own: it holds
read authority on exactly the argument path and nothing else.

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

## Options

Flags are recognised by `ArgvSurface::argv_surface_parse` (`src/argv_surface.pdx`)
over `libpdx-argv::Parser`, and OR'd into a bit-field read by `Runner`. A short
flag that is not `l`/`a`/`h` returns `AS_ERR_UNSUPPORTED_SHORT`; a long flag
outside the recognised set returns `AS_ERR_UNKNOWN_FLAG`. Both are exit 2.
Clustered short flags (`-la`) are rejected upstream by `parse_argv` and surface
as `AS_ERR_PARSER_REJECT`, also exit 2 — write `-l -a`.

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

## Semantic pipe output

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
| 136 | `owner_target_ptr` | `u64` | `ls` | `user_row`; `0` placeholder at 1.0 until `sys_pdxfs_stat_by_inode` ships |

Bytes `[0..128)` are the M3-001 record unchanged, so a decoder pinned to the
128-byte shape still reads a valid prefix of a 144-byte record. Field additions
follow the `libpdx-semantic-pipe` version-tolerance rules and are additive on the
1.x line; changing the meaning of an existing field is a 2.0.

## Exit codes

`src/exit_map.pdx` folds the internal `0xFFFFEBxx` band into the I4 vocabulary.
An unclassified code routes to 3, never to 0.

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

Version `1.0.0` (R50 Wave-2). `CHANGELOG.md` records the 0.1→1.0 progression and
the 1.x additive-only rules; `design/release-1.0.md` pins the `manifest.pdxsig`
shape and `design/mirror-push.md` the `pkg install ls` path. MIT — see `LICENSE`.
