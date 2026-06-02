# Notes: `cat`

`cat` is where this repo starts feeling less like “tiny syscall demos” and more like “a real Unix utility is being assembled from small pieces.”

It still is not a giant program. It does not implement numbering, squeezing blank lines, visible control characters, or the wider option set. The source says those are intentionally missing in this teaching version. 

But the important shape is here:

> read bytes from somewhere, write those same bytes somewhere else, keep going until EOF.

That one sentence is the skeleton of a huge amount of Unix tooling.

Keep `src/cat.asm` open beside this note. This page is here to help the file read like a map instead of a wall.

---

## What this command really does

At the shell level, `cat` feels like:

> show me this file

or:

> join these streams together

At the assembly level, this version is more literal:

> open an input file descriptor, repeatedly read chunks into a buffer, then write those chunks to stdout

With no operands, it copies stdin to stdout. With file operands, it opens each one in order. A single `-` means stdin, following the common `cat` convention. 

The big picture looks like this:

| Left pane: code idea                          | Right pane: human meaning                           |
| --------------------------------------------- | --------------------------------------------------- |
| Read `argc` and `argv` from the startup stack | “What did the user ask us to copy?”                 |
| If there are no operands                      | “Act like a filter: stdin to stdout.”               |
| Otherwise loop over pathnames                 | “Visit each requested file.”                        |
| Open each file read-only                      | “Turn the pathname into a file descriptor.”         |
| Copy fd to stdout                             | “Move bytes until EOF.”                             |
| Close successful opens                        | “Clean up the file descriptor.”                     |
| Accumulate failure status                     | “Keep going, but remember if something went wrong.” |

That is already a very Unix-shaped program.

---

## The tiny command-line parser

Near the top of `_start`, the program loads two important things:

`argc`

and

`argv`

The source keeps them in long-lived registers:

| Register | Meaning                                    |
| -------- | ------------------------------------------ |
| `r12`    | `argc`, the number of command-line entries |
| `r13`    | base address of the `argv` pointer array   |
| `r14`    | current argv index                         |
| `r15`    | accumulated process status                 |

The useful thing to notice is that `argv` is not magic. It is just an array of pointers placed on the process stack when the program begins.

So this line shape:

`mov rsi, [r13 + r14*8]`

means:

> load the pointer for argv entry number `r14`

The `*8` is there because this is 64-bit code. Each pointer is 8 bytes.

This is one of those places where assembly makes the hidden machinery visible. In C, you say `argv[i]`. Here, you can see the address arithmetic.

---

## Why `r14` starts at 1

The source initializes:

`r14 = 1`

That skips `argv[0]`.

`argv[0]` is the program name. The first real user-supplied operand is `argv[1]`.

So the loop starts at index `1`, not index `0`.

That little detail is worth locking in early:

| argv entry | Usual meaning         |
| ---------- | --------------------- |
| `argv[0]`  | command name/path     |
| `argv[1]`  | first actual operand  |
| `argv[2]`  | second actual operand |

This becomes important in any command that reads arguments by hand.

---

## The no-operand path: Unix filter mode

If `argc` is `1`, there are no file operands.

That means the user ran something like:

```sh
cat
```

In this case, the program copies stdin to stdout.

The source does this by putting `0` in the input fd register and calling the common copy helper. File descriptor `0` is stdin. File descriptor `1` is stdout. File descriptor `2` is stderr.

That means the no-argument version of `cat` is not a special high-level mode. It is just:

> copy fd 0 to fd 1

This is the classic Unix filter shape.

You can put it in the middle of a pipeline because it does not care whether fd `0` is your keyboard, a pipe, a redirected file, or something else.

---

## The named-file loop

When there are operands, the program enters the loop labeled around:

`.copy_named_files`

The loop invariant in the comments is doing real teaching work here: `r14` is the next argv index, and `r15` remains `0` only as long as every earlier file copied successfully. 

That is a good way to read the loop:

| Register | Question it answers        |
| -------- | -------------------------- |
| `r14`    | “Which operand am I on?”   |
| `r12`    | “How many operands exist?” |
| `r15`    | “Has anything failed yet?” |

The loop stops when `r14` catches up to `r12`.

That comparison is the assembly version of:

```c
while (i < argc) {
    ...
}
```

Except here, you can see every part of the bookkeeping.

---

## The special `-` operand

Before trying to open the current operand as a file, the program checks:

`is_single_dash`

That helper returns true only for exactly `"-"`.

Not “starts with dash.”

Not “some option.”

Exactly one dash.

For `cat`, that means:

> read from stdin at this point in the file list

So this:

```sh
cat a.txt - b.txt
```

means:

> copy `a.txt`, then copy stdin, then copy `b.txt`

The helper itself is almost comically direct:

| Check               | Meaning                       |
| ------------------- | ----------------------------- |
| first byte is `'-'` | maybe a dash operand          |
| second byte is NUL  | exactly one character long    |
| otherwise           | not the special stdin operand |

This is a nice reminder that many “string tests” in assembly are just byte comparisons with a little control flow.

---

## Opening a file: pathname becomes fd

For a normal operand, the source calls:

`open_read_only`

That helper wraps the `open(2)` syscall. The source defines syscall numbers near the top, including `SYS_OPEN`, `SYS_READ`, `SYS_WRITE`, `SYS_CLOSE`, and `SYS_EXIT`. 

The conceptual move is:

> pathname string in, file descriptor out

A pathname is text.

A file descriptor is a small integer handle the kernel gives back.

Once the program has the fd, it does not keep passing the filename around for reading. The fd becomes the thing the kernel understands.

That is an important Unix boundary:

| Before `open`                                           | After successful `open` |
| ------------------------------------------------------- | ----------------------- |
| “Here is a path.”                                       | “Here is an fd.”        |
| user-space string                                       | kernel-issued handle    |
| can fail because file does not exist, permissions, etc. | can be passed to `read` |

The source checks the return value with a sign test. Negative return means failure.

---

## Why failed opens do not immediately exit

If one file fails to open, this `cat` prints a short diagnostic, marks failure, then continues to the next operand. 

That is a very normal command-line-tool behavior.

Example:

```sh
cat good.txt missing.txt also-good.txt
```

A useful `cat` should still show the files it can show.

But the final exit status should remember that something went wrong.

That is what `r15` is doing. It is not “the current error.” It is the final report card.

| `r15` value | Meaning                     |
| ----------- | --------------------------- |
| `0`         | everything so far succeeded |
| `1`         | at least one thing failed   |

This is a nice practical pattern: keep working when possible, but do not lie at the end.

---

## The central helper: `copy_fd_to_stdout`

This is the heart of the program.

The helper receives an input fd in `rdi`.

It copies from that fd to stdout until one of three things happens:

| `read(2)` result | Meaning             |
| ---------------- | ------------------- |
| positive number  | got that many bytes |
| zero             | EOF, done           |
| negative number  | read error          |

The source comments state the loop invariant clearly: bytes from earlier reads have already been written to stdout; the next read either supplies another chunk, reports EOF, or fails. 

That is exactly how to think about this loop.

Not “read the file.”

More precisely:

> ask the kernel for up to 4096 bytes; if it gives us some, write exactly those bytes; repeat

---

## The buffer is reusable scratch space

The source reserves:

`buffer: resb BUFFER_SIZE`

and `BUFFER_SIZE` is `4096`. 

That does not mean the file is 4096 bytes.

It means:

> this program moves data in chunks up to 4096 bytes at a time

The same buffer gets reused for every read.

So for a large file, the program does not load the whole thing into memory. It cycles:

```text
read chunk -> write chunk
read chunk -> write chunk
read chunk -> write chunk
...
```

That is the shape you want burned into memory.

A stream program is often not “holding the data.”

It is borrowing a little buffer and passing bytes along.

---

## Write the bytes read, not the whole buffer

After a successful read, `rax` contains the number of bytes actually read.

The source then uses that value as the write length. 

That matters.

If the buffer is 4096 bytes, a read might return:

| Returned bytes | Situation                        |
| -------------- | -------------------------------- |
| `4096`         | full chunk                       |
| `500`          | smaller chunk, maybe near EOF    |
| `1`            | tiny input or interactive stream |
| `0`            | EOF                              |

When the kernel says “I gave you 500 bytes,” the program must write 500 bytes.

Not 4096.

The rest of the buffer is old scratch space. It is not part of this read.

That is a quiet but important low-level habit:

> the buffer capacity and the valid byte count are different facts

---

## Why `write_all` exists

A beginner version might call `write(2)` once and assume all bytes were written.

This source does better. It has a `write_all` helper.

The reason is that `write(2)` can write fewer bytes than requested. For normal terminal output or small files, you may not see that often, but stream code should not depend on luck.

The source comments say the helper keeps writing the unwritten suffix. 

The helper tracks two things:

| Register | Meaning                                  |
| -------- | ---------------------------------------- |
| `r9`     | pointer to the next byte not yet written |
| `r10`    | number of bytes still to write           |

After each successful write:

```text
advance pointer by bytes written
shrink remaining count by bytes written
```

That is the whole trick.

This is not glamorous, but it is the difference between “toy syscall demo” and “stream code with the right instincts.”

---

## The write loop as a moving window

The key movement in `write_all` is:

`add r9, rax`
`sub r10, rax`

Read that as:

> the kernel accepted `rax` bytes, so move the start pointer forward and reduce the remaining count

Picture the original buffer like this:

```text
[ already written ][ still needs writing ]
                  ^
                  r9
```

Each successful write moves `r9` to the right.

When `r10` reaches zero, there is nothing left to write, and the helper returns success.

This is a good assembly pattern to notice because it shows up everywhere: pointer plus remaining length. Parsing, copying, searching, writing — many loops reduce to some version of that pair.

---

## Closing files

After a named file is copied, the source calls:

`close_fd`

The comments point out the practical lesson: every successful open should have a matching close in simple tools. 

For a short-lived process, the OS would clean up open fds when the process exits.

But relying on that everywhere is a sloppy habit.

This version teaches the normal lifecycle:

```text
open -> use -> close
```

Or more concretely:

```text
pathname -> fd -> read loop -> close fd
```

That is the file version of cleaning your workbench before moving on.

---

## Diagnostics go to stderr

The program writes file-open errors, read errors, and write errors to fd `2`.

That is stderr.

This matters because stdout is supposed to be the copied data.

If errors went to stdout, this would be bad:

```sh
cat missing.txt real.txt > combined.txt
```

The error message would get mixed into the output file.

By writing diagnostics to stderr, the program keeps two streams separate:

| fd         | Purpose                    |
| ---------- | -------------------------- |
| `1` stdout | actual `cat` output        |
| `2` stderr | complaints and diagnostics |

This is one of those Unix details that seems fussy until pipelines and redirection enter the picture. Then it becomes essential.

---

## Measuring C strings for error output

The helper:

`write_c_string_fd`

takes a NUL-terminated string and counts bytes until it finds `0`.

Then it calls `write_all`.

That is necessary because `write(2)` does not accept “a C string.”

It accepts:

> pointer plus byte count

So if the source has messages like:

`"cat: read failed", 10, 0`

the trailing `0` is useful for the program’s own string-counting helper, but it is not something `write(2)` understands magically.

The helper turns:

```text
pointer to NUL-terminated string
```

into:

```text
pointer + measured length
```

That conversion is a very practical piece of glue.

---

## The final exit status

At the end, the command exits with:

`r15`

That means the process status is accumulated across all operands.

If every file copied successfully, `r15` is still `0`.

If any open, read, or write failed, `r15` becomes `1`.

So the program can continue copying later files while still reporting failure to the shell at the end.

That is exactly the kind of small behavior that makes command-line tools composable. A human sees the diagnostic. A script sees the exit status.

---

## What this file is quietly teaching

`cat.asm` teaches a lot of reusable assembly habits:

| Concept                                        | Where it appears                   |
| ---------------------------------------------- | ---------------------------------- |
| Reading `argc` / `argv` from the initial stack | `_start` setup                     |
| Looping over command operands                  | `.copy_named_files`                |
| Special operand handling                       | `is_single_dash`                   |
| File descriptor lifecycle                      | `open_read_only`, `close_fd`       |
| Fixed-size reusable buffer                     | `.bss buffer`                      |
| EOF-driven read loop                           | `copy_fd_to_stdout`                |
| Buffer capacity vs valid byte count            | `BUFFER_SIZE` vs `rax` from `read` |
| Partial-write handling                         | `write_all`                        |
| stderr diagnostics                             | fd `2`                             |
| Accumulated exit status                        | `r15`                              |

That is why this one earns a companion note.

It is not just “here is `cat`.”

It is the first strong example of a durable stream-processing pattern.

---

## Suggested experiments

Try stdin mode:

```sh
printf 'hello\n' | ./build/cat
```

Try a normal file:

```sh
./build/cat README.md
```

Try multiple files:

```sh
./build/cat file1.txt file2.txt
```

Try the special dash operand:

```sh
printf 'middle\n' | ./build/cat file1.txt - file2.txt
```

Try an error case:

```sh
./build/cat definitely-not-here.txt README.md
echo $?
```

The important behavior to watch:

> it should complain about the missing file, still copy `README.md`, and exit with failure status.

That is a grown-up command-line-tool behavior hiding inside a small teaching implementation.

---

## Takeaway

`cat.asm` is the stream-processing keystone.

`clear` taught:

> write these bytes once

`cat` teaches:

> keep moving bytes until the kernel says there are no more

That is a major step up.

Once this shape makes sense — fd in, buffer in the middle, stdout out, loop until EOF — a lot of other Unix commands become less mysterious. They may transform, count, filter, split, or decorate the stream, but many of them are still built around the same basic engine:

```text
read some bytes
do something
write some bytes
repeat
```

That is the kind of pattern worth recognizing early.
