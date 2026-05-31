; false.asm - teaching implementation of the standard `false` utility.
;
; Behavior implemented:
;   - Ignore all command-line arguments.
;   - Exit unsuccessfully with status code 1.
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
;   - BusyBox and GNU `false` both fail even when extra operands are given.
;     This version follows that recognizable core behavior.

bits 64
default rel

global _start

section .text
_start:
    mov rax, 60     ; syscall number: exit(2) on Linux x86_64.
    mov rdi, 1      ; arg1 status = 1, so shells see failure.
    syscall         ; process terminates; no return to user code.
