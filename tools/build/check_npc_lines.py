#!/usr/bin/env python3
"""Check the line banks under data/npc_lines/.

    python tools/build/check_npc_lines.py            # every file
    python tools/build/check_npc_lines.py path.json  # one file

Two formats:
  * flat banks (lr.npc_lines/1): {"schema", "category", "kind": "speech" | "ambient", "lines": [...]}
    at least MIN_LINES unique lines per file.
  * hunter banks (lr.hunter_lines/1): {"schema", "hunter", "kind": "hunter" | "void",
    "situations": {"chase": [...], ...}} with every situation in SITUATIONS present, at least
    MIN_PER_SITUATION unique lines in each, and at least MIN_HUNTER_LINES unique lines in total.

Line rules (both formats): 3..14 words, at most MAX_CHARS characters (the chat limit is 80), plain text (no quote marks,
URLs, emoji, '//', stage directions, all-caps words of 4+ letters), no blocked words. No line may repeat anywhere in the bank.
Exit code 0 only when everything passes.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BANK = os.path.join(ROOT, "data", "npc_lines")
MIN_LINES = 65
MIN_PER_SITUATION = 10
MIN_HUNTER_LINES = 100
MAX_CHARS = 80
MIN_WORDS, MAX_WORDS = 3, 14
SITUATIONS = ["chase", "catch", "hear", "search", "stunned", "hide_spot", "light", "idle", "ability", "mechanic"]
BLOCKED = {"fuck", "shit", "bitch", "cunt", "nigger", "faggot", "retard", "rape", "porn", "kill yourself"}
BAD_PATTERNS = [
    (re.compile(r"https?://|www\.", re.I), "contains a URL"),
    (re.compile(r"[\U0001F300-\U0001FAFF☀-➿]"), "contains an emoji"),
    (re.compile(r"//"), "contains '//' (HUD style, not speech)"),
    (re.compile(r"\[[^\]]*\]|\*[^*]*\*"), "contains a stage direction"),
    (re.compile(r"[\"“”]"), "contains quote marks"),
    (re.compile(r"\b[A-Z]{4,}\b"), "contains an all-caps word (TTS reads it letter by letter)"),
]


def line_problems(text):
    problems = []
    words = len(text.split())
    if not (MIN_WORDS <= words <= MAX_WORDS):
        problems.append("%d words (need %d-%d): %s" % (words, MIN_WORDS, MAX_WORDS, text))
    if len(text) > MAX_CHARS:
        problems.append("%d chars (max %d): %s" % (len(text), MAX_CHARS, text))
    for pattern, why in BAD_PATTERNS:
        if pattern.search(text):
            problems.append("%s: %s" % (why, text))
    if any(re.search(r"\b%s\b" % re.escape(word), text.lower()) for word in BLOCKED):
        problems.append("blocked word: %s" % text)
    return problems


def key_of(text):
    return re.sub(r"[^a-z' ]", "", text.lower()).strip()


def collect(lines, seen_global, problems, label=""):
    """Check one list of lines; returns the unique texts that passed."""
    unique = []
    local = set()
    for raw in lines:
        if not isinstance(raw, str):
            problems.append("%snon-string entry: %r" % (label, raw))
            continue
        text = raw.strip()
        key = key_of(text)
        if key in local:
            problems.append("%sduplicate in file: %s" % (label, text))
            continue
        if key in seen_global:
            problems.append("%sduplicate across the bank: %s" % (label, text))
            continue
        local.add(key)
        found = line_problems(text)
        problems.extend(found)
        if not found:
            unique.append(text)
    seen_global.update(local)
    return unique


def check_flat(data, seen_global, problems):
    if data.get("schema") != "lr.npc_lines/1":
        problems.append("schema must be lr.npc_lines/1")
    if data.get("kind") not in ("speech", "ambient"):
        problems.append("kind must be speech or ambient")
    lines = data.get("lines", [])
    if not isinstance(lines, list):
        problems.append("lines must be a list")
        return 0
    unique = collect(lines, seen_global, problems)
    if len(unique) < MIN_LINES:
        problems.append("only %d unique lines (need %d)" % (len(unique), MIN_LINES))
    return len(unique)


def check_hunter(data, seen_global, problems):
    if data.get("schema") != "lr.hunter_lines/1":
        problems.append("schema must be lr.hunter_lines/1")
    if data.get("kind") not in ("hunter", "void"):
        problems.append("kind must be hunter or void")
    situations = data.get("situations")
    if not isinstance(situations, dict):
        problems.append("situations must be an object")
        return 0
    for name in SITUATIONS:
        if name not in situations:
            problems.append("missing situation: %s" % name)
    for name in situations:
        if name not in SITUATIONS:
            problems.append("unknown situation: %s" % name)
    total = 0
    for name in SITUATIONS:
        lines = situations.get(name, [])
        if not isinstance(lines, list):
            problems.append("%s must be a list" % name)
            continue
        unique = collect(lines, seen_global, problems, label="[%s] " % name)
        if len(unique) < MIN_PER_SITUATION:
            problems.append("[%s] only %d unique lines (need %d)" % (name, len(unique), MIN_PER_SITUATION))
        total += len(unique)
    if total < MIN_HUNTER_LINES:
        problems.append("only %d unique lines in total (need %d)" % (total, MIN_HUNTER_LINES))
    return total


def check_file(path, seen_global):
    problems = []
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - report any parse failure
        return ["not valid JSON: %s" % exc], 0
    if data.get("schema") == "lr.hunter_lines/1":
        count = check_hunter(data, seen_global, problems)
    else:
        count = check_flat(data, seen_global, problems)
    return problems, count


def main(argv):
    paths = argv[1:] or sorted(glob.glob(os.path.join(BANK, "*.json")))
    if not paths:
        print("no files in", BANK)
        return 1
    seen_global = set()
    failed = False
    for path in paths:
        problems, count = check_file(path, seen_global)
        name = os.path.relpath(path, ROOT).replace("\\", "/")
        if problems:
            failed = True
            print("FAIL %s (%d good lines)" % (name, count))
            for problem in problems[:40]:
                print("   -", problem)
            if len(problems) > 40:
                print("   ... %d more" % (len(problems) - 40))
        else:
            print("ok   %s (%d lines)" % (name, count))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
