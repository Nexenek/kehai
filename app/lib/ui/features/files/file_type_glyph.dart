/// Pixel type-glyph for a shared file's extension (kb/design-language.md:
/// "text glyphs, FE0E discipline" — every glyph below defaults to text
/// presentation already, so none needs a `︎` selector; see
/// `board_stickers.dart`'s note on the same discipline).
///
/// [extension] should already be lowercased with no leading dot (see
/// `SharedFile.extension`).
String sharedFileGlyph(String extension) {
  if (_imageExtensions.contains(extension)) return _imageGlyph;
  if (_audioExtensions.contains(extension)) return _audioGlyph;
  if (_videoExtensions.contains(extension)) return _videoGlyph;
  if (_docExtensions.contains(extension)) return _docGlyph;
  return _otherGlyph;
}

const _imageGlyph = '◉';
const _audioGlyph = '♪';
const _videoGlyph = '▸';
const _docGlyph = '✎';
const _otherGlyph = '▪';

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'svg',
  'tiff',
  'avif',
};

const _audioExtensions = {
  'mp3',
  'wav',
  'flac',
  'ogg',
  'oga',
  'm4a',
  'aac',
  'wma',
  'opus',
};

const _videoExtensions = {
  'mp4',
  'mov',
  'mkv',
  'webm',
  'avi',
  'wmv',
  'm4v',
  'flv',
};

const _docExtensions = {
  'pdf',
  'doc',
  'docx',
  'txt',
  'md',
  'rtf',
  'odt',
  'xls',
  'xlsx',
  'csv',
  'ppt',
  'pptx',
  'pages',
  'key',
  'numbers',
};
