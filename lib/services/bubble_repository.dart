import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/page_bubbles.dart';
import 'api_client.dart';
import 'mirror/mirror_database.dart';
import 'panel_detector.dart';
import 'sync_queue.dart';

Object? _decode(String text) => jsonDecode(text);

/// Bubble-zoom sidecars for the comic open in the reader: the downloaded
/// bubbles.json first, else the server. Answers (including "not processed" and
/// malformed sidecars) are cached for the reader's lifetime; network errors are
/// not, so an offline miss retries.
class BubbleRepository {
  BubbleRepository({required this.client, this.queue, this.mirror});

  final ApiClient client;
  final SyncQueue? queue;

  /// Caches on-device panels ([detectedPanels]).
  final MirrorDatabase? mirror;
  final Map<int, PageBubbles?> _cache = {};
  String? _localDir;
  Future<Map<String, dynamic>?>? _localPages;
  Map<String, dynamic>? _localOrders;
  Future<void> _saving = Future.value();

  /// `downloads/<source>/<comic>` once the reader knows the comic is downloaded.
  set localDir(String? dir) {
    _localDir = dir;
    _localPages = null;
    _localOrders = null;
    _cache.clear();
  }

  Future<PageBubbles?> forPage(String comicId, int page) async {
    if (_cache.containsKey(page)) return _cache[page];
    final local = await (_localPages ??= _readLocal());
    Map<String, dynamic>? json;
    if (local != null) {
      json = local['$page'] as Map<String, dynamic>?;
    } else {
      try {
        json = await client.getPageBubbles(comicId, page);
      } catch (_) {
        return null;
      }
    }
    PageBubbles? pb;
    try {
      pb = json == null ? null : PageBubbles.fromJson(json);
    } catch (e) {
      debugPrint(
        'bubbles: malformed sidecar for page $page: $e',
      ); // host-job output; fall back
    }
    final saved = (await _readOrders())['$page'];
    if (pb != null && saved is List) pb.applyOrder(saved.cast<int>());
    return _cache[page] = pb;
  }

  /// Panels for a page with no sidecar, from the on-device model: the mirror's
  /// cached boxes, else detected on [image] (which this disposes) and cached,
  /// "none found" included. Null when the model can't run here.
  Future<PageBubbles?> detectedPanels(String comicId, int page, Future<ui.Image?> Function() image) async {
    final db = mirror;
    if (db == null) return null;
    var row = await db.panelsFor(comicId, page, panelModel);
    if (row == null) {
      final img = await image();
      if (img == null) return null;
      try {
        final panels = await detectPanels(img);
        if (panels == null) return null;
        row = PanelRow(
          comicId: comicId,
          page: page,
          model: panelModel,
          width: img.width,
          height: img.height,
          panels: jsonEncode([for (final r in panels) [r.left, r.top, r.right, r.bottom]]),
        );
      } finally {
        img.dispose();
      }
      await db.savePanels(row);
    }
    return PageBubbles(
      width: row.width,
      height: row.height,
      bubbles: const [],
      panels: [
        for (final r in (jsonDecode(row.panels) as List).cast<List>())
          ui.Rect.fromLTRB(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble()),
      ],
    );
  }

  /// Persists [pb]'s current order: a small bubble_orders.json beside the download
  /// (offline rereads keep it), then the server, else the sync queue. Serialised so
  /// quick swaps land in order; one failure never blocks later saves.
  Future<void> saveOrder(String comicId, int page, PageBubbles pb) {
    final labels = pb.labels;
    final next = _saving.then((_) async {
      try {
        await _writeOrder(page, labels);
      } catch (_) {}
      try {
        await client.putBubbleOrder(comicId, page, labels);
      } on ApiException catch (e) {
        if (e.statusCode >= 500) await _enqueue(comicId, page, labels);
        // 4xx: the sidecar changed under us; this order can never apply.
      } catch (_) {
        await _enqueue(comicId, page, labels);
      }
    });
    _saving = next.catchError((_) {});
    return next;
  }

  Future<void> _enqueue(String comicId, int page, List<int> labels) async =>
      queue?.enqueue({
        'type': 'bubble_order',
        'payload': {'comic_id': comicId, 'page': page, 'labels': labels},
      });

  File? _file(String name) =>
      _localDir == null ? null : File(p.join(_localDir!, name));

  /// The downloaded sidecars, decoded off the UI isolate (a 1,500-page book is ~23 MB).
  Future<Map<String, dynamic>?> _readLocal() async {
    final f = _file('bubbles.json');
    if (f == null || !await f.exists()) return null;
    try {
      final root =
          await compute(_decode, await f.readAsString())
              as Map<String, dynamic>;
      return root['pages'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _readOrders() async {
    if (_localOrders != null) return _localOrders!;
    final f = _file('bubble_orders.json');
    try {
      if (f != null && await f.exists()) {
        return _localOrders =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return _localOrders = {};
  }

  Future<void> _writeOrder(int page, List<int> labels) async {
    final f = _file('bubble_orders.json');
    if (f == null) return;
    final orders = await _readOrders();
    orders['$page'] = labels;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(orders), flush: true);
    await tmp.rename(f.path);
  }
}
