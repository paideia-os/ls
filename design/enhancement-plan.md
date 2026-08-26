# ls — enhancement plan (v1.x)

**Status:** planning pass, 2026-08-25. No code changes in this document.
**Baseline:** `v1.0.0` (commit `05d63e2`, M5 closed) plus the post-tag
build fixes (`f18e651`, `9c71c11`, `9fc643d`) and the README rewrite
(`220a319`).
**Method:** every claim below was checked against the source tree at
HEAD, not against STATUS.md or the milestone titles. Where a shipped
document and the code disagree, the code is treated as the fact.

---

## 1. Current state

### 1.1 What genuinely works

`ls` is the best-integrated tool in the org, and the integration claims
survive inspection. Three of the five declared library dependencies have
real call sites on the live execution path, not just manifest entries:

| Library | Manifest | Real call site | On live path? |
|---|---|---|---|
| `libpdx-argv` | `deps:` ✓ | `call parse_argv`, `call parsed_args_reset` (`src/argv_surface.pdx`) | yes |
| `libpdx-cap` | `deps:` ✓ | `call cap_unpack` (`src/owner_col.pdx:259`) + `unpacked_kind` / `unpacked_target_ptr` reads (`:262`, `:269`) | reachable only via `long_format_line` — see §2.2 |
| `libpdx-semantic-pipe` | `deps:` ✓ | `call libpdx_semantic_pipe_bind` (`src/semantic_emit.pdx:257`), `call send_record` (`:369`) | **yes** — `runner_ls` calls both per run |
| `libpdx-audit` | `deps:` ✓ | `call audit_ls_begin` (`src/runner.pdx:248`), `call audit_ls_commit` (`:427`) | **yes** — audit-first ordering is real |
| `libpdx-elevate` | `deps:` ✓ | none | **no** — phantom dep, see ENH-013 |

The audit-first invariant (I5) is genuinely enforced: `runner_ls` opens
the `DirListRecord` frame at line 248, *before* `sem_emit_reset` and
before any `tty_write`, and every return path funnels through
`rn_ls_epilogue` which commits with the exit code. The syscall
trampolines (`sysno 72 sys_pdxfs_dir_readnext`) are real. The 144-byte
wire body is composed and sent for real. Four fixture modules exist with
genuine golden data (`tests/color_fixtures.pdx` 607 lines,
`tests/owner_fixtures.pdx` 575, `tests/exit_matrix.pdx` 258,
`tests/schema_golden.pdx` 426).

### 1.2 What the tool actually does when run

Everything else is scaffolding that is not connected to anything.

`Runner::runner_ls` writes `name + '\n'` unconditionally for every
accepted entry (`rn_ls_copy_head` → `tty_write`, lines 319–352) and reads
exactly one flag bit — `RN_BIT_A_MASK` (0x2, `-a`) — which it forwards to
`hidden_filter_accept`. It never reads `AS_BIT_L`, `AS_BIT_H`,
`AS_BIT_JSON`, `AS_BIT_SCHEMA`, or `AS_BIT_COLOR`.

A grep for call targets across `src/*.pdx` returns 23 symbols. The
following shipped, documented, tested entry points are **not among
them** — nothing in the tool ever calls them:

- `LongFormat::long_format_line` — the `-l` renderer. Only textual
  occurrence outside its own file is a comment at `src/ls.pdx:133`.
- `ColorPicker::color_pick`, `color_sgr_prefix`, `color_sgr_suffix` —
  the `--color=` renderers.
- `ExitMap::exit_map` — the 0xFFFFEBxx → I4 exit-code fold.
- `OwnerCol::owner_col_render_from_wire` — reachable only from the
  fixture, never from the tool.

`HumanSize::human_size_render` and `OwnerCol::owner_col_render_from_row`
*are* called, but only from `long_format_line`, which is itself dead.

So at HEAD, `ls -l`, `ls -h`, `ls --color=always`, `ls --json` and
`ls --schema` all produce byte-identical output to bare `ls`. The only
flag with observable behaviour is `-a`.

### 1.3 Exit codes are never folded

`manifest.pdxproj` declares `entry = Dispatch::ls_dispatch`.
`ls_dispatch` returns `runner_ls`'s raw `rax` verbatim — one of the
`0xFFFFEBxx` sentinels. `exit_map` has no caller. There is no `_start`
in this repo.

Consequently the exit vocabulary documented in README §"Exit codes" and
in `doc/ls.pdxdoc` §"exit codes" (0 / 2 / 3 / 4) is not what the entry
point returns. A successful run returns `0xFFFFEB00` (4294962432), not
`0`. `tests/exit_matrix.pdx` verifies `exit_map` in isolation and passes,
which is why this was never caught: the fixture tests the function, and
nothing tests the composition.

### 1.4 The path argument is decorative

`Dispatch::ls_dispatch` loads `_as_path_ptr` (lines 100–101) and passes
it to `runner_ls` as `rdi`. `runner_ls` uses it for exactly one thing —
a two-instruction well-formedness gate (lines 231–236): null is accepted,
non-null-with-byte0-NUL returns `LS_ERR_BAD_PATH`. The path is never
resolved, never compared against anything, and never used to select a
directory. The listing target is determined entirely by whichever
capability the shell placed in `LS_DIR_CAP_SLOT` (2).

There is no occurrence of `chdir`, `getcwd`, or `cwd` anywhere in
`src/`. `ls`, `ls /bin`, `ls ../foo`, and `ls a-path-that-does-not-exist`
therefore all list the same directory and all exit identically. The
README example `$ ls /bin` is not achievable by anything inside this
repo; it depends wholly on shell-side cap narrowing, and `ls` performs no
check that the cap it received corresponds to the path the user typed.

---

## 2. The `-l` format bug

This is two defects stacked, and they need separating because they ship
on different timelines.

### 2.1 Layer 1 — the man page documents output the renderer cannot produce

`doc/ls.pdxdoc` is the man-equivalent that `doc ls` renders. It is the
user-facing spec. Its `-l` example (lines 149–154) reads:

```
$ ls -l
f rw- u:0    12103  2026-08-21T20:49  argv_surface.pdx
```

`LongFormat::long_format_line` (`src/long_format.pdx`, twelve emit steps)
produces, for the same entry:

```
- 644 u:0 12103 ns:1755808140000000000 argv_surface.pdx
```

Field by field:

| Column | `ls.pdxdoc` shows | Code emits | Authority in source |
|---|---|---|---|
| kind | `f` | `-` | `_lf_kind_letters[0x8] = 0x2D` (`:131`) — `'f'` is not in the table at all |
| mode | `rw-` (POSIX glyphs) | `644` (three raw octal digits) | steps 3a/3b/3c, `add rax, 0x30` (`:235`, `:250`, `:263`) |
| owner | `u:0` | `u:0` | matches |
| size | `12103` | `12103` | matches |
| mtime | `2026-08-21T20:49` (ISO-8601) | `ns:1755808140000000000` | step 9a emits `'n'`,`'s'`,`':'` (`:354`, `:364`, `:374`) then `render_dec_u64` |
| separators | multi-space, columns padded to width | exactly one `0x20`, no padding anywhere | steps 2/4/6/8/10 each emit a single `mov rdx, 0x20` (`:221`, `:278`, `:301`, `:343`, `:397`) |

Four of six columns are wrong, and the column *alignment* the sample
implies does not exist in the renderer at all — `long_format_line` has no
padding logic of any kind.

The `-lh` example (lines 156–161) compounds it twice more:

1. It uses the clustered short form `-lh`. `README.md` §Options states
   clustered short flags are rejected upstream by `parse_argv` and
   surface as `AS_ERR_PARSER_REJECT` → exit 2. The documented invocation
   cannot run.
2. It shows `12K`. `HumanSize::human_size_render` emits `N.dK` for
   anything ≥ 1024 (`:231`–`:261`: integer, `'.'`, tenth, letter). 12103
   bytes renders as `11.8K`, not `12K`.

The `--schema` example (lines 163–167) shows a schema dump. `AS_BIT_SCHEMA`
has no consumer; the real output is empty.

`README.md` is *correct* on all of this — it was rewritten from source at
`220a319` and accurately documents `-`, three octal digits, `ns:`-prefix,
single-space separation, and the "shipped, not called by the read loop"
status. The defect is confined to `doc/ls.pdxdoc`, which was written at
M5-001 (`87b074a`) against the plan doc's intended layout rather than
against the code. Since `doc ls` is how a user on the running system
reads this, the pdxdoc is the copy that matters most.

### 2.2 Layer 2 — the renderer is dead code and has never been verified

`long_format_line` has zero callers (§1.2). It is also the only renderer
in the repo with **no test fixture**: `tests/` covers ColorPicker,
OwnerCol, ExitMap, and SemanticEmit, but there is no long-format golden
and no human-size golden. Its column layout has therefore never been
byte-compared against anything, by anything, ever.

That is why the layer-1 divergence could persist through M5 sign-off:
the sample in the man page and the bytes from the renderer were never in
contact.

Ordering consequence for the fix: pin the renderer with a byte-exact
golden **first** (ENH-003), then correct the man page to match the pinned
bytes (ENH-001), then wire it into the loop (ENH-002). Correcting the doc
before pinning the renderer just moves the unverified claim.

---

## 3. Status of the prior milestone claims

### 3.1 ls#12 — "M4-002 owner-render correctness for multi-user quota subtree"

**Genuine as a unit test. Stale as titled.**

Real: `tests/owner_fixtures.pdx` exists at 575 lines and does what it
says — 7 row cases (rows 0, 1, 7, 42, 1000, 65534, 65535) through
`owner_col_render_from_row` with byte-exact expected output, plus 2
wire-cap cases through `owner_col_render_from_wire` including a
KIND_USER round-trip and a KIND_TTY refusal asserting `OC_ERR_NOT_USER`.
The `libpdx-cap` decode path is genuinely exercised.

Not achieved: there is no path in the running tool by which a multi-user
quota subtree renders distinct owners.

- The text path (`owner_col_render_from_row`) is reachable only through
  `long_format_line`, which is never called (§1.2).
- The semantic-pipe path hardcodes the owner row to zero. `sem_emit_entry`
  stores `KIND_USER` at wire offset 128 and then `xor rax, rax` → offset
  136 (`src/semantic_emit.pdx:362`). `sem_emit_wire_compose` does the same
  at `:483`. Every record ever emitted, for every entry, for every owner,
  reports row 0.

The placeholder is honestly disclosed in README, pdxdoc, and CHANGELOG,
and is blocked on `sys_pdxfs_stat_by_inode` which does not exist
kernel-side. But the issue title claims a correctness property the tool
does not have. Tracked forward as ENH-008.

### 3.2 ls#14 — "M4-004 `--schema` output validates against libpdx-semantic-pipe golden"

**Real work landed. Title overclaims on both halves.**

Real: `SemanticEmit::sem_emit_wire_compose` (the compose-only sibling of
`sem_emit_entry`) and `tests/schema_golden.pdx` (426 lines) both exist and
genuinely pin the 144-byte wire body byte-for-byte without needing a live
substrate. That is worthwhile and it does protect the wire shape.

Overclaim 1 — "`--schema` output": `--schema` produces no output.
`AS_BIT_SCHEMA` is set by `argv_surface_parse` and read by nothing
(§1.2). The fixture validates `sem_emit_wire_compose`, a function
unreachable from the CLI. No `--schema` output was produced, so none was
validated.

Overclaim 2 — "against libpdx-semantic-pipe golden": the golden is
self-referential. `sem_emit_reset` imprints a stub hash — `mov rax, 1`
into lane 0, zeros in lanes 1–3 (`src/semantic_emit.pdx:216`) — rather
than BLAKE3("PdxFsDirEntry@0.1"). The fixture pins that same stub. The
test confirms the tool agrees with its own placeholder; it does not
confirm agreement with any semantic-pipe registry value. The real hash is
deferred to `libpdx-schema-registry.M1` (R51+), as the source comment
states. Tracked forward as ENH-006 and ENH-010.

### 3.3 M5-001 / M5-002 release artefacts

`CHANGELOG.md` §"Release artefacts (M5-001, #15)" states
`dist/manifest.pdxsig` was "composed per design/release-1.0.md".
`manifest.pdxproj` §release names it as `manifest_pdxsig =
dist/manifest.pdxsig`. `design/mirror-push.md` builds a four-way
byte-identity invariant on top of it.

`dist/` does not exist in the tree and `git ls-files dist` returns
nothing. The signed artefact the 1.0 tag and the entire mirror-push
runbook rest on is absent from the repository. Tracked as ENH-012.

### 3.4 Test execution

`tools/build.sh` compiles every `src/*.pdx` and `tests/*.pdx` with
`paideia-as build --emit elf64` and reports failures. It does not
*execute* any fixture — `<fixture>_verify_all` is never invoked. The
"future M5 smoke harness" that `tests/README.md` describes was never
written.

Additionally, each file is compiled independently, so cross-module call
targets (`call render_byte_write`, `call cap_unpack`, `call send_record`)
are never link-resolved. A green `build.sh` is evidence that each file
parses and encodes; it is not evidence that the composition links or that
any golden passes. Tracked as ENH-011.

---

## 4. Gap versus what a paideia-os user needs at HEAD

A user at a shell prompt on the running system, today, gets: a list of
bare filenames from a directory chosen by the shell rather than by their
argument, with dot-files hidden unless `-a`, an exit code outside the
documented vocabulary, and a man page whose three most useful examples
show output the tool cannot emit.

Ranked by user-visible impact:

1. **`-l` does nothing** (ENH-002) — the single most-used flag of the
   single most-used utility. Blocks any interactive filesystem work.
2. **The man page lies** (ENH-001) — `doc ls` is the discovery surface;
   wrong samples cost more than absent ones because they are trusted.
3. **Exit codes are unmapped** (ENH-004) — every shell conditional,
   pipeline, and script that branches on `ls` status is wrong. Cheap fix,
   wide blast radius.
4. **The path argument is ignored** (ENH-009) — `ls somedir` silently
   lists something else. Arguably worse than an error, because it is
   silent.
5. **`--schema` is inert** (ENH-006) — the semantically-queryable
   terminal is the project's thesis; schema discovery is how a user
   finds out what to query. Trivial to implement.
6. **Owner is always row 0** (ENH-008) — undermines the D2
   owner-as-capability literal in practice. Kernel-blocked.
7. `--color=`, `--json`, multi-path (ENH-005, ENH-007, ENH-015).

The pattern across items 1–5 is uniform and worth naming: **every
primitive is built, tested, and disconnected.** The repo's deficit is not
missing implementation, it is missing composition. That is unusually
cheap to close, and it is why the recommendation in §6 is polish rather
than reset.

---

## 5. Issue plan

Filed under milestone **"Enhancement v1.x — ls"**.

| ID | # | Title | Effort | Deps |
|---|---|---|---|---|
| ENH-001 | #23 | Correct `doc/ls.pdxdoc` `-l`/`-lh`/`--schema` examples to match real output | XS | #17 |
| ENH-002 | #24 | Wire `LongFormat` into the read loop behind `AS_BIT_L` | M | #17 |
| ENH-003 | #17 | Byte-exact goldens for `long_format_line` + `human_size_render` | S | none |
| ENH-004 | #18 | Fold `0xFFFFEBxx` through `ExitMap` at the entry boundary | S | none |
| ENH-005 | #25 | Wire `ColorPicker` into the read loop behind `AS_BIT_COLOR` | M | #24 |
| ENH-006 | #19 | `--schema` prints declared output schemas and exits 0 | S | none |
| ENH-007 | #26 | `--json` emits one JSON object per row over the wire record | M | #24 |
| ENH-008 | #28 | Real per-entry owner row (retire the hardcoded 0) | L | #24 + kernel |
| ENH-009 | #29 | Resolve the path argument against the kernel cwd (R86) | L | kernel |
| ENH-010 | #27 | Real `PdxFsDirEntry@0.1` schema hash from the registry | M | #19 |
| ENH-011 | #20 | Execute fixtures + link-check in `tools/build.sh` | S | none |
| ENH-012 | #21 | Compose and commit the missing `dist/manifest.pdxsig` | S | none |
| ENH-013 | #22 | Drop the phantom `libpdx-elevate` dependency | XS | none |

Suggested landing order: #17 → #23 → #18 → #20 → #22 → #21 (all cheap,
all unblocked, all shippable as 1.0.1) then #24 → #19 → #25/#26 → #27 as
1.1.0, with #28 and #29 gated on kernel work.

---

## 6. Is `v1.0.0` defensible?

**Split verdict: defensible as an interface freeze, not defensible as a
working tool. Correct response is a 1.0.1 doc patch plus a 1.1.0 wiring
milestone — not a version reset.**

Defensible: what 1.0 explicitly froze — the argv surface, the
`0xFFFFEBxx` → I4 exit-code map, the 144-byte `PdxFsDirEntry@0.1` wire
body, and `caps.decl` — are all real, all pinned by fixtures, and all
worth binding against. Downstream consumers that bind to the *wire* got
what they were promised. The library integration is real on the live
path, uniquely so in this org. Re-tagging would also break the four-way
byte-identity invariant `design/mirror-push.md` builds over
`pkgs.paideia-os/ls/1.0.0/`, for no benefit to those consumers.

Not defensible: `CHANGELOG.md` frames 1.0 as "the R50 Wave-2
core-utility contract that every downstream consumer binds against" and
lists `-l`, `-h`, and `--color=` under "Contract frozen at 1.0 → Text
render". A contract that says `-l` layout is `kind mode owner size mtime
name` when `-l` emits nothing is not a contract. Combined with a man page
showing fabricated output and an entry point returning undocumented exit
codes, the tag overstates the tool by roughly one minor version — this is
a solid 0.5, not a 1.0.

Recommendation: keep the `v1.0.0` tag. Ship ENH-001/003/004/011/012/013
as **1.0.1**, an honesty patch that makes the documentation and the exit
codes true without touching any frozen interface. Ship ENH-002/005/006/007
as **1.1.0** — all purely additive, all anticipated by README's own
"wiring a renderer into the loop later is additive and needs no re-sign".
The 1.0 freeze was designed to permit exactly this, and it does.

---

## 7. Companion paideia-os monorepo work (flagged, not filed here)

Per the coordinating pass, these are noted only:

1. **`sys_pdxfs_stat_by_inode`** — required to retire the hardcoded owner
   row 0 (ENH-008). Also needs per-entry `mode_bits`, `size`, and
   `mtime_ns`, none of which the 128-byte `sys_pdxfs_dir_readnext` record
   carries today — which means ENH-002's `-l` will render zeros for three
   of its six columns until this lands. This is the hard blocker on the
   whole `-l` line, not just on owner.
2. **`sys_chdir` / `sys_getcwd` (R86) reachable from a tool** — required
   for ENH-009. Also needs a decision on where argument-path → capability
   resolution belongs: the shell narrows the cap today, and `ls` cannot
   verify the cap matches the argument.
3. **`bin_seeds` entry for `ls`** — no `_start` exists in this repo;
   whatever wraps `Dispatch::ls_dispatch` on the monorepo side must call
   `ExitMap::exit_map` (ENH-004) or the fold has to move into `ls_dispatch`
   itself. Needs a cross-repo convention decision.
4. **`libpdx-schema-registry.M1`** — required for ENH-010's real
   `PdxFsDirEntry@0.1` hash.
5. **`sys_pdxfs_dir_readnext` stub set** — still the fixed 3-entry stub
   (`.`, `..`, `hello.pdx`) per STATUS.md, which caps what any live smoke
   of `ls` can assert.
