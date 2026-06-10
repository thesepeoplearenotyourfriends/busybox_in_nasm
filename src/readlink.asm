; readlink.asm - teaching implementation of a small `readlink` utility.
;
; Behavior implemented:
;   - Accept exactly one pathname operand.
;   - Print the link target followed by a newline.
;
; Behavior missing:
;   - Options such as `-f`, `-n`, `--canonicalize`, `--help`, and
;     `--version` are not implemented.
;
; Syscalls used:
;   - readlink(2), write(2), exit(2)
;
; Teaching focus:
;   - readlink(2) copies raw bytes and does not append a NUL terminator, so
;     the returned byte count is the only length to print.

bits 64
default rel

global _start

%define SYS_WRITE    1
%define SYS_EXIT     60
%define SYS_READLINK 89

%define TARGET_CAP 4096

section .rodata
missing_msg:    db "readlink: missing operand", 10, 0
unexpected_msg: db "readlink: unexpected extra operand: ", 0
fail_msg:       db "readlink: cannot read link ", 0
newline:        db 10

section .bss
target_buf: resb TARGET_CAP

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 2
    jb .missing_operand
    ja .extra_operand

    mov rax, SYS_READLINK   ; syscall number: readlink(2).
    ; arg1 rdi = symlink pathname; arg2 rsi = destination buffer;
    ; arg3 rdx = destination capacity.  The kernel returns the byte count.
    mov rdi, [r13 + 8]
    lea rsi, [target_buf]
    mov rdx, TARGET_CAP
    syscall                 ; returns target length or negative errno.
    test rax, rax
    js .readlink_failed
    cmp rax, TARGET_CAP     ; Full buffer may mean the target was truncated.
    jae .readlink_failed

    mov rdi, 1              ; stdout.
    lea rsi, [target_buf]
    mov rdx, rax
    call write_all
    test rax, rax
    jnz .exit_failure
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_all
    test rax, rax
    jnz .exit_failure
    jmp .exit_success

.missing_operand:
    mov rsi, missing_msg
    call write_c_string_stderr
    jmp .exit_failure

.extra_operand:
    mov rsi, unexpected_msg
    call write_c_string_stderr
    mov rsi, [r13 + 16]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    jmp .exit_failure

.readlink_failed:
    mov rsi, fail_msg
    call write_c_string_stderr
    mov rsi, [r13 + 8]
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
