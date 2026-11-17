"""Counts spoken words in dialogue JSON files (strings only; expression
tags like [happy] and placeholders like {you} are not counted as words).
Usage: python3 -I tools/dialogue_words.py data/dialogue/founders/mara.json ...
The full per-character report (own vs shared, every villager) is printed by
tests/dialogue_content_test.gd, which runs inside the game."""
import json, re, sys

def strings(node, key=""):
    if isinstance(node, str):
        if key not in ("id",) and not key.startswith("_"):
            yield node
    elif isinstance(node, list):
        for item in node:
            yield from strings(item, key)
    elif isinstance(node, dict):
        for k, v in node.items():
            if k in ("id", "options", "free"):
                continue
            yield from strings(v, k)

def words(line):
    line = re.sub(r"^\[[a-z_]+\]", "", line)
    line = re.sub(r"\{[a-z_]+\}", "", line)
    return len(line.split())

for path in sys.argv[1:]:
    data = json.load(open(path))
    lines = sorted(set(strings(data)))
    print(f"{path}: {len(lines)} distinct lines, {sum(words(l) for l in lines)} words")
