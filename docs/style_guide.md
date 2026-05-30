# Style guide

This project is a teaching project first. The assembly should be easy to read, easy to modify, and honest about what it does not implement yet.

## Source shape

Each utility should be a standalone NASM file under `src/` with this rough structure:

```asm
_start:
    ; read argc / argv if needed
    ; parse options if supported
    ; perform command behavior
    ; handle errors or broken pipes as appropriate
    ; exit with the documented status
```

Avoid building a shared runtime too early. A little repetition is useful while the project is still demonstrating the basic mechanics.

## Comments

Comments are part of the deliverable. Every utility should have a header that explains:

- what the command does
- which subset of behavior is implemented
- which common behavior is missing
- which Linux syscalls it uses
- how errors are handled
- expected exit status values
- compatibility notes compared to BusyBox or GNU tools

Instruction comments should explain the Linux or assembly concept, not restate the mnemonic.

Prefer this:

```asm
mov rax, 1      ; write(2) syscall number on Linux x86_64
mov rdi, 1      ; file descriptor 1 is stdout
```

Avoid this:

```asm
mov rax, 1      ; move 1 into rax
```

## Assembly style

- Use NASM-compatible syntax.
- Use `_start` as the entry point for raw-syscall examples.
- Prefer labels and loops that reveal intent.
- Prefer obvious register usage over clever register tricks.
- Avoid macro DSLs and opaque include files in beginner utilities.
- Keep advanced size-coding or performance tricks out of the main implementation.

## Error handling

Utilities should print human-readable errors to stderr when practical. Early tools may document limitations instead of implementing a reusable errno table immediately.

Unsupported options should fail clearly. For example, a teaching `echo` can say that `--help` is unsupported rather than pretending to be fully compatible.

## Compatibility

The familiar command name is the user's mental index, so the recognizable core behavior should match normal Linux expectations. Full GNU or BusyBox compatibility can be added over time.

When behavior is intentionally incomplete, document that limitation in the file header and in project docs where appropriate.
