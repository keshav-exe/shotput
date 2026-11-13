#!/usr/bin/env python3
"""Checks the translations against the code.

The key is the English string, so the code is the source of truth: every `L("...")` in
Sources/ShotputKit must have an entry in Resources/<language>.lproj/Localizable.strings, and every
entry must still be used. Placeholders have to survive translation, or a label with a capture
count would come out as a bare %d.

    Scripts/check-localization.py            # missing and stale keys are warnings
    Scripts/check-localization.py --strict   # missing and stale keys are errors too
    Scripts/check-localization.py --missing  # print untranslated keys, ready to fill in

Exits non-zero on a broken translation file (duplicate key, empty value, placeholders that do not
match), so CI catches a translation that would show the wrong thing.

Python rather than shell: the check compares strings with accents, «ёлочки» and characters outside
the Basic Multilingual Plane, and a pipeline of sed and cut does that differently depending on the
machine it runs on. This parses both sides itself, so a green run here is a green run in CI.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "ShotputKit"
RESOURCES = ROOT / "Resources"

# L("...") in Swift, with escaped characters allowed inside the literal.
CALL = re.compile(r'L\("((?:[^"\\]|\\.)*)"\)')
# "key" = "value"; in a .strings file.
ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
# %@ %d %ld %1$@ and friends, so "a %@ b" cannot lose its placeholder in translation.
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:l{0,2}[@dfsux])")

RED = "\033[31m"
YELLOW = "\033[33m"
BOLD = "\033[1m"
RESET = "\033[0m"


def unescape(text: str) -> str:
    """Turns the escapes of a quoted literal into the characters they stand for."""
    out = []
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text):
            following = text[index + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}.get(following, following))
            index += 2
            continue
        out.append(char)
        index += 1
    return "".join(out)


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def code_keys() -> set[str]:
    """Every string the code asks for, in the form it is shown in."""
    keys = set()
    for path in sorted(SOURCES.rglob("*.swift")):
        for match in CALL.finditer(path.read_text(encoding="utf-8")):
            keys.add(unescape(match.group(1)))
    return keys


def parse(path: pathlib.Path) -> list[tuple[int, str, str]]:
    """Reads "key" = "value"; entries as (line number, key, value)."""
    text = path.read_text(encoding="utf-8")
    # Comments become blank lines, so line numbers in errors still point at the real file.
    text = COMMENT.sub(lambda match: "\n" * match.group(0).count("\n"), text)

    entries = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        match = ENTRY.match(line)
        if match is None:
            raise ValueError(f"{path}:{number}: not a \"key\" = \"value\"; line: {line.strip()[:80]}")
        entries.append((number, unescape(match.group(1)), unescape(match.group(2))))
    return entries


def placeholders(text: str) -> list[str]:
    return sorted(PLACEHOLDER.findall(text))


def main() -> int:
    # Line buffered, so a message on stderr does not jump ahead of the one on stdout.
    sys.stdout.reconfigure(line_buffering=True)
    parser = argparse.ArgumentParser(description="Checks the translations against the code.")
    parser.add_argument("--strict", action="store_true", help="missing and stale keys are errors too")
    parser.add_argument("--missing", action="store_true", help="print untranslated keys, ready to fill in")
    options = parser.parse_args()

    used = code_keys()
    broken = False

    files = sorted(RESOURCES.glob("*.lproj/Localizable.strings"))
    if not files:
        print(f"{RED}no translation files under {RESOURCES}{RESET}", file=sys.stderr)
        return 1

    for path in files:
        language = path.parent.stem
        print(f"{BOLD}Checking {language}{RESET}")

        try:
            entries = parse(path)
        except ValueError as error:
            print(f"{RED}{error}{RESET}", file=sys.stderr)
            return 1

        if not entries:
            print(f"{RED}{path} has no entries{RESET}", file=sys.stderr)
            return 1

        seen: dict[str, int] = {}
        translated: set[str] = set()
        for number, key, value in entries:
            # A duplicate would silently win over the other at run time.
            if key in seen:
                print(f"{RED}duplicate key in {language}, lines {seen[key]} and {number}: {key}{RESET}", file=sys.stderr)
                broken = True
            seen.setdefault(key, number)
            translated.add(key)

            # An empty value shows a blank label instead of English.
            if not value:
                print(f"{RED}empty translation in {language} for: {key}{RESET}", file=sys.stderr)
                broken = True
            # A lost or renamed placeholder prints raw or crashes.
            elif placeholders(key) != placeholders(value):
                print(
                    f"{RED}placeholders differ in {language}: \"{key}\" -> \"{value}\"{RESET}",
                    file=sys.stderr,
                )
                broken = True

        stale = sorted(translated - used)
        if stale:
            message = f"{len(stale)} key(s) in {language} no longer used: {', '.join(stale[:5])}"
            if options.strict:
                print(f"{RED}{message}{RESET}", file=sys.stderr)
                broken = True
            else:
                print(f"{YELLOW}{message}{RESET}", file=sys.stderr)

        missing = sorted(used - translated)
        if missing:
            if options.missing:
                for key in missing:
                    print(f'"{escape(key)}" = "";')
            else:
                message = (
                    f"{len(missing)} key(s) untranslated in {language}, shown in English: "
                    f"{', '.join(missing[:3])}"
                )
                if options.strict:
                    print(f"{RED}{message}{RESET}", file=sys.stderr)
                    broken = True
                else:
                    print(f"{YELLOW}{message}{RESET}", file=sys.stderr)

        print(f"{BOLD}{language}: {len(translated)} translated, {len(missing)} to go{RESET}")

    if broken:
        return 1
    if not options.missing:
        print(f"{BOLD}Translations check out{RESET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())