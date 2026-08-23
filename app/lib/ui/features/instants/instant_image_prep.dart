import 'dart:typed_data';
import 'dart:ui' as ui;

/// Longest-side cap enforced before upload — keeps the feed snappy without
/// a server-side resize step. Enforced client-side (rather than leaning on
/// `image_picker`'s own `maxWidth`/`maxHeight` params) because those only
/// take effect on mobile: the desktop `image_picker` implementation is
/// backed by `file_selector` and ignores them entirely, so this is the one
/// path that behaves the same on every platform.
const instantMaxDimension = 1600;

/// Caption limit mirrored from kb/contracts.md ("`caption` text ≤140").
const instantCaptionMaxLength = 140;

bool isCaptionWithinLimit(String caption) =>
    caption.length <= instantCaptionMaxLength;

/// Pure sizing decision for a [width]x[height] source image: does it need
/// downscaling, and if so to what target size (aspect ratio preserved,
/// longest side clamped to [maxDimension])? Split out from the actual
/// decode/re-encode ([prepareInstantImage]) so it's unit-testable without a
/// Flutter binding or real image bytes.
class DownscaleDecision {
  const DownscaleDecision({
    required this.needed,
    required this.targetWidth,
    required this.targetHeight,
  });

  final bool needed;
  final int targetWidth;
  final int targetHeight;

  @override
  bool operator ==(Object other) =>
      other is DownscaleDecision &&
      other.needed == needed &&
      other.targetWidth == targetWidth &&
      other.targetHeight == targetHeight;

  @override
  int get hashCode => Object.hash(needed, targetWidth, targetHeight);

  @override
  String toString() =>
      'DownscaleDecision(needed: $needed, target: ${targetWidth}x$targetHeight)';
}

DownscaleDecision decideDownscale(
  int width,
  int height, {
  int maxDimension = instantMaxDimension,
}) {
  if (width <= 0 || height <= 0) {
    return DownscaleDecision(
      needed: false,
      targetWidth: width,
      targetHeight: height,
    );
  }
  final longest = width > height ? width : height;
  if (longest <= maxDimension) {
    return DownscaleDecision(
      needed: false,
      targetWidth: width,
      targetHeight: height,
    );
  }
  final scale = maxDimension / longest;
  return DownscaleDecision(
    needed: true,
    targetWidth: (width * scale).round(),
    targetHeight: (height * scale).round(),
  );
}

/// The result of [prepareInstantImage]: bytes ready to upload, plus whether
/// they were re-encoded (which changes the format — see that function's
/// doc comment — so callers know to pick a `.png` filename).
class PreparedInstantImage {
  const PreparedInstantImage({required this.bytes, required this.downscaled});

  final Uint8List bytes;
  final bool downscaled;
}

/// Decodes [bytes], downscales if the longest side exceeds
/// [instantMaxDimension], and returns bytes ready to upload.
///
/// Tradeoff (no new deps, per the task brief): `dart:ui`'s
/// `Image.toByteData` only encodes PNG, not JPEG — there's no in-Flutter
/// JPEG encoder without pulling in `package:image`. So a downscaled photo
/// re-uploads as PNG (bigger than a re-compressed JPEG would be, but still
/// comfortably under the server's 5MB cap at 1600px). An image that's
/// already within the size cap uploads completely untouched — original
/// bytes, original format — so the common case (a phone camera shot
/// already ≤1600px on its longest side, or an already-reasonable gallery
/// pick) never pays the PNG-inflation cost at all.
Future<PreparedInstantImage> prepareInstantImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final decision = decideDownscale(image.width, image.height);
    if (!decision.needed) {
      return PreparedInstantImage(bytes: bytes, downscaled: false);
    }

    final resizedCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: decision.targetWidth,
      targetHeight: decision.targetHeight,
    );
    final resizedFrame = await resizedCodec.getNextFrame();
    final resizedImage = resizedFrame.image;
    try {
      final byteData = await resizedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        // Re-encode failed for some reason — fall back to the original
        // (oversized but honest) bytes rather than losing the photo.
        return PreparedInstantImage(bytes: bytes, downscaled: false);
      }
      return PreparedInstantImage(
        bytes: byteData.buffer.asUint8List(),
        downscaled: true,
      );
    } finally {
      resizedImage.dispose();
    }
  } finally {
    image.dispose();
  }
}

/// Filename to upload with — PNG for a downscaled (re-encoded) image, the
/// original name otherwise (falling back to a sane default if the picker
/// didn't give one, e.g. some desktop file-selector paths).
String instantUploadFilename(bool downscaled, String originalName) {
  if (downscaled) return 'instant.png';
  return originalName.isNotEmpty ? originalName : 'instant.jpg';
}
