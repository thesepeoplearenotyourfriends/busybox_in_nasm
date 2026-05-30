# Roadmap

This project grows by adding familiar Linux utilities in order of educational complexity. BusyBox is useful as a source list for command names, but implementation here should remain original and teaching-focused.

## First pass

- `true`: process exit with status 0.
- `false`: process exit with status 1.
- `yes`: repeated writes to stdout, simple argv handling, broken-pipe behavior.
- `echo`: argv scanning, spaces between operands, optional newline suppression with `-n`.

## Near-term utilities

- `cat`: open/read/write loop, stdin handling, file errors.
- `pwd`: current-working-directory syscall behavior and buffer sizing.
- `basename`: string scanning and path edge cases.
- `dirname`: related path scanning with different edge cases.
- `wc`: file input plus counters for bytes, lines, and words.
- `head`: line counting and early termination.

## Documentation to add as utilities grow

- process startup stack layout
- argc / argv / envp in more detail
- file descriptors and standard streams
- stdout vs stderr conventions
- exit codes
- errno and human-readable errors
- NASM syntax notes
- common string routines in assembly
- comparisons between raw syscalls and libc wrappers

## Compatibility policy

Implement the recognizable core behavior first. Document missing options clearly and fail loudly for unsupported options when silent behavior would be confusing.

Avoid starting with complex tools such as `grep`, `find`, `tar`, `sed`, `awk`, `sh`, or `vi`. Those commands are valuable later, but they hide too many concepts at once for the beginning of the project.
