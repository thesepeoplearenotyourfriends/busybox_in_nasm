; ttysize.asm - teaching implementation of a tiny `ttysize` utility subset.
;
; Behavior implemented:
;   - With no operands, ask the kernel for stdin's terminal window size.
;   - Print rows, a space, columns, and a newline.
;
; Unsupported behavior:
;   - Options and operands are not implemented.
;   - Pixel dimensions from struct winsize are intentionally ignored.
;
; Syscalls used:
;   - ioctl(2) with TIOCGWINSZ to read struct winsize for stdin.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Compatibility notes:
;   - This command needs a real terminal on stdin. In a pipe or redirected test
;     run, ioctl(2) fails and the program exits with status 1.

bits 64
default rel

global _start

%define TIOCGWINSZ 0x5413

section .rodata
newline: db 10
space: db ' '
unsupported_prefix: db "ttysize: unsupported option: ", 0
unsupported_suffix: db "ttysize: this teaching version supports no options", 10, 0
operand_prefix: db "ttysize: unexpected operand: ", 0
operand_suffix: db "ttysize: this teaching version takes no operands", 10, 0
ioctl_failed_message: db "ttysize: ioctl TIOCGWINSZ failed", 10, 0

section .bss
; struct winsize is four unsigned shorts: rows, columns, x pixels, y pixels.
winsize_buffer: resw 4
number_buffer: resb 20

section .text
_start:
    mov r12, [rsp]              ; argc.
    lea r13, [rsp + 8]          ; argv pointer array.

    cmp r12, 1
    je .read_window_size

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.read_window_size:
    mov rax, 16                 ; syscall number: ioctl(2).
    mov rdi, 0                  ; arg1 fd = 0 (stdin terminal being queried).
    mov rsi, TIOCGWINSZ         ; arg2 request = read terminal window size.
    lea rdx, [winsize_buffer]   ; arg3 pointer = kernel writes struct winsize.
    syscall                     ; returns 0 or a negative errno.
    test rax, rax
    js .ioctl_failed

    movzx rax, word [winsize_buffer]      ; ws_row.
    call write_unsigned_decimal_stdout
    test rax, rax
    jnz .exit_failure

    lea rsi, [space]
    mov rdx, 1
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    movzx rax, word [winsize_buffer + 2]  ; ws_col.
    call write_unsigned_decimal_stdout
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    jmp .exit_success

.unsupported_option:
    mov r15, [r13 + 8]
    mov rsi, unsupported_prefix
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure
    mov rsi, r15
    mov rdi, 2
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure
    mov rsi, unsupported_suffix
    mov rdi, 2
    call write_c_string_fd
    jmp .exit_failure

.unexpected_operand:
    mov r15, [r13 + 8]
    mov rsi, operand_prefix
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure
    mov rsi, r15
    mov rdi, 2
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure
    mov rsi, operand_suffix
    mov rdi, 2
    call write_c_string_fd
    jmp .exit_failure

.ioctl_failed:
    mov rsi, ioctl_failed_message
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.exit_success:
    mov rax, 60                 ; syscall number: exit(2).
    xor rdi, rdi                ; arg1 status = 0 (success).
    syscall                     ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60                 ; syscall number: exit(2).
    mov rdi, 1                  ; arg1 status = 1 (failure).
    syscall                     ; process terminates; no return to user code.

starts_with_dash:
    cmp byte [rsi], '-'
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; write_unsigned_decimal_stdout
;   Input:  rax = unsigned integer to print.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rbx, rcx, rdx, rsi, rdi, r8, r9, r10, r11.
write_unsigned_decimal_stdout:
    lea r8, [number_buffer + 20] ; fill digits backward from the end.
    xor r9, r9                  ; digit count.
    mov r10, 10

    test rax, rax
    jnz .divide_loop
    dec r8
    mov byte [r8], '0'
    mov r9, 1
    jmp .write_number

.divide_loop:
    xor rdx, rdx
    div r10                     ; unsigned divide rdx:rax by 10; remainder is digit.
    add dl, '0'
    dec r8
    mov [r8], dl
    inc r9
    test rax, rax
    jnz .divide_loop

.write_number:
    mov rsi, r8
    mov rdx, r9
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    ret

write_c_string_fd:
    mov rbx, rsi
    xor rdx, rdx
.count_loop:
    cmp byte [rbx + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop
.known_length:
    call write_buffer_fd
    ret

write_buffer_fd:
    mov rax, 1                  ; syscall number: write(2).
    ; arg1 rdi = file descriptor; arg2 rsi = bytes; arg3 rdx = byte count.
    syscall                     ; returns bytes written or a negative errno.
    cmp rax, rdx                ; short writes are failure in this teaching pass.
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
