# ls -- CHANGELOG

Every ls release ships as a dual-signed `manifest.pdxsig` per
`design/release-1.0.md`; the CHANGELOG entry moves in lock-step with
the version stamp in `manifest.pdxproj` and the git tag.

## [Unreleased]

Nothing pending -- v1.2.0 (Wave G) drained the honesty-patch queue
+ landed the v1.1-A/B/C release closer in a single batch.

## [1.2.0] -- 2026-09-13 <a id="120"></a>

**Wave G close.** Consolidates the v1.1-A/B/C release-closer trio
(#42/#43/#44) with the two enhancement items whose Runner-side
wire lands in the same pass (#29 cwd-relative path resolve, #35
-R per-directory header). Jump from 1.0.0 -> 1.2.0 (skipping the
never-tagged 1.1.0) mirrors the `cat` v1.2.0-A Wave-B pattern:
one release stamp for the batch, no phantom mid-versions.

The 1.0 frozen contract holds: argv surface, exit-code map, wire
body shape (144 bytes = 128 kernel prefix + 16 owner Cap wire),
and `caps.decl` are all bit-identical to 1.0.0. Downstream v1.0
consumers filtering by wire shape continue to decode v1.2.0
emissions; consumers filtering by schema-name hash see the new
`LsRecord@0.1` id and can pin against either it or the retained
`PdxFsDirEntry@0.1` id (both are imprinted at reset).

### Closed

- **#42 (v1.1-A) -- LS_RUN_STUB retirement.** The M1-001 STUB
  posture that the Runner briefly held before M3-001 flipped it
  to a real syscall body is now formally retired. Every
  well-formed invocation resolves to `LS_OK` or one of the
  substrate-error sub-band codes. `Ls::LS_RUN_STUB` (0xFFFFEB20)
  stays declared in the error band as a historical marker (so a
  downstream consumer parsing the band-table by name still
  resolves the ordinal) but is never returned by any code path.
  `src/runner.pdx` file header + §V1.1 WAVE block make this
  explicit; no code-body edit was required.

- **#43 (v1.1-B) -- direct sys_semantic_send wire.** The Runner's
  per-entry emit now hits `sys_semantic_send` (sysno 115,
  paideia-os R107-M0-001) directly instead of routing through
  `libpdx-semantic-pipe::Send::send_record`. The 144-byte record
  fits well below the kernel body's 240-byte cap, so no
  fragmentation is required. `LsRecord@0.1` is imprinted as the
  primary v1.1 schema literal via
  `libpdx-semantic-pipe::Schema::spipe_schema_id_from_name`;
  lane 0 of the resulting 32-byte hash is passed as the opaque
  `schema` u64 the kernel body takes. The prior
  `PdxFsDirEntry@0.1` hash is retained in `.bss` for
  interoperability with 1.0 consumers that pin on it.
  - `src/semantic_emit.pdx` -- adds `SE_SYSNO_SEMANTIC_SEND`,
    `SE_KERNEL_MAX_RECORD`, `_se_lsrecord_schema_name`,
    `_se_lsrecord_hash`, `sem_semantic_send_syscall`
    trampoline; `sem_emit_reset` now imprints both hashes;
    `sem_emit_entry` calls the direct trampoline; the
    `send_record` call site is gone.

- **#44 (v1.1-C) -- release closer.** Version bumped 1.0.0 ->
  1.2.0 in `manifest.pdxproj`; `release.changelog_entry` and
  `release.mirror_target` re-point to the 1.2.0 anchors; this
  CHANGELOG entry lands. The `manifest.pdxsig` re-sign lands
  with the next release scan; the on-tree signature slots keep
  their scaffold-epoch `SIG_UNSIGNED_SCAFFOLD` posture. Git tag
  `v1.2.0` is applied by main after the build succeeds.

- **#29 (ENH-009) -- cwd-relative path resolve.** Runner now
  resolves a non-absolute argv path against the process cwd via
  `sys_getcwd` (sysno 86, paideia-os R86.M1-003) BEFORE calling
  `audit_ls_begin`, so the DirListRecord frame carries the
  fully qualified path. Null and already-absolute paths pass
  through unchanged; a `sys_getcwd` refusal defensively falls
  back to the raw argv path (correctness before qualification).
  - `src/pdxfs_shim.pdx` -- new `sys_getcwd` trampoline
    (sysno 86, 2-arg pass-through).
  - `src/runner.pdx` -- new `runner_resolve_path` non-leaf
    helper + `_rn_resolved_path` / `_rn_resolved_len` `.bss`
    slots + wire-in point in `rn_ls_audit_open` (before
    `audit_ls_begin`).

- **#35 (ENH-017) -- -R per-directory header.** When
  `AS_BIT_R_REC` (0x200) is set, Runner emits a
  `<resolved_path>:\n` header via `runner_emit_r_header` after
  `audit_ls_begin` succeeds and before the read loop. The
  header is D3-safe (framed inside the audit) and gives
  downstream tooling a stable section-boundary to bracket
  child listings under. The full depth-first descent lands
  when the paideia-os `sys_pdxfs_dir_open_at` kernel primitive
  ships; today the header is the observable v1.2.0 change.
  - `src/runner.pdx` -- new `runner_emit_r_header` non-leaf
    helper + `_rn_hdr_buf` `.bss` slot + `RN_BIT_R_REC_MASK`
    constant + wire-in point in `rn_ls_audit_open` (after
    `audit_ls_begin`, before `sem_emit_reset`).

### Added

- **PDX_TOOL_NAME + PDX_TOOL_VERSION externs.** New
  `src/tool_ident.pdx` module supplies the two `.rodata` symbols
  libpdx-argv >= 1.1.3's `VersionBackend::emit_default` requires
  (ENH-032). Wire-in of a Parser-driven `--version` fast path
  retires the inline `--version` compare when the next argv
  round lands; the externs ship preemptively so a final-link
  against libpdx-argv 1.1.3+ succeeds without a source bump.
- **`.gitignore`** covers `build-out/` (paideia-as build output),
  `*.swp`, `.DS_Store`.

### Changed

- **`manifest.pdxproj`.** `version = 1.2.0`; `sources` list
  adds `src/tool_ident.pdx`; `deps` bumps
  `libpdx-argv @ ^1.0` -> `libpdx-argv @ >= 1.1.3`.

### Deferred to v1.3

- **Descent controller for -R.** Depth-first recursion under
  `-R` lands when `sys_pdxfs_dir_open_at` (per-name kernel-side
  dir open) ships; ls today emits only the section header.
- **Retire inline `--version` compare.** Route the version
  fast-path through libpdx-argv `VersionBackend::emit_default`
  once the argv-migration round lands (mirrors cat v1.2.0-A's
  own note).

## [Unreleased-pre-1.2 items retained]

Enhancement v1.x wave (`design/enhancement-plan.md`), 1.0.1
honesty-patch items retained from the previous [Unreleased]
section that predated the v1.2.0 batch. No frozen 1.0 interface
change in this section.

### Fixed

- **ENH-010** (#27) -- `SemanticEmit::sem_emit_reset` now imprints the
  real `PdxFsDirEntry@0.1` schema id via `libpdx-semantic-pipe::
  Schema::spipe_schema_id_from_name`, replacing the M3-001 placeholder
  (a fixed first-byte-0x01 stub with no relation to the schema name).
  The new id is byte-identical to libpdx-semantic-pipe's own
  `tests/wire_golden.pdx` `_wg_hash0` corpus entry, so an
  independently-built adopter binding the same schema name now
  interoperates with ls without coordination. Not cryptographic --
  see `src/semantic_emit.pdx` §Schema Hash for the pre-BLAKE3 bridge
  rationale. `tests/schema_golden.pdx`'s hash golden is updated to
  match.
- **ENH-004** (#18) -- `Dispatch::ls_dispatch` now folds its return
  value through `ExitMap::exit_map` before returning. Previously
  `exit_map` had no caller anywhere in the tool and `ls_dispatch`
  (this repo's `entry`, since there is no `_start` frame) returned a
  raw `0xFFFFEBxx` sentinel verbatim; a successful run exited
  `0xFFFFEB00`, not `0`. Every documented exit code (0/2/3/4, README
  and `doc/ls.pdxdoc`) is now what the tool actually returns.
- **ENH-001** (#23) -- `doc/ls.pdxdoc`'s `-l`/`-l -h`/`--schema`
  examples now match the actual renderers: `kind` is `-` (not `f`),
  `mode` is three raw octal digits (not POSIX `rwx` glyphs), `mtime`
  is `ns:<decimal>` (not ISO-8601), `-h` sizes carry a tenths digit
  (`11.8K`, not `12K`), and the `-lh` clustered form is replaced with
  `-l -h` (clustered short flags are rejected upstream). Also adds
  the disclosure `README.md` already carried: at 1.0.0 `-l`/`-h`/
  `--color=` are parsed but not wired into the read loop, `--json`/
  `--schema` have no consumer, and the `--schema` example is a
  proposed shape (`ls.ENH-006`), not shipped output.
- **ENH-013** (#22) -- drops the phantom `libpdx-elevate @ ^1.0` entry
  from `manifest.pdxproj`'s `deps:` block. No call site in this repo
  ever consumed it; `libpdx-elevate` appears elsewhere only as a
  naming-convention precedent cited in comments, not as a real
  dependency.

## [1.0.0] -- 2026-08-22 <a id="100"></a>

**M5 close.** First byte-frozen release. The 1.0 line is the R50
Wave-2 core-utility contract that every downstream consumer (shell
pipelines, `doc ls`, `pkg install ls`, the R50.M5 QEMU smoke) binds
against. Version bump + git tag `v1.0.0` + dual-signed
`manifest.pdxsig` under `dist/` all move together per this repo's
version discipline (mirrors `feedback_paideia_as_version_discipline`
across the ls repo boundary).

### Contract frozen at 1.0

- **argv surface (M1-002).** `ls [-l] [-a] [-h] [--json] [--schema]
  [--color=<v>] [<path>]`; unknown flags return exit 2 (I4 usage);
  positionals beyond `[0]` are ignored at 1.0 and become a
  multi-path list at 1.1.
- **Text render (M1-003 + M2-001..004).** Entry names, one per line,
  to `KIND_TTY(write)`. `-l` layout is `kind mode owner size mtime
  name`. `-a` includes dot-prefix entries. `-h` renders sizes as
  base-2 K/M/G/T/P/E. `-l` owner column is `u:<row>` from
  `KIND_USER_ref` (M2-002 shim; upgraded to a live decode when
  `libpdx-cap` M3-001 lands live). `--color=` is schema/MIME-driven
  per `design/tooling/r49-r50-plan.md` §4.4 -- NOT POSIX file-type
  bits.
- **Semantic pipe (M3-001..002).** `PdxFsDirEntry@0.1` schema; one
  144-byte record per accepted entry on `KIND_IPC_ENDPOINT` stdout.
  Owner field is a 16-byte wire Cap (KIND_USER + placeholder
  user_row 0 until `sys_pdxfs_stat_by_inode` ships). The wire
  shape is the M4-004 fixture golden; a change to the record body
  is a 1.x-compat break under the schema-version rules of
  `libpdx-semantic-pipe`.
- **Audit (M3-003).** `DirListRecord` opened via `libpdx-audit`
  before the first `KIND_TTY` byte; committed at the Runner
  epilogue. Missing broker -> `LS_ERR_AUDIT` -> exit 3; the whole
  Runner body is gated on audit-first per I5.
- **Exit-code map (M4-003).** The 0xFFFFEBxx -> I4 fold pinned in
  `src/exit_map.pdx`. Empty=0, missing=2, cap-denied=4 -- the three
  case-0/7/8 rows in `tests/exit_matrix.pdx`.
- **caps.decl.** The four caps at repo root: `KIND_USER`,
  `KIND_TTY(write)`, `KIND_PDXFS_FILE(read, <arg-path>)`,
  `KIND_IPC_ENDPOINT`. Extra caps refused at exec by the shell's
  `cap_manifest_verify`; missing caps -> exit 4.

### Release artefacts (M5-001, #15)

- `manifest.pdxproj` version bumped to `1.0.0`.
- `dist/manifest.pdxsig` composed per `design/release-1.0.md` --
  header + KV body + 2 x ML-DSA-65 sigblock. In the scaffold epoch
  (pre-R32) both signature slots are bytewise zero and the pkg
  verifier returns `SIG_UNSIGNED_SCAFFOLD` per
  `design/drivers/blob-policy.md` §1.7 in the paideia-os repo. A
  re-sign at R32 bumps the header's `created_unix_secs` field
  without a source-tree change.
- `doc/ls.pdxdoc` -- man-equivalent for `doc ls` per `design/tooling/
  plan.md` I7.
- `CHANGELOG.md` (this file).

### Mirror + `pkg install ls` (M5-002, #16)

- `design/mirror-push.md` -- runbook for staging `pkgs.paideia-os/ls/
  1.0.0/{pkg.tar, manifest.pdxsig}` and the byte-identical invariant
  between the tar-embedded copy of `manifest.pdxsig` and the mirror-
  standalone copy.
- `tests/pkg_install_e2e.md` -- witness matrix for the end-to-end
  `pkg install ls` flow: fetch -> verify -> unpack under
  `KIND_PDXFS_TXN` -> rename -> `pkg list` lists `ls-1.0.0` ->
  `/pkgs/ls-1.0.0/bin/ls` runs against a stub cap-set. Live QEMU
  smoke is deferred to the pkg-repo M5 close per the r49-r50-plan
  §5.1 cross-dep.

### Compatibility rules from 1.0 forward

- **Additive-only.** New flags, new KV body tags in
  `manifest.pdxsig`, new columns in `-l`, new schema fields in
  `PdxFsDirEntry` (via `libpdx-semantic-pipe` version-tolerance
  rules) are additive on the 1.x line and do NOT require a re-sign.
- **Semantic changes.** Any change to the meaning of an existing
  flag, an existing exit-code row, or an existing schema field is a
  2.0 line.
- **Crypto rotation.** ML-DSA-65 -> higher-level variant is a
  `manifest.pdxsig` header `format_version` bump per
  `design/tooling/plan.md` §6; ls follows the pkg format cadence.

### Not in 1.0 (tracked for 1.1)

- Multi-path list (positionals beyond `[0]`).
- Live owner-row lookup via `sys_pdxfs_stat_by_inode` (owner wire
  field currently `user_row = 0` placeholder; upgrades in place
  when the substrate lands).
- Live TTY byte-pump write via `cap_invoke(KIND_TTY, TTY_OP_WRITE)`;
  the M3 compat shim uses `sys_write(fd=1)` until R49.M1 flips it.
- Live emission on `KIND_IPC_ENDPOINT` (shell-populated slot 3);
  today the wire body is composed and pinned by the M4-004 golden.

## [0.4.0] -- 2026-08-22 (M4 close, pre-1.0)

- M4-004 -- `--schema` validates against libpdx-semantic-pipe golden
  (144-byte wire body + schema-hash imprint).
- M4-003 -- exit-code matrix (0xFFFFEBxx -> I4; 13 cases).
- M4-002 -- owner-render correctness for multi-user quota subtree
  (7 row cases + 2 wire-cap cases).
- M4-001 -- coloring test against known-schema fixture corpus
  (10 dispatch cases + 3 SGR goldens).

## [0.3.0] -- 2026-08-21 (M3 close)

- M3-003 -- `DirListRecord` via libpdx-audit before first byte.
- M3-002 -- owner field emits as cap ref, not text uid (D2 literal).
- M3-001 -- `PdxFsDirEntry[]` schema bind + emit on stdout.

## [0.2.0] -- 2026-08-21 (M2 close)

- M2-004 -- coloring driven by declared schema/MIME (not POSIX bits).
- M2-003 -- `-a` hidden-files toggle + `-h` human-readable size.
- M2-002 -- owner column via `KIND_USER_ref` decode through libpdx-cap.
- M2-001 -- `-l` long-format layout (kind, size, mtime, owner).

## [0.1.0] -- 2026-08-21 (M1 close)

- M1-003 -- first runnable: entry-name print to `KIND_TTY`.
- M1-002 -- argv surface via libpdx-argv.
- M1-001 -- scaffold + `caps.decl`.
