# Notes: `printenv`

`printenv` is the natural sequel to `env`.

`env` says:

> find the environment and print every entry

`printenv` says:

> find the environment, then search it for particular names

That adds one important new layer: string matching.

The program still walks the raw `envp` array from the initial process stack. It still writes plain strings to stdout. But now it has to compare a requested name like:

```text id="7x9d5j"
HOME
```

against environment entries shaped like:

```text id="so1swp"
HOME=/home/art
PATH=/usr/bin:/bin
TERM=xterm-256color
```

That makes this a good small lesson in matching a prefix carefully without accidentally matching too much.

Keep `src/printenv.asm` open beside this note. The center of the file is not the printing. The center is the test:

> does this `NAME` exactly match the part before `=`?

---

## What this command really does

At the shell level, `printenv` feels like:

> show me environment variables

At the assembly level, this teaching version has two modes:

| User shape        | Program behavior                              |
| ----------------- | --------------------------------------------- |
| no operands       | print every environment entry as `NAME=VALUE` |
| one or more names | print only the value for each matching name   |

So:

```sh id="6fj3bs"
./build/printenv
```

prints entries like:

```text id="fed0um"
HOME=/home/art
PATH=/usr/bin:/bin
```

But:

```sh id="dtbc9o"
./build/printenv HOME PATH
```

prints only the values:

```text id="2eq5uj"
/home/art
/usr/bin:/bin
```

That difference matters.

`env` prints whole entries.

Named `printenv` prints values.

The source states that focus directly: this version is about envp scanning and `NAME=VALUE` matching, not GNU/coreutils option compatibility. 

---

## The two big paths

Near the top, the program checks `argc`.

If `argc == 1`, there are no requested names, so it jumps to the print-all path.

Otherwise, it starts looping through requested names from `argv[1]`.

That gives the file a clean fork:

| Path                     | Job                                               |
| ------------------------ | ------------------------------------------------- |
| `.print_all_environment` | walk envp and print each full entry               |
| `.name_loop`             | walk requested names and search envp for each one |

This is a good way to read the file. Do not try to digest it as one long stream of instructions.

It is two modes sharing a few helpers.

---

## Startup stack again: `argc`, `argv`, then `envp`

The setup is familiar by now:

```asm id="38tkqa"
mov r12, [rsp]
lea r13, [rsp + 8]
lea r14, [r13 + r12*8 + 8]
```

Read that as:

| Register | Meaning              |
| -------- | -------------------- |
| `r12`    | `argc`               |
| `r13`    | pointer to `argv[0]` |
| `r14`    | pointer to `envp[0]` |

The `envp` calculation is the same idea from `env`.

Starting from `argv[0]`, skip:

```text id="zql3up"
argc argv pointers
plus the NULL pointer after argv
```

Then you land on the first environment pointer.

In C-ish terms:

```c id="ls51xe"
envp = &argv[argc + 1];
```

The source comment says exactly that shape: `r14` becomes the envp pointer array after the argv NULL terminator. 

That is the foundation for both modes.

---

## Print-all mode

The no-operand path starts here:

```asm id="mfnhay"
.print_all_environment:
```

This mode is very close to the `env` command.

The loop keeps a current envp slot in `rbx`.

At each step:

```text id="fke4z2"
load pointer from current envp slot
if pointer is NULL, stop
write the C string to stdout
write a newline
advance to next envp slot
```

The source gives the loop invariant clearly: entries before the current pointer have already been printed, and the current slot points either at the next entry or the final NULL. 

That means this path is mainly:

> pointer-array walking

No parsing.

No matching.

No splitting at `=`.

Just print each inherited environment string.

---

## Named mode: search for each requested name

When the user supplies names, the program starts at `argv[1]`.

The register `rbx` holds the current argv index.

The loop does:

```text id="6rgtmt"
load requested name
reject it if it looks like an unsupported option
search envp for that name
if found, print the value
if missing, remember that something failed
move to next requested name
```

The missing-name behavior is a nice practical detail.

If you ask for several names and one is missing, the command does not stop immediately.

It still prints the values it can find.

But it exits with failure at the end.

That means:

```sh id="zdudq0"
./build/printenv HOME DEFINITELY_NOT_REAL PATH
echo $?
```

can still print `HOME` and `PATH`, while the exit status tells a script that the whole request was not fully satisfied.

That is the same “keep working, but do not lie” pattern from `cat` and `wc`.

---

## `r15`: the missing-name flag

The source initializes:

```asm id="al8tmt"
xor r15, r15
```

Here `r15` is used as a missing-name flag.

| `r15` | Meaning                                    |
| ----- | ------------------------------------------ |
| `0`   | every requested name has been found so far |
| `1`   | at least one requested name was missing    |

When a name search fails, the code sets:

```asm id="xckh1t"
mov r15, 1
```

At the end of the name loop, the program tests `r15`.

If it is still zero, exit success.

If it is one, exit failure.

That is a simple way to accumulate status across multiple requested names.

The command can produce useful output and still remember that the overall request had a problem.

---

## Unsupported dash options

Before searching for a requested name, the source checks:

```asm id="xc5m5g"
starts_with_dash
```

So input like:

```sh id="ov1u51"
./build/printenv --help
./build/printenv -0
```

is rejected as an unsupported option.

This teaching version does not implement `--help`, `--version`, or GNU’s `-0` output mode. It supports name operands only. 

That keeps the code focused.

A fuller `printenv` could support options.

This one is teaching:

```text id="xxk1i4"
argv name -> envp search -> value output
```

That is enough.

---

## Names containing `=` are not special here

The source comments say names containing `=` are accepted as literal names and normally will not match environment entries. 

That is worth noticing.

This command does not parse requested operands as assignments.

So:

```sh id="fm2zfl"
./build/printenv HOME=/tmp
```

does not mean:

> set HOME to `/tmp`

It means:

> search for an environment variable literally named `HOME=/tmp`

That will normally fail, because environment entries are matched by the name before the `=`.

Again, this keeps the implementation honest and narrow.

`printenv` is not `env`.

It does not modify the environment or run a command under a modified environment.

---

## `find_and_print_name`: search one name

The helper:

```asm id="wlqkeo"
find_and_print_name
```

receives one requested name in `rdi`.

It uses `r14` as the beginning of the environment pointer array.

The shape is:

```text id="6z0eob"
current envp slot = envp[0]

while current slot is not NULL:
    compare requested NAME with this NAME=VALUE entry
    if it matches:
        print VALUE
        return found
    advance to next envp slot

return not found
```

That helper is the heart of named mode.

The source comment says its output is `rax = 0` if found and printed, `1` if not found or write failed. 

That is a practical combined status:

| Return | Meaning                  |
| ------ | ------------------------ |
| `0`    | found and printed        |
| `1`    | missing or output failed |

The caller does not need to know which one happened for its final status decision.

Either way, this requested name did not complete successfully.

---

## The envp search loop

Inside `find_and_print_name`, `r9` points at the current envp slot.

The source comment gives the invariant:

> envp slots before `r9` did not match the requested name. 

That is the whole loop in one sentence.

At each slot:

```asm id="6b6mac"
mov r10, [r9]
test r10, r10
jz .not_found
```

This loads the current environment entry pointer and stops if it is NULL.

If not NULL, it calls the comparison helper.

If the helper says no match, the code advances:

```asm id="nk2jmx"
add r9, 8
```

Again, `8` is pointer size.

So the search is just:

```text id="swv8uu"
check pointer
compare string
advance by one pointer
repeat
```

No hash table.

No index.

No library call.

Just a linear scan through `envp`.

---

## The matching helper is the real lesson

The helper:

```asm id="s1f23g"
name_matches_environment_entry
```

answers this question:

> does requested `NAME` exactly match the name part of this `NAME=VALUE` environment entry?

Its inputs are:

| Register | Meaning                                  |
| -------- | ---------------------------------------- |
| `rdi`    | requested name, like `HOME`              |
| `rsi`    | environment entry, like `HOME=/home/art` |

Its output is:

| `rax`            | Meaning  |
| ---------------- | -------- |
| pointer to value | match    |
| `0`              | no match |

The source comment says the helper compares the name only, then requires an equals sign before the value. 

That final `=` check is what keeps the matching exact.

---

## Matching byte by byte

The comparison loop uses `rdx` as an offset into both strings.

Conceptually:

```text id="ly63j6"
offset = 0

while requested_name[offset] is not NUL:
    if requested_name[offset] != env_entry[offset]:
        no match
    offset += 1
```

So for:

```text id="3g5lk9"
requested: HOME
entry:     HOME=/home/art
```

the matching bytes are:

| Offset | Requested | Entry |
| -----: | --------- | ----- |
|    `0` | `H`       | `H`   |
|    `1` | `O`       | `O`   |
|    `2` | `M`       | `M`   |
|    `3` | `E`       | `E`   |

Then the requested string ends.

Now comes the important part.

---

## The equals sign prevents false prefix matches

After the requested name ends, the helper checks:

```asm id="7j6r0u"
cmp byte [rsi + rdx], '='
jne .no_match
```

This means:

> the environment entry must have `=` exactly where the requested name ended

That prevents prefix mistakes.

For example, searching for:

```text id="rqjpeq"
PATH
```

should match:

```text id="cgx2z9"
PATH=/usr/bin:/bin
```

But it should not match:

```text id="qjcpuc"
PATHNAME=something
```

Without the `=` check, `PATH` would look like a prefix of `PATHNAME`, and the program might incorrectly treat it as a match.

The exact rule is:

```text id="yu9wk5"
all name bytes match
and the next environment byte is '='
```

That is the key lesson of this file.

Good string matching often means checking the boundary, not just the prefix.

---

## Returning a pointer to the value

When the helper finds a match, it does:

```asm id="c4zh1d"
lea rax, [rsi + rdx + 1]
```

At that moment:

| Thing     | Meaning                    |
| --------- | -------------------------- |
| `rsi`     | start of `NAME=VALUE`      |
| `rdx`     | offset where `=` was found |
| `rdx + 1` | first byte after `=`       |

So `rax` becomes a pointer to the value.

For:

```text id="gbh5cl"
HOME=/home/art
```

the returned pointer points at:

```text id="2zp0g8"
/home/art
```

Not at `HOME`.

Not at `=`.

At the value.

That is why named `printenv HOME` prints only:

```text id="1ytmp9"
/home/art
```

The source uses that returned pointer directly as the string to print. 

---

## Print-all mode prints entries; named mode prints values

This is a useful contrast:

| Mode           | What gets printed          |
| -------------- | -------------------------- |
| no operands    | whole `NAME=VALUE` entries |
| named operands | only `VALUE`               |

That difference comes from where the output pointer starts.

In print-all mode:

```text id="3bpn4v"
rsi = pointer to full env entry
```

In named mode, after a match:

```text id="ggxh9i"
rsi = pointer returned by matcher
```

And the matcher returns the address after the `=`.

So the output behavior is not a special formatting trick. It comes directly from which pointer gets passed to the string writer.

That is a very assembly-ish idea:

> change the pointer, change what gets printed

---

## C strings still need measuring

Environment entries and requested names are NUL-terminated strings.

But `write(2)` does not accept NUL-terminated strings.

It accepts:

```text id="kmm8l2"
fd
pointer
byte count
```

So the helper:

```asm id="b67702"
write_c_string_fd
```

counts bytes until it finds a zero byte, then calls the lower-level write helper.

The source comment says this is converting C strings from `argv` and `envp` into `write(2)` byte counts. 

That conversion is now a familiar pattern:

```text id="45610r"
NUL-terminated string -> pointer plus length
```

A lot of these small commands use that exact bridge.

---

## Newlines are written separately

The environment strings themselves do not include newline bytes.

They end with NUL.

So after printing an entry or a value, the program separately writes:

```asm id="2v1jlq"
newline: db 10
```

This produces one output item per line.

That separation is worth remembering:

| Byte | Meaning                               |
| ---- | ------------------------------------- |
| `0`  | terminates string in memory           |
| `10` | creates a new line in terminal output |

The NUL byte is not printed.

The newline byte is.

---

## The write helper is simple

The lower-level helper:

```asm id="lv8trs"
write_buffer_fd
```

does one `write(2)` syscall and checks whether the number of bytes written equals the requested count.

If not, it returns failure.

The source treats short writes as failure in this teaching pass. 

That is simpler than a full `write_all` loop.

For this command, output is made of environment strings, values, newlines, and diagnostics. The simple helper keeps the focus on envp scanning and string matching.

A larger stream command would need more careful partial-write handling.

Here, the short helper is a reasonable teaching trade.

---

## stdout and stderr

Normal environment output goes to stdout.

Unsupported-option diagnostics go to stderr.

That means:

```sh id="sdti2x"
./build/printenv HOME > home.txt
```

captures the value cleanly.

But:

```sh id="qrmnzb"
./build/printenv --help > out.txt
```

should not put the unsupported-option complaint into `out.txt`.

The command uses fd `2` for diagnostics.

This same habit shows up across the repo because it is one of the small things that makes Unix tools compose properly.

---

## Missing names affect exit status

A missing name does not print a diagnostic in this version.

It just sets the missing-name flag.

That gives behavior like:

```sh id="yygthn"
./build/printenv HOME NOT_REAL PATH
echo $?
```

The command can print values for `HOME` and `PATH`, but still exit `1` because `NOT_REAL` was missing.

That is useful for scripting.

A human gets the values that exist.

A script gets an honest failure status if any requested name could not be found.

The source states this behavior directly: if any requested name is missing, matching values are still printed, but the final exit status is `1`. 

---

## What this file is quietly teaching

`printenv.asm` teaches a focused set of useful ideas:

| Concept                           | Where it appears                 |
| --------------------------------- | -------------------------------- |
| Raw startup stack access          | `argc`, `argv`, `envp` setup     |
| Finding `envp` after `argv`       | `lea r14, [r13 + r12*8 + 8]`     |
| Two command modes                 | no operands vs named operands    |
| Pointer-array walking             | envp loops                       |
| Linear search                     | `find_and_print_name`            |
| Exact string matching             | `name_matches_environment_entry` |
| Prefix-boundary checking          | require `=` after requested name |
| Returning a pointer into a string | value pointer after `=`          |
| C-string measuring                | `write_c_string_fd`              |
| Missing-name accumulation         | `r15` flag                       |
| stdout/stderr separation          | fd `1` vs fd `2`                 |

That makes this a strong 00-level companion note.

It takes the `env` idea and adds just enough comparison logic to become more interesting.

---

## Suggested experiments

Print everything:

```sh id="8lrdh4"
./build/printenv | head
```

Print one known variable:

```sh id="3h4mpe"
./build/printenv HOME
echo $?
```

Print several:

```sh id="5sjbbq"
./build/printenv HOME PATH SHELL
echo $?
```

Try a missing one:

```sh id="e1f1tl"
./build/printenv DEFINITELY_NOT_REAL
echo $?
```

Try a mix of present and missing:

```sh id="hfnp6h"
./build/printenv HOME DEFINITELY_NOT_REAL PATH
echo $?
```

The values that exist should still print, but the final status should be failure.

Try an unsupported option:

```sh id="gsdvxw"
./build/printenv --help
echo $?
```

Try a name containing `=`:

```sh id="lm6kw9"
./build/printenv HOME=/tmp
echo $?
```

That last one is useful because it shows what this implementation does **not** do. It treats `HOME=/tmp` as a literal requested name, not as an assignment.

---

## Takeaway

`printenv.asm` is an environment-search lesson.

`env` walked the environment and printed every full string.

`printenv` walks the same environment, but now asks a sharper question:

```text id="u9ao8z"
does this requested name match the bytes before '='?
```

The important detail is the boundary check.

Matching `PATH` against `PATH=/usr/bin` is correct.

Matching `PATH` against `PATHNAME=something` would be wrong.

That is why the helper does not stop at “the requested bytes matched.” It also requires the next byte in the environment entry to be `=`.

That one extra check is the difference between a prefix match and a correct name match.

Small detail.

Big lesson.
