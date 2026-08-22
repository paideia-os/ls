# ls.M2-002 — implementation notes

**Issue:** #5 — owner-column via KIND_USER_ref decode through libpdx-cap.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 (paideia-os).

## What landed

- `src/owner_col.pdx` — new `OwnerCol` module:
  - `owner_col_render_from_row(dst, cap, user_row) -> bytes |
    OC_ERR_OVERFLOW` — emits `u:<row>` from a raw KIND_USER row id.
  - `owner_col_render_from_wire(dst, cap, cap_wire_ptr) -> bytes |
    OC_ERR_NOT_USER | OC_ERR_OVERFLOW` — decodes a 16-byte Cap
    record via `libpdx-cap::cap_unpack`, verifies
    `unpacked_kind == LS_KIND_USER (0x190)`, extracts the row from
    the low 16 bits of `unpacked_target_ptr`, and delegates.
- Reserved OwnerCol sub-band `0xFFFFEB3x` (extends the ls
  return-code family from `design/architecture.md` §6).

## libpdx-cap dependency note

The plan doc §5.10 allocates the KIND_USER_ref decoder to
`libpdx-cap.M3-001` — this has NOT landed at HEAD (libpdx-cap
ships M1 + M2 only). OwnerCol therefore hand-decodes here as an M2
shim: `cap_unpack` (M1 API) populates the four `unpacked_*`
singletons; OwnerCol reads `unpacked_kind` + `unpacked_target_ptr`
directly, masks the row from the low 16 bits, and hands off.

When libpdx-cap.M3 lands `kind_user_ref_decode(cap_wire_ptr)
-> user_row`, the six-line decode block in
`owner_col_render_from_wire` collapses to
`call kind_user_ref_decode; mov r13, rax`. The wire format stays
16 bytes; the row-id semantics stay `[unpacked_target_ptr] &
0xFFFF`; consumers of OwnerCol see zero behavioural change across
the swap.

## Design decisions

- **Two entry points, one shared body.** `from_row` is the leaf
  render; `from_wire` is the decode + delegate. Splitting means a
  future call site that already has a row (e.g. Runner reading
  from a KIND_USER-embedded PdxFsDirEntry field once the schema
  ships at M3-002) skips the cap_unpack path and calls
  `from_row` directly.
- **`u:%d` text prefix.** Distinguishes the owner column from
  a raw digit column so a downstream schema-typed consumer parsing
  text-layer output can tell "owner: row N" apart from "size: N".
  Same discipline the D3 audit records use for audit-id
  columns.  A future release replaces the digit with the
  username once a name-resolution service exists (post
  libpdx-cap.M4).
- **Kind check before extract.** `OC_ERR_NOT_USER` refuses a
  wire cap with the wrong kind before any row-id math runs. Two
  reasons: (1) the row-id lane is kind-specific — `KIND_PDXFS_FILE`
  packs different data into target_ptr's low 16 bits, so blindly
  masking would render nonsense; (2) an audit-first tool should
  surface the type violation rather than mask it into a plausible-
  looking numeric owner.

## paideia-as conformance

Same rules as M1: no `test`, no `cmp imm > 0x7FFFFFFF`, byte
writes via `mov_b [dst], reg` (through Render), r11 scratch.
KIND_USER (0x190) and the row mask (0xFFFF) fit imm32 trivially;
the sentinel returns (0xFFFFFFFFFFFFFFFF for OVERFLOW, 0xFFFFEB30
for NOT_USER) are staged into r11 for compares.

## Tests

Deferred to M4:
- `owner_col_render_from_row` known-answer: row 0, 1, 15,
  255, 65535 (max), overflow with dst_cap = 1.
- `owner_col_render_from_wire` accept-path against a wire Cap
  packed with KIND_USER + row = 5.
- `owner_col_render_from_wire` refuse-path against KIND_PDXFS_FILE
  and KIND_TTY wire caps.
