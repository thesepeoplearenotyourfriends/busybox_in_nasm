# Notes: `ascii`

`ascii` is a quiet little program, but it teaches a useful assembly lesson:

> sometimes the program does not calculate the answer at runtime; sometimes the answer is already sitting in the binary as bytes.

This implementation prints a compact table for the 7-bit ASCII character set: decimal value, hexadecimal value, and either the printable character or a standard control-code name.

It does not parse options. It does not know about Unicode. It does not ask libc or the terminal for formatting help. It writes one prebuilt table to stdout and exits.

That makes it a good companion piece after `clear`.

`clear` said:

> here are a few control bytes; write them

`ascii` says:

> here is a whole reference table; write it

Same basic syscall shape, bigger data lesson.

Keep `src/ascii.asm` open beside this note. This page is here to help the source feel intentional instead of looking like a giant wall of numbers.

---

## What this command really does

At the shell level, `ascii` feels like a lookup tool:

> show me the ASCII table

At the assembly level, this teaching version does something much simpler:

> write a fixed block of bytes to stdout

There is no loop that counts from `0` to `127`.

There is no code converting numbers into decimal and hexadecimal text.

There is no decision tree for control-code names.

All of that work has already been done ahead of time. The table is stored directly in the program.

The shape is:

| Left pane: code idea              | Right pane: human meaning                  |
| --------------------------------- | ------------------------------------------ |
| Define `ascii_table` in `.rodata` | “Here are the exact bytes to print.”       |
| Define `ascii_table_len`          | “Here is how many bytes are in the table.” |
| Call `write(2)`                   | “Send the table to stdout.”                |
| Check the return value            | “Did the whole table get written?”         |
| Call `exit(2)`                    | “Leave with success or failure status.”    |

That is the entire program.

Not every useful command starts as an algorithm. Some start as carefully arranged data.

---

## The table is the program’s payload

The source has a large block under:

`ascii_table:`

followed by many `db` lines.

`db` means “define byte.”

So the table is not a string in some high-level language sense. It is a sequence of byte values placed into the program by the assembler.

A line like this:

`db 68, 101, 99, 32, 72, 101, 120`

is not meant to be read as math.

Those numbers are byte values.

Interpreted as ASCII, they spell:

`Dec Hex`

That is the first mental shift for this file:

> the scary-looking number wall is just text, stored as bytes

The source could have used more quoted string fragments in places, but the fully numeric style makes the byte-level reality impossible to miss. This is not “text magic.” It is bytes all the way down.

---

## Why this belongs in `.rodata`

The table lives in:

`section .rodata`

That means read-only data.

The program never edits the table. It only gives the kernel a pointer to it.

That is a clean separation:

| Section   | Purpose here                   |
| --------- | ------------------------------ |
| `.rodata` | the fixed ASCII table          |
| `.text`   | the instructions that write it |

This is a good early habit: when bytes are fixed, treat them as fixed data.

The CPU does not need to execute the table.

The program does not need to modify the table.

It just needs the table to exist somewhere in the binary so `write(2)` can read from it.

---

## The numbers are ASCII describing ASCII

This file has a funny self-reference hiding in plain sight.

The command prints an ASCII table.

The table itself is also stored as ASCII bytes.

For example, the row for capital `A` is not stored as “the abstract idea of letter A.” It is stored as bytes that, when printed, produce text like:

`65 41 A`

That row contains:

| Visible text | What it means       |
| ------------ | ------------------- |
| `65`         | decimal value       |
| `41`         | hexadecimal value   |
| `A`          | printable character |

But even the characters `6`, `5`, `4`, `1`, and `A` are themselves bytes in the output table.

That is worth sitting with for a second.

The table is not a structured database at runtime. It is already formatted display text.

The program does not “know” that `65` means `A`.

The human knows.

The assembler just put the bytes there.

The kernel writes them.

The terminal displays them.

---

## Control codes get names

The early ASCII values are not printable characters.

Byte `0` is not something you can visibly print as a normal glyph. Same with many values up through `31`, plus `127`.

So the table uses names like:

`NUL`

`SOH`

`LF`

`CR`

`ESC`

`DEL`

This is why the table has three columns instead of just trying to show every byte as a character.

For printable characters, the third column can show the character.

For control codes, the third column shows a name.

That means the output table is already an interpretation layer. It is not dumping raw bytes `0` through `127`. It is showing a human-readable reference.

Again, though, that interpretation has already happened before runtime. The program is only printing the finished reference text.

---

## `ascii_table_len`: let the assembler count

After the table, the source defines:

`ascii_table_len: equ $ - ascii_table`

This is the same useful idiom from `clear`.

Read it as:

> define the table length as “where we are now minus where the table started”

The `$` means the assembler’s current position.

Since the assembler has just finished placing the table bytes, subtracting `ascii_table` gives the total byte count.

That byte count matters because `write(2)` does not accept “print this label.”

It accepts:

> fd, buffer pointer, byte count

So the program needs both:

| Thing             | Meaning                 |
| ----------------- | ----------------------- |
| `ascii_table`     | where the table starts  |
| `ascii_table_len` | how many bytes to write |

This is a good example of assembly being less forgiving but more honest.

There is no hidden string object.

There is just a start address and a length.

---

## `_start`: one job, then leave

The executable begins at:

`_start:`

This project is using raw Linux process entry, not a C `main()`.

So there is no caller to return to.

There is no standard library cleanup path.

When this program is done, it exits by syscall.

That makes the flow pleasantly direct:

```text
write table
if short/failure, exit 1
otherwise, exit 0
```

This file is small enough that you can read it almost like a sentence.

---

## The write syscall

The main syscall setup is:

`rax = 1`

`rdi = 1`

`rsi = ascii_table`

`rdx = ascii_table_len`

Then:

`syscall`

For Linux x86_64, that means:

| Register | Meaning        | Value here             |
| -------- | -------------- | ---------------------- |
| `rax`    | syscall number | `1`, `write`           |
| `rdi`    | argument 1     | `1`, stdout            |
| `rsi`    | argument 2     | pointer to table bytes |
| `rdx`    | argument 3     | table byte count       |

This is exactly the same basic shape as `clear`.

The only real difference is payload size.

`clear` writes a short terminal-control sequence.

`ascii` writes a longer human-readable table.

That is a useful connection: once you understand one direct `write`, you understand the skeleton of many tiny output commands.

---

## `lea` points at the table

The source uses:

`lea rsi, [ascii_table]`

That puts the address of the table into `rsi`.

It does not copy the table into the register.

It cannot. The table is much larger than one register.

Instead, `rsi` says:

> the bytes begin over there

And `rdx` says:

> write this many bytes from over there

That pointer-plus-length pair is one of the core shapes of low-level programming.

Any time you see a syscall writing or reading data, look for those two facts:

| Fact                 | Common register here |
| -------------------- | -------------------- |
| Where is the buffer? | `rsi`                |
| How many bytes?      | `rdx`                |

The kernel needs both.

---

## Checking for a complete write

After `syscall`, `rax` contains the return value from `write(2)`.

This program compares it against:

`ascii_table_len`

If the return value does not equal the full table length, it exits with failure.

That catches both obvious write errors and short writes.

For a small terminal utility, this is enough. It does not print a diagnostic. It does not retry. It simply refuses to claim success unless the whole table was written.

That is a good teaching habit:

> success should mean the requested operation actually happened

Not:

> we asked nicely and hoped

---

## Why extra arguments are ignored

The source comments say extra arguments are ignored in this first static-table teaching version.

So:

```sh
ascii whatever
```

still just prints the table.

That is not trying to be a full-featured `ascii` utility. It is keeping the lesson narrow:

> static data plus `write(2)`

Argument parsing would be a different lesson.

A lookup mode like `ascii A` would also be a different lesson.

Generating the table dynamically would definitely be a different lesson.

Those could all be interesting later, but they would pull attention away from what this file is good at teaching.

This version has one job: print the prebuilt table.

---

## Static table versus generated table

It is worth asking: why not generate the table with code?

You could imagine a more algorithmic version:

```text
for n = 0 to 127:
    print decimal n
    print hex n
    print character name or printable char
```

That would teach loops, division, number formatting, branches, and maybe lookup tables.

Useful, but much bigger.

This version makes a different trade:

| Static-table version              | Generated-table version      |
| --------------------------------- | ---------------------------- |
| simpler code                      | more algorithmic             |
| bigger `.rodata`                  | smaller static data          |
| teaches bytes and `write` clearly | teaches conversion and loops |
| easy to inspect output bytes      | more moving parts            |

For a `00`-level command, the static table is a good call.

The reader gets to see that an executable can carry around a ready-made block of output, then hand it straight to the kernel.

That is not cheating.

That is a legitimate design.

---

## The final exits

The success path is:

`exit(0)`

The failure path is:

`exit(1)`

The success path uses the common idiom:

`xor rdi, rdi`

to set the exit status to zero.

The failure path uses:

`mov rdi, 1`

to set the exit status to one.

So the shell-level meaning is:

| Exit status | Meaning                     |
| ----------- | --------------------------- |
| `0`         | full table was written      |
| `1`         | table was not fully written |

No decorations.

No drama.

Just an honest status.

---

## What this file is quietly teaching

`ascii.asm` teaches a small set of ideas very cleanly:

| Concept                    | Where it appears                |
| -------------------------- | ------------------------------- |
| Raw byte data              | the `db` table                  |
| Read-only program payload  | `.rodata`                       |
| Assembler-computed size    | `equ $ - ascii_table`           |
| Pointer-plus-length output | `rsi` and `rdx`                 |
| Direct syscall use         | `write(2)`                      |
| Return-value checking      | compare `rax` with table length |
| Process status             | `exit(0)` or `exit(1)`          |

That makes it a good early note.

The program is not clever.

That is the point.

It is a clear example of using the assembler to package bytes, then using the kernel to write them.

---

## Suggested experiments

Pipe the output into `head`:

```sh
./build/ascii | head
```

That lets you inspect the top of the table without the full output scrolling past.

Pipe it into `od`:

```sh
./build/ascii | od -An -tx1 | head
```

Now you are looking at the table as bytes again.

That is the important flip:

| View            | What you see                     |
| --------------- | -------------------------------- |
| normal terminal | formatted ASCII table            |
| `od -tx1`       | the bytes that create that table |

Try searching for a known row:

```sh
./build/ascii | grep ' 65 '
```

That should lead you to the row for `A`.

Then remember the funny part:

> the row explaining ASCII is itself made out of ASCII bytes

That is the whole charm of this command.

---

## Takeaway

`ascii.asm` is a static-data lesson wearing a command’s hat.

It shows that a useful program does not always need loops, parsing, or runtime generation. Sometimes the cleanest early version is:

```text
store the finished bytes
write the finished bytes
exit honestly
```

That is not a toy idea. It shows up everywhere: help text, lookup tables, protocol messages, fixed headers, templates, banners, test fixtures, and more.

Once this file clicks, a wall of `db` lines stops looking like random number gravel.

It becomes what it really is:

> the program’s cargo, packed byte by byte.
