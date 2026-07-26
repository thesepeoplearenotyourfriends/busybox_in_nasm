; stat.asm - readable Linux x86-64 file metadata with a stable script form.
;
; Surface: stat [-L] [--stable] [--] FILE... .  The default uses lstat(2), so a
; symbolic link itself is described; -L switches to stat(2) and follows links.
; Default output is labeled and human-readable.  --stable is this project's
; deliberately small interface, not GNU's -c mini-language: one tab-separated
; record per successful operand with fixed labels/order.  The pathname is hex
; encoded so tabs, newlines, and other bytes cannot break record boundaries.
; Times are signed Unix epoch seconds plus exactly nine nanosecond digits; no
; locale or timezone conversion occurs.  Multiple failures are aggregated.
;
; Linux x86-64 struct stat offsets are named below.  This source intentionally
; exposes them rather than hiding the ABI behind a generated definition.
; Syscalls: stat, lstat, write, exit. Writes retry EINTR and partial results.
bits 64
default rel
global _start
%define SYS_WRITE 1
%define SYS_STAT 4
%define SYS_LSTAT 6
%define SYS_EXIT 60
%define EINTR 4
%define STAT_SIZE 144
%define ST_DEV 0
%define ST_INO 8
%define ST_NLINK 16
%define ST_MODE 24
%define ST_UID 28
%define ST_GID 32
%define ST_RDEV 40
%define ST_SIZE 48
%define ST_ATIME 72
%define ST_ATIME_NS 80
%define ST_MTIME 88
%define ST_MTIME_NS 96
%define ST_CTIME 104
%define ST_CTIME_NS 112
%define S_IFMT 0170000o
%define S_IFREG 0100000o
%define S_IFDIR 0040000o
%define S_IFLNK 0120000o
%define S_IFCHR 0020000o
%define S_IFBLK 0060000o
%define S_IFIFO 0010000o
%define S_IFSOCK 0140000o
section .rodata
usage: db 'stat: expected [-L] [--stable] [--] FILE...',10
usage_len: equ $-usage
fail_prefix: db 'stat: cannot stat '
fail_prefix_len: equ $-fail_prefix
write_msg: db 'stat: write failed',10
write_msg_len: equ $-write_msg
file_label: db 'File: ',0
type_label: db 'Type: ',0
mode_label: db 'Mode: ',0
size_label: db 'Size: ',0
inode_label: db 'Inode: ',0
links_label: db 'Links: ',0
uid_label: db 'UID: ',0
gid_label: db 'GID: ',0
dev_label: db 'Device: ',0
rdev_label: db 'Special device: ',0
access_label: db 'Access: ',0
modify_label: db 'Modify: ',0
change_label: db 'Change: ',0
stable_path: db 'path_hex=',0
stable_type: db 9,'type=',0
stable_mode: db 9,'mode=',0
stable_perm: db 9,'perm=',0
stable_size: db 9,'size=',0
stable_inode: db 9,'inode=',0
stable_links: db 9,'links=',0
stable_uid: db 9,'uid=',0
stable_gid: db 9,'gid=',0
stable_dev: db 9,'dev=',0
stable_rdev: db 9,'rdev=',0
stable_atime: db 9,'atime=',0
stable_mtime: db 9,'mtime=',0
stable_ctime: db 9,'ctime=',0
open_paren: db ' (',0
close_paren: db ')',10,0
newline: db 10
blankline: db 10,10
period: db '.'
hex_digits: db '0123456789abcdef'
type_regular: db 'regular',0
type_directory: db 'directory',0
type_symlink: db 'symlink',0
type_char: db 'character-device',0
type_block: db 'block-device',0
type_fifo: db 'fifo',0
type_socket: db 'socket',0
type_unknown: db 'unknown',0
section .bss
stat_buf: resb STAT_SIZE
number_buf: resb 32
perm_buf: resb 11
hex_byte: resb 2
current_path: resq 1
type_ptr: resq 1
follow_links: resb 1
stable_form: resb 1
final_status: resb 1
printed_count: resq 1
section .text
_start:
 mov r12,[rsp]              ; r12=argc and r13=argv remain live across operands.
 lea r13,[rsp+8]
 mov r14,1                  ; r14=next argument index.
 mov byte [follow_links],0
 mov byte [stable_form],0
 mov byte [final_status],0
.parse:
 cmp r14,r12
 jae .missing
 mov rbx,[r13+r14*8]
 cmp byte [rbx],'-'
 jne .operands
 cmp byte [rbx+1],0
 je .operands
 cmp byte [rbx+1],'-'
 jne .short
 cmp byte [rbx+2],0
 je .end_options
 ; Only the exact project long option --stable is accepted.
 cmp byte [rbx+2],'s'
 jne .bad
 mov rdi,rbx
 mov rsi,stable_option
 call strings_equal
 test eax,eax
 jz .bad
 mov byte [stable_form],1
 inc r14
 jmp .parse
.short:
 cmp byte [rbx+1],'L'
 jne .bad
 cmp byte [rbx+2],0
 jne .bad
 mov byte [follow_links],1
 inc r14
 jmp .parse
.end_options: inc r14
 jmp .operands
.bad:
 mov edi,2
 mov rsi,usage
 mov edx,usage_len
 call write_all
 mov byte [final_status],1
 jmp .exit
.missing:
 mov edi,2
 mov rsi,usage
 mov edx,usage_len
 call write_all
 mov byte [final_status],1
 jmp .exit
.operands:
 cmp r14,r12
 jae .missing
.operand_loop:
 ; Invariant: every earlier path was printed or diagnosed; status aggregates.
 cmp r14,r12
 jae .exit
 mov rbx,[r13+r14*8]
 mov [current_path],rbx
 cmp byte [follow_links],0
 jne .do_stat
 mov eax,SYS_LSTAT          ; lstat(2): rdi=path, rsi=writable struct stat.
 jmp .metadata_call
.do_stat:
 mov eax,SYS_STAT           ; stat(2): rdi=path, rsi=writable struct stat.
.metadata_call:
 mov rdi,rbx
 lea rsi,[stat_buf]
 syscall
 test rax,rax
 js .stat_failed
 call choose_type
 call make_permissions
 cmp byte [stable_form],0
 jne .print_stable
 cmp qword [printed_count],0
 je .human
 mov edi,1
 mov rsi,newline
 mov edx,1
 call write_all
 test eax,eax
 jnz .output_failed
.human:
 call print_human
 jmp .printed
.print_stable:
 call print_stable
.printed:
 test eax,eax
 jnz .output_failed
 inc qword [printed_count]
 jmp .next
.stat_failed:
 mov edi,2
 mov rsi,fail_prefix
 mov edx,fail_prefix_len
 call write_all
 mov edi,2
 mov rsi,rbx
 call write_c_string
 mov edi,2
 mov rsi,newline
 mov edx,1
 call write_all
 mov byte [final_status],1
 jmp .next
.output_failed:
 mov edi,2
 mov rsi,write_msg
 mov edx,write_msg_len
 call write_all
 mov byte [final_status],2
 jmp .exit
.next: inc r14
 jmp .operand_loop
.exit:
 movzx edi,byte [final_status]
 test edi,edi
 setnz dil
 movzx edi,dil
 mov eax,SYS_EXIT           ; exit(2): rdi=aggregate zero/one status.
 syscall
section .rodata
stable_option: db '--stable',0
section .text
; choose_type reads st_mode and records a stable lowercase type word.
choose_type:
 mov eax,[stat_buf+ST_MODE]
 and eax,S_IFMT
 mov qword [type_ptr],type_unknown
 cmp eax,S_IFREG
 je .regular
 cmp eax,S_IFDIR
 je .directory
 cmp eax,S_IFLNK
 je .symlink
 cmp eax,S_IFCHR
 je .char
 cmp eax,S_IFBLK
 je .block
 cmp eax,S_IFIFO
 je .fifo
 cmp eax,S_IFSOCK
 je .socket
 ret
.regular: mov qword [type_ptr],type_regular
 ret
.directory: mov qword [type_ptr],type_directory
 ret
.symlink: mov qword [type_ptr],type_symlink
 ret
.char: mov qword [type_ptr],type_char
 ret
.block: mov qword [type_ptr],type_block
 ret
.fifo: mov qword [type_ptr],type_fifo
 ret
.socket: mov qword [type_ptr],type_socket
 ret
; make_permissions constructs the familiar ten-byte type/rwx form plus NUL.
; Special bits replace execute with s/S or t/T exactly as traditional `stat`.
make_permissions:
 push rbx
 mov ebx,[stat_buf+ST_MODE] ; ebx = mode throughout permission construction.
 mov eax,ebx
 mov byte [perm_buf],'?'
 mov edx,eax
 and edx,S_IFMT
 cmp edx,S_IFREG
 jne .mp_dir
 mov byte [perm_buf],'-'
 jmp .bits
.mp_dir: cmp edx,S_IFDIR
 jne .mp_link
 mov byte [perm_buf],'d'
 jmp .bits
.mp_link: cmp edx,S_IFLNK
 jne .mp_char
 mov byte [perm_buf],'l'
 jmp .bits
.mp_char: cmp edx,S_IFCHR
 jne .mp_block
 mov byte [perm_buf],'c'
 jmp .bits
.mp_block: cmp edx,S_IFBLK
 jne .mp_fifo
 mov byte [perm_buf],'b'
 jmp .bits
.mp_fifo: cmp edx,S_IFIFO
 jne .mp_socket
 mov byte [perm_buf],'p'
 jmp .bits
.mp_socket: cmp edx,S_IFSOCK
 jne .bits
 mov byte [perm_buf],'s'
.bits:
 mov ecx,0                 ; ecx=permission position 0..8.
 mov r8d,0400o             ; r8d=ordinary permission mask, shifted right.
 mov r9b,'r'                ; r9b=letter for current position.
.bit_loop:
 cmp ecx,9
 jae .special
 mov byte [perm_buf+rcx+1],'-'
 test ebx,r8d
 jz .bit_next
 mov [perm_buf+rcx+1],r9b
.bit_next:
 shr r8d,1                 ; permission masks descend 0400 through 0001.
 inc ecx
 mov edx,ecx
 mov r10d,edx
 xor edx,edx
 mov eax,r10d
 mov r11d,3
 div r11d                  ; remainder chooses r, w, or x for the next slot.
 cmp edx,0
 je .letter_r
 cmp edx,1
 je .letter_w
 mov r9b,'x'
 jmp .bit_loop
.letter_r: mov r9b,'r'
 jmp .bit_loop
.letter_w: mov r9b,'w'
 jmp .bit_loop
.special:
 test ebx,04000o
 jz .group_special
 cmp byte [perm_buf+3],'x'
 jne .user_upper
 mov byte [perm_buf+3],'s'
 jmp .group_special
.user_upper: mov byte [perm_buf+3],'S'
.group_special:
 test ebx,02000o
 jz .sticky
 cmp byte [perm_buf+6],'x'
 jne .group_upper
 mov byte [perm_buf+6],'s'
 jmp .sticky
.group_upper: mov byte [perm_buf+6],'S'
.sticky:
 test ebx,01000o
 jz .perm_done
 cmp byte [perm_buf+9],'x'
 jne .sticky_upper
 mov byte [perm_buf+9],'t'
 jmp .perm_done
.sticky_upper: mov byte [perm_buf+9],'T'
.perm_done: mov byte [perm_buf+10],0
 pop rbx
 ret
; print_human emits labeled fields. Times are epoch seconds.nanoseconds.
print_human:
 mov rsi,file_label
 mov rdi,[current_path]
 call labeled_string
 test eax,eax
 jnz .ph_ret
 mov rsi,type_label
 mov rdi,[type_ptr]
 call labeled_string
 test eax,eax
 jnz .ph_ret
 mov edi,1
 mov rsi,mode_label
 call write_c_string
 test eax,eax
 jnz .ph_ret
 mov edi,[stat_buf+ST_MODE]
 and edi,07777o
 call write_octal4
 test eax,eax
 jnz .ph_ret
 mov edi,1
 mov rsi,open_paren
 call write_c_string
 test eax,eax
 jnz .ph_ret
 mov edi,1
 mov rsi,perm_buf
 call write_c_string
 test eax,eax
 jnz .ph_ret
 mov edi,1
 mov rsi,close_paren
 call write_c_string
 test eax,eax
 jnz .ph_ret
 mov rsi,size_label
 mov rdi,[stat_buf+ST_SIZE]
 call labeled_u64
 test eax,eax
 jnz .ph_ret
 mov rsi,inode_label
 mov rdi,[stat_buf+ST_INO]
 call labeled_u64
 test eax,eax
 jnz .ph_ret
 mov rsi,links_label
 mov rdi,[stat_buf+ST_NLINK]
 call labeled_u64
 test eax,eax
 jnz .ph_ret
 mov rsi,uid_label
 mov edi,[stat_buf+ST_UID]
 call labeled_u64
 test eax,eax
 jnz .ph_ret
 mov rsi,gid_label
 mov edi,[stat_buf+ST_GID]
 call labeled_u64
 test eax,eax
 jnz .ph_ret
 mov rsi,dev_label
 mov rdi,[stat_buf+ST_DEV]
 call labeled_u64
 test eax,eax
 jnz .ph_ret
 mov rsi,rdev_label
 mov rdi,[stat_buf+ST_RDEV]
 call labeled_u64
 test eax,eax
 jnz .ph_ret
 mov rsi,access_label
 mov rdi,[stat_buf+ST_ATIME]
 mov rdx,[stat_buf+ST_ATIME_NS]
 call labeled_time
 test eax,eax
 jnz .ph_ret
 mov rsi,modify_label
 mov rdi,[stat_buf+ST_MTIME]
 mov rdx,[stat_buf+ST_MTIME_NS]
 call labeled_time
 test eax,eax
 jnz .ph_ret
 mov rsi,change_label
 mov rdi,[stat_buf+ST_CTIME]
 mov rdx,[stat_buf+ST_CTIME_NS]
 call labeled_time
.ph_ret: ret
; print_stable emits the fixed project record documented in the header.
print_stable:
 mov edi,1
 mov rsi,stable_path
 call write_c_string
 test eax,eax
 jnz .ps_ret
 mov rsi,[current_path]
 call write_hex_string
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_type
 mov rdi,[type_ptr]
 call stable_string
 test eax,eax
 jnz .ps_ret
 mov edi,1
 mov rsi,stable_mode
 call write_c_string
 test eax,eax
 jnz .ps_ret
 mov edi,[stat_buf+ST_MODE]
 and edi,07777o
 call write_octal4
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_perm
 mov rdi,perm_buf
 call stable_string
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_size
 mov rdi,[stat_buf+ST_SIZE]
 call stable_u64
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_inode
 mov rdi,[stat_buf+ST_INO]
 call stable_u64
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_links
 mov rdi,[stat_buf+ST_NLINK]
 call stable_u64
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_uid
 mov edi,[stat_buf+ST_UID]
 call stable_u64
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_gid
 mov edi,[stat_buf+ST_GID]
 call stable_u64
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_dev
 mov rdi,[stat_buf+ST_DEV]
 call stable_u64
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_rdev
 mov rdi,[stat_buf+ST_RDEV]
 call stable_u64
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_atime
 mov rdi,[stat_buf+ST_ATIME]
 mov rdx,[stat_buf+ST_ATIME_NS]
 call stable_time
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_mtime
 mov rdi,[stat_buf+ST_MTIME]
 mov rdx,[stat_buf+ST_MTIME_NS]
 call stable_time
 test eax,eax
 jnz .ps_ret
 mov rsi,stable_ctime
 mov rdi,[stat_buf+ST_CTIME]
 mov rdx,[stat_buf+ST_CTIME_NS]
 call stable_time
 test eax,eax
 jnz .ps_ret
 mov edi,1
 mov rsi,newline
 mov edx,1
 call write_all
.ps_ret: ret
; labeled_string: rsi=label, rdi=value string.
labeled_string:
 push rdi
 mov edi,1
 call write_c_string
 pop rsi
 test eax,eax
 jnz .ls_ret
 mov edi,1
 call write_c_string
 test eax,eax
 jnz .ls_ret
 mov edi,1
 mov rsi,newline
 mov edx,1
 call write_all
.ls_ret: ret
; labeled_u64: rsi=label, rdi=value.
labeled_u64:
 push rdi
 mov edi,1
 call write_c_string
 pop rdi
 test eax,eax
 jnz .lu_ret
 call write_u64
 test eax,eax
 jnz .lu_ret
 mov edi,1
 mov rsi,newline
 mov edx,1
 call write_all
.lu_ret: ret
; stable_string/u64 write their label then value without newline.
stable_string:
 push rdi
 mov edi,1
 call write_c_string
 pop rsi
 test eax,eax
 jnz .ss_ret
 mov edi,1
 call write_c_string
.ss_ret: ret
stable_u64:
 push rdi
 mov edi,1
 call write_c_string
 pop rdi
 test eax,eax
 jnz .su_ret
 call write_u64
.su_ret: ret
; labeled_time/stable_time: rsi=label, rdi=signed seconds, rdx=nanoseconds.
labeled_time:
 push rdx
 push rdi
 mov edi,1
 call write_c_string
 pop rdi
 pop rdx
 test eax,eax
 jnz .lt_ret
 call write_time
 test eax,eax
 jnz .lt_ret
 mov edi,1
 mov rsi,newline
 mov edx,1
 call write_all
.lt_ret: ret
stable_time:
 push rdx
 push rdi
 mov edi,1
 call write_c_string
 pop rdi
 pop rdx
 test eax,eax
 jnz .st_ret
 call write_time
.st_ret: ret
; write_time: rdi=signed seconds, rdx=nanoseconds; writes seconds.9digits.
write_time:
 push rdx
 call write_i64
 pop rdi
 test eax,eax
 jnz .wt_ret
 push rdi
 mov edi,1
 mov rsi,period
 mov edx,1
 call write_all
 pop rdi
 test eax,eax
 jnz .wt_ret
 call write_nine_digits
.wt_ret: ret
; write_i64 handles negative epoch seconds without signed division.
write_i64:
 test rdi,rdi
 jns write_u64
 push rdi
 mov edi,1
 mov byte [hex_byte],'-'
 mov rsi,hex_byte
 mov edx,1
 call write_all
 pop rdi
 test eax,eax
 jnz .wi_ret
 neg rdi                    ; two's-complement magnitude also works for INT64_MIN.
 call write_u64
.wi_ret: ret
; write_nine_digits: rdi=0..999999999, writes exactly nine decimal digits.
write_nine_digits:
 lea rsi,[number_buf+9]
 mov rax,rdi
 mov r10,10
 mov ecx,9
.wnd_loop:
 xor edx,edx
 div r10                    ; remainder supplies one right-to-left digit.
 dec rsi
 add dl,'0'
 mov [rsi],dl
 dec ecx
 jnz .wnd_loop
 mov edi,1
 mov edx,9
 jmp write_all
; write_octal4: edi=permission/special bits, always exactly four octal digits.
write_octal4:
 lea rsi,[number_buf+4]
 mov eax,edi
 mov ecx,4
.wo_loop:
 mov edx,eax
 and edx,7                  ; mask the low base-eight digit.
 add dl,'0'
 dec rsi
 mov [rsi],dl
 shr eax,3                  ; discard the digit just formatted.
 dec ecx
 jnz .wo_loop
 mov edi,1
 mov edx,4
 jmp write_all
; write_u64: rdi=value, decimal to stdout using right-to-left division.
write_u64:
 lea rsi,[number_buf+32]
 mov rax,rdi
 mov r10,10
.wu_loop:
 xor edx,edx
 div r10                    ; RDX:RAX / 10 => quotient and remainder digit.
 dec rsi
 add dl,'0'
 mov [rsi],dl
 test rax,rax
 jnz .wu_loop
 lea rdx,[number_buf+32]
 sub rdx,rsi
 mov edi,1
 jmp write_all
; write_hex_string: rsi=NUL pathname, output two lowercase hex digits per byte.
write_hex_string:
 mov r8,rsi                 ; r8 = next pathname byte throughout loop.
.whs_loop:
 movzx eax,byte [r8]
 test al,al
 jz .whs_ok
 mov edx,eax
 shr eax,4                  ; high nibble indexes the first hex digit.
 and edx,15                 ; low nibble indexes the second hex digit.
 mov al,[hex_digits+rax]
 mov [hex_byte],al
 mov dl,[hex_digits+rdx]
 mov [hex_byte+1],dl
 push r8
 mov edi,1
 mov rsi,hex_byte
 mov edx,2
 call write_all
 pop r8
 test eax,eax
 jnz .whs_ret
 inc r8
 jmp .whs_loop
.whs_ok: xor eax,eax
.whs_ret: ret
strings_equal:
 mov al,[rdi]
 cmp al,[rsi]
 jne .se_no
 test al,al
 jz .se_yes
 inc rdi
 inc rsi
 jmp strings_equal
.se_yes: mov eax,1
 ret
.se_no: xor eax,eax
 ret
write_c_string:
 xor edx,edx
.wcs_loop:
 cmp byte [rsi+rdx],0
 je write_all
 inc rdx
 jmp .wcs_loop
write_all:
 test rdx,rdx
 jz .wa_ok
 mov eax,SYS_WRITE          ; write(2): rdi=fd, rsi=remaining bytes, rdx=count.
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
