# Notes: `wc`

`wc` is the repository's clearest example of turning a byte stream into several
state machines at once. Read `src/wc.asm` for the canonical daily-use command;
read `lessons/wc/01-default-counters.asm` for the earlier stage that always
prints only lines, words, and bytes.

## Supported surface

```text
wc [-l] [-w] [-c] [-m] [-L] [--] [FILE...]
```

Selectors combine. The first selector replaces the default `-lwc` set, and
fields always appear in `l w m c L` order. A literal `-` means fd 0 at that
point in operand order. File descriptors can be reopened, but stdin cannot be
rewound, so repeated `-` operands naturally continue from the same stream.

Output deliberately uses one space between decimal fields instead of GNU's
column padding. Tests normalize only that presentation difference when checking
compatible count values against GNU coreutils 9.4.

## One scan, several states

For every input byte the scanner may update:

- `cur_bytes`, by the successful `read(2)` byte count;
- `cur_lines`, when the byte is newline;
- `cur_words`, when a non-whitespace byte follows whitespace;
- `cur_chars`, through the documented UTF-8 decoder state; and
- `cur_line` / `cur_max`, for byte length between newline bytes.

The input buffer is not a line buffer. A line, word, or UTF-8 sequence may cross
a 4096-byte read boundary because the relevant state survives between reads.
That is the important streaming lesson: boundaries chosen by `read(2)` have no
semantic meaning.

## Character policy without libc or locale

Calling bytes “characters” would be misleading, but implementing locale tables
would obscure the command. The canonical source therefore uses one explicit,
locale-independent UTF-8 policy:

- ASCII and structurally valid UTF-8 lead bytes begin a character;
- continuation bytes complete the current character;
- each malformed byte begins one replacement character; and
- an incomplete final sequence counts once because its lead byte already began
  a character.

This is structural decoding, not Unicode normalization, grapheme clustering, or
terminal width. Tests cover valid multibyte text and malformed bytes directly.

`-L` intentionally remains simpler: it counts input bytes excluding newline,
including a final unterminated line. It does not claim GNU's locale-sensitive
display-column semantics.

## Checked totals

Every counter is unsigned 64-bit. An increment or addition that carries is an
error; it never silently wraps. Totals are checked in temporary registers before
any total is committed, so overflow cannot leave a half-updated total record.
Line/word/byte/character totals sum successful inputs, while the total `-L` is
the maximum of their maxima.

## Error and I/O policy

`read(2)` retries `EINTR`. `write_all` retries `EINTR` and advances through
partial writes. Missing and unreadable operands are diagnosed by name, later
operands are still attempted, and any failure produces final status 1. A stdout
failure stops further presentation because continuing cannot produce a useful
result.

The command does not decode errno names and does not implement GNU long-option
aliases. Those omissions are documented compatibility boundaries, not silent
fallbacks.
