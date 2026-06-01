# BusyBox-inspired NASM utilities

This repository is an educational collection of familiar Linux command-line utilities written in NASM-compatible x86_64 assembly.

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
- unsigned decimal parsing and `nanosleep(2)` timespec setup
- simple shell-based regression tests

Educational clarity is more important than cleverness, size, or speed.

Level 00 is complete — time for cake and confetti! 🎂🎊

## Current utilities

| Utility | Level | Status | Notes |
| --- | ---: | --- | --- |
| `true` | 00 | ✅ | exits with status 0 |
| `false` | 00 | ✅ | exits with status 1 |
| `echo` | 00 | ✅ | supports plain operands and `-n`; unsupported option handling is intentionally explicit |
| `yes` | 00 | ✅ | writes `y` repeatedly, or the provided operands joined by spaces |
| `pwd` | 00 | ✅ | prints the kernel current working directory with `getcwd(2)` |
| `arch` | 00 | ✅ | prints the machine hardware name from `uname(2)` |
| `ascii` | 00 | ✅ | prints a compact 7-bit ASCII reference table |
| `clear` | 00 | ✅ | writes an ANSI/VT100 clear-screen sequence |
| `uname` | 00 | ✅ | prints the kernel name by default; supports `-m` |
| `env` | 00 | ✅ | prints the current environment; editing and command execution are not implemented |
| `printenv` | 00 | ✅ | prints all environment entries or selected variable values |
| `sleep` | 00 | ✅ | sleeps for one unsigned decimal seconds operand |
| `usleep` | 00 | ✅ | sleeps for one unsigned decimal microseconds operand |
| `hostname` | 00 | ✅ | prints the kernel node name from `uname(2)` |
| `hostid` | 00 | ✅ | prints an eight-hex-digit FNV-1a teaching identifier from the kernel node name |
| `logname` | 00 | ✅ | prints the non-empty `LOGNAME` environment value in this envp-focused first pass |
| `nproc` | 00 | ✅ | counts CPUs allowed by the current process affinity mask |
| `whoami` | 00 | ✅ | prints the effective user name by scanning `/etc/passwd` for `geteuid(2)` |
| `tty` | 00 | ✅ | checks stdin with `ioctl(TCGETS)` and prints its terminal path; supports silent `-s` |
| `ttysize` | 00 | ✅ | prints terminal rows and columns from `ioctl(TIOCGWINSZ)` on stdin |
| `cat` | 01 | ✅ | copies stdin or named files to stdout with a fixed buffer and write-all loop |
| `head` | 01 | ✅ | prints the first 10 lines from stdin or one named file |
| `wc` | 01 | ✅ | prints default line, word, and byte counts for stdin or one or more files |
| `tee` | 01 | ✅ | copies stdin to stdout and to one or more files; supports simple `-a` append mode |
| `rev` | 01 | ✅ | reverses each input line using a documented 4096-byte line buffer limit |
| `basename` | 01 | ✅ | strips directory prefixes and trailing slashes from one pathname operand |

Difficulty and topic metadata are tracked in `docs/command_index.tsv`; per-command teaching contracts are tracked in `docs/commands.md`. Source files stay flat under `src/` so commands remain easy to find by name.

## Requirements

- Linux on x86_64
- `make`
- `nasm`
- `ld` from GNU binutils or a compatible linker
- POSIX-ish shell for tests

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
```

## Project philosophy

- Prefer raw syscalls when they teach the mechanism.
- Prefer plain procedural assembly over macro frameworks.
- Keep each tool readable as a standalone lesson.
- Document missing behavior honestly.
- Add compatibility gradually after the educational core is clear.

See `docs/style_guide.md`, `docs/linux_syscall_abi.md`, `docs/roadmap.md`, `docs/command_index.tsv`, and `docs/commands.md` for more details.
