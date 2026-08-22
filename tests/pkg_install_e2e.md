# tests/pkg_install_e2e.md -- `pkg install ls` end-to-end witness

**Wave:** R50  Milestone: M5 (signed 1.0 release)
**Issue:** [#16](https://github.com/paideia-os/ls/issues/16)
`ls.M5-002 mirror push + verify \`pkg install ls\` works end-to-end`.
**Upstream:** `design/mirror-push.md` §4 (this repo) + `pkg/design/
install-flow.md` (paideia-os/pkg).

## 0. Purpose

M5-002 is a spec-and-runbook close (§5 of `design/mirror-push.md`).
The **live QEMU smoke** of `pkg install ls` requires the pkg-repo
M5 tooling (`pkg publish`, `pkg push`) plus a runnable shell + doc
+ mount.pdxfs; each is at M4 today. This file is the matrix witness
that:

- Enumerates every observable in the 10-step install path from
  `design/mirror-push.md` §4.
- Records the scaffold-epoch expectation for each step (what the
  today-tree observes when the pre-R32 signing chain is in play).
- Names the exact promotion criterion each row transitions on
  when the live substrate arrives (typically: what verdict flips
  from `SIG_UNSIGNED_SCAFFOLD` to `SIG_OK`).

The matrix is a **spec-only fixture**: no `.pdx` code, no runtime
harness. The live counterpart -- the paideia-as `.pdx` test
harness that exercises the same 10 rows against a live pkg
substrate -- lands at pkg-repo M5-002 per `design/mirror-push.md`
§5.

## 1. Preconditions

Each row of the matrix assumes:

- `pkg` at 1.0.0 is installed on the target system (bootstrap
  per `design/tooling/plan.md` §6.5 has run).
- `pkgs.paideia-os/ls/1.0.0/pkg.tar` and
  `pkgs.paideia-os/ls/1.0.0/manifest.pdxsig` have been staged
  per `design/mirror-push.md` §2.
- `/system/keys/paideia_root_pk.fpr` exists (scaffold epoch: an
  all-zero file; R32: the real 32-byte fingerprint).
- The invoking user's caps.decl grants pkg the four caps pkg
  needs: `KIND_USER`, `KIND_TTY(write)`, `KIND_PDXFS_FILE(write,
  /pkgs)`, `KIND_NETWORK(fetch, pkgs.paideia-os)`.

## 2. Matrix

| # | Step (per mirror-push.md §4)                             | Observable                                              | Scaffold-epoch expectation                                                   | R32 flip                                                                             |
|---|----------------------------------------------------------|---------------------------------------------------------|------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| 1 | Resolve `ls@latest` via `index.pdxsig`                   | Resolved version string                                 | `"1.0.0"`                                                                    | Same.                                                                                |
| 2 | Fetch standalone `manifest.pdxsig`                       | HTTP GET status + byte length                           | `200 OK`; length = `64 + body_len + 6594` (~13 KB)                           | Same. (Pubkey slots grow if a level-3/5 rotation lands, per format §6.)              |
| 3 | Header parse                                             | `header.magic` + `format_version` + `header_flags`      | `"pdxsig\0\0"` + `1` + `0`                                                   | Same.                                                                                |
| 3 | Body parse (KV walk)                                     | Presence of PKG_NAME / PKG_VERSION / AUTHOR_PUBKEY / ROOT_PUBKEY / CAPS_DECL_HASH | All 5 present                                                             | Same.                                                                                |
| 3 | body_sha3_256 check                                      | Recomputed sha3-256(body) == header.body_sha3_256       | Both all-zero -> equal (trivial pass)                                        | Real 32-byte equality; mismatch -> `PKG_ERR_BODY_HASH` (exit 5).                     |
| 3 | `ml_dsa_65_verify(author_sig, AUTHOR_PUBKEY, ...)`       | Verdict per blob-policy §1.7                            | `SIG_UNSIGNED_SCAFFOLD` (1) -- LOG-AND-CONTINUE                              | `SIG_OK` (0) or `SIG_VERIFY_FAIL` (0xFFFFFD88) -> abort on fail.                     |
| 3 | `ml_dsa_65_verify(root_sig, ROOT_PUBKEY, ...)`           | Verdict per blob-policy §1.7                            | `SIG_UNSIGNED_SCAFFOLD` (1) -- LOG-AND-CONTINUE                              | `SIG_OK` (0) or `SIG_VERIFY_FAIL` -> abort on fail.                                  |
| 3 | ROOT_FPR check against `/system/keys/paideia_root_pk.fpr`| Byte equality of two 32-byte fingerprints               | Both all-zero -> equal (trivial pass)                                        | Real 32-byte equality; mismatch -> `PKG_ERR_ROOT_FPR` (exit 5).                      |
| 4 | Fetch `pkg.tar`                                          | HTTP GET status + byte length                           | `200 OK`; length = ustar rounded (bin/ls + caps.decl + doc + manifest)       | Same.                                                                                |
| 5 | Cross-check: in-tar manifest == standalone manifest      | Byte-equality of the two manifest copies                | All-zero == all-zero -> equal                                                | Real 32-byte hash equality; mismatch -> `PKG_ERR_MANIFEST_MISMATCH` (exit 5).        |
| 6 | Mint `KIND_PDXFS_TXN`                                    | TXN cap handed to pkg                                   | TXN handed; scaffold epoch behaves identically                               | Same.                                                                                |
| 6 | Extract + hash-check each FILE_INVENTORY entry           | 4 hashes, one per file                                  | Each `sha3_256` field all-zero -> equal to any file's placeholder            | Real per-file 32-byte equality; any mismatch -> abort the TXN, no rename.            |
| 7 | Atomic rename TXN scope -> `/pkgs/ls-1.0.0/`             | `/pkgs/ls-1.0.0/` exists post-rename                    | Directory populated with 4 files                                             | Same.                                                                                |
| 8 | Symlink `/pkgs/ls-1.0.0/bin/ls` -> `/bin/ls`             | `readlink /bin/ls`                                      | `/pkgs/ls-1.0.0/bin/ls`                                                      | Same.                                                                                |
| 9 | Journal `PkgInstallRecord` via `libpdx-audit`            | Audit record present in `/system/audit/user-events/`    | Record with `verdict = SIG_UNSIGNED_SCAFFOLD` per slot                       | Record with `verdict = SIG_OK` per slot.                                             |
|10 | `pkg list` includes `ls-1.0.0`                           | `pkg list` output line                                  | `ls-1.0.0` present                                                           | Same.                                                                                |
|10 | Invoke `ls` from a shell with the four ls caps           | Exit code + first line of stdout                        | Exit `0`; stdout is the entry list (no error)                                | Same.                                                                                |
|10 | `doc ls` renders the man-equivalent                      | First line of `doc ls` output                           | Reads `doc/ls.pdxdoc`; renders `ls` synopsis                                 | Same.                                                                                |

## 3. Failure modes exercised by the matrix

Every failure the matrix asserts pkg-side, spelled out:

| Failure                                    | Detected at row | Expected outcome                            |
|--------------------------------------------|-----------------|---------------------------------------------|
| Standalone manifest tampered post-mirror   | Row 5 (cross-check)          | Exit 5 (`PKG_ERR_MANIFEST_MISMATCH`); no `/pkgs/` write. |
| In-tar manifest tampered post-mirror       | Row 5 (cross-check)          | Same.                                       |
| Any FILE_INVENTORY hash mismatch (R32)     | Row 6 (per-file hash)        | TXN abort; no `/pkgs/ls-1.0.0/` rename.     |
| body_sha3_256 mismatch (R32)               | Row 3 (body-hash step)       | Exit 5 (`PKG_ERR_BODY_HASH`).               |
| author_sig verify-fail (R32)               | Row 3 (author sig step)      | Exit 5 (`PKG_ERR_AUTHOR_SIG`).              |
| root_sig verify-fail (R32)                 | Row 3 (root sig step)        | Exit 5 (`PKG_ERR_ROOT_SIG`).                |
| ROOT_FPR mismatch (R32)                    | Row 3 (fpr step)             | Exit 5 (`PKG_ERR_ROOT_FPR`).                |
| Missing `/pkgs/` write cap                 | Row 6 (TXN mint)             | Exit 4 (cap denied).                        |
| Missing `pkgs.paideia-os` fetch cap        | Row 2 or 4 (HTTP fetch)      | Exit 4 (cap denied).                        |
| ls-side caps.decl missing at invocation    | Row 10 (`ls` invoke)         | Exit 4 (cap denied) from ls, not from pkg.  |

## 4. Non-observable in this fixture

- **Fetch retry semantics.** Transient HTTP failures + retry are
  a `libpdx-elevate` / pkg-side concern; the matrix rows assume
  a clean first-try fetch.
- **`pkg upgrade`.** Row 8 (`/bin/ls` symlink) tolerates an
  existing symlink to a previous version and swings the target
  atomically; the "upgrade" path is a separate matrix at
  pkg-repo M4.
- **`pkg remove ls`.** The M4-003 QEMU smoke for pkg exercises
  install-then-remove; ls's M5-002 exercises install only.
- **`pkg verify ls` post-install.** A post-install verify is a
  degenerate case of steps 3-6 with the local install as the
  source; matrix covers the install path only.

## 5. Bridge to live pkg-repo M5-002

Every row in the §2 matrix has a paideia-as-side observation the
pkg-repo M5-002 live harness will assert against. The live harness
lives at `pkg/tests/e2e/ls_install_smoke.pdx` (per pkg-repo
convention) and reads THIS file's row order to compose its own
assertions -- the ls-side spec and the pkg-side harness stay
tightly coupled by row index.

Promotion at pkg-repo M5-002:

- Each `SIG_UNSIGNED_SCAFFOLD` cell in column 4 promotes to
  `SIG_OK` in column 5 -- the pkg-side harness asserts the
  post-R32 outcome.
- The "trivial pass" cells become real hash equalities.
- The "log and continue" behaviour becomes "abort on any
  verdict != SIG_OK".

No source-tree edit in the ls repo is required for the promotion;
the same 1.0.0 tag remains the resolvable target of
`pkg install ls@1.0.0`.
