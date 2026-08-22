# ls -- mirror push + `pkg install ls` end-to-end

**Wave:** R50  Milestone: M5 (signed 1.0 release)
**Issue:** [#16](https://github.com/paideia-os/ls/issues/16)
`ls.M5-002 mirror push + verify \`pkg install ls\` works end-to-end`.
**Upstream design:**
  - `design/tooling/plan.md` §6.3 (paideia-os) -- pkgs.paideia-os
    repo tree layout.
  - `pkg/design/manifest-format.md` §2 (paideia-os/pkg) -- byte-
    identity invariant between the tar-embedded and mirror-
    standalone copies of `manifest.pdxsig`.
  - `pkg/design/install-flow.md` (paideia-os/pkg) -- the fetch ->
    verify -> unpack -> rename pipeline `pkg install` runs.
  - `design/release-1.0.md` (this repo) -- the manifest.pdxsig
    wire shape ls-1.0.0 ships against.

## 0. Reading order

- §1 -- the mirror tree layout at `pkgs.paideia-os/ls/1.0.0/`.
- §2 -- the release-day mirror-push runbook.
- §3 -- the byte-identity invariant between the tar-embedded and
  mirror-standalone `manifest.pdxsig` copies, plus the tar
  composition order that preserves it.
- §4 -- the `pkg install ls` end-to-end path, step by step,
  against the ls-1.0.0 artefact.
- §5 -- the M5-002 close criterion + the deferred live-QEMU
  witness at pkg-repo M5.

## 1. Mirror tree layout

`pkg install ls` fetches from `pkgs.paideia-os/ls/1.0.0/`. The
mirror tree layout for ls-1.0.0:

```
pkgs.paideia-os/
  index.pdxsig                     ← top-level {name, version, hash}
                                    (composed by pkg-repo M5)
  ls/
    1.0.0/
      pkg.tar                      ← package archive
      manifest.pdxsig              ← standalone dual-signed manifest
```

The `pkg.tar` archive is a POSIX tar with the contents of
`/pkgs/ls-1.0.0/` at install-target-time:

```
pkg.tar :: [ls-1.0.0/]
  bin/ls                           ← elaborated Paideia binary
  caps.decl                        ← callee's cap manifest
  doc/ls.pdxdoc                    ← doc back-end payload
  manifest.pdxsig                  ← same bytes as the standalone copy
```

Note there is no `lib/*.so` in the ls-1.0.0 archive -- ls's
`libpdx-*` dependencies are resolved by pkg at install time from
each library's own package under `/pkgs/libpdx-*-<version>/`, not
bundled here (per `pkg/design/manifest-format.md` §8 non-goals of
1.0 -- no transitive bundling).

## 2. Release-day mirror-push runbook

The M5 close for ls -- and the source of the 1.0.0 mirror content
-- is a five-step runbook. Every step is manual today (pkg-repo M5
lands the automated `pkg publish` command later); the runbook
below is the invariant every automated flow will preserve.

### 2.1 Compose the byte-frozen artefacts locally

```
$ cd <ls-repo-root>
$ paideia-as build src/*.pdx -o build-out/ls           # M1..M4 sources
$ paideia-as release --scaffold-epoch \
                     --name ls \
                     --version 1.0.0 \
                     --caps caps.decl \
                     --pdxdoc doc/ls.pdxdoc \
                     --paideia-as-ver 0.33-crypto-kdf \
                     --source-date-epoch 1755849600 \
                     --output dist/manifest.pdxsig
```

At R32 the same `paideia-as release` invocation without
`--scaffold-epoch` produces a live-signed `dist/manifest.pdxsig`
against the user's `author_sk` (KDF-unlocked) and the release-
engineering `paideia_root_sk`. The rest of this runbook is
identical under either epoch.

### 2.2 Compose `pkg.tar` in the canonical order

The tar composition order is a byte-repro invariant. The pkg-side
verifier in `pkg/src/manifest_codec.pdx` walks the FILE_INVENTORY
records in the order §2.2 of `design/release-1.0.md` pins and
expects the archive to yield the same order. Compose order for
ls-1.0.0:

  1. `ls-1.0.0/bin/ls`
  2. `ls-1.0.0/caps.decl`
  3. `ls-1.0.0/doc/ls.pdxdoc`
  4. `ls-1.0.0/manifest.pdxsig`

Reference invocation (BSD-tar or GNU-tar, both accepted):

```
$ mkdir -p stage/ls-1.0.0/{bin,doc}
$ cp build-out/ls          stage/ls-1.0.0/bin/ls
$ cp caps.decl             stage/ls-1.0.0/caps.decl
$ cp doc/ls.pdxdoc         stage/ls-1.0.0/doc/ls.pdxdoc
$ cp dist/manifest.pdxsig  stage/ls-1.0.0/manifest.pdxsig
$ ( cd stage \
    && tar --format=ustar \
           --owner=0 --group=0 \
           --mtime='@1755849600' \
           --numeric-owner \
           --sort=name \
           -cf ../dist/pkg.tar \
           ls-1.0.0/ ) \
    ;
```

Reproducibility flags (`--owner`, `--group`, `--mtime`,
`--numeric-owner`, `--sort=name`) are load-bearing: without them,
two independent composes on different hosts produce byte-different
`pkg.tar` files with the same content, breaking the mirror-side
`index.pdxsig` hash check.

### 2.3 Verify the byte-identity invariant locally

```
$ sha3sum stage/ls-1.0.0/manifest.pdxsig
<H>  stage/ls-1.0.0/manifest.pdxsig
$ sha3sum dist/manifest.pdxsig
<H>  dist/manifest.pdxsig
```

The two hashes must be byte-equal. In the scaffold epoch every
signature slot is all-zero and this passes trivially; at R32 the
check catches a `paideia-as release` re-invocation that produced
a different manifest between step 2.1 and step 2.2 (e.g. because
`--source-date-epoch` was omitted the second time).

### 2.4 Push to the mirror

```
$ pkg push --repo pkgs.paideia-os \
           --name ls \
           --version 1.0.0 \
           --pkg dist/pkg.tar \
           --manifest dist/manifest.pdxsig
```

`pkg push` writes to `pkgs.paideia-os/ls/1.0.0/pkg.tar` and
`pkgs.paideia-os/ls/1.0.0/manifest.pdxsig` under the release-
engineering account's cap. The `--repo` argument names the
mirror; a mirror-push against `pkgs.paideia-os` requires a
KIND_NETWORK cap narrowed to that host (per pkg's own caps.decl).

At today's tree state `pkg push` lands with pkg-repo M5 (issue
`pkg.M5-002 pkgs.paideia-os mirror push + .pdxdoc for doc pkg`);
this repo's M5-002 documents the runbook the automated push will
observe.

### 2.5 Tag `v1.0.0` on `main`

The M5-002 close commit is the tag point. `git tag v1.0.0` +
`git push --tags`. `pkg install ls` at 1.0.0 will resolve against
this tag once the pkg-repo M5 index publishes.

## 3. Byte-identity invariant

`pkg/design/manifest-format.md` §2 states: "`manifest.pdxsig`
sits inside the tar AND is served alongside it in the repository
-- both copies must be byte-identical, and the install body
cross-checks this." For ls-1.0.0 the check chain is:

```
sha3-256(dist/manifest.pdxsig)                                    (compose)
  == sha3-256(dist/pkg.tar :: extract "ls-1.0.0/manifest.pdxsig") (in-tar)
  == sha3-256(pkgs.paideia-os/ls/1.0.0/manifest.pdxsig)           (mirror)
  == sha3-256(pkgs.paideia-os/ls/1.0.0/pkg.tar
                 :: extract "ls-1.0.0/manifest.pdxsig")           (mirror in-tar)
```

The four hashes are byte-equal at release time and remain equal
across the mirror push. `pkg install ls` re-checks the equality
in step 5 of §4 below before committing the KIND_PDXFS_TXN scope
to `/pkgs/ls-1.0.0/`.

Failure modes:

- **Tar composition drift.** Two composes produced different
  bytes for the same manifest (missing `--source-date-epoch`,
  different tar tool). Caught at §2.3.
- **Mirror-side tamper.** The mirror-standalone
  `manifest.pdxsig` was replaced (attacker with mirror-write
  access). Caught by `pkg install`'s step-5 cross-check between
  the in-tar and standalone copies.
- **Tar-embedded tamper.** The tar-embedded copy was replaced
  after mirror upload. Same catch: the standalone copy would
  still hash to the original, so the cross-check fails.

In the scaffold epoch all four hashes are the same all-zero
sentinel -- the invariant holds trivially. At R32 it becomes a
real 32-byte equality gate on every install.

## 4. `pkg install ls` end-to-end path

Given a fresh system with `pkg` at 1.0.0 already installed
(bootstrapped per `design/tooling/plan.md` §6.5) and
`pkgs.paideia-os/ls/1.0.0/` populated per §2:

```
$ pkg install ls
```

The path pkg walks against the ls-1.0.0 mirror artefact:

  1. Resolve `ls@latest` via `pkgs.paideia-os/index.pdxsig` -> `ls@1.0.0`.
  2. Fetch `pkgs.paideia-os/ls/1.0.0/manifest.pdxsig` (standalone).
  3. Verify the standalone manifest per
     `pkg/design/manifest-format.md` §5 steps 1-11:
       a. Header magic, format_version, sizes.
       b. body_sha3_256 matches recomputed sha3-256(body).
       c. KV parse: presence of PKG_NAME, PKG_VERSION,
          AUTHOR_PUBKEY, ROOT_PUBKEY, CAPS_DECL_HASH.
       d. `ml_dsa_65_verify(author_sig, AUTHOR_PUBKEY,
          header || body)`.
       e. `ml_dsa_65_verify(root_sig, ROOT_PUBKEY,
          header || body)`.
       f. ROOT_FPR matches `/system/keys/paideia_root_pk.fpr`.
     **Scaffold-epoch outcome:** both `ml_dsa_65_verify` calls
     return `SIG_UNSIGNED_SCAFFOLD` (1) per blob-policy §1.7.
     Consumer discipline is "log and continue": pkg journals an
     `InstallProgressRecord` with
     `verdict = SIG_UNSIGNED_SCAFFOLD` per slot but permits the
     install.
  4. Fetch `pkgs.paideia-os/ls/1.0.0/pkg.tar`.
  5. Cross-check: extract in-tar `ls-1.0.0/manifest.pdxsig`;
     assert sha3-256 equality with the standalone copy fetched
     at step 2. **On mismatch:** abort with
     `PKG_ERR_MANIFEST_MISMATCH` (exit 5); no bytes touch
     `/pkgs/`.
  6. Mint `KIND_PDXFS_TXN` scope; extract every FILE_INVENTORY
     entry from the tar; hash each against its FILE_INVENTORY
     `sha3_256`. **On any mismatch:** abort the TXN, no rename.
  7. Atomic rename the TXN scope to `/pkgs/ls-1.0.0/`.
  8. Symlink `/pkgs/ls-1.0.0/bin/ls` into `/bin/ls`.
  9. Journal a `PkgInstallRecord` via `libpdx-audit` closing the
     install with `verdict = OK` (or the scaffold-epoch
     equivalent).
 10. `pkg list` now includes `ls-1.0.0`; `ls` is invocable from
     any shell whose caps.decl grants the four ls-side caps.

## 5. M5-002 close criterion + deferred live witness

**M5-002 closes when:**

- `design/mirror-push.md` (this file) commits.
- `tests/pkg_install_e2e.md` commits with the fixture matrix
  documenting the 10-step path in §4 -- one row per step, one
  column per (input state, expected outcome, scaffold-epoch
  observation).
- `.plans/m5-002-notes.md` commits.
- `STATUS.md` bumps M5-002 to LANDED + M5 milestone to CLOSED.
- The `v1.0.0` tag lands on `main` (the M5-002 commit is the
  tag point).

**Deferred to pkg-repo M5 (issue `pkg.M4-003` upgrades to a
live matrix at pkg.M5-002):**

- Live QEMU smoke of the full `install -> list -> verify ->
  remove -> verify absent` path. Requires:
    (a) pkg-repo M5 close (pkg publish + pkg push tooling),
    (b) a runnable shell (shell-repo M5 close),
    (c) a runnable doc (doc-repo M5 close so `pkg install ls`
        can be followed by `doc ls`),
    (d) mkfs.pdxfs + mount.pdxfs at runnable state so the
        `/pkgs/` mount can hold ls-1.0.0.
  ls-repo M5-002 ships the runbook + the matrix witness; the
  live pass is a pkg-repo M5-002 obligation ("QEMU smoke:
  install -> list -> verify -> remove -> verify absent" per
  `r49-r50-plan.md` §5.1).

## 6. Non-goals of M5-002

- **No `pkg publish` / `pkg push` implementation.** Both live at
  pkg-repo M5 per the runbook §2.
- **No `paideia-as release` implementation.** Lives at
  paideia-as v0.34 per `design/user/model.md` §11.2 (post-R32).
- **No index.pdxsig composition.** The mirror-level index is a
  pkg-repo M5 concern; ls contributes only the leaf artefact.
- **No mirror-side ACL enforcement.** The KIND_NETWORK cap
  narrowing on `pkg push` is a pkg-side concern; ls documents
  the shape but does not enforce it.
