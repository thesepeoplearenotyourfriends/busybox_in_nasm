; head.asm - teaching implementation of a small `head` utility.
;
; Behavior implemented:
;   - With no operands, print the first 10 lines from stdin.
;   - With one file operand, print the first 10 lines from that file.
;
; Behavior missing:
;   - Options such as `-n`, byte counts, quiet/verbose headers, and multiple-file
;     headers are not implemented in this first pass.
;   - Diagnostics are short and do not decode errno values.
;
; Syscalls used:
;   - open(2), read(2), write(2), close(2), exit(2)
;
; Teaching focus:
;   - Reusing the cat-style buffer loop while adding a simple line counter that
;     stops after the newline ending the tenth line.

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
%define DEFAULT_LINES 10

section .rodata
open_prefix:        db "head: cannot open ", 0
unexpected_prefix:  db "head: unexpected operand: ", 0
unsupported_prefix: db "head: unsupported option: ", 0
read_msg:           db "head: read failed", 10, 0
write_msg:          db "head: write failed", 10, 0
newline:            db 10

section .bss
buffer: resb BUFFER_SIZE

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.

    cmp r12, 1
    je .use_stdin
    cmp r12, 2
    ja .too_many_operands

    mov rsi, [r13 + 8]      ; rsi = argv[1], the one accepted pathname.
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option

    mov rdi, [r13 + 8]
    call open_read_only
    test rax, rax
    js .open_failed

    mov rbx, rax            ; rbx = opened file descriptor until close(2).
    mov rdi, rbx
    call copy_first_ten_lines
    mov r14, rax            ; r14 = copy status while we close the file.

    mov rdi, rbx
    call close_fd
    jmp .exit_with_r14

.use_stdin:
    xor edi, edi            ; input fd = stdin.
    call copy_first_ten_lines
    mov r14, rax
    jmp .exit_with_r14

.too_many_operands:
    mov rsi, unexpected_prefix
    call write_c_string_stderr
    mov rsi, [r13 + 16]     ; argv[2] is the first operand beyond the subset.
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    mov r14, 1
    jmp .exit_with_r14

.unsupported_option:
    mov rsi, unsupported_prefix
    call write_c_string_stderr
    mov rsi, [r13 + 8]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    mov r14, 1
    jmp .exit_with_r14

.open_failed:
    mov rsi, open_prefix
    call write_c_string_stderr
    mov rsi, [r13 + 8]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    mov r14, 1

.exit_with_r14:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov rdi, r14            ; arg1 status = 0 on success, 1 on failure.
    syscall                 ; process terminates; no return to user code.

; copy_first_ten_lines
;   Input:  rdi = input file descriptor.
;   Output: rax = 0 on success, 1 on read or write failure.
;   Clobbers: rax, rbx, rdi, rsi, rdx, r8, r9, r10, r12, rcx, r11.
;   Teaches: line-oriented tools can still read block-sized chunks; the program
;            scans only the bytes read and writes the useful prefix of a chunk.
copy_first_ten_lines:
    mov r8, rdi             ; r8 = input fd kept across the read loop.
    mov r12, DEFAULT_LINES  ; r12 = number of newline-terminated lines left.

.read_loop:
    ; Loop invariant: every earlier byte that belongs in the first ten lines has
    ; been written.  r12 tells how many more newline bytes may be copied.
    test r12, r12
    jz .done

    mov rax, SYS_READ       ; syscall number: read(2).
    ; arg1 rdi = input fd; arg2 rsi = buffer; arg3 rdx = buffer capacity.
    mov rdi, r8
    lea rsi, [buffer]
    mov rdx, BUFFER_SIZE
    syscall                 ; returns byte count, 0 for EOF, or negative errno.

    test rax, rax
    js .read_failed
    jz .done

    mov r10, rax            ; r10 = bytes read in this chunk.
    xor ebx, ebx            ; rbx = scan index within buffer.

.scan_chunk:
    ; Loop purpose: find how much of this chunk belongs to the first ten lines.
    ; Invariant: bytes before rbx are allowed output bytes.
    cmp rbx, r10
    jae .write_whole_chunk
    cmp byte [buffer + rbx], 10
    jne .next_byte
    dec r12                 ; the newline just seen completes one output line.
    inc rbx                 ; include that newline in the bytes we print.
    test r12, r12
    jz .write_prefix_and_finish
    jmp .scan_chunk
.next_byte:
    inc rbx
    jmp .scan_chunk

.write_whole_chunk:
    lea rsi, [buffer]
    mov rdx, r10
    mov rdi, 1              ; stdout.
    call write_all
    test rax, rax
    jnz .write_failed
    jmp .read_loop

.write_prefix_and_finish:
    lea rsi, [buffer]
    mov rdx, rbx            ; prefix length ending at the tenth newline.
    mov rdi, 1              ; stdout.
    call write_all
    test rax, rax
    jnz .write_failed

.done:
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

; starts_with_dash
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 1 if the first byte is '-', otherwise 0.
;   Clobbers: rax.
;   Teaches: explicit subset diagnostics keep early implementations honest.
starts_with_dash:
    cmp byte [rsi], '-'
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
open_read_only:
    mov rax, SYS_OPEN       ; syscall number: open(2).
    ; arg1 rdi = pathname; arg2 rsi = flags; arg3 rdx = mode (unused here).
    mov rsi, O_RDONLY
    xor edx, edx
    syscall                 ; returns fd or negative errno.
    ret

; close_fd
;   Input:  rdi = file descriptor to close.
;   Output: rax = kernel return value; caller ignores close errors.
;   Clobbers: rax, rcx, r11.
close_fd:
    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = file descriptor.
    syscall                 ; returns 0 or negative errno.
    ret

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, rbx, r9, rcx, r11.
write_c_string_fd:
    mov rbx, rsi            ; rbx = start pointer while rdx counts bytes.
    xor edx, edx
.count_loop:
    cmp byte [rbx + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop
.known_length:
    call write_all
    ret

; write_all
;   Input:  rdi = output fd, rsi = buffer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rsi, rdx, r9, rcx, r11.
;   Teaches: partial writes are handled by retrying with the unwritten suffix.
write_all:
    mov r9, rsi             ; r9 = next byte to write.
.write_loop:
    test rdx, rdx
    jz .success
    mov rax, SYS_WRITE      ; syscall number: write(2).
    ; arg1 rdi = output fd; arg2 rsi = next byte; arg3 rdx = remaining count.
    mov rsi, r9
    syscall                 ; returns bytes written or negative errno.
    test rax, rax
    jle .failure
    add r9, rax             ; skip over the bytes accepted by the kernel.
    sub rdx, rax            ; keep only the unwritten byte count.
    jmp .write_loop
.success:
    xor eax, eax
    ret
.failure:
    mov eax, 1
    ret
