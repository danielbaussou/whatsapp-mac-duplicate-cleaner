# WhatsApp Mac Duplicate Cleaner

### Because apparently, storing the same video 132,979 times is a feature.

RAM is expensive. SSD storage isn't free either. And while the tech industry is busy selling us more memory, WhatsApp for Mac seems determined to fill our disks with the same six videos.

*Merci WhatsApp. Muchas gracias. Vraiment.*

## The discovery: 12 GB of absolutely nothing new

One day, while investigating why my Mac was consuming so much disk space, I discovered something magnificent.

Not 100 duplicate files. Not 1,000.

**132,978 redundant files. Just six groups of identical content. 12.07 GB of logical duplicate data.**

| The investigation | The result |
|---|---|
| Redundant files | 132,978 |
| Different SHA-256 groups | 6 |
| Logical duplicate size | 12.07 GB |
| Different filenames | Yes |
| Different content | Nope |
| My reaction | *Mais c'est quoi ce bordel ?* |

All associated with a single WhatsApp identifier.

*¡Olé! Un festival de duplicados.*

And the best part? The files were stored under perfectly legitimate-looking WhatsApp directories, with different filenames, as if they were all precious and unique.

They weren't.

## The usual suspect

```text
~/Library/Group Containers/
  group.net.whatsapp.WhatsApp.shared/
    Message/
      Media/
        123456789@lid/
          ...
```

Sometimes the directory ends with `@lid`, sometimes with `@lid.status`.

WhatsApp also maintains local SQLite databases containing contact information, which means we can sometimes identify which contact is associated with a particular directory.

No hacking. No mysterious cloud service. Just examining locally stored data.

## Enter WhatsApp Mac Duplicate Cleaner

Three little scripts, one objective:

**Find the duplicates. Identify where they are. Get rid of the unnecessary copies.**

Preferably without deleting the original family video, your cat's masterpiece, or that one absolutely essential 14-second Status.

### 1. `whatsapp-duplicates.sh`

The detective.

Scans your WhatsApp media storage and compares file hashes using SHA-256.

Reports:

- Total files scanned.
- Exact duplicate groups.
- Number of redundant copies.
- Logical disk space consumed by duplicates.
- WhatsApp IDs with more than five redundant copies.
- Contact names and phone numbers, when available locally.

```bash
./whatsapp-duplicates.sh
```

Example output:

```text
WHATSAPP CONTACTS WITH MORE THAN 5 DUPLICATE FILES

1. Example Contact
   WhatsApp ID:      123456789@lid
   Duplicate files:  132,978
   Duplicate groups: 6
   Wasted space:     12.07 GB
```

*Señoras y señores, tenemos un ganador.*

### 2. `whatsapp-owner.sh`

The investigator.

You have a directory with an obscure WhatsApp ID and want to know which contact is associated with it?

```bash
./whatsapp-owner.sh \
"$HOME/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media/123456789@lid.status"
```

The script checks the local WhatsApp SQLite databases for a matching contact name and phone number.

*Élémentaire, mon cher Watson.* Well, almost.

### 3. `whatsapp-delete-duplicates.sh`

The cleaning crew.

First, preview the cleanup:

```bash
./whatsapp-delete-duplicates.sh 123456789
```

When you are satisfied:

```bash
./whatsapp-delete-duplicates.sh 123456789 --delete
```

The goal is to keep one file for each distinct SHA-256 hash within the selected directory and remove redundant copies.

For example:

```text
BEFORE
  video_A_001.mp4
  video_A_002.mp4
  video_A_003.mp4
  video_A_004.mp4

All four files have the same SHA-256 hash.

AFTER
  video_A_001.mp4

Three redundant copies removed.
```

*Au revoir les doublons. Hasta nunca.*

**Important:** WhatsApp may reference each file by its individual path. Deleting an identical copy can make a particular message's media unavailable, even when another copy remains. Always run preview mode first and back up anything important.

## Installation

Requirements:

- macOS.
- WhatsApp Desktop with local media files.
- Python 3.
- A healthy level of curiosity.

No paid software. No subscriptions. No obscure dependencies.

```bash
git clone https://github.com/YOUR_USERNAME/whatsapp-mac-duplicate-cleaner.git
cd whatsapp-mac-duplicate-cleaner

chmod +x whatsapp-duplicates.sh \
         whatsapp-owner.sh \
         whatsapp-delete-duplicates.sh
```

Replace `YOUR_USERNAME` with your GitHub username.

## Why SHA-256?

Because filenames lie.

```text
video_hello.mp4       abc123...
random_UUID_001.mp4   abc123...
another_name.mp4      abc123...
```

Same hash, same bytes, regardless of the name.

Unlike comparing file sizes alone, hashing confirms exact duplicates to a very high degree of confidence.

The limitation? If WhatsApp recompresses a video, changes its metadata, or re-encodes it, the hash changes even when the video looks identical.

We are detecting exact duplicates, not performing cinematic analysis.

*On n'est pas à Cannes non plus.*

## Execution history

Every execution writes a history to:

```text
./history.log
```

Including timestamps, commands, results, error codes, and deletion activity.

Because deleting thousands of files without knowing what happened is not exactly my idea of good system administration.

The history file stays local and should not be committed to GitHub.

Recommended `.gitignore`:

```gitignore
history.log
*.log
*.sqlite
*.sqlite-wal
*.sqlite-shm
.DS_Store
__pycache__/
```

## One technical detail: APFS

Those 12.07 GB represent the logical size of redundant files.

On macOS, APFS can use cloned files that share underlying disk blocks. This means removing 12 GB of logically duplicated files does not always recover 12 GB of physical SSD space.

Measure available disk space before and after:

```bash
df -h "$HOME"
```

*Parce que même les gigaoctets peuvent mentir.*

## What caused this mess?

We don't know for certain.

Potential explanations include:

- Repeated media downloads.
- A synchronization loop.
- A caching or file-management bug.
- Unexpected behavior in WhatsApp Desktop's media storage.

What we do know is that finding 132,978 redundant files across six content groups is not reasonable storage behavior.

And blaming the contact for sharing a video is probably unfair.

*El problema no es el vídeo. El problema es guardarlo cien mil veces.*

## Privacy: your contacts stay your contacts

Everything runs locally.

No uploads, no external APIs, no sending contacts to mysterious servers.

When available, contact information comes from WhatsApp's own local databases:

```text
ContactsV2.sqlite
LID.sqlite
```

Do not publish your logs, personal media, or SQLite databases.

The project is intended to help understand and manage locally stored data, not expose anyone's private information.

## Limitations

- Only exact SHA-256 duplicates are identified.
- WhatsApp can change its directory layout or database schema.
- Contact names may be unavailable.
- Some directories end in `@lid`, others in `@lid.status`.
- Physical disk savings may differ from logical duplicate size.
- Deleted media may be downloaded again.
- Removing WhatsApp-managed files may break media references.

The detection tool is read-only. The cleanup tool is destructive when `--delete` is supplied.

Use accordingly.

## Contributing

Found 200,000 duplicates? Half a million? A million copies of your uncle's birthday video?

Open an issue with your statistics.

Please remove all personal names, phone numbers, media paths containing identifiers, and private content before sharing.

Pull requests are welcome for improving performance, detection accuracy, APFS storage reporting, and cleanup safety.

## A small message to WhatsApp

Dear WhatsApp,

We appreciate your contribution to global communication.

But storing the same six pieces of media more than 130,000 times is a rather creative interpretation of data redundancy.

We already have backups.

We do not need a backup of a backup of a backup of a backup of a backup of a backup.

*Avec toute notre affection.*

*Con cariño, pero sin duplicados.*

Sincerely,

A Mac user who would rather use their SSD for something else.

---

## Disclaimer

This is an independent, unofficial project, not affiliated with WhatsApp or Meta.

It is not a universal repair tool for WhatsApp's internal storage. Users are responsible for reviewing operations and maintaining backups before deleting files.

## License

MIT — see `LICENSE` for details.

---

**Made with Python, curiosity, a terminal, and 12.07 GB of existential questions.**

*Moins de doublons, plus de liberté. Menos basura, más espacio.*

### Performance update — November 2026

The original cleanup script had a small problem: deleting 130,000 duplicate files could take hours because it repeatedly recalculated SHA-256 hashes.

The optimized version calculates hashes once, verifies the retained files, and processes duplicates without unnecessary repeated comparisons.