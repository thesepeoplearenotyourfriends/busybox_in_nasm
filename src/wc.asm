; wc.asm - selectable, multi-input word/count utility using raw Linux syscalls.
;
; Supported: wc [-l] [-w] [-c] [-m] [-L] [--] [FILE...].  With no selection
; option the line, word, and byte counters are printed.  A literal `-` consumes
; stdin at that point; another `-` continues from its current EOF position.
;
; Encoding policy is deliberately small and locale-independent.  -m decodes
; UTF-8 structure: ASCII and valid leading bytes start a character, continuation
; bytes finish that character, and each malformed byte starts one replacement
; character.  An incomplete final sequence counts as the character begun by its
; lead byte.  -L is the maximum number of input bytes between newline bytes,
; excluding newline and including a final unterminated line.  It is not terminal
; display width.  Words use the six ASCII/POSIX whitespace bytes.
;
; Selected fields print in fixed `l w m c L` order, separated by one space, then
; an optional operand name.  This intentionally omits GNU's alignment padding.
; Counts are unsigned 64-bit; any counter or total overflow is diagnosed rather
; than wrapped. Reads and writes retry EINTR, writes complete partial results,
; and multiple operands aggregate failures. Syscalls: open, read, write, close,
; exit.
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
%define F_LINES 1
%define F_WORDS 2
%define F_BYTES 4
%define F_CHARS 8
%define F_MAX 16
section .rodata
usage_msg: db 'wc: supported options are -l -w -c -m -L and --',10
usage_len: equ $-usage_msg
open_prefix: db 'wc: cannot open '
open_prefix_len: equ $-open_prefix
read_prefix: db 'wc: read failed: '
read_prefix_len: equ $-read_prefix
close_prefix: db 'wc: close failed: '
close_prefix_len: equ $-close_prefix
overflow_prefix: db 'wc: count overflow: '
overflow_prefix_len: equ $-overflow_prefix
write_msg: db 'wc: write failed',10
write_msg_len: equ $-write_msg
stdin_name: db '-',0
empty_name: db 0
total_name: db 'total',0
space: db ' '
newline: db 10
section .bss
buffer: resb BUFFER_SIZE
number_buf: resb 20
selected: resb 1
selection_seen: resb 1
final_status: resb 1
operand_count: resq 1
successful_count: resq 1
current_name: resq 1
cur_lines: resq 1
cur_words: resq 1
cur_bytes: resq 1
cur_chars: resq 1
cur_max: resq 1
cur_line: resq 1
tot_lines: resq 1
tot_words: resq 1
tot_bytes: resq 1
tot_chars: resq 1
tot_max: resq 1
section .text
_start:
 mov r12,[rsp]              ; r12 = argc for the lifetime of the program.
 lea r13,[rsp+8]            ; r13 = argv vector.
 mov r14,1                  ; r14 = next argument index.
 mov byte [selected],F_LINES|F_WORDS|F_BYTES
 mov byte [selection_seen],0
 mov byte [final_status],0
 ; Parse short option clusters. A first selector replaces the default set.
.parse_options:
 cmp r14,r12
 jae .options_done
 mov rbx,[r13+r14*8]
 cmp byte [rbx],'-'
 jne .options_done
 cmp byte [rbx+1],0
 je .options_done
 cmp byte [rbx+1],'-'
 jne .short_cluster
 cmp byte [rbx+2],0
 jne .bad_option
 inc r14
 jmp .options_done
.short_cluster:
 lea rsi,[rbx+1]
.cluster_loop:
 mov al,[rsi]
 test al,al
 jz .cluster_done
 cmp byte [selection_seen],0
 jne .classify
 mov byte [selected],0
 mov byte [selection_seen],1
.classify:
 cmp al,'l'
 je .set_l
 cmp al,'w'
 je .set_w
 cmp al,'c'
 je .set_c
 cmp al,'m'
 je .set_m
 cmp al,'L'
 je .set_L
 jmp .bad_option
.set_l: or byte [selected],F_LINES
 jmp .cluster_next
.set_w: or byte [selected],F_WORDS
 jmp .cluster_next
.set_c: or byte [selected],F_BYTES
 jmp .cluster_next
.set_m: or byte [selected],F_CHARS
 jmp .cluster_next
.set_L: or byte [selected],F_MAX
.cluster_next: inc rsi
 jmp .cluster_loop
.cluster_done: inc r14
 jmp .parse_options
.bad_option:
 mov edi,2
 mov rsi,usage_msg
 mov edx,usage_len
 call write_all
 mov byte [final_status],1
 jmp .exit
.options_done:
 mov rax,r12
 sub rax,r14
 mov [operand_count],rax
 test rax,rax
 jnz .operand_loop
 ; No operands means one unnamed stdin input.
 mov qword [operand_count],1
 mov qword [current_name],empty_name
 xor edi,edi
 call process_fd
 jmp .finish_inputs
.operand_loop:
 ; Loop invariant: all operands below r14 were attempted in argv order.
 cmp r14,r12
 jae .finish_inputs
 mov rbx,[r13+r14*8]        ; rbx = operand name through processing.
 mov [current_name],rbx
 cmp byte [rbx],'-'
 jne .open_file
 cmp byte [rbx+1],0
 jne .open_file
 mov qword [current_name],stdin_name
 xor edi,edi
 call process_fd
 jmp .next_operand
.open_file:
 mov eax,SYS_OPEN           ; open(2): rdi=path, rsi=O_RDONLY, rdx=unused mode.
 mov rdi,rbx
 mov esi,O_RDONLY
 xor edx,edx
 syscall
 test rax,rax
 js .open_failed
 mov r15,rax                ; r15 = opened descriptor until close(2).
 mov rdi,r15
 call process_fd
 mov ebp,eax                ; ebp = processing result across close(2).
 mov eax,SYS_CLOSE          ; close(2): rdi=opened file descriptor.
 mov rdi,r15
 syscall
 test rax,rax
 js .close_failed
 test ebp,ebp
 jnz .next_operand
 jmp .next_operand
.open_failed:
 mov rsi,open_prefix
 mov edx,open_prefix_len
 call operand_error
 jmp .next_operand
.close_failed:
 mov rsi,close_prefix
 mov edx,close_prefix_len
 call operand_error
.next_operand:
 cmp byte [final_status],2  ; stdout failure makes further output impossible.
 je .exit
 inc r14
 jmp .operand_loop
.finish_inputs:
 cmp byte [final_status],2
 je .exit
 cmp qword [operand_count],1
 jbe .exit
 call load_totals
 mov qword [current_name],total_name
 mov rsi,total_name
 call print_counts
 test eax,eax
 jz .exit
 mov byte [final_status],2
.exit:
 movzx edi,byte [final_status]
 test edi,edi
 setnz dil
 movzx edi,dil
 mov eax,SYS_EXIT           ; exit(2): rdi=0 success or 1 aggregate failure.
 syscall
; process_fd
; Input: rdi=readable fd, current_name points to the display name.
; Output: rax=0 success, 1 failure. Updates totals and prints only on success.
; Register roles: r8=input fd, bl=in-word, bh=UTF-8 continuation bytes expected.
process_fd:
 push rbx
 push r12
 mov r8,rdi
 xor ebx,ebx
 mov qword [cur_lines],0
 mov qword [cur_words],0
 mov qword [cur_bytes],0
 mov qword [cur_chars],0
 mov qword [cur_max],0
 mov qword [cur_line],0
.read_loop:
 ; Invariant: counters cover prior chunks; bl and bh carry scanner state.
 mov eax,SYS_READ           ; read(2): rdi=fd, rsi=buffer, rdx=capacity.
 mov rdi,r8
 lea rsi,[buffer]
 mov edx,BUFFER_SIZE
 syscall
 cmp rax,-EINTR
 je .read_loop
 test rax,rax
 js .read_failed
 jz .eof
 add [cur_bytes],rax
 jc .overflow
 mov r12,rax                ; r12 = bytes returned in this chunk.
 xor r10d,r10d              ; r10 = next byte index.
.scan_loop:
 cmp r10,r12
 jae .read_loop
 movzx eax,byte [buffer+r10]
 mov r9b,al                 ; r9b = current byte across line helper calls.
 ; Lines and byte line lengths are independent of text decoding.
 cmp al,10
 jne .ordinary_byte
 call finish_line
 jc .overflow
 jmp .word_test
.ordinary_byte:
 inc qword [cur_line]
 jz .overflow
.word_test:
 mov al,r9b
 push rax
 call is_space
 test eax,eax
 pop rax
 jnz .space_byte
 test bl,bl
 jnz .utf8
 inc qword [cur_words]
 jz .overflow
 mov bl,1
 jmp .utf8
.space_byte:
 xor bl,bl
.utf8:
 call count_utf8_byte
 jc .overflow
 inc r10
 jmp .scan_loop
.eof:
 mov rax,[cur_line]
 cmp rax,[cur_max]
 jbe .totals
 mov [cur_max],rax          ; final unterminated line participates in -L.
.totals:
 call add_totals
 jc .overflow
 inc qword [successful_count]
 mov rsi,[current_name]
 call print_counts
 test eax,eax
 jz .ok
 mov byte [final_status],2
 mov eax,1
 jmp .return
.ok: xor eax,eax
.return:
 pop r12
 pop rbx
 ret
.read_failed:
 mov rsi,read_prefix
 mov edx,read_prefix_len
 call operand_error
 mov eax,1
 jmp .return
.overflow:
 mov rsi,overflow_prefix
 mov edx,overflow_prefix_len
 call operand_error
 mov eax,1
 jmp .return
; finish_line: updates maximum for a newline-terminated line and resets length.
; Output CF=1 on line-count overflow. Clobbers rax.
finish_line:
 mov rax,[cur_line]
 cmp rax,[cur_max]
 jbe .not_longer
 mov [cur_max],rax
.not_longer:
 mov qword [cur_line],0
 inc qword [cur_lines]
 jz .of
 clc
 ret
.of: stc
 ret
; count_utf8_byte: al=byte, bh=expected continuation count.
; Output: bh updated, cur_chars incremented for a new decoding unit; CF overflow.
count_utf8_byte:
 test bh,bh
 jz .new_unit
 mov dl,al
 and dl,0c0h               ; UTF-8 continuation bytes have high bits 10.
 cmp dl,080h
 jne .new_unit             ; malformed byte begins its own replacement unit.
 dec bh
 clc
 ret
.new_unit:
 xor bh,bh
 inc qword [cur_chars]
 jz .cu_overflow
 cmp al,080h
 jb .cu_ok
 cmp al,0c2h
 jb .cu_ok                 ; stray continuation/invalid lead = replacement.
 cmp al,0dfh
 jbe .need_one
 cmp al,0efh
 jbe .need_two
 cmp al,0f4h
 jbe .need_three
 jmp .cu_ok                ; invalid high lead = replacement.
.need_one: mov bh,1
 jmp .cu_ok
.need_two: mov bh,2
 jmp .cu_ok
.need_three: mov bh,3
.cu_ok: clc
 ret
.cu_overflow: stc
 ret
; is_space: al=byte. Output eax=1 for ASCII space or bytes 9..13.
is_space:
 cmp al,' '
 je .yes
 cmp al,9
 jb .no
 cmp al,13
 ja .no
.yes: mov eax,1
 ret
.no: xor eax,eax
 ret
; add_totals sums count fields and takes the maximum line length. CF reports
; wrap. All sums are checked before any store, so a failed input cannot leave a
; partly updated total record.
add_totals:
 mov rax,[cur_lines]
 add rax,[tot_lines]
 jc .at_overflow
 mov r8,[cur_words]
 add r8,[tot_words]
 jc .at_overflow
 mov r9,[cur_bytes]
 add r9,[tot_bytes]
 jc .at_overflow
 mov r10,[cur_chars]
 add r10,[tot_chars]
 jc .at_overflow
 mov [tot_lines],rax
 mov [tot_words],r8
 mov [tot_bytes],r9
 mov [tot_chars],r10
 mov rax,[cur_max]
 cmp rax,[tot_max]
 jbe .at_ok
 mov [tot_max],rax
.at_ok: clc
 ret
.at_overflow: stc
 ret
load_totals:
 mov rax,[tot_lines]
 mov [cur_lines],rax
 mov rax,[tot_words]
 mov [cur_words],rax
 mov rax,[tot_bytes]
 mov [cur_bytes],rax
 mov rax,[tot_chars]
 mov [cur_chars],rax
 mov rax,[tot_max]
 mov [cur_max],rax
 ret
; print_counts: rsi=name (empty omits it). Fixed selected order l,w,m,c,L.
print_counts:
 push r12
 push r13
 mov r12,rsi                ; r12 = name retained through formatting calls.
 xor r13d,r13d              ; r13b = whether a prior field was printed.
 mov al,[selected]
 test al,F_LINES
 jz .pc_words
 mov rdi,[cur_lines]
 call print_field
 jc .pc_fail
.pc_words:
 mov al,[selected]
 test al,F_WORDS
 jz .pc_chars
 mov rdi,[cur_words]
 call print_field
 jc .pc_fail
.pc_chars:
 mov al,[selected]
 test al,F_CHARS
 jz .pc_bytes
 mov rdi,[cur_chars]
 call print_field
 jc .pc_fail
.pc_bytes:
 mov al,[selected]
 test al,F_BYTES
 jz .pc_max
 mov rdi,[cur_bytes]
 call print_field
 jc .pc_fail
.pc_max:
 mov al,[selected]
 test al,F_MAX
 jz .pc_name
 mov rdi,[cur_max]
 call print_field
 jc .pc_fail
.pc_name:
 cmp byte [r12],0
 je .pc_newline
 mov rsi,space
 mov edx,1
 mov edi,1
 call write_all
 test eax,eax
 jnz .pc_fail
 mov rsi,r12
 mov edi,1
 call write_c_string
 test eax,eax
 jnz .pc_fail
.pc_newline:
 mov rsi,newline
 mov edx,1
 mov edi,1
 call write_all
 test eax,eax
 jnz .pc_fail
 pop r13
 pop r12
 xor eax,eax
 ret
.pc_fail:
 mov edi,2
 mov rsi,write_msg
 mov edx,write_msg_len
 call write_all
 pop r13
 pop r12
 mov eax,1
 ret
; print_field: rdi=value, r13b tracks first field. CF reports output failure.
print_field:
 test r13b,r13b
 jz .pf_number
 push rdi
 mov rsi,space
 mov edx,1
 mov edi,1
 call write_all
 pop rdi
 test eax,eax
 jnz .pf_fail
.pf_number:
 call write_uint
 test eax,eax
 jnz .pf_fail
 mov r13b,1
 clc
 ret
.pf_fail: stc
 ret
; write_uint: rdi=u64, stdout decimal. Right-to-left div formatting.
write_uint:
 lea rsi,[number_buf+20]
 mov rax,rdi
 mov r10,10
.wu_loop:
 xor edx,edx                ; div uses RDX:RAX; clear high half for u64/10.
 div r10                    ; quotient in rax, remainder digit in rdx.
 dec rsi
 add dl,'0'
 mov [rsi],dl
 test rax,rax
 jnz .wu_loop
 lea rdx,[number_buf+20]
 sub rdx,rsi
 mov edi,1
 jmp write_all
; operand_error: rsi=prefix, rdx=length. Names current operand, records status 1.
operand_error:
 push rsi
 push rdx
 mov edi,2
 call write_all
 mov rsi,[current_name]
 mov edi,2
 call write_c_string
 mov rsi,newline
 mov edx,1
 mov edi,2
 call write_all
 mov byte [final_status],1
 pop rdx
 pop rsi
 ret
; write_c_string: rdi=fd, rsi=NUL text. Output eax=0/1.
write_c_string:
 xor edx,edx
.wcs_len:
 cmp byte [rsi+rdx],0
 je write_all
 inc rdx
 jmp .wcs_len
; write_all: rdi=fd, rsi=buffer, rdx=count. Retries EINTR and partial writes.
write_all:
 test rdx,rdx
 jz .wa_ok
 mov eax,SYS_WRITE          ; write(2): rdi=fd, rsi=remaining data, rdx=count.
 syscall
 cmp rax,-EINTR
 je write_all
 test rax,rax
 jle .wa_fail
 add rsi,rax
 sub rdx,rax
 jmp write_all
.wa_ok: xor eax,eax
 ret
.wa_fail: mov eax,1
 ret
