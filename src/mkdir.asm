; mkdir.asm - small field-usable directory creator.
; Surface: mkdir [-p] [-m MODE] [--] DIRECTORY... . MODE is exactly 1-4 octal
; digits (0000..7777). The final directory is chmod(2)'d after creation so -m is
; exact despite umask, but only for a final directory this invocation creates.
; Under -p, existing directories keep their modes.  Parents use 0777 before
; umask while preserving owner write/search so a restrictive mask cannot strand
; the component walk.
; Paths are copied to a 4096-byte buffer and overflow fails explicitly.
; Syscalls: mkdir, chmod, stat, write, exit. Every operand is attempted.
bits 64
default rel
global _start
%define SYS_WRITE 1
%define SYS_STAT 4
%define SYS_CHMOD 90
%define SYS_UMASK 95
%define SYS_MKDIR 83
%define SYS_EXIT 60
%define EINTR 4
%define EEXIST 17
%define S_IFMT 0170000o
%define S_IFDIR 0040000o
%define PATH_MAX 4096
section .rodata
missing: db 'mkdir: missing operand',10,0
badopt: db 'mkdir: unsupported option: ',0
badmode: db 'mkdir: invalid mode: ',0
fail: db 'mkdir: cannot create directory ',0
nl: db 10
section .bss
path: resb PATH_MAX
st: resb 144
status: resb 1
section .text
_start:
 mov r12,[rsp]              ; r12 = argc; r13 = argv for entire parser.
 lea r13,[rsp+8]
 mov r14,1                  ; r14 = next argv index.
 xor ebx,ebx                ; bl = -p; bh = explicit -m was supplied.
 mov ebp,0777o              ; ebp = requested final mode.
.parse:
 cmp r14,r12
 jae .missing
 mov rsi,[r13+r14*8]
 cmp byte [rsi],'-'
 jne .operands
 cmp byte [rsi+1],0
 je .operands
 cmp byte [rsi+1],'-'
 jne .short
 cmp byte [rsi+2],0
 jne .bad_option
 inc r14
 jmp .operands
.short:
 cmp byte [rsi+1],'p'
 jne .maybe_m
 cmp byte [rsi+2],0
 jne .bad_option
 mov bl,1
 inc r14
 jmp .parse
.maybe_m:
 cmp byte [rsi+1],'m'
 jne .bad_option
 cmp byte [rsi+2],0
 jne .attached_mode
 inc r14
 cmp r14,r12
 jae .mode_missing
 mov rsi,[r13+r14*8]
 jmp .parse_mode
.attached_mode: lea rsi,[rsi+2]
.parse_mode:
 call octal_mode
 test rax,rax
 js .invalid_mode
 mov ebp,eax
 mov bh,1
 inc r14
 jmp .parse
.bad_option:
 mov rsi,badopt
 call errstr
 mov rsi,[r13+r14*8]
 call errline
 jmp .exit1
.mode_missing: lea rsi,[empty]
.invalid_mode:
 push rsi
 mov rsi,badmode
 call errstr
 pop rsi
 call errline
 jmp .exit1
.operands:
 cmp r14,r12
 jae .missing
 mov byte [status],0
.loop:                      ; Invariant: all earlier operands were attempted.
 cmp r14,r12
 jae .exit
 mov rdi,[r13+r14*8]
 test bl,bl
 jz .plain
 call mkdir_parents
 jmp .result
.plain:
 mov eax,SYS_MKDIR          ; mkdir(2): rdi=operand, rsi=mode before umask.
 mov esi,ebp
 syscall
 test rax,rax
 js .failed
 test bh,bh
 jz .next
 mov eax,SYS_CHMOD          ; chmod(2): rdi=new final directory, rsi=exact mode.
 mov rdi,[r13+r14*8]
 mov esi,ebp
 syscall
.result: test rax,rax
 jns .next
.failed:
 mov byte [status],1
 mov rsi,fail
 call errstr
 mov rsi,[r13+r14*8]
 call errline
.next: inc r14
 jmp .loop
.missing:
 mov rsi,missing
 call errstr
.exit1: mov byte [status],1
.exit:
 mov eax,SYS_EXIT           ; exit(2): rdi=aggregate status.
 movzx edi,byte [status]
 syscall
; mkdir_parents: rdi=operand; uses bl=-p, bh=-m and ebp=final mode.
; Copies one byte at a time. At each slash it temporarily inserts NUL, creates
; the prefix, verifies EEXIST is a directory, then restores the slash.
mkdir_parents:
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi               ; r12 = source path; r13 = copied length.
    xor r13d,r13d
    xor r14d,r14d             ; r14 = 1 while the parent-specific umask is active.
.copy:
 cmp r13,PATH_MAX-1
 jae .mp_fail
 mov al,[r12+r13]
 mov [path+r13],al
 inc r13
 test al,al
 jnz .copy
 ; Skip repeated separators and dot components naturally: empty prefixes and
 ; prefixes ending '/.' are not sent to mkdir.
    lea rcx,[path]
    mov rdx,rcx

    ; GNU mkdir's intermediate-parent policy is `=rwx,u+wx`: the caller's
    ; umask filters ordinary bits, but may not remove owner write/search and
    ; strand mkdir inside a parent it just created.  umask(2) returns the old
    ; mask, so temporarily clear those two mask bits while walking parents.
    mov eax,SYS_UMASK          ; umask(2): rdi = temporary mask 0; returns old mask.
    xor edi,edi
    syscall
    mov r15,rax               ; r15 = caller's umask until it is restored.
    mov rdi,rax
    and edi,~0300o
    mov eax,SYS_UMASK          ; umask(2): rdi = parent-creation mask.
    syscall
    mov r14d,1
    mov rcx,rdx                ; syscall clobbers rcx; restart the path scan.
.scan:
 mov al,[rcx]
 test al,al
 jz .final
 cmp al,'/'
 jne .advance
 ; A run of separators at the end belongs to the final operand, not to the
 ; parent list.  Otherwise `new/` would be created as a parent and mistaken for
 ; an already-existing final directory, incorrectly skipping explicit chmod.
 mov rax,rcx
.look_past_slashes:
 cmp byte [rax],'/'; find the first byte after this separator run.
 jne .after_slashes
 inc rax
 jmp .look_past_slashes
.after_slashes:
 cmp byte [rax],0
 je .final
 cmp rcx,rdx
 je .advance
 cmp byte [rcx-1],'/'
 je .advance
 cmp byte [rcx-1],'.'
 jne .component
 lea rax,[rdx+1]
 cmp rcx,rax
 je .advance
 cmp byte [rcx-2],'/'; component exactly '.' after a slash.
 je .advance
.component:
 mov byte [rcx],0
 push rcx
 mov rdi,rdx
 mov esi,0777o
 call ensure_dir
 pop rcx
 mov byte [rcx],'/'
 test rax,rax
 js .mp_fail
.advance: inc rcx
 jmp .scan
.final:
    ; The requested final directory uses the caller's original umask.  An
    ; explicit -m is made exact later, but only when this invocation creates it.
    mov eax,SYS_UMASK          ; umask(2): rdi = saved caller mask.
    mov rdi,r15
    syscall
    xor r14d,r14d
 ; Remove trailing slashes for a stable final syscall, except root '/'.
 lea rcx,[path+r13-2]
.trim: cmp rcx,rdx
 jbe .create_final
 cmp byte [rcx],'/'; repeated/trailing slash has no semantic value here.
 jne .create_final
 mov byte [rcx],0
 dec rcx
 jmp .trim
.create_final:
 mov rdi,rdx
 mov esi,ebp
    call ensure_dir
    test rax,rax
    js .mp_fail
    mov r15,rax               ; 0 = created, 1 = already-existing directory.
    test bh,bh
    jz .mp_ok
    test r15,r15
    jnz .mp_ok                ; -p never changes an existing directory's mode.
 mov eax,SYS_CHMOD          ; chmod final only; implicit parents retain umask mode.
 mov rdi,rdx
 mov esi,ebp
 syscall
 test rax,rax
 js .mp_fail
.mp_ok: xor eax,eax
 jmp .mp_ret
.mp_fail:
    test r14d,r14d
    jz .mp_failed_after_restore
    mov eax,SYS_UMASK          ; umask(2): restore even when a parent fails.
    mov rdi,r15
    syscall
.mp_failed_after_restore:
    mov rax,-1
.mp_ret:
    pop r15
    pop r14
    pop r13
 pop r12
 ret
; ensure_dir: rdi=path, esi=create mode.
; Output: rax=0 if created, 1 if an existing directory was found, negative on
; failure.  Distinguishing the first two states prevents `mkdir -p -m` from
; chmodding a directory that belongs to the caller already.
ensure_dir:
 push rdi
 mov eax,SYS_MKDIR
 syscall
 test rax,rax
 jns .ed_ok
 cmp rax,-EEXIST
 jne .ed_ret
 pop rdi
 push rdi
 mov eax,SYS_STAT           ; stat(2): rdi=prefix, rsi=writable struct stat.
 lea rsi,[st]
 syscall
 test rax,rax
 js .ed_ret
 mov eax,[st+24]
 and eax,S_IFMT
 cmp eax,S_IFDIR
 jne .ed_bad
 jmp .ed_existing
.ed_ok: xor eax,eax
    jmp .ed_ret
.ed_existing:
    mov eax,1
    jmp .ed_ret
.ed_bad: mov rax,-1
.ed_ret: pop rdi
 ret
; octal_mode: rsi=NUL text; rax=value or -1. Reject empty, >4 digits, non-octal.
octal_mode:
 xor eax,eax
 xor ecx,ecx
.om_loop: movzx edx,byte [rsi+rcx]
 test dl,dl
 jz .om_end
 cmp ecx,4
 jae .om_bad
 sub dl,'0'
 cmp dl,7
 ja .om_bad
 shl eax,3                  ; base-eight shift makes room for the next digit.
 add eax,edx
 inc ecx
 jmp .om_loop
.om_end: test ecx,ecx
 jz .om_bad
 ret
.om_bad: mov rax,-1
 ret
errline: call errstr
 lea rsi,[nl]
 mov edx,1
 mov edi,2
 jmp write_all
errstr: mov edi,2
 xor edx,edx
.eslen: cmp byte [rsi+rdx],0
 je write_all
 inc rdx
 jmp .eslen
write_all:
 test rdx,rdx
 jz .wa_ok
 mov eax,SYS_WRITE          ; write(2): fd, remaining pointer/count.
 syscall
 cmp rax,-EINTR
 je write_all
 test rax,rax
 jle .wa_bad
 add rsi,rax
 sub rdx,rax
 jmp write_all
.wa_ok: xor eax,eax
 ret
.wa_bad: mov eax,1
 ret
section .rodata
empty: db 0
