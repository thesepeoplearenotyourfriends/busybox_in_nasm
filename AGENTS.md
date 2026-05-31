Before changing docs, identify the source of truth:
- roadmap.md = implementation order
- command_index.tsv = implemented/planned command metadata
- commands.md = notes about implemented commands
- Makefile TOOLS = build list
- src/*.asm = actual source files

Do not infer implemented commands from roadmap alone.
When updating command lists, cross-check command_index.tsv, Makefile, and src/.
