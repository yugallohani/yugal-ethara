#!/usr/bin/env python3
"""Generate the frozen answer files for the figlet-go task.

Runs on the task author's machine, NOT inside Docker. It expects the pyfiglet
checkout (at commit 255827efbc09d662875dad50fa0edc1e1263bf45, with the font
setup step done: pyfiglet/fonts/ populated from pyfiglet/fonts-standard/)
next to the task folder or in one of its parent folders, for example:

    harbour-practice/
        pyfiglet/            <- original project
        yugal-task-2/
            figlet-go/tests/gen.py

Set PYFIGLET_DIR=/path/to/pyfiglet to use a checkout somewhere else.

Every "out" value is captured from the ORIGINAL pyfiglet main(). Nothing is
written by hand. Inputs on which pyfiglet raises or does not finish are
skipped and replaced by the next random draw, so the files only contain
inputs where pyfiglet exits normally.

Usage:  python3 tests/gen.py
"""

from __future__ import annotations

import collections
import io
import json
import random
import signal
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def find_pyfiglet() -> Path:
    """PYFIGLET_DIR if set, else the nearest pyfiglet/ beside the task folder or above it."""
    import os

    if os.environ.get("PYFIGLET_DIR"):
        return Path(os.environ["PYFIGLET_DIR"]).resolve()
    for parent in HERE.parents[1:]:
        candidate = parent / "pyfiglet"
        if (candidate / "pyfiglet" / "__init__.py").is_file():
            return candidate
    return HERE.parents[1] / "pyfiglet"  # check_checkout() reports it missing


PYFIGLET_ROOT = find_pyfiglet()
EXPECTED_SHA = "255827efbc09d662875dad50fa0edc1e1263bf45"

N_VISIBLE = 2000
N_HIDDEN = 2000
TIMEOUT_SEC = 2.0

FONTS = ["standard", "slant", "small", "big", "mini", "banner", "shadow", "script"]
WIDTHS = [10, 20, 40, 60, 80, 120]
JUSTIFY = ["auto", "left", "center", "right"]
DIRECTION = ["auto", "left-to-right", "right-to-left"]

WORDS = [
    "hello", "world", "go", "port", "figlet", "harbor", "twin", "shout", "giant",
    "letters", "Smush", "Kern", "ABC", "xyz", "Test", "README", "OK", "wow",
    "pyfiglet", "Go123", "42", "3.14", "a", "I", "Mm", "Ww", "jig", "quick",
    "brown", "fox", "jumps", "over", "lazy", "dog", "HELLO", "Hi!", "why?",
    "a+b=c", "x*y", "50%", "#tag", "@home", "$5", "~ok~", "'quote'", '"dq"',
    "tab", "it's", "end.", "C3PO", "R2D2", "Zz", "Oo", "VvV", "MAX", "min",
]

# Rare cases from NOTES.md plus the hierarchy characters.
TRICKY = [
    "|_|", "||", "|||", "__", "_|_", "/\\", "\\/", "/\\/\\", "><", "<>", "[]",
    "][", "{}", "}{", "()", ")(", "[{(<>)}]", "_/", "\\_", "|/", "\\|", "/_\\",
    "(|)", "<|>", "{_}", "[_]", "i", "l", "!", ".", ",", ":", ";", "'", "`",
    "|", "/", "\\", "_", "[", "]", "{", "}", "(", ")", "<", ">", "^", "v",
    "$", "$$", "MW", "AV", "Pb", "mw", "#", "%", "&", "@", "~", "=", "+",
]
HIERARCHY_CHARS = "|/\\_[]{}()<>"

UNICODE = [
    "é", "ß", "ñ", "ü", "Ä", "Ö", "Ü", "ä", "ö", "café", "Straße", "niño",
    "Grüße", "Ärger", "Öl", "Übel", "naïve", "façade", "¡hola!", "¿qué?",
    "€", "→", "★", "日本", "Ā", "ł", "Ž", "Ω", "Жук", "αβγ", "\t", "\u00a0",
    "©", "°", "±", "µ", "½",
]

SENTENCES = [
    "the quick brown fox jumps over the lazy dog",
    "this sentence is long enough that it must wrap at narrow widths",
    "hello world from the machine that shouts in giant letters",
    "smushing rules stack and every space must match exactly",
    "go build then run and compare every byte of output",
    "Harbor runs the verifier after the agent has finished",
    "a b c d e f g h i j k l m n o p",
    "Mirror mirror on the wall who smushes best of all",
]


def check_checkout() -> None:
    head = PYFIGLET_ROOT / ".git" / "HEAD"
    if head.exists():
        sha = head.read_text().strip()
        if sha != EXPECTED_SHA:
            sys.exit(f"pyfiglet checkout is at {sha!r}, expected {EXPECTED_SHA}")
    if not (PYFIGLET_ROOT / "pyfiglet" / "fonts" / "standard.flf").exists():
        sys.exit(
            "pyfiglet/fonts/ is missing. Run the font setup first:\n"
            "  mkdir -p pyfiglet/pyfiglet/fonts && "
            "cp pyfiglet/pyfiglet/fonts-standard/* pyfiglet/pyfiglet/fonts/"
        )


def make_text(rng: random.Random) -> str:
    k = rng.random()
    if k < 0.25:
        return " ".join(rng.choice(WORDS) for _ in range(rng.randint(1, 3)))
    if k < 0.45:
        parts = [rng.choice(TRICKY) for _ in range(rng.randint(1, 3))]
        if rng.random() < 0.5:
            parts.insert(rng.randint(0, len(parts)), rng.choice(WORDS))
        sep = rng.choice(["", " ", ""])
        return sep.join(parts)
    if k < 0.55:
        return "".join(rng.choice(HIERARCHY_CHARS) for _ in range(rng.randint(2, 8)))
    if k < 0.63:
        a, b = rng.choice(WORDS), rng.choice(WORDS)
        return rng.choice([f"{a}  {b}", f"  {a}", f"{a}  ", f"{a}   {b}", f"{a} {b}  {a}"])
    if k < 0.78:
        s = rng.choice(SENTENCES)
        if rng.random() < 0.3:
            s = s + " " + rng.choice(SENTENCES)
        return s
    if k < 0.92:
        parts = [rng.choice(UNICODE) for _ in range(rng.randint(1, 3))]
        if rng.random() < 0.6:
            parts.insert(rng.randint(0, len(parts)), rng.choice(WORDS))
        return rng.choice(["", " "]).join(parts)
    if k < 0.96:
        a, b = rng.choice(WORDS), rng.choice(WORDS + TRICKY)
        return f"{a}\n{b}"
    return rng.choice(WORDS) + rng.choice(TRICKY) + rng.choice(WORDS)


def make_args(rng: random.Random) -> list[str]:
    args: list[str] = []
    font = rng.choice(FONTS)
    if font != "standard" or rng.random() < 0.7:
        args += ["-f", font]
    width = rng.choice(WIDTHS)
    if width != 80 or rng.random() < 0.7:
        args += ["-w", str(width)]
    justify = rng.choice(JUSTIFY)
    if justify != "auto" or rng.random() < 0.5:
        args += ["-j", justify]
    direction = rng.choice(DIRECTION)
    if direction != "auto" or rng.random() < 0.5:
        args += ["-D", direction]
    for flag in ("-r", "-F", "-s", "-n"):
        if rng.random() < 0.25:
            args.append(flag)

    text = make_text(rng)
    if " " in text and rng.random() < 0.35:
        words = text.split(" ")  # keeps empty strings, so the join is lossless
    else:
        words = [text]
    return args + words


class Timeout(Exception):
    pass


def _alarm(signum, frame):  # noqa: ARG001
    raise Timeout()


def run_original(argv: list[str]) -> bytes | None:
    """Run pyfiglet.main() in-process and return stdout bytes, or None on failure."""
    import pyfiglet

    raw = io.BytesIO()
    old_stdout, old_argv = sys.stdout, sys.argv
    sys.stdout = io.TextIOWrapper(raw, encoding="utf-8")
    sys.argv = ["pyfiglet"] + argv
    signal.signal(signal.SIGALRM, _alarm)
    signal.setitimer(signal.ITIMER_REAL, TIMEOUT_SEC)
    try:
        rc = pyfiglet.main()
    except (Exception, SystemExit, Timeout):
        return None
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        sys.stdout, sys.argv = old_stdout, old_argv
    if rc not in (0, None):
        return None
    return raw.getvalue()


def build(rng: random.Random, n: int, seen: set[tuple[str, ...]], stats: collections.Counter):
    cases = []
    while len(cases) < n:
        argv = make_args(rng)
        key = tuple(argv)
        if key in seen:
            stats["duplicate"] += 1
            continue
        if any(a.startswith("-") for a in argv[_text_start(argv):]):
            stats["dash_text"] += 1
            continue
        out = run_original(argv)
        if out is None:
            stats["rejected_error_or_hang"] += 1
            continue
        seen.add(key)
        cases.append({"args": argv, "out": out.decode("utf-8")})
    return cases


def _text_start(argv: list[str]) -> int:
    i = 0
    while i < len(argv):
        if argv[i] in ("-f", "-w", "-j", "-D"):
            i += 2
        elif argv[i] in ("-r", "-F", "-s", "-n"):
            i += 1
        else:
            break
    return i


def describe(name: str, cases: list[dict]) -> None:
    c = collections.Counter()
    for case in cases:
        a = case["args"]
        opts = a[: _text_start(a)]
        c["rtl"] += "right-to-left" in opts
        width = opts[opts.index("-w") + 1] if "-w" in opts else "80"
        c["narrow(<=20)"] += width in ("10", "20")
        c["rtl+narrow"] += ("right-to-left" in opts) and width in ("10", "20")
        c["wrapped(>1 block)"] += case["out"].count("\n") > 12
        for f in ("-r", "-F", "-s", "-n"):
            c[f] += f in opts
        for j in ("center", "right"):
            c["-j " + j] += j in opts
        c["multi-arg text"] += len(a) - _text_start(a) > 1
        c["newline in text"] += any("\n" in t for t in a[_text_start(a):])
    print(f"{name}: {len(cases)} cases; " + ", ".join(f"{k}={v}" for k, v in sorted(c.items())))


def write_jsonl(path: Path, cases: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for case in cases:
            fh.write(json.dumps(case, ensure_ascii=True, sort_keys=True) + "\n")


def main() -> None:
    check_checkout()
    sys.path.insert(0, str(PYFIGLET_ROOT))
    random.seed(7)
    rng = random.Random(7)
    seen: set[tuple[str, ...]] = set()
    stats: collections.Counter = collections.Counter()
    visible = build(rng, N_VISIBLE, seen, stats)
    hidden = build(rng, N_HIDDEN, seen, stats)
    write_jsonl(HERE / "data" / "visible.jsonl", visible)
    write_jsonl(HERE / "data" / "hidden.jsonl", hidden)
    describe("visible", visible)
    describe("hidden", hidden)
    print("skipped draws:", dict(stats))


if __name__ == "__main__":
    main()
