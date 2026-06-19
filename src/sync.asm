; sync.asm - teaching implementation of a tiny `sync` utility.
;
; Behavior implemented:
;   - Accept no operands.
;   - Ask the kernel to schedule writeback of dirty filesystem data.
;
; Behavior missing:
;   - File operands, `-d`, `-f`, `--help`, and `--version` are not implemented.
;
; Syscalls used:
;   - sync(2), write(2), exit(2)
;
; Teaching focus:
;   - Some commands are thin names for one syscall, but still need honest argv
;     checking and clear diagnostics around the supported subset.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_SYNC  162
%define SYS_EXIT  60

section .rodata
unexpected_msg: db "sync: unexpected operand: ", 0
newline:        db 10

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 1
    ja .unexpected_operand

    mov rax, SYS_SYNC       ; syscall number: sync(2).
    ; sync(2) has no argument registers; it asks for global filesystem writeback.
    syscall                 ; Linux sync(2) returns after scheduling writeback.

    mov rax, SYS_EXIT       ; syscall number: exit(2).
    xor edi, edi            ; arg1 status = 0.
    syscall                 ; process terminates; no return to user code.

.unexpected_operand:
    mov rsi, unexpected_msg
    call write_c_string_stderr
    mov rsi, [r13 + 8]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all

    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov edi, 1              ; arg1 status = 1.
    syscall                 ; process terminates; no return to user code.

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, r9, r10, rcx, r11.
;   Teaches: syscall interfaces use counted buffers rather than C strings.
write_c_string_fd:
    mov r9, rsi             ; r9 = string byte being measured.
    xor edx, edx            ; rdx = measured byte length.
.count_loop:
    ; Loop invariant: bytes before r9+rdx are non-NUL string bytes.
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
;   Teaches: even diagnostics should use the same partial-write pattern.
write_all:
    mov r9, rsi             ; r9 = next byte to write.
    mov r10, rdx            ; r10 = bytes still unwritten.
.write_loop:
    ; Loop invariant: earlier writes completed, and r10 counts only remaining bytes.
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
