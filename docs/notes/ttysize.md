# Notes: `ttysize`

`ttysize` is a small command with a different flavor from the earlier ones.

It does not walk a file.

It does not scan bytes.

It does not parse environment variables.

It asks a terminal device a question:

> how big are you right now?

That question goes through `ioctl(2)`, which makes this file a nice introduction to a syscall shape that is not just “read bytes” or “write bytes.”

The output is simple:

```text
rows columns
```

But the path there is interesting:

```text
stdin fd -> ioctl request -> struct winsize -> decimal output
```

Keep `src/ttysize.asm` open beside this note. The main lesson is how a program asks the kernel to fill in a small structure, then reads fields back out of that structure.

---

## What this command really does

At the shell level, `ttysize` feels like:

> print the terminal size

At the assembly level, this version does something more specific:

| Left pane: code idea                         | Right pane: human meaning                     |
| -------------------------------------------- | --------------------------------------------- |
| Reject operands and options                  | “This teaching version takes no arguments.”   |
| Call `ioctl(0, TIOCGWINSZ, &winsize_buffer)` | “Ask stdin’s terminal for its window size.”   |
| Check for a negative return                  | “Did the ioctl fail?”                         |
| Load `ws_row`                                | “Get the row count.”                          |
| Print a space                                | “Separate the two numbers.”                   |
| Load `ws_col`                                | “Get the column count.”                       |
| Print newline                                | “Finish the output line.”                     |
| Exit success or failure                      | “Report whether the query and output worked.” |

That is the entire command.

Small surface.

Useful syscall lesson.

---

## Why stdin matters

The source queries fd `0`.

Fd `0` is stdin.

That means the command is asking:

> is my standard input a terminal, and if so, what size is it?

That is slightly different from asking some abstract global “current terminal” object.

There may not be one.

For example, this should usually work in a real terminal:

```sh
./build/ttysize
```

But this may fail:

```sh
printf x | ./build/ttysize
```

because stdin is now a pipe, not the terminal device.

That is why the source comments say this command needs a real terminal on stdin. In a pipe or redirected test run, `ioctl(2)` fails and the program exits with status `1`.

That behavior is not a bug. It is the syscall boundary showing through.

---

## No operands, no options

The command begins by checking:

```asm
cmp r12, 1
je .read_window_size
```

Since `argc` includes `argv[0]`, `argc == 1` means:

```text
no user operands
```

That is the only supported shape.

So this is supported:

```sh
./build/ttysize
```

But these are not:

```sh
./build/ttysize --help
./build/ttysize whatever
```

The source separates those two error cases:

| First extra argument    | Error style        |
| ----------------------- | ------------------ |
| starts with `-`         | unsupported option |
| does not start with `-` | unexpected operand |

This is the same narrow-scope discipline as the other 00 commands.

The file is here to teach `ioctl` and `struct winsize`, not option parsing.

---

## The request number: `TIOCGWINSZ`

Near the top, the source defines:

```asm
%define TIOCGWINSZ 0x5413
```

That value is the ioctl request code for:

```text
get window size
```

The name breaks down roughly as:

| Piece   | Meaning              |
| ------- | -------------------- |
| `TIOC`  | terminal I/O control |
| `G`     | get                  |
| `WINSZ` | window size          |

You do not need to memorize the number.

The important point is that `ioctl` is a general syscall with many request types. The request number tells the kernel what kind of device-specific operation you want.

So the syscall is not merely:

```text
ioctl this fd
```

It is:

```text
ioctl this fd with this request, using this memory
```

That gives it a different feel from `read(2)` or `write(2)`.

---

## The `ioctl` syscall setup

The main syscall block is:

```asm
mov rax, 16
mov rdi, 0
mov rsi, TIOCGWINSZ
lea rdx, [winsize_buffer]
syscall
```

Read it as a small form being filled out:

| Register | Meaning        | Value here                  |
| -------- | -------------- | --------------------------- |
| `rax`    | syscall number | `16`, `ioctl`               |
| `rdi`    | argument 1     | fd `0`, stdin               |
| `rsi`    | argument 2     | request code, `TIOCGWINSZ`  |
| `rdx`    | argument 3     | pointer to `winsize_buffer` |

The important part is `rdx`.

The kernel needs a place to write the answer.

So the program gives it the address of a buffer.

This is an output pointer:

```text
kernel, please write the terminal size over here
```

That is a useful new shape.

Earlier commands often passed a pointer to bytes the kernel should read.

Here, the program passes a pointer to memory the kernel should fill.

---

## `winsize_buffer`: a tiny struct in memory

The source reserves:

```asm
winsize_buffer: resw 4
```

The comment explains the layout:

```text
struct winsize is four unsigned shorts:
rows, columns, x pixels, y pixels
```

Each `resw` slot is a word, meaning 2 bytes.

So the buffer layout is:

| Offset | Field       | Meaning          |
| -----: | ----------- | ---------------- |
|   `+0` | `ws_row`    | terminal rows    |
|   `+2` | `ws_col`    | terminal columns |
|   `+4` | `ws_xpixel` | pixel width      |
|   `+6` | `ws_ypixel` | pixel height     |

This program only prints rows and columns.

The pixel fields are intentionally ignored.

That keeps the behavior simple and matches the visible terminal-grid idea most people expect from a command like this.

---

## The structure is filled by the kernel

Before the syscall, `winsize_buffer` is just reserved memory.

After a successful syscall, it contains the answer.

That means this command has a clear before-and-after:

| Moment                   | Meaning                                                  |
| ------------------------ | -------------------------------------------------------- |
| before `ioctl`           | buffer exists, but has no useful answer yet              |
| after successful `ioctl` | buffer contains rows, columns, pixel width, pixel height |

That is the key low-level idea.

The program is not calculating terminal size.

It is not reading environment variables like `LINES` or `COLUMNS`.

It is asking the terminal device through the kernel, and the kernel writes a small structure back.

---

## Checking `ioctl` failure

After the syscall, the source does:

```asm
test rax, rax
js .ioctl_failed
```

Linux syscalls usually report errors as negative return values.

The `js` jump means:

> jump if the sign flag is set

So this checks whether `rax` is negative.

If yes, the command prints:

```text
ttysize: ioctl TIOCGWINSZ failed
```

to stderr and exits failure.

On success, `ioctl` returns `0`, and the program continues.

The rule is:

| `rax` after `ioctl` | Meaning |
| ------------------- | ------- |
| `0`                 | success |
| negative            | failure |

This is the same negative-error convention seen in other syscall-based commands.

---

## Loading rows: `movzx`

After success, the program reads the row count:

```asm
movzx rax, word [winsize_buffer]
```

There are two details worth noticing.

First, it reads a `word`, which is 2 bytes.

That matches the `struct winsize` field size.

Second, it uses `movzx`.

`movzx` means:

```text
move with zero extension
```

The field is a small unsigned value. But the decimal printing helper expects the number in a larger register, `rax`.

So `movzx` loads the 16-bit value and fills the upper bits with zero.

That gives the printer a clean unsigned integer.

Conceptually:

```text
read 16-bit rows field
turn it into a 64-bit unsigned value
print it
```

That is the right move.

---

## Loading columns: offset `+2`

The column count is loaded with:

```asm
movzx rax, word [winsize_buffer + 2]
```

Why `+2`?

Because the first field, `ws_row`, is an unsigned short.

That is 2 bytes.

So the next field begins 2 bytes after the start of the struct.

The struct starts like this:

```text
offset 0: rows
offset 2: columns
```

This is the assembly version of reading fields from a struct.

There are no field names at runtime.

There is just:

```text
base address + offset
```

That is an important mental model.

A struct is memory with an agreed layout.

---

## Pixel dimensions are ignored

The source reserves room for four words:

```text
rows
columns
x pixels
y pixels
```

But the program only prints the first two.

That means it ignores:

```text
winsize_buffer + 4
winsize_buffer + 6
```

This is intentional.

Terminal row/column size is the common shell-facing information.

Pixel dimensions may be zero or less useful depending on terminal and environment.

For this teaching version, printing:

```text
rows columns
```

keeps the output direct and easy to test.

---

## Printing rows and columns

The output path is:

```text
print rows as decimal
print one space
print columns as decimal
print newline
```

So if your terminal is 40 rows by 120 columns, the output should look like:

```text
40 120
```

The fixed fragments live in `.rodata`:

```asm
space: db ' '
newline: db 10
```

Those are written as one-byte buffers.

The numbers use the decimal formatting helper.

That combination is common in these small tools:

| Output piece | How it is produced              |
| ------------ | ------------------------------- |
| number       | convert integer to decimal text |
| space        | write one fixed byte            |
| number       | convert integer to decimal text |
| newline      | write one fixed byte            |

No `printf`.

No format string.

Just small output pieces stitched together.

---

## Decimal printing works backwards

The helper:

```asm
write_unsigned_decimal_stdout
```

is the same kind of decimal printer used in other commands.

It starts at the end of `number_buffer`:

```asm
lea r8, [number_buffer + 20]
```

Then it repeatedly divides by 10.

Division gives the least-significant digit first.

For example:

```text
120 / 10 = 12 remainder 0
12  / 10 = 1  remainder 2
1   / 10 = 0  remainder 1
```

The digits arrive as:

```text
0, 2, 1
```

which is backwards.

So the helper stores digits from right to left in the temporary buffer.

By the time division is done, the pointer has moved left to the first digit, and the digits are in the correct order in memory.

That is a classic low-level number-formatting trick.

---

## Zero is special

The decimal helper checks:

```asm
test rax, rax
jnz .divide_loop
```

If the number is zero, it writes the character `'0'` directly.

That special case matters because the normal division loop would produce no digits for zero.

For terminal size, rows and columns should not normally be zero in a real terminal. But the helper is general enough to print zero correctly anyway.

That is good utility behavior.

A number printer should print `0`, not an empty string.

---

## The write helper is simple

The lower-level helper:

```asm
write_buffer_fd
```

does one `write(2)` syscall and checks:

```asm
cmp rax, rdx
jne .write_failed
```

That means:

> success only if the write returned exactly the requested byte count

For this command, writes are small:

* decimal row count
* one space
* decimal column count
* one newline
* short diagnostics

So this simple helper is reasonable.

A stream-copying command like `cat` deserves a full `write_all` loop.

Here, the teaching focus is `ioctl` and struct fields, not partial-write machinery.

---

## Diagnostics go to stderr

Normal output goes to stdout:

```text
rows columns
```

Error messages go to stderr.

That matters for redirection:

```sh
./build/ttysize > size.txt
```

If the command succeeds, `size.txt` should contain only the size line.

If it fails because stdin is not a terminal, the error should not be mixed into that output file.

The file uses fd `2` for those complaints.

Same habit as the other commands:

| fd  | Purpose             |
| --- | ------------------- |
| `1` | real command output |
| `2` | diagnostics         |

Tiny command, grown-up stream behavior.

---

## The failure case is expected sometimes

This command is a good reminder that not every syscall failure means the program is broken.

Try:

```sh
./build/ttysize
```

in a normal terminal.

Then try:

```sh
printf x | ./build/ttysize
```

The second form changes stdin.

Now fd `0` is a pipe.

A pipe does not have terminal window dimensions.

So `ioctl(TIOCGWINSZ)` can fail.

That is a correct failure.

This is a useful practical lesson:

> file descriptors are not all the same kind of thing

A syscall can make sense for one fd and fail for another.

`read(2)` works on lots of fd types.

`TIOCGWINSZ` only makes sense for terminal-like fds.

---

## Why this is not just `LINES` and `COLUMNS`

Some shells expose environment variables like:

```text
LINES
COLUMNS
```

But this command does not read those.

It asks the terminal device itself.

That difference matters.

Environment variables are strings inherited at process startup. They can be absent, stale, manually overridden, or not exported.

`ioctl(TIOCGWINSZ)` asks the device for its current window size.

So this command is closer to:

```text
what does the terminal report right now?
```

than:

```text
what strings did the shell give me?
```

That makes `ttysize` a nice contrast with `env` and `printenv`.

Those commands inspect inherited process text.

This one queries a live device property.

---

## What this file is quietly teaching

`ttysize.asm` teaches a compact set of low-level ideas:

| Concept                                | Where it appears                |
| -------------------------------------- | ------------------------------- |
| Argument rejection                     | `argc` check                    |
| Option-looking input detection         | `starts_with_dash`              |
| `ioctl(2)` syscall shape               | `rax = 16`                      |
| Device-specific request code           | `TIOCGWINSZ`                    |
| Passing an output buffer to the kernel | `winsize_buffer`                |
| Struct layout in memory                | four unsigned shorts            |
| Field offsets                          | rows at `+0`, columns at `+2`   |
| Zero-extending small fields            | `movzx`                         |
| Decimal number formatting              | `write_unsigned_decimal_stdout` |
| Fixed one-byte output                  | space and newline               |
| Expected syscall failure               | stdin is not a terminal         |
| stdout/stderr separation               | fd `1` vs fd `2`                |

That makes it a strong 00-level note.

It is small, but it opens the door to a whole category of interactions:

> not just reading and writing streams, but asking devices for control information

---

## Suggested experiments

Run it in a real terminal:

```sh
./build/ttysize
echo $?
```

Resize the terminal window and run it again:

```sh
./build/ttysize
```

Watch the row and column values change.

Redirect stdout:

```sh
./build/ttysize > size.txt
cat size.txt
```

Try it with stdin replaced by a pipe:

```sh
printf x | ./build/ttysize
echo $?
```

That should exercise the failure path.

Try an unsupported option:

```sh
./build/ttysize --help
echo $?
```

Try an unexpected operand:

```sh
./build/ttysize whatever
echo $?
```

The useful behavior map is:

| Command               | Expected idea                                 |
| --------------------- | --------------------------------------------- |
| `ttysize`             | query stdin terminal and print `rows columns` |
| `printf x \| ttysize` | fail because stdin is a pipe                  |
| `ttysize --help`      | unsupported option                            |
| `ttysize whatever`    | unexpected operand                            |

That covers the important branches.

---

## Takeaway

`ttysize.asm` is an `ioctl` lesson in a small package.

The program gives the kernel:

```text
fd 0
TIOCGWINSZ request code
pointer to a winsize buffer
```

Then, if the call succeeds, the buffer contains a tiny structure:

```text
rows
columns
x pixels
y pixels
```

The command reads the first two fields, prints them as decimal numbers, and exits.

That is the whole trick.

Earlier commands showed several different low-level patterns:

```text
write fixed bytes
walk argv
walk envp
read and scan streams
```

`ttysize` adds another one:

```text
pass a structure to the kernel and let the kernel fill it in
```

That is a big idea hiding inside a tiny utility.
