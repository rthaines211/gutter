import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../services/local_import.dart';
import 'cache_providers.dart';
import 'download_provider.dart';
import 'mirror_provider.dart';
import 'navigation_provider.dart';
import 'server_actions.dart';
import 'source_provider.dart';

/// Lets the person pick comic files (the system Files picker; iOS only, see
/// `ComicPicker` in AppDelegate.swift). Returns the paths of *copies* in the
/// app's temp directory, empty when they cancel; the import deletes each
/// copy when it is done with it.
final comicFilePickerProvider = Provider<Future<List<String>> Function()>(
    (ref) => () async =>
        await const MethodChannel('app.comic_reader/files')
            .invokeListMethod<String>('pickComics') ??
        const []);

/// One picked file: [problem] is null when it was imported.
typedef ImportOutcome = ({String fileName, String? problem});

String importProblem(LocalImportError e) => switch (e) {
      LocalImportError.notAZip => 'Not a CBZ file.',
      LocalImportError.noImages => 'No pages found in it.',
      LocalImportError.alreadyImported => 'Already imported.',
      LocalImportError.tooLarge => 'Too large (over 4 GB unpacked).',
    };

/// How far a running import is, or null when none runs.
final localImportProvider =
    NotifierProvider<LocalImportNotifier, ({int done, int total})?>(
        LocalImportNotifier.new);

class LocalImportNotifier extends Notifier<({int done, int total})?> {
  @override
  ({int done, int total})? build() => null;

  /// Picks files and imports them into the active (local) source, one by
  /// one, then lists them in Downloads and syncs so the Library shows them.
  /// [intoLocal] is the one-step path from onboarding and Servers: the local
  /// source becomes active (made if there is none) and the Library opens,
  /// but only once a file is picked, so a cancel changes nothing.
  /// Free: no Pro gate, never [DownloadManager.enqueue].
  Future<List<ImportOutcome>> pickAndImport({bool intoLocal = false}) async {
    if (state != null) return const [];
    final paths = await ref.read(comicFilePickerProvider)();
    if (paths.isEmpty) return const [];
    if (intoLocal) {
      ref.read(navigationProvider.notifier).go(NavDestination.library);
      ref.read(serverActionsProvider).useLocal();
    }
    final sourceId = ref.read(activeSourceProvider).id;
    final outcomes = <ImportOutcome>[];
    state = (done: 0, total: paths.length);
    try {
      final docsDir = await ref.read(docsDirProvider.future);
      for (final path in paths) {
        String? problem;
        try {
          final comic = await importCbz(
              cbzPath: path, docsDir: docsDir, sourceId: sourceId);
          await ref.read(downloadManagerProvider)?.adopt(comic.comicId, sourceId);
        } on LocalImportException catch (e) {
          problem = importProblem(e.error);
        } catch (_) {
          problem = 'Could not be imported.';
        } finally {
          // The picker's copy: don't keep the comic twice.
          try {
            await File(path).delete();
          } catch (_) {}
        }
        outcomes.add((fileName: p.basename(path), problem: problem));
        state = (done: outcomes.length, total: paths.length);
      }
      try {
        // ponytail: right after a source switch the engine can still be
        // null; wait up to 2 s for it, else the next timed sync lists them.
        for (var i = 0; i < 20 && ref.read(syncEngineProvider) == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await ref.read(syncEngineProvider)?.sync(force: true);
      } catch (_) {
        // The next sync (launch, resume, the 60 s timer) lists them.
      }
    } finally {
      state = null;
    }
    return outcomes;
  }
}
