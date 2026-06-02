; which.asm - teaching implementation of a small `which` utility.
;
; Behavior implemented:
;   - Accept one or more command-name operands.
;   - If an operand contains '/', test that path directly with access(X_OK).
;   - Otherwise search PATH and print the first executable candidate.
;
; Behavior missing:
;   - Options such as `-a`, shell aliases/functions/builtins, permission
;     details, hashed command tables, and `--help`/`--version` are not
;     implemented.
;
; Syscalls used:
;   - access(2), write(2), exit(2)
;
; Teaching focus:
;   - PATH lookup is string splitting plus one kernel executability check per
;     candidate; no shell magic is needed for a first pass.

bits 64
default rel

global _start

%define SYS_WRITE  1
%define SYS_ACCESS 21
%define SYS_EXIT   60

%define X_OK 1
%define CANDIDATE_SIZE 4096

section .rodata
missing_msg: db "which: missing command operand", 10, 0
not_found_1: db "which: ", 0
not_found_2: db " not found", 10, 0
path_name:   db "PATH=", 0
default_path: db "/usr/local/bin:/usr/bin:/bin", 0
newline:     db 10

section .bss
candidate: resb CANDIDATE_SIZE

section .text
_start:
    mov r12, [rsp]          ; r12 = argc, including argv[0].
    lea r13, [rsp + 8]      ; r13 = argv array from the initial stack.
    mov r14, 1              ; r14 = argv index of next command operand.
    xor r15d, r15d          ; r15 = accumulated process status.

    cmp r12, 2
    jb .missing_operand

    ; envp starts after argv[argc] and the NULL pointer that terminates argv.
    lea rdi, [r13 + r12*8 + 8]
    call find_path_env
    test rax, rax
    jnz .have_path
    lea rax, [default_path]
.have_path:
    mov rbx, rax            ; rbx = PATH value reused for every operand.

.process_operands:
    ; Loop purpose: resolve each command operand independently.  Invariant:
    ; r15 is nonzero once any operand has not been found.
    cmp r14, r12
    jae .exit_with_status
    mov rdi, [r13 + r14*8]
    mov rsi, rbx
    call find_command
    test rax, rax
    jnz .next_operand

    mov r15, 1
    mov rsi, not_found_1
    call write_c_string_stderr
    mov rsi, [r13 + r14*8]
    call write_c_string_stderr
    mov rsi, not_found_2
    call write_c_string_stderr

.next_operand:
    inc r14
    jmp .process_operands

.missing_operand:
    mov rsi, missing_msg
    call write_c_string_stderr
    mov r15, 1

.exit_with_status:
    mov rax, SYS_EXIT       ; syscall number: exit(2).
    mov rdi, r15            ; arg1 status = accumulated success/failure.
    syscall                 ; process terminates; no return to user code.

; find_path_env
;   Input:  rdi = envp array, terminated by a NULL pointer.
;   Output: rax = pointer to PATH value after "PATH=", or 0 if not present.
;   Clobbers: rax, rdi, rsi, r8, rcx.
;   Teaches: envp is just an array of pointers to NAME=VALUE byte strings.
find_path_env:
    mov r8, rdi             ; r8 = current envp slot.
.next_env:
    mov rsi, [r8]
    test rsi, rsi
    jz .not_present
    lea rdi, [path_name]
    call starts_with_c_string
    test rax, rax
    jnz .found
    add r8, 8
    jmp .next_env
.found:
    mov rax, [r8]
    add rax, 5
    ret
.not_present:
    xor eax, eax
    ret

; find_command
;   Input:  rdi = command operand, rsi = PATH value.
;   Output: rax = 1 if a path was printed, 0 if not found.
;   Clobbers: rax, rdi, rsi, rdx, r8, r9, r10, rcx, r11.
;   Teaches: operands containing '/' bypass PATH; simple names try each PATH
;            directory joined with a slash.
find_command:
    mov r8, rdi             ; r8 = command operand.
    mov r9, rsi             ; r9 = PATH scan pointer.
    call contains_slash
    test rax, rax
    jz .search_path

    mov rdi, r8
    call is_executable
    test rax, rax
    jz .not_found
    mov rsi, r8
    call write_c_string_stdout_line
    mov eax, 1
    ret

.search_path:
    ; Loop invariant: r9 points at the first byte of the next PATH component.
    mov r10, r9             ; r10 = component start.
.find_component_end:
    cmp byte [r9], 0
    je .try_component
    cmp byte [r9], ':'
    je .try_component
    inc r9
    jmp .find_component_end

.try_component:
    mov rdi, r10
    mov rsi, r9
    mov rdx, r8
    call build_candidate
    test rax, rax
    jz .after_component

    lea rdi, [candidate]
    call is_executable
    test rax, rax
    jz .after_component

    lea rsi, [candidate]
    call write_c_string_stdout_line
    mov eax, 1
    ret

.after_component:
    cmp byte [r9], 0
    je .not_found
    inc r9                  ; skip ':' before the next component.
    jmp .search_path
.not_found:
    xor eax, eax
    ret

; build_candidate
;   Input:  rdi = component start, rsi = component end, rdx = command name.
;   Output: rax = 1 and candidate[] is NUL-terminated, or 0 if too long.
;   Clobbers: rax, rdi, rsi, rdx, r10, r11.
;   Teaches: an empty PATH component means the current directory, written here
;            as "." so the printed answer is explicit.
build_candidate:
    lea r11, [candidate]    ; r11 = next output byte in candidate buffer.
    xor r10d, r10d          ; r10 = candidate length excluding final NUL.

    cmp rdi, rsi
    jne .copy_component
    mov byte [r11], '.'
    inc r11
    inc r10
    jmp .add_slash

.copy_component:
    ; Loop invariant: bytes [component start, rdi) are copied to candidate[].
    cmp rdi, rsi
    jae .add_slash
    cmp r10, CANDIDATE_SIZE - 2
    jae .too_long
    mov al, [rdi]
    mov [r11], al
    inc rdi
    inc r11
    inc r10
    jmp .copy_component

.add_slash:
    cmp r10, CANDIDATE_SIZE - 2
    jae .too_long
    mov byte [r11], '/'
    inc r11
    inc r10

.copy_name:
    ; Loop invariant: candidate holds "component/" plus bytes before rdx.
    mov al, [rdx]
    test al, al
    jz .finish
    cmp r10, CANDIDATE_SIZE - 1
    jae .too_long
    mov [r11], al
    inc rdx
    inc r11
    inc r10
    jmp .copy_name
.finish:
    mov byte [r11], 0
    mov eax, 1
    ret
.too_long:
    xor eax, eax
    ret

; contains_slash
;   Input:  rdi = NUL-terminated string.
;   Output: rax = 1 if the string contains '/', otherwise 0.
;   Clobbers: rax, rdi.
;   Teaches: command names with a slash are already paths, so PATH is skipped.
contains_slash:
.scan:
    mov al, [rdi]
    test al, al
    jz .no
    cmp al, '/'
    je .yes
    inc rdi
    jmp .scan
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; is_executable
;   Input:  rdi = NUL-terminated pathname.
;   Output: rax = 1 when access(path, X_OK) succeeds, otherwise 0.
;   Clobbers: rax, rsi, rcx, r11.
;   Teaches: access(2) asks the kernel whether this process may execute path.
is_executable:
    mov rax, SYS_ACCESS     ; syscall number: access(2).
    ; arg1 rdi = path; arg2 rsi = X_OK executability check.
    mov rsi, X_OK
    syscall                 ; returns 0 on success or negative errno.
    test rax, rax
    jz .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; starts_with_c_string
;   Input:  rsi = candidate string, rdi = required prefix string.
;   Output: rax = 1 when candidate starts with prefix, otherwise 0.
;   Clobbers: rax, rsi, rdi, rcx.
;   Teaches: NAME matching is a byte comparison through the prefix NUL.
starts_with_c_string:
.compare:
    mov al, [rdi]
    test al, al
    jz .yes
    cmp [rsi], al
    jne .no
    inc rsi
    inc rdi
    jmp .compare
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

write_c_string_stderr:
    mov rdi, 2              ; stderr.
    jmp write_c_string_fd

write_c_string_stdout_line:
    mov rdi, 1              ; stdout.
    call write_c_string_fd
    test rax, rax
    jnz .done
    lea rsi, [newline]
    mov rdx, 1
    mov rdi, 1              ; stdout.
    call write_all
.done:
    ret

; write_c_string_fd
;   Input:  rdi = output fd, rsi = NUL-terminated string.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rdx, r9, r10, rcx, r11.
;   Teaches: raw write(2) uses byte counts, so C strings must be measured.
write_c_string_fd:
    push rdi
    mov r9, rsi             ; r9 = start of string while rdx counts bytes.
    xor edx, edx
.count_loop:
    cmp byte [r9 + rdx], 0
    je .known_length
    inc rdx
    jmp .count_loop
.known_length:
    pop rdi
    call write_all
    ret

; write_all
;   Input:  rdi = output fd, rsi = buffer, rdx = byte count.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: rax, rsi, rdx, r9, r10, rcx, r11.
;   Teaches: a partial write advances the pointer and retries remaining bytes.
write_all:
    mov r9, rsi             ; r9 = next byte to write.
    mov r10, rdx            ; r10 = bytes still unwritten.
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
