#!/usr/bin/env python3
"""validate-gcx-invocations.py - catch stale gcx commands in skill markdown.

Extracts every `gcx ...` invocation from fenced code blocks and inline code
spans in skill markdown files, then validates the command path against the
command tree of a real gcx binary (`gcx help-tree`). This is the same idea as
the drift test gcx runs against its own bundled skills: when a gcx release
renames or removes a command, CI fails here instead of an agent failing at
runtime.

A command word only errors when it doesn't resolve at a point where gcx
expects a subcommand (a command group). Positional arguments after leaf
commands, flags, placeholders (<...>), paths (/...), and quoted strings are
all ignored.

Usage:
    ./scripts/validate-gcx-invocations.py [--gcx-bin PATH] [DIR ...]

Defaults: --gcx-bin gcx, DIR = skills. The binary version should match the
pin in .gcx-version (CI downloads and verifies exactly that version).
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# Flags that consume the following token as their value when written as
# "--flag value" (rather than "--flag=value").
VALUE_FLAGS = {
    "--context", "--config", "--jq", "--json", "--output", "-o",
    "--server", "--token", "--since", "--step", "--limit", "--namespace",
    "-H", "-d", "-X", "-f",
}

# A token starting with one of these can never be a subcommand word; it ends
# command-path matching for the invocation.
STOP_PREFIXES = ("<", "/", "'", '"', "{", "[", "$", "`")

GCX_RE = re.compile(r"(?:^|[\s`$(|;&={])gcx\s+([^\n]*)")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE_RE = re.compile(r"`([^`]+)`")


def load_tree(gcx_bin: str) -> dict:
    result = subprocess.run(
        [gcx_bin, "--agent", "help-tree"],
        capture_output=True, text=True, timeout=60,
    )
    if result.returncode != 0:
        sys.exit(f"error: '{gcx_bin} --agent help-tree' failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def children_of(node: dict) -> dict:
    return {c["name"]: c for c in node.get("children", [])}


def extract_invocations(text: str):
    """Yield (line_number, invocation_tail) pairs for every gcx call."""
    in_fence = False
    pending = ""  # accumulates backslash-continued lines inside fences
    pending_start = 0
    for lineno, line in enumerate(text.splitlines(), start=1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            pending = ""
            continue
        if in_fence:
            if line.lstrip().startswith("#"):
                # Shell comments are prose; matching them yields false
                # positives like "no gcx and no auth header".
                pending = ""
                continue
            if pending:
                line = pending + " " + line.strip()
                lineno = pending_start
            if line.rstrip().endswith("\\"):
                pending = line.rstrip()[:-1].rstrip()
                pending_start = lineno
                continue
            pending = ""
            for m in GCX_RE.finditer(line):
                yield lineno, m.group(1)
        else:
            for span in INLINE_CODE_RE.findall(line):
                for m in GCX_RE.finditer(span):
                    yield lineno, m.group(1)


def validate_invocation(tail: str, root: dict):
    """Return an error string if the invocation references an unknown
    subcommand, else None."""
    node = root
    path = ["gcx"]
    tokens = tail.split()
    i = 0
    while i < len(tokens):
        token = tokens[i]
        i += 1
        if token.startswith(STOP_PREFIXES):
            break
        if token.startswith("-"):
            if token in VALUE_FLAGS and i < len(tokens):
                i += 1  # skip the flag's value
            continue
        # Trim trailing shell/markdown closers so `token)"` matches `token`.
        word = token.rstrip(")\"'`;,.")
        if not re.fullmatch(r"[a-z][a-z0-9-]*", word):
            break
        kids = children_of(node)
        if word in kids:
            node = kids[word]
            path.append(word)
            continue
        if kids:
            # We're at a command group and the word is not one of its
            # subcommands - this is exactly what drift looks like.
            return (
                f"unknown gcx command: '{' '.join(path + [word])}' "
                f"('{word}' is not a subcommand of '{' '.join(path)}')"
            )
        break  # leaf command: remaining words are positional args
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gcx-bin", default="gcx")
    parser.add_argument("dirs", nargs="*", default=["skills"])
    args = parser.parse_args()

    root = load_tree(args.gcx_bin)

    files = []
    for d in args.dirs:
        files.extend(sorted(Path(d).rglob("*.md")))
    if not files:
        sys.exit(f"error: no markdown files found under: {' '.join(args.dirs)}")

    errors = 0
    checked = 0
    for md in files:
        text = md.read_text(encoding="utf-8")
        for lineno, tail in extract_invocations(text):
            checked += 1
            problem = validate_invocation(tail, root)
            if problem:
                errors += 1
                print(f"{md}:{lineno}: {problem}")

    print(f"Checked {checked} gcx invocation(s) in {len(files)} file(s): "
          f"{errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
