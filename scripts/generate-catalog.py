#!/usr/bin/env python3
"""Generate InitialLibrary.json entries from the Gutenberg Top 50 collection.

Scans books/public_domain_books/gutenberg_top50_classified/<category>/*.epub,
reads title/author from each EPUB's OPF metadata, deduplicates, and merges
entries into Tomeet/Tomeet/Data/InitialLibrary.json.

Filename convention: <rank>_<gutenberg-id>_<Title>.epub — the filename stem
becomes the catalog id (== bundle dir name produced by Scripts/copy-books.sh).

Dedup rules:
  1. Same Gutenberg id twice (e.g. apostrophe vs _s_ filename variants):
     keep the variant listed in the collection README, move the other aside.
  2. Same normalized title+author (different Gutenberg editions, e.g. two
     Draculas): keep the lower rank number, move the other aside.
Moved duplicates go to books/duplicates_excluded/ (outside the bundle scan
path), never deleted.

Usage:
    python3 scripts/generate-catalog.py            # dry-run, print plan
    python3 scripts/generate-catalog.py --apply    # move dupes + write JSON
"""

import argparse
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "books" / "public_domain_books" / "gutenberg_top50_classified"
EXCLUDED_DIR = REPO_ROOT / "books" / "duplicates_excluded"
JSON_PATH = REPO_ROOT / "Tomeet" / "Tomeet" / "Data" / "InitialLibrary.json"
README_PATH = SOURCE_DIR / "README.md"

FILENAME_RE = re.compile(r"^(?P<rank>\d+)_(?P<gid>\d+)_(?P<title>.+)\.epub$")
DC_RE = re.compile(r"<dc:(title|creator)[^>]*>([^<]*)<")


def read_readme_filenames() -> set:
    """Filenames referenced by the collection README (preferred variants)."""
    if not README_PATH.exists():
        return set()
    return set(re.findall(r"`([^`]+\.epub)`", README_PATH.read_text(encoding="utf-8")))


def opf_metadata(epub: Path) -> tuple:
    """Return (title, creator) from the EPUB's OPF, or (None, None)."""
    try:
        with zipfile.ZipFile(epub) as z:
            opf_names = [n for n in z.namelist() if n.endswith(".opf")]
            if not opf_names:
                return None, None
            data = z.read(opf_names[0]).decode("utf-8", "replace")
    except (zipfile.BadZipFile, OSError) as e:
        print(f"  warning: cannot read {epub.name}: {e}", file=sys.stderr)
        return None, None
    fields = {}
    for key, value in DC_RE.findall(data):
        fields.setdefault(key, value.strip())
    return fields.get("title"), fields.get("creator")


def humanize(stem_title: str) -> str:
    return stem_title.replace("_", " ").replace(" s ", "'s ").strip()


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def collect_books():
    """Scan source dir → list of dicts, duplicates excluded."""
    preferred = read_readme_filenames()
    entries = []
    for epub in sorted(SOURCE_DIR.glob("*/*.epub")):
        m = FILENAME_RE.match(epub.name)
        if not m:
            print(f"  skip (unexpected filename): {epub.name}")
            continue
        title, creator = opf_metadata(epub)
        entries.append({
            "id": epub.stem,
            "rank": int(m.group("rank")),
            "gid": m.group("gid"),
            "category": epub.parent.name,
            "path": epub,
            "title": title or humanize(m.group("title")),
            "author": creator or "",
        })

    kept, dupes = [], []
    by_gid = {}
    for e in entries:
        by_gid.setdefault(e["gid"], []).append(e)
    for group in by_gid.values():
        if len(group) == 1:
            kept.append(group[0])
            continue
        group.sort(key=lambda e: (e["path"].name not in preferred, e["path"].name))
        kept.append(group[0])
        dupes.extend(group[1:])

    by_work = {}
    for e in sorted(kept, key=lambda e: e["rank"]):
        key = (normalize(e["title"]), normalize(e["author"]))
        if key in by_work:
            dupes.append(e)
        else:
            by_work[key] = e

    result = sorted(by_work.values(), key=lambda e: e["rank"])
    return result, dupes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="move duplicates and write InitialLibrary.json")
    args = parser.parse_args()

    books, dupes = collect_books()
    print(f"kept {len(books)} books, {len(dupes)} duplicates")
    for d in dupes:
        print(f"  dupe: {d['path'].relative_to(REPO_ROOT)}")

    catalog = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    existing_ids = {b["id"] for b in catalog["books"]}
    new_entries = [
        {
            "id": b["id"],
            "title": b["title"],
            "author": b["author"],
            "category": b["category"],
            "themes": [],
        }
        for b in books
        if b["id"] not in existing_ids
    ]
    print(f"catalog: {len(existing_ids)} existing + {len(new_entries)} new")

    if not args.apply:
        print("dry-run; re-run with --apply to write changes")
        return

    for d in dupes:
        EXCLUDED_DIR.mkdir(parents=True, exist_ok=True)
        dest = EXCLUDED_DIR / d["path"].name
        if dest.exists():
            print(f"  skip move (exists): {dest.name}")
            continue
        shutil.move(str(d["path"]), str(dest))
        print(f"  moved: {d['path'].name} → books/duplicates_excluded/")

    catalog["books"].extend(new_entries)
    JSON_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {JSON_PATH.relative_to(REPO_ROOT)} ({len(catalog['books'])} books total)")


if __name__ == "__main__":
    main()
