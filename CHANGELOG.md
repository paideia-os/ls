# ls -- CHANGELOG

Signing is performed at `pkgs.paideia-os` mirror-push time (see
`design/mirror-push.md`); the in-tree release does NOT carry a signed
`manifest.pdxsig`. The CHANGELOG entry moves in lock-step with the
version stamp in `manifest.pdxproj` and the git tag; the signed
`manifest.pdxsig` is composed against those inputs at the mirror push
and stored under `pkgs.paideia-os/ls/<version>/`.

## [Unreleased]

Post-1.1.8 items on the Enhancement v1.x wave
(`design/enhancement-plan.md`). No frozen 1.0 interface (argv surface,
exit-code map, wire body shape, `caps.decl`) changes in this section.

## [1.1.9] -- 2026-09-06 -- centralize the owner-row honest gap (ls.ENH-008) <a id="119"></a>

**1.1.9.** `ls -l` and the semantic-pipe wire record still report owner
row 0 for every entry -- that has NOT changed, and could not change
without a kernel-side schema bump (see "Kernel schema state" below).
What changed is that the three places that previously hardcoded the
literal 0 inline (`Runner::runner_ls`'s `-l` text path,
`SemanticEmit::sem_emit_entry`'s wire path, `SemanticEmit::
sem_emit_wire_compose`'s compose-only sibling) now all call one named,
documented, fixture-pinned function instead:
`OwnerCol::owner_col_owner_row_from_entry`.

### Added

- **`OwnerCol::owner_col_owner_row_from_entry`** (`src/owner_col.pdx`)
  -- an honest pass-through accessor: `(kernel_entry_ptr: u64) -> u64`,
  leaf, effects `{}`, always returns 0. Same discipline as
  `SortOptions::sort_options_by_mtime` / `sort_options_by_size`
  (`src/sort_options.pdx`, ls.ENH-016) for the identical reason -- the
  kernel's `PdxFsDirEntry` record is frozen at inode@0, kind@8,
  name_len@16, name@24 (128 bytes total; see paideia-os
  `src/kernel/core/cap/pdxfs_dir_iter.pdx` SECTION 1, "FROZEN LAYOUT
  (unchanged since R42-PREP-008)") and carries no owner/uid field
  anywhere. `kernel_entry_ptr` is accepted as a real argument (not
  folded away) so the future upgrade -- `PdxFsDirEntry` growing an
  owner field, or a `sys_pdxfs_stat_by_inode` follow-up call -- is a
  one-function-body edit rather than a three-call-site
  search-and-replace.
- **`tests/owner_fixtures.pdx`** sub-matrix C (cases 9-10, new) --
  trip-wire goldens pinning the honest gap: an all-zero 128-byte
  kernel record AND a densely-populated one (every byte `0xFF`,
  including bytes past where `name_len` would bound a real name) both
  must return 0 from `owner_col_owner_row_from_entry`. The populated
  case is what proves the function truly never dereferences
  `kernel_entry_ptr` rather than coincidentally landing on 0 against a
  blank fixture. `OF_CASE_COUNT` moves 9 -> 11.

### Changed

- **`Runner::runner_ls`** (`src/runner.pdx`, `rn_ls_render_long`) --
  the `-l` text path's owner_row write into `_rn_lf_extra_scratch`
  now calls `owner_col_owner_row_from_entry(&_rn_entry_buf)` instead of
  `xor rax, rax`. The call runs before `kind_mode_flags` is built into
  `r10` (a caller-save register that would otherwise be live across
  it), using only caller-save registers so none of the function's six
  callee-save carriers are disturbed.
- **`SemanticEmit::sem_emit_entry`** / **`sem_emit_wire_compose`**
  (`src/semantic_emit.pdx`) -- the `owner_target_ptr` qword at wire
  offset 136 is now `owner_col_owner_row_from_entry(kernel_entry_ptr)`
  instead of an inline placeholder. Both call sites were already
  aligned for a nested call (`sem_emit_wire_compose`'s `sub rsp, 8` pad
  existed specifically "for parity with sem_emit_entry" against this
  exact future); no alignment padding needed to change.

### Kernel schema state (honest gap, unchanged)

`PdxFsDirEntry` -- the 128-byte record `sys_pdxfs_dir_readnext`
(sysno 72) fills and every `ls` consumer reads -- does NOT carry a
uid/owner field. Confirmed directly against paideia-os
`src/kernel/core/cap/pdxfs_dir_iter.pdx` SECTION 1 at HEAD: the frozen
layout is `inode@0` (u64), `kind@8` (u64), `name_len@16` (u64),
`name@24` (u8[104]) -- exactly 128 bytes, nothing else. Retiring the
owner placeholder for real needs either (a) that record growing an
owner field, or (b) a `sys_pdxfs_stat_by_inode` syscall `ls` can call
per entry -- both are paideia-os kernel work, tracked as this issue's
own "kernel" dependency. This release does the honest, available half:
replacing three scattered inline literals with one reviewable,
documented, trip-wired function, so that future kernel-side landing is
a one-function-body edit instead of a three-file search-and-replace.

## [1.1.8] -- 2026-09-06 -- multi-path listing, `ls a b c` (ls.ENH-014) <a id="118"></a>

**1.1.8.** `ls a b c` now iterates every positional path argument
instead of silently ignoring everything past the first. Each path
after the first is preceded by a blank line and a `<path>:` header
(GNU `ls` convention); a single explicit path, or none at all, stays
byte-identical to pre-1.1.8 output.

### Added

- **`RecurseHeader::multipath_header_compose`**
  (`src/recurse_header.pdx`) -- composes the `[\n]<path>:\n` header,
  reusing that module's "scan-or-default path, clamp at `RH_PATH_MAX`,
  two-pass compose, no partial write on overflow" discipline rather
  than duplicating it. Byte-exact goldens plus the overflow path live
  in `tests/multipath_fixtures.pdx` (5 cases).
- **`Runner::runner_ls`** -- at `rn_ls_pre_emit`, right after the bind
  check and before the (unrelated) `-l` total-line gate, composes and
  writes the header via the existing `tty_write` trampoline when the
  new `RN_BIT_HEADER_MASK` (0x8000) is set, with `RN_BIT_HEADER_BLANK_
  MASK` (0x10000) additionally requesting the leading blank line. Both
  bits are Dispatch-private -- never argv-recognised (see
  `ArgvSurface`'s own "RESERVED: 0x8000 and 0x10000" note in
  `src/argv_surface.pdx`).
- **`Dispatch::ls_dispatch`** (`src/dispatch.pdx`) -- replaces the
  single `runner_ls` call with a per-positional loop (capped at the
  new `MULTIPATH_MAX_PATHS` = 16) once `_as_pos_count > 1`; a
  `pos_count <= 1` invocation keeps the pre-1.1.8 single-call shape
  exactly. Every `runner_ls` return is folded through `ExitMap::
  exit_map` immediately inside the loop, and Dispatch returns the
  worst (numerically largest: 4 cap-denied > 3 system > 2 usage > 0
  ok) of those folded codes.
- **`tests/multipath_fixtures.pdx`** (new, 5 cases) -- byte-exact
  goldens for `multipath_header_compose` modeling the real Dispatch
  call sequence for a 2-3 path invocation (including a mixed file+dir
  pair), plus the shared `RH_PATH_MAX` clamp and an overflow case.

### Interaction notes

- **`-R`**: each per-path `runner_ls` call is a fully independent
  invocation with its own `-R` state, so `ls -R a b` performs a
  complete `-R` pass under each of `a` and `b` in turn.
- **Sort / `--group-directories-first` / multi-column**: also
  per-call and independent -- nothing merges entries across paths.

### Known gaps (tracked, not regressions)

- The shell's `InitCap` handoff still narrows only one directory cap
  (`LS_DIR_CAP_SLOT`) per invocation regardless of how many
  positionals were given (paideia-os/ls#29). Every per-path
  `runner_ls` call therefore reads through that SAME held cap -- each
  path gets its own correct header, but the listing body under it is
  today's single directory's content repeated, not a distinct
  per-path read. This is the exact interim shape the issue itself
  authorizes, not a silent regression.
- Positionals past `MULTIPATH_MAX_PATHS` (16) are silently not
  iterated -- no error surfaces, matching this repo's existing
  "unreachable at HEAD" static-bound style (`RN_GDF_MAX_ENTRIES`,
  `RN_R_MAX_ENTRIES`).

## [1.1.7] -- 2026-09-06 -- `-l` total line + `PdxLsSummaryRecord@0.1` (ls.ENH-021) <a id="117"></a>

**1.1.7.** `ls -l` now prefixes its listing with a POSIX-style
`total <N>` line, and `ls -l --json` additionally appends one
fixed-shape 32-byte `PdxLsSummaryRecord@0.1` wire record after the
listing. Both additions land at single fall-through points in
`Runner::runner_ls` -- no change to the per-entry dispatch or either
buffered-vs-streaming path.

### Added

- **`LongTotal::long_total_compute`** (`src/long_total.pdx`, new
  module) -- computes the `-l` total-line value (sum of
  `ceil(size_bytes / 512)` across every emitted entry). Honest
  pass-through identity, same shape and rationale as
  `SortOptions::sort_options_by_mtime` / `sort_options_by_size`: the
  kernel's `PdxFsDirEntry` record carries no size field at HEAD, so
  the result is always 0 regardless of `entries_ptr` / `count`. Pinned
  by `tests/long_total_fixtures.pdx` cases 0-2 (including a non-null
  `entries_ptr` and a non-zero count) as the trip-wire for this gap.
- **`LongTotal::long_total_summary_record_compose`**
  (`src/long_total.pdx`) -- composes the fixed 32-byte
  `PdxLsSummaryRecord@0.1` wire record (magic `"PLSS"`, version
  `0x0100`, `entry_count`/`dir_count`/`file_count` as little-endian
  u32s, `total_blocks` as a little-endian u64 from
  `long_total_compute`, 4 bytes reserved) into a caller-owned buffer,
  refusing with `LT_ERR_OVERFLOW` when `dst_cap < 32`. Byte-exact
  goldens (including a multi-byte pattern that pins little-endian byte
  order) plus the overflow path live in
  `tests/long_total_fixtures.pdx` cases 3-6.
- **`Runner::runner_ls`** -- at `rn_ls_pre_emit`, when `-l` is set,
  composes and writes `"total <N>\n"` via the existing `tty_write`
  trampoline before the read loop starts. At `rn_ls_success`, when
  both `-l` and `--json` are set, composes and writes the
  `PdxLsSummaryRecord@0.1` record verbatim through the same trampoline
  -- reusing "the existing `--json` path" per the issue's own scope
  note, rather than standing up a second semantic-pipe endpoint bind
  ahead of the paideia-os/ls#30 schema-registry migration.
- **`tests/long_total_fixtures.pdx`** (new, 7 cases) -- 3 honest-gap
  trip-wire cases for `long_total_compute`, 3 byte-exact record
  goldens and 1 overflow case for
  `long_total_summary_record_compose`.

### Known gaps (tracked, not regressions)

- `total <N>` is always `total 0`: no kernel `PdxFsDirEntry` size
  field exists to sum, the same substrate gap `-t`/`-S` already
  document (ls.ENH-016, #34).
- `entry_count`/`dir_count`/`file_count` in the summary record ship as
  0 -- Runner does not accumulate a live per-kind tally across a
  listing today. The composer itself is not a stub: it encodes
  whatever values it is given correctly, so wiring real counters
  through is a one-line call-site change in a future round.
- The summary record travels over the same `KIND_TTY(write)` channel
  as `--json`'s per-entry lines, not a dedicated semantic-pipe
  `Binding::bind` slot -- `paideia-os/ls#30` (schema-registry
  migration off the placeholder hash) is still the blocker for a real
  second endpoint; `SemanticEmit::_se_summary_schema_name`'s deferred
  literal and comment are left untouched by this landing.

## [1.1.6] -- 2026-09-06 -- multi-column default output (ls.ENH-018) <a id="116"></a>

**1.1.6.** `-1`/`-C` already parsed (`AS_BIT_ONE`/`AS_BIT_C_MAJ`) but
had no Runner-side behaviour -- this release lands the fitted-grid
column algorithm and wires it into Runner's buffered-listing path (the
same one `-t`/`-S`/`-r`/`--group-directories-first` already use), so
multicol always renders the already-sorted/grouped buffer, column-major.

### Added

- **`Columns::columns_layout`** (`src/columns.pdx`, new module) --
  given a caller-owned array of name pointers/lengths, tries candidate
  row-counts ascending from 1 (`cols = ceil(count/rows)` derived per
  candidate so no column is ever empty) and accepts the first
  (therefore widest) candidate whose total rendered width fits
  `term_width`; `rows == count` (one column) is accepted
  unconditionally as the guaranteed-fits fallback, so a single name
  wider than the terminal collapses the whole listing to one column
  rather than being truncated or wrapped. Renders column-major with a
  one-column lookahead against the precomputed column-start table so a
  short trailing column never leaves trailing whitespace before its
  row's newline. No multiplication or division instruction anywhere in
  the module -- every `ceil`/`c*rows` is computed by repeated
  subtraction / incremental accumulation.
- **`TtyWrite::tty_probe_is_tty`** (`src/tty_write.pdx`) -- the
  "is stdout a TTY" probe multicol's auto-detect gate reads. Honestly
  returns 0 (not a TTY) unconditionally: no cap-bound fd 1 and no
  `ioctl`/`ttywinsize`/`isatty` syscall exist in paideia-os at HEAD
  (confirmed absent from `design/user/syscall-table.md`), the same
  substrate gap `AS_BIT_COLOR_AUTO`'s own probe already documents.
  Bare `ls` therefore keeps its pre-1.1.6 one-per-line default until
  that sub-blocker clears; `-C` is the real, live, unconditional path
  to multi-column output today.
- **`Runner::runner_ls`** -- computes `_rn_multicol_mode` once at entry
  (OFF when `-l`/`--json`/`-1`/`-F`/`--color` is set -- `-F`'s suffix
  and `--color`'s ANSI escapes would corrupt columns_layout's byte-
  length-based width math, a documented v1 scope cut, not a silent
  gap; else ON when `-C` is explicit or `tty_probe_is_tty()` reports a
  TTY), widens the buffered-path trigger alongside GDF/sort, and adds
  a dedicated `rn_ls_multicol_collect`/`rn_ls_multicol_render` phase
  that walks the finalized order buffer (hidden-filter + the same `-R`
  recursion-candidate detection the per-entry path runs, `sem_emit_entry`
  unchanged per accepted entry) before handing the whole accepted set
  to `columns_layout` and `tty_write`ing the composed grid in one call.
- **`tests/multicol_fixtures.pdx`** (new, 5 cases) -- empty, even-fit,
  uneven-fit (the dedicated trailing-whitespace-on-a-short-column pin),
  single-column-fallback (narrow terminal), and one-per-column
  (a single very-wide entry collapses the whole listing).

### Known gaps (tracked, not regressions)

- Auto-detect ("on over TTY") cannot be made real yet: no kernel
  primitive exposes terminal width or TTY-ness to userspace
  (`design/user/syscall-table.md` has no `ioctl`/`ttywinsize`/`isatty`
  entry, and fd 1 has no cap-slot binding in the M3 compat shim). `-C`
  is the live, testable path; `tty_probe_is_tty`'s single instruction
  flips when the sub-blocker clears, with no change needed to
  `columns_layout` or Runner's gate.
- `-F` and `--color` disable multicol mode at v1 (fall back to the
  existing one-per-line renderer, which already handles both
  correctly) rather than threading a "display width" concept through
  `columns_layout` separate from raw byte length.
- Terminal width is a fixed `RN_COL_TERM_WIDTH` (80) constant for the
  same reason auto-detect isn't real yet -- no live width query exists.

## [1.1.5] -- 2026-09-06 -- `-t`/`-S`/`-r` sort options (ls.ENH-016) <a id="115"></a>

**1.1.5.** `-t`/`-S`/`-r` already parsed (`AS_BIT_T`/`AS_BIT_S`/
`AS_BIT_R_REV`, commit `52e14a7`) but had no Runner-side behaviour --
this release lands the comparators and wires them into Runner's
buffered-listing path (the same one `--group-directories-first`,
ls.ENH-020 #38, already uses). Default sort stays lexicographic
ascending by name; `-t` sorts by mtime, `-S` by size, and `-r`
reverses whichever sort is active (`-tr` = mtime oldest-first, `-Sr`
= smallest-first).

### Added

- **`SortOptions::sort_options_by_name`** (`src/sort_options.pdx`,
  new module) -- a real, stable, in-place insertion sort over the
  buffered records' `name_len`/name-bytes fields, via a bounded
  lexicographic byte comparator (`so_name_compare`) with a
  length tiebreak on a shared prefix (`"ann" < "annb"`). `reverse`
  flips the comparison sense.
- **`SortOptions::sort_options_by_mtime`** /
  **`sort_options_by_size`** (same module) -- honest pass-through
  identity functions, not real comparators: the kernel's
  `PdxFsDirEntry` record (inode@0, kind@8, name_len@16, name@24) has
  no mtime or size field at HEAD, the same gap `LongFormat`'s own
  `-l` columns already placeholder at 0. A stable sort over an
  all-ties key performs zero swaps, so `-t`/`-tr`/`-S`/`-Sr` all keep
  the original readdir encounter order today. Pinned as an executable
  golden (not a silent behaviour) by `tests/sort_options_fixtures.pdx`
  cases 6-9, so a future kernel record growing real `mtime_ns` /
  `size_bytes` fields shows up as a diff there.
- **`Runner::runner_ls`** -- extends the existing GDF buffered-
  listing path (`_rn_gdf_buf` / `rn_ls_gdf_collect` /
  `rn_ls_gdf_emit_next`) to also trigger on any of `-t`/`-S`/`-r`
  (new `_rn_sort_mode` flag, OR'd alongside `_rn_gdf_mode` at both
  "take the buffered path" decision points) rather than only on
  `--group-directories-first`. Inside `rn_ls_gdf_partition`, a
  requested sort now runs on the buffered record array BEFORE any
  GDF directories-first partition (or, absent GDF, before a trivial
  identity-order fill) -- `group_sort_partition`'s two-pass stability
  preserves the sort's order within each of the two groups, so
  `ls -t --group-directories-first` groups directories first and
  orders each group by the requested sort, matching GNU ls's own
  composition of the two options.
- **`tests/sort_options_fixtures.pdx`** (new, 10 cases) -- see
  `tests/README.md` for the full case table.

### Known gaps (tracked, not regressions)

- `-t` and `-S` do not yet discriminate by real mtime/size (see
  above); this needs the kernel's `PdxFsDirEntry` readdir record to
  grow those fields, tracked alongside `LongFormat`'s own `-l`
  mtime/size placeholders (`design/enhancement-plan.md` §7).
- `ls -tS` (both `-t` and `-S` set) resolves `-t` first, a fixed
  tiebreak rather than GNU ls's "last flag on the command line wins"
  -- the OR'd `flag_bits` vocabulary this argv surface builds cannot
  distinguish argument order.

## [1.1.4] -- 2026-09-05 -- `-R` recursion-header interim landing (ls.ENH-017) <a id="114"></a>

**1.1.4.** `-R` already parsed (`AS_BIT_R_REC`, commit `9fb4b98`) but
had no Runner-side behaviour at all -- `ls -R` and bare `ls` produced
byte-identical output. This release lands a real, observable,
fixture-tested piece of `-R`'s behaviour: after the primary listing,
`ls -R` now prints one `"<path>/<name>:"` header per subdirectory it
found, in encounter order. It does **not** land full recursive
descent -- no listing follows a header. That gap is architectural,
not a shortcut: `PdxfsShim::pdxfs_open_dir` mints a directory cap
only from a `KIND_MEMORY` parent carrying `RIGHT_MINT`, which a
read-only tool like `ls` never holds, and no kernel
`pdxfs_dir_open_at`-shaped trampoline (open a named child of an
already-held directory cap) exists anywhere in paideia-os at HEAD.
Real descent additionally needs paideia-os/ls#29 (path-argument-to-
cap resolution) so a recursion step even knows what path string to
hand the shell for the child. Both gaps are unresolved and out of
scope for a single-repo `ls` change; issue #35 stays open, tracking
them, rather than being closed on a partial landing.

### Added

- **`RecurseFilter::recurse_should_descend`** (`src/recurse_filter.pdx`,
  new module) -- the `-R` recursion-candidacy predicate: a directory-
  kind entry (kind nibble `0x4`) that is not exactly `.` or `..` is a
  candidate; everything else (files, symlinks -- `-L` is not
  implemented anywhere in this tree, so a symlink is never followed
  into a directory -- and the two dot-entries) is not. Pure leaf, no
  syscalls, 8 fixture cases.
- **`RecurseHeader::recurse_header_compose`** (`src/recurse_header.pdx`,
  new module) -- composes the GNU-`ls`-shaped
  `'\n<path>/<name>:\n'` header byte-for-byte, defaulting `path` to
  `.` when no argument path was given (matching bare `ls -R`'s own
  convention). Two-pass (compute-then-write, no partial output on
  overflow, matching `Render::render_dec_u64`'s contract), with an
  independent clamp on both the path scan (`RH_PATH_MAX` 200) and the
  caller-supplied `name_len` (`RH_NAME_MAX` 104). Pure leaf, no
  syscalls, 5 byte-exact fixture cases.
- **`Runner::runner_ls`** two new phases, both gated on
  `AS_BIT_R_REC`: (1) per-entry, right where every other render
  decision already happens, a qualifying directory-kind entry is
  bulk-copied into a new 64-entry buffer (`_rn_r_buf`, identical
  shape to the existing `--group-directories-first` buffer, and
  subject to the same loud-refusal-on-overflow policy, unreachable at
  HEAD for the same "kernel readnext is a fixed small stub" reason);
  (2) once the primary listing is fully emitted, a second loop walks
  that buffer and writes each header via `tty_write`. `path_ptr` is
  stashed in a dedicated `.bss` cell (`_rn_r_path_ptr`) at function
  entry, before `--group-directories-first`'s own partition phase
  permanently repurposes the register that used to carry it -- a real
  bug this landing would otherwise have introduced silently under
  `ls -R --group-directories-first` together.
- **`tests/recurse_filter_fixtures.pdx`** (new, 8 cases) and
  **`tests/recurse_header_fixtures.pdx`** (new, 5 cases) -- see
  `tests/README.md` for the full case tables.

### Known gaps (tracked, not regressions)

- No listing follows a recursion-block header (paideia-os/ls#29 +
  the missing kernel `pdxfs_dir_open_at` trampoline; see above).
- `RN_R_MAX_DEPTH` (16) is a reserved constant for the real descent
  controller's future call-depth guard; nothing branches on it today
  because nothing recurses past depth 1 (the immediate children of
  the single directory cap `ls` holds).

## [1.1.3] -- 2026-09-05 -- file-as-path single-row fallback (ls.ENH-015) <a id="113"></a>

**1.1.3.** `ls <path>` unconditionally assumed `<path>` resolved to a
directory and called `sys_pdxfs_dir_readnext` in a loop; a `<path>`
that resolved to a regular file surfaced `LS_ERR_READDIR` (exit 4)
instead of the single-row GNU `ls` behaviour. This release lands the
interim fall-through the issue text scopes for while
paideia-os/ls#29 (real argument-to-cap path resolution) is still
open: "a shell that already narrows to a file cap gets correct
behaviour."

### Added

- **`Runner::rn_compose_file_entry`** (`src/runner.pdx`, new pure
  helper) -- composes a synthetic 128-byte `PdxFsDirEntry`-shaped
  record from a raw NUL-terminated name: zeroes the record, stores
  the new `RN_ENT_KIND_FILE` (8) placeholder at the kind offset,
  computes `name_len` via a `RN_ENT_NAME_MAX` (104)-bounded strnlen,
  and copies the name bytes in. No syscalls, no callee-save
  registers, directly fixture-testable.
- **`Runner::runner_ls`** `rn_ls_file_fallback` path. `sys_pdxfs_
  dir_readnext` returns `-EBADF` for two substrate conditions the
  kernel body cannot itself distinguish (an unpopulated
  `LS_DIR_CAP_SLOT` and a live cap whose mode nibble is not DIR); a
  non-null `path_ptr` is used as the second signal that picks the
  latter, so a bare `ls` with an unwired cap keeps failing exactly as
  before (the M3 boot-smoke fingerprint is unaffected) while `ls
  file.txt` against an already-narrowed file cap now renders one row.
  The fallback composes the record via `rn_compose_file_entry` and
  jumps into a new shared label, `rn_ls_render_dispatch`, positioned
  AFTER the `hidden_filter_accept` check so an explicit path argument
  is never dot-filtered (POSIX semantics) while still reusing every
  existing renderer (`-l`, `--json`, `--color`, `-F`) with no
  duplicated format-flag switch. A new `_rn_single_file_mode` flag
  makes `rn_ls_continue` terminate after the one synthetic entry
  instead of calling `pdxfs_dir_readnext` again (which would re-hit
  the same `-EBADF` and loop forever).
- **`tests/file_fallback_fixtures.pdx`** (new, 5 cases) -- byte-exact
  128-byte record diffs for `rn_compose_file_entry`: a plain short
  name, an empty name, a dotfile (pinning that the composer itself
  does not hidden-filter), and two `RN_ENT_NAME_MAX` clamp-boundary
  cases (one where the real terminator coincides with the clamp, one
  where the clamp fires strictly before the string's actual NUL).

### Known gaps (tracked, not regressions)

- **Symlinks are not distinguishable.** tmpfs mints only
  `VNODE_TYPE_REG=1` / `VNODE_TYPE_DIR=2` at HEAD -- there is no
  symlink vnode type in this filesystem yet -- and no cap-kind-query
  trampoline is exposed to userspace to tell a file cap from a
  hypothetical future symlink cap apart. `RN_ENT_KIND_FILE` is
  therefore a hardcoded placeholder (same discipline as the owner/
  mtime/mode_bits placeholders elsewhere in this file); `-L`
  (dereference) and "print the symlink line without following" are
  both out of scope until a symlink vnode type and a stat/cap-kind
  primitive exist.
- **The standalone `ls file.txt` case (no shell pre-narrowing) and
  `ls does-not-exist` -> exit 3** from the issue's fingerprint section
  both require real argument-to-path resolution and stay blocked on
  paideia-os/ls#29, exactly as #33 itself scopes.

## [1.1.2] -- 2026-09-05 -- `--group-directories-first` (ls.ENH-020) <a id="112"></a>

**1.1.2.** `ArgvSurface::AS_BIT_GDF` parsed since commit `36d5995`
(argv-surface-only landing, Refs #38) but the read loop never buffered
or reordered anything -- `ls --group-directories-first` was byte-
identical to bare `ls`. This release wires the comparator half.

### Added

- **`GroupSort::group_sort_partition`** (`src/group_sort.pdx`, new
  module) -- a stable two-pass directories-first partition over a
  caller-supplied array of kind codes. Pass 1 collects directory
  indices in encounter order; pass 2 collects everything else in
  encounter order. This is the complete implementation of "each group
  sorted by whatever the existing sort discipline is" as that
  discipline stands today: ls has no live `-t`/`-S`/`-r` comparator
  anywhere in this tree yet (`ls.ENH-016`, #34, is argv-surface-only,
  same as ENH-020 was before this release), so within-group order is
  raw readdir order, preserved. The two-pass stability composes with
  a future real comparator unchanged.
- **`Runner::runner_ls`** (`src/runner.pdx`) GDF collect/partition/
  emit phases. The held `KIND_PDXFS_FILE` directory cap has no
  rewind primitive, so grouping requires buffering: when `AS_BIT_GDF`
  is set, the read loop now drains the whole directory into a static
  64-entry buffer (`_rn_gdf_buf`, `RN_GDF_MAX_ENTRIES`), extracts one
  kind-nibble per entry, calls `group_sort_partition`, then replays
  the buffered records through the **unchanged** per-entry render/
  emit body (`rn_ls_have_entry` onward -- every `-l`/`--json`/
  `--color`/`-F` rendering path is untouched) in the computed order.
  Non-GDF listings take the exact byte-for-byte same streaming path
  as before (zero behavioural change; verified by inspection, no
  existing fixture touches Runner's control flow).
- **`tests/group_sort_fixtures.pdx`** -- 7 cases for
  `group_sort_partition`: empty, all-dirs, all-files, mixed, mixed
  with symlinks, single dir, single file. The symlink case is the
  executable pin for the documented no-promotion gap below.

### Known limitation

- **Symlink-to-directory promotion is not implemented.** GNU ls
  groups a symlink whose target is a directory alongside real
  directories; that needs the target's type, which needs a
  stat-follow syscall `PdxfsShim` does not expose (it has only
  `pdxfs_open_dir` + `pdxfs_dir_readnext`). A symlink entry (kind
  `0xA`) is grouped with the non-directory partition today. Documented
  in `src/group_sort.pdx`'s module comment and pinned by
  `tests/group_sort_fixtures.pdx` case 4; tracked as a follow-up once
  a stat-follow trampoline lands.
- **`RN_GDF_MAX_ENTRIES` = 64 static cap.** A directory with more
  entries than that refuses with the existing `LS_ERR_READDIR`
  sentinel rather than silently truncating the grouped listing.
  Unreachable at HEAD -- `sys_pdxfs_dir_readnext` is still a fixed
  small stub (`design/enhancement-plan.md` §1.1) -- but a real
  substrate will need a dynamic buffer once this tool has an
  allocator primitive to lean on.

## [1.1.1] -- 2026-09-03 -- JSON escape + schema catalog correctness (post-1.1.0 debugger findings) <a id="111"></a>

**1.1.1 (post-1.1.0 debugger patch).** Closes the three findings the
v1.1.0 debugger pass surfaced (HIGH + MEDIUM + LOW). No frozen 1.0
interface changes -- the argv surface, 144-byte `PdxFsDirEntry@0.1`
wire body, exit-code map, and `caps.decl` requires-set are unchanged.
`caps.decl :: declares_output_schemas` shrinks from two entries to
one (`PdxLsSummaryRecord@0.1` is retracted, matching what the tool
actually emits); a consumer that inspected the manifest and preloaded
a decoder for the phantom schema now sees the honest surface.

Fixes: v1.1.0 debugger findings 1+2+3.

### Fixed

- **v1.1.0 finding 1 (HIGH -- correctness / injection).**
  `JsonLine::json_line_render`'s name-copy loop (`src/json_line.pdx`
  L202-225 pre-1.1.1) wrote every raw byte from `name_ptr` straight
  into the `"name":"..."` field with zero escaping, justified with a
  false claim about `sys_pdxfs_open`'s mint contract. The debugger
  verified that path is a stub cap-mint constructor with no name
  argument; the real name-writing path is `tmpfs_create` which caps
  length only, so a filename like `foo"bar` produced unparseable JSON
  and a filename with `\n` split one JSON-lines record into two. The
  copy loop now implements RFC 8259 string escaping: `"` -> `\"`, `\`
  -> `\\`, `0x08` -> `\b`, `0x09` -> `\t`, `0x0A` -> `\n`, `0x0C` ->
  `\f`, `0x0D` -> `\r`, and any other control byte (`0x00-0x1F`) ->
  `\u00XX`. The 104-byte cap is now an INPUT-byte clamp
  (`JL_NAME_MAX_INPUT`, renamed from `JL_NAME_MAX`); each input byte
  may expand to up to six output bytes, and the existing
  `JL_ERR_OVERFLOW` sentinel surfaces cleanly if `dst_cap` cannot
  accommodate the worst case. The false justification is retracted;
  the new one names `tmpfs_create` as the writer and
  `caps.decl :: declares_output_schemas` as the schema authority.

- **v1.1.0 finding 2 (MEDIUM -- schema-registry integrity).**
  `SchemaDump::_sd_catalog_bytes` (`src/schema_dump.pdx` L96-101
  pre-1.1.1) named two schemas -- `PdxFsDirEntry@0.1` and
  `PdxLsSummaryRecord@0.1` -- but ls never emitted a record of the
  second shape on any code path (`caps.decl :: declares_output_schemas`
  only declared the first; `SemanticEmit::_se_summary_schema_name`
  was an inert byte-array constant no emit function ever read). A
  consumer that ran `ls --schema` and BLAKE3-hashed the second name
  would preload a decoder for a schema id no record ever arrived
  against. The catalog is now single-entry:
  `PdxFsDirEntry@0.1 -- one record per directory entry\n` (52 bytes,
  down from 125). `caps.decl` gains an INVARIANT note naming its
  `declares_output_schemas` as the single authoritative source; the
  `SchemaDump` catalog literal and the `SemanticEmit` schema-name
  literals are lock-step mirrors. `SemanticEmit::_se_summary_schema
  _name` gains a `ls.ENH-021 (#39) deferred -- retire this comment
  when the summary record ships` note so its inert status is honest.

### Added

- **v1.1.0 finding 3 (LOW -- test coverage).**
  Two new fixture modules under `tests/`, both following the M4
  fixture convention (`<name>_case_count / _run / _verify_all`
  triples documented in `tests/README.md`):
  - `tests/json_line_fixtures.pdx` -- seven byte-exact cases pinning
    the v1.1.1 escape overhaul: plain name (passthrough), the three
    single-byte shortcuts most likely to fire in the wild
    (`\"`, `\\`, `\n`), the six-byte `\u00XX` fallback for `0x01`,
    the max-input clamp at 104 bytes, and the overflow-sentinel path
    with an undersized `dst_cap`. Human-readable copies at
    `tests/goldens/json_line_case<N>_*.txt`.
  - `tests/schema_dump_fixtures.pdx` -- one byte-diff of the entire
    52-byte catalog against a local golden copy. This is the
    tripwire the `caps.decl` invariant note points at: any future
    edit that adds, drops, or renames a schema in the catalog
    without updating this golden fails byte-diff. Human-readable
    copy at `tests/goldens/schema_dump_catalog.txt`.
  Both fixtures land in the same commit as the renderer fixes;
  `Phase 2 paideia-as test` remains a parse+encode smoke (see the
  1.0.1 debugger note), so the runtime cover lands when the M5 QEMU
  smoke sequences these `_verify_all` entry points.

### Files touched

- `src/json_line.pdx` -- rewrite name-copy loop with escape dispatch;
  rename `JL_NAME_MAX` -> `JL_NAME_MAX_INPUT`; retract false
  justification; add `jl_esc_*` label family.
- `src/schema_dump.pdx` -- shrink `_sd_catalog_bytes` to 52 bytes and
  the len constant to 52; retract two-entry claim; name `caps.decl`
  as the authoritative source.
- `src/semantic_emit.pdx` -- annotate `_se_summary_schema_name` as
  deferred until `ls.ENH-021 (#39)` and inert until then.
- `caps.decl` -- add INVARIANT note pointing at the two mirrors
  (`SchemaDump` catalog and `SemanticEmit` schema-name literals)
  that must stay lock-step with `declares_output_schemas`.
- `manifest.pdxproj` -- version 1.1.1; add the two new fixtures to
  the tests list; bump `mirror_target` and `manifest_pdxsig`.
- `tests/json_line_fixtures.pdx` (new) + `tests/schema_dump_fixtures
  .pdx` (new) + goldens under `tests/goldens/`.

## [1.1.0] -- 2026-09-03 -- wiring wave (ENH-002 + ENH-005 + ENH-006 + ENH-007 + ENH-022 + ENH-023) <a id="110"></a>

**1.1.0 (v1.x wiring wave).** Closes the six 1.1.0-wave items from
`design/enhancement-plan.md` §5 (ENH-002/005/006/007 for the top-band
"built + tested + disconnected" primitives, plus ENH-022 + ENH-023
that had been sitting as pin-only markers behind #24 and #25). Every
flag whose recognition landed at M1-002 but whose runner-side wiring
lagged is now live on the read loop; every enhancement issue closed
in this wave is purely additive per the "Compatibility rules from
1.0 forward" §Additive-only rule (no frozen 1.0 interface changes:
the argv surface stays the same, the 144-byte `PdxFsDirEntry@0.1`
wire body is unchanged on every path including `--json`, the exit-
code map is unchanged, and `caps.decl` is unchanged). Bundled release
per the `libpdx-elevate` v1.1.2 pattern -- six related wire-in items
ship as one minor.

**Watch-out (from the 1.0.1 debugger note).** `paideia-as test` in
Phase 2 of `tools/build.sh` is a parse+encode smoke, not a runtime
verify. New fixtures added in this wave (none in-tree yet -- see
Follow-ups) will vacuous-pass Phase 2; the real correctness gate is
a shell-level byte-diff smoke against the compiled binary once the
kernel wire lights up.

### Added

- **ENH-002** (#24) -- `Runner::runner_ls` now dispatches to
  `LongFormat::long_format_line` when `AS_BIT_L` is set on
  `_as_flag_bits`. The renderer packs `kind_nibble`, `mode_bits`
  (placeholder 0 -- ENH-008 tracks the kernel-side per-entry mode
  addition), and `human_size_flag` (from `AS_BIT_H`) into
  `kind_mode_flags`, points `extra_ptr` at a pre-zeroed 16-byte
  `_rn_lf_extra_scratch` (mtime_ns and owner_row both 0 -- same
  kernel-blocked story), and composes into `_rn_line_buf` (grown
  from 14 u64 to 32 u64 = 256 bytes to fit the max long-format line
  including the ENH-022 symlink tail). The default (no `-l`) path
  is byte-identical to 1.0.1. Bumps `LS_ST_LONG` (slot 6) per
  rendered line so the tool's stats table records the wiring.
- **ENH-005** (#25) -- `Runner::runner_ls` now wraps text-branch
  content with ANSI SGR when `AS_BIT_COLOR` is set on
  `_as_flag_bits`. `ColorPicker::color_pick` chooses a palette from
  the entry's `kind_nibble`; `color_sgr_prefix` composes the SGR
  set-color sequence into `_rn_sgr_prefix_scratch`, then `tty_write`
  emits prefix + content + suffix as three separate writes.
  `AS_BIT_JSON` disables color regardless (structured output must
  not carry ANSI escapes). Palette 0 (no-color-known) short-circuits
  to the plain emit path so an entry the palette dispatch cannot
  classify emits verbatim. Bumps `LS_ST_COLOR` (slot 7) per wrapped
  line.
- **ENH-006** (#19) -- `Dispatch::ls_dispatch` now short-circuits to
  `SchemaDump::schema_dump_emit` when `AS_BIT_SCHEMA` is set on
  `_as_flag_bits`, BEFORE calling `Runner::runner_ls`. The catalog
  is a 125-byte `.rodata` literal with one line per declared schema:
  `PdxFsDirEntry@0.1 -- directory entry emitted per accepted row\n`
  and `PdxLsSummaryRecord@0.1 -- run summary emitted after last
  entry\n`. `--schema` opens no `DirListRecord` audit frame (no
  directory read) and emits no semantic-pipe record -- it is a
  stateless read-of-manifest. Success routes through `ExitMap` to
  exit 0; a `tty_write` failure surfaces `LS_ERR_TTY_WRITE` and
  routes to exit 4. Retires the `--schema is inert` line from
  `design/enhancement-plan.md` §4.5.
- **ENH-007** (#26) -- `Runner::runner_ls` now emits one JSON object
  per accepted entry when `AS_BIT_JSON` is set, replacing the
  KIND_TTY text branch with `JsonLine::json_line_render`. Format:
  `{"name":"<name>","kind":<nibble_dec>,"inode":<inode_dec>}\n`.
  The 144-byte `PdxFsDirEntry@0.1` semantic-pipe record is emitted
  UNCHANGED on every path including `--json`; the JSON emit only
  swaps the text-format branch on the same fd -- simplest mental
  model, matches every other Unix tool with a `--json` mode. Name
  escaping deferred: PdxFS-v1's `sys_pdxfs_open` mint contract
  rejects `"`, `\\`, and control bytes at kernel-cap-narrow time,
  so unescaped bytes are safe on the v1.x line; a future PdxFS
  variant relaxing that constraint gets escape support as a
  one-branch copy-loop extension in `JsonLine`.
- **ENH-022** (#40) -- `LongFormat::long_format_line` now appends
  ` -> <link:target-unknown>` (25 bytes) after the name column when
  the kind letter at the anchor byte reads `l` (symlink; kind
  nibble 0xA). The literal placeholder ships until a paideia-os
  kernel readlink primitive lands -- see the follow-up
  `paideia-os#TBD: sys_pdxfs_readlink_by_slot for symlink targets`
  in the Deferred (upstream fix) section. Consumers see a distinct,
  self-describing value rather than a fabricated target; the ` -> `
  separator is the POSIX ls precedent so a downstream tool
  splitting on it recovers the expected shape.
- **ENH-023** (#41) -- `ArgvSurface::argv_surface_parse` now
  recognises `--color=auto` as a discriminator value: when the
  captured `_as_color_value_ptr` matches the literal `"auto\0"`,
  `AS_BIT_COLOR_AUTO` (0x4000) is set on `_as_flag_bits` alongside
  `AS_BIT_COLOR` (0x20). `Runner::runner_ls` reads this bit to
  decide whether to probe stdout's KIND before enabling color:
  today fd 1 has no cap-slot binding (M3 compat shim; see
  `tty_write.pdx` §TW_KIND_TTY note), so the probe falls through to
  "not a TTY" and color is disabled on `--color=auto`. Values other
  than `"auto"` (e.g. `--color=always`) leave the AUTO bit clear;
  Runner treats them as the "on" path.

### Changed

- **`src/runner.pdx`** -- `_rn_line_buf` grown from 14 u64 (112 B)
  to 32 u64 (256 B) so LongFormat's max line (with the ENH-022
  symlink tail) and JsonLine's max line (fixed 30 + name 104 +
  digits 22 = 156 B) fit without a per-renderer buffer split. The
  default path uses well under 105 B; the growth is a strict
  superset. Adds `_rn_lf_extra_scratch` (16 B) for the LongFormat
  `extra_ptr` and `_rn_sgr_prefix_scratch` + `_rn_sgr_suffix_scratch`
  (8 B each) for the ColorPicker SGR emit.
- **`manifest.pdxproj`** -- version bumped to `1.1.0`; adds
  `src/schema_dump.pdx` and `src/json_line.pdx` to the `sources:`
  block; `release:` block re-points to
  `pkgs.paideia-os/ls/1.1.0/`.
- **`STATUS.md`** -- Version bumped to 1.1.0; the milestone rollup
  table now marks ENH-002/005/006/007/022/023 as WIRED (previously
  DESIGNED behind pin markers) and pins the wiring wave close.

### Deferred (upstream fix)

- `src/long_format.pdx:lf_no_symlink_tail` uses the fixed placeholder
  `<link:target-unknown>` for the symlink target column until the
  paideia-os kernel exposes a `sys_pdxfs_readlink_by_slot` primitive
  the tool can call inline at this point. Filed as
  `paideia-os#TBD: sys_pdxfs_readlink_by_slot for symlink targets`;
  the LongFormat body will replace the placeholder with an inline
  `pdxfs_readlink_by_slot` call + name-copy tail as a one-block
  edit when the kernel wire lands.
- `src/runner.pdx:rn_ls_emit_wire` treats every `--color=auto` as
  the "not a TTY" outcome because fd 1 has no cap-slot binding
  today (M3 compat shim; see `tty_write.pdx` §TW_KIND_TTY note).
  When the R49.M1 KIND_TTY write wire lands, a `tty_stdout_kind()`
  helper in `TtyWrite` replaces the always-off gate with a real
  KIND compare against `TW_KIND_TTY` (0x197).
- `LongFormat` continues to render `mode_bits=0`, `size=0`, and
  `mtime=0` per entry because the 128-byte kernel
  `sys_pdxfs_dir_readnext` record carries only inode + kind +
  name_len + name at v1.x. `ENH-008` (#28) tracks the per-entry
  owner discovery via `sys_pdxfs_stat_by_inode`; the same kernel
  primitive will supply mode/size/mtime for the `-l` columns on the
  same round.

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
