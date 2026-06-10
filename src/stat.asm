; stat.asm - teaching implementation of a small `stat` utility.
;
; Behavior implemented:
;   - Accept exactly one pathname operand.
;   - Print a compact teaching summary: size, mode, inode, and link count.
;
; Behavior missing:
;   - Options such as `-c`, `-f`, `-L`, `--printf`, `--help`, and `--version`,
;     timestamps, owner/group names, file type names, device numbers, and
;     filesystem statistics are not implemented.
;
; Syscalls used:
;   - stat(2), write(2), exit(2)
;
; Teaching focus:
;   - stat(2) fills a binary structure.  This command reads a few fixed fields
;     from that structure and formats unsigned integers as decimal text.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_STAT  4
%define SYS_EXIT  60

%define STAT_SIZE    144
%define ST_INO_OFF   8
%define ST_NLINK_OFF 16
%define ST_MODE_OFF  24
%define ST_SIZE_OFF  48

section .rodata
missing_msg:    db "stat: missing operand", 10, 0
unexpected_msg: db "stat: unexpected extra operand: ", 0
fail_msg:       db "stat: cannot stat ", 0
size_label:     db "Size: ", 0
mode_label:     db "Mode: ", 0
inode_label:    db "Inode: ", 0
links_label:    db "Links: ", 0
newline:        db 10

section .bss
stat_buf:   resb STAT_SIZE
number_buf: resb 32

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 2
    jb .missing_operand
    ja .extra_operand

    mov rax, SYS_STAT       ; syscall number: stat(2).
    ; arg1 rdi = pathname; arg2 rsi = writable struct stat buffer.
    mov rdi, [r13 + 8]
    lea rsi, [stat_buf]
    syscall                 ; returns 0 on success or negative errno.
    test rax, rax
    js .stat_failed

    mov rsi, size_label
    mov rdi, [stat_buf + ST_SIZE_OFF]
    call print_labeled_u64
    test rax, rax
    jnz .exit_failure

    mov rsi, mode_label
    mov edi, dword [stat_buf + ST_MODE_OFF]
    and rdi, 7777o         ; show permission/special bits, not file type bits.
    call print_labeled_u64
    test rax, rax
    jnz .exit_failure

    mov rsi, inode_label
    mov rdi, [stat_buf + ST_INO_OFF]
    call print_labeled_u64
    test rax, rax
    jnz .exit_failure

    mov rsi, links_label
    mov rdi, [stat_buf + ST_NLINK_OFF]
    call print_labeled_u64
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

.stat_failed:
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

; print_labeled_u64
;   Input:  rsi = NUL-terminated label, rdi = unsigned integer value.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rbx, rcx, rdx, rdi, rsi, r8, r9, r10, r11.
;   Teaches: combine small reusable writers: label, number, then newline.
print_labeled_u64:
    mov r8, rdi             ; r8 = value preserved while label is written.
    mov rdi, 1              ; stdout.
    call write_c_string_fd
    test rax, rax
    jnz .failure
    mov rdi, r8
    call print_u64_stdout
    test rax, rax
    jnz .failure
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_all
    ret
.failure:
    mov eax, 1
    ret

; print_u64_stdout
;   Input:  rdi = unsigned integer value.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rbx, rcx, rdx, rdi, rsi, r9, r10, r11.
;   Teaches: decimal formatting writes digits right-to-left because div gives
;            the least-significant digit as the remainder.
print_u64_stdout:
    lea rsi, [number_buf + 32]
    mov rax, rdi            ; rax = value being divided down to zero.
    mov rbx, 10             ; rbx = decimal base for div.
.convert_loop:
    ; Loop invariant: bytes from rsi to number_buf+31 are formatted digits for
    ; the low-order part already removed from rax.
    xor edx, edx            ; div reads RDX:RAX; clear high half for u64 / 10.
    div rbx                 ; quotient -> rax, remainder 0..9 -> rdx.
    dec rsi
    add dl, '0'
    mov [rsi], dl
    test rax, rax
    jnz .convert_loop

    lea rdx, [number_buf + 32]
    sub rdx, rsi            ; rdx = number of generated digit bytes.
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
