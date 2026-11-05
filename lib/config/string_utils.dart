import 'dart:convert';

String stripComicExtension(String name) {
  return name.replaceAll(
      RegExp(r'\.(cbz|cbr|cb7|pdf)$', caseSensitive: false), '');
}

/// Decode a base64url-encoded comic ID back to its file path.
String comicIdToPath(String comicId) {
  final padded = comicId.padRight((comicId.length + 3) ~/ 4 * 4, '=');
  try {
    return utf8.decode(base64Url.decode(padded));
  } catch (_) {
    return comicId;
  }
}
