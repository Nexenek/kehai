import 'dart:typed_data';

/// Hard ceiling mirrored from the server's `image` field
/// (server/migrations/10_art.go: `MaxSize: 2 << 20`). Checked client-side
/// too so an oversized file gets a sentence instead of a 400.
const int artMaxUploadBytes = 2 * 1024 * 1024;

/// What the how-to text recommends drawing on. Not enforced anywhere — the
/// compositor scales whatever it's given into the same square — but every
/// layer being the same size is what makes the anchors line up (ADR-13's
/// "fixed canvas + anchor grid").
const int artRecommendedCanvas = 512;

/// Mirrors the server's `name` field max.
const int artLayerNameMaxLength = 60;

/// The eight bytes every PNG file starts with.
const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Why a picked file can't become an art layer. Null = it's fine.
enum ArtUploadProblem {
  /// Not a PNG. A JPEG has no transparency, so it would paint an opaque
  /// rectangle over every layer beneath it — the single most confusing
  /// failure in a layer system, and worth refusing loudly.
  notPng,

  /// Over [artMaxUploadBytes]; the server would refuse it anyway.
  tooBig,

  /// Zero bytes / unreadable pick.
  empty,
}

/// Sniffs the actual bytes rather than trusting the file extension — the
/// desktop file picker will happily hand over `sketch.png` that's really a
/// JPEG someone renamed.
bool isPngBytes(Uint8List bytes) {
  if (bytes.length < _pngMagic.length) return false;
  for (var i = 0; i < _pngMagic.length; i++) {
    if (bytes[i] != _pngMagic[i]) return false;
  }
  return true;
}

/// The one gate every upload goes through. Pure, so the honest-copy path is
/// unit-testable without touching a file picker.
ArtUploadProblem? checkArtUpload(Uint8List bytes) {
  if (bytes.isEmpty) return ArtUploadProblem.empty;
  if (!isPngBytes(bytes)) return ArtUploadProblem.notPng;
  if (bytes.length > artMaxUploadBytes) return ArtUploadProblem.tooBig;
  return null;
}

/// A PNG's pixel dimensions, straight out of its IHDR chunk.
class PngSize {
  const PngSize(this.width, this.height);

  final int width;
  final int height;

  bool get isSquare => width == height && width > 0;

  @override
  bool operator ==(Object other) =>
      other is PngSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// Reads width/height from the IHDR chunk (bytes 16..24 of any valid PNG)
/// without decoding the image. Used only to warn the artist that a layer
/// isn't square or doesn't match the rest of the set — never to refuse an
/// upload, because "wrong size" is a taste call, not an error.
PngSize? readPngSize(Uint8List bytes) {
  if (!isPngBytes(bytes) || bytes.length < 24) return null;
  final data = ByteData.sublistView(bytes, 16, 24);
  final width = data.getUint32(0);
  final height = data.getUint32(4);
  if (width == 0 || height == 0) return null;
  return PngSize(width, height);
}

/// Upload filename. PocketBase only uses it for the stored file's name and
/// extension, so it just needs to be a sane `.png`.
String artUploadFilename(String slotName, String originalName) {
  final trimmed = originalName.trim();
  if (trimmed.toLowerCase().endsWith('.png') && trimmed.length > 4) {
    return trimmed;
  }
  return '$slotName.png';
}
