; nproc.asm - teaching implementation of a small `nproc` utility subset.
;
; First-pass semantics:
;   - With no operands, call sched_getaffinity(2) for the current process.
;   - Count one bit for each CPU allowed by that affinity mask.
;   - Print the count as unsigned decimal followed by a newline.
;
; Why this policy:
;   - Real nproc may account for options, environment, libc sysconf(3), online
;     CPU state, and system configuration policy.
;   - The affinity-mask rule is small, visible, and useful in containers where
;     the process may be restricted to fewer CPUs than the host owns.
;
; Unsupported behavior:
;   - Options such as --all, --ignore=N, --help, and --version are rejected.
;   - CPU masks larger than 1024 CPUs, cgroup CPU quotas, and hotplug races are
;     not handled in this primer implementation.
;
; Syscalls used:
;   - sched_getaffinity(2) to read the current process CPU affinity mask.
;   - write(2) for stdout and stderr.
;   - exit(2) for the process status.

bits 64
default rel

global _start

%define CPU_MASK_BYTES 128

section .rodata
newline: db 10
unsupported_prefix: db "nproc: unsupported option: ", 0
unsupported_suffix: db "nproc: this teaching version supports no options", 10, 0
operand_prefix: db "nproc: unexpected operand: ", 0
operand_suffix: db "nproc: this teaching version takes no operands", 10, 0
affinity_failed_message: db "nproc: sched_getaffinity failed", 10, 0
zero_cpus_message: db "nproc: affinity mask contained no CPUs", 10, 0

section .bss
cpu_mask: resb CPU_MASK_BYTES
number_buffer: resb 20

section .text
_start:
    mov r12, [rsp]              ; argc.
    lea r13, [rsp + 8]          ; argv pointer array.

    cmp r12, 1
    je .print_available_processor_count

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.print_available_processor_count:
    mov rax, 204                ; sched_getaffinity(2)
    xor rdi, rdi                ; pid 0 means current process.
    mov rsi, CPU_MASK_BYTES
    lea rdx, [cpu_mask]
    syscall
    test rax, rax
    js .affinity_failed

    call count_affinity_bits
    test rax, rax
    jz .zero_cpus

    call write_unsigned_decimal_stdout
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

.affinity_failed:
    mov rsi, affinity_failed_message
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.zero_cpus:
    mov rsi, zero_cpus_message
    mov rdi, 2                  ; stderr.
    call write_c_string_fd
    jmp .exit_failure

.exit_success:
    mov rax, 60                 ; exit(2)
    xor rdi, rdi
    syscall

.exit_failure:
    mov rax, 60                 ; exit(2)
    mov rdi, 1
    syscall

; count_affinity_bits
;   Output: rax = number of set bits in the fixed cpu_mask buffer.
;   Notes:  This intentionally uses small loops instead of clever bit tricks so
;           the byte/bit scan is easy to follow in a debugger.
count_affinity_bits:
    lea r8, [cpu_mask]
    mov r9, CPU_MASK_BYTES
    xor r10, r10                ; total set-bit count.
.byte_loop:
    cmp r9, 0
    je .done

    movzx r11, byte [r8]
    mov rcx, 8                  ; bits remaining in this byte.
.bit_loop:
    mov rdx, r11
    and rdx, 1
    add r10, rdx
    shr r11, 1
    loop .bit_loop

    inc r8
    dec r9
    jmp .byte_loop
.done:
    mov rax, r10
    ret

; write_unsigned_decimal_stdout
;   Input:  rax = unsigned integer to print.
;   Output: rax = 0 on success, 1 on write failure.
write_unsigned_decimal_stdout:
    lea r8, [number_buffer + 20]
    xor r9, r9
    mov r10, 10

    test rax, rax
    jnz .divide_loop
    dec r8
    mov byte [r8], '0'
    mov r9, 1
    jmp .write_number

.divide_loop:
    xor rdx, rdx
    div r10
    add dl, '0'
    dec r8
    mov [r8], dl
    inc r9
    test rax, rax
    jnz .divide_loop

.write_number:
    mov rsi, r8
    mov rdx, r9
    mov rdi, 1                  ; stdout.
    call write_buffer_fd
    ret

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
    mov rax, 1                  ; write(2)
    syscall
    cmp rax, rdx
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
