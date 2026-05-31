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

; Linux cpu_set_t-style masks are bitsets. 128 bytes * 8 bits/byte lets
; this teaching version represent CPU numbers 0 through 1023 (1024 possible
; CPU bits) without introducing dynamic allocation yet.
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
    mov r12, [rsp]              ; r12 = argc, kept while validating operands.
    lea r13, [rsp + 8]          ; r13 = argv pointer array on the initial stack.

    cmp r12, 1
    je .print_available_processor_count

    mov rsi, [r13 + 8]
    call starts_with_dash
    test rax, rax
    jnz .unsupported_option
    jmp .unexpected_operand

.print_available_processor_count:
    ; sched_getaffinity(pid, cpusetsize, mask) asks the kernel which CPUs this
    ; process may run on. Linux x86_64 syscall arguments go in rdi, rsi, rdx, ...
    mov rax, 204                ; syscall number: sched_getaffinity(2).
    xor rdi, rdi                ; arg1 pid = 0 means the current process.
    mov rsi, CPU_MASK_BYTES     ; arg2 cpusetsize = bytes available in cpu_mask.
    lea rdx, [cpu_mask]         ; arg3 mask = output buffer for CPU affinity bits.
    syscall                     ; kernel fills cpu_mask or returns a negative errno.
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
    mov rax, 60                 ; syscall number: exit(2).
    xor rdi, rdi                ; arg1 status = 0 (success).
    syscall                     ; process terminates; no return to user code.

.exit_failure:
    mov rax, 60                 ; syscall number: exit(2).
    mov rdi, 1                  ; arg1 status = 1 (failure).
    syscall                     ; process terminates; no return to user code.

; count_affinity_bits
;   Input:  fixed global cpu_mask filled by sched_getaffinity(2).
;   Output: rax = number of set bits in the fixed cpu_mask buffer.
;   Clobbers: r8, r9, r10, r11, rcx, rdx.
;   Teaches: a byte loop nested around a bit loop for reading a packed bitset.
;   Notes:  This intentionally uses small loops instead of clever bit tricks so
;           the byte/bit scan is easy to follow in a debugger.
count_affinity_bits:
    lea r8, [cpu_mask]          ; r8 = address of the next mask byte to inspect.
    mov r9, CPU_MASK_BYTES      ; r9 = number of bytes not processed yet.
    xor r10, r10                ; r10 = running total of set CPU bits.

    ; Byte-loop invariant: bytes before r8 have been counted, r9 bytes remain,
    ; and r10 holds the number of 1 bits seen so far.
.byte_loop:
    cmp r9, 0
    je .done

    movzx r11, byte [r8]        ; r11 = current byte, zero-extended for shifts.
    mov rcx, 8                  ; rcx = bits remaining in this byte.

    ; Bit-loop invariant: the low bit of r11 is the next CPU bit to count.
    ; `loop` is unusual: it decrements rcx automatically, then jumps if rcx != 0.
.bit_loop:
    mov rdx, r11
    and rdx, 1                  ; mask off every bit except the current low bit.
    add r10, rdx                ; add 0 or 1 to the total.
    shr r11, 1                  ; shift the next CPU bit into the low-bit position.
    loop .bit_loop              ; rcx--, repeat until all 8 bits were inspected.

    inc r8
    dec r9
    jmp .byte_loop
.done:
    mov rax, r10
    ret

; write_unsigned_decimal_stdout
;   Input:  rax = unsigned integer to print.
;   Output: rax = 0 on success, 1 on write failure.
;   Clobbers: r8, r9, r10, rdx, rsi, rdi, rcx, r11.
;   Teaches: decimal conversion by repeated division by 10.
write_unsigned_decimal_stdout:
    ; The least-significant decimal digit is produced first by division. Humans
    ; read the most-significant digit first, so we reserve the end of the buffer
    ; and store digits right-to-left as remainders appear.
    lea r8, [number_buffer + 20] ; r8 = one byte past the end of the digit area.
    xor r9, r9                  ; r9 = digit count.
    mov r10, 10                 ; divisor for base-10 conversion.

    test rax, rax
    jnz .divide_loop
    dec r8
    mov byte [r8], '0'
    mov r9, 1
    jmp .write_number

.divide_loop:
    xor rdx, rdx                ; unsigned div reads rdx:rax, so clear high half.
    div r10                     ; rax = quotient, rdx = remainder 0..9.
    add dl, '0'                ; turn numeric remainder into an ASCII digit.
    dec r8                      ; move left because digits are built right-to-left.
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

; write_c_string_fd
;   Input:  rdi = fd, rsi = NUL-terminated string.
;   Output: rax = 0 on full write, 1 on failure or short write.
;   Clobbers: rax, rbx, rdx, rcx, r11.
;   Teaches: C-string length scanning before a write(2) call.
write_c_string_fd:
    mov rbx, rsi                ; rbx = start of string while rdx counts bytes.
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
;   Teaches: raw write(2) setup; this pass treats short writes as failure so
;            stream retry loops can be taught later in a dedicated utility.
write_buffer_fd:
    mov rax, 1                  ; syscall number: write(2).
    ; arg1 rdi = file descriptor; arg2 rsi = bytes; arg3 rdx = byte count.
    syscall                     ; rcx and r11 are clobbered by the syscall ABI.
    cmp rax, rdx                ; any short write is failure in this teaching pass.
    jne .write_failed
    xor rax, rax
    ret
.write_failed:
    mov rax, 1
    ret
