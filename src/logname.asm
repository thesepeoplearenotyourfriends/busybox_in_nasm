; logname.asm - teaching implementation of a small `logname` utility subset.
;
; First-pass semantics:
;   - With no operands, scan the initial environment for LOGNAME=VALUE.
;   - If VALUE is present and non-empty, print it followed by a newline.
;
; Why this policy:
;   - Real logname answers "who logged in on this session?" and commonly uses
;     libc getlogin(3), utmp/session records, or terminal state.
;   - Those data sources are intentionally left for later lessons. This first
;     pass teaches envp scanning while clearly reporting when LOGNAME is absent.
;
; Unsupported behavior:
;   - Options and operands are rejected.
;   - utmp, PAM, /proc/self/loginuid, controlling-terminal lookup, and libc
;     getlogin(3) are not implemented.
;
; Compatibility notes:
;   - Edited environments can make this disagree with real logname. That is an
;     explicit limitation of this teaching version, not hidden compatibility.

bits 64
default rel

global _start

section .rodata
requested_name: db "LOGNAME", 0
newline: db 10
unsupported_prefix: db "logname: unsupported option: ", 0
unsupported_suffix: db "logname: this teaching version supports no options", 10, 0
operand_prefix: db "logname: unexpected operand: ", 0
operand_suffix: db "logname: this teaching version takes no operands", 10, 0
missing_message: db "logname: LOGNAME is not set in the environment", 10, 0
empty_message: db "logname: LOGNAME is empty in the environment", 10, 0

section .text
_start:
    mov r12, [rsp]              ; r12 = argc, kept while validating operands.
    lea r13, [rsp + 8]          ; r13 = argv pointer array on the initial stack.
    ; At process entry the stack is argc, argv pointers, a NULL argv terminator,
    ; then envp pointers. r14 is long-lived: it always points at envp[0].
    lea r14, [r13 + r12*8 + 8]  ; r14 = envp pointer array after argv NULL.

    cmp r12, 1
    je .print_logname

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.print_logname:
    lea rdi, [requested_name]
    call find_environment_value
    test rax, rax
    jz .missing_logname
    cmp byte [rax], 0
    je .empty_logname

    mov rsi, rax
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

.missing_logname:
    mov rsi, missing_message
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.empty_logname:
    mov rsi, empty_message
    mov rdi, 2                  ; stderr.
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

; find_environment_value
;   Input:  rdi = requested NAME, r14 = envp pointer array.
;   Output: rax = pointer to VALUE when NAME=VALUE exists, otherwise 0.
;   Clobbers: r8, r9, r10, rdi, rsi, rdx.
;   Teaches: envp is a NULL-terminated array of pointers to NAME=VALUE strings.
find_environment_value:
    mov r8, rdi                 ; r8 = requested name kept across comparisons.
    mov r9, r14                 ; r9 = current envp slot being examined.

    ; Loop invariant: envp slots before r9 were checked and did not match. A
    ; NULL pointer marks the end of the environment array.
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
    ret
.not_found:
    xor rax, rax
    ret

; name_matches_environment_entry
;   Input:  rdi = requested NAME, rsi = environment entry NAME=VALUE.
;   Output: rax = pointer to VALUE on exact NAME match, otherwise 0.
;   Clobbers: rdx, al.
;   Teaches: matching only the NAME part so LOGNAME2=... does not match LOGNAME.
name_matches_environment_entry:
    xor rdx, rdx                ; rdx = byte offset into both strings.

    ; Loop invariant: bytes before rdx matched exactly. The requested name must
    ; end at the same position where the environment entry has '='.
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

; write_c_string_fd
;   Input:  rdi = fd, rsi = NUL-terminated string.
;   Output: rax = 0 on full write, 1 on failure or short write.
;   Clobbers: rax, rbx, rdx, rcx, r11.
;   Teaches: C strings must be counted before Linux write(2), which has no NUL
;            terminator convention.
write_c_string_fd:
    mov rbx, rsi                ; rbx = stable string start while rdx counts.
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
;   Input:  rdi = fd, rsi = buffer pointer, rdx = byte count.
;   Output: rax = 0 on full write, 1 on failure or short write.
;   Clobbers: rax, rcx, r11.
;   Teaches: raw write(2) setup after envp scanning finds text to print.
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
