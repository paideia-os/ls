# ls.M5-002 -- implementation notes

**Issue:** #16 -- mirror push + verify `pkg install ls` works
end-to-end.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M5-002 line
502 (paideia-os).

## What landed

- `design/mirror-push.md` -- the runbook + invariants for staging
  `pkgs.paideia-os/ls/1.0.0/`. Sections:
    - §1 -- mirror tree layout (pkg.tar contents + standalone
      manifest.pdxsig).
    - §2 -- five-step release-day runbook (build -> compose
      manifest -> compose tar -> verify byte-identity -> push
      -> tag).
    - §3 -- the four-way byte-identity invariant between the
      compose, in-tar, mirror-standalone, and mirror-in-tar
      copies of manifest.pdxsig.
    - §4 -- the `pkg install ls` end-to-end path spelled out
      step by step against ls-1.0.0.
    - §5 -- M5-002 close criterion + the deferred live-QEMU
      witness at pkg-repo M5.
    - §6 -- non-goals (pkg publish tooling, paideia-as release
      tooling, index composition, mirror ACL).
- `tests/pkg_install_e2e.md` -- the fixture matrix for the
  end-to-end path. 17 matrix rows, one per observable in the
  10-step install; each row records the scaffold-epoch expectation
  and the R32 promotion criterion. Bridges to the pkg-repo M5-002
  live harness which will read this file's row order to compose
  its own assertions.
- `.plans/m5-002-notes.md` -- this file.
- `STATUS.md` -- bumped M5-002 to LANDED + M5 milestone to
  CLOSED; ls now at 1.0.0.
- `README.md` -- bumped status line to `1.0.0 (M5 closed)`.

Post-commit: `v1.0.0` tag lands on `main` (per §5 of
`design/mirror-push.md`, the M5-002 commit is the tag point).

## Entry-point contract

None -- M5-002 is a spec + runbook + witness close, mirroring
M5-001's discipline. No new `.pdx` files, no new module entry
points. The mirror-push runbook, the byte-identity invariant, and
the end-to-end matrix compose the M5 close shape a downstream
pkg-repo M5-002 live harness consumes when the pkg publish / pkg
push tooling lands.

## Design decisions

- **Runbook + matrix over live harness at ls-repo M5.** The live
  QEMU smoke of `pkg install ls` requires four sibling repos at
  runnable state (`pkg` M5, `shell` M5, `doc` M5, `mount.pdxfs`
  runnable). None is available today; every one is on the R50/R51
  arc. The ls-repo can either:
    (a) block M5 close on the four cross-repo dependencies
        (violates the memory `feedback_autonomous_tempo` --
        "run continuously across every open issue and
        milestone"), OR
    (b) ship the spec + runbook + fixture matrix, then close
        M5, and let the live harness land at pkg-repo M5-002
        against ls-1.0.0 as a byte-frozen artefact.
  M5-002 takes option (b). The matrix in
  `tests/pkg_install_e2e.md` §2 is the promotion table pkg-repo
  M5-002 will exercise; every row names its scaffold-epoch
  observation and its R32 flip explicitly, so the pkg-side live
  harness has an unambiguous per-row assertion to make.

- **`tests/pkg_install_e2e.md` as a markdown fixture, not
  `.pdx`.** Every M4 fixture in this repo is a `.pdx` module
  (`ColorFixtures`, `OwnerFixtures`, `ExitMatrix`,
  `SchemaGolden`). M5-002's fixture is markdown because:
    (a) The observable it asserts against is the pkg-side
        install path, not an ls-side entry point. There is no
        ls module a `.pdx` fixture could call.
    (b) The matrix is a cross-repo contract -- the pkg-side
        live harness reads it to compose assertions. Markdown
        is the format both a human reviewer and the pkg-side
        toolchain can consume without a version-pinned parser.
    (c) The paideia-as `test` runner does not execute markdown,
        so a `.pdx` fixture would need to no-op or synthesise
        the observable itself -- both defeat the fixture's
        purpose.
  This is the same discipline `cp/tests/*.md` uses for its
  three M4 test-spec markdown files (per `cp/manifest.pdxproj`
  comment: "three test-spec markdown files under tests/
  covering the 18 matrix rows the plan §5.6 M4 line
  enumerates; no cp code change at M4, observation hooks
  already exposed by the M2/M3 modules").

- **Mirror-push runbook is manual today.** `pkg publish` /
  `pkg push` land with pkg-repo M5 (issue `pkg.M5-002`); the
  M5-002 close for ls documents the manual runbook the automated
  push will observe. The runbook step 2.2 pins the tar
  composition order + the reproducibility flags -- both are
  load-bearing for the byte-identity invariant. An automated
  push that ignored either would break the pkg-repo M5-002 live
  cross-check at step 5 of the install path.

- **`--source-date-epoch=1755849600` (2026-08-22T00:00:00Z).**
  Same value as `manifest.pdxsig::created_unix_secs` from
  `design/release-1.0.md` §2.1. The mirror-push runbook, the
  release-1.0 spec, and the CHANGELOG date all agree on this
  epoch second -- a downstream reproducibility check across
  the three artefacts must observe the same date.

- **Byte-identity invariant expressed as a four-way hash
  chain, not a two-way check.** The pkg-side design doc talks
  about "in-tar and standalone" (2 copies); ls's runbook adds
  "compose-side" and "mirror-in-tar" so a compose drift
  between the developer's build and the mirror push is caught
  at §2.3 of the runbook, before the push happens. The
  developer-side hash equality between `dist/manifest.pdxsig`
  and `stage/ls-1.0.0/manifest.pdxsig` catches a `cp -p` that
  didn't happen (would strip the executable bit) or a tar
  compose that pulled from a different source path than the
  developer thinks.

## paideia-as conformance

Not applicable -- no `.pdx` files at M5-002. The mirror-push
runbook is bash/paideia-as CLI; the fixture matrix is markdown.

## What is NOT in this file

- **A live `pkg install ls` execution.** Deferred to pkg-repo
  M5-002. The matrix at `tests/pkg_install_e2e.md` §2 is the
  contract the pkg-side harness will exercise.
- **`pkg publish` / `pkg push` implementation.** Lives at
  pkg-repo M5.
- **`paideia-as release` implementation.** Lives at paideia-as
  v0.34 (post-R32).
- **index.pdxsig composition for pkgs.paideia-os.** A pkg-repo
  M5 concern.
- **Mirror ACL enforcement.** A KIND_NETWORK cap narrowing on
  the push side; pkg's own caps.decl governs.
- **Live TTY byte-pump write of `ls`'s output post-install.**
  Waits on R49.M1 flipping `sys_write(fd=1)` to
  `cap_invoke(KIND_TTY, TTY_OP_WRITE)`.

## What's next

- **v1.0.0 tag.** Lands immediately after the M5-002 commit on
  `main`. `git tag v1.0.0 && git push --tags`.
- **pkg-repo M5-002 close.** Composes `pkg publish` + `pkg push`
  + the live e2e harness at `pkg/tests/e2e/ls_install_smoke.pdx`
  that reads THIS file's `tests/pkg_install_e2e.md` §2 matrix
  and asserts each row against a live pkg substrate.
- **R32 re-sign.** At R32 the scaffold-epoch cells in the
  matrix promote to real hash / verify outcomes; no ls-side
  source-tree edit is required (per `design/release-1.0.md`
  §1).
