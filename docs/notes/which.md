# Notes: `which`

`which` is a great command for deflating a little bit of shell mystique.

At the shell level, it feels like:

> tell me where this command comes from

At the assembly level, this teaching version does something much more concrete:

> split `PATH` into directories, join each directory with the command name, and ask the kernel whether that candidate is executable

No shell magic is required for the first useful version.

No aliases.

No functions.

No hashed command table.

No builtin detection.

Just strings, candidate paths, and `access(2)`.

Keep `src/which.asm` open beside this note. The interesting center of the file is the path from:

```text
ls
```

to candidates like:

```text
/usr/local/bin/ls
/usr/bin/ls
/bin/ls
```

until one of them passes the executable check.

---

## What this command really does

This teaching version accepts one or more command-name operands.

For each operand:

| Left pane: code idea                | Right pane: human meaning                                  |
| ----------------------------------- | ---------------------------------------------------------- |
| Find `PATH` in `envp`               | “Where should command names be searched?”                  |
| If `PATH` is missing, use a default | “Still have a simple fallback search path.”                |
| Check whether operand contains `/`  | “If it already looks like a path, do not search PATH.”     |
| Split PATH on `:`                   | “Try each directory component.”                            |
| Build `directory/command`           | “Make one candidate pathname.”                             |
| Call `access(candidate, X_OK)`      | “Can this process execute it?”                             |
| Print first successful candidate    | “This is the command path.”                                |
| Remember failures                   | “If any operand is missing, final exit status is failure.” |

That is the whole command.

The source says it intentionally does **not** implement options like `-a`, shell aliases/functions/builtins, permission details, hashed command tables, `--help`, or `--version`. 

That is a good boundary. This file is teaching PATH lookup, not trying to impersonate the shell.

---

## `which` is not the shell

This is worth saying early.

A shell may know about things that are not executable files in PATH:

```text
aliases
functions
builtins
hashed command locations
```

This teaching version does not know about those.

So a command like:

```sh
which cd
```

may not behave like your shell’s own command lookup, because `cd` is usually a shell builtin, not an external executable found by searching PATH.

That is not a bug in this teaching version.

It is a scope line.

This version answers a narrower question:

> if this name maps to an executable pathname, where is the first match?

That is already enough to teach the real mechanics underneath the common case.

---

## Startup setup

The program begins with the familiar raw process entry setup:

```asm
mov r12, [rsp]
lea r13, [rsp + 8]
mov r14, 1
xor r15d, r15d
```

Read those as:

| Register | Meaning                     |
| -------- | --------------------------- |
| `r12`    | `argc`                      |
| `r13`    | pointer to the `argv` array |
| `r14`    | current operand index       |
| `r15`    | accumulated failure status  |

That last register is the usual “keep working, but remember trouble” flag.

If any requested command is not found, `r15` becomes nonzero. Later operands are still attempted.

At the end, the process exits with `r15`.

So this works like a useful command-line tool:

```text
find what can be found
complain about what cannot
exit failure if anything was missing
```

---

## Missing operand

The command requires at least one operand.

So:

```sh
./build/which
```

prints a missing-operand diagnostic and exits failure.

That check happens before PATH lookup. No point finding PATH if there is no command name to search for.

This is a nice practical ordering habit:

> reject impossible command shapes before doing setup work

Small thing, but it keeps control flow sane.

---

## Finding `PATH` in `envp`

Before processing command names, the program computes where `envp` begins:

```asm
lea rdi, [r13 + r12*8 + 8]
call find_path_env
```

This is the same stack-layout idea from `env` and `printenv`.

Starting at `argv[0]`, skip:

```text
argc argv pointers
plus the NULL after argv
```

and you land on `envp[0]`.

Then `find_path_env` walks the environment pointer array looking for an entry that starts with:

```text
PATH=
```

The source has a fixed string for that name:

```asm
path_name: db "PATH=", 0
```

When it finds a match, it returns a pointer just after the prefix. 

So if the environment entry is:

```text
PATH=/usr/local/bin:/usr/bin:/bin
```

the returned pointer points at:

```text
/usr/local/bin:/usr/bin:/bin
```

Not at `PATH`.

Not at `=`.

At the value.

---

## Default PATH fallback

If `PATH` is not present, the source falls back to:

```text
/usr/local/bin:/usr/bin:/bin
```

That default is stored in `.rodata`. 

This is a small but useful behavior choice.

The command can still perform a reasonable search even if the inherited environment does not provide PATH.

The flow is:

```text
try envp PATH
if present, use it
if missing, use default_path
```

That keeps later code simpler. `find_command` always receives some PATH string to scan.

It does not need a special “no PATH exists” mode.

---

## One PATH value, many operands

The source finds PATH once, then reuses it for every command operand.

That happens here:

```asm
mov rbx, rax
```

`rbx` holds the PATH value pointer while the operand loop runs.

That is a practical design:

| Thing           | How often it changes |
| --------------- | -------------------- |
| PATH value      | once per process     |
| command operand | once per argv entry  |

So the program does not rescan `envp` for every command.

It finds PATH once and then resolves each requested command against that same value.

That is the kind of small efficiency choice that also makes the code easier to reason about.

---

## The operand loop

The main operand loop starts at `argv[1]`.

For each operand:

```text
load command name
call find_command(command, PATH)
if found, move on
if not found, print diagnostic and mark failure
```

The source comment states the loop invariant directly: `r15` is nonzero once any operand has not been found. 

So for:

```sh
./build/which sh definitely-not-real ls
```

the program should still try all three operands.

It may print paths for `sh` and `ls`, complain about the missing one, and exit failure overall.

Again: keep working, but do not lie.

---

## Slash changes everything

The first major branch inside `find_command` is:

```asm
call contains_slash
```

If the operand contains `/`, the program does **not** search PATH.

That is standard command-lookup behavior.

These are already path-like:

```text
./script
/bin/sh
../tool
```

So `which` should test them directly.

The source comment says operands containing `/` bypass PATH; simple names try each PATH directory joined with a slash. 

That gives two paths:

| Operand shape | Behavior              |
| ------------- | --------------------- |
| contains `/`  | test operand directly |
| no `/`        | search PATH           |

That single slash scan controls the whole lookup mode.

---

## `contains_slash`: plain byte scan

The slash check is simple:

```text
while byte is not NUL:
    if byte is '/':
        return yes
    advance
return no
```

The source implements that directly. 

No parser.

No pathname library.

No filesystem question.

Just:

> does this string contain slash byte `47`?

That is enough to decide whether PATH search applies.

This is a recurring theme in these commands: lots of “command behavior” begins as byte-string classification.

---

## Direct path mode

If the operand contains `/`, the program calls:

```asm
is_executable
```

on the operand itself.

If that succeeds, it prints the operand.

So:

```sh
./build/which /bin/sh
```

does not search PATH for `sh`.

It asks:

```text
is /bin/sh executable for this process?
```

If yes, print:

```text
/bin/sh
```

This is a clean distinction:

| Input        | Question                      |
| ------------ | ----------------------------- |
| `sh`         | “Where in PATH is `sh`?”      |
| `/bin/sh`    | “Is `/bin/sh` executable?”    |
| `./myscript` | “Is `./myscript` executable?” |

Once the user includes a slash, they have already supplied a path shape.

---

## PATH search mode

If the operand has no slash, `find_command` begins scanning PATH.

PATH is a colon-separated list:

```text
/usr/local/bin:/usr/bin:/bin
```

The code treats each component as the bytes between colons.

The loop uses:

| Register | Meaning                    |
| -------- | -------------------------- |
| `r9`     | scan pointer through PATH  |
| `r10`    | start of current component |

The scan advances `r9` until it sees either:

```text
:
```

or:

```text
NUL
```

That gives a component range:

```text
[r10, r9)
```

In plain English:

> the current directory component starts at `r10` and ends just before `r9`

That range is then passed to `build_candidate`.

---

## PATH components are ranges, not copied strings yet

This is a useful low-level idea.

While scanning PATH, each component is not automatically copied into a new string.

The program just remembers:

```text
start pointer
end pointer
```

So for:

```text
/usr/local/bin:/usr/bin:/bin
```

the first component is:

```text
start -> /usr/local/bin
end   -> colon
```

The colon stays in the original PATH string.

The program does not modify PATH.

It uses pointer ranges to describe pieces of PATH, then copies only when building a candidate.

That is efficient and clear.

---

## Building a candidate pathname

The helper:

```asm
build_candidate
```

receives:

| Register | Meaning         |
| -------- | --------------- |
| `rdi`    | component start |
| `rsi`    | component end   |
| `rdx`    | command name    |

It writes a NUL-terminated candidate path into the fixed `candidate` buffer.

Conceptually:

```text
copy PATH component
write '/'
copy command name
write NUL
```

So if the component is:

```text
/usr/bin
```

and the command name is:

```text
ls
```

the candidate becomes:

```text
/usr/bin/ls
```

The source reserves a 4096-byte candidate buffer for this job. 

That buffer is reused for each PATH component.

---

## Empty PATH components mean current directory

PATH can contain empty components.

For example:

```text
:/usr/bin
```

or:

```text
/usr/bin::/bin
```

An empty component traditionally means the current directory.

This source handles that by writing:

```text
.
```

as the component, so the printed candidate becomes explicit:

```text
./command
```

The source comment calls that out directly: an empty PATH component means the current directory, written here as `"."` so the printed answer is explicit. 

That is a nice teaching choice.

It makes the hidden meaning visible instead of printing a path that starts awkwardly with just `/command`.

---

## Candidate length checks

`build_candidate` checks that the candidate will fit in the fixed buffer.

If copying the component or command name would exceed the buffer, it returns failure for that candidate.

That is another practical low-level lesson:

> fixed buffers need boundaries

The helper tracks candidate length in `r10`.

Before adding bytes, it compares against limits based on `CANDIDATE_SIZE`.

This is not glamorous code, but it is the difference between “copy bytes safely” and “scribble past the buffer.”

For a teaching implementation, returning “candidate too long” as “not found here” is a reasonable simplification.

---

## The executable check

The helper:

```asm
is_executable
```

calls:

```text
access(path, X_OK)
```

The syscall setup is:

| Register | Meaning                        |
| -------- | ------------------------------ |
| `rax`    | syscall number for `access(2)` |
| `rdi`    | pathname                       |
| `rsi`    | `X_OK`                         |

`X_OK` asks:

> may this process execute this path?

The source comments state that `access(2)` asks the kernel whether this process may execute the path. 

That is the kernel-side test.

The program does not open the file.

It does not inspect mode bits itself.

It asks the kernel one yes/no question.

---

## First match wins

As soon as a candidate passes `access(X_OK)`, the program prints it and returns found.

That means PATH order matters.

Given:

```text
PATH=/custom/bin:/usr/bin:/bin
```

and command:

```text
thing
```

the search order is:

```text
/custom/bin/thing
/usr/bin/thing
/bin/thing
```

The first executable candidate wins.

This version does not implement `which -a`, which would print all matches.

That is intentionally missing. The source says options such as `-a` are not implemented. 

So the behavior is:

```text
search in PATH order
print first executable match
stop searching this operand
```

Simple and correct for the narrow version.

---

## Not found is per operand

If no candidate works, `find_command` returns zero.

The caller then prints:

```text
which: NAME not found
```

to stderr and sets the accumulated failure status.

Then it moves on to the next operand.

So:

```sh
./build/which sh not-real ls
```

is not all-or-nothing.

Each operand is independent.

That independence is good command behavior:

| Operand       | Result                         |
| ------------- | ------------------------------ |
| found         | print path                     |
| missing       | print diagnostic, mark failure |
| later operand | still attempted                |

The final exit status summarizes whether every requested lookup succeeded.

---

## `starts_with_c_string`: matching `PATH=`

The helper used by `find_path_env` is:

```asm
starts_with_c_string
```

It compares a candidate string against a required prefix until the prefix reaches its NUL terminator.

For this file, the important use is:

```text
does this environment entry start with "PATH="?
```

The `=` is part of the prefix.

That prevents a false match like:

```text
PATHNAME=something
```

Because `PATHNAME=` does not start with `PATH=`.

That is the same boundary lesson from `printenv`: when matching environment names, checking the separator matters.

---

## Printing the result

When a path is found, the program calls:

```asm
write_c_string_stdout_line
```

That helper writes the NUL-terminated pathname, then writes a newline.

So the found path:

```text
/usr/bin/ls
```

becomes output:

```text
/usr/bin/ls\n
```

The candidate buffer must be NUL-terminated because the string-writing helper measures it by scanning for the zero byte.

That connects two pieces:

| Producer                           | Consumer                                        |
| ---------------------------------- | ----------------------------------------------- |
| `build_candidate` writes final NUL | `write_c_string_stdout_line` measures until NUL |

Low-level code is full of these small contracts.

If one helper promises a NUL-terminated string, the next helper can use C-string-style measuring.

---

## `write_all`: finish the output

This file uses a proper `write_all` helper.

That helper keeps writing until all requested bytes are written or a failure occurs.

It tracks:

| Register | Meaning                         |
| -------- | ------------------------------- |
| `r9`     | next byte to write              |
| `r10`    | number of bytes still unwritten |

After each successful partial write:

```text
advance pointer
reduce remaining count
```

The source comments say exactly that: a partial write advances the pointer and retries remaining bytes. 

That is the right helper for command output that may include arbitrary path lengths.

---

## stdout and stderr

Found paths go to stdout.

Not-found diagnostics go to stderr.

That means:

```sh
./build/which sh not-real > found.txt
```

should put only successful paths in `found.txt`.

The complaint about `not-real` should go to stderr.

This is the usual composable command-line split:

| fd         | Purpose                   |
| ---------- | ------------------------- |
| `1` stdout | successful lookup results |
| `2` stderr | diagnostics               |

That matters because `which` output is often consumed by scripts.

A script wants stdout to contain paths, not error prose.

---

## What this file is quietly teaching

`which.asm` teaches a very reusable cluster of ideas:

| Concept                            | Where it appears        |
| ---------------------------------- | ----------------------- |
| Finding `envp` from startup stack  | `_start` setup          |
| Searching environment variables    | `find_path_env`         |
| Prefix matching with boundary      | `PATH=`                 |
| Reusing one PATH for all operands  | `rbx`                   |
| Accumulated status across operands | `r15`                   |
| Slash detection                    | `contains_slash`        |
| PATH bypass for path-like operands | direct `access(X_OK)`   |
| Colon-separated string scanning    | PATH component loop     |
| Pointer ranges                     | component start/end     |
| Candidate path construction        | `build_candidate`       |
| Empty PATH component handling      | `"."`                   |
| Fixed buffer boundary checks       | `CANDIDATE_SIZE`        |
| Kernel executability check         | `access(2)` with `X_OK` |
| First-match-wins behavior          | PATH order              |
| stdout/stderr separation           | results vs diagnostics  |

That is a lot of value for one command.

This is why `which` earns a note.

It turns a shell-ish behavior into visible string and syscall mechanics.

---

## Suggested experiments

Find a common command:

```sh
./build/which sh
echo $?
```

Try several:

```sh
./build/which sh ls definitely-not-real
echo $?
```

You should get paths for the commands that exist, a diagnostic for the missing one, and a failure exit status overall.

Try a direct path:

```sh
./build/which /bin/sh
echo $?
```

Because the operand contains `/`, PATH should be skipped.

Try a relative path:

```sh
./build/which ./some-script
echo $?
```

Again, PATH should be skipped because the operand contains `/`.

Try a missing command:

```sh
./build/which no-such-command-here
echo $?
```

Try changing PATH for one run:

```sh
PATH=/bin ./build/which sh
```

Then try a restricted PATH that probably misses something:

```sh
PATH=/tmp ./build/which sh
echo $?
```

Try an empty PATH component if your shell allows this form:

```sh
PATH=:/bin ./build/which my-local-script
```

An empty component means current directory, and this implementation writes it explicitly as:

```text
./my-local-script
```

when building the candidate.

---

## Takeaway

`which.asm` is a PATH-search lesson.

It shows that the common case of command lookup is not mystical:

```text
get PATH
split on ':'
join each directory with the command name
ask the kernel whether the candidate is executable
print the first match
```

The shell may add layers on top of that: aliases, functions, builtins, cached lookups, and special rules.

This teaching version does not chase those layers.

It teaches the durable core:

```text
PATH lookup is string work plus access(X_OK)
```

That is the valuable part.

Once that clicks, `which` stops feeling like a magical command oracle and starts looking like what it is here:

> a careful loop over candidate pathnames.
