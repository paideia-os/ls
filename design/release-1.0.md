# ls -- release-1.0 specification

**Wave:** R50  Milestone: M5 (signed 1.0 release)
**Issues:** [#15](https://github.com/paideia-os/ls/issues/15)
`ls.M5-001 dual-signed release + .pdxdoc` and
[#16](https://github.com/paideia-os/ls/issues/16)
`ls.M5-002 mirror push + verify \`pkg install ls\` works end-to-end`.
**Upstream design:**
  - `design/tooling/r49-r50-plan.md` §5.4 (paideia-os) -- ls milestone
    breakdown, cross-repo dependencies, KIND allocations.
  - `design/tooling/plan.md` §6 + `pkg/design/manifest-format.md`
    (paideia-os/pkg) -- the `manifest.pdxsig` byte-level wire spec
    every 1.0 release binds against.
  - `design/drivers/blob-policy.md` §1.3 + §1.7 (paideia-os) -- the
    dual-signature D1.a discipline and the scaffold-epoch
    (SIG_UNSIGNED_SCAFFOLD) verdict this release inherits.
  - `design/user/model.md` §11.2 (paideia-os) -- paideia-as
    v0.33-crypto-kdf bundle that provisions ML-DSA-65 verify.

## 0. Reading order

- §1 -- what "signed 1.0" means in the scaffold epoch and after R32.
- §2 -- the `manifest.pdxsig` wire shape for `ls-1.0.0` (header +
  body + sigblock, KV-record-by-KV-record).
- §3 -- release process: how the file at `dist/manifest.pdxsig` is
  composed, and how the two signatures are staged (scaffold epoch
  today; live at R32).
- §4 -- byte-identity invariant between the tar-embedded and mirror-
  standalone copies of `manifest.pdxsig` (M5-002 bridge to
  `design/mirror-push.md`).
- §5 -- what freezes at 1.0 and what stays 1.x-additive per
  `CHANGELOG.md` §"Compatibility rules from 1.0 forward".

## 1. What "signed" means at 1.0

D4 in `design/tooling/plan.md` §3 mandates every ls install carries
a *dual* signature: the author's key (`author_pk`) AND the paideia
manifest re-sign key (`paideia_root_pk`, from R32). Neither alone is
enough for `pkg install ls` to accept the package.

At the current tree state -- R50 Wave-2 close, pre-R32 -- neither
key exists as a runtime artefact. The signing chain is in the
**scaffold epoch** documented at `design/drivers/blob-policy.md` §1.7
(paideia-os):

- No ML-DSA-65 signing tool exists on-tree.
- No `paideia_root_pk` is provisioned to
  `/system/keys/paideia_root_pk.fpr`.
- No author key is provisioned to any per-user keyring.

Consequently, at 1.0 the two signature slots in
`dist/manifest.pdxsig` are **bytewise zero**. The pkg verifier at
step 9 + 10 of `pkg/design/manifest-format.md` §5 will invoke
`driver_sig_verify_algo(ML_DSA_65, header || body, sig, pk)` on each
slot and each will return `SIG_UNSIGNED_SCAFFOLD` (`1`), which is
**not** a pass -- it is a numerically distinct verdict that says
"structurally well-formed, provably NOT signed" per blob-policy §1.7.

Consumer discipline in the scaffold epoch:

- `pkg install ls` LOGS the outcome via `libpdx-audit`
  (`InstallProgressRecord` with `verdict = SIG_UNSIGNED_SCAFFOLD` per
  slot) but permits the install to proceed under the R29 "log and
  continue" rule (blob-policy §1.7 line "R29 consumer discipline").
- `pkg verify ls` prints the same verdict pair to stderr and returns
  a non-zero exit code so a downstream release-gate script never
  mistakes a scaffold artefact for a signed one.

At R32 the two signature slots are re-computed against a real
`author_pk` and `paideia_root_pk` and the manifest is re-emitted with
a new `created_unix_secs` field; the source tree does not change.
The 1.0.0 tag stays; the manifest is a re-signed 1.0.0.

## 2. `manifest.pdxsig` wire shape for ls-1.0.0

The layout follows `pkg/design/manifest-format.md` §3-§4 exactly.
Every integer is little-endian.

### 2.1 Header (64 bytes)

| Offset | Size | Field                | Value at 1.0.0                                        |
|--------|------|----------------------|-------------------------------------------------------|
| 0      | 8    | `magic`              | ASCII `"pdxsig\0\0"` = `0x00_00_67_69_73_78_64_70`    |
| 8      | 4    | `format_version`     | `1`                                                   |
| 12     | 4    | `header_flags`       | `0`                                                   |
| 16     | 8    | `body_len`           | measured at compose time (see §2.2 tag list)          |
| 24     | 16   | `body_sha3_256`      | sha3-256(body) -- **all-zero in the scaffold epoch**  |
| 40     | 8    | `sigblock_len`       | `4 + 3293 + 4 + 3293` = `6594`                        |
| 48     | 4    | `pubkey_len_author`  | `1952` (ML-DSA-65 pk at NIST security level 2)        |
| 52     | 4    | `pubkey_len_root`    | `1952`                                                |
| 56     | 8    | `created_unix_secs`  | `1755849600` = 2026-08-22T00:00:00Z (release day)     |

Note on `body_sha3_256`: at R32 the sha3-256 primitive is provisioned
alongside ml_dsa_65_verify; today the field is bytewise zero and the
verifier records the mismatch as `SIG_UNSIGNED_SCAFFOLD`-adjacent
diagnostics (the verifier's step 6 fails but never in a way the
scaffold epoch treats as an accept-block).

### 2.2 Body (KV records, order fixed for byte-repro)

Every record is `u16 kv_tag | u16 kv_len | bytes kv_value`. Order
below is the byte order in the composed body -- the KV record
grammar in `pkg/design/manifest-format.md` §4.2 permits any order,
but `ls-1.0.0` freezes the order below so the byte hash is stable
across re-composes on the same source tree.

| # | Tag    | Name                | Value at 1.0.0                                          |
|---|--------|---------------------|---------------------------------------------------------|
| 1 | 0x0001 | `PKG_NAME`          | UTF-8 `"ls"`                                            |
| 2 | 0x0002 | `PKG_VERSION`       | UTF-8 `"1.0.0"`                                         |
| 3 | 0x0003 | `PKG_REPO_URL`      | UTF-8 `"https://github.com/paideia-os/ls"`              |
| 4 | 0x0004 | `PAIDEIA_AS_VER`    | UTF-8 `"0.33-crypto-kdf"` (compliance floor per M1-001) |
| 5 | 0x0010 | `AUTHOR_PUBKEY`     | 1952 bytes -- **all-zero in the scaffold epoch**        |
| 6 | 0x0011 | `AUTHOR_FPR`        | 32-byte sha3-256(AUTHOR_PUBKEY) -- **all-zero**         |
| 7 | 0x0012 | `AUTHOR_EXPIRY`     | `0` (never)                                             |
| 8 | 0x0020 | `ROOT_PUBKEY`       | 1952 bytes -- **all-zero in the scaffold epoch**        |
| 9 | 0x0021 | `ROOT_FPR`          | 32-byte sha3-256(ROOT_PUBKEY) -- **all-zero**           |
|10 | 0x0022 | `ROOT_EXPIRY`       | `0` (never)                                             |
|11 | 0x0030 | `CAPS_DECL_HASH`    | sha3-256(caps.decl) -- **all-zero in the scaffold epoch** |
|12 | 0x0031 | `DEPS_LIST_HASH`    | sha3-256(deps.list as-composed from manifest.pdxproj)   |
|13 | 0x0040 | `FILE_INVENTORY`    | one per file in `/pkgs/ls-1.0.0/` (see §2.2.1)          |
|14 | 0x00F0 | `BUILD_REPRODUCER`  | UTF-8 `"paideia-as-v0.33-crypto-kdf; SOURCE_DATE_EPOCH=1755849600"` |

At the scaffold epoch every hash field carries the all-zero sentinel
so a downstream reader can distinguish "unpopulated by design" from
"populated but wrong" -- the same discipline blob-policy §1.7 pins
for the signature slots.

#### 2.2.1 `FILE_INVENTORY` records

One record per installed file. `mode` mirrors POSIX bits + Paideia
type nibble; `path` is relative to `/pkgs/ls-1.0.0/`. Files at 1.0.0:

| # | Path                        | mode (octal)  | sha3-256 at 1.0.0 |
|---|-----------------------------|---------------|-------------------|
| 1 | `bin/ls`                    | 0100755       | all-zero (scaffold) |
| 2 | `caps.decl`                 | 0100644       | all-zero (scaffold) |
| 3 | `doc/ls.pdxdoc`             | 0100644       | all-zero (scaffold) |
| 4 | `manifest.pdxsig`           | 0100644       | all-zero (scaffold) |

At R32 the sha3 slots are populated from the actual file bytes; the
inventory shape does not change.

### 2.3 Sigblock (6594 bytes)

Layout per `pkg/design/manifest-format.md` §4.4:

  u32 sig_len_author = 3293
  bytes author_sig[3293]              -- ML-DSA-65 sig; all-zero
  u32 sig_len_root   = 3293
  bytes root_sig[3293]                -- ML-DSA-65 sig; all-zero

Both signatures cover bytes `[0, 64 + body_len)` of the file -- the
sigblock itself is not signed. In the scaffold epoch both slots are
all-zero and each verifies as `SIG_UNSIGNED_SCAFFOLD` per §1.

## 3. Release process

### 3.1 Compose (paideia-as release, scaffold epoch)

```
$ paideia-as build src/*.pdx -o build-out/ls          # produce binary
$ paideia-as release --scaffold-epoch \
                     --name ls \
                     --version 1.0.0 \
                     --caps caps.decl \
                     --pdxdoc doc/ls.pdxdoc \
                     --paideia-as-ver 0.33-crypto-kdf \
                     --source-date-epoch 1755849600 \
                     --output dist/manifest.pdxsig
```

The `--scaffold-epoch` flag tells `paideia-as release` to emit
all-zero for the two signature slots + the two pubkey slots + every
sha3 field, per §1. This is the exact one-flag hook that flips off at
R32; the same command without `--scaffold-epoch` invokes the R32
signing chain (which reads the user's Argon2id-KDF-unlocked
`user_sk` for `author_sig` and dispatches to the release-engineering
service for `root_sig`).

`paideia-as release` itself lands with `paideia-as v0.34` (post-R32)
per `design/user/model.md` §11.2; at today's tree state, M5 ships the
release **specification** (this document + the CHANGELOG entry + the
.pdxdoc) so a downstream `paideia-as release` at v0.34 composes the
file byte-deterministically. This is the same pattern
`design/security/pe-secure-boot-signing.md` established for R28
(scaffold-first, live-at-R32).

### 3.2 Stage under `dist/`

The composed manifest lands at `dist/manifest.pdxsig`. `dist/` is
git-ignored at 1.0 (composed artefacts are not source); the M5
release process publishes `dist/manifest.pdxsig` to the mirror per
§4 + `design/mirror-push.md`.

### 3.3 Tag

The M5-001 commit tags `v1.0.0` on `main`. The tag is what
`pkg install ls@1.0.0` will resolve against once the pkg-repo M5
lands. Version discipline: `manifest.pdxproj:version` + `git tag` +
`CHANGELOG.md:[1.0.0]` all move together in a single commit or in a
tight commit sequence gated by the M5-001 close (this repo's analog
of `feedback_paideia_as_version_discipline`).

## 4. Byte-identity invariant (bridge to M5-002)

`pkg/design/manifest-format.md` §2 states: "`manifest.pdxsig` sits
inside the tar AND is served alongside it in the repository -- both
copies must be byte-identical, and the install body cross-checks
this." For ls-1.0.0 that invariant is:

  sha3-256(dist/manifest.pdxsig)
    ==
  sha3-256(pkgs.paideia-os/ls/1.0.0/manifest.pdxsig)
    ==
  sha3-256(pkgs.paideia-os/ls/1.0.0/pkg.tar :: manifest.pdxsig)

At the scaffold epoch, the check is `all-zero == all-zero == all-
zero` and passes trivially; at R32 the check is a real 32-byte hash
equality and is enforced by `pkg install` before any file lands
under `/pkgs/ls-1.0.0/`.

`design/mirror-push.md` §3 pins the tar composition order so the
byte-embedded copy of `manifest.pdxsig` inside `pkg.tar` is exactly
the same bytes as the standalone `manifest.pdxsig` served alongside.

## 5. What freezes at 1.0

Per `CHANGELOG.md` §"Contract frozen at 1.0" and §"Compatibility
rules from 1.0 forward":

- **Additive-only.** New KV tags (0x0100+, dense allocation from the
  low end), new flags, new schema fields (via
  `libpdx-semantic-pipe` version-tolerance rules) -- all safe on
  1.x, no re-sign required.
- **Semantic-change.** Any change to the meaning of an existing
  flag, an existing exit-code row, or an existing schema field is a
  2.0 line + a new `manifest.pdxsig` with `format_version > 1`.
- **Crypto rotation.** ML-DSA-65 -> higher-level variant is a
  `manifest.pdxsig` `format_version` bump; ls does not initiate the
  rotation -- it follows the pkg format cadence.
- **Toolchain floor.** `PAIDEIA_AS_VER` at 1.0 is
  `0.33-crypto-kdf`; a floor bump (e.g. to `0.34-release-signer` at
  R32) is a re-sign event, not a source-tree edit.

## 6. Non-goals of the M5-001 release spec

- **No live signing.** ML-DSA-65 signing is an R32 concern; today
  the tree ships the scaffold-epoch manifest + this spec.
- **No repository index sign.** `index.pdxsig` at
  `pkgs.paideia-os/index.pdxsig` (per `pkg/design/manifest-format.md`
  §2) is a pkg-repo M5 concern; ls contributes only the leaf
  manifest.
- **No compression.** `pkg.tar` at 1.0 is uncompressed
  (`pkg/design/manifest-format.md` §8).
