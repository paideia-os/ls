# ls.M3-003 -- implementation notes

**Issue:** #10 -- DirListRecord via libpdx-audit before first byte.
**Upstream doc:** `design/tooling/r49-r50-plan.md` §5.4 M3-003 line
496, §1 D3 (audit-first invariant), §5 line 148 (audit-refused ->
tool-refuses), §5 line 785 (libpdx-audit.M1-001 API).

## What landed

- `src/audit_shim.pdx` -- new `AuditShim` module (tool-shaped
  wrappers around libpdx-audit's three externally-linked symbols):
  - `audit_ls_begin(path_ptr, flag_bits)` -- imprints `_au_op_name`
    ("ls\0"), composes DirListRecord args at `_au_args_scratch`
    (path_ptr @0, flag_bits @8, reserved 0 @16), calls
    `audit_begin(op_name, args)`. Negative-errno u64 return ->
    `LS_ERR_AUDIT` (0xFFFFEB26); success -> stash audit_id at
    `_au_id`, return `AU_OK`.
  - `audit_ls_commit(exit_code)` -- loads `_au_id`; if zero, no-op
    return AU_OK (safe for pre-audit bail paths). Otherwise calls
    `audit_commit(audit_id, exit_code)`, clears `_au_id`, returns
    AU_OK. Library return IGNORED (tool's own exit_code is
    authoritative).
- `src/runner.pdx` -- Runner wraps the body in the begin/commit
  pair:
  - New `rn_ls_audit_open` label between the path gate and the
    existing `rn_ls_pre_emit`. Calls `audit_ls_begin(r12, r13)`
    (path_ptr, flag_bits). On refusal jumps to new
    `rn_ls_audit_fail` -> `LS_ERR_AUDIT`.
  - `rn_ls_epilogue` now saves rax in r13 (dead at epilogue --
    flag_bits done), calls `audit_ls_commit`, restores rax, then
    unwinds. Every ret path (including the pre-audit
    `LS_ERR_BAD_PATH` bail) funnels through the same epilogue -- the
    `_au_id == 0` gate inside audit_ls_commit makes that unification
    safe with no separate no-audit epilogue.
  - Justification updated to name the two new callees and enumerate
    the extra call sites the 6-push + sub-rsp-8 frame supports
    (audit_ls_begin, audit_ls_commit) at rsp % 16 == 0.
- `STATUS.md` -- M3-003 LANDED; M3 wave rollup marked CLOSED.

## D3 invariant enforcement

The audit_ls_begin call is placed AFTER the path gate and BEFORE
sem_emit_reset. This is the earliest point where all inputs (path,
flags) are validated (so the DirListRecord's args blob is
well-formed) and BEFORE any code path can emit output:

  - sem_emit_reset writes to .bss only (no output).
  - sem_emit_bind_stdout writes to the semantic-pipe binding table
    (no output byte).
  - The FIRST user-visible byte is emitted by the tty_write call
    inside the read loop -- which is unreachable until audit_ls_begin
    has already succeeded.

If audit_begin refuses (library unreachable, audit-journal full),
Runner returns LS_ERR_AUDIT without touching KIND_TTY or the stdout
endpoint. This is the "audit-refused -> tool-refuses" gate from
r49-r50-plan.md §5 line 148.

## Why no cap in caps.decl for the audit-journal endpoint

libpdx-audit resolves the svc.audit-journal endpoint on first call
via `sys_svc_lookup` (per r49-r50-plan.md §3 line 202, "every | in
a pipeline mints one via sys_svc_lookup"). The tool itself does not
need to hold a KIND_IPC_ENDPOINT cap narrowed to svc.audit-journal
in caps.decl -- the four caps declared at M1 (KIND_USER,
KIND_TTY(write), KIND_PDXFS_FILE(read,<arg-path>),
KIND_IPC_ENDPOINT for stdout) suffice.

Some future audit-journal implementation may push the cap into
caps.decl explicitly (for the same reason the stdout endpoint is
declared explicitly -- it lets the shell validate the manifest
before exec). At M3-003 we take the "library resolves internally"
route because it matches every other libpdx-* library convention.

## Library-stub compatibility

libpdx-audit ships M1-001 as a scaffold with the three symbol names
but no-op bodies (returning 0 for begin -> audit_id=0 -> commit
no-op; 0 for record_output; 0 for commit). Running ls linked against
that stub therefore has NO observable D3 output -- but exercises the
full call chain the M4 correctness matrix will pin. When
libpdx-audit's real body lands (writes to svc.audit-journal via
sys_ipc_send), ls-side behavior lights up without any tool-side
change.

## paideia-as conformance

- `AuditShim` PascalCase module basename.
- No `test` mnemonic. Zero-checks use `cmp reg, 0`.
- All `cmp reg, imm` immediates fit imm32 (0, 8, 16 in audit_shim;
  no new compares in runner beyond the existing 128 max).
- Byte reads: none. op_name is a qword store.
- `r11` scratch for LEA. `r12`/`r13` callee-save for arg survival.
- audit_ls_begin: 2 pushes + `sub rsp, 8` pad -> 24 bytes; entry
  rsp % 16 == 8; 8 + 24 = 32; 32 % 16 == 0 at the audit_begin call
  site. Matched add rsp,8 + 2 pops.
- audit_ls_commit: 1 push -> 8 bytes; entry rsp % 16 == 8; 8 + 8 =
  16; 16 % 16 == 0 at the audit_commit call site. Matched pop.
- Runner: unchanged 6-push + sub rsp,8 frame handles the two new
  nested call sites (audit_ls_begin, audit_ls_commit) at rsp % 16
  == 0 without adjustment.
- LS_ERR_AUDIT (0xFFFFEB26) already declared in Ls at M3-001; the
  M3-003 shim uses the same sentinel.
