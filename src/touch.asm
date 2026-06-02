; touch.asm - teaching implementation of a small `touch` utility.
;
; Behavior implemented:
;   - Accept one or more file operands.
;   - For an existing file, update access and modification times to "now".
;   - For a missing file, create an empty regular file with mode 0666 masked
;     by the process umask.
;
; Behavior missing:
;   - Options such as `-a`, `-c`, `-d`, `-m`, `-r`, `-t`, `--help`, and
;     `--version` are not implemented.
;
; Syscalls used:
;   - utimensat(2), open(2), close(2), write(2), exit(2)
;
; Teaching focus:
;   - Try the direct timestamp syscall first; if the path is reported
;     missing, create it with open(O_CREAT) as a simple fallback.

bits 64
default rel

global _start

%define SYS_WRITE     1
%define SYS_OPEN      2
%define SYS_CLOSE     3
%define SYS_EXIT      60
%define SYS_UTIMENSAT 280

%define AT_FDCWD -100
%define O_WRONLY 1
%define O_CREAT  64
%define MODE_666 438

section .rodata
missing_msg: db "touch: missing file operand", 10, 0
fail_msg:    db "touch: cannot touch ", 0
newline:     db 10

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.
    mov r14, 1              ; r14 = argv index of next file operand.
    xor r15d, r15d          ; r15 = accumulated process status.

    cmp r12, 2
    jb .missing_operand

.process_operands:
    ; Loop purpose: touch each path in argv order.  Invariant: r15 records
    ; whether any earlier path failed, but later paths are still attempted.
    cmp r14, r12
    jae .exit_with_status
    mov rdi, [r13 + r14*8]
    call touch_one_path
    test rax, rax
    jz .next_operand

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

; touch_one_path
;   Input:  rdi = NUL-terminated pathname.
;   Output: rax = 0 on success, 1 on failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r10, rcx, r11.
;   Teaches: passing NULL times to utimensat asks the kernel to use current
;            time for both atime and mtime; open(O_CREAT) creates missing files.
touch_one_path:
    mov r8, rdi             ; r8 = pathname reused if utimensat fails.

    mov rax, SYS_UTIMENSAT  ; syscall number: utimensat(2).
    ; arg1 rdi = AT_FDCWD; arg2 rsi = path; arg3 rdx = NULL timespec array;
    ; arg4 r10 = flags (0).  NULL times means "set both times to now".
    mov rdi, AT_FDCWD
    mov rsi, r8
    xor edx, edx
    xor r10d, r10d
    syscall                 ; returns 0 on success or negative errno.
    test rax, rax
    jz .success
    cmp rax, -2             ; -ENOENT: path is missing, so creation may help.
    jne .failure

    mov rax, SYS_OPEN       ; syscall number: open(2).
    ; arg1 rdi = path; arg2 rsi = O_WRONLY|O_CREAT; arg3 rdx = file mode 0666.
    mov rdi, r8
    mov rsi, O_WRONLY | O_CREAT
    mov rdx, MODE_666
    syscall                 ; returns new fd or negative errno.
    test rax, rax
    js .failure

    mov rdi, rax            ; rdi = fd returned by open(2), now close it.
    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = file descriptor to close.
    syscall                 ; returns 0 on success or negative errno.
    test rax, rax
    js .failure
.success:
    xor eax, eax
    ret
.failure:
    mov eax, 1
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
