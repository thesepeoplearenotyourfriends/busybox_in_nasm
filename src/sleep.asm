; sleep.asm - teaching implementation of a tiny `sleep` utility subset.
;
; Behavior implemented:
;   - Sleep for a single unsigned decimal number of seconds.
;   - `0` is accepted and returns immediately after the nanosleep(2) syscall.
;
; Unsupported behavior:
;   - Fractional values, suffixes such as `m`/`h`/`d`, multiple duration
;     operands, options, and signal-aware restart loops are not implemented.
;   - Extremely large values are not checked for integer overflow while parsing.
;
; Syscalls used:
;   - nanosleep(2) to ask the kernel to suspend the process.
;   - write(2) for stderr diagnostics.
;   - exit(2) for the process status.
;
; Error handling:
;   - Missing, extra, non-decimal, or option-looking operands print a short
;     diagnostic and exit 1.
;   - nanosleep failure exits 1 without decoding errno values.
;
; Exit behavior:
;   - Exits 0 after the requested sleep completes; exits 1 for bad input or a
;     syscall failure.
;
; Compatibility notes:
;   - BusyBox and GNU sleep accept richer duration syntax. This version keeps
;     parsing intentionally small so the timespec and nanosleep syscall are the
;     main lesson.

bits 64
default rel

global _start

section .rodata
newline: db 10
missing_message: db "sleep: missing operand", 10, "sleep: this teaching version expects one decimal seconds operand", 10, 0
extra_prefix: db "sleep: unexpected operand: ", 0
extra_suffix: db "sleep: this teaching version expects exactly one operand", 10, 0
invalid_prefix: db "sleep: invalid seconds: ", 0
invalid_suffix: db "sleep: expected unsigned decimal seconds", 10, 0
unsupported_prefix: db "sleep: unsupported option: ", 0
unsupported_suffix: db "sleep: this teaching version supports no options", 10, 0
nanosleep_failed_message: db "sleep: nanosleep failed", 10, 0

section .bss
request_timespec: resq 2
remaining_timespec: resq 2

section .text
_start:
    mov r12, [rsp]          ; argc, including argv[0].
    lea r13, [rsp + 8]      ; argv pointer array.

    cmp r12, 2
    jb .missing_operand
    ja .unexpected_extra

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option

    mov rsi, [r13 + 8]
    call parse_unsigned_decimal
    test rdx, rdx
    jnz .invalid_operand

    mov [request_timespec], rax
    mov qword [request_timespec + 8], 0

    mov rax, 35             ; nanosleep(2) syscall number on Linux x86_64.
    lea rdi, [request_timespec]
    lea rsi, [remaining_timespec]
    syscall
    test rax, rax
    js .nanosleep_failed
    jmp .exit_success

.missing_operand:
    mov rsi, missing_message
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.unexpected_extra:
    mov r15, [r13 + 16]
    mov rsi, extra_prefix
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
    mov rsi, extra_suffix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    jmp .exit_failure

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

.invalid_operand:
    mov r15, [r13 + 8]
    mov rsi, invalid_prefix
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
    mov rsi, invalid_suffix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.nanosleep_failed:
    mov rsi, nanosleep_failed_message
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

parse_unsigned_decimal:
    xor rax, rax            ; parsed value.
    xor rdx, rdx            ; status: 0 = valid, 1 = invalid.
    cmp byte [rsi], 0
    je .invalid
.parse_loop:
    mov bl, [rsi]
    test bl, bl
    jz .done
    cmp bl, '0'
    jb .invalid
    cmp bl, '9'
    ja .invalid
    imul rax, rax, 10
    sub bl, '0'
    movzx rbx, bl
    add rax, rbx
    inc rsi
    jmp .parse_loop
.invalid:
    mov rdx, 1
.done:
    ret

starts_with_dash:
    cmp byte [rsi], '-'
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

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
