/// Leading articles ignored when filing a series, as a physical longbox would.
const _articles = ['the ', 'a ', 'an '];

/// The string a series sorts and files under: lowercased, with one leading
/// article and any leading punctuation removed.
///
/// Sorting and A–Z sectioning MUST both use this. If they disagree, a
/// section's members stop being contiguous in the sorted list and the index
/// rail scrolls to the wrong offset.
String sortTitle(String name) {
  var s = name.toLowerCase().trimLeft();
  for (final a in _articles) {
    if (s.startsWith(a)) {
      s = s.substring(a.length).trimLeft();
      break;
    }
  }
  // Drop leading characters that are neither a letter nor a digit.
  var i = 0;
  while (i < s.length && !RegExp(r'[a-z0-9]').hasMatch(s[i])) {
    i++;
  }
  s = s.substring(i);
  // Drop trailing characters that are neither a letter nor a digit.
  var j = s.length - 1;
  while (j >= 0 && !RegExp(r'[a-z0-9]').hasMatch(s[j])) {
    j--;
  }
  return s.substring(0, j + 1);
}

/// The section a series files under: `A`–`Z`, or `#` for digits, symbols and
/// empty names.
///
/// Note: Accented initials (Ámbar, Étoile) file under # due to [a-z] matching.
/// This is a coarse-bucketing limitation, not a contiguity bug; sorting and
/// sectioning agree.
String sectionKey(String name) {
  final s = sortTitle(name);
  if (s.isEmpty) return '#';
  final c = s[0].toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
}
