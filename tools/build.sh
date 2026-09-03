#!/usr/bin/env bash
# Per-repo build script. Runs paideia-as build over every .pdx source,
# then paideia-as test over every tests/*.pdx fixture, then a
# fingerprint link-check across src/ and tests/. Non-zero on any
# failure -- fixture parse/encode fail, unresolved compile, or a
# malformed `[legacy: ... OK]` fingerprint tag.
#
# 1.0.1 ENH-011 (paideia-os/ls#20): the pre-1.0.1 script only invoked
# `paideia-as build --emit elf64` on every source and reported
# failures. It did not (a) parse-verify any fixture, so a fixture
# that failed to parse under a paideia-as bump was silently non-
# invoked, or (b) check that `[legacy: ... OK]` fingerprint tags
# were well-formed (the space-`OK`-space closing that gates the
# OK_TOK sweep). Both are added here.
#
# Cross-module call resolution is NOT verified end-to-end: paideia-as
# still emits per-file object files at `--emit elf64` and there is no
# on-tree linker. Live invocation of the fixture `<name>_verify_all`
# functions gates on the paideia-as runtime evaluator
# (paideia-as-test §"Phase-4-m12-001"); until that lands, the
# `paideia-as test` pass here is a parse+encode smoke per fixture.
# It still catches the pre-1.0.1 failure mode (a fixture silently
# broken by an unrelated paideia-as bump).
#
# Resolves paideia-as via (in order):
#   1. $PAIDEIA_AS env var
#   2. paideia-os checkout sibling to this repo: ../paideia-os/tools/paideia-as/target/release/paideia-as
#   3. $HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as
#   4. paideia-as on $PATH (must be >= 0.21.0)
#
# Requires paideia-as >= 0.21.0. The 0.9.0 shipped in $PATH by default does not
# accept the syntax used in this repo.

set -euo pipefail
cd "$(dirname "$0")/.."

MIN_VERSION="0.21.0"

resolve_paideia_as() {
    if [ -n "${PAIDEIA_AS:-}" ] && [ -x "$PAIDEIA_AS" ]; then
        echo "$PAIDEIA_AS"; return
    fi
    for cand in \
        "../paideia-os/tools/paideia-as/target/release/paideia-as" \
        "$HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as"
    do
        if [ -x "$cand" ]; then
            echo "$cand"; return
        fi
    done
    if command -v paideia-as >/dev/null 2>&1; then
        command -v paideia-as; return
    fi
    return 1
}

version_ge() {
    # $1 = have, $2 = want ; returns 0 if have >= want
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

PA="$(resolve_paideia_as || true)"
if [ -z "$PA" ]; then
    echo "[build] FAIL: paideia-as not found. Set PAIDEIA_AS or clone paideia-os as a sibling." >&2
    exit 2
fi
VER="$("$PA" --version | awk '{print $2}')"
if ! version_ge "$VER" "$MIN_VERSION"; then
    echo "[build] FAIL: paideia-as $VER is too old, need >= $MIN_VERSION (found $PA)" >&2
    exit 2
fi
echo "[build] paideia-as $VER at $PA"

BUILD_DIR="build-out"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Phase 1: compile every .pdx to a per-file elf64 object.
# ---------------------------------------------------------------------------
FAIL=0
COUNT=0
for pdx in src/*.pdx; do
    [ -f "$pdx" ] || continue
    COUNT=$((COUNT + 1))
    obj="$BUILD_DIR/$(basename "$pdx" .pdx).o"
    if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
        FAIL=$((FAIL + 1))
    fi
done

if [ -d tests ]; then
    for pdx in tests/*.pdx; do
        [ -f "$pdx" ] || continue
        COUNT=$((COUNT + 1))
        obj="$BUILD_DIR/tests-$(basename "$pdx" .pdx).o"
        if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
            FAIL=$((FAIL + 1))
        fi
    done
fi

echo "[build] compile: $COUNT source(s), $FAIL failure(s)"
if [ "$FAIL" -ne 0 ]; then
    echo "[build] FAIL: compile phase" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Phase 2 (1.0.1 ENH-011): parse+encode-smoke every tests/*.pdx via
# `paideia-as test`. This is not a live verify_all invocation (the
# runtime evaluator is not on-tree; see paideia-as-test §Phase-4-m12-
# 001) but it does hand each fixture through the fresh lex+parse+
# elaborate+encode path a second time -- catching the pre-1.0.1
# failure mode where a fixture broke silently under a paideia-as
# bump and the compile phase happened to still succeed for the src/
# subset.
# ---------------------------------------------------------------------------
FIX_COUNT=0
FIX_FAIL=0
if [ -d tests ]; then
    for pdx in tests/*.pdx; do
        [ -f "$pdx" ] || continue
        FIX_COUNT=$((FIX_COUNT + 1))
        if ! "$PA" test "$pdx" 2>&1; then
            echo "[build] FAIL: fixture parse-smoke failed: $pdx" >&2
            FIX_FAIL=$((FIX_FAIL + 1))
        fi
    done
fi
echo "[build] fixtures: $FIX_COUNT parse-smoke run, $FIX_FAIL failure(s)"
if [ "$FIX_FAIL" -ne 0 ]; then
    echo "[build] FAIL: fixture phase" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Phase 3 (1.0.1 ENH-011): fingerprint link-check.
#
# Every legacy-cross-reference fingerprint tag has the exact shape
# `[legacy: <text> OK]` with a mandatory single space on each side of
# the `OK` token (the OK_TOK gate). This check greps src/ and tests/
# for `[legacy:` decls and flags any decl whose closing is not `space
# OK space ]` -- either a lowercase `ok`, a missing space, or an
# entirely missing closing. Currently a no-op (the ls repo carries no
# legacy tags) but active as a forward guard for the God-file
# refactor cadence documented in feedback_god_file_refactor.md.
# ---------------------------------------------------------------------------
LINK_FAIL=0
if command -v grep >/dev/null 2>&1; then
    # Every line that opens `[legacy:` must close with ` OK ]` on the
    # same line. `grep -c` counts matches; any line matching `[legacy:`
    # but NOT matching ` OK ]` is a orphan.
    ORPHANS=$(grep -rnE '\[legacy:' src/ tests/ 2>/dev/null | grep -vE ' OK ?\]' || true)
    if [ -n "$ORPHANS" ]; then
        echo "[build] FAIL: malformed [legacy: ... OK] fingerprint(s):" >&2
        echo "$ORPHANS" >&2
        LINK_FAIL=1
    fi
    LC=$(grep -rnE '\[legacy:' src/ tests/ 2>/dev/null | wc -l | awk '{print $1}')
    echo "[build] link-check: $LC legacy tag(s) surveyed, $LINK_FAIL malformed"
else
    echo "[build] link-check: skipped (grep not available)"
fi
if [ "$LINK_FAIL" -ne 0 ]; then
    exit 1
fi

echo "[build] OK"
