Before changing docs, identify the source of truth:
- roadmap.md = implementation order
- command_index.tsv = implemented/planned command metadata
- commands.md = notes about implemented commands
- Makefile TOOLS = build list
- src/*.asm = actual source files

Do not infer implemented commands from roadmap alone.
When updating command lists, cross-check command_index.tsv, Makefile, and src/.

Educational readability is a correctness requirement.

If a utility works but the implementation is too clever, too compressed, or too poorly commented for a beginner/intermediate reader to learn from, treat that as a failed implementation and rewrite it more plainly.

Commenting standard for assembly sources:
- Comment every syscall setup: syscall number, argument registers, and what each argument means.
- Comment register roles when a register becomes a long-lived variable, such as `r12 = argc` or `r14 = envp`.
- Comment loop purpose and loop invariant before non-trivial loops.
- Comment helper routine contracts with:
  - input registers
  - output registers
  - clobbered registers, when relevant
  - what concept the helper teaches
- Comment non-obvious instructions such as `div`, `mul`/`imul`, `loop`, `syscall`, bit shifting, masking, and right-to-left number formatting.
- Prefer “why this works” comments over comments that merely restate the instruction.
- Avoid noisy comments on obvious moves when the surrounding concept is already clear: comments need not be every line, but should lean into being more informative than not.

## Orient from the repository before implementing

Do not approach a new utility as an isolated assembly exercise.

This repository contains a growing body of canonical NASM code, lessons, tests, documentation, and prior design decisions. That existing work is part of the implementation context. Use it.

Before designing or writing a substantial command:

1. Read the relevant project guidance, especially `README.md`, `docs/style_guide.md`, `docs/roadmap.md`, and the command contract in `docs/commands.md`.

2. Inspect several existing canonical `src/*.asm` implementations that exercise mechanisms related to the new work. Prefer mature commands when available. Look at how this repository handles:

   * process entry and argv parsing;
   * long-lived register ownership;
   * syscall setup and documentation;
   * buffered and streaming I/O;
   * `EINTR` and partial writes;
   * numeric parsing and formatting;
   * pathname handling;
   * aggregate failure status;
   * option parsing;
   * fixed-buffer boundaries;
   * diagnostics;
   * tests and reference comparisons.

3. Inspect relevant `lessons/` sources when they exist. They show which mechanisms were considered pedagogically distinct and why the canonical implementation became more elaborate.

4. Inspect existing tests for comparable commands before designing the new tests. Follow established project conventions rather than inventing an unrelated testing style.

The goal is not to copy code mechanically. The goal is to understand the local assembly dialect and continue it.

Treat existing source as evidence of project judgment. When several established commands solve a problem in a clear and similar way, begin from that precedent unless there is a concrete reason to depart from it. When implementations intentionally differ, understand why before trying to unify them.

Do not ignore the existing codebase and substitute generic assembly style, size-coding tricks, unnecessary abstractions, macro frameworks, or a fresh personal architecture. A new command should look like it was written by someone who has already lived in this repository.

Readable and explainable outweigh clever and compact.

## New canonical utilities

The initial breadth/primer phase has provided enough mechanism-level examples.

New command names should no longer be added to `src/` merely because a small implementation demonstrates a new syscall or algorithm. Mechanism-only stages belong under `lessons/<command>/` when they are educationally useful.

A new canonical `src/<command>.asm` should be designed as a real BusyBox-style utility: deliberately smaller than exhaustive GNU implementations, but sufficiently complete, robust, and conventional to serve as a practical replacement for the functionality it claims.

Use this question as the stopping criterion:

> If this were the implementation available in a small BusyBox-like userland, would the supported command be useful and dependable rather than obviously a teaching stub?

Distinct mechanisms help decide what is worth implementing next. BusyBox-like usefulness determines when the canonical implementation is finished.
