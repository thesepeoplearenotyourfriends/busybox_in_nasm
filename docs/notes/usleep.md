# Notes: `usleep`

`usleep` is a nice step up from the pure “write these bytes and exit” commands.

It still has a small job:

> sleep for a number of microseconds

But getting there requires several new ideas:

* reading an argument from `argv`
* rejecting missing, extra, invalid, or option-looking input
* parsing decimal text into an integer
* converting microseconds into seconds plus nanoseconds
* building a `timespec` structure for the kernel
* calling `nanosleep(2)`

That makes this a good early example of a command that has to translate between three worlds:

| World            | Example                               |
| ---------------- | ------------------------------------- |
| user text        | `"250000"`                            |
| program number   | `250000` microseconds                 |
| kernel structure | `{ tv_sec = 0, tv_nsec = 250000000 }` |

Keep `src/usleep.asm` open beside this note. The source is doing several small jobs in sequence, and the trick is to see each one separately.

---

## What this command really does

At the shell level, you type something like:

```sh
usleep 500000
```

and expect the program to pause for half a second.

At the assembly level, this version does something more mechanical:

| Left pane: code idea         | Right pane: human meaning                            |
| ---------------------------- | ---------------------------------------------------- |
| Check `argc`                 | “Did the user provide exactly one operand?”          |
| Reject leading `-`           | “This teaching version does not support options.”    |
| Parse decimal digits         | “Turn text into a number.”                           |
| Divide by `1,000,000`        | “Separate whole seconds from leftover microseconds.” |
| Multiply leftovers by `1000` | “Convert microseconds into nanoseconds.”             |
| Store two 64-bit values      | “Build a Linux `timespec`.”                          |
| Call `nanosleep(2)`          | “Ask the kernel to sleep.”                           |
| Exit `0` or `1`              | “Report success or failure.”                         |

That is the whole shape.

The interesting part is not sleeping.

The interesting part is the translation path from command-line text to kernel-facing data.

---

## Why `usleep` uses `nanosleep`

The source comments point out that this version uses `nanosleep(2)` so the conversion from microseconds to a Linux `timespec` is visible.

That is a good teaching choice.

There is not a magic “sleep microseconds” syscall here. The program receives microseconds from the user, but the kernel call wants a structure with:

```text
seconds
nanoseconds
```

So the program has to convert:

```text
total microseconds
```

into:

```text
whole seconds + leftover nanoseconds
```

That sounds like a tiny detail, but it is very assembly-relevant. Low-level programming is often about satisfying the exact shape an interface expects.

Not the shape you wish it accepted.

The shape it actually accepts.

---

## `_start`: first, find `argc` and `argv`

The program begins by loading:

```asm
mov r12, [rsp]
lea r13, [rsp + 8]
```

Read that as:

| Register | Meaning                          |
| -------- | -------------------------------- |
| `r12`    | `argc`                           |
| `r13`    | base of the `argv` pointer array |

At raw process startup, there is no friendly `main(argc, argv)` function being called for you.

The startup stack already contains that information, and this program reads it directly.

So the usual C shape:

```c
int main(int argc, char **argv)
```

becomes something more literal:

```text
argc is at [rsp]
argv begins at [rsp + 8]
```

This is one of the pleasures of these tiny assembly commands: normal abstractions are peeled back just enough to see the hardware-facing arrangement.

---

## Exactly one operand

The first real check is:

```asm
cmp r12, 2
jb .missing_operand
ja .unexpected_extra
```

Remember that `argc` includes the program name.

So for:

```sh
usleep 500000
```

the entries are:

| argv entry | Meaning      |
| ---------- | ------------ |
| `argv[0]`  | program name |
| `argv[1]`  | `500000`     |

That means `argc` should be `2`.

The code says:

| Condition   | Meaning         |
| ----------- | --------------- |
| below `2`   | missing operand |
| above `2`   | extra operand   |
| exactly `2` | continue        |

This is a small but useful command-line parsing pattern. The program narrows the allowed shape before doing any deeper work.

It refuses to guess.

---

## Why option-looking input is rejected early

After confirming that there is one operand, the source checks whether it starts with `-`.

That is done by:

```asm
call starts_with_dash
```

This teaching version supports no options, so something like:

```sh
usleep -h
```

does not mean help.

And something like:

```sh
usleep -5
```

does not mean negative sleep.

Both are rejected as unsupported option-looking input.

That keeps the parser simple and honest:

> the only accepted operand is unsigned decimal microseconds

No suffixes.

No fractions.

No flags.

No negative values.

That narrowness is not a flaw here. It keeps the file focused on the lesson.

---

## Loading `argv[1]`

The source gets the operand pointer with:

```asm
mov rsi, [r13 + 8]
```

Since `r13` points at the beginning of the `argv` array, this means:

```text
load argv[1]
```

Why `+ 8`?

Because this is 64-bit code, and each pointer is 8 bytes.

So the array looks like:

```text
r13 + 0   -> argv[0]
r13 + 8   -> argv[1]
r13 + 16  -> argv[2]
```

Again, assembly makes the hidden arithmetic visible.

In C, `argv[1]` feels like a language feature.

Here, it is simply:

> base address plus one pointer-sized slot

---

## Parsing decimal text

The helper:

```asm
parse_unsigned_decimal
```

turns a string like:

```text
"12345"
```

into the integer:

```text
12345
```

It returns:

| Register | Meaning                        |
| -------- | ------------------------------ |
| `rax`    | parsed value                   |
| `rdx`    | status: `0` valid, `1` invalid |

That return shape is worth noticing. Since this parser wants to return both a number and a success/failure flag, it uses two registers.

No object.

No exception.

No hidden result wrapper.

Just:

```text
rax = useful value
rdx = did it work?
```

The caller then does:

```asm
test rdx, rdx
jnz .invalid_operand
```

Meaning:

> if the status is nonzero, reject the operand

---

## Empty strings are invalid

The parser begins by checking:

```asm
cmp byte [rsi], 0
je .invalid
```

That says:

> if the first byte is NUL, the string is empty

An empty string is not a valid decimal number.

You may not hit that easily from a normal shell, but the parser still treats it correctly. That is a good habit: define what counts as valid input, then reject everything else.

For this command, valid means:

```text
one or more decimal digits
```

So the empty string fails before the loop even starts.

---

## Digit checking: byte by byte

Inside the parse loop, the code loads one byte:

```asm
mov bl, [rsi]
```

Then checks whether it is the string terminator:

```asm
test bl, bl
jz .done
```

If it is not the end, the parser checks:

```asm
cmp bl, '0'
jb .invalid
cmp bl, '9'
ja .invalid
```

That is the entire digit test.

ASCII digits are ordered. So if the byte is below `'0'` or above `'9'`, it is not a decimal digit.

This is one of those simple byte-level facts that makes parsing feel much less mysterious.

A string is not being “understood” all at once.

The program is asking each byte:

> are you a digit?

If yes, fold it into the number.

If no, reject the whole operand.

---

## The decimal folding trick

The core parse step is:

```asm
imul rax, rax, 10
sub bl, '0'
movzx rbx, bl
add rax, rbx
```

Read that as:

```text
old_value = old_value * 10
digit_value = current_character - '0'
new_value = old_value + digit_value
```

So parsing `"123"` goes like:

| Character | Previous value | New value |
| --------- | -------------: | --------: |
| `'1'`     |            `0` |       `1` |
| `'2'`     |            `1` |      `12` |
| `'3'`     |           `12` |     `123` |

That is the normal base-10 parser, written without any library help.

The line:

```asm
sub bl, '0'
```

is the tiny conversion from ASCII character to numeric digit.

The byte for `'7'` is not the number `7`.

But:

```text
'7' - '0' = 7
```

That one subtraction is the bridge from text to value.

---

## Overflow is intentionally not handled here

The source comments say extremely large values are not checked for integer overflow while parsing.

That means this parser is not trying to be bulletproof against every giant input.

For a teaching utility, that is a reasonable boundary.

Handling overflow correctly would be another lesson:

* compare before multiplying
* detect carry or overflow
* reject values too large for the chosen representation
* maybe clamp or report a better diagnostic

Useful, but distracting here.

This file’s main parser lesson is:

> walk decimal bytes and accumulate a number

Not:

> build a production-grade numeric parser

That distinction keeps the code readable.

---

## Microseconds are not what `nanosleep` wants

After parsing, `rax` contains total microseconds.

But `nanosleep` wants a `timespec`.

Conceptually:

```c
struct timespec {
    time_t tv_sec;
    long   tv_nsec;
};
```

This program reserves two 64-bit slots:

```asm
request_timespec: resq 2
remaining_timespec: resq 2
```

For this teaching version, the important one is `request_timespec`.

It will hold:

| Offset                 | Meaning     |
| ---------------------- | ----------- |
| `request_timespec + 0` | seconds     |
| `request_timespec + 8` | nanoseconds |

So the program has to split the user’s microseconds into those two fields.

---

## Dividing by one million

This block does the conversion:

```asm
xor rdx, rdx
mov rbx, 1000000
div rbx
```

The source comment gives the key result:

```text
rax = seconds
rdx = leftover microseconds
```

The `div` instruction is one of those instructions that uses specific registers implicitly.

For unsigned 64-bit division, it divides the combined value in:

```text
rdx:rax
```

by the operand.

That is why the code clears `rdx` first.

Before the division:

| Register | Meaning                                |
| -------- | -------------------------------------- |
| `rax`    | total microseconds                     |
| `rdx`    | high half of dividend, cleared to zero |
| `rbx`    | divisor, `1,000,000`                   |

After the division:

| Register | Meaning               |
| -------- | --------------------- |
| `rax`    | whole seconds         |
| `rdx`    | leftover microseconds |

Example:

```text
2,500,123 microseconds / 1,000,000
```

becomes:

| Part                  |    Value |
| --------------------- | -------: |
| seconds               |      `2` |
| leftover microseconds | `500123` |

That is exactly the split needed before converting the leftover piece to nanoseconds.

---

## Storing the seconds

Right after the divide:

```asm
mov [request_timespec], rax
```

stores the whole seconds field.

At this moment:

```text
request_timespec.tv_sec = rax
```

In assembly, there is no visible field name like `.tv_sec`.

There is only the address of the structure and an offset.

For the first field, the offset is zero, so:

```asm
[request_timespec]
```

is enough.

This is a good first taste of structs at assembly level:

> a struct is memory laid out in an agreed order

No magic container.

Just slots.

---

## Converting leftover microseconds to nanoseconds

The leftover microseconds are still in `rdx`.

`nanosleep` does not want microseconds in the second field. It wants nanoseconds.

Since:

```text
1 microsecond = 1000 nanoseconds
```

the source does:

```asm
imul rdx, rdx, 1000
mov [request_timespec + 8], rdx
```

That writes the nanosecond field.

So if the user entered:

```text
2500000
```

the conversion becomes:

| Field                 |       Value |
| --------------------- | ----------: |
| seconds               |         `2` |
| leftover microseconds |    `500000` |
| nanoseconds           | `500000000` |

And the resulting request is:

```text
sleep 2 seconds and 500,000,000 nanoseconds
```

Which is 2.5 seconds.

The important bit is that the kernel interface decides the representation.

The command accepts microseconds.

The syscall wants seconds plus nanoseconds.

The program is the adapter.

---

## Why `remaining_timespec` exists

The source also reserves:

```asm
remaining_timespec: resq 2
```

and passes its address as the second argument to `nanosleep`.

That second pointer is where the kernel can write the remaining unslept time if the sleep is interrupted.

This teaching version does not implement a restart loop, so it does not use that remaining time to continue sleeping. The comments say signal-aware restart loops are intentionally unsupported.

Still, passing a real buffer makes the syscall shape visible:

| Argument | Meaning                                      |
| -------- | -------------------------------------------- |
| `req`    | requested sleep duration                     |
| `rem`    | place to store remaining time if interrupted |

That is another useful low-level habit:

> sometimes a syscall argument is not just input; it is a pointer where the kernel may write output

---

## The `nanosleep` syscall

The syscall setup is:

```asm
mov rax, 35
lea rdi, [request_timespec]
lea rsi, [remaining_timespec]
syscall
```

Read it as:

| Register | Meaning                              |
| -------- | ------------------------------------ |
| `rax`    | syscall number: `nanosleep`          |
| `rdi`    | pointer to requested `timespec`      |
| `rsi`    | pointer to remaining-time `timespec` |

The two `lea` instructions are important.

They pass addresses.

The kernel does not want the seconds value directly in `rdi`.

It wants a pointer to a memory structure containing the seconds and nanoseconds fields.

So:

```asm
lea rdi, [request_timespec]
```

means:

> the request structure starts here

This is a slightly richer version of the pointer-plus-length idea from `write`.

With `write`, the kernel receives a pointer to bytes and a byte count.

With `nanosleep`, the kernel receives a pointer to a structure with a known layout.

Different interface, same general rule:

> put the expected thing in memory, then pass the address

---

## Checking the syscall result

After `nanosleep`, the source does:

```asm
test rax, rax
js .nanosleep_failed
```

The `js` instruction jumps if the sign flag is set.

Linux syscalls usually report errors as negative return values.

So this says:

> if `rax` is negative, the syscall failed

On success, `nanosleep` returns zero.

This version does not decode errno values. It just prints a short failure message and exits `1`.

That is enough for this teaching pass.

The lesson is:

| Return value | Meaning         |
| ------------ | --------------- |
| `0`          | sleep completed |
| negative     | syscall failed  |

---

## The error paths are repetitive on purpose

The source has separate paths for:

* missing operand
* extra operand
* unsupported option
* invalid decimal input
* nanosleep failure

Several of those paths write a prefix, then the offending operand, then a suffix.

That may look repetitive, but for this level it is a virtue.

You can see each error case plainly.

There is no clever diagnostic framework hiding the basic steps:

```text
write message to stderr
exit failure
```

For assembly learning, obvious beats fancy most of the time.

The pattern is:

| Step                         | Meaning                          |
| ---------------------------- | -------------------------------- |
| put message pointer in `rsi` | choose what to print             |
| put `2` in `rdi`             | choose stderr                    |
| call `write_c_string_fd`     | write the NUL-terminated message |
| jump to `.exit_failure`      | leave with status `1`            |

That is boilerplate, but it is useful boilerplate.

---

## `write_c_string_fd`: turning C strings into write calls

The diagnostic strings are NUL-terminated.

But `write(2)` does not know about NUL-terminated strings.

It wants:

```text
fd, pointer, byte count
```

So the helper:

```asm
write_c_string_fd
```

counts bytes until it finds `0`.

Then it calls:

```asm
write_buffer_fd
```

This is the same bridge seen in other commands:

| Human/program convenience | Kernel requirement  |
| ------------------------- | ------------------- |
| NUL-terminated message    | pointer plus length |

The helper turns one representation into the other.

That is a recurring theme in assembly:

> the program spends a lot of time converting from convenient shapes into syscall-shaped shapes

---

## `write_buffer_fd`: short writes are failure here

The `write_buffer_fd` helper calls `write(2)` and then compares:

```asm
cmp rax, rdx
jne .write_failed
```

That means this teaching version expects the whole message to be written in one go.

For diagnostics this small, that is usually fine.

A more robust stream-writing helper would loop until every byte has been written, like the bigger `cat` implementation does.

Here, keeping the helper short is reasonable because it supports error messages, not large data copying.

That difference is worth noticing:

| Situation        | Helper style                            |
| ---------------- | --------------------------------------- |
| tiny diagnostics | one write, treat short write as failure |
| stream copying   | loop until all bytes are written        |

Same syscall.

Different level of care depending on the job.

---

## Success and failure exits

The ending is simple:

```asm
.exit_success:
    exit 0

.exit_failure:
    exit 1
```

At shell level:

| Exit status | Meaning                            |
| ----------- | ---------------------------------- |
| `0`         | operand parsed and sleep completed |
| `1`         | bad input or syscall failure       |

The program does not return from `_start`.

It must tell the kernel the process is done.

That is why both paths use the `exit(2)` syscall directly.

---

## What this file is quietly teaching

`usleep.asm` teaches a dense little cluster of useful low-level ideas:

| Concept                                 | Where it appears                           |
| --------------------------------------- | ------------------------------------------ |
| Startup stack argument access           | `argc` / `argv` setup                      |
| Exact operand count checking            | `cmp r12, 2`                               |
| Option-looking input rejection          | `starts_with_dash`                         |
| Byte-by-byte decimal parsing            | `parse_unsigned_decimal`                   |
| ASCII digit to numeric digit conversion | `sub bl, '0'`                              |
| Base-10 accumulation                    | `value = value * 10 + digit`               |
| Unsigned division                       | `div rbx`                                  |
| Quotient and remainder use              | `rax` seconds, `rdx` leftover microseconds |
| Unit conversion                         | microseconds to nanoseconds                |
| Struct layout in memory                 | `request_timespec`                         |
| Passing pointers to syscalls            | `lea rdi`, `lea rsi`                       |
| Negative syscall error checks           | `js .nanosleep_failed`                     |
| stderr diagnostics                      | fd `2`                                     |

That is why this command deserves a note.

It is still small, but it touches several ideas that come back constantly.

---

## Suggested experiments

Try a tiny sleep:

```sh
./build/usleep 1
echo $?
```

Try zero:

```sh
./build/usleep 0
echo $?
```

This should still call `nanosleep`, but return immediately.

Try half a second:

```sh
time ./build/usleep 500000
```

Try one and a half seconds:

```sh
time ./build/usleep 1500000
```

That one is good because it exercises both fields:

```text
1 second
500,000,000 nanoseconds
```

Try invalid input:

```sh
./build/usleep abc
echo $?
```

Try an option-looking argument:

```sh
./build/usleep -h
echo $?
```

Try too many operands:

```sh
./build/usleep 1 2
echo $?
```

The important thing to observe is not only whether it sleeps.

Watch the shape of the behavior:

| Input    | Expected path                                      |
| -------- | -------------------------------------------------- |
| `500000` | parse, convert, sleep, exit `0`                    |
| `0`      | parse, convert to zero timespec, syscall, exit `0` |
| `abc`    | invalid decimal, exit `1`                          |
| `-h`     | unsupported option, exit `1`                       |
| `1 2`    | unexpected extra operand, exit `1`                 |

That gives you a small test map for the source.

---

## Takeaway

`usleep.asm` is an adapter lesson.

The user gives the program text:

```text
"500000"
```

The parser turns that text into a number:

```text
500000 microseconds
```

The conversion code reshapes that number into a kernel structure:

```text
0 seconds
500000000 nanoseconds
```

Then the syscall receives a pointer to that structure.

That is a very assembly-shaped journey.

A lot of low-level programming is not mysterious wizardry. It is careful translation:

```text
text -> number -> fields in memory -> syscall
```

Once that path feels normal, many other commands become easier to read. They may parse different text, build different structures, or call different syscalls, but the underlying job is often the same:

> take the user’s loose command-line request and turn it into the exact bytes and registers the kernel expects.
