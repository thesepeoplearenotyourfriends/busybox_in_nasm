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


# The command index is intentionally small metadata, but it should stay present
# for each binary built by this first-pass Makefile.
for tool in true false echo yes pwd arch ascii clear uname env printenv sleep usleep hostname hostid logname nproc whoami tty ttysize cat head wc tee rev basename dirname which seq touch mkdir rmdir unlink ln readlink realpath stat; do
    awk -F '\t' -v tool="$tool" 'NR > 1 && $1 == tool { found = 1 } END { exit found ? 0 : 1 }' "$ROOT_DIR/docs/command_index.tsv" \
        || fail "docs/command_index.tsv is missing $tool"
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

cat_input=/tmp/asmutils-cat.input
cat_output=/tmp/asmutils-cat.output
printf 'alpha\nbeta\ngamma\n' >"$cat_input"
"$BUILD_DIR/cat" "$cat_input" - >"$cat_output" <<'CAT_STDIN'
delta
epsilon
CAT_STDIN
printf 'alpha\nbeta\ngamma\ndelta\nepsilon\n' >/tmp/asmutils-cat.expected
cmp -s "$cat_output" /tmp/asmutils-cat.expected || fail 'cat did not copy file and stdin operands in order'

head_input=/tmp/asmutils-head.input
awk 'BEGIN { for (i = 1; i <= 12; i++) printf "line %d\n", i }' >"$head_input"
head_output=$("$BUILD_DIR/head" "$head_input")
expected_head=$(sed -n '1,10p' "$head_input")
[ "$head_output" = "$expected_head" ] || fail 'head did not print the first ten lines'

wc_one=/tmp/asmutils-wc-one.input
wc_two=/tmp/asmutils-wc-two.input
printf 'one two\nthree\n' >"$wc_one"
printf 'x y z' >"$wc_two"
assert_stdout "2 3 14" "$BUILD_DIR/wc" <"$wc_one"
expected_wc_files="2 3 14 $wc_one
0 3 5 $wc_two
2 6 19 total"
actual_wc_files=$("$BUILD_DIR/wc" "$wc_one" "$wc_two")
[ "$actual_wc_files" = "$expected_wc_files" ] || fail 'wc did not print file counts and total'

tee_one=/tmp/asmutils-tee-one.output
tee_two=/tmp/asmutils-tee-two.output
rm -f "$tee_one" "$tee_two"
tee_stdout=$(printf 'tee line\n' | "$BUILD_DIR/tee" "$tee_one" "$tee_two")
[ "$tee_stdout" = 'tee line' ] || fail 'tee did not copy stdin to stdout'
printf 'tee line\n' >/tmp/asmutils-tee.expected
cmp -s "$tee_one" /tmp/asmutils-tee.expected || fail 'tee did not write first file'
cmp -s "$tee_two" /tmp/asmutils-tee.expected || fail 'tee did not write second file'
printf 'again\n' | "$BUILD_DIR/tee" -a "$tee_one" >/dev/null
printf 'tee line\nagain\n' >/tmp/asmutils-tee-append.expected
cmp -s "$tee_one" /tmp/asmutils-tee-append.expected || fail 'tee -a did not append'

rev_input=/tmp/asmutils-rev.input
printf 'abc\ndef\nno-newline' >"$rev_input"
expected_rev='cba
fed
enilwen-on'
actual_rev=$("$BUILD_DIR/rev" "$rev_input")
[ "$actual_rev" = "$expected_rev" ] || fail 'rev did not reverse each line'

assert_stdout "bin" "$BUILD_DIR/basename" /usr/bin/
assert_stdout "/" "$BUILD_DIR/basename" ///
assert_stdout "plain" "$BUILD_DIR/basename" plain
assert_status 1 "$BUILD_DIR/basename"

assert_stdout "/usr" "$BUILD_DIR/dirname" /usr/bin/
assert_stdout "/" "$BUILD_DIR/dirname" ///
assert_stdout "." "$BUILD_DIR/dirname" plain
assert_status 1 "$BUILD_DIR/dirname"

expected_seq='1
2
3'
actual_seq=$("$BUILD_DIR/seq" 3)
[ "$actual_seq" = "$expected_seq" ] || fail 'seq LAST did not print 1 through LAST'
expected_seq_step='2
4
6'
actual_seq_step=$("$BUILD_DIR/seq" 2 2 6)
[ "$actual_seq_step" = "$expected_seq_step" ] || fail 'seq FIRST INCREMENT LAST did not step correctly'
assert_status 1 "$BUILD_DIR/seq" 1 0 3

which_dir=/tmp/asmutils-which-bin
rm -rf "$which_dir"
mkdir -p "$which_dir"
printf '#!/bin/sh\nexit 0\n' >"$which_dir/demo-tool"
chmod +x "$which_dir/demo-tool"
assert_stdout "$which_dir/demo-tool" env PATH="$which_dir" "$BUILD_DIR/which" demo-tool
assert_stdout "$which_dir/demo-tool" "$BUILD_DIR/which" "$which_dir/demo-tool"
assert_status 1 env PATH="$which_dir" "$BUILD_DIR/which" missing-tool

touch_file=/tmp/asmutils-touch-file
rm -f "$touch_file"
assert_status 0 "$BUILD_DIR/touch" "$touch_file"
[ -f "$touch_file" ] || fail 'touch did not create a missing file'
assert_status 0 "$BUILD_DIR/touch" "$touch_file"

mkdir_dir=/tmp/asmutils-mkdir-dir
rm -rf "$mkdir_dir"
assert_status 0 "$BUILD_DIR/mkdir" "$mkdir_dir"
[ -d "$mkdir_dir" ] || fail 'mkdir did not create the requested directory'
assert_status 1 "$BUILD_DIR/mkdir" "$mkdir_dir"

rmdir_dir=/tmp/asmutils-rmdir-dir
rm -rf "$rmdir_dir"
mkdir -p "$rmdir_dir"
assert_status 0 "$BUILD_DIR/rmdir" "$rmdir_dir"
[ ! -e "$rmdir_dir" ] || fail 'rmdir did not remove the empty directory'
assert_status 1 "$BUILD_DIR/rmdir" "$rmdir_dir"

unlink_file=/tmp/asmutils-unlink-file
printf 'remove me
' >"$unlink_file"
assert_status 0 "$BUILD_DIR/unlink" "$unlink_file"
[ ! -e "$unlink_file" ] || fail 'unlink did not remove the file name'
assert_status 1 "$BUILD_DIR/unlink" "$unlink_file"
assert_status 1 "$BUILD_DIR/unlink" one two

ln_source=/tmp/asmutils-ln-source
ln_link=/tmp/asmutils-ln-link
rm -f "$ln_source" "$ln_link"
printf 'linked data
' >"$ln_source"
assert_status 0 "$BUILD_DIR/ln" "$ln_source" "$ln_link"
cmp -s "$ln_source" "$ln_link" || fail 'ln did not create a readable hard link'
source_inode=$(stat -c %i "$ln_source")
link_inode=$(stat -c %i "$ln_link")
[ "$source_inode" = "$link_inode" ] || fail 'ln result does not share the source inode'
assert_status 1 "$BUILD_DIR/ln" "$ln_source"
assert_status 1 "$BUILD_DIR/ln" "$ln_source" "$ln_link" extra

readlink_target=/tmp/asmutils-readlink-target
readlink_link=/tmp/asmutils-readlink-link
rm -f "$readlink_target" "$readlink_link"
printf 'target data
' >"$readlink_target"
ln -s "$readlink_target" "$readlink_link"
assert_stdout "$readlink_target" "$BUILD_DIR/readlink" "$readlink_link"
assert_status 1 "$BUILD_DIR/readlink" "$readlink_target"
assert_status 1 "$BUILD_DIR/readlink" "$readlink_link" extra

realpath_dir=/tmp/asmutils-realpath-dir
rm -rf "$realpath_dir"
mkdir -p "$realpath_dir/sub"
printf 'real data
' >"$realpath_dir/sub/file"
assert_stdout "$realpath_dir/sub/file" "$BUILD_DIR/realpath" "$realpath_dir/./sub/../sub/file"
assert_stdout "$readlink_target" "$BUILD_DIR/realpath" "$readlink_link"
assert_status 1 "$BUILD_DIR/realpath" "$realpath_dir/missing"

stat_file=/tmp/asmutils-stat-file
printf '1234567890
' >"$stat_file"
stat_output=$("$BUILD_DIR/stat" "$stat_file")
expected_stat_prefix="Size: $(stat -c %s "$stat_file")
Mode: $(printf "%d" "0$(stat -c %a "$stat_file")")
Inode: $(stat -c %i "$stat_file")
Links: $(stat -c %h "$stat_file")"
[ "$stat_output" = "$expected_stat_prefix" ] || fail 'stat did not print the expected metadata summary'
assert_status 1 "$BUILD_DIR/stat" "$stat_file" extra

assert_stdout "$(uname -m)" "$BUILD_DIR/arch"
assert_stdout "$(uname -n)" "$BUILD_DIR/hostname"

hostid_output=$("$BUILD_DIR/hostid")
case "$hostid_output" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) fail "hostid did not print eight lowercase hexadecimal digits: $hostid_output" ;;
esac

assert_stdout "student" env LOGNAME=student "$BUILD_DIR/logname"
assert_status 1 env -i "$BUILD_DIR/logname"
assert_stdout "$(nproc)" "$BUILD_DIR/nproc"
assert_stdout "$(id -un)" "$BUILD_DIR/whoami"
assert_stdout "$(uname)" "$BUILD_DIR/uname"
assert_stdout "$(uname -m)" "$BUILD_DIR/uname" -m

controlled_env_output=$(env -i ASMUTILS_TEST_VALUE=abc OTHER_VALUE=def "$BUILD_DIR/env")
expected_controlled_env='ASMUTILS_TEST_VALUE=abc
OTHER_VALUE=def'
[ "$controlled_env_output" = "$expected_controlled_env" ] || fail 'env did not print the controlled environment'

assert_stdout "abc" env -i ASMUTILS_TEST_VALUE=abc "$BUILD_DIR/printenv" ASMUTILS_TEST_VALUE
assert_stdout 'abc
def' env -i ASMUTILS_TEST_VALUE=abc OTHER_VALUE=def "$BUILD_DIR/printenv" ASMUTILS_TEST_VALUE OTHER_VALUE
assert_status 1 env -i "$BUILD_DIR/printenv" ASMUTILS_TEST_VALUE

assert_status 0 "$BUILD_DIR/sleep" 0
assert_status 0 "$BUILD_DIR/usleep" 0

set +e
tty_not_tty_output=$("$BUILD_DIR/tty" </dev/null)
tty_not_tty_status=$?
set -e
[ "$tty_not_tty_status" -eq 1 ] || fail 'tty should fail with status 1 without a terminal on stdin'
[ "$tty_not_tty_output" = "not a tty" ] || fail 'tty did not report non-tty stdin'
assert_status 1 "$BUILD_DIR/tty" -s </dev/null

set +e
ttysize_stderr=$("$BUILD_DIR/ttysize" </dev/null 2>&1 >/tmp/asmutils-ttysize.out)
ttysize_status=$?
set -e
[ "$ttysize_status" -eq 1 ] || fail 'ttysize should fail with status 1 without a terminal on stdin'
case "$ttysize_stderr" in
    *"ioctl TIOCGWINSZ failed"*) ;;
    *) fail 'ttysize did not explain the ioctl failure' ;;
esac

set +e
sleep_stderr=$($BUILD_DIR/sleep nope 2>&1 >/tmp/asmutils-sleep-bad.out)
sleep_status=$?
set -e
[ "$sleep_status" -eq 1 ] || fail 'sleep with a non-decimal operand should fail with status 1'
case "$sleep_stderr" in
    *"invalid seconds: nope"*) ;;
    *) fail 'sleep did not explain the invalid operand' ;;
esac

set +e
usleep_stderr=$($BUILD_DIR/usleep --help 2>&1 >/tmp/asmutils-usleep-help.out)
usleep_status=$?
set -e
[ "$usleep_status" -eq 1 ] || fail 'usleep --help should fail with status 1 in this teaching version'
case "$usleep_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'usleep --help did not explain the unsupported option' ;;
esac

ascii_head=$($BUILD_DIR/ascii | sed -n '1,4p')
expected_ascii_head='Dec Hex Chr
  0 00  NUL
  1 01  SOH
  2 02  STX'
[ "$ascii_head" = "$expected_ascii_head" ] || fail 'ascii table did not start with the expected rows'

ascii_tail=$($BUILD_DIR/ascii | tail -n 1)
[ "$ascii_tail" = '127 7F  DEL' ] || fail 'ascii table did not end with DEL'

clear_file=/tmp/asmutils-clear.out
expected_clear_file=/tmp/asmutils-clear.expected
"$BUILD_DIR/clear" >"$clear_file"
printf '\033[H\033[2J' >"$expected_clear_file"
cmp -s "$clear_file" "$expected_clear_file" || fail 'clear did not write the expected escape sequence'

set +e
pwd_stderr=$($BUILD_DIR/pwd --help 2>&1 >/tmp/asmutils-pwd-help.out)
pwd_status=$?
set -e
[ "$pwd_status" -eq 1 ] || fail 'pwd --help should fail with status 1 in this teaching version'
case "$pwd_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'pwd --help did not explain the unsupported option' ;;
esac

set +e
hostid_stderr=$($BUILD_DIR/hostid --help 2>&1 >/tmp/asmutils-hostid-help.out)
hostid_status=$?
set -e
[ "$hostid_status" -eq 1 ] || fail 'hostid --help should fail with status 1 in this teaching version'
case "$hostid_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'hostid --help did not explain the unsupported option' ;;
esac

set +e
logname_stderr=$($BUILD_DIR/logname --help 2>&1 >/tmp/asmutils-logname-help.out)
logname_status=$?
set -e
[ "$logname_status" -eq 1 ] || fail 'logname --help should fail with status 1 in this teaching version'
case "$logname_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'logname --help did not explain the unsupported option' ;;
esac

set +e
nproc_stderr=$($BUILD_DIR/nproc --help 2>&1 >/tmp/asmutils-nproc-help.out)
nproc_status=$?
set -e
[ "$nproc_status" -eq 1 ] || fail 'nproc --help should fail with status 1 in this teaching version'
case "$nproc_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'nproc --help did not explain the unsupported option' ;;
esac

set +e
hostname_stderr=$($BUILD_DIR/hostname --help 2>&1 >/tmp/asmutils-hostname-help.out)
hostname_status=$?
set -e
[ "$hostname_status" -eq 1 ] || fail 'hostname --help should fail with status 1 in this teaching version'
case "$hostname_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'hostname --help did not explain the unsupported option' ;;
esac

set +e
whoami_stderr=$($BUILD_DIR/whoami extra 2>&1 >/tmp/asmutils-whoami-extra.out)
whoami_status=$?
set -e
[ "$whoami_status" -eq 1 ] || fail 'whoami with an operand should fail with status 1'
case "$whoami_stderr" in
    *"unexpected operand: extra"*) ;;
    *) fail 'whoami did not explain the unexpected operand' ;;
esac

set +e
tty_stderr=$($BUILD_DIR/tty --help 2>&1 >/tmp/asmutils-tty-help.out)
tty_status=$?
set -e
[ "$tty_status" -eq 1 ] || fail 'tty --help should fail with status 1 in this teaching version'
case "$tty_stderr" in
    *"unsupported option: --help"*) ;;
    *) fail 'tty --help did not explain the unsupported option' ;;
esac

set +e
uname_stderr=$($BUILD_DIR/uname -a 2>&1 >/tmp/asmutils-uname-a.out)
uname_status=$?
set -e
[ "$uname_status" -eq 1 ] || fail 'uname -a should fail with status 1 in this teaching version'
case "$uname_stderr" in
    *"unsupported option: -a"*) ;;
    *) fail 'uname -a did not explain the unsupported option' ;;
esac

printf 'All tests passed.\n'
