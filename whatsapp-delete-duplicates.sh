#!/bin/bash

python3 - "$@" <<'PY'
import os
import sys
import re
import hashlib
import shlex
from collections import defaultdict
from datetime import datetime

BASE = os.path.expanduser(
    "~/Library/Group Containers/"
    "group.net.whatsapp.WhatsApp.shared/Message/Media"
)

LOG = os.path.join(os.getcwd(), "history.log")
args = sys.argv[1:]
errors = 0

def output(message):
    print(message, flush=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(message + "\n")

def sizefmt(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.2f} {unit}"
        n /= 1024
    return f"{n:.2f} PB"

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            data = f.read(1024 * 1024)
            if not data:
                break
            h.update(data)
    return h.hexdigest()

output("")
output("=" * 70)
output("DATE: " + datetime.now().isoformat(timespec="seconds"))
output("COMMAND: " + shlex.join(["whatsapp-delete-duplicates.sh"] + args))
output("WORKING DIRECTORY: " + os.getcwd())

if not args or not re.fullmatch(r"\d+", args[0]) or (
    len(args) > 2 or
    (len(args) == 2 and args[1] != "--delete")
):
    output("USAGE: ./whatsapp-delete-duplicates.sh ID [--delete]")
    output("EXIT CODE: 1")
    sys.exit(1)

lid = args[0]
delete_mode = "--delete" in args
folder = os.path.join(BASE, lid + "@lid")

if not os.path.isdir(folder):
    folder = os.path.join(BASE, lid + "@lid.status")

output("WHATSAPP ID: " + lid)
output("FOLDER: " + folder)
output("MODE: " + ("DELETE DUPLICATES" if delete_mode else "DRY RUN"))

if not os.path.isdir(folder):
    output("ERROR: Folder does not exist")
    output("EXIT CODE: 1")
    sys.exit(1)

files_by_size = defaultdict(list)
total_files = 0

for root, dirs, files in os.walk(folder, followlinks=False):
    for name in files:
        path = os.path.join(root, name)
        if os.path.islink(path):
            continue
        try:
            size = os.path.getsize(path)
            files_by_size[size].append(path)
            total_files += 1
        except OSError as e:
            output(f"ERROR: {path}: {e}")
            errors += 1

duplicates = []
groups = 0

for size, paths in files_by_size.items():
    if len(paths) < 2:
        continue

    hashes = defaultdict(list)

    for path in paths:
        try:
            hashes[sha256(path)].append(path)
        except OSError as e:
            output(f"ERROR: {path}: {e}")
            errors += 1

    for digest, matches in hashes.items():
        if len(matches) < 2:
            continue

        groups += 1
        matches.sort(key=os.path.getmtime, reverse=True)

        output("")
        #output("HASH: " + digest)
        #output("KEEP: " + matches[0])

        for path in matches[1:]:
            duplicates.append((path, size))

total_wasted = sum(size for _, size in duplicates)
deleted_count = 0
deleted_bytes = 0

for path, size in duplicates:
    if delete_mode:
        try:
            # Revalidate before deleting in case the file changed
            if os.path.getsize(path) != size:
                raise ValueError("File size changed during scan")

            # Only delete if an identical retained copy still exists
            digest = sha256(path)
            matches = [
                p for p in files_by_size[size]
                if p != path and
                p not in {d[0] for d in duplicates}
                and os.path.isfile(p)
            ]

            if not any(sha256(p) == digest for p in matches):
                raise ValueError("No verified retained copy")

            os.remove(path)
            deleted_count += 1
            deleted_bytes += size
            output("DELETED: " + path)

        except (OSError, ValueError) as e:
            errors += 1
            output(f"ERROR: {path}: {e}")
    else:
        pass

output("")
output("=" * 70)
output("SUMMARY")
output("=" * 70)
output(f"Total files scanned: {total_files}")
output(f"Duplicate groups: {groups}")
output(f"Extra duplicate files: {len(duplicates)}")
output(f"Potential recoverable space: {sizefmt(total_wasted)}")
output(f"Files deleted: {deleted_count}")
output(f"Space deleted: {sizefmt(deleted_bytes)}")
output(f"Errors: {errors}")
output("END: " + datetime.now().isoformat(timespec="seconds"))

exit_code = 1 if errors else 0
output(f"EXIT CODE: {exit_code}")
output("=" * 70)

sys.exit(exit_code)
PY