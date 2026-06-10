; realpath.asm - teaching implementation of a small `realpath` utility.
;
; Behavior implemented:
;   - Accept exactly one existing pathname operand.
;   - Print the kernel-resolved absolute path followed by a newline.
;
; Behavior missing:
;   - Multiple operands, missing-path modes, relative output modes, options such
;     as `-e`, `-m`, `--relative-to`, `--help`, and `--version` are not
;     implemented.
;
; Syscalls used:
;   - open(2), readlink(2), close(2), write(2), exit(2)
;
; Teaching focus:
;   - Opening a path lets the kernel perform normal pathname resolution.  The
;     `/proc/self/fd/N` symlink then exposes the absolute name of that open file.

bits 64
default rel

global _start

%define SYS_WRITE    1
%define SYS_OPEN     2
%define SYS_CLOSE    3
%define SYS_EXIT     60
%define SYS_READLINK 89

%define O_PATH 2097152
%define O_CLOEXEC 524288
%define PATH_CAP 4096

section .rodata
missing_msg:    db "realpath: missing operand", 10, 0
unexpected_msg: db "realpath: unexpected extra operand: ", 0
fail_msg:       db "realpath: cannot resolve ", 0
proc_prefix:    db "/proc/self/fd/"
proc_prefix_len equ $ - proc_prefix
newline:        db 10

section .bss
proc_path:  resb 64
result_buf: resb PATH_CAP

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 2
    jb .missing_operand
    ja .extra_operand

    mov rax, SYS_OPEN       ; syscall number: open(2).
    ; arg1 rdi = pathname to resolve; arg2 rsi = O_PATH|O_CLOEXEC;
    ; arg3 rdx is unused because O_CREAT is not set.  O_PATH asks for a
    ; reference to the path itself without opening it for data reads.
    mov rdi, [r13 + 8]
    mov rsi, O_PATH | O_CLOEXEC
    xor edx, edx
    syscall                 ; returns fd or negative errno.
    test rax, rax
    js .resolve_failed
    mov r14, rax            ; r14 = fd kept open while procfs names it.

    mov rdi, r14
    call build_proc_fd_path

    mov rax, SYS_READLINK   ; syscall number: readlink(2).
    ; arg1 rdi = /proc/self/fd/N; arg2 rsi = path buffer; arg3 rdx = capacity.
    lea rdi, [proc_path]
    lea rsi, [result_buf]
    mov rdx, PATH_CAP
    syscall                 ; returns resolved path length or negative errno.
    mov r15, rax            ; r15 = result length, preserved across close.

    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = fd returned by open(2).
    mov rdi, r14
    syscall                 ; best effort close; resolution result is primary.

    test r15, r15
    js .resolve_failed
    cmp r15, PATH_CAP       ; A full buffer may mean the procfs target truncated.
    jae .resolve_failed

    mov rdi, 1              ; stdout.
    lea rsi, [result_buf]
    mov rdx, r15
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

.resolve_failed:
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

; build_proc_fd_path
;   Input:  rdi = non-negative file descriptor.
;   Output: proc_path contains a NUL-terminated string like /proc/self/fd/3.
;   Clobbers: rax, rbx, rcx, rdx, r8, r9.
;   Teaches: decimal formatting is easiest to compute right-to-left because
;            division reveals the least-significant digit first.
build_proc_fd_path:
    lea r8, [proc_path]     ; r8 = destination cursor.
    lea r9, [proc_prefix]   ; r9 = source cursor for constant prefix.
    mov rcx, proc_prefix_len
.copy_prefix:
    ; Loop invariant: bytes before r8 have been copied from the prefix.
    test rcx, rcx
    jz .format_fd
    mov al, [r9]
    mov [r8], al
    inc r8
    inc r9
    dec rcx
    jmp .copy_prefix

.format_fd:
    mov rax, rdi            ; rax = fd value being divided into digits.
    lea r9, [proc_path + 63]
    mov byte [r9], 0        ; reserve final NUL terminator.
    mov rbx, 10             ; rbx = decimal base for div.
.digit_loop:
    ; Loop invariant: bytes after r9 are the already-formatted suffix digits.
    xor edx, edx            ; div uses RDX:RAX, so clear the high half first.
    div rbx                 ; quotient -> rax, remainder 0..9 -> rdx.
    dec r9
    add dl, '0'
    mov [r9], dl
    test rax, rax
    jnz .digit_loop
.copy_digits:
    ; Loop invariant: r9 points to the next formatted digit to copy after prefix.
    mov al, [r9]
    mov [r8], al
    inc r8
    inc r9
    test al, al
    jnz .copy_digits
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
