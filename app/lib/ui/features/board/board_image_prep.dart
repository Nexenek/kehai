import 'dart:typed_data';
import 'dart:ui' as ui;

/// Longest-side cap for a board photo — smaller than an instant's (see
/// `ui/features/instants/instant_image_prep.dart`) since board photos are
/// meant to render "small, instant-style" pinned to a corkboard tile, not
/// as a full-screen feed image.
const boardPhotoMaxDimension = 900;

/// Pure sizing decision, split out from the decode/re-encode below for the
/// same reason as `instant_image_prep.dart`'s `decideDownscale`: testable
/// without a Flutter binding or real image bytes.
class BoardDownscaleDecision {
  const BoardDownscaleDecision({
    required this.needed,
    required this.targetWidth,
    required this.targetHeight,
  });

  final bool needed;
  final int targetWidth;
  final int targetHeight;

  @override
  bool operator ==(Object other) =>
      other is BoardDownscaleDecision &&
      other.needed == needed &&
      other.targetWidth == targetWidth &&
      other.targetHeight == targetHeight;

  @override
  int get hashCode => Object.hash(needed, targetWidth, targetHeight);
}

BoardDownscaleDecision decideBoardDownscale(
  int width,
  int height, {
  int maxDimension = boardPhotoMaxDimension,
}) {
  if (width <= 0 || height <= 0) {
    return BoardDownscaleDecision(
      needed: false,
      targetWidth: width,
      targetHeight: height,
    );
  }
  final longest = width > height ? width : height;
  if (longest <= maxDimension) {
    return BoardDownscaleDecision(
      needed: false,
      targetWidth: width,
      targetHeight: height,
    );
  }
  final scale = maxDimension / longest;
  return BoardDownscaleDecision(
    needed: true,
    targetWidth: (width * scale).round(),
    targetHeight: (height * scale).round(),
  );
}

class PreparedBoardImage {
  const PreparedBoardImage({required this.bytes, required this.downscaled});

  final Uint8List bytes;
  final bool downscaled;
}

/// Decodes [bytes], downscales if the longest side exceeds
/// [boardPhotoMaxDimension], and returns bytes ready to upload. Same
/// PNG-re-encode tradeoff as `instant_image_prep.dart`'s
/// `prepareInstantImage` (no in-Flutter JPEG encoder without a new
/// dependency) — see that function's doc comment for the full reasoning.
Future<PreparedBoardImage> prepareBoardImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final decision = decideBoardDownscale(image.width, image.height);
    if (!decision.needed) {
      return PreparedBoardImage(bytes: bytes, downscaled: false);
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
        return PreparedBoardImage(bytes: bytes, downscaled: false);
      }
      return PreparedBoardImage(
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

String boardPhotoUploadFilename(bool downscaled, String originalName) {
  if (downscaled) return 'board_photo.png';
  return originalName.isNotEmpty ? originalName : 'board_photo.jpg';
}
