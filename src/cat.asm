; cat.asm - teaching implementation of the standard `cat` utility.
;
; Behavior implemented:
;   - With no operands, copy stdin to stdout until EOF.
;   - With file operands, copy each file to stdout in argv order.
;   - A single operand `-` means stdin, matching a common cat convention.
;
; Behavior missing:
;   - Numbering, squeezing blank lines, visible-control-character output, and other
;     options are not implemented.
;   - Diagnostics are intentionally short and do not decode errno values yet.
;
; Syscalls used:
;   - open(2), read(2), write(2), close(2), exit(2)
;
; Teaching focus:
;   - A fixed-size buffer, a read loop, a write-all helper for partial writes,
;     and simple multi-file argv traversal.

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
open_prefix: db "cat: cannot open ", 0
read_msg:    db "cat: read failed", 10, 0
write_msg:   db "cat: write failed", 10, 0
newline:     db 10

section .bss
buffer: resb BUFFER_SIZE

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, the number of argv entries.
    lea r13, [rsp + 8]      ; r13 = argv base address on the initial stack.
    mov r14, 1              ; r14 = argv index of the next file operand.
    xor r15d, r15d          ; r15 = process status accumulated across files.

    cmp r12, 1
    jne .copy_named_files

    ; No operands: teach the Unix filter shape by copying fd 0 to fd 1.
    xor edi, edi            ; input fd = stdin.
    call copy_fd_to_stdout
    test rax, rax
    jz .exit_with_status
    mov r15, 1
    jmp .exit_with_status

.copy_named_files:
    ; Loop purpose: visit each pathname operand once, copying successful opens and
    ; remembering if any file failed.  Invariant: r14 is the next argv index and
    ; r15 is 0 only if every earlier file copied successfully.
    cmp r14, r12
    jae .exit_with_status

    mov rsi, [r13 + r14*8]  ; rsi = current argv string.
    call is_single_dash
    test rax, rax
    jnz .copy_stdin_operand

    mov rdi, rsi
    call open_read_only
    test rax, rax
    js .open_failed

    mov rbx, rax            ; rbx = opened file descriptor until close(2).
    mov rdi, rbx
    call copy_fd_to_stdout
    test rax, rax
    jz .close_after_success
    mov r15, 1

.close_after_success:
    mov rdi, rbx
    call close_fd
    inc r14
    jmp .copy_named_files

.copy_stdin_operand:
    xor edi, edi            ; input fd = stdin for the conventional `-` operand.
    call copy_fd_to_stdout
    test rax, rax
    jz .next_operand
    mov r15, 1
.next_operand:
    inc r14
    jmp .copy_named_files

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
    inc r14
    jmp .copy_named_files

.exit_with_status:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov rdi, r15            ; arg1 status = accumulated success/failure.
    syscall                 ; process terminates; no return to user code.

; open_read_only
;   Input:  rdi = pathname pointer.
;   Output: rax = file descriptor on success, negative errno on failure.
;   Clobbers: rax, rsi, rdx, rcx, r11.
;   Teaches: open(2) takes flags and mode even when mode is unused for O_RDONLY.
open_read_only:
    mov rax, SYS_OPEN       ; syscall number: open(2).
    ; arg1 rdi = pathname; arg2 rsi = flags; arg3 rdx = mode (ignored here).
    mov rsi, O_RDONLY
    xor edx, edx
    syscall                 ; returns fd or negative errno.
    ret

; close_fd
;   Input:  rdi = file descriptor to close.
;   Output: rax = kernel return value; this caller ignores close errors.
;   Clobbers: rax, rcx, r11.
;   Teaches: every successful open should have a matching close in simple tools.
close_fd:
    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = file descriptor.
    syscall                 ; returns 0 or negative errno.
    ret

; copy_fd_to_stdout
;   Input:  rdi = input file descriptor.
;   Output: rax = 0 on success, 1 on read or write failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: repeated read(2) calls fill a reusable buffer until EOF.
copy_fd_to_stdout:
    mov r8, rdi             ; r8 = input fd for the whole read loop.

.read_loop:
    ; Loop invariant: bytes from all earlier reads have already been written to
    ; stdout.  The next read either supplies another chunk, reports EOF, or fails.
    mov rax, SYS_READ       ; syscall number: read(2).
    ; arg1 rdi = input fd; arg2 rsi = buffer; arg3 rdx = buffer capacity.
    mov rdi, r8
    lea rsi, [buffer]
    mov rdx, BUFFER_SIZE
    syscall                 ; returns byte count, 0 for EOF, or negative errno.

    test rax, rax
    js .read_failed
    jz .done

    lea rsi, [buffer]
    mov rdx, rax            ; write exactly the bytes read, not the whole buffer.
    mov rdi, 1              ; stdout.
    call write_all
    test rax, rax
    jnz .write_failed
    jmp .read_loop

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

; is_single_dash
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 1 for exactly "-", otherwise 0.
;   Clobbers: rax.
;   Teaches: small option/pathname tests are just byte comparisons.
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

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, rbx, r9, r10, rcx, r11.
;   Teaches: syscalls need byte counts, so C-style strings must be measured.
write_c_string_fd:
    mov rbx, rsi            ; rbx = start of string while rdx counts bytes.
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
;   Clobbers: rax, rsi, rdx, r9, r10, rcx, r11.
;   Teaches: write(2) may write fewer bytes than requested, so robust stream
;            programs keep writing the unwritten suffix.
write_all:
    mov r9, rsi             ; r9 = pointer to the next byte not yet written.
    mov r10, rdx            ; r10 = number of bytes still to write.
.write_loop:
    test r10, r10
    jz .success
    mov rax, SYS_WRITE      ; syscall number: write(2).
    ; arg1 rdi = output fd; arg2 rsi = next byte; arg3 rdx = remaining count.
    mov rsi, r9
    mov rdx, r10
    syscall                 ; returns bytes written or negative errno.
    test rax, rax
    jle .failure            ; zero would make no progress, so treat it as error.
    add r9, rax             ; advance past the bytes the kernel accepted.
    sub r10, rax
    jmp .write_loop
.success:
    xor eax, eax
    ret
.failure:
    mov eax, 1
    ret
