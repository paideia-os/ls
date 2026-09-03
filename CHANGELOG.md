# ls -- CHANGELOG

Signing is performed at `pkgs.paideia-os` mirror-push time (see
`design/mirror-push.md`); the in-tree release does NOT carry a signed
`manifest.pdxsig`. The CHANGELOG entry moves in lock-step with the
version stamp in `manifest.pdxproj` and the git tag; the signed
`manifest.pdxsig` is composed against those inputs at the mirror push
and stored under `pkgs.paideia-os/ls/<version>/`.

## [Unreleased]

Post-1.0.1 items on the Enhancement v1.x wave
(`design/enhancement-plan.md`). No frozen 1.0 interface (argv surface,
exit-code map, wire body shape, `caps.decl`) changes in this section.

## [1.0.1] -- 2026-09-03 -- honesty patch (ENH-003 + ENH-011 + ENH-012) <a id="101"></a>

**1.0.1 (v1.x honesty patch).** Closes the seven 1.0.1-wave items from
`design/enhancement-plan.md` §5 (ENH-001/003/004/010/011/012/013) --
the three headline honesty items (ENH-003 + ENH-011 + ENH-012, from
which this release takes its subtitle) plus the four cheap-and-
unblocked items that had already landed under `[Unreleased]` before
the version bump. Every entry is either a documentation retraction,
a test-harness tightening, or a small correctness fold behind an
existing entry point: no change to any frozen 1.0 interface (argv
surface, exit-code map, wire body, `caps.decl`) per §"Compatibility
rules from 1.0 forward". Wave 2 (ENH-002 / ENH-005 / ENH-006 /
ENH-007) lands as 1.1.0 per the same plan.

### Fixed

- **ENH-003** (#17) -- adds byte-exact golden fixtures for
  `LongFormat::long_format_line` (`tests/long_format_fixtures.pdx`,
  3 cases: file mode 0o644, dir mode 0o755, symlink mode 0o777 with
  deterministic uid/gid/size/mtime) and for
  `HumanSize::human_size_render` (`tests/human_size_fixtures.pdx`,
  6 boundary cases: 0, 999, 1024 -> "1.0K", 1536 -> "1.5K",
  1048576 -> "1.0M", 1099511627776 -> "1.0T"). Human-readable copies
  of each expected byte sequence live under `tests/goldens/`; the
  `.pdx` fixtures pin the same bytes as `.rodata` tables so the
  comparator is byte-for-byte exact without a filesystem read.
  Retires the enhancement-plan §2.2 "dead code with no fixture"
  status for both renderers at HEAD.
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
- **ENH-004** (#18) -- `Dispatch::ls_dispatch` now folds its return
  value through `ExitMap::exit_map` before returning. Previously
  `exit_map` had no caller anywhere in the tool and `ls_dispatch`
  (this repo's `entry`, since there is no `_start` frame) returned a
  raw `0xFFFFEBxx` sentinel verbatim; a successful run exited
  `0xFFFFEB00`, not `0`. Every documented exit code (0/2/3/4, README
  and `doc/ls.pdxdoc`) is now what the tool actually returns.
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
- **ENH-011** (#20) -- `tools/build.sh` now iterates every
  `tests/*.pdx` and invokes `paideia-as test <fixture>` on each,
  propagating a non-zero exit. The runtime evaluator is not on-tree
  today (paideia-as-test §"Phase-4-m12-001: execution gates on the
  runtime evaluator") so this is a parse+encode smoke pass per
  fixture rather than a live `verify_all` run; it does catch the
  scenario the pre-1.0.1 script missed (a fixture that fails to
  parse under a paideia-as bump, silently non-invoked). Also adds a
  link-check pass that greps `src/` and `tests/` for orphan
  `[legacy: ... OK]` fingerprint tags: any decl missing the
  space-`OK`-space closing is flagged. Currently a no-op (no legacy
  tags in the ls repo) but active as a forward guard for the
  God-file refactor cadence.
- **ENH-012** (#21) -- retracts the `dist/manifest.pdxsig` claim.
  CHANGELOG, STATUS, and `manifest.pdxproj` previously stated the
  in-tree release ships `dist/manifest.pdxsig` "composed per
  `design/release-1.0.md`". `dist/` does not exist in the tree
  (`git ls-files dist` empty) and was never composed. The signing
  chain moves to `pkgs.paideia-os` mirror-push time (per
  `design/mirror-push.md`): the manifest is composed and signed by
  the mirror pipeline against the tagged source tree + tar, and lives
  at `pkgs.paideia-os/ls/<version>/manifest.pdxsig`. The in-tree
  release carries CHANGELOG + STATUS + `manifest.pdxproj` + tag only.
  The four-way byte-identity invariant `design/mirror-push.md` builds
  degrades to a three-way (compose / mirror-standalone / in-tar);
  the tree copy is dropped from the invariant.
- **ENH-013** (#22) -- drops the phantom `libpdx-elevate @ ^1.0` entry
  from `manifest.pdxproj`'s `deps:` block. No call site in this repo
  ever consumed it; `libpdx-elevate` appears elsewhere only as a
  naming-convention precedent cited in comments, not as a real
  dependency.

### Deferred (upstream fix)

- `src/argv_surface.pdx:266-268` carries a one-line NOTE pointing to
  libpdx-argv#42, which tracks the argv[0] convention: `parse_argv`
  currently treats argv[0] as a real arg, which is silently latent
  until multi-path listing (#29 / ENH-014) lands. The fix belongs
  upstream in libpdx-argv, not here; ls's passthrough is byte-for-
  byte unchanged in 1.0.1 and will land automatically when the
  libpdx-argv fix bumps the submodule.

## [1.0.0] -- 2026-08-22 <a id="100"></a>

**M5 close.** First byte-frozen release. The 1.0 line is the R50
Wave-2 core-utility contract that every downstream consumer (shell
pipelines, `doc ls`, `pkg install ls`, the R50.M5 QEMU smoke) binds
against. Version bump + git tag `v1.0.0` move together per this
repo's version discipline (mirrors
`feedback_paideia_as_version_discipline` across the ls repo boundary).
NB: the original 1.0.0 entry claimed a `dist/manifest.pdxsig` shipped
with the tree; that was incorrect (see 1.0.1 ENH-012). The signed
manifest is composed at `pkgs.paideia-os` mirror-push time and lives
at `pkgs.paideia-os/ls/1.0.0/manifest.pdxsig`.

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
- `manifest.pdxsig` is NOT in the tree (see 1.0.1 ENH-012). The
  signed manifest is composed and dual-signed at `pkgs.paideia-os`
  mirror-push time per `design/mirror-push.md`, against the tagged
  source tree + `pkg.tar`. It lives at
  `pkgs.paideia-os/ls/1.0.0/manifest.pdxsig`, not under `dist/` in
  this repo. In the scaffold epoch (pre-R32) both signature slots
  are bytewise zero and the pkg verifier returns
  `SIG_UNSIGNED_SCAFFOLD` per `design/drivers/blob-policy.md` §1.7 in
  the paideia-os repo. A re-sign at R32 rewrites the mirror copy
  only; the source tree does not change.
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
