; true.asm - teaching implementation of the standard `true` utility.
;
; Behavior implemented:
;   - Ignore all command-line arguments.
;   - Exit successfully with status code 0.
;
; Behavior missing:
;   - GNU-style --help and --version are not implemented.
;
; Syscalls used:
;   - exit(2)
;
; Error handling:
;   - There is no operation here that can usefully fail before exit.
;
; Compatibility notes:
;   - BusyBox and GNU `true` both succeed even when extra operands are given.
;     This version follows that recognizable core behavior.

bits 64
default rel

global _start

section .text
_start:
    mov rax, 60     ; syscall number: exit(2) on Linux x86_64.
    xor rdi, rdi    ; arg1 status = 0, so shells see success.
    syscall         ; process terminates; no return to user code.
