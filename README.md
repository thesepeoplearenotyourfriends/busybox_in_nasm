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
- simple shell-based regression tests

Educational clarity is more important than cleverness, size, or speed.

## Current utilities

| Utility | Level | Status | Notes |
| --- | ---: | --- | --- |
| `true` | 00 | implemented | exits with status 0 |
| `false` | 00 | implemented | exits with status 1 |
| `echo` | 00 | implemented | supports plain operands and `-n`; unsupported option handling is intentionally explicit |
| `yes` | 00 | implemented | writes `y` repeatedly, or the provided operands joined by spaces |

Difficulty and topic metadata are tracked in `docs/applet_index.tsv`; per-command teaching contracts are tracked in `docs/applets.md`. Source files stay flat under `src/` so commands remain easy to find by name.

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
build/yes
build/echo
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
```

## Project philosophy

- Prefer raw syscalls when they teach the mechanism.
- Prefer plain procedural assembly over macro frameworks.
- Keep each tool readable as a standalone lesson.
- Document missing behavior honestly.
- Add compatibility gradually after the educational core is clear.

See `docs/style_guide.md`, `docs/linux_syscall_abi.md`, `docs/roadmap.md`, `docs/applet_index.tsv`, and `docs/applets.md` for more details.
