; link.asm - teaching implementation of the POSIX `link` utility.
;
; Behavior implemented:
;   - Accept exactly two operands: FILE LINK_NAME.
;   - Create a hard link named LINK_NAME for FILE with link(2).
;
; Behavior missing:
;   - Options such as `--help` and `--version` are not implemented.
;
; Syscalls used:
;   - link(2), write(2), exit(2)
;
; Teaching focus:
;   - The link(2) syscall adds a new directory entry for an existing inode.
;     It is the small syscall-shaped cousin of the friendlier `ln` command.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_LINK  86
%define SYS_EXIT  60

section .rodata
missing_msg:    db "link: missing operand", 10, 0
unexpected_msg: db "link: unexpected extra operand: ", 0
fail_msg:       db "link: cannot create link ", 0
arrow:          db " -> ", 0
newline:        db 10

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 3
    jb .missing_operand
    ja .extra_operand

    mov rax, SYS_LINK       ; syscall number: link(2).
    ; arg1 rdi = existing file path; arg2 rsi = new hard-link pathname.
    mov rdi, [r13 + 8]
    mov rsi, [r13 + 16]
    syscall                 ; returns 0 on success or negative errno.
    test rax, rax
    jns .exit_success

    mov rsi, fail_msg
    call write_c_string_stderr
    mov rsi, [r13 + 8]
    call write_c_string_stderr
    mov rsi, arrow
    call write_c_string_stderr
    mov rsi, [r13 + 16]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    jmp .exit_failure

.missing_operand:
    mov rsi, missing_msg
    call write_c_string_stderr
    jmp .exit_failure

.extra_operand:
    mov rsi, unexpected_msg
    call write_c_string_stderr
    mov rsi, [r13 + 24]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    jmp .exit_failure

.exit_success:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    xor edi, edi            ; arg1 status = 0.
    syscall                 ; process terminates; no return to user code.

.exit_failure:
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
;   Teaches: syscalls write counted buffers, so strings need measurement first.
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
;   Teaches: partial writes are handled by advancing the pointer and retrying.
write_all:
    mov r9, rsi             ; r9 = next byte to write.
    mov r10, rdx            ; r10 = bytes still unwritten.
.write_loop:
    ; Loop invariant: r9/r10 describe exactly the unwritten suffix.
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
