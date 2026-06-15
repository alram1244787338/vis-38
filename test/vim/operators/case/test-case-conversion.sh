#!/bin/sh
#
# Regression test: verify gu/gU/g~ pipe commands preserve newlines
# and produce correct output for all cases.
#
# This script simulates the vis pipe mechanism (cmd_filter) by piping
# test input through the tr commands from config.def.h and comparing
# byte-for-byte against expected output.
#
# Usage: sh test-case-conversion.sh
# Exit:  0 = all tests pass, 1 = failure

set -e

PASS=0
FAIL=0
TOTAL=0

# Temporary files for byte-exact comparison (avoids $(…) stripping trailing \n)
TMPDIR="${TMPDIR:-/tmp}"
T_IN="$TMPDIR/vis-test-in.$$"
T_EXP="$TMPDIR/vis-test-exp.$$"
T_ACT="$TMPDIR/vis-test-act.$$"
trap 'rm -f "$T_IN" "$T_EXP" "$T_ACT"' EXIT

run_test() {
    name="$1"
    cmd="$2"
    input="$3"
    expected="$4"

    TOTAL=$((TOTAL + 1))

    # Write input/expected to files, pipe through command, compare byte-for-byte
    printf '%s' "$input"    > "$T_IN"
    printf '%s' "$expected" > "$T_EXP"
    eval "$cmd" < "$T_IN" > "$T_ACT"

    if cmp -s "$T_EXP" "$T_ACT"; then
        PASS=$((PASS + 1))
        printf "PASS  %s\n" "$name"
    else
        FAIL=$((FAIL + 1))
        printf "FAIL  %s\n" "$name"
        printf "  expected: %s\n" "$(od -c < "$T_EXP" | head -3)"
        printf "  actual:   %s\n" "$(od -c < "$T_ACT" | head -3)"
    fi
}

# Commands from config.def.h (after fix)
CMD_GU="tr '[:upper:]' '[:lower:]'"
CMD_GUP="tr '[:lower:]' '[:upper:]'"
CMD_GTILDE="tr '[:lower:][:upper:]' '[:upper:][:lower:]'"

echo "=== Case conversion regression tests ==="
echo ""

# ---- Test 1: gu single word ----
run_test "gu single word" \
    "$CMD_GU" \
    "HELLO" \
    "hello"

# ---- Test 2: gU single word ----
run_test "gU single word" \
    "$CMD_GUP" \
    "hello" \
    "HELLO"

# ---- Test 3: gu multi-line ----
run_test "gu multi-line (2 lines)" \
    "$CMD_GU" \
    "HELLO WORLD
FOO BAR" \
    "hello world
foo bar"

# ---- Test 4: gU multi-line ----
run_test "gU multi-line (2 lines)" \
    "$CMD_GUP" \
    "hello world
foo bar" \
    "HELLO WORLD
FOO BAR"

# ---- Test 5: g~ multi-line (case swap) ----
run_test "g~ multi-line (3 lines)" \
    "$CMD_GTILDE" \
    "Hello
WORLD
foo Bar" \
    "hELLO
world
FOO bAR"

# ---- Test 6: gu with empty line in range ----
run_test "gu with empty line" \
    "$CMD_GU" \
    "Hello

World!
Foo-Bar 123" \
    "hello

world!
foo-bar 123"

# ---- Test 7: gU with empty line in range ----
run_test "gU with empty line" \
    "$CMD_GUP" \
    "hello

world!
foo-bar 123" \
    "HELLO

WORLD!
FOO-BAR 123"

# ---- Test 8: g~ with empty line in range ----
run_test "g~ with empty line" \
    "$CMD_GTILDE" \
    "Hello

World" \
    "hELLO

wORLD"

# ---- Test 9: gu preserves trailing newline ----
run_test "gu preserves trailing newline" \
    "$CMD_GU" \
    "HELLO
WORLD
" \
    "hello
world
"

# ---- Test 10: gU preserves trailing newline ----
run_test "gU preserves trailing newline" \
    "$CMD_GUP" \
    "hello
world
" \
    "HELLO
WORLD
"

# ---- Test 11: gu single line no trailing newline ----
run_test "gu single line (no trailing newline)" \
    "$CMD_GU" \
    "HELLO" \
    "hello"

# ---- Test 12: g~ preserves digits, punctuation, spaces ----
run_test "g~ preserves non-alpha characters" \
    "$CMD_GTILDE" \
    "Hello, World! 123 (test)" \
    "hELLO, wORLD! 123 (TEST)"

# ---- Test 13: gu all-punctuation line ----
run_test "gu preserves punctuation-only lines" \
    "$CMD_GU" \
    "---
!!!
..." \
    "---
!!!
..."

# ---- Test 14: Byte-level newline preservation ----
# This is the core regression test for the original bug.
# The old awk command would strip newlines, producing "ABCDEF"
# instead of "abc\ndef\n".
run_test "byte-level: gu multi-line preserves newlines" \
    "$CMD_GU" \
    "ABC
DEF
" \
    "abc
def
"

# ---- Summary ----
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    echo "REGRESSION DETECTED"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
