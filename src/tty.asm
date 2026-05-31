; tty.asm - teaching implementation of a small `tty` utility subset.
;
; Behavior implemented:
;   - With no operands, print the terminal path connected to stdin.
;   - With `-s`, stay silent and report only the exit status.
;   - If stdin is not a terminal-like /dev path, print `not a tty` and exit 1.
;
; Unsupported behavior:
;   - Long options such as --help and --version are not implemented.
;   - Extra operands are rejected.
;
; Syscalls used:
;   - ioctl(2) with TCGETS to check whether stdin behaves like a terminal.
;   - readlink(2) on /proc/self/fd/0 to inspect stdin's kernel file target.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Compatibility notes:
;   - TCGETS is the kernel request behind a simple terminal check. The procfs
;     readlink step is used only after that check succeeds, so ordinary files
;     such as /dev/null are still rejected.

bits 64
default rel

global _start

%define TCGETS 0x5401

section .rodata
fd0_path: db "/proc/self/fd/0", 0
newline: db 10
not_tty_message: db "not a tty", 10, 0
unsupported_prefix: db "tty: unsupported option: ", 0
unsupported_suffix: db "tty: this teaching version supports only no operands or -s", 10, 0
operand_prefix: db "tty: unexpected operand: ", 0
operand_suffix: db "tty: this teaching version does not take operands", 10, 0

section .bss
link_buffer: resb 4096
; TCGETS writes a termios structure. Reserving 64 bytes is enough for the
; Linux x86_64 layout and keeps this utility independent of C headers.
termios_buffer: resb 64

section .text
_start:
    mov r12, [rsp]              ; argc.
    lea r13, [rsp + 8]          ; argv pointer array.
    xor r14, r14                ; r14 = 1 means silent mode.

    cmp r12, 1
    je .check_stdin

    cmp r12, 2
    jne .reject_extra

    mov rsi, [r13 + 8]
    call is_dash_s
    test rax, rax
    jz .reject_first

    mov r14, 1
    jmp .check_stdin

.reject_extra:
    mov rsi, [r13 + 16]         ; argv[2] is the first definitely extra word.
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option_from_rsi
    jmp .unexpected_operand_from_rsi

.reject_first:
    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option_from_rsi
    jmp .unexpected_operand_from_rsi

.check_stdin:
    mov rax, 16                 ; ioctl(2)
    mov rdi, 0                  ; stdin.
    mov rsi, TCGETS
    lea rdx, [termios_buffer]
    syscall
    test rax, rax
    js .not_a_tty

    mov rax, 89                 ; readlink(2)
    lea rdi, [fd0_path]
    lea rsi, [link_buffer]
    mov rdx, 4095               ; leave room for a newline byte.
    syscall
    test rax, rax
    js .not_a_tty

    mov r15, rax                ; byte count returned by readlink(2).
    call link_target_starts_with_dev
    test rax, rax
    jz .not_a_tty

    test r14, r14
    jnz .exit_success

    lea rsi, [link_buffer]
    mov rdx, r15
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    jmp .exit_success

.not_a_tty:
    test r14, r14
    jnz .exit_failure
    mov rsi, not_tty_message
    mov rdi, 1                  ; GNU tty writes this diagnostic to stdout.
    call write_c_string_fd
    jmp .exit_failure

.unsupported_option_from_rsi:
    mov r15, rsi
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

.unexpected_operand_from_rsi:
    mov r15, rsi
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

.exit_success:
    mov rax, 60                 ; exit(2)
    xor rdi, rdi
    syscall

.exit_failure:
    mov rax, 60                 ; exit(2)
    mov rdi, 1
    syscall

link_target_starts_with_dev:
    cmp r15, 5
    jl .no
    cmp byte [link_buffer], '/'
    jne .no
    cmp byte [link_buffer + 1], 'd'
    jne .no
    cmp byte [link_buffer + 2], 'e'
    jne .no
    cmp byte [link_buffer + 3], 'v'
    jne .no
    cmp byte [link_buffer + 4], '/'
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

is_dash_s:
    cmp byte [rsi], '-'
    jne .no
    cmp byte [rsi + 1], 's'
    jne .no
    cmp byte [rsi + 2], 0
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

starts_with_dash:
    cmp byte [rsi], '-'
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
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
    mov rax, 1                  ; write(2)
    syscall
    cmp rax, rdx
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
