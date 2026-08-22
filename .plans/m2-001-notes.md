# ls.M2-001 — implementation notes

**Issue:** #4 — `-l` long-format layout (kind, size, mtime, owner).
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 (paideia-os).

## What landed

- `src/long_format.pdx` — new `LongFormat` module:
  - `long_format_line(dst, cap, name_ptr, kind_nibble, mode_bits,
    size_bytes, mtime_ns, owner_row, human_size_flag) -> bytes |
    LF_ERR_OVERFLOW` — renders one directory-entry line as
    `<kind> <mode:o> <owner> <size> <mtime> <name>\n`, delegating
    to OwnerCol (M2-002), HumanSize (M2-003), and Render (utility).

## Design decisions

- **Nine-argument entry over a struct-typed detour.** Every field
  arrives from a different upstream source in the M3 readdir loop
  (name from the entry blob; kind + mode + size + mtime from
  `KIND_PDXFS_FILE` cap queries; owner from a KIND_USER decode).
  Bundling them into a struct would force every M4 fixture to
  build the struct just to render one line. The nine-arg signature
  pushes the composition cost onto the caller who already has
  every value separately.
- **Column order (kind, mode, owner, size, mtime, name).** One
  extra column vs the plan doc §4.4 four-column base — mode is
  added so a text-layer reader without the schema pipe still sees
  permission bits. `lf_emit_mode` is the drop-swap point if
  fixture feedback shows it clutters.
- **Mode as raw octal digits at M2.** Three ASCII digits `'0'..'7'`.
  The POSIX `rwxrwxrwx` glyph translation is deferred to M3 where
  the schema/MIME palette decides how permissions render across
  text and typed outputs. Raw octal keeps M2 deterministic
  against a fixture; glyphs need palette state.
- **Kind letter table (`_lf_kind_letters`).** Sixteen slots so a
  corrupted nibble lands on `'?'` rather than segfaulting or
  emitting an out-of-band byte. Assigned nibbles match the
  PdxFS-v1 file-type nibble in `mode_bits[15:12]` per
  paideia-os `src/kernel/core/cap/kind_pdxfs_file.pdx` SECTION 1.
- **Mtime rendered as `ns:<decimal>`.** pdx-time doesn't ship
  until R54 (plan §3.6); the `ns:` prefix keeps the column
  self-describing so a downstream typed consumer can recover the
  raw i128 value unambiguously.
- **Overflow refuses without unwinding.** Partial dst bytes on
  overflow are acceptable because a line-level rendering that
  overruns dst_cap is a caller-provided-too-small-buffer scenario
  where the caller must discard the whole line — the partial
  bytes carry a truncated schema no downstream consumer will
  read. Different discipline than Render's atomic refusal (which
  can afford to keep dst untouched because Render only writes one
  primitive at a time).

## Register plan

Six callee-save pushes (rbx, r12, r13, r14, r15, rbp) + `sub rsp, 8`
pad = 56 bytes. Entry rsp % 16 == 8; +56 = 64; 64 % 16 == 0 at
every nested-call site (matches HumanSize's shape).

Stack-arg accesses at [rsp+64] (mtime_ns), [rsp+72] (owner_row),
[rsp+80] (human_size_flag) — loaded at consume site to keep the
callee-save register set at 6.

kind_nibble stays in rcx (caller-save) — consumed at step 1 before
any nested call fires, no spill.

## Runner integration

Runner is still STUB (see M2-003 notes for the R42 PdxFS-v1
directory-iterator kernel gap). LongFormat is a pure primitive
tested at M4; M3 wires it into `Runner::runner_ls` alongside the
readdir loop when the substrate lands.

## paideia-as conformance

- Byte reads (name copy loop) use `xor rax; mov_b rax, [ptr]`
  (#1248 mitigation).
- Byte writes via `mov_b [dst], reg` through Render.
- No `test` mnemonic; every zero-check is `cmp reg, 0`.
- Largest immediate 0x7F (ASCII); sentinel `0xFFFFFFFFFFFFFFFF`
  stages into r11 before compare.
- SysV push/pop parity + 16-byte rsp alignment at every nested
  call site.

## Tests

Deferred to M4:
- Full-line render against a fixture with known field values;
  expected byte-for-byte output in the plans corpus.
- Overflow at every intermediate emit step (dst_cap = 0, 1, 5,
  50, 200 — the incremental byte counts identify which step
  refused).
- Unknown kind nibble (0x0, 0xF) renders as `'?'`.
- Human vs raw size dispatch: flag = 0 emits digits, flag = 1
  emits `1.5K`-form.
- Name copy: empty name (single NUL), one-byte name, long name.
