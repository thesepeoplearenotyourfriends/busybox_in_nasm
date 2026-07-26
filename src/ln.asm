; ln.asm - small field-usable hard/symbolic link utility.
; Surface: ln [-s] [-f] [--] TARGET LINK_NAME; ln ... TARGET... DIRECTORY.
; A directory operand is followed (including a symlink to a directory, as stat(2)
; does) and each destination is DIRECTORY/basename(TARGET).  -f unlinks only after
; link creation reports EEXIST, and refuses source/destination identity for hard
; links.  Unsupported: -n, -T, -i, backups, relative-link rewriting.
; Raw syscalls: stat, link, symlink, unlink, write, exit. Status is aggregate 0/1.
bits 64
default rel
global _start
%define SYS_WRITE 1
%define SYS_STAT 4
%define SYS_LINK 86
%define SYS_UNLINK 87
%define SYS_SYMLINK 88
%define SYS_EXIT 60
%define EINTR 4
%define EEXIST 17
%define S_IFMT 0170000o
%define S_IFDIR 0040000o
%define PATH_MAX 4096
%define ST_INO 8
%define ST_DEV 0
%define ST_MODE 24
section .rodata
usage: db 'ln: expected TARGET LINK_NAME or TARGET... DIRECTORY',10,0
badopt: db 'ln: unsupported option: ',0
faila: db 'ln: cannot link ',0
arrow: db ' -> ',0
same: db 'ln: refusing to force a hard link onto its source: ',0
nl: db 10
section .bss
st_dest: resb 144
st_src: resb 144
path: resb PATH_MAX
status: resb 1
dirform: resb 1
section .text
_start:
 mov r12,[rsp]              ; r12 = argc for the whole program.
 lea r13,[rsp+8]            ; r13 = argv vector.
 mov r14,1                  ; r14 = parser/current source index.
 xor ebx,ebx                ; bl = symbolic option, bh = force option.
 mov byte [dirform],0
.parse:
 cmp r14,r12
 jae .usage
 mov rsi,[r13+r14*8]
 cmp byte [rsi],'-'
 jne .parsed
 cmp byte [rsi+1],0
 je .parsed
 cmp byte [rsi+1],'-'
 jne .short
 cmp byte [rsi+2],0
 jne .bad
 inc r14
 jmp .parsed
.short:
 inc rsi
.short_loop:                ; Every byte in a short option cluster is consumed.
 mov al,[rsi]
 test al,al
 jz .short_done
 cmp al,'s'
 je .set_s
 cmp al,'f'
 je .set_f
 jmp .bad
.set_s: mov bl,1
 inc rsi
 jmp .short_loop
.set_f: mov bh,1
 inc rsi
 jmp .short_loop
.short_done:
 inc r14
 jmp .parse
.bad:
 mov rsi,badopt
 call errstr
 mov rsi,[r13+r14*8]
 call errline
 jmp .exit1
.parsed:
 mov rax,r12
 sub rax,r14
 cmp rax,2
 jb .usage
 mov r15,r12
 dec r15                   ; r15 = final operand index.
 ; stat(2) follows a final symlink, deliberately making it a directory operand.
 mov eax,SYS_STAT
 mov rdi,[r13+r15*8]
 lea rsi,[st_dest]
 syscall
 test rax,rax
 js .two_operand
 mov eax,[st_dest+ST_MODE]
 and eax,S_IFMT
 cmp eax,S_IFDIR
 jne .two_operand
 lea rbp,[r15-1]            ; rbp marks directory-form final source index.
 mov byte [dirform],1
 jmp .sources
.two_operand:
 mov rax,r15
 sub rax,r14
 cmp rax,1
 jne .usage
 mov rbp,r14
.sources:
 mov byte [status],0         ; aggregate status survives syscall's r11 clobber.
.source_loop:
 cmp r14,rbp
 ja .done
 mov r8,[r13+r14*8]         ; r8 = source/target string.
 cmp byte [dirform],0
 jne .join
 mov r9,[r13+r15*8]         ; r9 = direct destination.
 jmp .attempt
.join:
 mov rdi,[r13+r15*8]
 mov rsi,r8
 call join_basename
 test rax,rax
 jnz .failed_pair
 lea r9,[path]
.attempt:
 ; First attempt is non-destructive. Only EEXIST can lead to unlink under -f.
 call make_link
 test rax,rax
 jns .next
 cmp rax,-EEXIST
 jne .failed_pair
 test bh,bh
 jz .failed_pair
 test bl,bl
 jnz .remove
 ; For hard links compare device+inode before unlinking: this prevents `ln -f a a`.
 mov eax,SYS_STAT
 mov rdi,r8
 lea rsi,[st_src]
 syscall
 test rax,rax
 js .failed_pair
 mov eax,SYS_STAT
 mov rdi,r9
 lea rsi,[st_dest]
 syscall
 test rax,rax
 js .failed_pair
 mov rax,[st_src+ST_DEV]
 cmp rax,[st_dest+ST_DEV]
 jne .remove
 mov rax,[st_src+ST_INO]
 cmp rax,[st_dest+ST_INO]
 jne .remove
 mov rsi,same
 call errstr
 mov rsi,r8
 call errline
 mov byte [status],1
 jmp .next
.remove:
 mov eax,SYS_UNLINK         ; unlink(2): rdi = existing destination pathname.
 mov rdi,r9
 syscall
 test rax,rax
 js .failed_pair
 call make_link
 test rax,rax
 jns .next
.failed_pair:
 mov rsi,faila
 call errstr
 mov rsi,r8
 call errstr
 mov rsi,arrow
 call errstr
 mov rsi,r9
 call errline
 mov byte [status],1
.next:
 inc r14
 jmp .source_loop
.done:
 mov eax,SYS_EXIT           ; exit(2): rdi = aggregate status.
 movzx edi,byte [status]
 syscall
.usage:
 mov rsi,usage
 call errstr
.exit1:
 mov eax,SYS_EXIT
 mov edi,1
 syscall
; make_link: r8=target, r9=destination, bl selects symlink. Returns kernel result.
make_link:
 test bl,bl
 jnz .sym
 mov eax,SYS_LINK           ; link(2): rdi = existing source, rsi = new name.
 jmp .go
.sym: mov eax,SYS_SYMLINK   ; symlink(2): rdi = stored target text, rsi = new name.
.go: mov rdi,r8
 mov rsi,r9
 syscall
 ret
; join_basename: rdi=directory, rsi=target. Output path[], rax=0 or 1 on overflow.
join_basename:
 lea rdx,[path]
 xor ecx,ecx
.jdir:                      ; Copy directory while reserving slash, basename, NUL.
 cmp rcx,PATH_MAX-1
 jae .overflow
 mov al,[rdi+rcx]
 mov [rdx+rcx],al
 test al,al
 jz .dir_end
 inc rcx
 jmp .jdir
.dir_end:
 test rcx,rcx
 jz .slash
 cmp byte [rdx+rcx-1],'/'; avoid manufacturing a doubled separator.
 je .base_find
.slash:
 cmp rcx,PATH_MAX-1
 jae .overflow
 mov byte [rdx+rcx],'/'
 inc rcx
.base_find:
 mov rax,rsi
 mov r10,rsi
.find_end:
 mov dil,[rax]
 test dil,dil
 jz .copy_base
 cmp dil,'/'
 jne .fe_next
 lea r10,[rax+1]
.fe_next: inc rax
 jmp .find_end
.copy_base:                 ; Basename is text after the last slash.
 mov al,[r10]
 cmp rcx,PATH_MAX-1
 jae .overflow
 mov [rdx+rcx],al
 inc r10
 inc rcx
 test al,al
 jnz .copy_base
 xor eax,eax
 ret
.overflow: mov eax,1
 ret
errline:
 call errstr
 lea rsi,[nl]
 mov edx,1
 mov edi,2
 jmp write_all
errstr:
 mov edi,2
 xor edx,edx
.len: cmp byte [rsi+rdx],0
 je write_all
 inc rdx
 jmp .len
; write_all retries EINTR and advances after partial writes.
write_all:
 test rdx,rdx
 jz .ok
 mov eax,SYS_WRITE          ; write(2): rdi=fd, rsi=remaining bytes, rdx=count.
 syscall
 cmp rax,-EINTR
 je write_all
 test rax,rax
 jle .badw
 add rsi,rax
 sub rdx,rax
 jmp write_all
.ok: xor eax,eax
 ret
.badw: mov eax,1
 ret
