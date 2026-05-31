; env.asm - teaching implementation of a tiny `env` utility subset.
;
; Behavior implemented:
;   - With no operands, print the current process environment, one NAME=VALUE
;     entry per line, in the order supplied by Linux at process startup.
;
; Unsupported behavior:
;   - Option parsing, environment modification, clearing the environment, and
;     command execution under a modified environment are not implemented yet.
;   - Operands are rejected instead of being interpreted as NAME=VALUE pairs or
;     a command to execute.
;
; Syscalls used:
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Error handling:
;   - Unsupported options or operands print a short diagnostic and exit 1.
;   - Write failures exit 1 without decoding errno values.
;
; Exit behavior:
;   - Exits 0 after successfully writing every environment entry; exits 1 for
;     unsupported input or write failure.
;
; Compatibility notes:
;   - Real BusyBox and GNU env are also environment editors and command
;     launchers. This first version intentionally teaches only how envp appears
;     on the initial process stack.

bits 64
default rel

global _start

section .rodata
newline: db 10
unsupported_prefix: db "env: unsupported option: ", 0
unsupported_suffix: db "env: this teaching version supports only no-operand environment printing", 10, 0
operand_prefix: db "env: unexpected operand: ", 0
operand_suffix: db "env: NAME=VALUE editing and command execution are not implemented yet", 10, 0

section .text
_start:
    mov r12, [rsp]          ; argc, including argv[0].
    lea r13, [rsp + 8]      ; argv pointer array from the initial stack.

    cmp r12, 1
    jne .reject_first_extra

    ; envp starts after argc argv pointers and the NULL pointer that terminates
    ; argv: &argv[argc + 1].
    lea r14, [r13 + r12*8 + 8]

.print_environment_loop:
    mov rsi, [r14]
    test rsi, rsi
    jz .exit_success

    call write_c_string_stdout
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    add r14, 8
    jmp .print_environment_loop

.reject_first_extra:
    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.unsupported_option:
    mov r15, [r13 + 8]
    mov rsi, unsupported_prefix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, r15
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, unsupported_suffix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.unexpected_operand:
    mov r15, [r13 + 8]
    mov rsi, operand_prefix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, r15
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, operand_suffix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.exit_success:
    mov rax, 60             ; exit(2)
    xor rdi, rdi            ; status 0.
    syscall

.exit_failure:
    mov rax, 60             ; exit(2)
    mov rdi, 1              ; status 1.
    syscall

starts_with_dash:
    cmp byte [rsi], '-'
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

write_c_string_stdout:
    mov rdi, 1              ; stdout.
    jmp write_c_string_fd

write_c_string_fd:
    mov rbx, rsi
    xor rdx, rdx
.count_loop:
    cmp byte [rbx + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop
.known_length:
    call write_buffer_fd
    ret

write_buffer_fd:
    mov rax, 1              ; write(2)
    syscall
    cmp rax, rdx
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
