# ls.M5-001 -- implementation notes

**Issue:** #15 -- dual-signed release + .pdxdoc.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M5-001 line
501 (paideia-os).

## What landed

- `manifest.pdxproj` -- new file at repo root; the paideia-as build
  manifest for the byte-frozen 1.0 artefact. Version bumped from
  the (implicit) M4 shape to `1.0.0`. Source list mirrors the
  15-file `src/` inventory landed across M1..M4; test list mirrors
  the 4-fixture `tests/` inventory. Dep list version-pins every
  library to `^1.0` so a downstream `pkg install ls` resolves
  against the 1.0 line of every library. `release:` block names
  the four M5 artefacts (manifest.pdxsig, CHANGELOG entry,
  pdxdoc, mirror target).
- `CHANGELOG.md` -- new file at repo root; the `[1.0.0]` entry
  freezes the argv surface, the text render, the PdxFsDirEntry
  wire body, the audit-first gate, the exit-code map, and the
  caps.decl at 1.0. Includes the compatibility rules for 1.x
  (additive-only) and the 2.0 semantic-change fence. Rolls up the
  0.1..0.4 progression against M1..M4 close.
- `doc/ls.pdxdoc` -- new file; the man-equivalent per
  `design/tooling/plan.md` I7 §2, in the `.pdxdoc` grammar the
  `doc` repo's `PdxdocParser` (doc.M1-002) accepts:
    - `!doc ls`, `!version 1.0.0` -- the two singleton headers.
    - `!section` boundaries: synopsis, flags, capabilities,
      semantic pipe, audit, exit codes, colorization, examples,
      see-also, version.
    - `!posix-diff` passthrough lines for the two load-bearing
      Paideia-vs-POSIX deltas (schema-driven colors,
      capability-not-uid owner column).
    - `!example` / `!end-example` blocks -- 5 concrete
      invocations with expected output.
    - `!ref` lines for the see-also cross-refs (pkg, shell,
      caps, libpdx-semantic-pipe, libpdx-audit).
- `design/release-1.0.md` -- new file; the release specification
  for `ls-1.0.0`. Sections:
    - §1 -- what "signed" means in the scaffold epoch (all-zero
      signature slots -> SIG_UNSIGNED_SCAFFOLD verdict per
      blob-policy §1.7).
    - §2 -- the `manifest.pdxsig` wire shape KV-record-by-record
      (header + 14 KV records + sigblock), pinned against
      `pkg/design/manifest-format.md` §3-§4.
    - §3 -- release process (paideia-as release invocation shape,
      dist/ staging, tag).
    - §4 -- byte-identity invariant between the tar-embedded and
      mirror-standalone manifest copies (bridge to M5-002).
    - §5 -- what freezes at 1.0 (additive-only rules).
    - §6 -- non-goals of the release spec.

## Entry-point contract

None -- M5-001 is a metadata + spec close. No new `.pdx` files, no
new module entry points. The build manifest, changelog, doc, and
release spec compose the 1.0 shape a downstream `paideia-as release`
consumes when the signing chain lands at R32.

## Design decisions

- **`manifest.pdxproj` retro-fitted at M5.** The M1..M4 tree
  landed without a `manifest.pdxproj` (unlike rm/cp/pkg which
  landed it at M1). Adding it at M5 rather than backfilling every
  intermediate milestone preserves the M1..M4 commit history and
  matches the "release-close moves metadata" pattern established
  by `feedback_paideia_as_version_discipline` (workspace.version +
  tag + CHANGELOG move together at phase close). The `sources:`
  block enumerates exactly the 15 files landed across M1..M4 --
  drift between the manifest and `src/` is a build-time error at
  `paideia-as build`.

- **Version 1.0.0 (not 0.5.0, not 1.0.0-rc).** M5 is the
  byte-frozen release, not a release candidate. The 1.0.0 tag is
  what pkg-repo M5 will resolve `pkg install ls@1.0.0` against.
  Any hardening between now and R32 lands as 1.0.1..1.0.N (bugfix
  additive) rather than as pre-1.0 markers.

- **CHANGELOG entry format follows Keep-a-Changelog.** `## [1.0.0]
  -- <date>` sections with `### <subheading>` blocks. Mirrors the
  paideia-as `CHANGELOG.md` shape (per the
  `feedback_paideia_as_version_discipline` memory) rather than the
  fully-freeform kernel `MEMORY.md` shape. Every 1.x bump on this
  repo appends a new `## [1.0.x]` block above the `[1.0.0]` block.

- **Scaffold-epoch discipline stamped into `dist/manifest.pdxsig`
  spec, not into a hand-written binary.** The M5 tree does not
  ship a `dist/manifest.pdxsig` binary today because:
    (a) the composing tool (`paideia-as release`) does not exist
        pre-R32 (per `design/user/model.md` §11.2);
    (b) fabricating a 6594-byte all-zero sigblock + 1952-byte
        all-zero pubkey pair by hand into a binary blob would
        pass the scaffold-epoch verdict at the pkg verifier but
        would embed a source-tree-authored file that the M5
        commit history could not audit-check byte-by-byte;
    (c) the discipline established by
        `design/security/pe-secure-boot-signing.md` for R28 was
        "scaffold-first specification, live-at-R32 binary" --
        the same pattern applies here.
  Instead, `design/release-1.0.md` §2 pins the wire shape
  KV-record-by-record, and `manifest.pdxproj`'s `release:` block
  names `dist/manifest.pdxsig` as the composed artefact. At R32
  the paideia-as release chain composes the file
  byte-deterministically from this spec + the current source
  tree, without a further source-tree edit.

- **`doc/ls.pdxdoc` in `doc/` not `docs/` or `.pdxdoc` at root.**
  The pkg install layout at `/pkgs/<name>-<version>/doc/*.pdxdoc`
  per `design/tooling/plan.md` §6.4 mandates `doc/` as the
  per-package doc directory; the repo directory shape mirrors
  that so a `pkg` tar composition (§design/mirror-push.md) is a
  direct copy without a rename.

- **CHANGELOG anchor `<a id="100"></a>`.** The
  `manifest.pdxproj:changelog_entry = CHANGELOG.md#100` reference
  requires a stable HTML anchor at the 1.0.0 section boundary.
  GitHub renders section headings with generated `#h-1-0-0`-style
  anchor ids that are template-dependent; the explicit `id="100"`
  span guarantees the fragment resolves the same across a
  rendered README, a `doc pkg` back-end, and a `gh browse` deep
  link.

- **`!posix-diff` passthrough (not first-class parse).** doc.M1-002
  passes `!posix-diff` lines through as body content; doc.M2-004
  upgrades them to first-class annotations. The M5 `ls.pdxdoc`
  uses `!posix-diff` as a section-independent line (not wrapped
  in `!section`) so both parses render it correctly -- as prose
  today, as a boxed inline annotation post-doc.M2.

## paideia-as conformance

Not applicable -- no `.pdx` files at M5-001. The `.pdxdoc` grammar
is doc-repo-side; the CHANGELOG + manifest.pdxproj + release-1.0.md
are prose/config-side.

## What is NOT in this file

- **The composed `dist/manifest.pdxsig` binary.** Per §"Scaffold-
  epoch discipline" above, the byte-frozen file is composed at R32
  from the spec at `design/release-1.0.md`. Today's tree ships the
  spec; the file lands with the R32 release chain.
- **Live ML-DSA-65 signature bytes.** Same reason.
- **`pkg install ls` end-to-end witness.** Lives in M5-002.
- **Mirror push runbook.** Lives in M5-002 (`design/mirror-push.md`).

## What's next

- **M5-002 (#16):** compose `design/mirror-push.md` (mirror-target
  layout, byte-identity invariant, staging runbook), the
  `tests/pkg_install_e2e.md` end-to-end witness matrix, and the
  supporting `.plans/m5-002-notes.md`. M5-002 close is M5 close;
  the `v1.0.0` tag moves at the M5-002 commit.
- **R32 re-sign (post-M5).** At R32 the `paideia-as release
  --scaffold-epoch` flag is retired; the same command composes a
  real dual-signed `manifest.pdxsig` from the same spec at
  `design/release-1.0.md`. The 1.0.0 tag stays; a `1.0.1` bump
  is NOT required for the re-sign per §1 of the release spec.
