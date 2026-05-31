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
