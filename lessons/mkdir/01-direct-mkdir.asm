; mkdir.asm - teaching implementation of a small `mkdir` utility.
;
; Behavior implemented:
;   - Accept one or more directory operands.
;   - Create each directory with mode 0777, letting the process umask remove
;     permission bits in the usual Unix way.
;
; Behavior missing:
;   - Options such as `-p`, `-m`, `--help`, and `--version` are not implemented.
;
; Syscalls used:
;   - mkdir(2), write(2), exit(2)
;
; Teaching focus:
;   - Directory creation is a single kernel request; the mode argument is still
;     subject to the caller's umask, just like in C library implementations.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_EXIT  60
%define SYS_MKDIR 83

%define MODE_777 511

section .rodata
missing_msg: db "mkdir: missing operand", 10, 0
fail_msg:    db "mkdir: cannot create directory ", 0
newline:     db 10

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.
    mov r14, 1              ; r14 = argv index of the next directory operand.
    xor r15d, r15d          ; r15 = accumulated process status.

    cmp r12, 2
    jb .missing_operand

.process_operands:
    ; Loop purpose: try every requested directory in argv order.
    ; Invariant: r15 is 1 if any previous mkdir(2) call failed.
    cmp r14, r12
    jae .exit_with_status

    mov rax, SYS_MKDIR      ; syscall number: mkdir(2).
    ; arg1 rdi = pathname; arg2 rsi = requested mode before umask filtering.
    mov rdi, [r13 + r14*8]
    mov rsi, MODE_777
    syscall                 ; returns 0 on success or negative errno.
    test rax, rax
    jns .next_operand

    mov r15, 1
    mov rsi, fail_msg
    call write_c_string_stderr
    mov rsi, [r13 + r14*8]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all

.next_operand:
    inc r14
    jmp .process_operands

.missing_operand:
    mov rsi, missing_msg
    call write_c_string_stderr
    mov r15, 1

.exit_with_status:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov rdi, r15            ; arg1 status = accumulated success/failure.
    syscall                 ; process terminates; no return to user code.

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, r9, r10, rcx, r11.
;   Teaches: raw write(2) uses byte counts, so C strings must be measured.
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
;   Teaches: a partial write advances the pointer and retries remaining bytes.
write_all:
    mov r9, rsi             ; r9 = next byte to write.
    mov r10, rdx            ; r10 = bytes still unwritten.
.write_loop:
    ; Loop invariant: r9 points at the next unwritten byte, and r10 counts
    ; exactly how many bytes remain after earlier successful writes.
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
