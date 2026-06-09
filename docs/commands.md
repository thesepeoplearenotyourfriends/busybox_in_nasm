# Command notes

This file records the teaching contract for each implemented command. The source files stay flat under `src/`; difficulty and topic metadata live in documentation so a command remains easy to find by name.

## Implemented commands

### `true`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `exit-syscall`, `return-codes`, `smoke-test`.
- **Implemented behavior:** ignores all arguments and exits with status `0`.
- **Unsupported behavior:** GNU-style `--help` and `--version` are not implemented.
- **Syscalls used:** `exit(2)`.
- **Manual tests:**
  - `./build/true; echo $?`
  - `./build/true ignored operands; echo $?`
- **Known limitations:** no user-visible output or option diagnostics; this is intentional for the first exit-status lesson.

### `false`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `exit-syscall`, `return-codes`, `smoke-test`.
- **Implemented behavior:** ignores all arguments and exits with status `1`.
- **Unsupported behavior:** GNU-style `--help` and `--version` are not implemented.
- **Syscalls used:** `exit(2)`.
- **Manual tests:**
  - `./build/false; echo $?`
  - `./build/false ignored operands; echo $?`
- **Known limitations:** no user-visible output or option diagnostics; this is intentional for the first exit-status lesson.

### `echo`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `stdout`, `stderr`, `argv`, `write-syscall`, `option-subset`.
- **Implemented behavior:** prints operands separated by single spaces, prints a final newline by default, and supports one leading `-n` to suppress that newline.
- **Unsupported behavior:** escape interpretation (`-e`, `-E`, `\\n`, `\\t`), repeated or combined `-n` forms such as `-nn`, and `--help` / `--version`.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `./build/echo hello world`
  - `./build/echo -n no-newline; echo '<after>'`
  - `./build/echo --help; echo $?`
- **Known limitations:** unsupported leading dash options fail explicitly; later compatibility passes can decide whether to match BusyBox, GNU, or shell-builtin edge cases.

### `yes`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `stdout`, `argv`, `write-syscall`, `simple-loop`, `pipe-behavior`.
- **Implemented behavior:** with no operands, repeatedly prints `y`; with operands, repeatedly prints operands joined by spaces. Each output record ends with a newline.
- **Unsupported behavior:** no option parsing; operands beginning with `-` are ordinary text. Write errors are not converted to human-readable errno names yet.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `./build/yes | sed -n '1,3{p;};3q'`
  - `./build/yes assembly | sed -n '1,3{p;};3q'`
- **Known limitations:** writes each argument separately and treats short writes as failure. A later stream utility can teach buffered output and retry loops.


### `pwd`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `cwd`, `getcwd-syscall`, `stdout`.
- **Implemented behavior:** with no operands, asks the kernel for the current working directory and prints it followed by a newline.
- **Unsupported behavior:** logical `-L` behavior, explicit physical `-P` option handling, `--help`, `--version`, and extra operands.
- **Syscalls used:** `getcwd(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/pwd`
  - `test "$(./build/pwd)" = "$(pwd -P)"`
  - `./build/pwd --help; echo $?`
- **Known limitations:** prints the kernel physical cwd rather than a shell-maintained logical `$PWD`; uses a fixed 4096-byte buffer and prints a short diagnostic instead of decoding every errno value.


### `arch`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `utsname`, `uname-syscall`, `stdout`.
- **Implemented behavior:** asks the kernel for utsname data and prints the machine hardware name followed by a newline, matching the same field used by `uname -m`.
- **Unsupported behavior:** `--help`, `--version`, and operands are not diagnosed yet; extra words are ignored in this small teaching version.
- **Syscalls used:** `uname(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/arch`
  - `test "$(./build/arch)" = "$(uname -m)"`
- **Known limitations:** depends on Linux x86_64 utsname field layout and prints only the machine field.

### `ascii`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `stdout`, `write-syscall`, `static-table`.
- **Implemented behavior:** prints a compact 7-bit ASCII reference table with decimal value, hexadecimal value, and character or control-code name.
- **Unsupported behavior:** alternate formats, option parsing, locale-aware names, Unicode, `--help`, and `--version` are not implemented.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `./build/ascii | sed -n '1,5p'`
  - `./build/ascii | tail -n 1`
- **Known limitations:** this is a static educational table rather than a configurable formatter.

### `clear`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `stdout`, `write-syscall`, `terminal-escape`.
- **Implemented behavior:** writes the standard ANSI/VT100 clear-screen sequence `ESC [ H ESC [ 2 J` to stdout.
- **Unsupported behavior:** terminfo lookup, terminal-specific behavior, option parsing, `--help`, and `--version` are not implemented.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `./build/clear`
  - `./build/clear | od -An -tx1`
- **Known limitations:** assumes an ANSI-compatible terminal instead of consulting `$TERM`.

### `uname`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `utsname`, `uname-syscall`, `stdout`, `option-subset`.
- **Implemented behavior:** with no operands, prints the kernel name; with exactly `-m`, prints the machine hardware name.
- **Unsupported behavior:** `-a`, `-n`, `-r`, `-s`, `-v`, `-o`, long options, combined short options, and extra operands are rejected with a short diagnostic.
- **Syscalls used:** `uname(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `test "$(./build/uname)" = "$(uname)"`
  - `test "$(./build/uname -m)" = "$(uname -m)"`
  - `./build/uname -a; echo $?`
- **Known limitations:** reads only the `sysname` and `machine` fields from Linux utsname.

### `env`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `envp`, `stdout`, `write-syscall`, `initial-stack`, `option-subset`.
- **Implemented behavior:** with no operands, prints the current process environment as `NAME=VALUE` lines in the order supplied at process startup.
- **Unsupported behavior:** options, clearing or editing the environment, `NAME=VALUE` assignments, and command execution under a modified environment are rejected.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `env -i ASMUTILS_TEST_VALUE=abc ./build/env`
  - `./build/env --help; echo $?`
  - `./build/env NAME=VALUE; echo $?`
- **Known limitations:** this is only the envp-printing half of a real `env`; command launching and environment mutation can be added after process creation is introduced.

### `printenv`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `envp`, `stdout`, `argv`, `string-scan`, `write-syscall`, `option-subset`.
- **Implemented behavior:** with no operands, prints every environment entry as `NAME=VALUE`; with `NAME` operands, prints the value for each matching variable and exits nonzero if any requested name is missing.
- **Unsupported behavior:** options such as `--help`, `--version`, and GNU `-0` output are rejected.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `env -i ASMUTILS_TEST_VALUE=abc ./build/printenv`
  - `env -i ASMUTILS_TEST_VALUE=abc ./build/printenv ASMUTILS_TEST_VALUE`
  - `env -i ./build/printenv ASMUTILS_TEST_VALUE; echo $?`
- **Known limitations:** environment names are matched by a simple byte scan before the `=` separator; no locale or encoding behavior is involved.

### `sleep`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `nanosleep-syscall`, `argv`, `decimal-parse`, `timespec`.
- **Implemented behavior:** accepts exactly one unsigned decimal seconds operand and sleeps with `nanosleep(2)`.
- **Unsupported behavior:** fractional values, suffixes such as `m` / `h` / `d`, multiple operands, options, signal-aware restart loops, and parse overflow diagnostics are not implemented.
- **Syscalls used:** `nanosleep(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/sleep 0; echo $?`
  - `./build/sleep 1; echo $?`
  - `./build/sleep nope; echo $?`
- **Known limitations:** interrupted sleeps currently report failure instead of retrying the remaining timespec.

### `usleep`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `nanosleep-syscall`, `argv`, `decimal-parse`, `timespec`.
- **Implemented behavior:** accepts exactly one unsigned decimal microseconds operand, converts it to a seconds/nanoseconds timespec, and sleeps with `nanosleep(2)`.
- **Unsupported behavior:** options, multiple operands, suffixes, fractional values, signal-aware restart loops, and parse overflow diagnostics are not implemented.
- **Syscalls used:** `nanosleep(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/usleep 0; echo $?`
  - `./build/usleep 1000; echo $?`
  - `./build/usleep --help; echo $?`
- **Known limitations:** interrupted sleeps currently report failure instead of retrying the remaining timespec.


### `hostname`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `utsname`, `uname-syscall`, `stdout`, `option-subset`.
- **Implemented behavior:** with no operands, asks the kernel for utsname data and prints the node name followed by a newline.
- **Unsupported behavior:** setting the hostname, short options such as `-s` / `-f`, long options, and operands are rejected.
- **Syscalls used:** `uname(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `test "$(./build/hostname)" = "$(uname -n)"`
  - `./build/hostname --help; echo $?`
- **Known limitations:** reads only the Linux utsname `nodename` field and does not call `sethostname(2)`.

### `hostid`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `utsname`, `hostname-hash`, `stdout`, `hex-format`, `option-subset`.
- **Implemented behavior:** with no operands, reads the kernel `nodename` with `uname(2)`, computes a simple documented 32-bit FNV-1a hash of that name, and prints eight lowercase hexadecimal digits; these are first-pass semantics chosen for a readable no-libc lesson.
- **Unsupported behavior:** options, operands, libc `gethostid(3)`, `/etc/hostid`, DNS address lookups, and vendor-specific host ID policy are not implemented.
- **Syscalls used:** `uname(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/hostid`
  - `./build/hostid --help; echo $?`
- **Known limitations:** the output is a stable teaching identifier for the current kernel hostname, not a compatibility promise for GNU, BusyBox, or libc `hostid` output.

### `logname`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `envp`, `login-name-policy`, `stdout`, `option-subset`.
- **Implemented behavior:** with no operands, prints the value of the `LOGNAME` environment variable when it is present and non-empty; this first-pass semantic keeps login-name lookup focused on envp scanning.
- **Unsupported behavior:** options, operands, utmp/session lookup, controlling-terminal lookup, PAM/loginuid handling, and libc `getlogin(3)` are not implemented.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `env LOGNAME=student ./build/logname`
  - `env -i ./build/logname; echo $?`
  - `./build/logname --help; echo $?`
- **Known limitations:** this is intentionally environment-based, so it may disagree with real `logname` on systems where no login session exists or where `LOGNAME` has been edited.

### `nproc`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `sched-affinity`, `cpu-count`, `bit-count`, `stdout`, `decimal-format`, `option-subset`.
- **Implemented behavior:** with no operands, calls `sched_getaffinity(2)` for the current process, counts set bits in a fixed-size CPU mask, and prints that count as decimal; this first-pass semantic teaches affinity bitsets before broader CPU policy.
- **Unsupported behavior:** options such as `--all`, `--ignore=N`, environment variables, libc `sysconf(3)`, CPU hotplug races, masks larger than the teaching buffer, and cgroup quota interpretation are not implemented.
- **Syscalls used:** `sched_getaffinity(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/nproc`
  - `./build/nproc --help; echo $?`
- **Known limitations:** reports the number of CPUs allowed by the process affinity mask, up to 1024 CPUs, rather than every online CPU or every CPU quota rule a full userland might consider.

### `whoami`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `geteuid-syscall`, `passwd-file`, `account-lookup`, `stdout`, `option-subset`.
- **Implemented behavior:** with no operands, calls `geteuid(2)`, scans `/etc/passwd`, and prints the first user name whose UID field matches the effective UID.
- **Unsupported behavior:** options, operands, libc NSS backends, LDAP, systemd-homed, and multi-read handling for unusually large passwd files are not implemented.
- **Syscalls used:** `geteuid(2)`, `open(2)`, `read(2)`, `close(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `test "$(./build/whoami)" = "$(id -un)"`
  - `./build/whoami extra; echo $?`
- **Known limitations:** reads only `/etc/passwd` into one fixed buffer; systems where the effective UID is known only through another NSS backend will not resolve.

### `tty`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `ioctl-syscall`, `procfs`, `readlink-syscall`, `stdin`, `tty-detection`, `option-subset`.
- **Implemented behavior:** with no operands, checks stdin with `ioctl(TCGETS)` and then reads `/proc/self/fd/0` to print the terminal path; with `-s`, prints nothing and reports only success or failure.
- **Unsupported behavior:** long options and operands are rejected; this first pass does not use libc `ttyname(3)`.
- **Syscalls used:** `ioctl(2)`, `readlink(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/tty`
  - `./build/tty -s; echo $?`
  - `./build/tty </dev/null; echo $?`
- **Known limitations:** uses procfs to name the terminal after the ioctl check succeeds; systems without `/proc/self/fd/0` will not resolve a printable path.

### `ttysize`

- **Difficulty level:** 00 — primer / smoke-test command.
- **Tags:** `ioctl-syscall`, `terminal-size`, `stdin`, `decimal-format`.
- **Implemented behavior:** with no operands, calls `ioctl(TIOCGWINSZ)` on stdin and prints `rows columns` followed by a newline.
- **Unsupported behavior:** options, operands, alternate output formats, stdout/stderr terminal fallback, and pixel dimensions are not implemented.
- **Syscalls used:** `ioctl(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `./build/ttysize`
  - `./build/ttysize </dev/null; echo $?`
- **Known limitations:** requires stdin to be a terminal; redirected or piped stdin fails with a short diagnostic.


### `cat`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `stdin`, `stdout`, `file-read`, `buffer-loop`, `open-read-write-close`.
- **Implemented behavior:** with no operands, copies stdin to stdout; with file operands, copies each file in order; an operand of `-` copies stdin at that point in the operand list.
- **Unsupported behavior:** display options such as `-n`, `-b`, `-s`, `-A`, `-v`, `-e`, and `-t`, long options, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `open(2)`, `read(2)`, `write(2)`, `close(2)`, and `exit(2)`.
- **Manual tests:**
  - `printf 'one\ntwo\n' | ./build/cat`
  - `./build/cat README.md | cmp -s README.md -`
  - `./build/cat missing-file; echo $?`
- **Known limitations:** this is the plain copying subset only; it treats read/write failures as command failure but intentionally avoids an errno-to-string table for now.

### `head`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `stdin`, `stdout`, `file-read`, `line-counting`, `buffer-loop`.
- **Implemented behavior:** prints the first 10 newline-terminated lines from stdin or from one named file.
- **Unsupported behavior:** options such as `-n`, byte counts, multiple-file headers, quiet/verbose modes, long options, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `open(2)`, `read(2)`, `write(2)`, `close(2)`, and `exit(2)`.
- **Manual tests:**
  - `seq 12 | ./build/head`
  - `./build/head README.md`
  - `./build/head README.md docs/roadmap.md; echo $?`
- **Known limitations:** only the default 10-line subset is implemented, and at most one file operand is accepted.

### `wc`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `stdin`, `stdout`, `file-read`, `byte-line-word-counting`.
- **Implemented behavior:** with no operands, counts stdin; with file operands, prints default line, word, and byte counts for each file and prints a `total` line when more than one file operand was provided.
- **Unsupported behavior:** count-selection options such as `-l`, `-w`, `-c`, `-m`, and `-L`, long options, exact GNU/BSD column spacing, the conventional `-` stdin operand, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `open(2)`, `read(2)`, `write(2)`, `close(2)`, and `exit(2)`.
- **Manual tests:**
  - `printf 'one two\nthree\n' | ./build/wc`
  - `./build/wc README.md docs/commands.md`
  - `./build/wc missing-file; echo $?`
- **Known limitations:** words are separated by ASCII whitespace bytes only, counts are unsigned 64-bit values, and output uses simple `lines words bytes [name]` columns rather than compatibility spacing.

### `tee`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `stdin`, `stdout`, `file-write`, `buffer-loop`.
- **Implemented behavior:** copies stdin to stdout and to each named output file; a leading `-a` appends to output files instead of truncating them.
- **Unsupported behavior:** `-i`, long options, option clusters, more than 32 output files, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `open(2)`, `read(2)`, `write(2)`, `close(2)`, and `exit(2)`.
- **Manual tests:**
  - `printf 'save me\n' | ./build/tee /tmp/tee-one /tmp/tee-two`
  - `printf 'again\n' | ./build/tee -a /tmp/tee-one`
  - `./build/tee --help; echo $?`
- **Known limitations:** this version opens all output files before copying stdin, stops on the first open failure, and uses a fixed descriptor table to keep the assembly readable.

### `rev`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `stdin`, `stdout`, `string-scan`, `line-buffer`.
- **Implemented behavior:** reverses each line from stdin or from file operands in order; a `-` operand reads stdin at that point.
- **Unsupported behavior:** options, Unicode grapheme-aware reversal, dynamically allocated long-line handling, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `open(2)`, `read(2)`, `write(2)`, `close(2)`, and `exit(2)`.
- **Manual tests:**
  - `printf 'abc\ndef\n' | ./build/rev`
  - `./build/rev README.md | ./build/head`
  - `python3 -c "print('x' * 4097)" | ./build/rev; echo $?`
- **Known limitations:** lines are buffered before reversal and are limited to 4096 bytes including a trailing newline; bytes are reversed, not characters or grapheme clusters.

### `basename`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `path`, `string-scan`.
- **Implemented behavior:** accepts one pathname operand, removes trailing slash bytes, prints the bytes after the final slash, and prints `/` for operands made only of slashes.
- **Unsupported behavior:** suffix removal, `-a`, `-s`, `-z`, `--help`, and `--version` are not implemented.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `./build/basename /usr/bin/`
  - `./build/basename ///`
  - `./build/basename; echo $?`
- **Known limitations:** pathnames are treated as raw byte strings; no filesystem lookup, locale handling, or suffix processing is attempted.


### `dirname`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `path`, `string-scan`.
- **Implemented behavior:** accepts one pathname operand, removes trailing slash bytes, prints the directory portion, prints `/` for operands made only of slashes, and prints `.` when there is no directory portion.
- **Unsupported behavior:** `-z`, `--help`, `--version`, and multiple operands are not implemented.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `./build/dirname /usr/bin/`
  - `./build/dirname ///`
  - `./build/dirname plain`
- **Known limitations:** pathnames are treated as raw byte strings; no filesystem lookup, locale behavior, or NUL-separated output is attempted.

### `which`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `path-search`, `envp`, `access-syscall`, `string-scan`.
- **Implemented behavior:** searches `PATH` for each command operand, prints the first executable match, and tests operands containing `/` directly with `access(X_OK)`.
- **Unsupported behavior:** options such as `-a`, shell aliases/functions/builtins, hashed command tables, detailed permission diagnostics, `--help`, and `--version` are not implemented.
- **Syscalls used:** `access(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `PATH=/bin:/usr/bin ./build/which sh`
  - `./build/which ./build/which`
  - `PATH=/tmp ./build/which definitely-missing; echo $?`
- **Known limitations:** empty `PATH` components are printed as explicit `./name` candidates, candidates longer than the fixed 4096-byte teaching buffer are skipped, and this utility does not model shell-specific command lookup.

### `seq`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `stdout`, `argv`, `decimal-parse`, `decimal-format`, `simple-loop`.
- **Implemented behavior:** supports `seq LAST`, `seq FIRST LAST`, and `seq FIRST INCREMENT LAST` for increasing unsigned decimal integer sequences.
- **Unsupported behavior:** negative numbers, floating point, custom separators, equal-width output, printf-style formats, options, and overflow diagnostics are not implemented.
- **Syscalls used:** `write(2)` and `exit(2)`.
- **Manual tests:**
  - `./build/seq 3`
  - `./build/seq 2 2 6`
  - `./build/seq 1 0 3; echo $?`
- **Known limitations:** this is an unsigned-integer teaching subset; if incrementing would wrap an unsigned 64-bit value, output stops rather than reporting a detailed overflow error.

### `touch`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `file-create`, `timestamp`, `utimensat-syscall`, `open-close`.
- **Implemented behavior:** accepts one or more file operands, updates timestamps on existing files with `utimensat(2)`, and creates missing files with `open(O_CREAT)`.
- **Unsupported behavior:** options such as `-a`, `-c`, `-d`, `-m`, `-r`, `-t`, long options, custom timestamps, reference files, no-create mode, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `utimensat(2)`, `open(2)`, `close(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `rm -f /tmp/asm-touch && ./build/touch /tmp/asm-touch && test -f /tmp/asm-touch`
  - `./build/touch /tmp/asm-touch`
  - `./build/touch; echo $?`
- **Known limitations:** `touch` only falls back to file creation when `utimensat(2)` reports `ENOENT`, and it relies on the process umask to apply normal permission masking to newly created files.


### `mkdir`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `directory-create`, `mkdir-syscall`, `mode-bits`.
- **Implemented behavior:** accepts one or more directory operands and creates each with mode `0777`, subject to the process umask.
- **Unsupported behavior:** options such as `-p`, `-m`, `--help`, and `--version`, parent creation, custom modes, verbose output, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `mkdir(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `rm -rf /tmp/asm-mkdir && ./build/mkdir /tmp/asm-mkdir && test -d /tmp/asm-mkdir`
  - `./build/mkdir /tmp/asm-mkdir; echo $?`
  - `./build/mkdir; echo $?`
- **Known limitations:** this is the direct syscall subset only; it does not create missing parents and reports simple path-level failures rather than decoding errno values.

### `rmdir`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `directory-remove`, `rmdir-syscall`.
- **Implemented behavior:** accepts one or more directory operands and removes each empty directory with `rmdir(2)`.
- **Unsupported behavior:** options such as `-p`, `--ignore-fail-on-non-empty`, `--help`, and `--version`, recursive removal, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `rmdir(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `mkdir -p /tmp/asm-rmdir && ./build/rmdir /tmp/asm-rmdir && test ! -e /tmp/asm-rmdir`
  - `mkdir -p /tmp/asm-rmdir/nonempty && touch /tmp/asm-rmdir/nonempty/file && ./build/rmdir /tmp/asm-rmdir/nonempty; echo $?`
  - `./build/rmdir; echo $?`
- **Known limitations:** only empty directories can be removed, matching the kernel syscall; non-empty directories are failures rather than prompts or recursive operations.

### `unlink`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `file-remove`, `unlink-syscall`, `directory-entry`.
- **Implemented behavior:** accepts exactly one pathname operand and removes that directory entry with `unlink(2)`.
- **Unsupported behavior:** multiple operands, options such as `--help` and `--version`, recursive behavior, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `unlink(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `printf data >/tmp/asm-unlink && ./build/unlink /tmp/asm-unlink && test ! -e /tmp/asm-unlink`
  - `./build/unlink /tmp/missing-file; echo $?`
  - `./build/unlink one two; echo $?`
- **Known limitations:** directories are intentionally not removed by this command; use `rmdir` for empty directories in this teaching set.

### `ln`

- **Difficulty level:** 01 — beginner streams, strings, and simple file I/O.
- **Tags:** `hard-link`, `link-syscall`, `directory-entry`.
- **Implemented behavior:** accepts exactly two operands, `TARGET` and `LINK_NAME`, and creates a hard link with `link(2)`.
- **Unsupported behavior:** symbolic links (`-s`), force/interactive/no-dereference options, directory-target forms, backup behavior, long options, and errno-specific diagnostics are not implemented.
- **Syscalls used:** `link(2)`, `write(2)`, and `exit(2)`.
- **Manual tests:**
  - `printf data >/tmp/asm-ln-src && ./build/ln /tmp/asm-ln-src /tmp/asm-ln-dst && cmp -s /tmp/asm-ln-src /tmp/asm-ln-dst`
  - `./build/ln /tmp/missing-target /tmp/asm-ln-dst; echo $?`
  - `./build/ln only-one; echo $?`
- **Known limitations:** this first pass teaches hard links only and relies on filesystem support for hard links; cross-device links, directories, and existing destinations fail through the kernel.

## Roadmap direction

Implementation order is tracked in `docs/roadmap.md`.

Do not treat this file as the scheduling source. This file documents commands that exist or have implementation notes. When choosing the next command batch, consult `docs/roadmap.md` and `docs/command_index.tsv`.
