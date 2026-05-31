; hostid.asm - teaching implementation of a small `hostid` utility subset.
;
; First-pass semantics:
;   - With no operands, ask the kernel for the current utsname data.
;   - Hash the `nodename` field with 32-bit FNV-1a.
;   - Print that 32-bit value as eight lowercase hexadecimal digits.
;
; Why this policy:
;   - Real hostid implementations are policy-heavy: libc may read /etc/hostid,
;     derive a value from network addresses, or use other system configuration.
;   - This project does not use libc yet, so this version chooses a small,
;     reproducible rule that can be explained directly from the assembly.
;
; Unsupported behavior:
;   - Options and operands are rejected.
;   - libc gethostid(3), /etc/hostid, DNS, and network-interface address lookup
;     are not implemented.
;
; Compatibility notes:
;   - This is an honest teaching identifier for the current hostname, not a
;     promise to match GNU coreutils, BusyBox, or libc hostid output.

bits 64
default rel

global _start

%define UTS_FIELD_SIZE 65
%define UTS_NODENAME_OFFSET UTS_FIELD_SIZE
%define FNV_OFFSET_BASIS 2166136261
%define FNV_PRIME 16777619

section .rodata
newline: db 10
hex_digits: db "0123456789abcdef"
unsupported_prefix: db "hostid: unsupported option: ", 0
unsupported_suffix: db "hostid: this teaching version supports no options", 10, 0
operand_prefix: db "hostid: unexpected operand: ", 0
operand_suffix: db "hostid: this teaching version takes no operands", 10, 0
uname_failed_message: db "hostid: uname failed", 10, 0

section .bss
utsname_buffer: resb UTS_FIELD_SIZE * 6
hex_buffer: resb 8

section .text
_start:
    mov r12, [rsp]              ; argc.
    lea r13, [rsp + 8]          ; argv pointer array.

    cmp r12, 1
    je .print_host_identifier

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.print_host_identifier:
    mov rax, 63                 ; uname(2)
    lea rdi, [utsname_buffer]
    syscall
    test rax, rax
    js .uname_failed

    lea rsi, [utsname_buffer + UTS_NODENAME_OFFSET]
    call hash_c_string_fnv1a_32
    call write_rax_as_8_hex_digits
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
    mov rdi, 2
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure
    mov rsi, unsupported_suffix
    mov rdi, 2
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
    mov rdi, 2
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure
    mov rsi, operand_suffix
    mov rdi, 2
    call write_c_string_fd
    jmp .exit_failure

.uname_failed:
    mov rsi, uname_failed_message
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.exit_success:
    mov rax, 60                 ; exit(2)
    xor rdi, rdi
    syscall

.exit_failure:
    mov rax, 60                 ; exit(2)
    mov rdi, 1
    syscall

; hash_c_string_fnv1a_32
;   Input:  rsi = zero-terminated byte string.
;   Output: eax = 32-bit FNV-1a hash.
;   Notes:  Each loop step is: hash = (hash xor byte) * FNV_PRIME.
hash_c_string_fnv1a_32:
    mov eax, FNV_OFFSET_BASIS
.hash_loop:
    movzx edx, byte [rsi]
    test dl, dl
    jz .done
    xor eax, edx
    imul eax, eax, FNV_PRIME
    inc rsi
    jmp .hash_loop
.done:
    ret

; write_rax_as_8_hex_digits
;   Input:  eax = value to print.
;   Output: rax = 0 on success, 1 on write failure.
write_rax_as_8_hex_digits:
    lea r8, [hex_buffer + 8]     ; fill digits from right to left.
    mov ecx, 8
.hex_loop:
    mov edx, eax
    and edx, 0x0f
    mov dl, [hex_digits + rdx]
    dec r8
    mov [r8], dl
    shr eax, 4
    loop .hex_loop

    lea rsi, [hex_buffer]
    mov rdx, 8
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
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
    mov rax, 1                  ; write(2)
    syscall
    cmp rax, rdx
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
