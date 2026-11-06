/// Trims, adds `https://` when no scheme was typed, and drops trailing
/// slashes: `nas.local:8080/` → `https://nas.local:8080`.
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// What to probe, in order. A typed scheme is taken as is; without one try
/// https, then plain http, which most LAN servers speak.
List<String> serverUrlCandidates(String input) {
  final url = normalizeServerUrl(input);
  if (input.trim().contains('://')) return [url];
  return [url, 'http://${url.substring('https://'.length)}'];
}
