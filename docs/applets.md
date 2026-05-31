# Applet notes

This file records the teaching contract for each implemented applet. The source files stay flat under `src/`; difficulty and topic metadata live in documentation so a command remains easy to find by name.

## Implemented applets

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

## Roadmap direction

Implementation order is tracked in `docs/roadmap.md`.

Do not treat this file as the scheduling source. This file documents applets that exist or have implementation notes. When choosing the next applet batch, consult `docs/roadmap.md` and `docs/applet_index.tsv`.
