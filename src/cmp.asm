; cmp.asm - compare two byte streams with parallel buffered reads.
;
; Supported:
;   cmp [-l] [-s] [-n LIMIT] [--] FILE1 [FILE2 [SKIP1 [SKIP2]]]
; FILE2 defaults to standard input, and one operand may be `-`.  -l reports
; every unequal byte in one-based decimal/octal form; -s suppresses all output;
; -n limits the number of bytes compared.  SKIP values and LIMIT are unsigned
; decimal integers from 0 through UINT64_MAX.  If both operands name standard
; input, they identify the same stream and are equal without consuming it.
;
; The ordinary diagnostic names the first unequal one-based character and line.
; Exit status is 0 for equal input, 1 for different input, and 2 for invocation,
; open/read/close/output errors.  Reads and writes retry EINTR; write_all also
; completes partial writes.  Files are streamed through fixed buffers, so file
; size is not limited and binary NUL bytes are ordinary data.
;
; Deliberate small-userland boundary: GNU/BusyBox numeric suffixes, --help, and
; --version are not implemented.  Linux x86-64 syscalls used: open(2), read(2),
; write(2), close(2), and exit(2).

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

section .rodata
usage_msg: db 'cmp: usage: cmp [-l] [-s] [-n LIMIT] FILE1 [FILE2 [SKIP1 [SKIP2]]]',10
usage_len: equ $-usage_msg
invalid_prefix: db 'cmp: invalid number: '
invalid_prefix_len: equ $-invalid_prefix
open_prefix: db 'cmp: cannot open '
open_prefix_len: equ $-open_prefix
read_prefix: db 'cmp: read failed: '
read_prefix_len: equ $-read_prefix
close_prefix: db 'cmp: close failed: '
close_prefix_len: equ $-close_prefix
incompatible_msg: db 'cmp: options -l and -s are incompatible',10
incompatible_len: equ $-incompatible_msg
write_msg: db 'cmp: write failed',10
write_len: equ $-write_msg
differ_infix: db ' differ: char '
differ_infix_len: equ $-differ_infix
line_infix: db ', line '
line_infix_len: equ $-line_infix
eof_prefix: db 'cmp: EOF on '
eof_prefix_len: equ $-eof_prefix
after_infix: db ' after byte '
after_infix_len: equ $-after_infix
space: db ' '
newline: db 10
stdin_name: db '-',0

section .bss
buffer1: resb BUFFER_SIZE
buffer2: resb BUFFER_SIZE
number_buffer: resb 32
fd1: resq 1
fd2: resq 1
name1: resq 1
name2: resq 1
skip1: resq 1
skip2: resq 1
limit: resq 1
limited: resb 1
list_mode: resb 1
silent_mode: resb 1
opened1: resb 1
opened2: resb 1
len1: resq 1
len2: resq 1
pos1: resq 1
pos2: resq 1
byte_number: resq 1
line_number: resq 1
last_was_newline: resb 1
different: resb 1
final_status: resb 1

section .text
_start:
    mov r12, [rsp]              ; r12 = argc for the lifetime of the program.
    lea r13, [rsp+8]            ; r13 = argv vector for the lifetime of the program.
    mov r14, 1                  ; r14 = index of the next argument to parse.
    mov qword [limit], -1

    ; Option-loop invariant: argv[1..r14-1] has been completely consumed.
.parse_options:
    cmp r14, r12
    jae .options_done
    mov rbx, [r13+r14*8]        ; rbx = current option or first operand.
    cmp byte [rbx], '-'
    jne .options_done
    cmp byte [rbx+1], 0         ; A lone '-' is an input operand.
    je .options_done
    cmp byte [rbx+1], '-'
    jne .short_options
    cmp byte [rbx+2], 0
    jne .usage
    inc r14
    jmp .options_done
.short_options:
    lea r15, [rbx+1]            ; r15 = next byte in this short-option cluster.
.short_loop:
    mov al, [r15]
    test al, al
    jz .short_done
    cmp al, 'l'
    je .set_list
    cmp al, 's'
    je .set_silent
    cmp al, 'n'
    jne .usage
    cmp byte [r15+1], 0         ; Keep `-n LIMIT` visually and mechanically plain.
    jne .usage
    inc r14
    cmp r14, r12
    jae .usage
    mov rdi, [r13+r14*8]
    call parse_number
    test rdx, rdx
    jnz .invalid_number
    mov [limit], rax
    mov byte [limited], 1
    jmp .short_done
.set_list:
    mov byte [list_mode], 1
    inc r15
    jmp .short_loop
.set_silent:
    mov byte [silent_mode], 1
    inc r15
    jmp .short_loop
.short_done:
    inc r14
    jmp .parse_options

.options_done:
    cmp byte [list_mode], 0
    je .options_compatible
    cmp byte [silent_mode], 0
    jne .incompatible_options
.options_compatible:
    mov rax, r12
    sub rax, r14                ; one through four positional operands are valid.
    cmp rax, 1
    jb .usage
    cmp rax, 4
    ja .usage
    mov rax, [r13+r14*8]
    mov [name1], rax
    inc r14
    cmp r14, r12
    jae .default_second
    mov rax, [r13+r14*8]
    mov [name2], rax
    inc r14
    jmp .parse_skips
.default_second:
    mov qword [name2], stdin_name
.parse_skips:
    cmp r14, r12
    jae .open_inputs
    mov rdi, [r13+r14*8]
    call parse_number
    test rdx, rdx
    jnz .invalid_number
    mov [skip1], rax
    inc r14
    cmp r14, r12
    jae .open_inputs
    mov rdi, [r13+r14*8]
    call parse_number
    test rdx, rdx
    jnz .invalid_number
    mov [skip2], rax

.open_inputs:
    mov rdi, [name1]
    call is_dash
    mov r8b, al                 ; r8b = whether FILE1 is standard input.
    mov rdi, [name2]
    call is_dash
    test r8b, r8b
    jz .open_first
    test al, al
    jz .open_first
.same_stdin:
    xor edi, edi                ; Both names share fd 0, so no bytes need consuming.
    jmp .exit
.open_first:
    mov rdi, [name1]
    call open_input
    test rdx, rdx
    js .open_first_failed
    mov [fd1], rax
    mov [opened1], dl           ; open_input returns opened flag in dl on success.
    mov rdi, [name2]
    call open_input
    test rdx, rdx
    js .open_second_failed
    mov [fd2], rax
    mov [opened2], dl

    mov rdi, [fd1]
    mov rsi, [skip1]
    mov rdx, [name1]
    call discard_bytes
    test eax, eax
    jnz .comparison_done
    mov rdi, [fd2]
    mov rsi, [skip2]
    mov rdx, [name2]
    call discard_bytes
    test eax, eax
    jnz .comparison_done

    mov qword [byte_number], 1
    mov qword [line_number], 1
    call compare_streams
.comparison_done:
    call close_inputs
    movzx edi, byte [final_status]
    test dil, dil
    jnz .exit
    movzx edi, byte [different]
.exit:
    mov rax, SYS_EXIT           ; exit(2): rdi=0 equal, 1 different, or 2 trouble.
    syscall                     ; successful exit does not return.

.open_first_failed:
    mov rsi, open_prefix
    mov rdx, open_prefix_len
    mov rcx, [name1]
    call named_error
    jmp .trouble_exit
.open_second_failed:
    mov rsi, open_prefix
    mov rdx, open_prefix_len
    mov rcx, [name2]
    call named_error
    call close_inputs
    jmp .trouble_exit
.incompatible_options:
    mov rdi, 2
    mov rsi, incompatible_msg
    mov rdx, incompatible_len
    call write_all                ; Invocation errors are not comparison silence.
    jmp .trouble_exit
.usage:
    mov rsi, usage_msg
    mov rdx, usage_len
    call diagnostic_part
    jmp .trouble_exit
.invalid_number:
    mov rcx, rdi
    mov rsi, invalid_prefix
    mov rdx, invalid_prefix_len
    call named_error
.trouble_exit:
    mov edi, 2
    jmp .exit

; compare_streams
;   Input: fd/name globals and initialized byte_number/line_number.
;   Output: different/final_status globals; no return value.
;   Clobbers: all caller-saved registers.
;   Teaches: independent buffer cursors let partial reads make progress without
;   assuming that two read(2) calls return equally sized chunks.
compare_streams:
    ; Loop invariant: every byte before byte_number has been compared, and each
    ; buffer cursor points to its first byte not yet compared.
.compare_loop:
    cmp byte [limited], 0
    je .need_data
    cmp qword [limit], 0
    je .equal_prefix
.need_data:
    mov rax, [pos1]
    cmp rax, [len1]
    jb .buffer1_ready
    mov rdi, [fd1]
    mov rsi, buffer1
    mov rdx, [name1]
    call refill
    test rax, rax
    js .read_trouble
    mov [len1], rax
    mov qword [pos1], 0
.buffer1_ready:
    mov rax, [pos2]
    cmp rax, [len2]
    jb .buffer2_ready
    mov rdi, [fd2]
    mov rsi, buffer2
    mov rdx, [name2]
    call refill
    test rax, rax
    js .read_trouble
    mov [len2], rax
    mov qword [pos2], 0
.buffer2_ready:
    mov rax, [len1]
    sub rax, [pos1]             ; rax = bytes currently available from FILE1.
    mov rcx, [len2]
    sub rcx, [pos2]             ; rcx = bytes currently available from FILE2.
    test rax, rax
    jz .first_eof
    test rcx, rcx
    jz .second_eof
    cmp rax, rcx
    cmova rax, rcx              ; rax = comparable bytes in both buffers.
    cmp byte [limited], 0
    je .chunk_ready
    cmp rax, [limit]
    cmova rax, [limit]
.chunk_ready:
    mov r8, rax                 ; r8 = bytes left in this parallel chunk.
    mov r9, [pos1]              ; r9 = FILE1 cursor.
    mov r10, [pos2]             ; r10 = FILE2 cursor.
    ; Chunk-loop invariant: r9/r10 address the same logical byte_number, and r8
    ; counts the paired bytes that can be examined without another syscall.
.byte_loop:
    mov al, [buffer1+r9]
    mov dl, [buffer2+r10]
    cmp al, dl
    je .same_byte
    mov byte [different], 1
    cmp byte [silent_mode], 0
    jne .different_silent
    cmp byte [list_mode], 0
    jne .list_difference
    call report_first_difference
    ret
.list_difference:
    movzx edi, al
    movzx esi, dl
    push r8                    ; reporting uses caller-saved registers, while
    push r9                    ; these three values are the comparison cursors.
    push r10
    call report_list_difference
    pop r10
    pop r9
    pop r8
    cmp byte [final_status], 0
    jne .save_and_return
.different_silent:
.same_byte:
    cmp al, 10
    jne .advance_non_newline
    mov byte [last_was_newline], 1
    inc qword [line_number]
    jmp .advance
.advance_non_newline:
    mov byte [last_was_newline], 0
.advance:
    inc qword [byte_number]
    inc r9
    inc r10
    dec r8
    cmp byte [limited], 0
    je .chunk_limit_checked
    dec qword [limit]
    jz .save_and_continue
.chunk_limit_checked:
    test r8, r8
    jnz .byte_loop
.save_and_continue:
    mov [pos1], r9
    mov [pos2], r10
    jmp .compare_loop
.save_and_return:
    mov [pos1], r9
    mov [pos2], r10
    ret
.first_eof:
    test rcx, rcx
    jz .equal_prefix
    mov rcx, [name1]
    jmp .unequal_eof
.second_eof:
    mov rcx, [name2]
.unequal_eof:
    mov byte [different], 1
    cmp byte [silent_mode], 0
    jne .equal_prefix
    push rcx                    ; stderr writes may clobber rcx via syscall.
    mov rsi, eof_prefix
    mov rdx, eof_prefix_len
    call diagnostic_part
    pop rsi
    call diagnostic_string
    mov rsi, after_infix
    mov rdx, after_infix_len
    call diagnostic_part
    mov rax, [byte_number]
    dec rax
    call diagnostic_unsigned
    cmp byte [list_mode], 0     ; GNU/POSIX list mode omits the EOF line number.
    jne .eof_newline
    mov rsi, line_infix
    mov rdx, line_infix_len
    call diagnostic_part
    mov rax, [line_number]
    cmp byte [last_was_newline], 0
    je .eof_line_ready
    dec rax                     ; EOF after newline belongs to the line just ended.
.eof_line_ready:
    call diagnostic_unsigned
.eof_newline:
    call diagnostic_newline
.equal_prefix:
    ret
.read_trouble:
    mov byte [final_status], 2
    ret

; refill
;   Input: rdi = fd, rsi = buffer, rdx = display name.
;   Output: rax = byte count/EOF, or -1 after a diagnosed read error.
;   Clobbers: rax, rdi, rsi, rdx, rcx, r11.
;   Teaches: EINTR means the operation did not complete and may be retried.
refill:
    mov r8, rdx                 ; r8 = display name preserved across read(2).
.retry:
    mov rax, SYS_READ           ; read(2): rdi=input fd, rsi=buffer, rdx=capacity.
    mov rdx, BUFFER_SIZE
    syscall                     ; returns bytes, zero at EOF, or negative errno.
    cmp rax, -EINTR
    je .retry
    test rax, rax
    jns .done
    mov rcx, r8
    mov rsi, read_prefix
    mov rdx, read_prefix_len
    call named_error
    mov rax, -1
.done:
    ret

; discard_bytes
;   Input: rdi = fd, rsi = bytes to discard, rdx = display name.
;   Output: eax = 0 success (EOF is allowed) or 1 read failure.
;   Clobbers: caller-saved registers.
;   Teaches: skips must work on pipes, where lseek(2) is unavailable.
discard_bytes:
    mov r8, rdi                 ; r8 = input fd while skipping.
    mov r9, rsi                 ; r9 = bytes still to discard.
    mov r10, rdx                ; r10 = display name.
.discard_loop:
    test r9, r9
    jz .success
    mov rdx, BUFFER_SIZE
    cmp r9, rdx
    cmovb rdx, r9
.retry_read:
    mov rax, SYS_READ           ; read(2): rdi=fd, rsi=scratch buffer, rdx=count.
    mov rdi, r8
    mov rsi, buffer1
    syscall                     ; EOF before SKIP is valid and leaves no data.
    cmp rax, -EINTR
    je .retry_read
    test rax, rax
    js .failure
    jz .success
    sub r9, rax
    jmp .discard_loop
.failure:
    mov rcx, r10
    mov rsi, read_prefix
    mov rdx, read_prefix_len
    call named_error
    mov byte [final_status], 2
    mov eax, 1
    ret
.success:
    xor eax, eax
    ret

; open_input
;   Input: rdi = pathname or `-`.
;   Output: rax = fd; rdx = 0 stdin, 1 opened file, or -1 failure.
;   Clobbers: rax, rdi, rsi, rdx, rcx, r11.
open_input:
    call is_dash
    test al, al
    jz .open_path
    xor eax, eax
    xor edx, edx
    ret
.open_path:
    mov rax, SYS_OPEN           ; open(2): rdi=path, rsi=O_RDONLY, rdx=mode unused.
    xor esi, esi
    xor edx, edx
    syscall                     ; returns fd or negative errno.
    test rax, rax
    js .failed
    mov edx, 1
    ret
.failed:
    mov rdx, -1
    ret

; close_inputs closes only descriptors opened by this process.  A close error
; becomes status 2, but both descriptors are attempted independently.
close_inputs:
    cmp byte [opened1], 0
    je .second
    mov rdi, [fd1]
    mov rcx, [name1]
    call close_one
.second:
    cmp byte [opened2], 0
    je .done
    mov rdi, [fd2]
    mov rcx, [name2]
    call close_one
.done:
    ret

; close_one
;   Input: rdi = owned fd, rcx = display name.
;   Output: final_status becomes 2 on failure.
;   Clobbers: caller-saved registers.
close_one:
    mov r8, rcx
.retry:
    mov rax, SYS_CLOSE          ; close(2): rdi=owned input descriptor.
    syscall                     ; Linux may report EINTR; retry for project policy.
    cmp rax, -EINTR
    je .retry
    test rax, rax
    jns .done
    mov rcx, r8
    mov rsi, close_prefix
    mov rdx, close_prefix_len
    call named_error
    mov byte [final_status], 2
.done:
    ret

; report_first_difference emits the conventional default record.
report_first_difference:
    mov rdi, 1
    mov rsi, [name1]
    call write_c_string
    mov rdi, 1
    mov rsi, space
    mov rdx, 1
    call write_checked
    mov rdi, 1
    mov rsi, [name2]
    call write_c_string
    mov rdi, 1
    mov rsi, differ_infix
    mov rdx, differ_infix_len
    call write_checked
    mov rax, [byte_number]
    call output_unsigned
    mov rdi, 1
    mov rsi, line_infix
    mov rdx, line_infix_len
    call write_checked
    mov rax, [line_number]
    call output_unsigned
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1
    jmp write_checked

; report_list_difference
;   Input: edi = FILE1 byte, esi = FILE2 byte.
;   Output: one `byte-number octal octal` record; output failure is global.
;   Clobbers: caller-saved registers.
report_list_difference:
    push rsi                     ; preserve both byte values across write syscalls.
    push rdi
    mov rax, [byte_number]
    call output_unsigned
    mov rdi, 1
    mov rsi, space
    mov rdx, 1
    call write_checked
    pop rax
    call output_octal
    mov rdi, 1
    mov rsi, space
    mov rdx, 1
    call write_checked
    pop rax
    call output_octal
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1
    jmp write_checked

; parse_number parses a full unsigned decimal string with overflow checking.
; Input rdi=string. Output rax=value, rdx=0 success/1 invalid. Clobbers rcx,r8.
parse_number:
    xor eax, eax
    xor ecx, ecx
    cmp byte [rdi], 0
    je .invalid
    mov r8, 1844674407370955161
.loop:
    movzx edx, byte [rdi+rcx]
    test dl, dl
    jz .valid
    sub edx, '0'
    cmp edx, 9
    ja .invalid
    cmp rax, r8
    ja .invalid
    jb .safe
    cmp edx, 5
    ja .invalid
.safe:
    imul rax, rax, 10           ; Shift the decimal value left by one digit.
    add rax, rdx
    inc rcx
    jmp .loop
.valid:
    xor edx, edx
    ret
.invalid:
    mov edx, 1
    ret

; output_unsigned/output_octal format right-to-left because division yields the
; least-significant digit first. Input rax=value; output goes to stdout.
output_unsigned:
    mov ecx, 10
    jmp format_number
output_octal:
    ; cmp conventionally gives each octal byte a three-column field.  Leading
    ; columns are spaces, not zeroes, so low byte values remain easy to scan.
    lea rsi, [number_buffer+29]
    mov byte [rsi], ' '
    mov byte [rsi+1], ' '
    mov byte [rsi+2], ' '
    mov ecx, 8
    mov r8d, 3
    lea r9, [rsi+3]
.octal_digits:
    xor edx, edx
    div rcx                     ; base-eight remainder produces one octal digit.
    add dl, '0'
    dec r9
    mov [r9], dl
    test rax, rax
    jnz .octal_digits
    mov rdi, 1
    mov rdx, r8
    jmp write_checked
format_number:
    lea rsi, [number_buffer+32]
    xor r8d, r8d
.digits:
    xor edx, edx                ; div uses RDX:RAX; clear the high dividend half.
    div rcx                     ; quotient stays in rax, remainder is next digit.
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc r8
    test rax, rax
    jnz .digits
    mov rdi, 1
    mov rdx, r8
    jmp write_checked

diagnostic_unsigned:
    mov ecx, 10
    lea rsi, [number_buffer+32]
    xor r8d, r8d
.digits:
    xor edx, edx
    div rcx                     ; right-to-left decimal conversion, as above.
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc r8
    test rax, rax
    jnz .digits
    mov rdi, 2
    mov rdx, r8
    jmp write_all

; write_checked promotes any stdout failure to trouble and reports it once.
write_checked:
    call write_all
    test eax, eax
    jz .done
    cmp byte [final_status], 2
    je .done
    mov byte [final_status], 2
    mov rsi, write_msg
    mov rdx, write_len
    call diagnostic_part
.done:
    ret

; write_all
;   Input: rdi=fd, rsi=first byte, rdx=length.
;   Output: eax=0 success or 1 failure. Clobbers rax,rsi,rdx,rcx,r11.
;   Teaches: a short write advances only through the accepted prefix.
write_all:
.loop:
    test rdx, rdx
    jz .success
    mov rax, SYS_WRITE          ; write(2): rdi=fd, rsi=unwritten bytes, rdx=count.
    syscall                     ; returns progress or negative errno.
    cmp rax, -EINTR
    je .loop
    test rax, rax
    jle .failure
    add rsi, rax
    sub rdx, rax
    jmp .loop
.success:
    xor eax, eax
    ret
.failure:
    mov eax, 1
    ret

write_c_string:
    xor edx, edx
.length:
    cmp byte [rsi+rdx], 0
    je write_checked
    inc rdx
    jmp .length

named_error:
    cmp byte [silent_mode], 0
    jne .done
    push rcx                     ; write(2) destroys rcx, so preserve the name.
    call diagnostic_part
    pop rsi
    call diagnostic_string
    call diagnostic_newline
.done:
    ret
diagnostic_part:
    cmp byte [silent_mode], 0
    jne .silent
    mov rdi, 2
    jmp write_all
.silent:
    xor eax, eax
    ret
diagnostic_string:
    mov rdi, 2
    xor edx, edx
.length:
    cmp byte [rsi+rdx], 0
    je write_all
    inc rdx
    jmp .length
diagnostic_newline:
    mov rdi, 2
    mov rsi, newline
    mov rdx, 1
    jmp write_all

is_dash:
    xor eax, eax
    cmp byte [rdi], '-'
    jne .done
    cmp byte [rdi+1], 0
    jne .done
    mov al, 1
.done:
    ret
