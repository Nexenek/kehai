#!/usr/bin/env python3
"""Draws Kehai's activity-aware status-bar (notification) icon set: ten
monochrome, chunky pixel-art glyphs — one per `AmbientLine`/activity bucket
`lib/domain/notification_icon.dart` can pick between, so a glance at the
Android status bar says "she's listening to music" / "coding" / "scrolling"
instead of just "app is running" (see kb/roadmap.md Wave 6 and
kehai_foreground_task.dart's `render`).

Android's status-bar small icon is tint-only: the platform recolors
whatever it's handed to match the shade/system color, so ONLY THE ALPHA
CHANNEL MATTERS. Every glyph here is drawn with a single opaque white and
otherwise fully transparent — no outline/shade palette like the launcher
heart (generate_tray_icon.py) needs, since there's nothing to shade.

Same style as generate_tray_icon.py: hand-placed pixel art on a small grid
(16x16 here), nearest-neighbour upscaled, hand-rolled PNG writer (struct +
zlib — no Pillow dependency, matching the precedent script, which doesn't
use Pillow either despite 32-bit RGBA PNGs looking like it might).

Unlike the heart, most of these shapes are built from little geometry
helpers (rect/ellipse/line/triangle cell-sets) rather than typed-out ASCII
grids — mistyping one character in a 16-wide ASCII art row is an easy way
to silently misalign a glyph, and the geometry helpers can't do that: they
either produce a cell inside the 16x16 canvas or they don't.

Run: python3 tool/generate_notification_icons.py   (from app/)

Output: PNGs at every density Android's notification-icon guidance expects
(24/36/48/72/96 px for mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi — the same 24dp base
size as any status-bar icon), under
android/app/src/main/res/drawable-<density>/ic_stat_<name>.png.

IMPORTANT: every name generated here must also be declared as an
`<meta-data android:resource="@drawable/...">` entry in AndroidManifest.xml
(flutter_foreground_task's `NotificationIcon.metaDataName` reads a manifest
meta-data int, not an arbitrary runtime resource-name lookup — see
kehai_foreground_task.dart's doc comment on `render`) AND kept in sync with
`lib/domain/notification_icon.dart`'s `_knownIcons` set, which is the
single source of truth `notificationIconFor` is asserted against.
"""

import struct
import zlib
from pathlib import Path

GRID_SIZE = 16

WHITE = (0xFF, 0xFF, 0xFF, 0xFF)
NONE = (0x00, 0x00, 0x00, 0x00)

# ---------------------------------------------------------------------------
# Geometry helpers — every one returns a set of (row, col) cells on the
# 16x16 canvas (row 0 = top, col 0 = left). Icons are built by unioning
# (`|`) and subtracting (`-`) these sets, then rasterised by `grid_from_cells`.
# ---------------------------------------------------------------------------


def rect(r0, r1, c0, c1):
    """All cells in the inclusive rows [r0, r1] x cols [c0, c1] box. r0==r1
    (or c0==c1) gives a straight 1-cell-thick bar — used for the eighth
    note's flag rows and the code icon's underscore."""
    return {(r, c) for r in range(r0, r1 + 1) for c in range(c0, c1 + 1)}


def rect_border(r0, r1, c0, c1, t=1):
    """The `t`-thick outline of the same box — a hollow rounded-rect look
    for the phone/screen/speech-bubble glyphs."""
    outer = rect(r0, r1, c0, c1)
    if r1 - r0 + 1 <= 2 * t or c1 - c0 + 1 <= 2 * t:
        return outer
    inner = rect(r0 + t, r1 - t, c0 + t, c1 - t)
    return outer - inner


def ellipse(cr, cc, rx, ry):
    """Filled ellipse centered at (cr, cc) with radii (rx, ry) — cell
    centers are tested against the standard ellipse inequality."""
    cells = set()
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            dr = (r - cr) / ry
            dc = (c - cc) / rx
            if dr * dr + dc * dc <= 1.0:
                cells.add((r, c))
    return cells


def line(r0, c0, r1, c1, width=1):
    """A `width`-thick Bresenham line from (r0, c0) to (r1, c1)."""
    cells = set()
    dr = abs(r1 - r0)
    dc = abs(c1 - c0)
    sr = 1 if r0 < r1 else -1
    sc = 1 if c0 < c1 else -1
    err = dr - dc
    r, c = r0, c0
    lo = -(width // 2)
    hi = width - width // 2
    while True:
        for wr in range(lo, hi):
            for wc in range(lo, hi):
                cells.add((r + wr, c + wc))
        if r == r1 and c == c1:
            break
        e2 = 2 * err
        if e2 > -dc:
            err -= dc
            r += sr
        if e2 < dr:
            err += dr
            c += sc
    return cells


def triangle(p1, p2, p3):
    """Filled triangle over three (row, col) vertices, via a barycentric
    area test."""
    (r1, c1), (r2, c2), (r3, c3) = p1, p2, p3

    def area2(ar, ac, br, bc, cr, cc):
        return abs((br - ar) * (cc - ac) - (cr - ar) * (bc - ac))

    total = area2(r1, c1, r2, c2, r3, c3)
    if total == 0:
        return set()
    cells = set()
    for r in range(GRID_SIZE):
        for c in range(GRID_SIZE):
            a1 = area2(r, c, r2, c2, r3, c3)
            a2 = area2(r1, c1, r, c, r3, c3)
            a3 = area2(r1, c1, r2, c2, r, c)
            if abs(a1 + a2 + a3 - total) < 0.5:
                cells.add((r, c))
    return cells


def letter_z(r0, r1, c0, c1, thickness=1):
    """One "Z": a top bar, a bottom bar, and a top-right-to-bottom-left
    diagonal — used three times, shrinking, for the sleep glyph's "zzZ"."""
    top = rect(r0, r0 + thickness - 1, c0, c1)
    bottom = rect(r1 - thickness + 1, r1, c0, c1)
    diag = line(r0, c1, r1, c0, thickness)
    return top | bottom | diag


def outline_of(cells):
    """The 1px border of a filled cell-set: every cell that has at least
    one of its 4-neighbours outside the set. Turns a filled silhouette into
    a hollow one — used to turn the heart into the "away" glyph's empty
    outline heart (design.md: "small ghost or empty outline heart" — the
    hollow heart reads as clearly as a ghost at this size and reuses the
    app's own icon language instead of introducing a new character)."""
    result = set()
    for r, c in cells:
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            if (r + dr, c + dc) not in cells:
                result.add((r, c))
                break
    return result


def clip(cells):
    return {(r, c) for r, c in cells if 0 <= r < GRID_SIZE and 0 <= c < GRID_SIZE}


def grid_from_cells(cells):
    """Cell-set -> 16 strings of 'W'/'.' — the same char-grid shape
    generate_tray_icon.py's hand-typed GRID uses, so it feeds the same kind
    of nearest-neighbour scaler."""
    cells = clip(cells)
    rows = []
    for r in range(GRID_SIZE):
        rows.append("".join("W" if (r, c) in cells else "." for c in range(GRID_SIZE)))
    return rows


# ---------------------------------------------------------------------------
# The ten glyphs.
# ---------------------------------------------------------------------------

# The launcher heart's silhouette (generate_tray_icon.py's GRID), copied
# verbatim — every non-'.' char there becomes an opaque white cell here, so
# `ic_stat_heart` reads as the exact same heart shape at any size, launcher
# icon included.
_HEART_ASCII = [
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


def _heart_cells():
    cells = set()
    for r, row in enumerate(_HEART_ASCII):
        for c, ch in enumerate(row):
            if ch != ".":
                cells.add((r, c))
    return cells


def _music_cells():
    notehead = ellipse(10, 6, 3.2, 2.4)
    stem = rect(2, 10, 9, 10)
    # A downward-tapering flag off the top of the stem.
    flag = rect(2, 2, 9, 13) | rect(3, 3, 9, 13) | rect(4, 4, 9, 12) | rect(5, 5, 9, 11)
    return notehead | stem | flag


def _code_cells():
    border = rect_border(1, 14, 1, 14, 1)
    # ">" chevron.
    chevron = line(5, 4, 8, 7, 2) | line(8, 7, 11, 4, 2)
    # "_" cursor.
    cursor = rect(10, 11, 9, 13)
    return border | chevron | cursor


def _scroll_cells():
    phone = rect_border(2, 13, 5, 10, 1)
    home_dot = rect(12, 12, 7, 8)
    # Motion/swipe marks to the phone's left.
    motion = rect(4, 4, 1, 3) | rect(7, 7, 1, 3) | rect(10, 10, 1, 3)
    return phone | home_dot | motion


def _watch_cells():
    screen = rect_border(2, 13, 2, 13, 1)
    play = triangle((5, 6), (11, 6), (8, 12))
    return screen | play


def _game_cells():
    body = rect(6, 10, 3, 12)
    corners = {(6, 3), (6, 12), (10, 3), (10, 12)}
    left_grip = ellipse(10, 3, 2.2, 2.2)
    right_grip = ellipse(10, 12, 2.2, 2.2)
    base = (body - corners) | left_grip | right_grip
    dpad_hole = rect(7, 9, 5, 5) | rect(8, 8, 4, 6)
    button_hole_a = rect(7, 7, 10, 10)
    button_hole_b = rect(9, 9, 10, 10)
    return base - dpad_hole - button_hole_a - button_hole_b


def _chat_cells():
    bubble = rect(2, 9, 2, 13)
    # Trim the four corners so the bubble reads as rounded, not square.
    corners = {(2, 2), (2, 13), (9, 2), (9, 13)}
    tail = triangle((9, 3), (12, 2), (9, 6))
    return (bubble - corners) | tail


def _photo_cells():
    body = rect(6, 12, 2, 13)
    viewfinder = rect(4, 5, 6, 9)
    lens_hole = ellipse(9, 7, 2.6, 2.6)
    return (body | viewfinder) - lens_hole


def _sleep_cells():
    z1 = letter_z(2, 6, 2, 8, thickness=2)
    z2 = letter_z(8, 10, 7, 11, thickness=1)
    z3 = letter_z(12, 13, 11, 14, thickness=1)
    return z1 | z2 | z3


def _away_cells():
    return outline_of(_heart_cells())


ICONS = {
    "ic_stat_heart": _heart_cells,
    "ic_stat_music": _music_cells,
    "ic_stat_code": _code_cells,
    "ic_stat_scroll": _scroll_cells,
    "ic_stat_watch": _watch_cells,
    "ic_stat_game": _game_cells,
    "ic_stat_chat": _chat_cells,
    "ic_stat_photo": _photo_cells,
    "ic_stat_sleep": _sleep_cells,
    "ic_stat_away": _away_cells,
}

# Notification-icon densities: Android's 24dp base status-bar icon size at
# each density bucket (24 * scale factor: 1 / 1.5 / 2 / 3 / 4).
DENSITIES = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}


def render(grid, size):
    """Nearest-neighbour resample of the 16x16 char grid to `size`x`size`
    RGBA rows — same algorithm as generate_tray_icon.py's `render`, kept
    independent here since this script has no other dependency on it."""
    n = len(grid)
    rows = []
    for y in range(size):
        src_y = y * n // size
        row = []
        for x in range(size):
            src_x = x * n // size
            row.append(WHITE if grid[src_y][src_x] == "W" else NONE)
        rows.append(row)
    return rows


def png_bytes(rows, size):
    raw = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *px) for px in row) for row in rows
    )

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">2I5B", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def generate(app_root: Path):
    android_res = app_root / "android" / "app" / "src" / "main" / "res"
    for name, build in ICONS.items():
        grid = grid_from_cells(build())
        assert len(grid) == GRID_SIZE and all(len(row) == GRID_SIZE for row in grid), (
            f"{name}: grid must be {GRID_SIZE}x{GRID_SIZE}"
        )
        for dirname, size in DENSITIES.items():
            out_dir = android_res / dirname
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path = out_dir / f"{name}.png"
            out_path.write_bytes(png_bytes(render(grid, size), size))
        print(f"wrote {name}.png at {', '.join(str(s) for s in DENSITIES.values())}px")


if __name__ == "__main__":
    app_root = Path(__file__).resolve().parent.parent
    generate(app_root)
    print(f"done — {len(ICONS)} icons x {len(DENSITIES)} densities under {app_root}/android/app/src/main/res/")
