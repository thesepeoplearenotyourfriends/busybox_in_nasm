; seq.asm - teaching implementation of a tiny `seq` utility.
;
; Behavior implemented:
;   - `seq LAST` prints 1 through LAST.
;   - `seq FIRST LAST` prints FIRST through LAST.
;   - `seq FIRST INCREMENT LAST` prints an increasing unsigned sequence.
;
; Behavior missing:
;   - Negative numbers, floating point, custom separators, equal-width output,
;     format strings, options, and overflow diagnostics are not implemented.
;
; Syscalls used:
;   - write(2), exit(2)
;
; Teaching focus:
;   - Parse decimal text by multiplying by ten, then format numbers from right
;     to left because the least-significant digit is produced first.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_EXIT  60

section .rodata
usage_msg:   db "seq: expected 1, 2, or 3 unsigned decimal operands", 10, 0
invalid_msg: db "seq: invalid unsigned decimal operand: ", 0
zero_msg:    db "seq: increment must be greater than zero", 10, 0
newline:     db 10

section .bss
number_buffer: resb 32

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 2
    jb .usage
    cmp r12, 4
    ja .usage

    cmp r12, 2
    je .one_operand
    cmp r12, 3
    je .two_operands

.three_operands:
    mov rdi, [r13 + 8]
    call parse_u64
    jc .invalid_first
    mov r14, rax            ; r14 = current sequence value.

    mov rdi, [r13 + 16]
    call parse_u64
    jc .invalid_second
    test rax, rax
    jz .zero_increment
    mov r15, rax            ; r15 = positive increment.

    mov rdi, [r13 + 24]
    call parse_u64
    jc .invalid_third
    mov rbx, rax            ; rbx = last value to print.
    jmp .print_sequence

.one_operand:
    mov r14, 1              ; default FIRST = 1.
    mov r15, 1              ; default INCREMENT = 1.
    mov rdi, [r13 + 8]
    call parse_u64
    jc .invalid_first
    mov rbx, rax
    jmp .print_sequence

.two_operands:
    mov r15, 1              ; default INCREMENT = 1.
    mov rdi, [r13 + 8]
    call parse_u64
    jc .invalid_first
    mov r14, rax
    mov rdi, [r13 + 16]
    call parse_u64
    jc .invalid_second
    mov rbx, rax

.print_sequence:
    ; Loop purpose: print current, then advance by increment while current is
    ; not beyond LAST.  Invariant: r14 is the next candidate value.
    cmp r14, rbx
    ja .exit_success
    mov rdi, r14
    call write_u64_line
    test rax, rax
    jnz .exit_failure
    add r14, r15
    jc .exit_success        ; unsigned wrap would make the sequence misleading.
    jmp .print_sequence

.usage:
    mov rsi, usage_msg
    call write_c_string_stderr
    jmp .exit_failure
.invalid_first:
    mov rsi, [r13 + 8]
    jmp .invalid_operand
.invalid_second:
    mov rsi, [r13 + 16]
    jmp .invalid_operand
.invalid_third:
    mov rsi, [r13 + 24]
.invalid_operand:
    push rsi
    mov rsi, invalid_msg
    call write_c_string_stderr
    pop rsi
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    jmp .exit_failure
.zero_increment:
    mov rsi, zero_msg
    call write_c_string_stderr
    jmp .exit_failure

.exit_success:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    xor edi, edi            ; arg1 status = 0.
    syscall                 ; process terminates; no return to user code.
.exit_failure:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov edi, 1              ; arg1 status = 1.
    syscall                 ; process terminates; no return to user code.

; parse_u64
;   Input:  rdi = NUL-terminated decimal string.
;   Output: rax = parsed value and CF clear on success; CF set on failure.
;   Clobbers: rax, rdx, r8, rcx.
;   Teaches: decimal parsing is repeated `value = value * 10 + digit`.
parse_u64:
    xor eax, eax            ; rax = accumulated value.
    xor r8d, r8d            ; r8 = number of digits consumed.
.parse_loop:
    movzx edx, byte [rdi]
    test dl, dl
    jz .end
    cmp dl, '0'
    jb .failure
    cmp dl, '9'
    ja .failure
    sub dl, '0'
    imul rax, rax, 10       ; multiply by base 10 before adding next digit.
    movzx edx, dl
    add rax, rdx
    inc r8
    inc rdi
    jmp .parse_loop
.end:
    test r8, r8
    jz .failure
    clc
    ret
.failure:
    stc
    ret

; write_u64_line
;   Input:  rdi = unsigned integer to print.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: division by 10 reveals digits right-to-left, so the buffer is
;            filled backward and then written from the first digit forward.
write_u64_line:
    lea r8, [number_buffer + 31]
    mov byte [r8], 10
    mov rax, rdi
    mov r10, 10
.convert_loop:
    xor edx, edx            ; div uses RDX:RAX, so clear high half first.
    div r10                 ; quotient -> rax, remainder digit -> rdx.
    add dl, '0'
    dec r8
    mov [r8], dl
    test rax, rax
    jnz .convert_loop

    mov rsi, r8
    lea rdx, [number_buffer + 32]
    sub rdx, r8
    mov rdi, 1              ; stdout.
    call write_all
    ret

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, r9, r10, rcx, r11.
;   Teaches: raw write(2) uses byte counts, so C strings must be measured.
write_c_string_fd:
    mov r9, rsi
    xor edx, edx
.count_loop:
    cmp byte [r9 + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop
.known_length:
    call write_all
    ret

; write_all
;   Input:  rdi = output fd, rsi = buffer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rsi, rdx, r9, r10, rcx, r11.
;   Teaches: a partial write advances the pointer and retries remaining bytes.
write_all:
    mov r9, rsi             ; r9 = next byte to write.
    mov r10, rdx            ; r10 = bytes still unwritten.
.write_loop:
    test r10, r10
    jz .success
    mov rax, SYS_WRITE      ; syscall number: write(2).
    ; arg1 rdi = output fd; arg2 rsi = next byte; arg3 rdx = remaining count.
    mov rsi, r9
    mov rdx, r10
    syscall                 ; returns bytes written or negative errno.
    test rax, rax
    jle .failure
    add r9, rax
    sub r10, rax
    jmp .write_loop
.success:
    xor eax, eax
    ret
.failure:
    mov eax, 1
    ret
