; dirname.asm - teaching implementation of a small `dirname` utility.
;
; Behavior implemented:
;   - Accept exactly one pathname operand.
;   - Remove trailing slash bytes, then print the directory portion.
;   - Print "." when the operand has no directory portion.
;
; Behavior missing:
;   - Options such as `-z`, `--help`, and `--version` are not implemented.
;
; Syscalls used:
;   - write(2), exit(2)
;
; Teaching focus:
;   - `dirname` is byte-string processing, not a filesystem lookup.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_EXIT  60

section .rodata
missing_msg:    db "dirname: missing operand", 10, 0
unexpected_msg: db "dirname: unexpected extra operand: ", 0
newline:        db 10
dot:            db "."
slash:          db "/"

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 2
    jb .missing_operand
    ja .extra_operand

    mov rdi, [r13 + 8]      ; rdi = the one pathname operand.
    call print_dirname
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

.exit_success:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    xor edi, edi            ; arg1 status = 0.
    syscall                 ; process terminates; no return to user code.

.exit_failure:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov edi, 1              ; arg1 status = 1.
    syscall                 ; process terminates; no return to user code.

; print_dirname
;   Input:  rdi = NUL-terminated pathname string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: path utilities often normalize only the text they were handed;
;            they do not need to ask the kernel whether a path exists.
print_dirname:
    mov r8, rdi             ; r8 = start of the pathname.
    xor r9d, r9d            ; r9 = pathname length in bytes.

.find_end:
    ; Loop invariant: bytes before r8+r9 are non-NUL pathname bytes.
    cmp byte [r8 + r9], 0
    je .have_length
    inc r9
    jmp .find_end

.have_length:
    test r9, r9
    jz .write_dot           ; dirname "" is "." in this teaching subset.

    mov r10, r9             ; r10 = one-past-end after trimming trailing '/'.
.trim_operand_slashes:
    ; Leave one slash for all-slash operands so "///" still means root.
    cmp r10, 1
    jbe .after_operand_trim
    cmp byte [r8 + r10 - 1], '/'
    jne .after_operand_trim
    dec r10
    jmp .trim_operand_slashes

.after_operand_trim:
    cmp r10, 1
    jne .find_separator
    cmp byte [r8], '/'
    je .write_root

.find_separator:
    ; Loop purpose: find the slash that separates directory from basename.
    ; Invariant: bytes after r10 are not part of the directory answer.
    test r10, r10
    jz .write_dot
    dec r10
    cmp byte [r8 + r10], '/'
    jne .find_separator

    ; r10 is the separator before the basename.  Now trim duplicate slashes
    ; before it, but keep one leading slash for absolute paths.
.trim_dir_slashes:
    cmp r10, 1
    jbe .after_dir_trim
    cmp byte [r8 + r10 - 1], '/'
    jne .after_dir_trim
    dec r10
    jmp .trim_dir_slashes

.after_dir_trim:
    test r10, r10
    jz .write_root
    mov rsi, r8
    mov rdx, r10
    jmp .write_answer

.write_dot:
    lea rsi, [dot]
    mov rdx, 1
    jmp .write_answer

.write_root:
    lea rsi, [slash]
    mov rdx, 1

.write_answer:
    mov rdi, 1              ; stdout.
    call write_all
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
