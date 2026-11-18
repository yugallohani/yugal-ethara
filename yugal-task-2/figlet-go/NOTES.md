# NOTES: pyfiglet

| Item | Value |
|---|---|
| URL | https://github.com/pwaller/pyfiglet |
| Commit SHA | `255827efbc09d662875dad50fa0edc1e1263bf45` |
| Commit date | `2026-08-02T22:51:18+01:00` (`git log -1 --format='%H %cI'`) |
| Version | 1.0.4 (`pyfiglet/version.py`) |
| Licence | MIT (`LICENSE`, also `setup.py: license='MIT'`) |

## What it is

pyfiglet is a pure-Python port of FIGlet. It reads a FIGlet font (`.flf`), turns each
character of the input text into a block of ASCII art rows, squeezes neighbouring
blocks together (kerning or smushing), wraps at a terminal width, justifies the rows,
and can mirror (`-r`) or flip (`-F`) the result. All rendering lives in
`pyfiglet/__init__.py` (`FigletFont`, `FigletBuilder`, `FigletString`, `main`).

## Why `python -m pyfiglet hello` fails right after cloning

The code loads fonts with `importlib.resources.files('pyfiglet.fonts')`, but a fresh
clone has no `pyfiglet/fonts/` folder. The fonts live in `pyfiglet/fonts-standard/`
(and `fonts-contrib/`). The error is:

```
ModuleNotFoundError: No module named 'pyfiglet.fonts'
```

The `Makefile` target `minimal` fixes it (after `clean` creates the folder):

```
rm -rf pyfiglet/fonts/ && mkdir pyfiglet/fonts/
cp pyfiglet/fonts-standard/* pyfiglet/fonts
```

`fonts-standard/` contains an `__init__.py`, so the copy also makes `pyfiglet.fonts`
an importable package. (`setup.py` does the same with `shutil.copytree`.) After the
copy, `python3 -m pyfiglet -f slant hello` prints the slanted banner. Verified locally.

## Font header and layout bits

Header: `flf2a<hardblank> height baseline maxlen oldlayout commentlines [direction [fulllayout]]`.
If `fulllayout` is missing: `oldlayout == 0 -> 64`, `< 0 -> 0`, else `(old & 31) | 128`.

| Bit | Name | Meaning |
|---|---|---|
| 1 | SM_EQUAL | rule 1 |
| 2 | SM_LOWLINE | rule 2 |
| 4 | SM_HIERARCHY | rule 3 |
| 8 | SM_PAIR | rule 4 |
| 16 | SM_BIGX | rule 5 |
| 32 | SM_HARDBLANK | rule 6 |
| 64 | SM_KERN | kerning only |
| 128 | SM_SMUSH | smushing on; if no rule bit (1..32) is set: universal smushing |

Fonts used by the task (all `printDirection = 0`, so `-D auto` is left-to-right):

| Font | layout | Mode |
|---|---|---|
| standard, big | 24463 | smush, rules 1-4 |
| slant | 18319 | smush, rules 1-4 |
| small | 22415 | smush, rules 1-4 |
| mini | 1920 | universal smushing |
| shadow | 4992 | universal smushing |
| banner, script | 64 / 3904 | kerning only |

None of the eight fonts sets rule 5 (BIGX) or rule 6 (HARDBLANK).

## Smushing rules (`FigletBuilder.smushChars`, checked against the real code)

Order of checks in `smushChars(left, right)`:

1. A space on either side: return the other character.
2. If the previous or current character is narrower than 2 columns: no smush.
3. If SM_SMUSH is off (kerning only): no smush.
4. If no rule bits are set (universal): a hardblank loses to the other character;
   otherwise the later character in the text wins (`right` for LTR, `left` for RTL).
5. Then the controlled rules below. A hardblank against anything else never smushes
   (unless rule 6 and both are hardblanks).

| # | Rule | Example (left + right -> result) | Verified with |
|---|---|---|---|
| 1 | Equal character | `|` + `|` -> `|`;  `_` + `_` -> `_` | `smushChars` and `pyfiglet -f standard '||'` |
| 2 | Underscore | `_` + `|` -> `|`;  `/` + `_` -> `/` (the `_` is replaced by any of `|/\[]{}()<>`) | `smushChars` |
| 3 | Hierarchy | classes `|` < `/\` < `[]` < `{}` < `()` < `<>`; the higher class wins: `|` + `/` -> `/`, `[` + `{` -> `{`, `(` + `<` -> `<` | `smushChars` |
| 4 | Opposite pair | `[` + `]` -> `|`, `{` + `}` -> `|`, `(` + `)` -> `|` (either order, so `)` + `(` -> `|` too) | `smushChars` |
| 5 | Big X | `/` + `\` -> `|`, `\` + `/` -> `Y`, `>` + `<` -> `X`; `<` + `>` does not smush | `smushChars` with layout 128+16 |
| 6 | Hardblank | `$` + `$` -> `$` (hardblank + hardblank) | `smushChars` with layout 128+32 |
| K | Kerning (layout 64) | blocks are moved together until they touch, no overlap. `banner` and `script` only kern | `pyfiglet -f banner` |

`smushAmount` decides how far the new block moves left: per row it counts the trailing
spaces of the left side plus the leading spaces of the right side, plus one more column
if the two touching characters can be smushed (or the left side is blank). The minimum
over all rows, capped at the width of the current character, is used.

## Options in scope

| Option | Effect |
|---|---|
| `-f FONT` | font name (default `standard`), looked up as `FONT.tlf` then `FONT.flf` |
| `-w COLS` | width for wrapping and justification (default 80). A line breaks when its width would reach `COLS` (`>=`), at the last space if there is one, otherwise before the current character |
| `-j auto\|left\|center\|right` | justification. `auto` = `left` for LTR, `right` for RTL. `right` pads each row with `COLS - len(row) - 1` spaces; `center` pads with `int((COLS - len(row)) / 2)` spaces. Uses the `-w` value, not 80 |
| `-D auto\|left-to-right\|right-to-left` | print direction; `auto` uses the font header. RTL swaps the two sides when smushing, so the new character goes on the left |
| `-r` | mirror each row: reverse it and swap `/`<->`\`, `(`<->`)`, `[`<->`]`, `{`<->`}`, `<`<->`>` |
| `-F` | flip vertically: reverse the row order and swap `/`<->`\`, `^`<->`v`, `A`<->`V`, `M`<->`W`, `m`<->`w`, `b`<->`P`; also `R`->`b`, `_`->`-` (one-way) |
| `-s` | drop leading blank rows and all trailing whitespace (wins over `-n`) |
| `-n` | like `-s`, then one empty line before and after |

`-r` runs before `-F`. The output is the rendered string followed by one `\n`.
Text = all positional arguments joined with a single space.
Out of scope: `-c`, `-L`, `-l`, `-i`.

## Rare cases (places where a naive reading is wrong)

1. **Big X is not "`/` + `\` -> X".** In this code `/\` -> `|`, `\/` -> `Y`, only `><` -> `X`. None of the task fonts enable it anyway.
2. **Characters narrower than 2 columns never smush** (`prevCharWidth < 2 or curCharWidth < 2`). They can still kern.
3. **After a wrap, `prevCharWidth` is not 0.** `cutBufferCommon` sets it to 0, but `addCharToProduct` overwrites it with the current width at the end. After an explicit `\n` it stays 0.
4. **The space that causes a wrap is dropped;** the next line starts at the character after the last space, and the saved buffer is the one from *before* the space was added.
5. **`-j right` pads to `COLS - 1`**, `-j center` uses truncating division, both per row. With RTL and `-j auto`, rows are right-justified.
6. **Python `'' in "abc"` is `True`.** When the smush window reaches past the start of the buffer, the empty "left" character matches every rule set.
7. **Characters missing from the font are skipped silently** (`é`, `ñ` in all task fonts). `standard` and `big` have `ÄÖÜäöüß` plus extra `0x...` codes.
8. **`-s` beats `-n`** (`elif`).
9. **Crashes and hangs in the original:** a character wider than `-w` raises `CharNotPrinted` (`pyfiglet -w 5 hello`). A character exactly as wide as `-w` with no leading blank column loops forever (`pyfiglet -f slant -w 11 '#'`, confirmed with a 3 s timeout). The generated cases exclude every input where the original crashes or hangs.
10. **The last line is only flushed if row 0 of the buffer is non-empty.**
11. **The `-F` map is lossy:** `_` becomes `-`, but `-` stays `-`.
