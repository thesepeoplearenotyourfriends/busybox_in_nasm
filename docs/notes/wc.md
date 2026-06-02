# Notes: `wc`

`wc` is a great next step after `cat`.

`cat` moves bytes.

`wc` watches bytes.

That is the key difference. The program still reads input in chunks, still deals with file descriptors, still loops until EOF, and still writes results to stdout. But instead of passing the input bytes along unchanged, it studies them and updates counters.

That makes this command a small but important shift:

> from stream copying to stream scanning

Keep `src/wc.asm` open beside this note. The file is longer than the earlier tiny commands, but it has a clean shape once you know what each region is responsible for.

---

## What this command really does

At the shell level, `wc` feels like:

> tell me how many lines, words, and bytes are in this input

At the assembly level, this version does something more explicit:

| Left pane: code idea                    | Right pane: human meaning                           |
| --------------------------------------- | --------------------------------------------------- |
| Read from stdin or open each named file | “Choose the input stream.”                          |
| Reuse a fixed buffer                    | “Read one chunk at a time.”                         |
| Count bytes returned by `read(2)`       | “Every byte read counts as a byte.”                 |
| Scan each byte                          | “Look for newlines and word boundaries.”            |
| Track whether we are inside a word      | “Only count a word when it starts.”                 |
| Print three decimal numbers             | “Show lines, words, and bytes.”                     |
| Add per-file counts into totals         | “If there are multiple files, print a final total.” |

That is the core program.

Not “load a file and analyze it.”

More like:

```text
read chunk
scan bytes in chunk
update counters
repeat until EOF
print counters
```

That loop shape is extremely reusable.

---

## What is intentionally missing

This teaching version keeps the surface small.

It does not implement:

```text
-l
-w
-c
-m
-L
--help
--version
```

It also does not implement the conventional `-` operand for stdin in the file list.

That is fine for this stage. Options would add command-line parsing complexity, but the heart of `wc` is not option parsing.

The heart is the scanner.

This file is here to teach:

> how a program can count meaning while reading raw bytes

That is enough.

---

## The three counters

The command tracks three current counters:

```text
current_lines
current_words
current_bytes
```

And three total counters:

```text
total_lines
total_words
total_bytes
```

That split matters.

For one file, the current counters are the answer.

For multiple files, each file gets its own current counters, and then those get added to the totals.

So the program has two different scopes:

| Counter group | Meaning                                              |
| ------------- | ---------------------------------------------------- |
| `current_*`   | counts for the input currently being scanned         |
| `total_*`     | accumulated counts across successfully counted files |

This is a clean design choice. It keeps the scanner focused on one input at a time, and lets the file loop worry about totals.

---

## The no-operand path

When there are no file operands, `wc` reads from stdin.

The source checks whether `argc` is `1`.

Remember:

| Value      | Meaning                     |
| ---------- | --------------------------- |
| `argc = 1` | only `argv[0]`; no operands |
| `argc > 1` | one or more pathnames       |

For no operands, the program uses fd `0`, which is stdin.

That means this works:

```sh
printf 'one two\nthree\n' | ./build/wc
```

The command does not need to know where stdin came from.

It could be your keyboard.

It could be a pipe.

It could be redirected from a file.

As far as this program is concerned, fd `0` is just an input stream.

---

## The named-file path

With file operands, the program loops over `argv[1]`, `argv[2]`, and so on.

Each pathname goes through the same rough lifecycle:

```text
open file
count fd
close file
add current counts to total
print line for that file
move to next operand
```

That is the classic file-descriptor pattern again:

```text
pathname -> fd -> read loop -> close
```

By this point in the repo, that should start feeling familiar.

A pathname is text.

A file descriptor is the small integer handle the kernel returns after a successful `open`.

Once the file is open, the scanner does not care what the pathname was. It only needs the fd.

---

## Why failed files do not stop the whole command

If an open fails, this version prints a short diagnostic, marks the final status as failure, and moves on to the next file.

That behavior is practical.

For example:

```sh
./build/wc good.txt missing.txt also-good.txt
```

A useful command should still count the files it can read.

But it should not exit with success if one of the requested files failed.

That is why the program keeps an accumulated status register.

At the end:

| Status | Meaning                      |
| ------ | ---------------------------- |
| `0`    | all requested work succeeded |
| `1`    | at least one thing failed    |

This is the same “keep working, but do not lie” pattern from `cat`.

---

## `count_fd`: the center of the program

The most important helper is:

```text
count_fd
```

It receives an input fd and updates the current counters.

That helper is where `wc` becomes `wc`.

The read loop asks the kernel for up to `BUFFER_SIZE` bytes at a time. The buffer size is 4096 bytes, but the number actually read may be smaller.

So the program always has to keep two facts separate:

| Fact            | Meaning                            |
| --------------- | ---------------------------------- |
| buffer capacity | how much space the buffer has      |
| read result     | how many bytes are valid this time |

That second value is the one returned in `rax` by `read(2)`.

If `read` returns a positive number, those bytes are scanned.

If it returns zero, that means EOF.

If it returns a negative value, that means read failure.

---

## Bytes are counted by `read`, not by the scanner

After a successful read, the program does:

```text
current_bytes += bytes_read
```

That is a nice detail.

The byte count does not need clever classification.

If `read(2)` returned 137 bytes, then 137 bytes were read. They all count as bytes.

The scanner still needs to inspect each byte for lines and words, but byte-counting itself is simple:

> add the chunk length

This is a good reminder that not all counters are equally complicated.

| Counter | How it is updated                 |
| ------- | --------------------------------- |
| bytes   | add the number returned by `read` |
| lines   | inspect each byte for newline     |
| words   | inspect whitespace transitions    |

The word count is the interesting one.

---

## Lines: count newline bytes

Line counting is the simplest scan rule:

> every byte equal to `10` counts as a newline

ASCII byte `10` is line feed, usually written as `\n`.

So the source checks the current byte against `10`.

If it matches, it increments:

```text
current_lines
```

This means `wc` is not counting “visual lines on screen.”

It is counting newline bytes in the input.

That distinction matters. A file that does not end with a newline can have text in it, but fewer newline bytes than you might casually expect.

At this level, the rule is plain:

```text
line count = number of LF bytes seen
```

---

## Words require state

Word counting is the reason this file deserves a note.

A word is not counted by looking at one byte alone.

The program needs to know whether the previous byte left us inside a word.

That is what `bl` is doing.

| `bl` value | Meaning                  |
| ---------- | ------------------------ |
| `0`        | currently outside a word |
| `1`        | currently inside a word  |

The rule is:

```text
if current byte is whitespace:
    we are now outside a word

if current byte is not whitespace:
    if we were outside a word:
        this byte starts a new word
        increment word count
    we are now inside a word
```

That is the whole word-counting state machine.

Not fancy.

Very important.

---

## The word starts at the transition

The key idea is that a word is counted when the scanner crosses this boundary:

```text
whitespace -> non-whitespace
```

Or, at the very beginning of input:

```text
start of file -> non-whitespace
```

That means this input:

```text
hello world
```

does not count every letter.

It counts:

```text
h starts word 1
w starts word 2
```

The rest of the letters are inside already-counted words.

That is why the “inside word” flag matters.

Without it, the program would either undercount or wildly overcount.

---

## The flag survives across chunks

This is easy to miss, but important.

The input is read in chunks.

A word can cross a buffer boundary.

Imagine the buffer ends after:

```text
hel
```

and the next read begins with:

```text
lo
```

That is still one word: `hello`.

The scanner’s `inside word` flag must survive from one chunk to the next.

That is why `bl` is initialized once at the start of `count_fd`, then maintained across the read loop.

The counters include earlier chunks.

The flag remembers the word state from the previous byte, even if that byte came from a previous read.

That is the difference between a correct stream scanner and a scanner that only works accidentally on small inputs.

---

## What counts as whitespace

The helper:

```text
is_space_byte
```

classifies a byte as a word separator.

This version treats these as whitespace:

```text
space
tab
newline
vertical tab
form feed
carriage return
```

In byte terms, that is:

```text
' '
9 through 13
```

The code uses comparisons rather than a lookup table.

The idea is:

| Byte  | Meaning         |
| ----- | --------------- |
| `' '` | ordinary space  |
| `9`   | tab             |
| `10`  | newline         |
| `11`  | vertical tab    |
| `12`  | form feed       |
| `13`  | carriage return |

For this `wc`, all of those end the current word.

Everything else is treated as a non-space byte.

That is a simple ASCII-oriented rule. It is not Unicode-aware, and it is not trying to be.

---

## The scanner loop

The chunk scanner uses an index into the buffer.

Conceptually:

```text
r10 = 0

while r10 < bytes_read:
    al = buffer[r10]
    update line count
    update word state
    r10 += 1
```

The source version is more register-shaped, but that is the whole loop.

There is a useful invariant hiding here:

> every byte before `r10` has already been classified

So when `r10` reaches the number of bytes read, the chunk is done.

Then the program goes back to `read(2)` for another chunk.

This is a good loop to study because it is not assembly trickery. It is ordinary scanning, written without the usual high-level clothing.

---

## Adding current counts to totals

After one named file is successfully counted, the program calls:

```text
add_current_to_total
```

This helper copies the current file’s counts into the accumulated totals by addition.

It does not reset the current counters. That happens at the start of the next `count_fd`.

The separation keeps the code readable:

| Helper                 | Job                                     |
| ---------------------- | --------------------------------------- |
| `count_fd`             | count one input                         |
| `add_current_to_total` | add that input’s counts into the totals |
| `print_count_line`     | display the current counters            |

Each helper has a narrow job.

That is especially helpful in assembly, where “cleverly compact” can become “unreadable brick” very quickly.

---

## Printing the count line

The output line has this simple shape:

```text
lines words bytes [name]
```

For stdin, the name is empty.

For files, the name is the pathname.

For totals, the name is:

```text
total
```

The nice part is that the same printing helper handles all three cases.

It prints:

```text
current_lines
space
current_words
space
current_bytes
optional space + name
newline
```

That means the total line is created by copying total values into the current counters, then calling the same printer.

That is a practical reuse move:

> make the totals look like “current counts” temporarily, then use the existing output path

No need for a separate total-printing function.

---

## Decimal printing is backwards

The helper:

```text
write_uint_stdout
```

turns an unsigned integer into decimal text.

This is one of the best little teaching moments in the file.

Humans write numbers left to right:

```text
1234
```

But division by 10 gives the rightmost digit first:

```text
1234 / 10 = 123 remainder 4
123  / 10 = 12  remainder 3
12   / 10 = 1   remainder 2
1    / 10 = 0   remainder 1
```

So the digits arrive in this order:

```text
4, 3, 2, 1
```

Backwards.

The source handles that by starting at the end of a temporary buffer and moving left one byte per digit.

That way, when the loop is done, the digits are laid out in the correct order in memory.

---

## The end-pointer trick

The number buffer is 20 bytes.

The code starts with a pointer one byte past the end:

```text
number_buf + 20
```

Then each digit does:

```text
move pointer left
store digit
```

So formatting `1234` looks like this conceptually:

```text
[....................]
                    ^
                    start just past end

store 4:
[...................4]
                   ^

store 3:
[..................34]
                  ^

store 2:
[.................234]
                 ^

store 1:
[................1234]
                ^
```

At the end:

| Pointer               | Meaning                      |
| --------------------- | ---------------------------- |
| current digit pointer | first digit                  |
| `number_buf + 20`     | one byte past the last digit |

The byte count is:

```text
end pointer - first digit pointer
```

That gives `write(2)` exactly the slice of the buffer containing the number.

This is a classic low-level formatting trick.

---

## Zero needs a special case

The formatting loop divides until the quotient becomes zero.

But the number zero would produce no digits if handled only by that loop.

So the source checks for zero first and manually writes:

```text
'0'
```

That is a common edge case in number formatting.

Without it, `wc` could print a blank field instead of `0`.

A file with no words, no lines, or no bytes should still show real zeroes.

Not silence.

---

## `write_all`: output should finish the job

The file uses a robust `write_all` helper.

That matters because `write(2)` can write fewer bytes than requested.

The helper keeps two pieces of state:

| Register | Meaning                            |
| -------- | ---------------------------------- |
| `r9`     | pointer to the next unwritten byte |
| `r10`    | number of bytes still unwritten    |

Each successful write moves the pointer forward and reduces the remaining count.

Conceptually:

```text
while remaining > 0:
    n = write(fd, pointer, remaining)
    if n <= 0: fail
    pointer += n
    remaining -= n
```

This is the right instinct for command output.

Even when most small writes succeed all at once, the code should understand that the syscall contract allows partial writes.

---

## Stderr is separate from stdout

Diagnostics go to fd `2`.

Counts go to fd `1`.

That separation matters.

If you run:

```sh
./build/wc missing.txt good.txt > counts.txt
```

you do not want the error message for `missing.txt` mixed into `counts.txt`.

The output file should receive only real count lines.

The complaint should go to stderr, where the terminal or caller can handle it separately.

This is one of those Unix habits that keeps tools composable.

---

## The final status

The command exits with the accumulated status.

That means:

| Situation                                   | Final exit |
| ------------------------------------------- | ---------- |
| all inputs counted and printed successfully | `0`        |
| any open, read, or write failed             | `1`        |

For multiple operands, this is important.

A command can produce useful partial output and still report that the overall request had a failure.

That is not indecision.

That is exactly what scripts need.

---

## What this file is quietly teaching

`wc.asm` teaches several ideas that show up all over low-level tools:

| Concept                       | Where it appears                        |
| ----------------------------- | --------------------------------------- |
| Stream reading                | `count_fd`                              |
| Fixed-size reusable buffer    | `buffer`                                |
| EOF-driven loop               | `read(2)` returning zero                |
| Byte counting                 | add the read length                     |
| Newline counting              | compare each byte to `10`               |
| Word counting                 | whitespace/non-whitespace state machine |
| State surviving across chunks | `bl` inside-word flag                   |
| Per-file counters             | `current_*`                             |
| Accumulated totals            | `total_*`                               |
| Decimal number formatting     | `write_uint_stdout`                     |
| Backwards digit generation    | divide by 10, store from buffer end     |
| Partial-write handling        | `write_all`                             |
| stdout/stderr separation      | fd `1` vs fd `2`                        |

That is a lot of value from one command.

It deserves a note because it teaches the moment where byte streams start becoming meaning.

---

## Suggested experiments

Try stdin:

```sh
printf 'one two\nthree\n' | ./build/wc
```

Expected idea:

```text
2 lines
3 words
14 bytes
```

The exact byte count depends on the exact input, so `printf` is better than `echo` for predictable testing.

Try no trailing newline:

```sh
printf 'hello' | ./build/wc
```

Notice the line count.

There is one word and five bytes, but zero newline bytes.

Try multiple spaces:

```sh
printf 'one     two\n' | ./build/wc
```

The word count should still be two.

Extra whitespace does not create extra words because words are counted at transitions from outside to inside a word.

Try tabs and newlines:

```sh
printf 'one\ttwo\nthree\r\n' | ./build/wc
```

This gives the whitespace classifier something more interesting than ordinary spaces.

Try multiple files:

```sh
./build/wc file1.txt file2.txt
```

Now watch for the final `total` line.

Try a missing file among real files:

```sh
./build/wc file1.txt definitely-not-here.txt file2.txt
echo $?
```

The useful behavior is:

```text
count what can be counted
complain about what cannot
exit failure overall
```

---

## Takeaway

`wc.asm` is the stream scanner keystone.

`cat` says:

```text
read bytes, write bytes
```

`wc` says:

```text
read bytes, interpret bytes, print counts
```

That is a major conceptual step.

The program is still only seeing one byte at a time. There is no grand parser. No object model. No hidden library doing the work.

Just a buffer, counters, and one tiny piece of memory:

```text
am I inside a word right now?
```

That one bit of state is enough to turn raw bytes into a word count.

That is the good stuff. Assembly does not have to be mystical to be powerful. Sometimes the whole trick is knowing exactly what small fact needs to survive from one byte to the next.
