import 'dart:convert';

String stripComicExtension(String name) {
  return name.replaceAll(
      RegExp(r'\.(cbz|cbr|cb7|pdf)$', caseSensitive: false), '');
}

/// Decode a base64url-encoded comic ID back to its file path. Ids that
/// don't decode to a comic file (Komga's opaque ids) come back unchanged.
String comicIdToPath(String comicId) {
  final padded = comicId.padRight((comicId.length + 3) ~/ 4 * 4, '=');
  try {
    final path = utf8.decode(base64Url.decode(padded));
    return _comicFile.hasMatch(path) ? path : comicId;
  } catch (_) {
    return comicId;
  }
}

final _comicFile = RegExp(r'\.(cbz|cbr|cb7|pdf|epub)$', caseSensitive: false);
