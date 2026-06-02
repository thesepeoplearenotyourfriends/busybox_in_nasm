
# Notes: `clear`

`clear` is a good early assembly lesson because the program is almost offensively small, but it still crosses several important borders:

You are not calling a library.

You are not asking curses, terminfo, or the shell to do anything clever.

You are writing a few bytes directly to stdout, and the terminal interprets those bytes as instructions.

That makes this command a nice little window into a core Unix idea: sometimes “doing a thing” just means writing the right bytes to the right file descriptor.

The source for this command lives at:

`src/clear.asm`

Keep that file open beside this. This document is not trying to duplicate the code; it is here to help your eyes know what they are looking at.

---

## What this command really does

At the command-line level, `clear` feels like an action:

> clear the screen

At the assembly level, this version does something much plainer:

> write an escape sequence to stdout

That sequence is described in the source as the common ANSI/VT100 clear-screen sequence. The implementation intentionally avoids terminal database lookup and writes the escape bytes directly. 

So the whole program is basically:

| Left pane: code idea                    | Right pane: human meaning                  |
| --------------------------------------- | ------------------------------------------ |
| Put terminal-control bytes in `.rodata` | “Here are the bytes we want to send.”      |
| Call `write(2)`                         | “Send those bytes to stdout.”              |
| Check the return value                  | “Did the kernel say it wrote all of them?” |
| Call `exit(2)`                          | “Leave with success or failure status.”    |

That is the whole shape.

Small, but very assembly-flavored.

---

## The data: bytes pretending to be a command

Look at the line containing:

`clear_sequence: db 27, "[H", 27, "[2J"`

This is the heart of the program. The source defines the terminal escape sequence as raw bytes in `.rodata`. 

The important piece is `27`.

Decimal `27` is ASCII **ESC**.

So this:

`27, "[H"`

means:

> ESC, then `[H`

And this:

`27, "[2J"`

means:

> ESC, then `[2J`

Together, the bytes are:

`ESC [ H ESC [ 2 J`

The first part moves the cursor to the home position.

The second part clears the screen.

The terminal is not receiving a friendly high-level request like “please clear yourself.” It is receiving a small byte-language command. That is a useful assembly mental model: the machine is often less mystical than it looks. You are putting bytes somewhere, and something downstream assigns meaning to those bytes.

---

## Why `.rodata`?

The sequence lives under:

`section .rodata`

That means “read-only data.”

Nothing in this program needs to edit the clear sequence at runtime. It is just a fixed piece of byte text. So it belongs in a data section, not mixed into the instruction stream.

That separation is worth noticing early:

| Thing                                | Where it belongs          |
| ------------------------------------ | ------------------------- |
| Instructions the CPU executes        | `.text`                   |
| Fixed bytes the program reads/writes | `.rodata`                 |
| Mutable storage                      | usually `.data` or `.bss` |

This command only needs `.rodata` and `.text`.

No heap.

No stack tricks.

No libc.

Just bytes and syscalls.

---

## The length trick: `equ $ - clear_sequence`

Right after the byte sequence, the source defines:

`clear_sequence_len: equ $ - clear_sequence`

This is one of those assembly idioms that looks like punctuation soup until it clicks.

Read it as:

> define `clear_sequence_len` as “current position minus the start of `clear_sequence`”

The `$` means “where the assembler is right now.”

Since the assembler has just finished laying down the bytes for `clear_sequence`, subtracting the label address gives the number of bytes in the sequence.

That matters because `write(2)` needs a byte count. The kernel does not care that humans see `"[H"` or `"[2J"` as little string fragments. It wants:

> file descriptor, buffer address, byte count

This line lets NASM count the bytes so the human does not have to.

Good assembly habit: let the assembler do bookkeeping when it can.

---

## `_start`: no lobby, no receptionist

The program begins at:

`_start:`

Because this is raw assembly without the C runtime, there is no `main()` waiting politely behind startup code. The kernel transfers control to the program entry point, and this project uses `_start` for that. The repo’s goals explicitly include process entry at `_start` without a C runtime. 

That means `_start` is not a function in the normal C sense.

There is no caller.

There is no return address you should return to.

When the program is done, it must use the `exit` syscall.

That is why the source does not end with `ret`.

It ends by telling the kernel:

> this process is finished

---

## The syscall setup: filling out the kernel’s form

The first syscall block prepares `write(2)`:

`mov rax, 1`
`mov rdi, 1`
`lea rsi, [clear_sequence]`
`mov rdx, clear_sequence_len`
`syscall`

The source comments identify these as the syscall number and the three `write` arguments. 

The useful way to read this is not as five random assembly lines. It is a form being filled out:

| Register | Meaning for Linux x86_64 syscall | Value here           |
| -------- | -------------------------------- | -------------------- |
| `rax`    | Which syscall?                   | `1`, meaning `write` |
| `rdi`    | Argument 1                       | `1`, stdout          |
| `rsi`    | Argument 2                       | address of the bytes |
| `rdx`    | Argument 3                       | number of bytes      |

Then `syscall` hands that filled-out form to the kernel.

This is one of the first big “assembly stops being fog” moments: registers are not just magic named boxes. For syscalls, they are the calling convention. Put the right values in the right registers, then cross into the kernel.

---

## `lea` is not loading the bytes

This line is worth pausing on:

`lea rsi, [clear_sequence]`

The program is not putting the escape sequence itself into `rsi`.

It is putting the **address** of the escape sequence into `rsi`.

That distinction matters constantly in assembly.

`write(2)` does not want the first byte of the message in a register. It wants to know where the message begins in memory.

So `rsi` becomes:

> “the buffer starts over there”

And `rdx` becomes:

> “read this many bytes from over there”

That pair — pointer plus length — is the low-level version of “string” for this syscall.

---

## The return check: did the kernel actually write it?

After `syscall`, the source does:

`cmp rax, clear_sequence_len`
`jne .exit_failure`

The `write` syscall returns the number of bytes written, or a negative error value. The source comments call out that failed or short writes exit with status `1`. 

This is a nice teaching choice. For a toy `clear`, it would be easy to ignore the return value and just exit `0`.

But checking it teaches the correct habit:

> a syscall is not a wish; it is a request with a result

If `rax` equals the full expected length, good. The escape sequence made it out.

If not, the program takes the failure path.

No fancy errno text yet. No retry loop. Just an honest binary decision:

| Result                      | Meaning                                |
| --------------------------- | -------------------------------------- |
| `rax == clear_sequence_len` | all expected bytes were written        |
| anything else               | failure for this tiny teaching version |

That is enough for this stage.

---

## The success exit

On success, the source sets up:

`mov rax, 60`
`xor rdi, rdi`
`syscall`

The comments identify syscall `60` as `exit(2)`, with `rdi` holding the process status. 

The line:

`xor rdi, rdi`

is a common assembly idiom for setting a register to zero.

So this says:

> exit with status 0

In shell terms, that means:

```sh
./build/clear
echo $?
```

should print `0` when the write succeeded.

---

## The failure exit

The failure path is labeled:

`.exit_failure:`

It performs another `exit(2)` syscall, but this time with:

`mov rdi, 1`

That means:

> exit with status 1

The source shows this failure path directly after the success path. 

That shape is very readable:

| Path                    | Exit status |
| ----------------------- | ----------- |
| wrote all bytes         | `0`         |
| did not write all bytes | `1`         |

For a first terminal-control command, that is exactly the right amount of error handling. It does not pretend to be a full `clear`. It teaches the syscall contract.

---

## What this file is quietly teaching

This little program teaches more than “how to clear a terminal.”

It teaches:

| Concept                      | Where it appears                      |
| ---------------------------- | ------------------------------------- |
| Fixed byte data              | `clear_sequence`                      |
| Assembler-computed length    | `equ $ - clear_sequence`              |
| Raw Linux syscall ABI        | `rax`, `rdi`, `rsi`, `rdx`, `syscall` |
| File descriptor output       | `rdi = 1`                             |
| Pointer-plus-length thinking | `rsi` + `rdx`                         |
| Syscall return checking      | `cmp rax, clear_sequence_len`         |
| Process status               | `exit(0)` vs `exit(1)`                |

That is a pretty good haul for a program whose visible behavior is “the screen blinked.”

---

## Suggested experiments

Try viewing the output as bytes instead of letting the terminal obey it:

```sh
./build/clear | od -An -tx1
```

The project already lists that as a manual test for this command. 

You should see the escape bytes instead of a cleared screen. That is the best way to make the command less magical:

> Oh. It really is just writing bytes.

Then try replacing the bytes with something harmless, rebuilding, and piping to `od` again. For example, make it write ordinary visible text first. Once that clicks, switch back to escape bytes.

That little loop — edit bytes, rebuild, inspect output — is a good way to get comfortable with the idea that assembly programs are not always doing “CPU wizardry.” Sometimes they are just very explicit byte plumbing.

---

## Takeaway

`clear.asm` is a pocket-sized syscall lesson disguised as a terminal command.

It does not know what a terminal is in any rich sense. It does not ask `$TERM` what kind of terminal you have. It does not load a database. It just writes a known escape sequence to stdout and trusts that an ANSI-compatible terminal will understand it.

That is the right level of primitive for this repo: readable, inspectable, honest about what is missing, and useful as a stepping stone toward bigger commands.
