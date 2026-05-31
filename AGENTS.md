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
