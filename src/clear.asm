; clear.asm - teaching implementation of the standard `clear` utility.
;
; Behavior implemented:
;   - Write the common ANSI/VT100 clear-screen sequence to stdout.
;   - The sequence moves the cursor to the home position and clears the screen.
;
; Unsupported behavior:
;   - Terminal database lookup, TERM-specific sequences, --help, --version, and
;     operand parsing are not implemented.
;
; Syscalls used:
;   - write(2) for stdout.
;   - exit(2) for the process status.
;
; Error handling:
;   - A failed or short write exits with status 1. Unsupported extra arguments
;     are intentionally ignored for this first tiny terminal-control lesson.
;
; Exit behavior:
;   - Exits 0 after writing the full escape sequence; exits 1 on write failure.
;
; Compatibility notes:
;   - Real `clear` implementations usually consult terminfo. This version uses
;     the widely recognized ESC [ H, ESC [ 2 J sequence directly so the bytes are
;     visible in the assembly source.

bits 64
default rel

global _start

section .rodata
clear_sequence: db 27, "[H", 27, "[2J"
clear_sequence_len: equ $ - clear_sequence

section .text
_start:
    mov rax, 1                  ; write(2)
    mov rdi, 1                  ; stdout.
    lea rsi, [clear_sequence]
    mov rdx, clear_sequence_len
    syscall

    cmp rax, clear_sequence_len
    jne .exit_failure

    mov rax, 60                 ; exit(2)
    xor rdi, rdi                ; status 0.
    syscall

.exit_failure:
    mov rax, 60                 ; exit(2)
    mov rdi, 1                  ; status 1.
    syscall
