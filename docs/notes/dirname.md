# Notes: `dirname`

`dirname` is a path command that does not need to touch the filesystem.

That is the main lesson.

It does not ask whether the path exists.

It does not open directories.

It does not call `stat`.

It does not care whether the operand names a real file, a broken symlink, a directory, or pure nonsense.

This teaching version treats the operand as a byte string and applies pathname text rules to it.

That makes it a good little string-processing note:

> sometimes a Unix path utility is just carefully trimming and slicing bytes

Keep `src/dirname.asm` open beside this note. The interesting part is the sequence of reductions:

```text
find the end
trim trailing slashes
find the separator slash
trim duplicate directory slashes
print the answer
```

---

## What this command really does

At the shell level, `dirname` feels like:

> give me the directory part of this path

At the assembly level, this version does something more mechanical:

| Left pane: code idea                        | Right pane: human meaning                      |
| ------------------------------------------- | ---------------------------------------------- |
| Require exactly one operand                 | “There should be one pathname string.”         |
| Measure the string                          | “Find where the pathname ends.”                |
| Trim trailing `/` bytes                     | “Ignore decorative ending slashes, mostly.”    |
| Preserve root slash                         | “Do not turn `/` or `///` into empty nothing.” |
| Scan backward for `/`                       | “Find the separator before the basename.”      |
| If no separator exists                      | “The directory part is `.`.”                   |
| Trim duplicate slashes before the separator | “Normalize `a//b` to directory `a`.”           |
| Print the selected byte range               | “Write the directory part.”                    |

That is the whole program.

There is no filesystem lookup hiding underneath.

The path is text.

The answer is also text.

---

## The intentionally narrow behavior

This implementation supports:

```sh
dirname PATH
```

with exactly one operand.

It does not implement options like:

```sh
dirname -z PATH
dirname --help
dirname --version
```

It also does not accept multiple pathnames.

So:

```sh
./build/dirname a/b c/d
```

is an error in this teaching version.

That keeps the source focused on the actual lesson:

> derive one directory string from one pathname string

Option parsing and multi-operand behavior would be useful later, but they would make this file less sharp as an early string-processing example.

---

## `_start`: one operand, no more

The source begins with the familiar startup setup:

```asm
mov r12, [rsp]
lea r13, [rsp + 8]
```

Read those as:

| Register | Meaning                     |
| -------- | --------------------------- |
| `r12`    | `argc`                      |
| `r13`    | pointer to the `argv` array |

Then it checks:

```asm
cmp r12, 2
jb .missing_operand
ja .extra_operand
```

Since `argc` includes `argv[0]`, exactly one user operand means:

```text
argc == 2
```

So the program accepts this:

```sh
./build/dirname /usr/bin/sh
```

and rejects both of these:

```sh
./build/dirname
./build/dirname a b
```

This is a good early pattern:

```text
check the command shape first
then do the real work
```

---

## `print_dirname`: the real command

Once the operand count is right, `_start` loads:

```asm
mov rdi, [r13 + 8]
```

That means:

```text
rdi = argv[1]
```

Then it calls:

```asm
print_dirname
```

That helper is the actual `dirname` algorithm.

The input is a pointer to a NUL-terminated pathname string.

The output is not returned as a string. The helper writes the answer directly to stdout and returns a status in `rax`.

| `rax` | Meaning          |
| ----- | ---------------- |
| `0`   | output succeeded |
| `1`   | write failure    |

So `print_dirname` combines two jobs:

```text
decide which bytes are the answer
write those bytes plus a newline
```

For this small command, that is a reasonable shape.

---

## First, measure the pathname

The helper starts with:

```asm
mov r8, rdi
xor r9d, r9d
```

Read that as:

| Register | Meaning               |
| -------- | --------------------- |
| `r8`     | start of the pathname |
| `r9`     | length counter        |

Then the `.find_end` loop walks forward until it sees byte `0`.

That byte is the NUL terminator.

Conceptually:

```text
length = 0

while pathname[length] != 0:
    length += 1
```

This is the same C-string measuring idea used in other commands.

The program cannot process “the string” as a magical object. It has a pointer to the first byte, and it counts until the terminator.

---

## Empty string becomes `.`

After measuring, the source checks:

```asm
test r9, r9
jz .write_dot
```

If the measured length is zero, the operand was an empty string.

This teaching version prints:

```text
.
```

That means:

```sh
./build/dirname ""
```

should produce:

```text
.
```

This is a nice edge case because it shows the algorithm has to define behavior even for path strings that do not look like normal paths.

The program does not shrug and fall through.

It says:

> no directory portion here, so use `.`

---

## Trailing slashes are mostly decoration

Next, the code copies the length into `r10`:

```asm
mov r10, r9
```

Here `r10` becomes the one-past-end position after trimming.

The loop `.trim_operand_slashes` removes trailing slash bytes:

```text
foo///  -> foo
a/b/    -> a/b
```

But there is an important exception:

> leave one slash for all-slash operands

So:

```text
/       -> /
///     -> /
```

does not become an empty string.

That special case matters because root is represented by a slash. If the input is all slashes, the directory answer should still be root-like, not `.` and not empty output.

This is the first sign that pathname text processing is simple, but not careless.

---

## Why trimming stops at one byte

The trimming loop checks whether `r10` is already `1` or below.

If so, it stops.

That protects cases like:

```text
/
///
```

After trimming, an all-slash input should still have one slash left.

This is a useful low-level edge-case pattern:

```text
trim repeated suffix bytes
but keep the minimum meaningful representation
```

For root-like paths, the minimum meaningful representation is one slash.

---

## If the trimmed path is just `/`

After trailing slash trim, the source checks whether the remaining string is one byte long and that byte is `/`.

If yes, it writes root:

```text
/
```

So these inputs all land on root:

```text
/
///
///////
```

This comes before the backward separator search because there is no basename to remove anymore.

The whole thing is root.

The answer is root.

---

## Now scan backward for the separator

For a normal path, the program needs to find the slash before the basename.

Examples:

| Input after trailing trim | Separator to find         | Output     |
| ------------------------- | ------------------------- | ---------- |
| `a/b`                     | slash between `a` and `b` | `a`        |
| `/usr/bin/sh`             | slash before `sh`         | `/usr/bin` |
| `foo`                     | none                      | `.`        |

The `.find_separator` loop moves backward through the string.

Conceptually:

```text
position = one-past-end

while position > 0:
    position -= 1
    if pathname[position] == '/':
        found separator
```

If the loop reaches the beginning without finding a slash, there is no directory portion.

So the answer is:

```text
.
```

That handles inputs like:

```text
foo
file.txt
noslash
```

No slash means:

> the pathname is relative to the current directory

So `dirname` prints `.`.

---

## The basename is everything after the separator

Once the separator slash is found, everything after it is the basename portion.

For:

```text
/usr/bin/sh
```

the separator before the basename is here:

```text
/usr/bin/sh
        ^
```

The directory answer is the bytes before that basename:

```text
/usr/bin
```

For:

```text
a/b
```

the separator is:

```text
a/b
 ^
```

The answer is:

```text
a
```

The source does not copy the basename.

It just uses the separator position to decide how many bytes from the front of the original string should be printed.

That is a good low-level habit:

> when possible, return or print a slice of the original bytes instead of building a new string

Here the slice is:

```text
start pointer = original pathname
length        = separator position after trimming
```

---

## Duplicate directory slashes get trimmed too

After finding the separator before the basename, the code trims duplicate slashes before it.

This matters for paths like:

```text
a//b
```

The separator before `b` is the second slash:

```text
a//b
  ^
```

If the program printed everything before that separator position, it would print:

```text
a/
```

But the source trims duplicate slashes before the separator and prints:

```text
a
```

This is what the `.trim_dir_slashes` loop is doing.

It says:

> if the directory portion ends with repeated slash bytes, trim them down

But again, it preserves a leading root slash.

So:

```text
/usr//bin
```

should become:

```text
/usr
```

when taking the dirname of `/usr//bin`.

Not `/usr/`.

Not empty.

---

## Root must survive duplicate slash trimming

The trimming loop for the directory portion stops when the separator position is `1` or below.

That means absolute paths keep their root slash.

Example:

```text
/foo
```

The separator before `foo` is at position `0`.

The code notices that and writes:

```text
/
```

Example:

```text
//foo
```

After the duplicate slash handling, this teaching version also reduces the directory answer to:

```text
/
```

The important rule is:

> do not trim the root slash away

Many path edge cases come down to that one small instinct.

You can remove redundant slashes, but not the slash that represents root.

---

## `.` means “no directory portion”

The `.write_dot` path writes one byte:

```text
.
```

That handles cases like:

```text
foo
foo/
""
```

after the relevant trimming.

The meaning is:

> the directory part is the current directory

This is not saying the file exists in the current directory.

It is only saying that, as a pathname string, there was no explicit directory component left.

That distinction matters.

`dirname` is not validating a path.

It is describing the path text it was handed.

---

## `/` means “root directory portion”

The `.write_root` path writes one byte:

```text
/
```

That handles cases where trimming and separator logic leave root as the directory answer.

Examples include:

```text
/
///
/foo
```

For `/foo`, the basename is `foo`, and the directory part is `/`.

For `/`, the whole operand is root, and the answer remains `/`.

Again, this is text processing with a few pathname conventions baked in.

No filesystem lookup is needed.

---

## Printing a slice

The normal directory case does this:

```asm
mov rsi, r8
mov rdx, r10
jmp .write_answer
```

Read that as:

| Register | Meaning                                    |
| -------- | ------------------------------------------ |
| `rsi`    | pointer to first byte of original pathname |
| `rdx`    | number of bytes to print                   |

So if the input is:

```text
/usr/bin/sh
```

and the final directory length is `8`, the program writes:

```text
/usr/bin
```

It does not need to allocate a new string.

It does not need to insert a NUL terminator.

For `write(2)`, pointer plus length is enough.

That is a beautiful little assembly moment:

> a substring can be represented by a pointer and a byte count

No new object required.

---

## The answer always gets a newline

After writing the answer bytes, `.write_answer` writes one newline byte.

So every successful run produces a normal line of output:

```text
answer\n
```

The answer itself may be:

```text
.
/
a
/usr/bin
```

but the output format is always:

```text
directory-part followed by newline
```

This keeps the command pleasant in the shell and predictable in scripts.

---

## `write_all`: output should finish

This file uses a proper `write_all` helper.

That means it does not assume one `write(2)` call always writes every requested byte.

The helper tracks:

| Register | Meaning               |
| -------- | --------------------- |
| `r9`     | next byte to write    |
| `r10`    | bytes still unwritten |

Each successful partial write advances the pointer and reduces the remaining count.

Conceptually:

```text
while remaining > 0:
    n = write(fd, pointer, remaining)
    if n <= 0:
        fail
    pointer += n
    remaining -= n
```

For `dirname`, output is usually tiny, but using `write_all` is still a good habit.

It lets the rest of the command say:

> write this answer

without worrying about short writes.

---

## Diagnostics go to stderr

Normal output goes to stdout.

Errors go to stderr.

So this:

```sh
./build/dirname a/b > out.txt
```

puts only:

```text
a
```

in `out.txt`.

But this:

```sh
./build/dirname a b > out.txt
```

should not put the error message into `out.txt`.

The diagnostic goes to fd `2`.

This is the same composable command-line habit as the other notes:

| fd         | Purpose             |
| ---------- | ------------------- |
| `1` stdout | real command output |
| `2` stderr | diagnostics         |

Even small text utilities should keep that split.

---

## What this file is quietly teaching

`dirname.asm` teaches a focused set of byte-string and pathname ideas:

| Concept                  | Where it appears             |
| ------------------------ | ---------------------------- |
| Exact operand count      | `_start`                     |
| C-string length scan     | `.find_end`                  |
| Empty input handling     | `.write_dot`                 |
| Trailing slash trimming  | `.trim_operand_slashes`      |
| Root preservation        | stop trimming at one slash   |
| Backward scanning        | `.find_separator`            |
| No-separator fallback    | `.`                          |
| Duplicate slash cleanup  | `.trim_dir_slashes`          |
| Printing a substring     | pointer plus length          |
| No filesystem lookup     | the whole algorithm          |
| Robust output            | `write_all`                  |
| stdout/stderr separation | normal output vs diagnostics |

That makes it a very good note candidate.

It is not syscall-heavy.

It is not register-wizardry-heavy.

It is a clean example of getting path behavior right with simple byte operations.

---

## Suggested experiments

Basic path:

```sh
./build/dirname /usr/bin/sh
```

Expected idea:

```text
/usr/bin
```

No slash:

```sh
./build/dirname foo
```

Expected:

```text
.
```

Relative path:

```sh
./build/dirname a/b
```

Expected:

```text
a
```

Trailing slash:

```sh
./build/dirname a/b/
```

Expected:

```text
a
```

All slashes:

```sh
./build/dirname /
./build/dirname ///
```

Expected:

```text
/
```

Absolute path with one basename:

```sh
./build/dirname /foo
```

Expected:

```text
/
```

Duplicate slashes:

```sh
./build/dirname a//b
```

Expected idea:

```text
a
```

Empty string:

```sh
./build/dirname ""
```

Expected:

```text
.
```

Too many operands:

```sh
./build/dirname a b
echo $?
```

Expected idea:

```text
diagnostic on stderr
exit status 1
```

The important thing to watch is that none of these require the paths to exist.

You can test with imaginary paths:

```sh
./build/dirname /made/up/path/to/nowhere
```

The command can still answer because it is working on the pathname string, not the filesystem.

---

## Takeaway

`dirname.asm` is a pathname-as-bytes lesson.

The command does not ask:

```text
what exists on disk?
```

It asks:

```text
given this path string, which leading bytes form the directory portion?
```

That is a different kind of problem.

The algorithm is a careful series of byte operations:

```text
measure the string
trim trailing slashes
preserve root
scan backward for slash
trim duplicate directory slashes
print a slice
```

That is the useful mental model.

A path can name a filesystem object, but before it does that, it is also just text. `dirname` lives mostly in that text layer.

And in assembly, the text layer is beautifully plain:

```text
pointer to first byte
count of bytes to print
```

That is enough to build the command.
