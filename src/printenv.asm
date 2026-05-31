; printenv.asm - teaching implementation of a small `printenv` utility subset.
;
; Behavior implemented:
;   - With no operands, print every environment entry as NAME=VALUE lines.
;   - With one or more NAME operands, print the value for each matching
;     environment variable, one value per line.
;
; Unsupported behavior:
;   - Options such as --help, --version, and GNU's -0 output mode are not
;     implemented.
;   - Names containing '=' are accepted as literal names and will normally not
;     match environment entries.
;
; Syscalls used:
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.
;
; Error handling:
;   - Unsupported dash options print a short diagnostic and exit 1.
;   - If any requested name is missing, matching values are still printed but
;     the final exit status is 1, matching the common useful behavior.
;   - Write failures exit 1 without decoding errno values.
;
; Exit behavior:
;   - Exits 0 when all requested output is written and every requested name is
;     found; exits 1 for unsupported input, missing names, or write failure.
;
; Compatibility notes:
;   - This version focuses on envp scanning and NAME=VALUE matching. It does
;     not attempt GNU/coreutils option compatibility.

bits 64
default rel

global _start

section .rodata
newline: db 10
unsupported_prefix: db "printenv: unsupported option: ", 0
unsupported_suffix: db "printenv: this teaching version supports NAME operands only", 10, 0

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv pointer array.
    lea r14, [r13 + r12*8 + 8] ; r14 = envp pointer array after argv NULL.
    xor r15, r15            ; r15 = missing-name flag: 0 means all found so far.

    cmp r12, 1
    je .print_all_environment

    mov rbx, 1              ; rbx = argv index for requested variable names.

    ; Loop invariant: requested names before rbx have been searched; r15 records
    ; whether any of those names were missing.
.name_loop:
    cmp rbx, r12
    jae .finish_named_lookup

    mov rsi, [r13 + rbx*8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option_from_current

    mov rdi, [r13 + rbx*8]  ; requested NAME.
    call find_and_print_name
    test rax, rax
    jz .next_name
    mov r15, 1              ; remember that at least one NAME was missing.

.next_name:
    inc rbx
    jmp .name_loop

.finish_named_lookup:
    test r15, r15
    jnz .exit_failure
    jmp .exit_success

.print_all_environment:
    mov rbx, r14            ; rbx = current envp slot for print-all mode.

    ; Loop invariant: envp entries before rbx have been printed; rbx points at
    ; the next entry pointer or the NULL terminator.
.print_all_loop:
    mov rsi, [rbx]
    test rsi, rsi
    jz .exit_success

    call write_c_string_stdout
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    add rbx, 8
    jmp .print_all_loop

.unsupported_option_from_current:
    mov r15, [r13 + rbx*8]
    mov rsi, unsupported_prefix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, r15
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    test rax, rax
    jnz .exit_failure

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 2              ; stderr.
    call write_buffer_fd
    test rax, rax
    jnz .exit_failure

    mov rsi, unsupported_suffix
    mov rdi, 2              ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.exit_success:
    mov rax, 60             ; syscall number: exit(2).
    xor rdi, rdi            ; arg1 status = 0 (success).
    syscall                 ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60             ; syscall number: exit(2).
    mov rdi, 1              ; arg1 status = 1 (failure).
    syscall                 ; process terminates; no return to user code.

; find_and_print_name
;   Input:  rdi = requested NAME, r14 = envp pointer array.
;   Output: rax = 0 if found and printed, 1 if not found or write failed.
;   Clobbers: rax, rsi, rdx, r8-r11, rcx.
find_and_print_name:
    mov r8, rdi             ; r8 = requested NAME kept across comparisons.
    mov r9, r14             ; r9 = current envp slot.

    ; Loop invariant: envp slots before r9 did not match the requested NAME.
.search_loop:
    mov r10, [r9]
    test r10, r10
    jz .not_found

    mov rdi, r8
    mov rsi, r10
    call name_matches_environment_entry
    test rax, rax
    jnz .found

    add r9, 8
    jmp .search_loop

.found:
    ; rax is the value pointer returned by name_matches_environment_entry.
    mov rsi, rax
    call write_c_string_stdout
    test rax, rax
    jnz .not_found

    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_buffer_fd
    ret

.not_found:
    mov rax, 1
    ret

; name_matches_environment_entry
;   Input:  rdi = requested NAME, rsi = environment entry NAME=VALUE.
;   Output: rax = pointer to VALUE if NAME matches exactly, otherwise 0.
;   Clobbers: rdx, al.
;   Teaches: compare NAME only, then require an equals sign before VALUE.
name_matches_environment_entry:
    xor rdx, rdx            ; rdx = byte offset into both strings.

    ; Loop invariant: all bytes before rdx matched exactly.
.compare_loop:
    mov al, [rdi + rdx]
    test al, al
    jz .end_of_name
    cmp al, [rsi + rdx]
    jne .no_match
    inc rdx
    jmp .compare_loop
.end_of_name:
    cmp byte [rsi + rdx], '='
    jne .no_match
    lea rax, [rsi + rdx + 1]
    ret
.no_match:
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

write_c_string_stdout:
    mov rdi, 1              ; stdout.
    jmp write_c_string_fd

; write_c_string_fd
;   Input:  rdi = fd, rsi = NUL-terminated string.
;   Output: rax = 0 on full write, 1 on failure or short write.
;   Clobbers: rax, r11, rdx, rcx.
;   Teaches: convert C strings from argv/envp into write(2) byte counts.
write_c_string_fd:
    mov r11, rsi            ; r11 = stable string start while rdx counts.
    xor rdx, rdx
.count_loop:
    cmp byte [r11 + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop
.known_length:
    call write_buffer_fd
    ret

write_buffer_fd:
    mov rax, 1              ; syscall number: write(2).
    ; arg1 rdi = file descriptor; arg2 rsi = bytes; arg3 rdx = byte count.
    syscall                 ; returns bytes written or a negative errno.
    cmp rax, rdx            ; short writes are failure in this teaching pass.
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
