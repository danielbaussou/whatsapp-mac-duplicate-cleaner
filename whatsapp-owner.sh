#!/bin/bash

BASE="$HOME/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
INPUT="${1:-}"

if [ -z "$INPUT" ]; then
    echo "Usage: $0 '<WhatsApp media directory>'"
    exit 1
fi

python3 - "$BASE" "$INPUT" <<'PY'
import os
import re
import sqlite3
import sys

base, path = sys.argv[1:3]

match = re.search(r'(\d+@lid)(?:\.status)?', path)

if not match:
    print("No WhatsApp LID found in path.")
    sys.exit(1)

lid = match.group(1)

print("WhatsApp LID:", lid)

def connect(filename):
    return sqlite3.connect(
        "file:" + os.path.join(base, filename) + "?mode=ro",
        uri=True
    )

# Contact name and telephone
with connect("ContactsV2.sqlite") as db:
    rows = db.execute("""
        SELECT ZFULLNAME, ZGIVENNAME, ZPHONENUMBER, ZBUSINESSNAME
        FROM ZWAADDRESSBOOKCONTACT
        WHERE ZLID = ?
    """, (lid,)).fetchall()

    for name, given, phone, business in rows:
        print("Contact:", name or given or business or "Unknown")
        print("Phone:", phone or "Unknown")

# Additional LID mapping
with connect("LID.sqlite") as db:
    row = db.execute("""
        SELECT ZPHONENUMBER
        FROM ZWAZACCOUNT
        WHERE ZIDENTIFIER = ?
    """, (lid,)).fetchone()

    if row and not rows:
        print("Contact: Unknown")
        print("Phone:", row[0])

    if not rows and not row:
        print("No matching contact found.")
PY
