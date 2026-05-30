; yes.asm - teaching implementation of the standard `yes` utility.
;
; Behavior implemented:
;   - With no operands, repeatedly print "y" followed by a newline.
;   - With operands, repeatedly print the operands separated by one space,
;     followed by a newline.
;
; Behavior missing:
;   - No option parsing is implemented; operands beginning with '-' are treated
;     as ordinary text, which matches the useful core of common `yes` tools.
;   - Write errors are not converted to human-readable errno messages yet.
;
; Syscalls used:
;   - write(2) for stdout
;   - exit(2)
;
; Error handling:
;   - Any failed write stops the loop and exits with status 1. This commonly
;     happens when a downstream command closes a pipe early.
;
; Compatibility notes:
;   - This is intentionally simple and writes each argument separately instead
;     of building a larger buffered line. That keeps argv and write(2) visible.

bits 64
default rel

global _start

section .rodata
default_word: db "y"
space:        db " "
newline:      db 10

section .text
_start:
    mov r12, [rsp]          ; argc: number of command-line words including argv[0].
    lea r13, [rsp + 8]      ; r13 points at argv[0] in the startup stack.

.yes_forever:
    cmp r12, 1              ; argc == 1 means no user operands were provided.
    je .write_default_line

    mov r14, 1              ; current argv index; skip argv[0], the program name.

.write_operand_loop:
    mov rsi, [r13 + r14*8]  ; rsi = pointer to argv[current].
    call write_c_string_stdout
    test rax, rax           ; helper returns 0 on success, 1 on write failure.
    jnz .exit_failure

    inc r14
    cmp r14, r12
    jae .write_line_newline ; after the final operand, end the output line.

    lea rsi, [space]
    mov rdx, 1
    call write_buffer_stdout
    test rax, rax
    jnz .exit_failure
    jmp .write_operand_loop

.write_default_line:
    lea rsi, [default_word]
    mov rdx, 1
    call write_buffer_stdout
    test rax, rax
    jnz .exit_failure

.write_line_newline:
    lea rsi, [newline]
    mov rdx, 1
    call write_buffer_stdout
    test rax, rax
    jnz .exit_failure
    jmp .yes_forever

.exit_failure:
    mov rax, 60             ; exit(2)
    mov rdi, 1              ; report a failed write as unsuccessful execution.
    syscall

; write_c_string_stdout
;   Input:  rsi = pointer to a NUL-terminated argv string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rdi, rdx, rbx, rax, rcx, r11.
;
; argv strings are C strings even though this program does not use libc. Linux
; places pointers to NUL-terminated argument bytes on the initial stack.
write_c_string_stdout:
    mov rbx, rsi            ; remember the start while scanning for the length.
    xor rdx, rdx            ; rdx will become the byte length for write(2).

.count_loop:
    cmp byte [rbx + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop

.known_length:
    ; rsi still points at the beginning of the string and rdx is its length.
    call write_buffer_stdout
    ret

; write_buffer_stdout
;   Input:  rsi = buffer pointer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdi, rcx, r11.
;
; This helper treats short writes as failure. For tiny writes to a terminal or
; pipe this is adequate for a first teaching version; robust retry loops can be
; introduced later in `cat` or `dd`-style examples.
write_buffer_stdout:
    mov rax, 1              ; write(2)
    mov rdi, 1              ; stdout file descriptor.
    syscall
    cmp rax, rdx            ; success for this simple helper means all bytes wrote.
    jne .write_failed
    xor rax, rax            ; return 0 for success.
    ret

.write_failed:
    mov rax, 1              ; return 1 for failure.
    ret
