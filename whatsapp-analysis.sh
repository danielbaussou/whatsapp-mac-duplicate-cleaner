#!/bin/bash

BASE="$HOME/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
DIR="$BASE/Message/Media"
LOGFILE="$PWD/history.log"

python3 - "$BASE" "$DIR" "$LOGFILE" "$0" "$@" <<'PY'
import os
import sys
import re
import hashlib
import sqlite3
import shlex
from collections import defaultdict, Counter
from datetime import datetime

base, root, logfile, script, *args = sys.argv[1:]

MIN_DUPLICATES = 5

def fmt(size):
    size = float(size)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.2f} {unit}"
        size /= 1024

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()

def open_db(filename):
    path = os.path.join(base, filename)
    return sqlite3.connect(
        "file:" + path + "?mode=ro",
        uri=True
    )

def get_contacts():
    contacts = {}

    try:
        with open_db("ContactsV2.sqlite") as db:
            rows = db.execute("""
                SELECT
                    ZLID,
                    ZFULLNAME,
                    ZGIVENNAME,
                    ZBUSINESSNAME,
                    ZPHONENUMBER
                FROM ZWAADDRESSBOOKCONTACT
                WHERE ZLID IS NOT NULL
            """)

            for lid, fullname, given, business, phone in rows:
                contacts[lid] = {
                    "name": fullname or given or business or "Unknown",
                    "phone": phone or "Unknown"
                }
    except (sqlite3.Error, OSError) as e:
        print("Contacts database warning:", e)

    try:
        with open_db("LID.sqlite") as db:
            rows = db.execute("""
                SELECT ZIDENTIFIER, ZPHONENUMBER
                FROM ZWAZACCOUNT
                WHERE ZIDENTIFIER LIKE '%@lid'
            """)

            for lid, phone in rows:
                if lid not in contacts:
                    contacts[lid] = {
                        "name": "Unknown",
                        "phone": phone or "Unknown"
                    }
                elif contacts[lid]["phone"] == "Unknown" and phone:
                    contacts[lid]["phone"] = phone

    except (sqlite3.Error, OSError) as e:
        print("LID database warning:", e)

    return contacts

def get_owner(path):
    relative = os.path.relpath(path, root)
    match = re.search(r'(?:^|/)(\d+@lid)(?:\.status)?(?:/|$)', relative)
    return match.group(1) if match else None

def main():
    started = datetime.now()

    command = shlex.join([script] + args)

    lines = []

    def out(message=""):
        message = str(message)
        print(message)
        lines.append(message)

    out("=" * 75)
    out("WHATSAPP DUPLICATE MEDIA REPORT")
    out("=" * 75)
    out("DATE: " + started.strftime("%Y-%m-%d %H:%M:%S"))
    out("COMMAND: " + command)
    out("DIRECTORY: " + root)
    out("MINIMUM DUPLICATES PER ID: " + str(MIN_DUPLICATES + 1))
    out()

    if not os.path.isdir(root):
        out("ERROR: WhatsApp media directory not found.")
        return lines, 1

    contacts = get_contacts()

    files_by_size = defaultdict(list)

    total_files = 0
    total_size = 0
    errors = 0

    out("Scanning WhatsApp media files...")

    for directory, _, filenames in os.walk(root):
        for filename in filenames:
            path = os.path.join(directory, filename)

            try:
                if not os.path.isfile(path):
                    continue

                size = os.path.getsize(path)

                files_by_size[size].append(path)

                total_files += 1
                total_size += size

            except OSError:
                errors += 1

    out("Files found: " + str(total_files))
    out("Checking SHA-256 hashes...")
    out()

    duplicate_groups = 0
    duplicate_files = 0
    wasted_bytes = 0

    duplicate_details = []

    # Aggregate per-owner files within matching content groups.
    # A file is considered redundant for an owner when that
    # owner has another identical file in their own directory.
    owner_duplicates = Counter()
    owner_wasted = Counter()
    owner_groups = Counter()

    for size, paths in files_by_size.items():

        if len(paths) < 2:
            continue

        hashes = defaultdict(list)

        for path in paths:
            try:
                digest = sha256(path)
                hashes[digest].append(path)

            except OSError:
                errors += 1

        for digest, matches in hashes.items():

            if len(matches) < 2:
                continue

            duplicate_groups += 1
            duplicate_files += len(matches) - 1
            wasted_bytes += size * (len(matches) - 1)

            duplicate_details.append({
                "hash": digest,
                "size": size,
                "paths": sorted(matches)
            })

            by_owner = defaultdict(list)

            for path in matches:
                owner = get_owner(path)
                if owner:
                    by_owner[owner].append(path)

            for owner, owner_paths in by_owner.items():
                extra = len(owner_paths) - 1

                if extra > 0:
                    owner_duplicates[owner] += extra
                    owner_wasted[owner] += extra * size
                    owner_groups[owner] += 1

    out("=" * 75)
    out("GLOBAL SUMMARY")
    out("=" * 75)
    out(f"Total files scanned:      {total_files:,}")
    out(f"Total media size:         {fmt(total_size)}")
    out(f"Duplicate groups:         {duplicate_groups:,}")
    out(f"Extra duplicate files:    {duplicate_files:,}")
    out(f"Wasted duplicate space:   {fmt(wasted_bytes)}")
    out(f"Scan errors:              {errors}")
    out()

    out("=" * 75)
    out("WHATSAPP CONTACTS WITH MORE THAN 5 DUPLICATE FILES")
    out("=" * 75)

    qualifying = [
        (lid, count)
        for lid, count in owner_duplicates.items()
        if count > MIN_DUPLICATES
    ]

    qualifying.sort(
        key=lambda item: owner_wasted[item[0]],
        reverse=True
    )

    if not qualifying:
        out("No WhatsApp contacts with more than 5 extra duplicates.")

    for index, (lid, count) in enumerate(qualifying, 1):

        contact = contacts.get(lid, {})

        name = contact.get("name", "Unknown")
        phone = contact.get("phone", "Unknown")

        out()
        out(f"{index}. {name}")
        out(f"   WhatsApp ID:      {lid}")
        out(f"   Phone:            {phone}")
        out(f"   Duplicate files:  {count:,}")
        out(f"   Duplicate groups: {owner_groups[lid]:,}")
        out(f"   Wasted space:     {fmt(owner_wasted[lid])}")

    out()
    out("=" * 75)
    out("CONTACT SUMMARY")
    out("=" * 75)
    out(f"Contacts exceeding threshold: {len(qualifying)}")
    out(
        "Extra copies in those contacts: "
        + str(sum(owner_duplicates[lid] for lid, _ in qualifying))
    )
    out(
        "Redundant bytes in those contacts: "
        + fmt(sum(owner_wasted[lid] for lid, _ in qualifying))
    )

    out()
    out("=" * 75)
    out("DETAILED DUPLICATE GROUPS")
    out("=" * 75)
    out("Detailed filenames are saved in history.log.")

    # Save detailed file information to the log without
    # flooding the terminal with thousands of paths.
    details = []

    duplicate_details.sort(
        key=lambda group: group["size"] * (len(group["paths"]) - 1),
        reverse=True
    )

    for group in duplicate_details:

        size = group["size"]
        paths = group["paths"]
        wasted = size * (len(paths) - 1)

        details.append("")
        details.append("-" * 65)
        details.append(f"SHA256: {group['hash']}")
        details.append(f"Copies: {len(paths)}")
        details.append(f"File size: {fmt(size)}")
        details.append(f"Redundant size: {fmt(wasted)}")

        for path in paths:
            owner = get_owner(path)
            if owner:
                name = contacts.get(owner, {}).get("name", "Unknown")
                details.append(f"  [{name} | {owner}] {path}")
            else:
                details.append(f"  {path}")

    result = 1 if errors else 0

    out()
    out("EXIT CODE: " + str(result))
    out("END: " + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    out("=" * 75)

    try:
        with open(logfile, "a", encoding="utf-8") as f:
            f.write("\n".join(lines))
            f.write("\n")
            f.write("\n".join(details))
            f.write("\n")
    except OSError as e:
        print("ERROR writing history:", e)
        return lines, 1

    return lines, result

_, exit_code = main()
sys.exit(exit_code)
PY