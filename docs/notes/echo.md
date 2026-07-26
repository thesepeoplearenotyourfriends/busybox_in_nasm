# Notes: `echo`

`echo` looks like it should be almost too simple to deserve a note.

Print the words.

Done.

But that simplicity is a little deceptive. This version teaches several useful assembly habits:

* reading `argc` and `argv`
* walking command-line operands
* recognizing one small supported option
* rejecting unsupported option-looking input
* printing separators between operands
* optionally printing a final newline
* measuring C strings before calling `write(2)`

So this is not really a “text output is easy” file.

It is a small command-line behavior lesson.

Keep `src/echo.asm` open beside this note. The interesting part is not that the program writes strings. The interesting part is how it decides which strings to write, where spaces belong, and whether the final newline should exist.

---

## What this command really does

At the shell level, `echo` feels like:

> print these words back to me

At the assembly level, this version does something more specific:

| Left pane: code idea                    | Right pane: human meaning                          |
| --------------------------------------- | -------------------------------------------------- |
| Read `argc` and `argv`                  | “What operands did the user provide?”              |
| Check for no operands                   | “Plain `echo` prints only a newline.”              |
| Check whether `argv[1]` is exactly `-n` | “Maybe suppress the trailing newline.”             |
| Reject other leading dash forms         | “Do not pretend unsupported options work.”         |
| Loop over printable operands            | “Write each word.”                                 |
| Print spaces between operands           | “Separate words, but do not add a trailing space.” |
| Maybe print newline                     | “Finish the normal `echo` line.”                   |
| Exit success or failure                 | “Report whether output worked.”                    |

That is the whole command.

The visible behavior is small, but the structure is very reusable.

---

## The deliberately narrow behavior

This implementation supports the recognizable simple form:

```sh
echo hello world
```

and:

```sh
echo -n hello world
```

It does not support escape interpretation:

```sh
echo -e 'hello\nworld'
```

It does not support repeated or combined `-n` forms like:

```sh
echo -nn hello
```

It does not support:

```sh
echo --help
echo --version
```

That is not an accident. `echo` is one of those commands where real-world implementations disagree about options and escape behavior. Shell builtins, GNU tools, BusyBox, and historical versions do not all behave exactly the same.

So this teaching version makes a good choice:

> implement the simple shape clearly, and reject unsupported leading options instead of guessing

That keeps the assembly readable and avoids quietly teaching fake compatibility.

---

## `_start`: command-line setup

The source begins with:

```asm
mov r12, [rsp]
lea r13, [rsp + 8]
mov r14, 1
mov r15, 1
```

Read those as:

| Register | Meaning                            |
| -------- | ---------------------------------- |
| `r12`    | `argc`, including the program name |
| `r13`    | pointer to the `argv` array        |
| `r14`    | index of the next operand to print |
| `r15`    | print-newline flag                 |

That last one is especially useful.

Instead of branching into two totally separate versions of the program, the code keeps a small flag:

| `r15` | Meaning                    |
| ----- | -------------------------- |
| `1`   | print the final newline    |
| `0`   | suppress the final newline |

That is exactly the kind of tiny state variable that makes command behavior manageable.

---

## No operands: print just a newline

The source checks:

```asm
cmp r12, 1
je .maybe_print_newline
```

Since `argc` includes `argv[0]`, `argc == 1` means the user gave no operands.

So:

```sh
echo
```

prints a newline.

That may sound too obvious, but it is a good example of command behavior being encoded directly:

```text
no operands -> maybe print newline -> exit
```

Because the newline flag starts as `1`, plain `echo` takes the newline path and exits successfully.

No words are needed.

The blank line is the output.

---

## `-n` is exactly `-n`

The first operand gets special attention.

The source loads `argv[1]` and calls:

```asm
is_dash_n
```

That helper checks three bytes:

```text
'-'
'n'
NUL
```

So the accepted option is exactly:

```text
-n
```

Not `-nn`.

Not `-ne`.

Not `--`.

Not `-nanything`.

Exactly two characters, then the string terminator.

That exactness is helpful. It keeps the teaching version honest and easy to inspect.

The helper is not doing general option parsing. It is answering one yes/no question:

> is this string exactly `-n`?

If yes, the program sets:

```asm
mov r15, 0
mov r14, 2
```

Meaning:

> do not print the final newline, and start printing operands after `-n`

So for:

```sh
echo -n hello world
```

the printable operands begin at `argv[2]`.

---

## Why unsupported options fail

If `argv[1]` is not `-n`, the program checks whether it starts with `-`.

That is the helper:

```asm
starts_with_dash
```

This helper only checks the first byte. If the first byte is `'-'`, the source treats it as an unsupported leading option.

So:

```sh
echo -e hello
```

does not print `-e hello`.

It produces an unsupported-option diagnostic and exits `1`.

That is a design choice.

Some `echo` implementations would treat `-e` as an option. Some would not. Some shells make it even murkier.

This teaching version chooses clarity:

> only `-n` is supported; other leading dash options are rejected

That way, the program does not accidentally suggest it is compatible with a wider `echo` world than it really is.

---

## `r14`: the current operand index

Once option handling is done, the loop uses `r14` as the current `argv` index.

At first:

| Situation           |  Starting `r14` |
| ------------------- | --------------: |
| normal `echo hello` |             `1` |
| `echo -n hello`     |             `2` |
| plain `echo`        | no operand loop |

The loop compares:

```asm
cmp r14, r12
```

That asks:

> have we reached `argc` yet?

If `r14 >= argc`, there are no more operands to print.

This is the low-level version of:

```c
while (i < argc) {
    print(argv[i]);
    i++;
}
```

Assembly just makes the index and pointer arithmetic visible.

---

## `argv` is an array of pointers

The operand load is:

```asm
mov rsi, [r13 + r14*8]
```

That means:

> load `argv[r14]`

The `*8` is there because this is 64-bit code, and each pointer is 8 bytes.

So if `r13` points at `argv[0]`, then:

| Expression      | Meaning     |
| --------------- | ----------- |
| `[r13 + 0]`     | `argv[0]`   |
| `[r13 + 8]`     | `argv[1]`   |
| `[r13 + 16]`    | `argv[2]`   |
| `[r13 + r14*8]` | `argv[r14]` |

This is a useful place to remember that `argv` does not hold the text inline.

It holds pointers to text.

The loop loads a pointer, then passes that pointer to the string-writing helper.

---

## Printing operands

Each operand is a NUL-terminated string.

The loop calls:

```asm
write_c_string_stdout
```

That helper writes the current operand to fd `1`, stdout.

So for:

```sh
echo hello world
```

the first loop iteration writes:

```text
hello
```

Then the second loop iteration writes:

```text
world
```

The loop itself does not add quotes, escaping, or interpretation.

By the time the program receives `argv`, the shell has already done its own parsing. This `echo` sees an array of strings.

It prints those strings.

That is the boundary:

| Shell’s job                          | This program’s job     |
| ------------------------------------ | ---------------------- |
| split command line into arguments    | walk `argv`            |
| remove shell quotes                  | print received strings |
| expand variables/globs if applicable | not involved           |

That helps keep expectations sane.

---

## Spaces go between operands

The source prints a space only after confirming there is another operand still to come.

The shape is:

```text
print operand
advance index
if no more operands:
    maybe newline
else:
    print one space
    continue loop
```

That avoids a trailing space.

For:

```sh
echo one two three
```

the output should be:

```text
one two three\n
```

Not:

```text
one two three \n
```

The difference is tiny, but the control flow matters.

This is one of those details that makes a command feel normal instead of slightly wrong.

The program is not “print every operand and always print a space.” It is:

> print spaces as separators

Separators belong between things, not after the last thing.

---

## The newline flag

After all operands are printed, execution reaches:

```asm
.maybe_print_newline
```

That block checks `r15`.

If `r15` is zero, the program exits successfully without printing a newline.

If `r15` is one, it writes one newline byte to stdout.

So:

```sh
echo hello
```

prints:

```text
hello\n
```

But:

```sh
echo -n hello
```

prints:

```text
hello
```

This is a clean little use of a flag. The operand loop does not need to know much about `-n`. It just prints operands and then lets the newline decision happen at the end.

That is a good habit:

> handle a small option once, store its effect, and let the main path stay simple

---

## The data section is tiny

The `.rodata` section contains:

```asm
space:   db " "
newline: db 10
```

Those are the two fixed output fragments.

A space is byte `32`.

A newline is byte `10`.

The program writes both using the lower-level buffer helper because they are not NUL-terminated strings in the same way as the diagnostic messages.

For those one-byte outputs, the source passes:

| Register | Meaning             |
| -------- | ------------------- |
| `rsi`    | address of the byte |
| `rdx`    | length, `1`         |
| `rdi`    | output fd           |

That is the simplest pointer-plus-length case possible:

> write this one byte

---

## Diagnostic messages are C strings

The error messages are different.

They are stored as NUL-terminated strings:

```asm
unsupported_prefix: db "echo: unsupported option: ", 0
supported_msg:      db "echo: this teaching version currently supports: -n", 10, 0
```

Those are meant for the `write_c_string_*` helpers.

So this file uses two nearby string styles:

| Style                   | Example            | How it is written                |
| ----------------------- | ------------------ | -------------------------------- |
| known one-byte fragment | `space`, `newline` | pass pointer and length directly |
| NUL-terminated message  | diagnostic strings | measure first, then write        |

That contrast is useful.

Assembly does not have one universal “string” concept. The program chooses a representation, then must use the right helper for that representation.

---

## Measuring a C string

The helper:

```asm
write_c_string_fd
```

receives:

| Register | Meaning                          |
| -------- | -------------------------------- |
| `rdi`    | file descriptor                  |
| `rsi`    | pointer to NUL-terminated string |

But `write(2)` needs:

```text
fd, pointer, byte count
```

So the helper counts bytes until it finds the NUL terminator.

Conceptually:

```text
length = 0

while string[length] != 0:
    length += 1
```

Once it knows the length, it calls:

```asm
write_buffer_fd
```

This is the recurring conversion:

```text
C string -> pointer plus length
```

That conversion shows up everywhere in these small commands.

---

## stdout versus stderr

Normal output goes to stdout, fd `1`.

Unsupported-option diagnostics go to stderr, fd `2`.

That means this:

```sh
./build/echo hello > out.txt
```

puts `hello` in the file.

But this:

```sh
./build/echo -e hello > out.txt
```

should not put the error message in `out.txt`.

The complaint belongs to stderr.

This separation is part of what makes command-line tools composable:

| fd         | Purpose                   |
| ---------- | ------------------------- |
| `1` stdout | the command’s real output |
| `2` stderr | diagnostics               |

Even a tiny command benefits from learning that habit early.

---

## The write helper is simple on purpose

The helper:

```asm
write_buffer_fd
```

does one `write(2)` syscall and checks whether the returned byte count matches the requested byte count.

If not, it reports failure.

This is simpler than the full `write_all` helper used in stream-heavy commands like `cat`.

For `echo`, most writes are tiny:

* one operand string
* one space
* one newline
* short diagnostics

A full partial-write loop would be more robust, but also more code.

This version chooses the small teaching shape:

```text
ask write to write N bytes
success only if it wrote exactly N
```

That keeps attention on argv walking and output layout, not stream robustness.

---

## Success and failure

The success path exits with status `0`.

The failure path exits with status `1`.

Failure can come from:

* unsupported leading option
* failed stdout write
* failed stderr write

The program does not decode errno.

It does not print a second-level error about the diagnostic failing.

It keeps the rule simple:

| Result                             | Exit status |
| ---------------------------------- | ----------- |
| output completed                   | `0`         |
| unsupported input or write failure | `1`         |

That is enough for this teaching version.

---

## What this file is quietly teaching

`echo.asm` teaches several small but reusable command-writing ideas:

| Concept                        | Where it appears             |
| ------------------------------ | ---------------------------- |
| Raw startup argument access    | `argc` and `argv` setup      |
| Operand index tracking         | `r14`                        |
| Small option handling          | exact `-n` check             |
| Unsupported option rejection   | leading dash check           |
| Flag-controlled final behavior | `r15` newline flag           |
| Pointer-array indexing         | `[r13 + r14*8]`              |
| C-string measurement           | `write_c_string_fd`          |
| Separator logic                | spaces only between operands |
| One-byte fixed output          | `space`, `newline`           |
| stdout/stderr split            | fd `1` vs fd `2`             |
| Honest exit status             | `0` or `1`                   |

That makes it more valuable than it first appears.

A tiny `echo` still has to make real command-line decisions.

---

## Suggested experiments

Plain newline:

```sh
./build/echo
echo $?
```

Basic operands:

```sh
./build/echo hello world
```

Suppress the newline:

```sh
./build/echo -n hello
printf '<END>\n'
```

The `<END>` marker should appear immediately after `hello`.

Multiple operands with `-n`:

```sh
./build/echo -n one two three
printf '<END>\n'
```

Unsupported escape-style option:

```sh
./build/echo -e hello
echo $?
```

Unsupported long option:

```sh
./build/echo --help
echo $?
```

Literal dash later in the operand list:

```sh
./build/echo hello -e world
```

That last one is worth noticing.

This implementation only treats a leading first operand as an option candidate. Once printing starts, later operands are just operands.

So `-e` after `hello` is printed as text.

That keeps option handling narrow and predictable.

---

## Takeaway

`echo.asm` is an argv-walking lesson disguised as the simplest possible output command.

The program starts with raw process startup data:

```text
argc
argv pointer array
```

Then it makes a few small decisions:

```text
is there a supported -n?
is there an unsupported leading option?
which operand should printing start with?
should the final newline be printed?
```

After that, it does the visible job:

```text
print operand
print separator if another operand exists
repeat
maybe print newline
```

That is not complicated, but it is foundational.

A lot of command-line tools start this way: inspect the first few operands, set a flag or two, then walk the rest.

`echo` is a small enough place to see that pattern without getting buried under file I/O, buffers, or parsing machinery.
