#!/bin/sh
# Simple smoke tests for the first NASM utility binaries.
# Keep this file boring: it should be easy to read and easy to run by hand.

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_status() {
    expected=$1
    shift

    set +e
    "$@" >/tmp/asmutils-test.out 2>/tmp/asmutils-test.err
    actual=$?
    set -e

    if [ "$actual" -ne "$expected" ]; then
        printf 'stdout:\n' >&2
        cat /tmp/asmutils-test.out >&2 || true
        printf 'stderr:\n' >&2
        cat /tmp/asmutils-test.err >&2 || true
        fail "expected status $expected from $*, got $actual"
    fi
}

assert_stdout() {
    expected=$1
    shift

    actual=$("$@")
    if [ "$actual" != "$expected" ]; then
        fail "expected stdout '$expected' from $*, got '$actual'"
    fi
}


# The applet index is intentionally small metadata, but it should stay present
# for each binary built by this first-pass Makefile.
for tool in true false echo yes pwd; do
    awk -F '\t' -v tool="$tool" 'NR > 1 && $1 == tool { found = 1 } END { exit found ? 0 : 1 }' "$ROOT_DIR/docs/applet_index.tsv" \
        || fail "docs/applet_index.tsv is missing $tool"
done

assert_status 0 "$BUILD_DIR/true"
assert_status 0 "$BUILD_DIR/true" ignored operands
assert_status 1 "$BUILD_DIR/false"
assert_status 1 "$BUILD_DIR/false" ignored operands

assert_stdout "" "$BUILD_DIR/echo"
assert_stdout "hello world" "$BUILD_DIR/echo" hello world

echo_n_file=/tmp/asmutils-echo-n.out
expected_echo_n_file=/tmp/asmutils-echo-n.expected
"$BUILD_DIR/echo" -n no-newline >"$echo_n_file"
printf 'no-newline' >"$expected_echo_n_file"
expected_size=10
actual_size=$(wc -c <"$echo_n_file" | tr -d ' ')
[ "$actual_size" -eq "$expected_size" ] || fail 'echo -n wrote the wrong byte count'
cmp -s "$echo_n_file" "$expected_echo_n_file" || fail 'echo -n did not write the expected text'

set +e
unsupported_stderr=$($BUILD_DIR/echo --help 2>&1 >/tmp/asmutils-echo-help.out)
unsupported_status=$?
set -e
[ "$unsupported_status" -eq 1 ] || fail 'echo --help should fail with status 1 in this teaching version'
case "$unsupported_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'echo --help did not explain the unsupported option' ;;
esac

# `yes` is infinite, so run it behind a reader that exits after a few lines.
# A broken pipe is acceptable; this test checks the recognizable output prefix.
yes_output=$($BUILD_DIR/yes assembly | sed -n '1,3{p;};3q')
expected_yes='assembly
assembly
assembly'
[ "$yes_output" = "$expected_yes" ] || fail 'yes did not repeat the provided operand'

assert_stdout "$(pwd -P)" "$BUILD_DIR/pwd"

set +e
pwd_stderr=$($BUILD_DIR/pwd --help 2>&1 >/tmp/asmutils-pwd-help.out)
pwd_status=$?
set -e
[ "$pwd_status" -eq 1 ] || fail 'pwd --help should fail with status 1 in this teaching version'
case "$pwd_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'pwd --help did not explain the unsupported option' ;;
esac

printf 'All tests passed.\n'
