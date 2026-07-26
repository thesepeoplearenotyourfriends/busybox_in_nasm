; head.asm - a plain, field-usable teaching implementation of `head`.
;
; Supported behavior:
;   - Print ten lines by default, or select a limit with `-n COUNT` / `-c COUNT`.
;   - Process files and conventional `-` stdin operands in argument order.
;   - Print GNU/BusyBox-style headers when there is more than one operand.
;   - `--` ends option parsing.  Quiet/verbose header options are deliberately not
;     included: headers are automatic and depend only on the operand count.
;   - Counts are unsigned decimal integers from 0 through UINT64_MAX.  Signs,
;     suffixes, empty counts, and overflowing values are rejected rather than
;     silently truncated.
;
; Errors name the failing operand.  read(2) and write(2) retry after EINTR;
; write_all preserves the unwritten suffix after a partial write.  Every opened
; descriptor is closed, and the exit status is 1 if any open, read, output, or
; close operation failed (otherwise 0).  A failed stdout stops further operands.
;
; Linux x86-64 syscalls used: open(2), read(2), write(2), close(2), exit(2).

bits 64
default rel
global _start

%define SYS_READ 0
%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_EXIT 60
%define O_RDONLY 0
%define EINTR 4
%define BUFFER_SIZE 4096
%define MODE_LINES 0
%define MODE_BYTES 1

section .rodata
usage_msg: db "head: expected -n COUNT or -c COUNT",10
usage_len: equ $-usage_msg
invalid_prefix: db "head: invalid count: "
invalid_prefix_len: equ $-invalid_prefix
open_prefix: db "head: cannot open "
open_prefix_len: equ $-open_prefix
read_prefix: db "head: read failed: "
read_prefix_len: equ $-read_prefix
close_prefix: db "head: close failed: "
close_prefix_len: equ $-close_prefix
write_msg: db "head: write failed",10
write_msg_len: equ $-write_msg
header_start: db "==> "
header_start_len: equ $-header_start
header_end: db " <==",10
header_end_len: equ $-header_end
newline: db 10
stdin_name: db "standard input",0

section .bss
buffer: resb BUFFER_SIZE
mode: resq 1
limit: resq 1
first_operand: resq 1
operand_count: resq 1
final_status: resq 1
header_printed: resq 1
current_name: resq 1

section .text
_start:
    mov r12, [rsp]              ; r12 = argc for the whole program.
    lea r13, [rsp+8]            ; r13 = argv pointer array.
    mov qword [mode], MODE_LINES
    mov qword [limit], 10
    mov qword [final_status], 0
    mov qword [header_printed], 0

    ; Section 1: option parsing.
    ; Loop invariant: argv[1..r14-1] are completely parsed options.
    mov r14, 1                  ; r14 = index of the next argv entry to parse.
.parse_options:
    cmp r14, r12
    jae .options_done
    mov rbx, [r13+r14*8]        ; rbx = current argument string.
    cmp byte [rbx], '-'
    jne .options_done
    cmp byte [rbx+1], 0         ; A lone '-' is an operand, not an option.
    je .options_done
    cmp byte [rbx+1], '-'
    jne .maybe_count_option
    cmp byte [rbx+2], 0
    jne .bad_option
    inc r14                     ; `--` itself is not an operand.
    jmp .options_done
.maybe_count_option:
    cmp byte [rbx+2], 0         ; Only the plain two-byte forms are accepted.
    jne .bad_option
    mov al, [rbx+1]
    cmp al, 'n'
    je .line_option
    cmp al, 'c'
    jne .bad_option
    mov qword [mode], MODE_BYTES
    jmp .take_count
.line_option:
    mov qword [mode], MODE_LINES
.take_count:
    inc r14
    cmp r14, r12
    jae .bad_option
    mov rdi, [r13+r14*8]
    call parse_count
    test rdx, rdx
    jnz .bad_count
    mov [limit], rax
    inc r14
    jmp .parse_options
.bad_count:
    mov rsi, invalid_prefix
    mov rdx, invalid_prefix_len
    call diagnostic_part
    mov rsi, [r13+r14*8]
    call diagnostic_string
    call diagnostic_newline
    mov qword [final_status], 1
    jmp .exit
.bad_option:
    mov rsi, usage_msg
    mov rdx, usage_len
    call diagnostic_part
    mov qword [final_status], 1
    jmp .exit

.options_done:
    mov [first_operand], r14
    mov rax, r12
    sub rax, r14
    mov [operand_count], rax

    ; Section 2: operand iteration.  No operands means one implicit stdin input.
    test rax, rax
    jnz .operand_loop_setup
    mov qword [operand_count], 1
    mov qword [current_name], stdin_name
    xor edi, edi
    call process_stream
    jmp .exit

.operand_loop_setup:
    ; Loop invariant: every operand before r14 has been opened or diagnosed,
    ; processed, and (when applicable) closed; final_status remembers failures.
.operand_loop:
    cmp r14, r12
    jae .exit
    mov rbx, [r13+r14*8]        ; rbx = current operand, retained through open.
    mov [current_name], rbx
    cmp byte [rbx], '-'
    jne .open_operand
    cmp byte [rbx+1], 0
    jne .open_operand
    mov qword [current_name], stdin_name
    xor edi, edi                ; fd 0 is reused for every '-' operand.
    call process_stream
    cmp qword [final_status], 2 ; A failed stdout makes further operands useless.
    je .exit
    jmp .next_operand

    ; Section 3: stream opening.
.open_operand:
    mov rax, SYS_OPEN           ; open(2): rdi=path, rsi=O_RDONLY, rdx=unused mode.
    mov rdi, rbx
    mov rsi, O_RDONLY
    xor edx, edx
    syscall                     ; returns a descriptor or a negative errno.
    test rax, rax
    js .open_failed
    mov r15, rax                ; r15 = opened fd until its close(2).
    mov rdi, r15
    call process_stream

    mov rax, SYS_CLOSE          ; close(2): rdi=the descriptor opened above.
    mov rdi, r15
    syscall                     ; close is not retried: the fd state is ambiguous.
    test rax, rax
    js .close_failed
    jmp .after_close
.open_failed:
    mov rsi, open_prefix
    mov rdx, open_prefix_len
    call operand_diagnostic
    jmp .next_operand
.close_failed:
    mov rsi, close_prefix
    mov rdx, close_prefix_len
    call operand_diagnostic
.after_close:
    cmp qword [final_status], 2 ; Status 2 means stdout failed: do not write more.
    je .exit
.next_operand:
    inc r14
    jmp .operand_loop

.exit:
    mov rdi, [final_status]
    test rdi, rdi
    setnz dil
    movzx rdi, dil
    mov rax, SYS_EXIT           ; exit(2): rdi=aggregated status (zero or one).
    syscall                     ; successful syscall does not return.

; process_stream
;   Input: rdi = readable fd; current_name identifies it.
;   Output: none; final_status records failures.
;   Clobbers: caller-saved registers plus r8-r11.
;   Teaches: headers, limiting, robust block reads, and writes are separate steps.
process_stream:
    mov r8, rdi                 ; r8 = input fd throughout this stream.

    ; Ordinary multi-file headers appear before every operand, with a blank line
    ; between headers.  This matches GNU head for the supported option subset.
    cmp qword [operand_count], 1
    jbe .limit_setup
    cmp qword [header_printed], 0
    je .header_text
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1
    call write_all
    test rax, rax
    jnz .output_failed
.header_text:
    mov rdi, 1
    mov rsi, header_start
    mov rdx, header_start_len
    call write_all
    test rax, rax
    jnz .output_failed
    mov rdi, 1
    mov rsi, [current_name]
    call write_c_string
    test rax, rax
    jnz .output_failed
    mov rdi, 1
    mov rsi, header_end
    mov rdx, header_end_len
    call write_all
    test rax, rax
    jnz .output_failed
    mov qword [header_printed], 1

    ; Section 4: line/byte limiting.  r9 is the remaining byte or line count.
.limit_setup:
    mov r9, [limit]             ; r9 = units still allowed for this operand.
    test r9, r9
    jz .success

    ; Section 5: robust buffered reads.
    ; Loop invariant: all selected bytes from prior reads have reached stdout,
    ; and r9 is the number of selected units still needed.
.read_loop:
.retry_read:
    mov rax, SYS_READ           ; read(2): rdi=input fd, rsi=buffer, rdx=capacity.
    mov rdi, r8
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    cmp qword [mode], MODE_LINES
    je .perform_read
    cmp r9, rdx                 ; Byte mode need not read beyond its remaining limit.
    cmovb rdx, r9
.perform_read:
    syscall                     ; returns bytes read, EOF zero, or negative errno.
    cmp rax, -EINTR
    je .retry_read
    test rax, rax
    js .read_failed
    jz .success
    mov r10, rax                ; r10 = bytes returned in this buffer.
    cmp qword [mode], MODE_BYTES
    je .byte_chunk

    xor r11d, r11d              ; r11 = scan index / selected prefix length.
    ; Scan invariant: buffer[0..r11-1] belongs to the output and each newline
    ; already seen has reduced the remaining line count exactly once.
.scan_lines:
    cmp r11, r10
    jae .write_chunk
    cmp byte [buffer+r11], 10
    jne .scan_next
    dec r9
.scan_next:
    inc r11
    test r9, r9
    jnz .scan_lines
    mov r10, r11                ; Exclude bytes after the limiting newline.
    ; Line mode has already reduced r9 once per newline.  Do not fall through
    ; into byte-mode subtraction and underflow the now-zero line count.
    jmp .write_chunk
.byte_chunk:
    sub r9, r10                 ; byte-mode reads are capped, so no underflow.
.write_chunk:
    mov rdi, 1
    mov rsi, buffer
    mov rdx, r10
    call write_all
    test rax, rax
    jnz .output_failed
    test r9, r9
    jnz .read_loop
.success:
    ret
.read_failed:
    mov rsi, read_prefix
    mov rdx, read_prefix_len
    call operand_diagnostic
    ret
.output_failed:
    mov qword [final_status], 2
    mov rsi, write_msg
    mov rdx, write_msg_len
    call diagnostic_part        ; Best effort: stderr itself may also be broken.
    ret

; parse_count
;   Input: rdi = NUL-terminated unsigned decimal string.
;   Output: rax = value; rdx = 0 success or 1 invalid/overflow.
;   Clobbers: rax, rdx, rcx, rsi, r8.
;   Teaches: checking before multiply/add prevents modulo-2^64 truncation.
parse_count:
    xor eax, eax
    xor ecx, ecx
    cmp byte [rdi], 0
    je .invalid
    mov r8, 1844674407370955161  ; floor(UINT64_MAX / 10).
.parse_digit_loop:
    ; Invariant: rax exactly represents all digits before index rcx.
    movzx esi, byte [rdi+rcx]
    test sil, sil
    jz .valid
    sub esi, '0'
    cmp esi, 9
    ja .invalid
    cmp rax, r8
    ja .invalid
    jb .safe_digit
    cmp esi, 5                  ; UINT64_MAX ends in digit 5.
    ja .invalid
.safe_digit:
    imul rax, rax, 10           ; Decimal place shift: old value * 10.
    add rax, rsi
    inc rcx
    jmp .parse_digit_loop
.valid:
    xor edx, edx
    ret
.invalid:
    mov edx, 1
    ret

; write_all
;   Input: rdi = fd, rsi = bytes, rdx = length.
;   Output: rax = 0 success or 1 failure.
;   Clobbers: rax, rsi, rdx, rcx, r11.
;   Teaches: EINTR and partial writes require retrying the exact unwritten suffix.
write_all:
    ; Loop invariant: rsi points at the first unwritten byte and rdx counts the
    ; suffix not yet accepted by the kernel.
.write_loop:
    test rdx, rdx
    jz .write_success
    mov rax, SYS_WRITE          ; write(2): rdi=fd, rsi=unwritten suffix, rdx=len.
    syscall                     ; returns progress or a negative errno.
    cmp rax, -EINTR
    je .write_loop
    test rax, rax
    jle .write_failure
    add rsi, rax
    sub rdx, rax
    jmp .write_loop
.write_success:
    xor eax, eax
    ret
.write_failure:
    mov eax, 1
    ret

; write_c_string
;   Input: rdi = fd, rsi = NUL-terminated string.
;   Output: rax = write_all status.
;   Clobbers: rax, rdx, rcx, r11.
;   Teaches: syscall writes require an explicit byte count.
write_c_string:
    xor edx, edx
.length_loop:
    cmp byte [rsi+rdx], 0
    je .known_length
    inc rdx
    jmp .length_loop
.known_length:
    jmp write_all

; operand_diagnostic
;   Input: rsi = fixed prefix, rdx = prefix length; current_name is appended.
;   Output: none; final_status becomes failure.
;   Clobbers: caller-saved registers.
operand_diagnostic:
    call diagnostic_part
    mov rsi, [current_name]
    call diagnostic_string
    call diagnostic_newline
    ; Preserve status 2 because it tells the operand loop to stop after a
    ; stdout failure; an ordinary input/close failure only upgrades success.
    cmp qword [final_status], 0
    jne .status_already_failed
    mov qword [final_status], 1
.status_already_failed:
    ret

; diagnostic helpers perform best-effort stderr writes without recursively
; diagnosing a failure of stderr itself.
diagnostic_part:
    mov rdi, 2
    jmp write_all
diagnostic_string:
    mov rdi, 2
    jmp write_c_string
diagnostic_newline:
    mov rdi, 2
    mov rsi, newline
    mov rdx, 1
    jmp write_all
