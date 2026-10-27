"""Deletes blocky GLBs (and their .import files) that the last build no longer lists in manifest.json.

    python3 tools/props/clean_orphans.py [DIR]

Files the builder writes outside the manifest (the locked relay barrel) and AppleDouble junk are left alone.
"""
import json
import os
import sys

d = sys.argv[1] if len(sys.argv) > 1 else "art/props-3d/props/blocky"
manifest = json.load(open(os.path.join(d, "manifest.json")))
keep = {f for files in manifest.values() for f in files} | {"locked_relay_barrel.glb"}
removed = 0
for f in sorted(os.listdir(d)):
    if f.startswith("._") or not f.endswith(".glb") or f in keep:
        continue
    for suffix in ("", ".import"):
        path = os.path.join(d, f + suffix)
        if os.path.exists(path):
            os.remove(path)
    removed += 1
print("removed", removed, "orphan models")
