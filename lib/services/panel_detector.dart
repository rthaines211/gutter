import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// On-device panel detection for sources without server sidecars (Komga): the
/// bundled YOLOX-S Core ML model (Apache-2.0, `ios/Runner/PanelDetector.mlpackage`)
/// behind the `app.comic_reader/panels` channel, then the cutoff, NMS and
/// reading order the server's `panel_order.py` gives its sidecars.

/// Bump when the bundled model or the rules below change, so cached boxes redo.
const panelModel = 'yolox-s-2';

const panelInput = 640; // the model's square input
const panelCutoff = 0.4; // panel score (objectness x class) a box needs
const _nmsIou = 0.45;
const _sameRow = 0.25; // boxes overlapping vertically by this much of the shorter one share a row

const _channel = MethodChannel('app.comic_reader/panels');

/// [image]'s panels in reading order, in page pixels; null when the model can't
/// run here (not iOS, or it failed to load).
Future<List<ui.Rect>?> detectPanels(ui.Image image) async {
  final input = await letterbox(image);
  final Float32List? raw;
  try {
    raw = await _channel.invokeMethod<Float32List>('detect', input);
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    debugPrint('panels: detect failed: $e');
    return null;
  }
  if (raw == null) return null;
  return panelsFromRaw(raw, width: image.width, height: image.height);
}

/// [image] scaled to fit [panelInput] square and pinned top-left on grey 114,
/// as RGBA bytes: the letterbox the model was trained on.
Future<Uint8List> letterbox(ui.Image image) async {
  final r = panelInput / math.max(image.width, image.height);
  final rec = ui.PictureRecorder();
  ui.Canvas(rec)
    ..drawColor(const ui.Color(0xFF727272), ui.BlendMode.src)
    ..drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, image.width * r, image.height * r),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  final boxed = await rec.endRecording().toImage(panelInput, panelInput);
  try {
    return (await boxed.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  } finally {
    boxed.dispose();
  }
}

/// The model's raw rows (cx, cy, w, h, objectness, panel score in input pixels)
/// to panels in reading order: score cutoff, NMS, scaled to the page and kept
/// inside it.
List<ui.Rect> panelsFromRaw(
  Float32List raw, {
  required int width,
  required int height,
  double cutoff = panelCutoff,
  bool fold = false,
}) {
  final r = panelInput / math.max(width, height);
  final found = <(double, ui.Rect)>[];
  for (var i = 0; i + 5 < raw.length; i += 6) {
    final score = raw[i + 4] * raw[i + 5];
    if (score < cutoff) continue;
    final cx = raw[i] / r, cy = raw[i + 1] / r, w = raw[i + 2] / r, h = raw[i + 3] / r;
    found.add((score, ui.Rect.fromLTRB(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)));
  }
  found.sort((a, b) => b.$1.compareTo(a.$1));
  final kept = <ui.Rect>[];
  for (final (_, box) in found) {
    if (kept.every((k) => _iou(k, box) <= _nmsIou)) kept.add(box);
  }
  final page = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  return orderPanels([for (final k in kept) k.intersect(page)], width: width, height: height, fold: fold);
}

/// `panel_order.ordered_panels`: insets folded into their host ([fold]), then
/// reading order, a spread's left page before its right.
List<ui.Rect> orderPanels(List<ui.Rect> panels, {required int width, required int height, bool fold = false}) {
  var p = panels;
  if (fold) {
    p = [
      for (final a in p)
        if (!p.any((q) => _area(q) > _area(a) && _inter(a, q) > 0.8 * _area(a))) a,
    ];
  }
  if (width <= height) return _order(p);
  bool onLeft(ui.Rect a) => a.left + a.right < width;
  return [..._order(p.where(onLeft).toList()), ..._order(p.where((a) => !onLeft(a)).toList())];
}

/// True if [a] reads before [b]: left first when side by side, else upper first.
/// Nested or heavily overlapping boxes get no call and fall to the tie-break.
bool _before(ui.Rect a, ui.Rect b) {
  final h = math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left)) / math.max(1.0, math.min(a.width, b.width));
  final v = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top)) / math.max(1.0, math.min(a.height, b.height));
  if (v >= _sameRow && h < _sameRow) return a.left + a.right < b.left + b.right;
  if (v < _sameRow) return a.top + a.bottom < b.top + b.bottom;
  return false;
}

/// Everything a box must follow comes first; ties go top then left, and a cycle
/// (a staggered row) takes the box waiting on fewest others, then the leftmost.
/// ponytail: O(n^2) pairs, fine for the dozen panels a page has.
List<ui.Rect> _order(List<ui.Rect> boxes) {
  final n = boxes.length;
  final after = [
    for (var i = 0; i < n; i++) {for (var j = 0; j < n; j++) if (j != i && _before(boxes[j], boxes[i])) j},
  ];
  final done = <int>{}, out = <ui.Rect>[];
  while (out.length < n) {
    final left = [for (var i = 0; i < n; i++) if (!done.contains(i)) i];
    final ready = left.where((i) => done.containsAll(after[i])).toList();
    int? pick;
    if (ready.isNotEmpty) {
      for (final i in ready) {
        final a = boxes[i], b = pick == null ? null : boxes[pick];
        if (b == null || a.top < b.top || (a.top == b.top && a.left < b.left)) pick = i;
      }
    } else {
      int waits(int i) => after[i].difference(done).length;
      for (final i in left) {
        if (pick == null || waits(i) < waits(pick) || (waits(i) == waits(pick) && boxes[i].left < boxes[pick].left)) pick = i;
      }
    }
    done.add(pick!);
    out.add(boxes[pick]);
  }
  return out;
}

double _area(ui.Rect a) => a.width * a.height;

double _inter(ui.Rect a, ui.Rect b) =>
    math.max(0.0, math.min(a.right, b.right) - math.max(a.left, b.left)) *
    math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));

double _iou(ui.Rect a, ui.Rect b) {
  final i = _inter(a, b), u = _area(a) + _area(b) - i;
  return u > 0 ? i / u : 0;
}
