import 'dart:io';
import 'package:path/path.dart' as p;

final _index = <String, Map<int, File>>{};

/// A downloaded page's file: names are the 1-based page number, with or
/// without an extension (archive-era downloads have one). The directory is
/// listed once; a complete download doesn't change.
File? localPageFile(String pagesDir, int page) {
  final files = _index.putIfAbsent(pagesDir, () {
    try {
      return {
        for (final f in Directory(pagesDir).listSync().whereType<File>())
          ?int.tryParse(p.basenameWithoutExtension(f.path)): f,
      };
    } catch (_) {
      return {};
    }
  });
  return files[page + 1];
}

/// Drops the cached listing of [pagesDir]: its comic was deleted or imported.
void forgetLocalPages(String pagesDir) => _index.remove(pagesDir);
