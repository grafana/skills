#!/usr/bin/env python3
"""validate-gcx-invocations.py - catch stale gcx commands in skill markdown.

Extracts every `gcx ...` invocation from shell code blocks and inline code
spans in skill markdown files, then validates the command path against the
command tree of a real gcx binary (`gcx help-tree`). This is the same idea as
the drift test gcx runs against its own bundled skills: when a gcx release
renames or removes a command, CI fails here instead of an agent failing at
runtime.

A command word only errors when it doesn't resolve at a point where gcx
expects a subcommand (a command group). Positional arguments after leaf
commands, flags, placeholders (<...>), paths (/...), and quoted strings are
all ignored. Fenced blocks are only scanned when their info string is a shell
language (or empty), so quoted gcx *output* in ```text blocks doesn't
false-positive.

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

# Fence info strings whose content is scanned for gcx invocations. Anything
# else (text, json, yaml, python, ...) is output or non-shell code.
SHELL_INFO = {"", "bash", "sh", "shell", "zsh", "console", "terminal"}

# The lookahead keeps the match zero-width so several gcx invocations on one
# line (e.g. chained with &&) are each extracted.
GCX_RE = re.compile(r"(?=(?:^|[\s`$(|;&={])gcx\s+([^\n]*))")
# Fences per CommonMark: 3+ backticks or tildes, up to 3 spaces of indent,
# optional info string. A close needs the same char, at least the opening
# length, and no info string - so nested shorter fences inside a longer
# fence stay content.
FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})\s*(\S*)")
BLOCKQUOTE_RE = re.compile(r"^(?:\s{0,3}>\s?)+")
INLINE_CODE_RE = re.compile(r"`([^`]+)`")


def load_tree(gcx_bin: str) -> dict:
    try:
        result = subprocess.run(
            [gcx_bin, "--agent", "help-tree"],
            capture_output=True, text=True, timeout=60,
        )
    except FileNotFoundError:
        sys.exit(f"error: gcx binary not found: '{gcx_bin}' (pass --gcx-bin)")
    if result.returncode != 0:
        sys.exit(f"error: '{gcx_bin} --agent help-tree' failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def children_of(node: dict) -> dict:
    return {c["name"]: c for c in node.get("children", [])}


def extract_invocations(text: str):
    """Return (line_number, invocation_tail) pairs for every gcx call."""
    results = []
    fence = None  # (marker_char, marker_len, is_shell) while inside a fence
    pending = ""  # accumulates backslash-continued lines inside fences
    pending_start = 0

    def scan(buf: str, lineno: int):
        for m in GCX_RE.finditer(buf):
            results.append((lineno, m.group(1)))

    def flush_pending():
        nonlocal pending
        if pending:
            scan(pending, pending_start)
            pending = ""

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = BLOCKQUOTE_RE.sub("", raw)  # blockquoted fences still count
        fence_match = FENCE_RE.match(line)

        if fence is None:
            if fence_match:
                info = fence_match.group(2).lower()
                marker = fence_match.group(1)
                fence = (marker[0], len(marker), info in SHELL_INFO)
                continue
            for span in INLINE_CODE_RE.findall(raw):
                scan(span, lineno)
            continue

        marker_char, marker_len, is_shell = fence
        if (fence_match and fence_match.group(1)[0] == marker_char
                and len(fence_match.group(1)) >= marker_len
                and not fence_match.group(2)):
            flush_pending()
            fence = None
            continue
        if not is_shell:
            continue
        if line.lstrip().startswith("#"):
            # Shell comments are prose; matching them yields false positives
            # like "no gcx and no auth header".
            flush_pending()
            continue
        # Trailing comments are prose too ("... # run after a gcx upgrade").
        line = re.sub(r"(?<=\s)#.*$", "", line)
        if pending:
            line = pending + " " + line.strip()
        else:
            pending_start = lineno
        if line.rstrip().endswith("\\"):
            pending = line.rstrip()[:-1].rstrip()
            continue
        pending = ""
        scan(line, pending_start)

    flush_pending()
    return results


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
