; tee.asm - teaching implementation of the standard `tee` utility.
;
; Behavior implemented:
;   - Copy stdin to stdout and to each named output file.
;   - Supports a simple `-a` option before file operands to append instead of
;     truncating output files.
;
; Behavior missing:
;   - `-i`, long options, repeated option clusters, and errno-specific
;     diagnostics are not implemented.
;   - This teaching version stores at most 32 output file descriptors.
;
; Syscalls used:
;   - open(2), read(2), write(2), close(2), exit(2)
;
; Teaching focus:
;   - Fan-out: one input buffer is written to stdout and then to several files,
;     with a write-all helper used for each destination.

bits 64
default rel

global _start

%define SYS_READ   0
%define SYS_WRITE  1
%define SYS_OPEN   2
%define SYS_CLOSE  3
%define SYS_EXIT   60

%define O_WRONLY   1
%define O_CREAT    64
%define O_TRUNC    512
%define O_APPEND   1024
%define FILE_MODE  0666o
%define BUFFER_SIZE 4096
%define MAX_FILES  32

section .rodata
open_prefix:       db "tee: cannot open ", 0
too_many_msg:      db "tee: too many output files", 10, 0
unsupported_prefix: db "tee: unsupported option: ", 0
read_msg:          db "tee: read failed", 10, 0
write_msg:         db "tee: write failed", 10, 0
newline:           db 10

section .bss
buffer: resb BUFFER_SIZE
fds:    resq MAX_FILES

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.
    mov r14, 1              ; r14 = argv index being parsed.
    xor r15d, r15d          ; r15 = number of successfully opened output files.
    xor ebx, ebx            ; ebx = 0 for truncate mode, 1 for append mode.

    cmp r14, r12
    jae .copy_input

    mov rsi, [r13 + r14*8]
    call is_dash_a
    test rax, rax
    jz .open_outputs
    mov ebx, 1              ; `-a` selects append mode for all later files.
    inc r14
    jmp .open_outputs

.open_outputs:
    ; Loop purpose: open each output pathname before copying stdin.  Invariant:
    ; fds[0..r15) are valid descriptors that should receive every input chunk.
    cmp r14, r12
    jae .copy_input

    mov rsi, [r13 + r14*8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option

    cmp r15, MAX_FILES
    jae .too_many_outputs

    mov rdi, [r13 + r14*8]
    mov rsi, O_WRONLY | O_CREAT | O_TRUNC
    test ebx, ebx
    jz .have_flags
    mov rsi, O_WRONLY | O_CREAT | O_APPEND
.have_flags:
    call open_output_file
    test rax, rax
    js .open_failed

    mov [fds + r15*8], rax
    inc r15
    inc r14
    jmp .open_outputs

.unsupported_option:
    mov rsi, unsupported_prefix
    call write_c_string_stderr
    mov rsi, [r13 + r14*8]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    mov r14, 1              ; r14 = final status for this early error.
    jmp .close_and_exit

.too_many_outputs:
    mov rsi, too_many_msg
    call write_c_string_stderr
    mov r14, 1
    jmp .close_and_exit

.open_failed:
    mov rsi, open_prefix
    call write_c_string_stderr
    mov rsi, [r13 + r14*8]
    call write_c_string_stderr
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_all
    mov r14, 1
    jmp .close_and_exit

.copy_input:
    call copy_stdin_to_outputs
    mov r14, rax            ; r14 = copy status, saved while closing files.

.close_and_exit:
    call close_open_outputs
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov rdi, r14            ; arg1 status = 0 on success, 1 on failure.
    syscall                 ; process terminates; no return to user code.

; copy_stdin_to_outputs
;   Input:  r15 = number of file descriptors stored in fds[].
;   Output: rax = 0 on success, 1 on read or write failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: tee writes each input chunk to stdout first, then reuses the same
;            buffer for every output file.
copy_stdin_to_outputs:
.read_loop:
    ; Loop invariant: every earlier input chunk was written to stdout and all
    ; opened output files before the next read starts.
    mov rax, SYS_READ       ; syscall number: read(2).
    ; arg1 rdi = stdin; arg2 rsi = buffer; arg3 rdx = buffer capacity.
    xor edi, edi
    lea rsi, [buffer]
    mov rdx, BUFFER_SIZE
    syscall                 ; returns byte count, 0 for EOF, or negative errno.

    test rax, rax
    js .read_failed
    jz .success

    mov r8, rax             ; r8 = bytes to write from this input chunk.

    mov rdi, 1              ; stdout.
    lea rsi, [buffer]
    mov rdx, r8
    call write_all
    test rax, rax
    jnz .write_failed

    xor r9d, r9d            ; r9 = index of next output fd.
.write_file_loop:
    ; Loop invariant: files before r9 already received this exact input chunk.
    cmp r9, r15
    jae .read_loop
    mov rdi, [fds + r9*8]
    lea rsi, [buffer]
    mov rdx, r8
    call write_all
    test rax, rax
    jnz .write_failed
    inc r9
    jmp .write_file_loop

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

; close_open_outputs
;   Input:  r15 = number of file descriptors stored in fds[].
;   Output: close errors are ignored, matching many small teaching utilities here.
;   Clobbers: rax, rdi, r8, rcx, r11.
;   Teaches: even when the main copy fails, opened files still need close(2).
close_open_outputs:
    xor r8d, r8d            ; r8 = index of next descriptor to close.
.close_loop:
    cmp r8, r15
    jae .done
    mov rdi, [fds + r8*8]
    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = file descriptor.
    syscall                 ; returns 0 or negative errno, ignored here.
    inc r8
    jmp .close_loop
.done:
    ret

; open_output_file
;   Input:  rdi = pathname, rsi = open flags.
;   Output: rax = file descriptor on success, negative errno on failure.
;   Clobbers: rax, rdx, rcx, r11.
;   Teaches: create/truncate and append are only flag differences to open(2).
open_output_file:
    mov rax, SYS_OPEN       ; syscall number: open(2).
    ; arg1 rdi = pathname; arg2 rsi = flags; arg3 rdx = file mode for O_CREAT.
    mov rdx, FILE_MODE
    syscall                 ; returns fd or negative errno.
    ret

; is_dash_a
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 1 for exactly "-a", otherwise 0.
;   Clobbers: rax.
is_dash_a:
    cmp byte [rsi], '-'
    jne .no
    cmp byte [rsi + 1], 'a'
    jne .no
    cmp byte [rsi + 2], 0
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; starts_with_dash
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 1 if the first byte is a dash, otherwise 0.
;   Clobbers: rax.
;   Teaches: this subset rejects option-looking operands explicitly.
starts_with_dash:
    cmp byte [rsi], '-'
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; write_c_string_stderr
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rdx, r9, r10, rcx, r11.
;   Teaches: stderr diagnostics reuse the same length-scan writer as stdout.
write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, rcx, r11.
;   Teaches: a NUL-terminated diagnostic needs a byte count before write(2).
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
;   Clobbers: rax, rsi, rdx, rcx, r11.  Preserves r9 and r10 for callers.
;   Teaches: preserving loop registers can make callers easier to read.
write_all:
    push r9
    push r10
    mov r9, rsi             ; r9 = pointer to next byte not yet written.
    mov r10, rdx            ; r10 = bytes still to write.
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
    pop r10
    pop r9
    ret
.failure:
    mov eax, 1
    pop r10
    pop r9
    ret
