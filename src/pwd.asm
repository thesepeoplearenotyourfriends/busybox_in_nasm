; pwd.asm - teaching implementation of the standard `pwd` utility.
;
; Behavior implemented:
;   - With no operands, print the current working directory followed by a newline.
;
; Unsupported behavior:
;   - Logical-vs-physical options such as -L and -P are not implemented.
;   - --help and --version are not implemented.
;   - Extra operands are rejected instead of being ignored.
;   - getcwd errors are not translated through a full errno-to-string table yet.
;
; Syscalls used:
;   - getcwd(2) to ask the kernel for the current working directory.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Error handling:
;   - Unsupported options and unexpected operands print clear stderr messages
;     and exit with status 1.
;   - getcwd or write failures exit with status 1 after a short diagnostic.
;
; Exit behavior:
;   - Exits 0 after printing the working directory and newline; exits 1 for
;     unsupported input or syscall/write failure.
;
; Compatibility notes:
;   - This version intentionally teaches the raw getcwd(2) syscall. It therefore
;     reports the kernel's physical current directory, not a shell-maintained
;     logical $PWD value with symlinks preserved.

bits 64
default rel

global _start

section .rodata
newline:                db 10
unsupported_prefix:     db "pwd: unsupported option: ", 0
unsupported_suffix:     db "pwd: this teaching version currently supports no options", 10, 0
operand_prefix:         db "pwd: unexpected operand: ", 0
operand_suffix:         db "pwd: this teaching version currently takes no operands", 10, 0
getcwd_failed_message:  db "pwd: getcwd failed (path may be too long or unavailable)", 10, 0

section .bss
; Linux PATH_MAX is commonly 4096 bytes. The getcwd(2) syscall reports ERANGE
; if this buffer is too small; a later lesson can demonstrate dynamic growth.
cwd_buffer: resb 4096

section .text
_start:
    mov r12, [rsp]          ; argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 points at the argv pointer array.

    cmp r12, 1
    je .print_working_directory

    ; pwd does not need operands for the first teaching version. If the first
    ; extra word starts with '-', call it an unsupported option; otherwise call
    ; it an unexpected operand. Both paths explain the supported subset.
    mov rsi, [r13 + 8]      ; argv[1].
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.print_working_directory:
    mov rax, 79             ; syscall number: getcwd(2).
    lea rdi, [cwd_buffer]   ; arg1 buf = destination for kernel's C string.
    mov rsi, 4096           ; arg2 size = bytes available in cwd_buffer.
    syscall                 ; returns a byte count or a negative errno.
    test rax, rax           ; Linux returns a negative errno value on failure.
    js .getcwd_failed

    ; On success, the raw Linux getcwd(2) syscall writes a NUL-terminated
    ; string into the buffer and returns a non-negative byte count. Scan the
    ; buffer manually to get the visible string length for write(2).
    lea rsi, [cwd_buffer]
    call write_c_string_stdout
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure
    jmp .exit_success

.unsupported_option:
    mov rsi, unsupported_prefix
    call write_c_string_stderr
    test rax, rax
    jnz .exit_failure

    mov rsi, [r13 + 8]
    call write_c_string_stderr
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, unsupported_suffix
    call write_c_string_stderr
    jmp .exit_failure

.unexpected_operand:
    mov rsi, operand_prefix
    call write_c_string_stderr
    test rax, rax
    jnz .exit_failure

    mov rsi, [r13 + 8]
    call write_c_string_stderr
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, operand_suffix
    call write_c_string_stderr
    jmp .exit_failure

.getcwd_failed:
    mov rsi, getcwd_failed_message
    call write_c_string_stderr
    jmp .exit_failure

.exit_success:
    mov rax, 60             ; syscall number: exit(2).
    xor rdi, rdi            ; arg1 status = 0 (success).
    syscall                 ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60             ; syscall number: exit(2).
    mov rdi, 1              ; arg1 status = 1 (failure).
    syscall                 ; process terminates; no return to user code.

; starts_with_dash
;   Input:  rsi = pointer to a NUL-terminated string.
;   Output: rax = 1 if the first byte is '-', otherwise 0.
starts_with_dash:
    cmp byte [rsi], '-'
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

write_c_string_stdout:
    mov rdi, 1              ; stdout.
    jmp write_c_string_fd

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = file descriptor, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, rbx, rcx, r11.
write_c_string_fd:
    mov rbx, rsi            ; keep the string start while scanning length.
    xor rdx, rdx            ; byte count for write(2).

.count_loop:
    cmp byte [rbx + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop

.known_length:
    call write_buffer_fd
    ret

; write_buffer_fd
;   Input:  rdi = file descriptor, rsi = buffer pointer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rcx, r11.
;
; For this small first pass, a short write is treated as failure. A later stream
; utility such as cat or tee can teach retry loops for partial writes.
write_buffer_fd:
    mov rax, 1              ; syscall number: write(2).
    ; arg1 rdi = file descriptor; arg2 rsi = bytes; arg3 rdx = byte count.
    syscall                 ; returns bytes written or a negative errno.
    cmp rax, rdx            ; short writes are failure in this teaching pass.
    jne .write_failed
    xor rax, rax
    ret

.write_failed:
    mov rax, 1
    ret
