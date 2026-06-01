; basename.asm - teaching implementation of a small `basename` utility.
;
; Behavior implemented:
;   - Accept exactly one pathname operand.
;   - Remove trailing slash bytes, then print the text after the final slash.
;   - If the operand is made only of slashes, print one slash.
;
; Behavior missing:
;   - Suffix removal, `-a`, `-s`, `-z`, `--help`, and `--version` are not
;     implemented.
;
; Syscalls used:
;   - write(2), exit(2)
;
; Teaching focus:
;   - Path handling as byte-string scanning: first find the end, trim trailing
;     separators, then scan backward for the directory separator.

bits 64
default rel

global _start

%define SYS_WRITE 1
%define SYS_EXIT  60

section .rodata
missing_msg:    db "basename: missing operand", 10, 0
unexpected_msg: db "basename: unexpected extra operand: ", 0
newline:        db 10
slash:          db "/"

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 2
    jb .missing_operand
    ja .extra_operand

    mov rdi, [r13 + 8]      ; rdi = the one pathname operand.
    call print_basename
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
    mov rsi, [r13 + 16]     ; argv[2] is the first extra operand.
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

; print_basename
;   Input:  rdi = NUL-terminated pathname string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rbx, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: basename can be understood as three small scans over bytes rather
;            than as a filesystem operation.
print_basename:
    mov r8, rdi             ; r8 = start of the original pathname.
    xor ebx, ebx            ; rbx = string length in bytes.

.find_end:
    ; Loop invariant: bytes before r8+rbx are non-NUL pathname bytes.
    cmp byte [r8 + rbx], 0
    je .have_length
    inc rbx
    jmp .find_end

.have_length:
    test rbx, rbx
    jz .write_empty_line    ; basename "" prints just a newline in this subset.

    mov r10, rbx            ; r10 = one-past-the-end after trimming slashes.

.trim_trailing_slashes:
    ; Keep one slash when the whole operand is slashes, so "/" and "///" both
    ; produce the conventional root basename "/".
    cmp r10, 1
    jbe .after_trim
    cmp byte [r8 + r10 - 1], '/'
    jne .after_trim
    dec r10
    jmp .trim_trailing_slashes

.after_trim:
    cmp r10, 1
    jne .find_last_slash
    cmp byte [r8], '/'
    je .write_root_slash

.find_last_slash:
    ; Loop purpose: walk left from the trimmed end until a slash is found.
    ; Invariant: bytes after r8+r9 and before r8+r10 are part of the basename.
    mov r9, r10
.search_backward:
    test r9, r9
    jz .whole_string_is_name
    dec r9
    cmp byte [r8 + r9], '/'
    jne .search_backward

    lea rsi, [r8 + r9 + 1]  ; basename starts after the final slash.
    mov rdx, r10
    sub rdx, r9
    dec rdx                 ; length excludes the slash itself.
    jmp .write_name_and_newline

.whole_string_is_name:
    mov rsi, r8
    mov rdx, r10
    jmp .write_name_and_newline

.write_root_slash:
    lea rsi, [slash]
    mov rdx, 1
    jmp .write_name_and_newline

.write_empty_line:
    xor edx, edx
    lea rsi, [newline]      ; zero-length first write; newline follows below.

.write_name_and_newline:
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
;   Teaches: write(2) needs explicit byte counts, so strings are measured first.
write_c_string_fd:
    mov r9, rsi             ; r9 = start of string while rdx counts bytes.
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
;   Teaches: a partial write advances the pointer and reduces the remaining
;            count until every requested byte has been accepted.
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
