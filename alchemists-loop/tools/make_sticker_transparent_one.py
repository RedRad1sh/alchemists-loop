#!/usr/bin/env python3
"""Run white-key on ONLY the files listed in args (or passed on cmdline)."""
import sys
from pathlib import Path
# Reuse module
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_stickers_transparent import process

STICKER_DIR = Path(__file__).resolve().parent.parent / "assets" / "spirits" / "stickers"

def main():
    targets = sys.argv[1:] if len(sys.argv) > 1 else sorted(p.name for p in STICKER_DIR.glob("*.png"))
    print(f"Processing {len(targets)} stickers\n")
    for name in targets:
        p = STICKER_DIR / name
        if p.exists():
            process(p)
    print("\nDone.")

if __name__ == "__main__":
    main()
