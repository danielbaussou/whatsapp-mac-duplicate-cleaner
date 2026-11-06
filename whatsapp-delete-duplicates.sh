#!/bin/bash

python3 - "$@" <<'PY'
import os
import sys
import re
import hashlib
import sqlite3
import shlex
import time
from collections import defaultdict
from datetime import datetime

BASE = os.path.expanduser(
    "~/Library/Group Containers/"
    "group.net.whatsapp.WhatsApp.shared"
)

MEDIA = os.path.join(BASE, "Message", "Media")
LOG = os.path.join(os.getcwd(), "history.log")
DETAILS = os.path.join(os.getcwd(), "deletion-details.log")

args = sys.argv[1:]
start = time.monotonic()
errors = 0

def output(message=""):
    print(message, flush=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(message + "\n")

def fmt(n):
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.2f} {unit}"
        n /= 1024

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            data = f.read(4 * 1024 * 1024)
            if not data:
                break
            h.update(data)
    return h.digest()

def contact_info(lid):
    name = "Unknown"
    phone = "Unknown"

    try:
        db = sqlite3.connect(
            "file:" + os.path.join(BASE, "ContactsV2.sqlite") +
            "?mode=ro",
            uri=True
        )

        row = db.execute("""
            SELECT ZFULLNAME, ZGIVENNAME,
                   ZBUSINESSNAME, ZPHONENUMBER
            FROM ZWAADDRESSBOOKCONTACT
            WHERE ZLID = ?
            LIMIT 1
        """, (lid,)).fetchone()

        if row:
            name = row[0] or row[1] or row[2] or name
            phone = row[3] or phone

        db.close()
    except (sqlite3.Error, OSError):
        pass

    if phone == "Unknown":
        try:
            db = sqlite3.connect(
                "file:" + os.path.join(BASE, "LID.sqlite") +
                "?mode=ro",
                uri=True
            )

            row = db.execute("""
                SELECT ZPHONENUMBER
                FROM ZWAZACCOUNT
                WHERE ZIDENTIFIER = ?
                LIMIT 1
            """, (lid,)).fetchone()

            if row and row[0]:
                phone = row[0]

            db.close()
        except (sqlite3.Error, OSError):
            pass

    return name, phone

output("")
output("=" * 65)
output("WHATSAPP DUPLICATE CLEANER - OPTIMIZED")
output("=" * 65)
output("DATE: " + datetime.now().isoformat(timespec="seconds"))
output("COMMAND: " + shlex.join(
    ["./whatsapp-delete-duplicates.sh"] + args
))

if (
    not args or
    len(args) > 2 or
    not re.fullmatch(r"\d+", args[0]) or
    (len(args) == 2 and args[1] != "--delete")
):
    output("Usage: ./whatsapp-delete-duplicates.sh ID [--delete]")
    output("EXIT CODE: 1")
    sys.exit(1)

id_number = args[0]
lid = id_number + "@lid"
delete_mode = len(args) == 2

folders = [
    os.path.join(MEDIA, lid),
    os.path.join(MEDIA, lid + ".status")
]

folders = [p for p in folders if os.path.isdir(p)]

if not folders:
    output("ERROR: No matching WhatsApp directory")
    output("EXIT CODE: 1")
    sys.exit(1)

name, phone = contact_info(lid)

output("Contact: " + name)
output("Phone: " + phone)
output("WhatsApp ID: " + lid)
output("Mode: " + ("DELETE" if delete_mode else "DRY RUN"))

for folder in folders:
    output("Directory: " + folder)

output("")
output("Step 1: Scanning files...")

by_size = defaultdict(list)
total_files = 0
total_bytes = 0

for folder in folders:
    for root, dirs, files in os.walk(folder):
        dirs[:] = [
            d for d in dirs
            if not os.path.islink(os.path.join(root, d))
        ]

        for filename in files:
            path = os.path.join(root, filename)

            try:
                st = os.stat(path, follow_symlinks=False)

                if not os.path.isfile(path) or os.path.islink(path):
                    continue

                # Path, size, modification time, inode and device
                entry = (
                    path,
                    st.st_size,
                    st.st_mtime_ns,
                    st.st_ino,
                    st.st_dev
                )

                by_size[st.st_size].append(entry)
                total_files += 1
                total_bytes += st.st_size

            except OSError as e:
                errors += 1
                output("SCAN ERROR: " + str(e))

output("Files scanned: " + format(total_files, ","))
output("Total logical size: " + fmt(total_bytes))

output("")
output("Step 2: Calculating SHA-256 hashes...")

duplicates = []
retained = []
duplicate_groups = 0
hashed = 0

for size, entries in by_size.items():

    if len(entries) < 2:
        continue

    hashes = defaultdict(list)

    for entry in entries:
        path = entry[0]

        try:
            digest = sha256(path)
            hashes[digest].append(entry)
            hashed += 1

        except OSError as e:
            errors += 1
            output("HASH ERROR: " + str(e))

    for digest, matches in hashes.items():

        if len(matches) < 2:
            continue

        # Newest file first, deterministic filename tie-break
        matches.sort(key=lambda x: (-x[2], x[0]))

        keep = matches[0]
        extra = matches[1:]

        duplicate_groups += 1
        retained.append((keep, digest))
        for entry in extra:
            duplicates.append((entry, keep))

output("Files hashed: " + format(hashed, ","))
output("Duplicate groups: " + format(duplicate_groups, ","))
output("Extra duplicate files: " + format(len(duplicates), ","))

potential_bytes = sum(entry[1] for entry, _ in duplicates)

output("Potential logical savings: " + fmt(potential_bytes))

if not delete_mode:
    output("")
    output("DRY RUN COMPLETE - NO FILES DELETED")
    output("To delete:")
    output(
        "./whatsapp-delete-duplicates.sh "
        + id_number + " --delete"
    )

    output("Duration: %.2f seconds" % (time.monotonic() - start))
    result = 1 if errors else 0
    output("EXIT CODE: " + str(result))
    output("=" * 65)
    sys.exit(result)

if errors:
    output("")
    output("ERROR: Scan/hash errors detected. No deletion performed.")
    output("EXIT CODE: 1")
    sys.exit(1)

output("")
output("Step 3: Verifying retained files...")

# Verify one retained file per hash group before deleting.
valid_keeps = set()

for keep, expected_hash in retained:
    try:
        if sha256(keep[0]) == expected_hash:
            valid_keeps.add(keep[0])
        else:
            errors += 1
            output("KEEP HASH CHANGED: " + keep[0])
    except OSError as e:
        errors += 1
        output("KEEP ERROR: " + str(e))

if errors:
    output("ERROR: Retained-file verification failed.")
    output("No deletion performed.")
    output("EXIT CODE: 1")
    sys.exit(1)

output("Retained copies verified: " + str(len(valid_keeps)))
output("")
output("Step 4: Deleting duplicates...")

deleted = 0
deleted_bytes = 0
skipped = 0

try:
    with open(DETAILS, "a", encoding="utf-8", buffering=1) as detail_log:

        detail_log.write(
            "\n=== " + datetime.now().isoformat() +
            " | ID: " + lid + " ===\n"
        )

        for entry, keep in duplicates:
            path, size, mtime_ns, inode, device = entry

            try:
                if keep[0] not in valid_keeps:
                    skipped += 1
                    errors += 1
                    continue

                # Ensure the file is still the one scanned
                st = os.stat(path, follow_symlinks=False)

                if (
                    os.path.islink(path) or
                    st.st_size != size or
                    st.st_mtime_ns != mtime_ns or
                    st.st_ino != inode or
                    st.st_dev != device
                ):
                    skipped += 1
                    detail_log.write("SKIPPED CHANGED: " + path + "\n")
                    continue

                # Avoid deleting the retained path
                if path == keep[0]:
                    skipped += 1
                    continue

                os.remove(path)

                deleted += 1
                deleted_bytes += size

                detail_log.write("DELETED: " + path + "\n")

                if deleted % 10000 == 0:
                    output(
                        "Deleted: {:,} files | Logical size: {}"
                        .format(deleted, fmt(deleted_bytes))
                    )

            except OSError as e:
                errors += 1
                skipped += 1
                detail_log.write(
                    "ERROR: " + path + " | " + str(e) + "\n"
                )

except KeyboardInterrupt:
    output("INTERRUPTED BY USER")
    errors += 1

except OSError as e:
    output("LOGGING ERROR: " + str(e))
    errors += 1

output("")
output("=" * 65)
output("FINAL SUMMARY")
output("=" * 65)
output("Contact: " + name)
output("WhatsApp ID: " + lid)
output("Files scanned: " + format(total_files, ","))
output("Duplicate groups: " + format(duplicate_groups, ","))
output("Duplicates identified: " + format(len(duplicates), ","))
output("Files deleted: " + format(deleted, ","))
output("Files skipped: " + format(skipped, ","))
output("Logical space deleted: " + fmt(deleted_bytes))
output("Errors: " + str(errors))
output("Duration: %.2f seconds" % (time.monotonic() - start))
output("History: " + LOG)
output("Deletion details: " + DETAILS)

result = 1 if errors else 0
output("EXIT CODE: " + str(result))
output("=" * 65)

sys.exit(result)
PY
