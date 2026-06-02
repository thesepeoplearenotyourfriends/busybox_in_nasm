# Notes: `env`

`env` looks like a command about environment variables.

This teaching version is also secretly a command about process startup.

That is what makes it useful.

The program does not call a library to ask for the environment. It does not use `extern environ`. It does not edit variables, clear variables, parse `NAME=VALUE`, or launch a command under a modified environment.

It just walks the raw process-startup stack and prints the environment strings Linux gave the process.

That gives this file a very specific lesson:

> after `argc` and `argv`, there is more useful process information sitting on the initial stack

Keep `src/env.asm` open beside this note. The source is short, but it points at a big idea.

---

## What this command really does

At the shell level, `env` feels like:

> show me the environment

At the assembly level, this version does something more literal:

| Left pane: code idea          | Right pane: human meaning                            |
| ----------------------------- | ---------------------------------------------------- |
| Read `argc` from `[rsp]`      | “How many command-line entries are there?”           |
| Find the `argv` pointer array | “Where are the argument pointers?”                   |
| Reject any operand            | “This version only prints the existing environment.” |
| Compute where `envp` begins   | “Skip past `argv` and its NULL terminator.”          |
| Walk environment pointers     | “Each pointer leads to a `NAME=VALUE` string.”       |
| Print each string and newline | “Show one environment entry per line.”               |
| Stop at NULL                  | “The environment pointer array is finished.”         |

That is the whole program.

It is not a full replacement for GNU or BusyBox `env`.

It is a small stack-walking lesson.

---

## The startup stack shape

Earlier commands already used:

```text
argc
argv
```

This command adds the next layer:

```text
envp
```

At raw process entry, the stack begins with a layout like this:

```text
[rsp]        argc

[rsp + 8]    argv[0]
[rsp + 16]   argv[1]
[rsp + 24]   argv[2]
...
             NULL

             envp[0]
             envp[1]
             envp[2]
...
             NULL
```

The exact number of `argv` entries depends on `argc`.

That means `envp` does not begin at one fixed address.

The program has to calculate where it begins.

That is the central move in this file.

---

## `argc` and `argv`, again

The source begins with the familiar setup:

```asm
mov r12, [rsp]
lea r13, [rsp + 8]
```

Read that as:

| Register | Meaning              |
| -------- | -------------------- |
| `r12`    | `argc`               |
| `r13`    | address of `argv[0]` |

This is the raw version of what C normally hands you as:

```c
main(int argc, char **argv)
```

But there is no `main()` here.

There is no C runtime preparing a neat function call.

The program starts at `_start`, and the startup information is already sitting on the stack.

---

## Why this version rejects operands

The source checks:

```asm
cmp r12, 1
jne .reject_first_extra
```

Since `argc` includes the program name, `argc == 1` means:

```text
no user operands
```

That is the only supported shape.

So this is allowed:

```sh
./build/env
```

But these are rejected:

```sh
./build/env FOO=bar
./build/env printenv
./build/env -i
```

Real `env` can do much more. It can modify the environment and launch a command. This teaching version intentionally does not do that. The comments say operands are rejected instead of being interpreted as `NAME=VALUE` pairs or a command to execute. 

That keeps the lesson narrow:

> find the inherited environment and print it

Not:

> implement all of `env`

That is a good boundary for a `00`-level assembly command.

---

## Finding `envp`

The key line is:

```asm
lea r14, [r13 + r12*8 + 8]
```

This looks dense, but it is just pointer-array arithmetic.

Remember:

| Register     | Meaning         |
| ------------ | --------------- |
| `r13`        | start of `argv` |
| `r12`        | `argc`          |
| each pointer | 8 bytes         |

So:

```text
r13 + r12*8
```

points to the NULL pointer after the last `argv` entry.

Then the extra:

```text
+ 8
```

moves past that NULL.

So the whole thing means:

> `r14` now points at `envp[0]`

In C-ish terms, it is like finding:

```c
&argv[argc + 1]
```

The source comments describe exactly that: `envp` starts after the `argc` `argv` pointers and the NULL pointer that terminates `argv`. 

This is the main “aha” of the file.

The environment is not fetched from a magic global.

It is adjacent to `argv` in the initial stack layout.

---

## Pointer arrays, not strings yet

At this point, `r14` points to a slot in an array.

That slot contains a pointer.

The string itself lives somewhere else.

So this line:

```asm
mov rsi, [r14]
```

means:

> load the pointer stored in the current `envp` slot

Not:

> load the first bytes of the environment string

That distinction matters.

The environment pointer array looks like:

```text
envp slot -> "HOME=/home/art"
envp slot -> "PATH=/bin:/usr/bin"
envp slot -> "TERM=xterm-256color"
...
NULL
```

The array is made of pointers.

Each pointer leads to a NUL-terminated string.

Assembly makes that extra level of indirection visible.

---

## The NULL terminator stops the loop

After loading the current pointer, the code checks:

```asm
test rsi, rsi
jz .exit_success
```

That asks:

> is this pointer NULL?

If yes, there are no more environment entries.

That is how the program knows when to stop.

There is no separate environment count.

Unlike `argv`, where `argc` tells you how many argument entries exist, `envp` is walked until a NULL pointer appears.

So the two arrays are similar but not identical:

| Array  | How the program knows the end  |
| ------ | ------------------------------ |
| `argv` | `argc`, plus a NULL terminator |
| `envp` | NULL terminator                |

This file is a good place to notice that difference.

---

## The loop invariant

The source comment gives a useful invariant:

> environment entries before `r14` have been printed with trailing newlines; `r14` points at the next pointer or the final NULL terminator. 

That is a compact way to understand the loop.

Before each iteration:

| Fact            | Meaning                            |
| --------------- | ---------------------------------- |
| earlier entries | already printed                    |
| `r14`           | current envp slot                  |
| `[r14]`         | pointer to current string, or NULL |
| NULL pointer    | loop is done                       |

After printing one entry, the program does:

```asm
add r14, 8
```

That advances to the next pointer slot.

Again, `8` is pointer size on x86_64.

This is pointer-array walking in its simplest form.

---

## Why each entry needs a newline

Environment strings are NUL-terminated, not newline-terminated.

An entry might look like:

```text
PATH=/usr/bin:/bin
```

In memory, it ends with byte `0`, not byte `10`.

But the command wants to print one entry per line.

So after writing the string, the program separately writes:

```asm
newline: db 10
```

That adds the line feed.

This is a good small reminder:

| Memory representation | Printed display |
| --------------------- | --------------- |
| `NAME=VALUE\0`        | `NAME=VALUE\n`  |

The NUL byte is for the program.

The newline is for the human-readable output.

---

## `NAME=VALUE` is just a string here

The environment entries look structured:

```text
HOME=/home/art
SHELL=/bin/bash
TERM=xterm-256color
```

But this teaching version does not split them.

It does not search for `=`.

It does not separately understand names and values.

It treats each entry as one C string and writes it.

That is exactly right for this lesson.

A later, more capable `env` could parse `NAME=VALUE`.

This one is here to show:

> `envp` is an array of pointers to NUL-terminated strings

That is enough.

---

## The diagnostic split: option-looking versus operand-looking

When the program sees extra input, it checks whether the first unexpected argument starts with `-`.

The helper:

```asm
starts_with_dash
```

only checks the first byte.

So:

| Input      | Path               |
| ---------- | ------------------ |
| `-i`       | unsupported option |
| `--help`   | unsupported option |
| `FOO=bar`  | unexpected operand |
| `printenv` | unexpected operand |

That is not full option parsing.

It is just enough to produce a more useful error message.

The source has separate diagnostic prefixes for unsupported options and unexpected operands. 

That is a nice small design move: keep implementation simple, but still tell the user which kind of unsupported thing they tried.

---

## Printing a C string means measuring it first

The helper:

```asm
write_c_string_fd
```

is one of the important support routines.

Its input is:

| Register | Meaning                            |
| -------- | ---------------------------------- |
| `rdi`    | file descriptor                    |
| `rsi`    | pointer to a NUL-terminated string |

But `write(2)` does not accept NUL-terminated strings.

It wants:

```text
fd, pointer, byte count
```

So the helper counts bytes until it finds the NUL terminator.

The source comment states the teaching point directly: envp entries are C strings, but `write(2)` needs a byte count. 

That is one of the most reusable ideas in this whole little command:

> a convenient program representation often has to be converted into a syscall representation

Here, the conversion is:

```text
C string -> pointer plus length
```

---

## The count loop

The string-length helper does this conceptually:

```text
start = rsi
length = 0

while start[length] != 0:
    length += 1
```

In the source, `rbx` holds the stable string start while `rdx` counts upward.

So each loop checks:

```asm
cmp byte [rbx + rdx], 0
```

That means:

> look at the byte `rdx` bytes after the beginning of the string

If the byte is zero, the length is known.

If not, increment `rdx` and continue.

Very plain.

Very useful.

A lot of assembly string handling begins exactly like this: one byte at a time until a sentinel value appears.

---

## `write_buffer_fd`: one syscall, honest result

Once the helper knows the length, it calls:

```asm
write_buffer_fd
```

That wrapper performs the `write(2)` syscall:

| Register | Meaning                         |
| -------- | ------------------------------- |
| `rax`    | syscall number, `1` for `write` |
| `rdi`    | fd                              |
| `rsi`    | pointer to bytes                |
| `rdx`    | byte count                      |

Then it compares the return value against the requested length.

If `write` wrote exactly the requested number of bytes, the helper returns `0`.

If not, it returns `1`.

The source treats short writes as failure in this teaching pass. 

A larger streaming command like `cat` deserves a full `write_all` loop.

Here, the output pieces are small environment strings and diagnostic fragments, so the simpler helper keeps the file easy to read.

Different tool, different robustness trade.

---

## stdout and stderr

Normal environment entries go to stdout.

Diagnostics go to stderr.

That means:

```sh
./build/env > env.txt
```

captures only real environment output.

But:

```sh
./build/env -i > env.txt
```

should not put the error message into `env.txt`.

That is why error messages use fd `2`.

This is the same composability habit seen in `cat` and `wc`:

| Stream         | Purpose                 |
| -------------- | ----------------------- |
| stdout, fd `1` | command’s actual output |
| stderr, fd `2` | complaints              |

A tiny command should still learn that habit early.

---

## The exit paths

The success path exits with status `0`.

The failure path exits with status `1`.

The source comments summarize that behavior: successful writing of every environment entry exits `0`; unsupported input or write failure exits `1`. 

This version does not decode errno values.

It does not attempt recovery from write failures.

It simply makes sure it does not claim success unless the requested output was written.

That is enough for this command’s teaching purpose.

---

## What this file is quietly teaching

`env.asm` teaches a different kind of low-level idea than `cat` or `wc`.

It is less about reading file data and more about understanding the process’s starting conditions.

| Concept                       | Where it appears          |
| ----------------------------- | ------------------------- |
| Raw process startup stack     | `_start`                  |
| `argc` access                 | `[rsp]`                   |
| `argv` pointer array          | `[rsp + 8]`               |
| Finding `envp`                | `argv + argc + NULL`      |
| Pointer array walking         | `r14`, then `add r14, 8`  |
| NULL-terminated pointer lists | stop when `[r14] == 0`    |
| C strings                     | each environment entry    |
| Measuring a C string          | `write_c_string_fd`       |
| Syscall-shaped output         | pointer plus byte count   |
| stdout/stderr separation      | fd `1` vs fd `2`          |
| Limited feature scope         | operands/options rejected |

That makes it a valuable note.

It answers a question many learners eventually have:

> where does the environment actually come from?

In this version, the answer is visible:

> it is handed to the process at startup, right after `argv`.

---

## Suggested experiments

Print your environment:

```sh
./build/env
```

Compare with your system `env`:

```sh
env | head
./build/env | head
```

The order and exact entries may vary depending on how the program is launched, but the shape should be familiar:

```text
NAME=VALUE
NAME=VALUE
NAME=VALUE
```

Redirect stdout:

```sh
./build/env > env.txt
```

Then inspect the file:

```sh
head env.txt
```

Try an unsupported option:

```sh
./build/env -i
echo $?
```

Try an unexpected operand:

```sh
./build/env FOO=bar
echo $?
```

Those are useful because real `env` accepts them, but this teaching version rejects them.

That contrast makes the scope clear:

| Command           | This version                |
| ----------------- | --------------------------- |
| `env`             | print inherited environment |
| `env FOO=bar cmd` | not implemented             |
| `env -i`          | not implemented             |
| `env --help`      | not implemented             |

The absence of those features is intentional. This file is teaching the stack layout, not full `env` behavior.

---

## Takeaway

`env.asm` is a process-startup layout lesson wearing a Unix command’s jacket.

Earlier files showed:

```text
argc lives at [rsp]
argv begins at [rsp + 8]
```

This file adds:

```text
envp begins after argv and argv’s NULL terminator
```

From there, the program just walks a NULL-terminated array of pointers and writes each C string.

That is a clean little reveal.

The environment is not mystical.

It is not hidden in a shell cloud.

By the time your program starts, Linux has already placed a pointer list where your code can find it.

And in assembly, you can see the path there byte-for-byte:

```text
argc -> argv pointers -> NULL -> envp pointers -> NULL
```

That is the real lesson of this command.
