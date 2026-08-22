# ls.M4-003 — implementation notes

**Issue:** #13 — exit-code matrix (empty=0, missing=2, cap-denied=4).
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M4-003 line
499 (paideia-os).

## What landed

- `src/exit_map.pdx` — new `ExitMap` module. `exit_map(ls_code) ->
  u64` collapses every 0xFFFFEBxx sentinel Ls declares into the
  I4 exit-code vocabulary (0 / 2 / 3 / 4) per
  `design/architecture.md` §6:
    - LS_OK / AS_OK / LS_RUN_STUB → 0
    - AS_ERR_BAD_ARGV / PARSER_REJECT / UNKNOWN_FLAG /
      UNSUPPORTED_SHORT / LS_ERR_BAD_PATH → 2 (usage error,
      includes the ls-side "missing" gate)
    - LS_ERR_READDIR / LS_ERR_TTY_WRITE → 4 (cap denied /
      substrate refusal; -EBADF on readnext from the shell not
      populating the dir cap slot maps here)
    - LS_ERR_EMIT_BIND / LS_ERR_EMIT_SEND / LS_ERR_AUDIT → 3
      (system error, library / IPC broker failure)
    - Unknown 0xFFFFEBxx → 3 (unclassified failure must not
      look like success)
- `tests/exit_matrix.pdx` — new `ExitMatrix` module. 13 rows in
  `_em_cases` covering every declared sentinel; each row is
  `(ls_code, expected_exit_code)`. The three lines the issue text
  pins ("empty=0", "missing=2", "cap-denied=4") are cases 0, 7,
  8 respectively.

## Entry-point contract

```
exit_matrix_case_count() -> u64            // 13
exit_matrix_run(case_idx) -> u64           // 0 = pass; sentinel = fail
exit_matrix_verify_all() -> u64            // fail-fast walk
```

Case-fail sentinels:

  - `EM_ERR_MISMATCH`     (0xFFFFEBD0) + case_idx
  - `EM_ERR_BAD_CASE_IDX` (0xFFFFEBDF)

## Design decisions

- **ExitMap in `src/`, ExitMatrix in `tests/`.** The mapping is
  a production-code concern (the eventual R14b `_start` frame
  will call `exit_map` between `ls_dispatch` and `sys_exit`), so
  it lives at `src/exit_map.pdx`. The matrix is a fixture-only
  concern (verify the mapping is what M4-003 pins), so it lives
  at `tests/exit_matrix.pdx`. When R14b `_start` lands, the
  wiring is two lines (`call ls_dispatch; call exit_map; call
  sys_exit`) and the M4-003 fixture continues to guard the
  mapping across every future refactor.
- **"Missing" maps to 2 via LS_ERR_BAD_PATH, not via
  LS_ERR_READDIR.** At M3 the ls-side missing-path gate returns
  LS_ERR_BAD_PATH when `path_ptr` is non-null but points at an
  empty string. A truly missing dir (path resolves to nothing)
  is intercepted by the shell BEFORE it hands ls a cap; ls
  never runs. LS_ERR_READDIR is reserved for substrate refusals
  (`sys_pdxfs_dir_readnext` returned -errno) which are cap-
  denied by the M3 mapping — includes both -EBADF (cap slot not
  populated) and any other errno; a future refactor may split
  these when Runner threads errno through, at which point the
  fixture gains a new case and the mapping table gains a new
  entry.
- **"Unknown → 3" fall-through, not "unknown → 0".** An
  unclassified 0xFFFFEBxx MUST NOT look like success to a shell
  script that gates on exit == 0. Routing unknown to system-
  error (3) rather than to cap-denied (4) leans on the "which
  layer failed" convention — an unclassified failure signals
  "something upstream is broken" (system error), not "you lack
  permission" (cap denied).
- **Large-immediate compare via r10 staging.** Every 0xFFFFEBxx
  sentinel is a large imm64 that does not fit in a sign-extended
  imm32 (per paideia-as `cmp reg, imm <= 0x7FFFFFFF` rule).
  `exit_map`'s 13 compares each stage via `mov r10, imm64; cmp
  rdi, r10; je ...` — the same idiom `Dispatch::ls_dispatch`
  uses for its AS_OK compare at `src/dispatch.pdx`.

## paideia-as conformance

- `ExitMap` + `ExitMatrix` PascalCase basenames.
- No `test` mnemonic. Zero-checks use `cmp reg, 0`.
- `cmp reg, imm` immediates: 13 (case cap), 16 (row stride), 4
  (byte cap). All fit imm32. Every 0xFFFFEBxx sentinel stages
  via `mov r10, imm64`.
- No byte reads (all data 8-aligned in u64 lanes).
- `r11` scratch for LEA; `r10` for compare staging.
- Prologues + alignment: `exit_map` is leaf (no callee-save);
  `exit_matrix_run` 3 pushes + `sub rsp, 16` pad (48, aligned);
  `exit_matrix_verify_all` 2 pushes + pad (32, aligned).

## What is NOT in this file

- The eventual R14b `_start` frame. The mapping is pinned; the
  frame lands at paideia-os R14b bootstrap and calls `exit_map`.
- Errno-through-Runner threading. When Runner learns to
  distinguish -EBADF from -ENOENT and propagate that
  distinction through LS_ERR_READDIR, `exit_map` gains an extra
  argument (or a sub-sentinel) and the M4-003 matrix gains new
  cases. Today's table locks the current shape.
- Cross-tool exit-code drift detection. Every tool has its own
  0xFFFFxxxx band (elevate=EA, ls=EB, shell=EC, kernel=ED); a
  future tests/paideia-os-wide exit-map fixture would ensure the
  four bands stay disjoint. Outside ls's M4 scope.
