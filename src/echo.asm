; echo.asm - teaching implementation of the standard `echo` utility.
;
; Behavior implemented:
;   - Print operands separated by one space.
;   - Print a trailing newline by default.
;   - Support a single leading `-n` option to suppress the trailing newline.
;
; Behavior missing:
;   - Escape interpretation such as `-e`, `-E`, `\n`, and `\t` is not implemented.
;   - Repeated or combined `-n` forms such as `-nn` are not implemented.
;   - `--help` and `--version` are not implemented.
;
; Syscalls used:
;   - write(2) for stdout and stderr
;   - exit(2)
;
; Error handling:
;   - Unsupported leading options produce a clear stderr message and exit 1.
;   - Write failures exit 1 without a full errno-to-string table.
;
; Compatibility notes:
;   - Common `echo` implementations differ on option and escape behavior. This
;     version implements only the recognizable simple form and documents the
;     missing pieces instead of guessing.

bits 64
default rel

global _start

section .rodata
space:              db " "
newline:            db 10
unsupported_prefix: db "echo: unsupported option: ", 0
supported_msg:      db "echo: this teaching version currently supports: -n", 10, 0

section .text
_start:
    mov r12, [rsp]          ; argc, including argv[0].
    lea r13, [rsp + 8]      ; pointer to argv array on the initial stack.
    mov r14, 1              ; argv index of the next word to process.
    mov r15, 1              ; print_newline flag: 1 = yes, 0 = no.

    cmp r12, 1
    je .maybe_print_newline ; no operands: echo only prints a newline.

    mov rsi, [r13 + 8]      ; argv[1], if present, may be the supported -n option.
    call is_dash_n
    test rax, rax
    jz .check_unsupported_option

    mov r15, 0              ; -n suppresses the final newline.
    mov r14, 2              ; first printable operand is after -n.
    jmp .print_operands

.check_unsupported_option:
    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jz .print_operands

    ; This teaching version chooses explicit failure for unsupported leading
    ; options so users do not mistake incomplete behavior for compatibility.
    mov rsi, unsupported_prefix
    call write_c_string_stderr
    test rax, rax
    jnz .exit_failure

    mov rsi, [r13 + 8]
    call write_c_string_stderr
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, supported_msg
    call write_c_string_stderr
    test rax, rax
    jnz .exit_failure
    jmp .exit_failure

.print_operands:
    cmp r14, r12
    jae .maybe_print_newline

.print_loop:
    mov rsi, [r13 + r14*8]
    call write_c_string_stdout
    test rax, rax
    jnz .exit_failure

    inc r14
    cmp r14, r12
    jae .maybe_print_newline

    lea rsi, [space]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure
    jmp .print_loop

.maybe_print_newline:
    cmp r15, 0
    je .exit_success

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

.exit_success:
    mov rax, 60             ; syscall number: exit(2).
    xor rdi, rdi            ; arg1 status = 0 (success).
    syscall                 ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60             ; syscall number: exit(2).
    mov rdi, 1              ; arg1 status = 1 (failure).
    syscall                 ; process terminates; no return to user code.

; is_dash_n
;   Input:  rsi = pointer to a NUL-terminated string.
;   Output: rax = 1 if the string is exactly "-n", otherwise 0.
is_dash_n:
    cmp byte [rsi], '-'
    jne .no
    cmp byte [rsi + 1], 'n'
    jne .no
    cmp byte [rsi + 2], 0
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; starts_with_dash
;   Input:  rsi = pointer to a NUL-terminated string.
;   Output: rax = 1 if the first byte is '-', otherwise 0.
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

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = file descriptor, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, rbx, rcx, r11.
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

; write_buffer_fd
;   Input:  rdi = file descriptor, rsi = buffer pointer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rcx, r11.
write_buffer_fd:
    mov rax, 1              ; syscall number: write(2).
    ; arg1 rdi = file descriptor; arg2 rsi = bytes; arg3 rdx = byte count.
    syscall                 ; returns bytes written or a negative errno.
    cmp rax, rdx            ; short writes are failure in this teaching pass.
    jne .write_failed
    xor rax, rax
    ret

.write_failed:
    mov rax, 1
    ret
