; wc.asm - teaching implementation of the standard `wc` utility.
;
; Behavior implemented:
;   - With no operands, count lines, words, and bytes from stdin.
;   - With file operands, count each file and print a total line when there is
;     more than one file operand.
;
; Behavior missing:
;   - Options such as `-l`, `-w`, `-c`, `-m`, `-L`, long options, and exact GNU
;     spacing are not implemented.  Output is simple decimal columns:
;     lines words bytes [name].
;   - The conventional `-` stdin operand is not implemented in this first pass.
;   - Diagnostics are intentionally short and do not decode errno values yet.
;
; Syscalls used:
;   - open(2), read(2), write(2), close(2), exit(2)
;
; Teaching focus:
;   - A byte scanner that maintains line, word, and byte counters while reading
;     fixed-size blocks, plus right-to-left decimal formatting for output.

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
open_prefix: db "wc: cannot open ", 0
read_msg:    db "wc: read failed", 10, 0
write_msg:   db "wc: write failed", 10, 0
space:       db " "
newline:     db 10

default_name: db 0

section .bss
buffer:       resb BUFFER_SIZE
number_buf:   resb 20
current_lines: resq 1
current_words: resq 1
current_bytes: resq 1
total_lines:   resq 1
total_words:   resq 1
total_bytes:   resq 1

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.
    mov r14, 1              ; r14 = next argv index to process as a pathname.
    xor r15d, r15d          ; r15 = accumulated process status.

    cmp r12, 1
    jne .count_named_files

    ; No operands: count stdin and print only the three default counts.
    xor edi, edi            ; input fd = stdin.
    call count_fd
    test rax, rax
    jnz .stdin_failed
    lea rsi, [default_name]
    call print_count_line
    test rax, rax
    jz .exit_with_status
.stdin_failed:
    mov r15, 1
    jmp .exit_with_status

.count_named_files:
    ; Loop purpose: count each pathname operand in order.  Invariant: r14 is the
    ; next argv index and the total_* variables include only files counted so far.
    cmp r14, r12
    jae .maybe_print_total

    mov rdi, [r13 + r14*8]
    call open_read_only
    test rax, rax
    js .open_failed

    mov rbx, rax            ; rbx = opened file descriptor until close(2).
    mov rdi, rbx
    call count_fd
    mov r10, rax            ; r10 = count status while the file is closed.

    mov rdi, rbx
    call close_fd

    test r10, r10
    jnz .count_failed

    call add_current_to_total
    mov rsi, [r13 + r14*8]
    call print_count_line
    test rax, rax
    jz .next_file
    mov r15, 1
    jmp .next_file

.count_failed:
    mov r15, 1
    jmp .next_file

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

.next_file:
    inc r14
    jmp .count_named_files

.maybe_print_total:
    cmp r12, 3              ; argc >= 3 means at least two file operands.
    jb .exit_with_status
    mov rax, [total_lines]
    mov [current_lines], rax
    mov rax, [total_words]
    mov [current_words], rax
    mov rax, [total_bytes]
    mov [current_bytes], rax
    mov rsi, total_label
    call print_count_line
    test rax, rax
    jz .exit_with_status
    mov r15, 1

.exit_with_status:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov rdi, r15            ; arg1 status = accumulated success/failure.
    syscall                 ; process terminates; no return to user code.

section .rodata
total_label: db "total", 0

section .text

; count_fd
;   Input:  rdi = input file descriptor.
;   Output: rax = 0 on success, 1 on read failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, r11, rcx.  Preserves rbx.
;   Teaches: `wc` is a state machine; a word starts when a non-whitespace byte
;            is seen after whitespace or at the beginning of input.
count_fd:
    push rbx
    mov r8, rdi             ; r8 = input fd for the whole read loop.
    xor ebx, ebx            ; bl = 1 while the scanner is inside a word.
    mov qword [current_lines], 0
    mov qword [current_words], 0
    mov qword [current_bytes], 0

.read_loop:
    ; Loop invariant: counters include all bytes from earlier chunks, and bl
    ; remembers whether the previous byte ended inside a word.
    mov rax, SYS_READ       ; syscall number: read(2).
    ; arg1 rdi = input fd; arg2 rsi = buffer; arg3 rdx = buffer capacity.
    mov rdi, r8
    lea rsi, [buffer]
    mov rdx, BUFFER_SIZE
    syscall                 ; returns byte count, 0 for EOF, or negative errno.

    test rax, rax
    js .read_failed
    jz .success

    add [current_bytes], rax
    mov r9, rax             ; r9 = bytes read in this chunk.
    xor r10d, r10d          ; r10 = scan index within buffer.

.scan_chunk:
    ; Loop purpose: classify each byte once.  Invariant: bytes before r10 have
    ; already updated the line count and word-state machine.
    cmp r10, r9
    jae .read_loop

    movzx eax, byte [buffer + r10]
    cmp al, 10
    jne .not_newline
    inc qword [current_lines]
.not_newline:
    call is_space_byte
    test rax, rax
    jnz .saw_space

    test bl, bl
    jnz .next_byte
    inc qword [current_words]
    mov bl, 1               ; the first non-space byte starts a new word.
    jmp .next_byte

.saw_space:
    xor ebx, ebx            ; whitespace ends any current word.

.next_byte:
    inc r10
    jmp .scan_chunk

.success:
    xor eax, eax
    pop rbx
    ret

.read_failed:
    mov rsi, read_msg
    call write_c_string_stderr
    mov eax, 1
    pop rbx
    ret

; is_space_byte
;   Input:  al = byte to classify.
;   Output: rax = 1 for ASCII whitespace, 0 otherwise.
;   Clobbers: rax.
;   Teaches: POSIX word counting treats spaces, tabs, newlines, vertical tabs,
;            form feeds, and carriage returns as separators.
is_space_byte:
    cmp al, ' '
    je .yes
    cmp al, 9
    jb .no
    cmp al, 13
    ja .no
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; add_current_to_total
;   Input:  current_* variables hold one file's counts.
;   Output: total_* variables are increased by those counts.
;   Clobbers: rax.
;   Teaches: separate per-file and total counters make multi-file output clear.
add_current_to_total:
    mov rax, [current_lines]
    add [total_lines], rax
    mov rax, [current_words]
    add [total_words], rax
    mov rax, [current_bytes]
    add [total_bytes], rax
    ret

; print_count_line
;   Input:  rsi = optional NUL-terminated name; empty string means no name.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: small text tools often share one formatting path for stdin, files,
;            and totals.
print_count_line:
    mov r8, rsi             ; r8 = name pointer kept across number printing.

    mov rdi, [current_lines]
    call write_uint_stdout
    test rax, rax
    jnz .failure
    call write_space_stdout
    test rax, rax
    jnz .failure

    mov rdi, [current_words]
    call write_uint_stdout
    test rax, rax
    jnz .failure
    call write_space_stdout
    test rax, rax
    jnz .failure

    mov rdi, [current_bytes]
    call write_uint_stdout
    test rax, rax
    jnz .failure

    cmp byte [r8], 0
    je .newline_only
    call write_space_stdout
    test rax, rax
    jnz .failure
    mov rdi, 1              ; stdout.
    mov rsi, r8
    call write_c_string_fd
    test rax, rax
    jnz .failure

.newline_only:
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_all
    ret

.failure:
    mov rsi, write_msg
    call write_c_string_stderr
    mov eax, 1
    ret

write_space_stdout:
    lea rsi, [space]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    jmp write_all

; write_uint_stdout
;   Input:  rdi = unsigned integer to print.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rsi, rdx, r9, r10, rcx, r11.
;   Teaches: decimal digits are easiest to produce from right to left because
;            division gives the least-significant digit first.
write_uint_stdout:
    lea r9, [number_buf + 20] ; r9 = one byte past the temporary digit buffer.
    mov rax, rdi
    test rax, rax
    jnz .format_loop
    dec r9
    mov byte [r9], '0'
    jmp .write_digits

.format_loop:
    ; `div` divides the 128-bit value rdx:rax by r10.  Clearing rdx makes this
    ; an ordinary unsigned 64-bit division; rdx receives the remainder digit.
    xor edx, edx
    mov r10, 10
    div r10
    add dl, '0'
    dec r9
    mov [r9], dl
    test rax, rax
    jnz .format_loop

.write_digits:
    lea rdx, [number_buf + 20]
    sub rdx, r9             ; byte count = end pointer - first digit pointer.
    mov rsi, r9
    mov rdi, 1              ; stdout.
    call write_all
    ret

; open_read_only
;   Input:  rdi = pathname pointer.
;   Output: rax = file descriptor on success, negative errno on failure.
;   Clobbers: rax, rsi, rdx, rcx, r11.
;   Teaches: open(2) needs flag and mode registers even for read-only opens.
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
;   Teaches: file-reading utilities should close descriptors they opened.
close_fd:
    mov rax, SYS_CLOSE      ; syscall number: close(2).
    ; arg1 rdi = file descriptor.
    syscall                 ; returns 0 or negative errno.
    ret

; write_c_string_stderr
;   Input:  rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rdx, r9, r10, rcx, r11.
;   Teaches: stderr is just file descriptor 2 passed to the generic writer.
write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, r9, r10, rcx, r11.
;   Teaches: NUL-terminated strings need a length scan before write(2).
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
;   Clobbers: rax, rsi, rdx, r9, r10, rcx, r11.
;   Teaches: write(2) can accept only a prefix, so callers retry the suffix.
write_all:
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
    ret
.failure:
    mov eax, 1
    ret
