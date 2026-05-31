# BusyBox-inspired NASM utilities

This repository is an educational collection of familiar Linux command-line utilities written in NASM-compatible x86_64 assembly.

The project uses BusyBox as a practical roadmap for recognizable command names, but it is **not** a BusyBox clone and does not copy BusyBox implementation code. Each utility is built as its own standalone binary so the assembly stays readable and each program can teach one low-level idea at a time.

## Goals

The first utilities are intentionally small. They demonstrate:

- process entry at `_start` without a C runtime
- Linux x86_64 system calls
- process exit status
- simple file descriptor I/O with `write(2)`
- reading `argc` and `argv` from the initial stack
- straightforward string scanning in assembly
- fixed table output and terminal escape sequences
- simple kernel information queries with `uname(2)`, `getcwd(2)`, and `ioctl(2)`
- environment pointer (`envp`) traversal from the initial stack
- simple account-name lookup by scanning `/etc/passwd`
- unsigned decimal parsing and `nanosleep(2)` timespec setup
- simple shell-based regression tests

Educational clarity is more important than cleverness, size, or speed.

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
| `whoami` | 00 | ✅ | prints the effective user name by scanning `/etc/passwd` for `geteuid(2)` |
| `tty` | 00 | ✅ | checks stdin with `ioctl(TCGETS)` and prints its terminal path; supports silent `-s` |
| `ttysize` | 00 | ✅ | prints terminal rows and columns from `ioctl(TIOCGWINSZ)` on stdin |

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
build/whoami
build/tty
build/ttysize
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
./build/whoami
./build/tty
./build/tty -s
./build/ttysize
```

## Project philosophy

- Prefer raw syscalls when they teach the mechanism.
- Prefer plain procedural assembly over macro frameworks.
- Keep each tool readable as a standalone lesson.
- Document missing behavior honestly.
- Add compatibility gradually after the educational core is clear.

See `docs/style_guide.md`, `docs/linux_syscall_abi.md`, `docs/roadmap.md`, `docs/command_index.tsv`, and `docs/commands.md` for more details.
