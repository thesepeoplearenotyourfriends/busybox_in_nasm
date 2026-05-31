; arch.asm - teaching implementation of the standard `arch` utility.
;
; Behavior implemented:
;   - Print the machine hardware name followed by a newline.
;   - The value comes from the same Linux uname(2) field used by `uname -m`.
;
; Unsupported behavior:
;   - --help, --version, and any operands are not implemented or diagnosed yet.
;
; Syscalls used:
;   - uname(2) to read the kernel utsname structure.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Error handling:
;   - uname or write failure exits with status 1 after a short diagnostic when
;     possible. Extra arguments are ignored in this first compatibility subset.
;
; Exit behavior:
;   - Exits 0 after printing the architecture and newline; exits 1 on syscall or
;     write failure.
;
; Compatibility notes:
;   - Linux x86_64 exposes utsname fields as fixed 65-byte C strings. The
;     machine field starts after sysname, nodename, release, and version.

bits 64
default rel

global _start

%define UTS_FIELD_SIZE 65
%define UTS_MACHINE_OFFSET (UTS_FIELD_SIZE * 4)

section .rodata
newline: db 10
uname_failed_message: db "arch: uname failed", 10, 0

section .bss
utsname_buffer: resb UTS_FIELD_SIZE * 6

section .text
_start:
    mov rax, 63                 ; uname(2)
    lea rdi, [utsname_buffer]
    syscall
    test rax, rax
    js .uname_failed

    lea rsi, [utsname_buffer + UTS_MACHINE_OFFSET]
    mov rdi, 1                  ; stdout.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    jmp .exit_success

.uname_failed:
    mov rsi, uname_failed_message
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.exit_success:
    mov rax, 60                 ; exit(2)
    xor rdi, rdi                ; status 0.
    syscall

.exit_failure:
    mov rax, 60                 ; exit(2)
    mov rdi, 1                  ; status 1.
    syscall

; write_c_string_fd
;   Input:  rdi = file descriptor, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, rbx, rcx, r11.
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

; write_buffer_fd
;   Input:  rdi = file descriptor, rsi = buffer pointer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rcx, r11.
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
