import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final renameTemplatesProvider =
    AsyncNotifierProvider<RenameTemplatesNotifier, Map<String, String>>(
        RenameTemplatesNotifier.new);

class RenameTemplatesNotifier extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    final client = ref.watch(apiClientProvider);
    return client.fetchRenameTemplates();
  }

  Future<void> save(Map<String, String> templates) async {
    await ref.read(apiClientProvider).saveRenameTemplates(templates);
    ref.invalidateSelf();
  }
}

// ---------------------------------------------------------------------------
// renderTemplateExample — pure preview function (Dart port of backend resolver)
// ---------------------------------------------------------------------------

const _sampleFields = {
  'series': 'Saga',
  'number': '7',
  'year': '2013',
  'title': 'Chapter Seven',
  'format': 'TPB',
  'volume': '2',
};

/// Matches {key} or {key:0N} placeholders.
final _placeholderRe = RegExp(r'\{([a-z_]+)(?::0(\d+))?\}');

/// Render [tpl] against sample fields for live preview.
///
/// Substitution rules (mirroring backend rename.Resolve):
/// - Known key with value → substitute (zero-pad numeric values if `:0N` given).
/// - Unknown key or empty value → drop placeholder; then scrub resulting empty
///   bracket pairs `()` / `[]` / `( )` / `[ ]`, squeeze whitespace, and trim
///   stray leading/trailing separators (` -#`).
String renderTemplateExample(String tpl) {
  // Step 1: substitute or remove each placeholder.
  var out = tpl.replaceAllMapped(_placeholderRe, (m) {
    final key = m.group(1)!;
    final val = _sampleFields[key] ?? '';
    if (val.isEmpty) return '\x00'; // sentinel for "removed placeholder"
    final padWidth = m.group(2);
    if (padWidth != null) {
      final n = int.tryParse(val);
      if (n != null) {
        return n.toString().padLeft(int.parse(padWidth), '0');
      }
      // Non-numeric value with pad spec → return as-is
      return val;
    }
    return val;
  });

  // Step 2: drop sentinel and any adjacent literal fragments that end up empty.
  // Strategy: remove the sentinel marker, then clean up orphaned punctuation.
  out = out.replaceAll('\x00', '');

  // Step 3: collapse empty bracket pairs (may have spaces inside after removal).
  for (final pair in [
    RegExp(r'\(\s*\)'),
    RegExp(r'\[\s*\]'),
  ]) {
    out = out.replaceAll(pair, '');
  }

  // Step 4: squeeze runs of whitespace to single space, trim.
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Step 5: trim stray leading/trailing separators left by removed placeholders.
  out = out.replaceAll(RegExp(r'^[\s\-#]+|[\s\-#]+$'), '').trim();

  return out;
}
