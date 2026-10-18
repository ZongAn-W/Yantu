"""Build the small startup font; keep the original for full offline coverage.

Requires fonttools and runs only when UI text or font sources change.
"""

import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / "assets" / "fonts"
OUTPUT = FONT_DIR / "PlannerSansSC-UI.ttf"


def startup_characters():
    characters = set(range(0x20, 0x7F))
    # GB2312 level 1 includes 3,755 common Chinese characters.
    for high in range(0xB0, 0xD8):
        for low in range(0xA1, 0xFF):
            try:
                characters.update(map(ord, bytes((high, low)).decode("gb2312")))
            except UnicodeDecodeError:
                continue
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        characters.update(map(ord, path.read_text(encoding="utf-8")))
    return characters


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    original = TTFont(FONT_DIR / "NotoSansSC.ttf", recalcTimestamp=False)
    expected = startup_characters() & original.getBestCmap().keys()
    if args.check:
        actual = TTFont(OUTPUT).getBestCmap().keys()
        missing = sorted(expected - actual)
        if missing:
            raise SystemExit(
                "Startup font is stale; run tool/subset-font.py. Missing: "
                + ", ".join(f"U+{value:04X}" for value in missing)
            )
        print(f"Startup font covers {len(expected):,} required code points.")
        return

    # A static regular instance is much smaller than the full variable font.
    font = instantiateVariableFont(original, {"wght": 400}, inplace=True)
    options = subset.Options()
    options.hinting = False
    options.recalc_timestamp = False
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=expected)
    subsetter.subset(font)
    names = {
        1: "Planner Sans SC UI",
        2: "Regular",
        3: "Planner Sans SC UI Regular",
        4: "Planner Sans SC UI Regular",
        6: "PlannerSansSCUI-Regular",
        16: "Planner Sans SC UI",
        17: "Regular",
    }
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    font.save(OUTPUT)
    print(f"{OUTPUT}: {OUTPUT.stat().st_size:,} bytes, {len(expected):,} code points")


if __name__ == "__main__":
    main()
