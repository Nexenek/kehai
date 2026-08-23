#!/usr/bin/env python3
"""Draws Kehai's tray icon — a chunky pixel heart — and writes both platform
formats: a 32x32 RGBA PNG (Linux/GTK) and a 32x32 32-bit ICO (Windows).

The source of truth is the 16x16 pixel grid below, scaled 2x with
nearest-neighbour so it stays crisp (kb/design-language.md: "texture
filtering OFF — nearest/point sampling everywhere or the crispness dies").
Palette is the app's own: chrome pink fill, deep-pink shading, ink outline.

Run: python3 tool/generate_tray_icon.py   (from app/)
"""

import struct
import zlib
from pathlib import Path

INK = (0x36, 0x2D, 0x3B, 0xFF)  # #362d3b — the one hard dark
FILL = (0xF4, 0xCB, 0xDC, 0xFF)  # #f4cbdc — chrome pink
SHADE = (0xB2, 0x4D, 0x89, 0xFF)  # #b24d89 — accent, lower-right shading
NONE = (0x00, 0x00, 0x00, 0x00)

PALETTE = {"O": INK, "F": FILL, "S": SHADE, ".": NONE}

# 16x16. Two lobes, a soft valley, and a point — read at 16px in a panel.
GRID = [
    "................",
    "...OOO...OOO....",
    "..OFFFO.OFFFO...",
    ".OFFFFFOFFFFFSO.",
    ".OFFFFFFFFFFFSO.",
    ".OFFFFFFFFFFFSO.",
    ".OFFFFFFFFFFSSO.",
    "..OFFFFFFFFSSO..",
    "..OFFFFFFFSSO...",
    "...OFFFFFSSO....",
    "....OFFFSSO.....",
    ".....OFSSO......",
    "......OSO.......",
    ".......O........",
    "................",
    "................",
]

SCALE = 2
SIZE = 16 * SCALE


def pixels():
    """Returns SIZE rows of SIZE RGBA tuples."""
    assert len(GRID) == 16 and all(len(row) == 16 for row in GRID), "grid must be 16x16"
    rows = []
    for line in GRID:
        row = []
        for char in line:
            row.extend([PALETTE[char]] * SCALE)
        rows.extend([row] * SCALE)
    return rows


def write_png(rows, path):
    raw = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *px) for px in row) for row in rows
    )

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">2I5B", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def write_ico(rows, path):
    """32-bit BMP-in-ICO: universally understood, unlike PNG-in-ICO."""
    xor = bytearray()
    for row in reversed(rows):  # BMP rows run bottom-up
        for r, g, b, a in row:
            xor += bytes((b, g, r, a))

    and_mask = bytearray()
    for row in reversed(rows):
        bits = 0
        for x in range(SIZE):
            # 1 = transparent, for renderers that ignore the alpha channel.
            bits |= (0 if row[x][3] else 1) << (7 - (x % 8))
            if x % 8 == 7:
                and_mask.append(bits)
                bits = 0
        while len(and_mask) % 4:  # rows pad to 4 bytes
            and_mask.append(0)

    dib = struct.pack("<3I2H6I", 40, SIZE, SIZE * 2, 1, 32, 0, len(xor), 0, 0, 0, 0)
    image = dib + bytes(xor) + bytes(and_mask)
    header = struct.pack("<3H", 0, 1, 1) + struct.pack(
        "<4B2H2I", SIZE, SIZE, 0, 0, 1, 32, len(image), 22
    )
    path.write_bytes(header + image)


if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "assets" / "tray"
    out.mkdir(parents=True, exist_ok=True)
    grid = pixels()
    write_png(grid, out / "kehai_heart.png")
    write_ico(grid, out / "kehai_heart.ico")
    print(f"wrote {out}/kehai_heart.png and kehai_heart.ico ({SIZE}x{SIZE})")
