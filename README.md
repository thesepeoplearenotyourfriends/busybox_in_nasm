# BusyBox-inspired NASM utilities

This repository is a human-steered, GPT/Codex authored, educational collection of familiar Linux command-line utilities written in NASM-compatible x86_64 assembly.

The project uses BusyBox as a practical roadmap for recognizable command names, but it is **not** a BusyBox clone and does not copy BusyBox implementation code. Each utility is built as its own standalone binary so the assembly stays readable and each program can teach one low-level idea at a time.

## Goals

The first utilities are intentionally small. They demonstrate:

- process entry at `_start` without a C runtime
- Linux x86_64 system calls
- process exit status
- simple file descriptor I/O with `read(2)` and `write(2)`
- reading `argc` and `argv` from the initial stack
- straightforward string scanning in assembly
- reusable buffer loops for stdin/stdout, file input, and file output
- fixed table output and terminal escape sequences
- simple kernel information queries with `uname(2)`, `getcwd(2)`, and `ioctl(2)`
- environment pointer (`envp`) traversal from the initial stack
- simple account-name lookup by scanning `/etc/passwd`
- pathname component scanning, `PATH` lookup, and executable checks
- unsigned decimal parsing for delays and sequence generation
- decimal output formatting for generated numbers
- simple timestamp/file creation syscalls with `utimensat(2)` and `open(2)`
- directory entry operations with `mkdir(2)`, `rmdir(2)`, `unlink(2)`, and `link(2)`
- `nanosleep(2)` timespec setup
- simple shell-based regression tests

Educational clarity is more important than cleverness, size, or speed.

Level 00 is complete — time for cake and confetti! 🎂🎊

## Maturity model

Having a source file means that a command's teaching mechanism exists; it does
not by itself mean that the command is ready for routine shell use or compatible
with another implementation.  The project uses these cumulative maturity
states:

- **`mechanism-complete`** — the source builds and demonstrates its stated
  low-level mechanism, its implemented behavior and important limitations are
  documented, and focused smoke tests cover that teaching contract.  It may
  still omit ordinary command behavior or robust I/O edge cases.
- **`daily-use complete`** — in addition to being mechanism-complete, the
  command satisfies **all applicable** daily-use criteria below.  This is an
  objective engineering gate, not a judgment that the source merely feels
  useful.
- **`compatibility-complete`** — in addition to being daily-use complete, the
  project deliberately names a compatibility profile (for example, a specific
  BusyBox release or GNU coreutils release), documents the profile's supported
  surface and intentional deviations, and tests the command against that named
  reference.  Similar-looking output or a command name borrowed from a roadmap
  is not a compatibility claim.

### Daily-use completion criteria

A daily-use command must have tests and documented behavior covering:

1. ordinary invocation and ordinary operand behavior;
2. common options for the deliberately supported command surface;
3. conventional stdin behavior and `-` as stdin wherever the command class
   conventionally accepts input streams;
4. correct success and failure exit statuses, including mixed-operand failures;
5. retrying interrupted (`EINTR`) operations and correctly completing partial
   reads/writes where the relevant syscall permits them;
6. detection and explicit failure for fixed-buffer truncation rather than
   silently returning incomplete data;
7. binary-safe data handling where the utility operates on byte streams;
8. useful diagnostics that identify the command, operation or operand that
   failed; and
9. differential tests against a **named reference implementation and version**
   for the behavior claimed by the daily-use surface.  Passing these tests does
   not create a compatibility profile; that requires the additional deliberate
   scope and deviation record described above.

An item may be marked not applicable only when the command's documented
contract explains why (for example, `true` has no input stream).  The current
audit inspected the actual `src/*.asm` implementations and the contracts in
`docs/commands.md`, rather than inferring maturity from the roadmap.  `head`,
`wc`, and `stat` meet the daily-use gate, including differential coverage
against GNU coreutils 9.4.  The other commands remain `mechanism-complete`;
several still do not retry `EINTR` or have a versioned named-reference
differential suite.  No compatibility profile has yet been selected.

## Current utilities

| Utility | Level | Source | Maturity | Notes |
| --- | ---: | --- | --- | --- |
| `true` | 00 | source exists | `mechanism-complete` | exits with status 0 |
| `false` | 00 | source exists | `mechanism-complete` | exits with status 1 |
| `echo` | 00 | source exists | `mechanism-complete` | [🔗](docs/notes/echo.md) supports plain operands and `-n`; unsupported option handling is intentionally explicit |
| `yes` | 00 | source exists | `mechanism-complete` | writes `y` repeatedly, or the provided operands joined by spaces |
| `pwd` | 00 | source exists | `mechanism-complete` | prints the kernel current working directory with `getcwd(2)` |
| `arch` | 00 | source exists | `mechanism-complete` | prints the machine hardware name from `uname(2)` |
| `ascii` | 00 | source exists | `mechanism-complete` | [🔗](docs/notes/ascii.md) prints a compact 7-bit ASCII reference table |
| `clear` | 00 | source exists | `mechanism-complete` | [🔗](docs/notes/clear.md) writes an ANSI/VT100 clear-screen sequence |
| `uname` | 00 | source exists | `mechanism-complete` | prints the kernel name by default; supports `-m` |
| `env` | 00 | source exists | `mechanism-complete` | [🔗](docs/notes/env.md) prints the current environment; editing and command execution are not implemented |
| `printenv` | 00 | source exists | `mechanism-complete` | [🔗](docs/notes/printenv.md) prints all environment entries or selected variable values |
| `sleep` | 00 | source exists | `mechanism-complete` | sleeps for one unsigned decimal seconds operand |
| `usleep` | 00 | source exists | `mechanism-complete` | [🔗](docs/notes/usleep.md) sleeps for one unsigned decimal microseconds operand |
| `hostname` | 00 | source exists | `mechanism-complete` | prints the kernel node name from `uname(2)` |
| `hostid` | 00 | source exists | `mechanism-complete` | prints an eight-hex-digit FNV-1a teaching identifier from the kernel node name |
| `logname` | 00 | source exists | `mechanism-complete` | prints the non-empty `LOGNAME` environment value in this envp-focused first pass |
| `nproc` | 00 | source exists | `mechanism-complete` | counts CPUs allowed by the current process affinity mask |
| `whoami` | 00 | source exists | `mechanism-complete` | prints the effective user name by scanning `/etc/passwd` for `geteuid(2)` |
| `tty` | 00 | source exists | `mechanism-complete` | checks stdin with `ioctl(TCGETS)` and prints its terminal path; supports silent `-s` |
| `ttysize` | 00 | source exists | `mechanism-complete` | [🔗](docs/notes/ttysize.md) prints terminal rows and columns from `ioctl(TIOCGWINSZ)` on stdin |
| `cat` | 01 | source exists | `mechanism-complete` | [🔗](docs/notes/cat.md) copies stdin or named files to stdout with a fixed buffer and write-all loop |
| `head` | 01 | source exists | `daily-use complete` | defaults to 10 lines; supports `-n`, `-c`, stdin/file operands, and automatic multi-file headers |
| `wc` | 01 | source exists | `daily-use complete` | [🔗](docs/notes/wc.md) selectable line, word, byte, UTF-8 character, and maximum byte-line counts |
| `tee` | 01 | source exists | `mechanism-complete` | copies stdin to stdout and to one or more files; supports simple `-a` append mode |
| `rev` | 01 | source exists | `mechanism-complete` | reverses each input line using a documented 4096-byte line buffer limit |
| `basename` | 01 | source exists | `mechanism-complete` | strips directory prefixes and trailing slashes from one pathname operand |
| `dirname` | 01 | source exists | `mechanism-complete` | prints the directory component of one pathname operand |
| `which` | 01 | source exists | `mechanism-complete` | searches `PATH` for executable command names, or checks paths that contain `/` |
| `seq` | 01 | source exists | `mechanism-complete` | prints increasing unsigned decimal sequences for 1-, 2-, or 3-operand forms |
| `touch` | 01 | source exists | `mechanism-complete` | updates file timestamps with `utimensat(2)` and creates missing files with `open(2)` |
| `mkdir` | 01 | source exists | `mechanism-complete` | supports `-p`, exact octal `-m`, `--`, and aggregate multi-operand failure |
| `rmdir` | 01 | source exists | `mechanism-complete` | removes one or more empty directories |
| `unlink` | 01 | source exists | `mechanism-complete` | removes one pathname with `unlink(2)` |
| `ln` | 01 | source exists | `mechanism-complete` | supports hard/symbolic links, `-f`, `--`, and destination-directory forms |
| `link` | 01 | source exists | `mechanism-complete` | accepts exactly `FILE LINK_NAME` and creates a hard link with `link(2)`; no options or symbolic links |
| `sync` | 01 | source exists | `mechanism-complete` | accepts no operands and calls global `sync(2)`; per-file modes and options are not implemented |
| `fsync` | 01 | source exists | `mechanism-complete` | opens exactly one pathname read-only, calls `fsync(2)`, and closes it; diagnostics are intentionally brief |
| `readlink` | 02 | source exists | `mechanism-complete` | prints the raw target of exactly one symbolic link; it does not canonicalize paths or support options |
| `realpath` | 02 | source exists | `mechanism-complete` | resolves one existing pathname through `/proc/self/fd`; procfs is required and missing-path modes are not supported |
| `stat` | 02 | source exists | `daily-use complete` | readable multi-path metadata, default link inspection, `-L`, and stable `--stable` records |
| `cmp` | 01 | source exists | `daily-use complete` | buffered binary comparison with `-l`, `-s`, `-n`, decimal skips, and stdin support |

Difficulty and topic metadata are tracked in `docs/command_index.tsv`; per-command teaching contracts are tracked in `docs/commands.md`. Source files stay flat under `src/` so commands remain easy to find by name.

## Companion notes

Some commands have companion notes under [`docs/notes/`](docs/notes/). In the utility table, a 🔗 icon marks commands with a corresponding note.

They are meant to be read with the corresponding `.asm` file open nearby, pointing out the structure, intent, low-level habits, and places where assembly can look stranger than it really is.

The goal is approachable, not simplified-to-death: useful margin notes for someone who already wants to understand what the code is doing.

## Requirements

- Linux on x86_64
- `make`
- `nasm`
- `ld` from GNU binutils or a compatible linker
- POSIX-ish shell for tests
- GNU coreutils 9.4 for the **differential test suite only**
- GNU diffutils 3.10 for the `cmp` **differential test suite only**
- Python 3 for constructing byte-exact expected `stat --stable` records in tests

## Build

```sh
make
```

Binaries are written to `build/`:

```text
build/true
build/false
build/echo
build/yes
build/pwd
build/arch
build/ascii
build/clear
build/uname
build/env
build/printenv
build/sleep
build/usleep
build/hostname
build/hostid
build/logname
build/nproc
build/whoami
build/tty
build/ttysize
build/cat
build/head
build/wc
build/tee
build/rev
build/basename
build/dirname
build/which
build/seq
build/touch
build/mkdir
build/rmdir
build/unlink
build/ln
build/link
build/sync
build/fsync
build/readlink
build/realpath
build/stat
build/cmp
```

## Test

```sh
make test
```

The tests are deliberately small shell checks. They are meant to catch obvious regressions, not to become a full test framework.

## Manual examples

```sh
./build/true
echo $?

./build/false
echo $?

./build/echo hello world
./build/echo -n no-newline

timeout 1 ./build/yes assembly

./build/pwd

./build/arch

./build/ascii | sed -n '1,5p'

./build/clear

./build/uname
./build/uname -m

env -i ASMUTILS_TEST_VALUE=abc ./build/env
env -i ASMUTILS_TEST_VALUE=abc ./build/printenv ASMUTILS_TEST_VALUE

./build/sleep 0
./build/usleep 1000

./build/hostname
./build/hostid
env LOGNAME=student ./build/logname
./build/nproc
./build/whoami
./build/tty
./build/tty -s
./build/ttysize

printf 'one\ntwo\n' | ./build/cat
./build/cat README.md | ./build/head
printf 'one two\nthree\n' | ./build/wc
printf 'save me\n' | ./build/tee /tmp/asmutils-tee-example
printf 'abc\ndef\n' | ./build/rev
./build/basename /usr/bin/
./build/dirname /usr/bin/
PATH=/bin:/usr/bin ./build/which sh
./build/seq 2 2 6
rm -f /tmp/asmutils-touch-example
./build/touch /tmp/asmutils-touch-example
test -f /tmp/asmutils-touch-example
rm -rf /tmp/asmutils-dir-example
./build/mkdir /tmp/asmutils-dir-example
./build/rmdir /tmp/asmutils-dir-example
printf data >/tmp/asmutils-unlink-example
./build/unlink /tmp/asmutils-unlink-example
printf data >/tmp/asmutils-ln-source
rm -f /tmp/asmutils-ln-link
./build/ln /tmp/asmutils-ln-source /tmp/asmutils-ln-link
rm -f /tmp/asmutils-link-copy
./build/link /tmp/asmutils-ln-source /tmp/asmutils-link-copy
./build/sync
./build/fsync /tmp/asmutils-ln-source
ln -sf /tmp/asmutils-ln-source /tmp/asmutils-readlink
./build/readlink /tmp/asmutils-readlink
./build/realpath ./src/../src/true.asm
./build/stat /tmp/asmutils-ln-source
```

## Project philosophy

- Prefer raw syscalls when they teach the mechanism.
- Prefer plain procedural assembly over macro frameworks.
- Keep each tool readable as a standalone lesson.
- Document missing behavior honestly.
- Add compatibility gradually after the educational core is clear.

See `docs/style_guide.md`, `docs/linux_syscall_abi.md`, `docs/roadmap.md`, `docs/command_index.tsv`, and `docs/commands.md` for more details.
