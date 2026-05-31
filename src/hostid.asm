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
    mov r12, [rsp]              ; r12 = argc, kept while validating operands.
    lea r13, [rsp + 8]          ; r13 = argv pointer array on the initial stack.

    cmp r12, 1
    je .print_host_identifier

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.print_host_identifier:
    ; uname(buf) fills a Linux utsname structure. The nodename field is the
    ; kernel hostname, stored as a fixed-size NUL-terminated byte string.
    mov rax, 63                 ; syscall number: uname(2).
    lea rdi, [utsname_buffer]   ; arg1 buf = output structure.
    syscall                     ; returns 0 or a negative errno.
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
    mov rax, 60                 ; syscall number: exit(2).
    xor rdi, rdi                ; arg1 status = 0 (success).
    syscall                     ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60                 ; syscall number: exit(2).
    mov rdi, 1                  ; arg1 status = 1 (failure).
    syscall                     ; process terminates; no return to user code.

; hash_c_string_fnv1a_32
;   Input:  rsi = zero-terminated byte string.
;   Output: eax = 32-bit FNV-1a hash.
;   Clobbers: edx, rsi.
;   Teaches: byte-at-a-time hashing without libc. FNV-1a starts with a fixed
;            offset basis; each byte is mixed by XOR, then multiplied by a
;            fixed prime. Keeping the result in eax naturally keeps 32 bits.
hash_c_string_fnv1a_32:
    mov eax, FNV_OFFSET_BASIS   ; eax = running 32-bit hash value.

    ; Loop invariant: bytes before rsi have already been folded into eax; rsi
    ; points at the next hostname byte or the terminating NUL.
.hash_loop:
    movzx edx, byte [rsi]
    test dl, dl
    jz .done
    xor eax, edx                ; FNV-1a mixes the next byte before multiplying.
    imul eax, eax, FNV_PRIME    ; low 32 bits are kept, matching FNV-1a overflow.
    inc rsi
    jmp .hash_loop
.done:
    ret

; write_rax_as_8_hex_digits
;   Input:  eax = value to print.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: r8, rcx, rdx, rsi, rdi, r11.
;   Teaches: fixed-width hexadecimal formatting with masking and shifts.
write_rax_as_8_hex_digits:
    ; The low hex digit is easiest to get first (value & 0x0f), but the final
    ; text must show the high digit first. Fill an 8-byte buffer right-to-left.
    lea r8, [hex_buffer + 8]     ; r8 = one byte past the output buffer.
    mov ecx, 8                  ; rcx = exactly eight nibbles for a 32-bit value.

    ; Loop invariant: hex digits to the right of r8 are final; eax still holds
    ; the unformatted higher nibbles. `loop` decrements rcx before testing it.
.hex_loop:
    mov edx, eax
    and edx, 0x0f               ; isolate the low 4-bit nibble.
    mov dl, [hex_digits + rdx]  ; use the nibble as an index into the digit table.
    dec r8
    mov [r8], dl
    shr eax, 4                  ; move the next nibble down into the low position.
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

; write_c_string_fd
;   Input:  rdi = fd, rsi = NUL-terminated string.
;   Output: rax = 0 on full write, 1 on failure or short write.
;   Clobbers: rax, rbx, rdx, rcx, r11.
;   Teaches: converting a C string into the pointer+length pair write(2) needs.
write_c_string_fd:
    mov rbx, rsi                ; rbx = stable string start while rdx counts.
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
;   Input:  rdi = fd, rsi = buffer pointer, rdx = byte count.
;   Output: rax = 0 on full write, 1 on failure or short write.
;   Clobbers: rax, rcx, r11.
;   Teaches: raw write(2) setup for stdout/stderr messages.
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
