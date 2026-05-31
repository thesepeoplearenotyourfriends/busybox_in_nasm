; whoami.asm - teaching implementation of a small `whoami` utility subset.
;
; Behavior implemented:
;   - With no operands, print the user name for the process effective UID.
;   - The name is found by scanning /etc/passwd for a matching numeric UID.
;
; Unsupported behavior:
;   - Options such as --help and --version are not implemented.
;   - NSS modules, LDAP, systemd-homed, and other libc name-service backends are
;     not consulted; this teaching version reads only /etc/passwd.
;
; Syscalls used:
;   - geteuid(2) to find the effective user ID.
;   - open(2), read(2), and close(2) to read /etc/passwd.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Compatibility notes:
;   - Real whoami uses libc account lookup. This version deliberately shows the
;     plain text passwd format and documents the limitation.

bits 64
default rel

global _start

%define PASSWD_BUFFER_SIZE 65536

section .rodata
passwd_path: db "/etc/passwd", 0
newline: db 10
unsupported_prefix: db "whoami: unsupported option: ", 0
unsupported_suffix: db "whoami: this teaching version supports no options", 10, 0
operand_prefix: db "whoami: unexpected operand: ", 0
operand_suffix: db "whoami: this teaching version takes no operands", 10, 0
open_failed_message: db "whoami: could not open /etc/passwd", 10, 0
read_failed_message: db "whoami: could not read /etc/passwd", 10, 0
not_found_message: db "whoami: effective uid was not found in /etc/passwd", 10, 0

section .bss
passwd_buffer: resb PASSWD_BUFFER_SIZE

section .text
_start:
    mov r12, [rsp]              ; argc.
    lea r13, [rsp + 8]          ; argv pointer array.

    cmp r12, 1
    je .lookup_effective_user

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.lookup_effective_user:
    mov rax, 107                ; syscall number: geteuid(2).
    syscall                     ; no arguments; returns the effective UID in rax.
    mov r12, rax                ; r12 = target effective UID for passwd matching.

    mov rax, 2                  ; syscall number: open(2).
    lea rdi, [passwd_path]      ; arg1 pathname = /etc/passwd.
    xor rsi, rsi                ; arg2 flags = O_RDONLY.
    xor rdx, rdx                ; arg3 mode unused without O_CREAT.
    syscall                     ; returns fd or a negative errno.
    test rax, rax
    js .open_failed
    mov r13, rax                ; file descriptor.

    mov rax, 0                  ; syscall number: read(2).
    mov rdi, r13                ; arg1 fd = opened /etc/passwd descriptor.
    lea rsi, [passwd_buffer]    ; arg2 buf = fixed teaching buffer.
    mov rdx, PASSWD_BUFFER_SIZE ; arg3 count = maximum bytes to read.
    syscall                     ; returns bytes read or a negative errno.
    test rax, rax
    js .read_failed
    mov r14, rax                ; bytes read.

    mov rax, 3                  ; syscall number: close(2).
    mov rdi, r13                ; arg1 fd = /etc/passwd descriptor.
    syscall                     ; close failure does not change lookup result.

    lea r15, [passwd_buffer]    ; current scan pointer.
    lea r13, [passwd_buffer + r14] ; one byte past the data read.

.next_line:
    cmp r15, r13
    jae .not_found

    mov r8, r15                 ; username starts at the beginning of the line.

.find_name_colon:
    cmp r15, r13
    jae .not_found
    mov al, [r15]
    cmp al, 10
    je .skip_line_after_newline
    cmp al, ':'
    je .found_name_colon
    inc r15
    jmp .find_name_colon

.found_name_colon:
    mov r9, r15                 ; username ends just before this colon.
    inc r15                     ; move into password field.

.find_password_colon:
    cmp r15, r13
    jae .not_found
    mov al, [r15]
    cmp al, 10
    je .skip_line_after_newline
    cmp al, ':'
    je .parse_uid_field
    inc r15
    jmp .find_password_colon

.parse_uid_field:
    inc r15                     ; first byte of decimal UID field.
    xor r10, r10                ; parsed UID value.
    xor r11, r11                ; digit count.

.uid_digit_loop:
    cmp r15, r13
    jae .not_found
    mov al, [r15]
    cmp al, ':'
    je .uid_field_done
    cmp al, 10
    je .skip_line_after_newline
    cmp al, '0'
    jb .skip_to_next_line
    cmp al, '9'
    ja .skip_to_next_line

    imul r10, r10, 10          ; decimal parse: move previous digits left.
    movzx rax, al
    sub rax, '0'
    add r10, rax
    inc r11
    inc r15
    jmp .uid_digit_loop

.uid_field_done:
    cmp r11, 0                  ; empty UID field is not a match.
    je .skip_to_next_line
    cmp r10, r12
    je .print_username
    jmp .skip_to_next_line

.skip_line_after_newline:
    inc r15
    jmp .next_line

.skip_to_next_line:
    cmp r15, r13
    jae .not_found
    cmp byte [r15], 10
    je .skip_line_after_newline
    inc r15
    jmp .skip_to_next_line

.print_username:
    mov rsi, r8
    mov rdx, r9
    sub rdx, r8                 ; username length.
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

.open_failed:
    mov rsi, open_failed_message
    mov rdi, 2
    call write_c_string_fd
    jmp .exit_failure

.read_failed:
    mov rsi, read_failed_message
    mov rdi, 2
    call write_c_string_fd
    mov rax, 3                  ; syscall number: close(2).
    mov rdi, r13                ; arg1 fd = /etc/passwd descriptor.
    syscall                     ; best-effort cleanup before reporting read failure.
    jmp .exit_failure

.not_found:
    mov rsi, not_found_message
    mov rdi, 2
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
