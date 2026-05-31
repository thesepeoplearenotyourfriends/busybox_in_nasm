; usleep.asm - teaching implementation of a tiny `usleep` utility subset.
;
; Behavior implemented:
;   - Sleep for a single unsigned decimal number of microseconds.
;   - `0` is accepted and returns immediately after the nanosleep(2) syscall.
;
; Unsupported behavior:
;   - Options, multiple operands, suffixes, fractional values, and
;     signal-aware restart loops are not implemented.
;   - Extremely large values are not checked for integer overflow while parsing.
;
; Syscalls used:
;   - nanosleep(2) with a seconds/nanoseconds timespec derived from the
;     requested microseconds.
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
;   - BusyBox usleep is intentionally simple too. This version uses nanosleep so
;     the conversion from microseconds to a Linux timespec is visible.

bits 64
default rel

global _start

section .rodata
newline: db 10
missing_message: db "usleep: missing operand", 10, "usleep: this teaching version expects one decimal microseconds operand", 10, 0
extra_prefix: db "usleep: unexpected operand: ", 0
extra_suffix: db "usleep: this teaching version expects exactly one operand", 10, 0
invalid_prefix: db "usleep: invalid microseconds: ", 0
invalid_suffix: db "usleep: expected unsigned decimal microseconds", 10, 0
unsupported_prefix: db "usleep: unsupported option: ", 0
unsupported_suffix: db "usleep: this teaching version supports no options", 10, 0
nanosleep_failed_message: db "usleep: nanosleep failed", 10, 0

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

    xor rdx, rdx
    mov rbx, 1000000
    div rbx                 ; unsigned divide: rax = seconds, rdx = leftover us.
    mov [request_timespec], rax
    imul rdx, rdx, 1000     ; convert leftover microseconds to nanoseconds.
    mov [request_timespec + 8], rdx

    mov rax, 35             ; syscall number: nanosleep(2).
    lea rdi, [request_timespec] ; arg1 req = requested sleep duration.
    lea rsi, [remaining_timespec] ; arg2 rem = where interrupted time would go.
    syscall                 ; returns 0 on full sleep or a negative errno.
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
    mov rax, 60             ; syscall number: exit(2).
    xor rdi, rdi            ; arg1 status = 0 (success).
    syscall                 ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60             ; syscall number: exit(2).
    mov rdi, 1              ; arg1 status = 1 (failure).
    syscall                 ; process terminates; no return to user code.

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
    imul rax, rax, 10      ; decimal parse: shift old digits one base-10 place.
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
