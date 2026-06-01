; rev.asm - teaching implementation of the standard `rev` utility.
;
; Behavior implemented:
;   - With no operands, read stdin and reverse each line independently.
;   - With file operands, read each file in argv order and reverse each line.
;   - A single operand `-` means stdin, matching a common filter convention.
;
; Behavior missing:
;   - This first pass is line-buffered with a 4096-byte maximum line length,
;     including the newline if present.  Longer lines fail with a clear message
;     instead of reallocating or streaming a partial reversal.
;   - Unicode grapheme and multibyte character awareness is not implemented;
;     bytes before the newline are reversed.
;   - Options and errno-specific diagnostics are not implemented.
;
; Syscalls used:
;   - open(2), read(2), write(2), close(2), exit(2)
;
; Teaching focus:
;   - Collect one line in a fixed buffer, then walk backward over the line body
;     while preserving the trailing newline.

bits 64
default rel

global _start

%define SYS_READ   0
%define SYS_WRITE  1
%define SYS_OPEN   2
%define SYS_CLOSE  3
%define SYS_EXIT   60

%define O_RDONLY   0
%define BUFFER_SIZE 4096

section .rodata
open_prefix: db "rev: cannot open ", 0
read_msg:    db "rev: read failed", 10, 0
write_msg:   db "rev: write failed", 10, 0
long_msg:    db "rev: line exceeds 4096-byte teaching buffer", 10, 0
newline:     db 10

section .bss
line_buffer: resb BUFFER_SIZE
one_byte:    resb 1

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.
    mov r14, 1              ; r14 = argv index of next input operand.
    xor r15d, r15d          ; r15 = accumulated process status.

    cmp r12, 1
    jne .process_operands

    xor edi, edi            ; input fd = stdin.
    call reverse_fd_lines
    mov r15, rax
    jmp .exit_with_status

.process_operands:
    ; Loop purpose: reverse each input operand in order.  Invariant: r14 is the
    ; next argv index and r15 records whether any earlier operand failed.
    cmp r14, r12
    jae .exit_with_status

    mov rsi, [r13 + r14*8]
    call is_single_dash
    test rax, rax
    jnz .use_stdin

    mov rdi, rsi
    call open_read_only
    test rax, rax
    js .open_failed

    mov rbx, rax            ; rbx = opened file descriptor until close(2).
    mov rdi, rbx
    call reverse_fd_lines
    test rax, rax
    jz .close_success
    mov r15, 1
.close_success:
    mov rdi, rbx
    call close_fd
    jmp .next_operand

.use_stdin:
    xor edi, edi            ; input fd = stdin for a `-` operand.
    call reverse_fd_lines
    test rax, rax
    jz .next_operand
    mov r15, 1
    jmp .next_operand

.open_failed:
    mov r15, 1
    mov rsi, open_prefix
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

.exit_with_status:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov rdi, r15            ; arg1 status = accumulated success/failure.
    syscall                 ; process terminates; no return to user code.

; reverse_fd_lines
;   Input:  rdi = input file descriptor.
;   Output: rax = 0 on success, 1 on read/write/line-length failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: this deliberately simple version keeps one line in memory so the
;            reversal can be shown as a backward scan over a fixed buffer.
reverse_fd_lines:
    mov r8, rdi             ; r8 = input fd for repeated one-byte reads.
    xor r9d, r9d            ; r9 = number of bytes currently in line_buffer.

.read_next_byte:
    ; Loop invariant: line_buffer[0..r9) is the current unfinished line, never
    ; exceeding BUFFER_SIZE bytes.
    mov rax, SYS_READ       ; syscall number: read(2).
    ; arg1 rdi = input fd; arg2 rsi = one-byte buffer; arg3 rdx = 1 byte.
    mov rdi, r8
    lea rsi, [one_byte]
    mov rdx, 1
    syscall                 ; returns 1 byte, 0 for EOF, or negative errno.

    test rax, rax
    js .read_failed
    jz .end_of_file

    cmp r9, BUFFER_SIZE
    jae .line_too_long
    mov al, [one_byte]
    mov [line_buffer + r9], al
    inc r9
    cmp al, 10
    jne .read_next_byte

    call write_reversed_line
    test rax, rax
    jnz .write_failed
    xor r9d, r9d            ; newline completed the buffered line.
    jmp .read_next_byte

.end_of_file:
    test r9, r9
    jz .success
    call write_reversed_line
    test rax, rax
    jnz .write_failed

.success:
    xor eax, eax
    ret

.read_failed:
    mov rsi, read_msg
    call write_c_string_stderr
    mov eax, 1
    ret
.write_failed:
    mov rsi, write_msg
    call write_c_string_stderr
    mov eax, 1
    ret
.line_too_long:
    mov rsi, long_msg
    call write_c_string_stderr
    mov eax, 1
    ret

; write_reversed_line
;   Input:  r9 = buffered line length in bytes; line_buffer holds that line.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rsi, rdx, r10, r11, rcx.
;   Teaches: if a line ends in newline, `rev` reverses bytes before it and then
;            writes the newline last so line boundaries stay line boundaries.
write_reversed_line:
    mov r10, r9             ; r10 = count of bytes to reverse before newline.
    cmp r10, 0
    je .success
    cmp byte [line_buffer + r10 - 1], 10
    jne .reverse_body
    dec r10                 ; keep the newline out of the reversed byte range.

.reverse_body:
    ; Loop invariant: bytes above r10 have already been written in reverse order.
    test r10, r10
    jz .maybe_newline
    dec r10
    lea rsi, [line_buffer + r10]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_all
    test rax, rax
    jnz .failure
    jmp .reverse_body

.maybe_newline:
    cmp byte [line_buffer + r9 - 1], 10
    jne .success
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_all
    ret
.success:
    xor eax, eax
    ret
.failure:
    mov eax, 1
    ret

; is_single_dash
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 1 for exactly "-", otherwise 0.
;   Clobbers: rax.
is_single_dash:
    cmp byte [rsi], '-'
    jne .no
    cmp byte [rsi + 1], 0
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; open_read_only
;   Input:  rdi = pathname pointer.
;   Output: rax = file descriptor on success, negative errno on failure.
;   Clobbers: rax, rsi, rdx, rcx, r11.
;   Teaches: file operands are regular read-only open(2) calls.
open_read_only:
    mov rax, SYS_OPEN       ; syscall number: open(2).
    ; arg1 rdi = pathname; arg2 rsi = flags; arg3 rdx = mode (unused here).
    mov rsi, O_RDONLY
    xor edx, edx
    syscall                 ; returns fd or negative errno.
    ret

; close_fd
;   Input:  rdi = file descriptor to close.
;   Output: rax = kernel return value; this caller ignores close errors.
;   Clobbers: rax, rcx, r11.
;   Teaches: each successfully opened input descriptor is closed after use.
close_fd:
    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = file descriptor.
    syscall                 ; returns 0 or negative errno.
    ret

; write_c_string_stderr
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rdx, rcx, r11.
;   Teaches: stderr is file descriptor 2, not a special library feature.
write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, rcx, r11.
;   Teaches: the kernel write call needs a length, so C strings are scanned.
write_c_string_fd:
    xor edx, edx            ; rdx = string length discovered so far.
.count_loop:
    cmp byte [rsi + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop
.known_length:
    call write_all
    ret

; write_all
;   Input:  rdi = output fd, rsi = buffer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rsi, rdx, rcx, r11.  Preserves r12 and r13 for callers.
;   Teaches: helpers can save registers when callers keep important state there.
write_all:
    push r12
    push r13
    mov r12, rsi            ; r12 = pointer to next byte not yet written.
    mov r13, rdx            ; r13 = bytes still to write.
.write_loop:
    test r13, r13
    jz .success
    mov rax, SYS_WRITE      ; syscall number: write(2).
    ; arg1 rdi = output fd; arg2 rsi = next byte; arg3 rdx = remaining count.
    mov rsi, r12
    mov rdx, r13
    syscall                 ; returns bytes written or negative errno.
    test rax, rax
    jle .failure
    add r12, rax
    sub r13, rax
    jmp .write_loop
.success:
    xor eax, eax
    pop r13
    pop r12
    ret
.failure:
    mov eax, 1
    pop r13
    pop r12
    ret
