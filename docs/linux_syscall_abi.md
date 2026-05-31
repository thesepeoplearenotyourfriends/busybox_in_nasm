# Linux x86_64 syscall ABI

The first utilities in this repository avoid libc and talk directly to the Linux kernel with the `syscall` instruction. This keeps the mechanism visible.

## Register convention

For Linux x86_64 syscalls:

| Purpose | Register |
| --- | --- |
| syscall number | `rax` |
| argument 1 | `rdi` |
| argument 2 | `rsi` |
| argument 3 | `rdx` |
| argument 4 | `r10` |
| argument 5 | `r8` |
| argument 6 | `r9` |
| return value | `rax` |

The `syscall` instruction clobbers `rcx` and `r11`. If a program needs values in those registers after a syscall, it must save them first.

## Common syscalls used here

| Name | Number | Arguments used in this project |
| --- | ---: | --- |
| `write(2)` | `1` | `rdi = fd`, `rsi = buffer`, `rdx = byte count` |
| `exit(2)` | `60` | `rdi = process status` |
| `nanosleep(2)` | `35` | `rdi = requested timespec`, `rsi = remaining timespec` |
| `getcwd(2)` | `79` | `rdi = buffer`, `rsi = byte count` |

## Return values and errors

On success, a syscall returns a non-negative value in `rax`. For `write(2)`, that value is the number of bytes written.

On failure, Linux returns a negative errno value in `rax`, such as `-32` for `EPIPE`. libc normally converts this into `-1` and stores the positive errno in `errno`; these raw assembly programs see the kernel value directly.

Early utilities in this repository keep error handling simple. For example, `yes` treats failed `write(2)` calls as a reason to stop and exit unsuccessfully rather than trying to print a full errno string table.

## Program startup without libc

When the linker uses `_start` as the entry point, there is no C runtime to call `main(argc, argv, envp)`. At process entry, Linux provides the startup data on the stack:

```text
rsp -> argc
       argv[0]
       argv[1]
       ...
       NULL
       envp[0]
       ...
       NULL
       auxiliary vector
```

A utility that needs command-line arguments reads `argc` from `[rsp]` and `argv[0]` from `[rsp + 8]`, `argv[1]` from `[rsp + 16]`, and so on.

The `echo`, `yes`, `pwd`, `env`, `printenv`, `sleep`, and `usleep` implementations use this layout directly so argument handling and environment traversal stay visible.


## Timespec values for nanosleep

The `sleep` and `usleep` utilities use Linux `nanosleep(2)`, whose first argument points at two 64-bit fields on x86_64:

```text
struct timespec {
    tv_sec   ; seconds
    tv_nsec  ; nanoseconds, 0 through 999999999
}
```

`sleep` places the parsed seconds in `tv_sec` and zero in `tv_nsec`. `usleep` divides microseconds by 1,000,000 for `tv_sec` and multiplies the remainder by 1,000 for `tv_nsec`.
