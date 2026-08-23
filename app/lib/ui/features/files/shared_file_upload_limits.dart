/// Client-side mirror of the server's file size cap
/// (server/migrations/12_files.go's `MaxSize: 100 << 20`), kept as its own
/// tiny pure module (like `instant_image_prep.dart`'s sizing helpers) so
/// the limit check is unit-testable without a picker or a server. Checking
/// client-side means a too-big pick gets an honest, immediate "too big"
/// message instead of spending minutes uploading 100MB+ only for the
/// server to reject it at the very end.
const sharedFileMaxUploadBytes = 100 << 20;

bool isWithinSharedFileUploadLimit(int bytes) =>
    bytes <= sharedFileMaxUploadBytes;
