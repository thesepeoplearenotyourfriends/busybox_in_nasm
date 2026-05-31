; uname.asm - teaching implementation of a small `uname` utility subset.
;
; Behavior implemented:
;   - With no operands, print the kernel name (`sysname`) followed by a newline.
;   - With exactly one `-m` option, print the machine hardware name followed by
;     a newline.
;
; Unsupported behavior:
;   - Other common options such as -a, -n, -r, -s, -v, -o, long options,
;     combined short options, and extra operands are not implemented.
;   - uname errors are not decoded into errno-specific messages.
;
; Syscalls used:
;   - uname(2) to read the kernel utsname structure.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Error handling:
;   - Unsupported options or operands print a short stderr diagnostic and exit
;     with status 1.
;   - uname or write failure exits with status 1 after a short diagnostic when
;     possible.
;
; Exit behavior:
;   - Exits 0 after printing the requested field and newline; exits 1 for
;     unsupported input or syscall/write failure.
;
; Compatibility notes:
;   - Linux x86_64 exposes utsname fields as fixed 65-byte C strings. This file
;     reads only sysname and machine for the first useful teaching subset.

bits 64
default rel

global _start

%define UTS_FIELD_SIZE 65
%define UTS_SYSNAME_OFFSET 0
%define UTS_MACHINE_OFFSET (UTS_FIELD_SIZE * 4)

section .rodata
newline: db 10
unsupported_prefix: db "uname: unsupported option: ", 0
unsupported_suffix: db "uname: this teaching version supports only default output and -m", 10, 0
operand_prefix: db "uname: unexpected operand: ", 0
operand_suffix: db "uname: this teaching version takes no operands except the -m option", 10, 0
uname_failed_message: db "uname: uname failed", 10, 0

section .bss
utsname_buffer: resb UTS_FIELD_SIZE * 6

section .text
_start:
    mov r12, [rsp]              ; argc, including argv[0].
    lea r13, [rsp + 8]          ; argv pointer array.

    cmp r12, 1
    je .select_sysname

    cmp r12, 2
    jne .unexpected_extra

    mov rsi, [r13 + 8]          ; argv[1].
    call is_dash_m
    test rax, rax
    jnz .select_machine

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.select_sysname:
    mov r14, UTS_SYSNAME_OFFSET
    jmp .read_uname

.select_machine:
    mov r14, UTS_MACHINE_OFFSET

.read_uname:
    mov rax, 63                 ; uname(2)
    lea rdi, [utsname_buffer]
    syscall
    test rax, rax
    js .uname_failed

    lea rsi, [utsname_buffer + r14]
    mov rdi, 1                  ; stdout.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    jmp .exit_success

.unexpected_extra:
    mov rsi, [r13 + 16]         ; report argv[2], the first definitely extra word.
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option_from_rsi
    jmp .unexpected_operand_from_rsi

.unsupported_option:
    mov rsi, [r13 + 8]
.unsupported_option_from_rsi:
    mov r15, rsi
    mov rsi, unsupported_prefix
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, r15
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2                  ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, unsupported_suffix
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.unexpected_operand:
    mov rsi, [r13 + 8]
.unexpected_operand_from_rsi:
    mov r15, rsi
    mov rsi, operand_prefix
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, r15
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2                  ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, operand_suffix
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.uname_failed:
    mov rsi, uname_failed_message
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.exit_success:
    mov rax, 60                 ; exit(2)
    xor rdi, rdi                ; status 0.
    syscall

.exit_failure:
    mov rax, 60                 ; exit(2)
    mov rdi, 1                  ; status 1.
    syscall

; is_dash_m
;   Input:  rsi = pointer to a NUL-terminated string.
;   Output: rax = 1 if the string is exactly "-m", otherwise 0.
is_dash_m:
    cmp byte [rsi], '-'
    jne .no
    cmp byte [rsi + 1], 'm'
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
    mov rax, 1                  ; write(2)
    syscall
    cmp rax, rdx
    jne .write_failed
    xor rax, rax
    ret

.write_failed:
    mov rax, 1
    ret
