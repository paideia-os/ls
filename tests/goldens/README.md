# tests/goldens/

Human-readable expected-output files for the byte-exact fixture
comparators added at 1.0.1 ENH-003 (#17). Each file records the
exact byte sequence one fixture case is asserted against. The
comparator lives inside the sibling `.pdx` fixture module and does
byte-for-byte compare against a `.rodata` table that mirrors these
files -- the files themselves are for humans (code review, doc
lookup, `diff`-based regeneration when a renderer changes shape)
and are NOT read at build or test time (paideia-as fixture modules
do not have a filesystem cap; the golden bytes have to live in
`.rodata`).

If a case's expected output ever changes:

1. Update the `.txt` file here.
2. Update the matching `.rodata` byte array in the `.pdx` fixture
   (`_lff_golden_case<N>` or `_hsf_golden_case<N>`).
3. Both edits ship in the same commit.

If the two ever drift, the `.rodata` bytes are the authority: they
are what the comparator asserts against, and they are what a
downstream consumer of the compiled fixture sees.

## Long-format cases (`tests/long_format_fixtures.pdx`)

The 12-step emit sequence of `LongFormat::long_format_line` renders
`<kind> <mode> <owner> <size> <mtime> <name>\n` with each column
separated by a single 0x20. Cases pin one kind letter each:

- `long_format_case0_file_644.txt` -- kind=file (`-`), mode=0o644,
  owner_row=0, size=12103, mtime=1755808140000000000,
  name="argv_surface.pdx". 56 bytes including the trailing `\n`.
- `long_format_case1_dir_755.txt` -- kind=dir (`d`), mode=0o755,
  owner_row=0, size=4096, mtime=1755850440000000000, name="src".
  42 bytes including the trailing `\n`.
- `long_format_case2_symlink_777.txt` -- kind=symlink (`l`),
  mode=0o777, owner_row=42, size=21, mtime=1755808141000000000,
  name="link". 42 bytes including the trailing `\n`.

`kind_mode_flags` is packed per `long_format.pdx` §COLUMN SEMANTICS:
`kind_nibble | (mode_bits << 4) | (human_size_flag << 13)`. All
three cases run with `human_size_flag = 0` so the size column emits
raw decimal via `render_dec_u64`; the `-h` path is exercised by the
human-size fixture below rather than layered on top of the long-
format one.

## Human-size cases (`tests/human_size_fixtures.pdx`)

`HumanSize::human_size_render` boundary cases spanning the fast path
(bytes < 1024, raw decimal) and the slow path (integer + `.` +
tenth + unit letter, base-2):

- `human_size_case0_zero.txt`      -- `0` (fast path)
- `human_size_case1_999.txt`       -- `999` (fast path, upper bound)
- `human_size_case2_1024.txt`      -- `1.0K` (slow path, unit 1 boundary)
- `human_size_case3_1536.txt`      -- `1.5K` (slow path, tenth digit)
- `human_size_case4_1048576.txt`   -- `1.0M` (slow path, unit 2)
- `human_size_case5_1T.txt`        -- `1.0T` (slow path, unit 4, 1024^4)

None of the six carries a trailing byte -- `human_size_render` does
not emit a terminator, so the golden has none either.

## Regenerating

There is no automated regeneration script. `human_size_render` and
`long_format_line` are deterministic given their inputs; if their
byte output changes without an intended shape change, that is a
regression in the renderer, not in the golden. Update the golden
only when a design change to the renderer itself is accepted (and
in that case the renderer's own justification comment updates in
the same commit).
