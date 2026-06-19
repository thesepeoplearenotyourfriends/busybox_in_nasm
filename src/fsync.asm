; fsync.asm - teaching implementation of a small `fsync` utility.
;
; Behavior implemented:
;   - Accept exactly one pathname operand.
;   - Open that file read-only and call fsync(2) on its file descriptor.
;
; Behavior missing:
;   - Directory sync policy, multiple operands, `--help`, and `--version` are not
;     implemented in this first pass.
;
; Syscalls used:
;   - open(2), fsync(2), close(2), write(2), exit(2)
;
; Teaching focus:
;   - Pathname-based commands often need a syscall sequence: open a path to get
;     a file descriptor, operate on that descriptor, then close it.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_OPEN  2
%define SYS_CLOSE 3
%define SYS_FSYNC 74
%define SYS_EXIT  60

%define O_RDONLY 0

section .rodata
missing_msg:    db "fsync: missing operand", 10, 0
unexpected_msg: db "fsync: unexpected extra operand: ", 0
open_msg:       db "fsync: cannot open ", 0
fsync_msg:      db "fsync: cannot sync ", 0
newline:        db 10

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 2
    jb .missing_operand
    ja .extra_operand

    mov rdi, [r13 + 8]
    call open_read_only
    test rax, rax
    js .open_failed

    mov rbx, rax            ; rbx = opened file descriptor until close(2).

    mov rax, SYS_FSYNC      ; syscall number: fsync(2).
    ; arg1 rdi = file descriptor whose dirty data and metadata should be flushed.
    mov rdi, rbx
    syscall                 ; returns 0 on success or negative errno.
    mov r14, rax            ; r14 = fsync result while close(2) runs.

    mov rdi, rbx
    call close_fd

    test r14, r14
    js .fsync_failed
    jmp .exit_success

.open_failed:
    mov rsi, open_msg
    call write_c_string_stderr
    mov rsi, [r13 + 8]
    call write_c_string_stderr
    call write_newline_stderr
    jmp .exit_failure

.fsync_failed:
    mov rsi, fsync_msg
    call write_c_string_stderr
    mov rsi, [r13 + 8]
    call write_c_string_stderr
    call write_newline_stderr
    jmp .exit_failure

.missing_operand:
    mov rsi, missing_msg
    call write_c_string_stderr
    jmp .exit_failure

.extra_operand:
    mov rsi, unexpected_msg
    call write_c_string_stderr
    mov rsi, [r13 + 16]
    call write_c_string_stderr
    call write_newline_stderr
    jmp .exit_failure

.exit_success:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    xor edi, edi            ; arg1 status = 0.
    syscall                 ; process terminates; no return to user code.

.exit_failure:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov edi, 1              ; arg1 status = 1.
    syscall                 ; process terminates; no return to user code.

; open_read_only
;   Input:  rdi = pathname pointer.
;   Output: rax = file descriptor on success, negative errno on failure.
;   Clobbers: rax, rsi, rdx, rcx, r11.
;   Teaches: file-descriptor syscalls usually begin by opening a path.
open_read_only:
    mov rax, SYS_OPEN       ; syscall number: open(2).
    ; arg1 rdi = pathname; arg2 rsi = flags; arg3 rdx = mode (unused here).
    mov rsi, O_RDONLY
    xor edx, edx
    syscall                 ; returns fd or negative errno.
    ret

; close_fd
;   Input:  rdi = file descriptor to close.
;   Output: rax = kernel return value; this caller ignores close errors.
;   Clobbers: rax, rcx, r11.
;   Teaches: descriptor lifetimes should be visible even in tiny examples.
close_fd:
    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = file descriptor.
    syscall                 ; returns 0 or negative errno.
    ret

write_newline_stderr:
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    jmp write_all

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, r9, r10, rcx, r11.
;   Teaches: raw write(2) requires a byte count, not a terminator byte.
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
;   Teaches: a reliable writer retries after short successful writes.
write_all:
    mov r9, rsi             ; r9 = next byte to write.
    mov r10, rdx            ; r10 = bytes still unwritten.
.write_loop:
    ; Loop invariant: r9 points at the next unwritten byte, r10 counts the rest.
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
