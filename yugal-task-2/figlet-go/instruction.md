# Port pyfiglet to Go

## 1. The repository

`/workspace/repo` contains pyfiglet 1.0.4 (MIT licence, commit
`255827efbc09d662875dad50fa0edc1e1263bf45`), a pure-Python implementation of FIGlet.
It reads FIGlet fonts (`.flf` files in `pyfiglet/fonts/`), turns each character of the
input text into a block of ASCII-art rows, squeezes neighbouring blocks together
(kerning, or "smushing" by the font's layout rules), wraps lines at a given width,
justifies them, and can mirror or flip the result. The rendering logic is in
`pyfiglet/__init__.py` (classes `FigletFont`, `FigletBuilder`, `FigletString` and the
function `main`). There is no Python interpreter in this environment.

## 2. What to build

Replace pyfiglet with a Go program in `/workspace/repo`. Running

```
cd /workspace/repo && go build -o /tmp/figlet .
```

must produce a command-line program that behaves like `python -m pyfiglet` for these
options:

| Option | Meaning |
|---|---|
| `-f FONT` | font name, without extension (default `standard`) |
| `-w COLS` | width used for line wrapping and for justification (default `80`) |
| `-j auto\|left\|center\|right` | justification (default `auto`) |
| `-D auto\|left-to-right\|right-to-left` | print direction (default `auto`) |
| `-r` | mirror the output |
| `-F` | flip the output upside down |
| `-s` | strip surrounding empty lines |
| `-n` | normalize surrounding empty lines |

The program is called with the options first, each as its own argument (`-w 40`, not
`-w40`; `-r -F`, not `-rF`), followed by the text as one or more arguments. As in
pyfiglet, the text is all of those arguments joined with a single space. No text
argument starts with `-`. The text may contain any Unicode characters, including
spaces, newlines and characters the font does not define.

For every such call, the program's standard output must be identical, byte for byte, to
what pyfiglet 1.0.4 at the commit above writes to standard output, including every
space and the final newline. `-j center` and `-j right` justify within the `-w` width
(80 if `-w` is not given), exactly as pyfiglet does. Only inputs for which pyfiglet
exits normally are checked; inputs where pyfiglet raises an exception or never
finishes are not.

Fonts used: `standard`, `slant`, `small`, `big`, `mini`, `banner`, `shadow`, `script`,
as shipped in this repository.

## 3. Fonts

You may move the `.flf` files (or embed them in the binary), but they must stay inside
`/workspace/repo`. The built program must work when run from any working directory and
when the binary is located outside the repository (for example `/tmp/figlet`).

## 4. Hard rules

- Go standard library only (no third-party modules).
- When you finish, there must be no `.py` file anywhere under `/workspace/repo`.
- `go build ./...` in `/workspace/repo` must succeed.

## 5. Not checked

Speed, memory use, error messages, exit codes, standard error, and the options `-c`,
`-L`, `-l` and `-i`.

## 6. Grading

Grading is automatic and gives partial credit. It builds the program with the command
in section 2, checks that no `.py` file remains, and compares the program's standard
output with pyfiglet's on a large set of inputs that you do not see.
