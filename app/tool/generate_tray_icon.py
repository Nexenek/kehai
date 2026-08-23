#!/usr/bin/env python3
"""Draws Kehai's tray icon — a chunky pixel heart — and writes both platform
formats: a 32x32 RGBA PNG (Linux/GTK) and a 32x32 32-bit ICO (Windows).

The source of truth is the 16x16 pixel grid below, scaled 2x with
nearest-neighbour so it stays crisp (kb/design-language.md: "texture
filtering OFF — nearest/point sampling everywhere or the crispness dies").
Palette is the app's own: chrome pink fill, deep-pink shading, ink outline.

Also emits the app icon set from the *same* 16x16 art, nearest-neighbour
scaled to whatever size each platform wants:

- Android: legacy mipmap-*/ic_launcher.png (mdpi..xxxhdpi) for API <26, PLUS
  an adaptive icon (mipmap-anydpi-v26/ic_launcher.xml) — a flat chrome-pink
  (#f4cbdc) background color layer + an ic_launcher_foreground.png per
  density, the heart rendered into a padded 24x24 grid so it sits inside
  Android's ~66%-of-canvas safe zone instead of getting clipped by the
  launcher's circle/squircle mask.
- Windows: windows/runner/resources/app_icon.ico, multi-size (16/32/48/256),
  replacing Flutter's default. Runner.rc already points IDI_APP_ICON at this
  file — nothing else to wire.
- Linux: assets/icons/kehai_icon.png, a single 256px PNG. GTK has no
  compiled-resource icon slot like Windows' .rc, so this is wired at runtime
  instead — see DesktopWindowService.bootstrap()'s windowManager.setIcon()
  call, Linux-only (window_manager's Dart doc says "@platforms windows" but
  its Linux plugin implements setIcon via gtk_window_set_icon_from_file, and
  the bundle layout the Dart side assumes — data/flutter_assets next to the
  executable — matches Linux's bundle just as much as Windows'; this was
  cheaper than patching my_application.cc for a one-line result).

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
    """Returns SIZE rows of SIZE RGBA tuples. Unchanged — this is exactly
    what shipped as the tray icon; app-icon generation below uses its own
    (more general) scaler so this path, and its output bytes, never move."""
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


# ---------------------------------------------------------------------------
# App icon set — general nearest-neighbour scaler, any square grid to any
# square output size (not just clean integer multiples of 16).
# ---------------------------------------------------------------------------


def pad_grid(grid, total):
    """Centers `grid` (square, side N) inside a `total`x`total` grid of '.'
    (transparent). Used for the adaptive-icon foreground, so the heart sits
    inside Android's ~66%-of-canvas safe zone instead of touching the mask
    edge."""
    n = len(grid)
    border = (total - n) // 2
    blank = "." * total
    rows = [blank] * border
    for line in grid:
        rows.append("." * border + line + "." * border)
    rows += [blank] * (total - len(rows))
    return rows


def render(grid, size):
    """Nearest-neighbour resample of a square `grid` of palette chars to a
    `size`x`size` list of RGBA rows. Works for any size, not just exact
    multiples of the grid's side — each output pixel maps back to the source
    cell it falls in, so edges stay crisp instead of blurring."""
    n = len(grid)
    rows = []
    for y in range(size):
        src_y = y * n // size
        row = []
        for x in range(size):
            src_x = x * n // size
            row.append(PALETTE[grid[src_y][src_x]])
        rows.append(row)
    return rows


def png_bytes(rows, size):
    raw = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *px) for px in row) for row in rows
    )

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">2I5B", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def write_png_at(grid, size, path):
    path.write_bytes(png_bytes(render(grid, size), size))


# Android launcher: legacy density buckets (API <26 and the play-store/
# fallback icon) — full-bleed heart, no safe-zone padding needed since
# there's no mask.
ANDROID_DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ADAPTIVE_ICON_BG = "#F4CBDC"  # chrome pink — kb/design-language.md `chrome`

ADAPTIVE_ICON_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""

ADAPTIVE_ICON_BG_COLOR_XML = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Adaptive icon background — kb/design-language.md `chrome` token.
         Generated alongside the icon set by tool/generate_tray_icon.py. -->
    <color name="ic_launcher_background">{ADAPTIVE_ICON_BG}</color>
</resources>
"""

# ICO sizes for the Windows runner icon. 256 is embedded as a raw PNG chunk
# (the ICO spec's only way to fit a size that needs 0 in the 1-byte
# width/height field); the rest reuse the classic BMP-in-ICO encoding.
WINDOWS_ICO_SIZES = [16, 32, 48, 256]


def bmp_ico_image(rows, size):
    xor = bytearray()
    for row in reversed(rows):
        for r, g, b, a in row:
            xor += bytes((b, g, r, a))
    and_mask = bytearray()
    for row in reversed(rows):
        bits = 0
        for x in range(size):
            bits |= (0 if row[x][3] else 1) << (7 - (x % 8))
            if x % 8 == 7:
                and_mask.append(bits)
                bits = 0
        if size % 8:
            and_mask.append(bits)
        while len(and_mask) % 4:
            and_mask.append(0)
    dib = struct.pack("<3I2H6I", 40, size, size * 2, 1, 32, 0, len(xor), 0, 0, 0, 0)
    return dib + bytes(xor) + bytes(and_mask)


def write_multi_ico(grid, sizes, path):
    entries = []  # (width_byte, height_byte, planes, bitcount, image_bytes)
    for size in sizes:
        if size == 256:
            image = png_bytes(render(grid, size), size)
            entries.append((0, 0, 1, 32, image))
        else:
            image = bmp_ico_image(render(grid, size), size)
            entries.append((size, size, 1, 32, image))

    header = struct.pack("<3H", 0, 1, len(entries))
    dir_entries = b""
    offset = 6 + 16 * len(entries)
    images = b""
    for width_b, height_b, planes, bitcount, image in entries:
        dir_entries += struct.pack(
            "<4B2H2I", width_b, height_b, 0, 0, planes, bitcount, len(image), offset
        )
        images += image
        offset += len(image)
    path.write_bytes(header + dir_entries + images)


def generate_app_icon_set(app_root: Path):
    android_res = app_root / "android" / "app" / "src" / "main" / "res"
    for dirname, size in ANDROID_DENSITIES.items():
        out_dir = android_res / dirname
        out_dir.mkdir(parents=True, exist_ok=True)
        write_png_at(GRID, size, out_dir / "ic_launcher.png")
        # Adaptive-icon foreground: same density bucket, heart padded down to
        # ~2/3 of the canvas (24x24 virtual grid) so it clears the safe zone.
        write_png_at(pad_grid(GRID, 24), size, out_dir / "ic_launcher_foreground.png")

    anydpi = android_res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(ADAPTIVE_ICON_XML)

    values = android_res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(ADAPTIVE_ICON_BG_COLOR_XML)

    windows_ico = app_root / "windows" / "runner" / "resources" / "app_icon.ico"
    windows_ico.parent.mkdir(parents=True, exist_ok=True)
    write_multi_ico(GRID, WINDOWS_ICO_SIZES, windows_ico)

    linux_icon_dir = app_root / "assets" / "icons"
    linux_icon_dir.mkdir(parents=True, exist_ok=True)
    write_png_at(GRID, 256, linux_icon_dir / "kehai_icon.png")

    print(f"wrote Android launcher/adaptive icons under {android_res}")
    print(f"wrote {windows_ico}")
    print(f"wrote {linux_icon_dir}/kehai_icon.png")


if __name__ == "__main__":
    app_root = Path(__file__).resolve().parent.parent
    out = app_root / "assets" / "tray"
    out.mkdir(parents=True, exist_ok=True)
    grid = pixels()
    write_png(grid, out / "kehai_heart.png")
    write_ico(grid, out / "kehai_heart.ico")
    print(f"wrote {out}/kehai_heart.png and kehai_heart.ico ({SIZE}x{SIZE})")

    generate_app_icon_set(app_root)
