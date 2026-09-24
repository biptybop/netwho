#!/usr/bin/env python3
"""Rebuilds assets/data/oui.tsv.gz from Wireshark's manuf file.

Usage: curl -sSfLo manuf https://www.wireshark.org/download/automated/data/manuf
       python3 tool/build_oui.py manuf

Output lines are "<hex prefix>\t<vendor>", where the prefix is 6, 7 or 9 hex
digits for /24, /28 and /36 assignments.
"""
import gzip, sys

rows = []
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    parts = [p.strip() for p in line.rstrip("\n").split("\t")]
    if len(parts) < 2:
        continue
    prefix, bits = (parts[0].split("/") + ["24"])[:2]
    hexp = prefix.replace(":", "").replace("-", "").upper()
    hexp = hexp[: int(bits) // 4]
    if len(hexp) not in (6, 7, 9):
        continue
    name = parts[2] if len(parts) > 2 and parts[2] else parts[1]
    rows.append(f"{hexp}\t{name}")

with gzip.open("assets/data/oui.tsv.gz", "wt", encoding="utf-8", compresslevel=9) as f:
    f.write("\n".join(rows))
print(f"{len(rows)} prefixes")
