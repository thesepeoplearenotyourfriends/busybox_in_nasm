; hostname.asm - teaching implementation of a small `hostname` utility subset.
;
; Behavior implemented:
;   - With no operands, print the kernel node name followed by a newline.
;   - The value comes from the `nodename` field returned by uname(2).
;
; Unsupported behavior:
;   - Setting the hostname is not implemented.
;   - Options such as -s, -f, --help, and --version are not implemented.
;   - Extra operands are rejected instead of being treated as a new hostname.
;
; Syscalls used:
;   - uname(2) to read the kernel utsname structure.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Compatibility notes:
;   - Linux x86_64 exposes utsname fields as fixed 65-byte C strings. This
;     first version reads only the nodename field.

bits 64
default rel

global _start

%define UTS_FIELD_SIZE 65
%define UTS_NODENAME_OFFSET UTS_FIELD_SIZE

section .rodata
newline: db 10
unsupported_prefix: db "hostname: unsupported option: ", 0
unsupported_suffix: db "hostname: this teaching version only prints the current hostname", 10, 0
operand_prefix: db "hostname: unexpected operand: ", 0
operand_suffix: db "hostname: setting the hostname is not implemented yet", 10, 0
uname_failed_message: db "hostname: uname failed", 10, 0

section .bss
utsname_buffer: resb UTS_FIELD_SIZE * 6

section .text
_start:
    mov r12, [rsp]              ; argc, including argv[0].
    lea r13, [rsp + 8]          ; argv pointer array.

    cmp r12, 1
    je .print_hostname

    mov rsi, [r13 + 8]          ; argv[1].
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.print_hostname:
    mov rax, 63                 ; syscall number: uname(2).
    lea rdi, [utsname_buffer]   ; arg1 buf = output utsname structure.
    syscall                     ; kernel fills the fixed-size utsname fields.
    test rax, rax
    js .uname_failed

    lea rsi, [utsname_buffer + UTS_NODENAME_OFFSET]
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

.unsupported_option:
    mov r15, [r13 + 8]
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
    mov r15, [r13 + 8]
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
    mov rax, 60                 ; syscall number: exit(2).
    xor rdi, rdi                ; arg1 status = 0 (success).
    syscall                     ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60                 ; syscall number: exit(2).
    mov rdi, 1                  ; arg1 status = 1 (failure).
    syscall                     ; process terminates; no return to user code.

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
    mov rax, 1                  ; syscall number: write(2).
    ; arg1 rdi = file descriptor; arg2 rsi = bytes; arg3 rdx = byte count.
    syscall                     ; returns bytes written or a negative errno.
    cmp rax, rdx                ; short writes are failure in this teaching pass.
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
