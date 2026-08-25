#!/usr/bin/env python3
"""Download the curated initial-library EPUBs.

Reads Tomeet/Tomeet/Data/InitialLibrary.json and downloads every book's EPUB.
Strategy:
  1. Try Standard Ebooks using the slug in sourceHint.standardEbooks.
  2. If that fails, query Gutendex (Project Gutenberg mirror) by title+author
     and download the EPUB from Gutenberg.

All files are saved as public_domain_books/books/<book.id>.epub so the Xcode
build phase can extract them into the app bundle.

Usage:
    python3 scripts/download-initial-library.py

Add --force to re-download files that already exist.
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
JSON_PATH = REPO_ROOT / "Tomeet" / "Tomeet" / "Data" / "InitialLibrary.json"
OUTPUT_DIR = REPO_ROOT / "public_domain_books" / "books"
SE_URL = "https://standardebooks.org/ebooks/{author}/{title}/downloads/{slug}.epub?source=download"
GUTENDEX_URL = "https://gutendex.com/books/"
USER_AGENT = "Tomeet/1.0 (initial library sync; contact developer)"


def load_catalog(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def split_slug(slug: str) -> Optional[Tuple[str, str]]:
    """Split a Standard Ebooks slug like 'jane-austen_pride-and-prejudice'
    into (author, title) for the URL path."""
    parts = slug.split("_", 1)
    if len(parts) != 2:
        return None
    return parts[0], parts[1]


def is_valid_epub(path: Path) -> bool:
    """Check file magic bytes for ZIP/EPUB."""
    if not path.exists() or path.stat().st_size < 4:
        return False
    with path.open("rb") as f:
        return f.read(4) == b"PK\x03\x04"


def cleanup_orphaned_epubs(output_dir: Path, valid_ids: set[str]) -> None:
    """Remove .epub files whose stem is no longer in the catalog."""
    if not output_dir.exists():
        return
    for path in output_dir.glob("*.epub"):
        if path.stem not in valid_ids:
            print(f"  cleanup {path.name}")
            path.unlink()


def fetch_json(url: str, timeout: int = 30) -> Optional[dict]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as e:
        print(f"  warn    API error for {url}: {e}")
        return None


def find_gutenberg_url(title: str, author: str) -> Optional[str]:
    """Use Gutendex to find a Gutenberg EPUB URL for the given title+author."""
    query = urllib.parse.quote(f"{title} {author}")
    data = fetch_json(f"{GUTENDEX_URL}?search={query}")
    if not data or not data.get("results"):
        return None

    for result in data["results"]:
        formats = result.get("formats", {})
        # Prefer image-including EPUB, fallback to no-images EPUB.
        for fmt in ["application/epub+zip", "application/epub"]:
            if fmt in formats:
                return formats[fmt]
    return None


def download(url: str, dest: Path, force: bool = False) -> bool:
    if not force and is_valid_epub(dest):
        print(f"  exists  {dest.name} ({dest.stat().st_size:,} bytes)")
        return True

    # Remove any previous incomplete/bogus download.
    if dest.exists():
        dest.unlink()

    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        if not is_valid_epub(dest):
            print(f"  FAIL    {dest.name} — downloaded file is not a valid EPUB")
            dest.unlink()
            return False
        print(f"  ok      {dest.name} ({len(data):,} bytes)")
        return True
    except urllib.error.HTTPError as e:
        print(f"  FAIL    {dest.name} — HTTP {e.code}: {e.reason}")
        return False
    except Exception as e:
        print(f"  FAIL    {dest.name} — {e}")
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Download Tomeet initial library EPUBs")
    parser.add_argument("--force", action="store_true", help="re-download existing files")
    parser.add_argument("--delay", type=float, default=1.0, help="seconds between downloads")
    args = parser.parse_args()

    if not JSON_PATH.exists():
        print(f"Catalog not found: {JSON_PATH}", file=sys.stderr)
        return 1

    catalog = load_catalog(JSON_PATH)
    books = catalog.get("books", [])
    valid_ids = {book.get("id") for book in books if book.get("id")}
    cleanup_orphaned_epubs(OUTPUT_DIR, valid_ids)

    print(f"Downloading {len(books)} books...")
    print(f"Output directory: {OUTPUT_DIR}")

    failures = []
    skipped = 0
    downloaded = 0
    from_gutenberg = 0
    from_se = 0

    for book in books:
        book_id = book.get("id")
        title = book.get("title", "?")
        author = book.get("author", "?")
        if not book_id:
            print(f"  SKIP    {title} — no id")
            failures.append((title, "no id"))
            continue

        dest = OUTPUT_DIR / f"{book_id}.epub"

        if not args.force and is_valid_epub(dest):
            skipped += 1
            print(f"  exists  {dest.name}")
            continue

        # Try Standard Ebooks first.
        se_slug = book.get("sourceHint", {}).get("standardEbooks")
        se_ok = False
        if se_slug:
            split = split_slug(se_slug)
            if split:
                se_author, se_title = split
                se_url = SE_URL.format(author=se_author, title=se_title, slug=se_slug)
                print(f"  trying  {dest.name} (SE)")
                if download(se_url, dest, force=args.force):
                    se_ok = True
                    from_se += 1

        # Fallback to Project Gutenberg via Gutendex.
        if not se_ok:
            print(f"  trying  {dest.name} (Gutenberg fallback)")
            gutenberg_url = find_gutenberg_url(title, author)
            if gutenberg_url:
                if download(gutenberg_url, dest, force=args.force):
                    from_gutenberg += 1
                else:
                    failures.append((title, f"Gutenberg: {gutenberg_url}"))
            else:
                print(f"  FAIL    {dest.name} — no Gutenberg URL found")
                failures.append((title, "no Gutenberg URL"))

        downloaded += 1
        if args.delay > 0:
            time.sleep(args.delay)

    print()
    print(
        f"Done. SE: {from_se}, Gutenberg: {from_gutenberg}, "
        f"skipped: {skipped}, failures: {len(failures)}"
    )

    if failures:
        print("\nFailed downloads:")
        for title, reason in failures:
            print(f"  - {title}: {reason}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
