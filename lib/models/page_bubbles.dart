import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

/// One balloon from a bubble-zoom sidecar. [rect] is in original page pixels;
/// [label] is its pixel value in the mask, independent of reading order.
class Bubble {
  final Rect rect;
  final int label;
  const Bubble(this.rect, this.label);

  factory Bubble.fromJson(Map<String, dynamic> json) {
    final r = (json['r'] as List).cast<num>();
    return Bubble(
      Rect.fromLTWH(
        r[0].toDouble(),
        r[1].toDouble(),
        r[2].toDouble(),
        r[3].toDouble(),
      ),
      json['label'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'r': [
      rect.left.round(),
      rect.top.round(),
      rect.width.round(),
      rect.height.round(),
    ],
    'label': label,
  };
}

/// A page's sidecar (spec Part 2). [bubbles] is the current reading order and is
/// changed in place by [swapWithNext]. [panels] are the page's panels in reading
/// order, LTRB in page pixels, for panel zoom.
class PageBubbles {
  final int width;
  final int height;
  final List<Bubble> bubbles;

  /// Label PNG: 8-bit grey, 1000 px wide, pixel value = [Bubble.label]. Null when
  /// the page has no balloons.
  final Uint8List? mask;

  final List<Rect> panels;

  PageBubbles({
    required this.width,
    required this.height,
    required this.bubbles,
    this.mask,
    this.panels = const [],
  });

  factory PageBubbles.fromJson(Map<String, dynamic> json) => PageBubbles(
    width: json['w'] as int,
    height: json['h'] as int,
    bubbles: ((json['bubbles'] as List?) ?? const [])
        .map((e) => Bubble.fromJson(e as Map<String, dynamic>))
        .toList(),
    mask: json['mask'] == null ? null : base64Decode(json['mask'] as String),
    panels: [
      for (final p in (json['panels'] as List?) ?? const [])
        if (p is List && p.length == 4 && p.every((v) => v is num))
          Rect.fromLTRB(
            (p[0] as num).toDouble(),
            (p[1] as num).toDouble(),
            (p[2] as num).toDouble(),
            (p[3] as num).toDouble(),
          ),
    ],
  );

  List<int> get labels => [for (final b in bubbles) b.label];

  /// Reorders [bubbles] to follow [labels]; ignored unless it is a permutation of them.
  void applyOrder(List<int> labels) {
    if (labels.length != bubbles.length || !labels.toSet().containsAll(this.labels)) return;
    final byLabel = {for (final b in bubbles) b.label: b};
    bubbles.setAll(0, [for (final l in labels) byLabel[l]!]);
  }

  /// "Not yet": balloon [i] trades places with balloon [i + 1].
  bool swapWithNext(int i) {
    if (i < 0 || i + 1 >= bubbles.length) return false;
    final b = bubbles[i];
    bubbles[i] = bubbles[i + 1];
    bubbles[i + 1] = b;
    return true;
  }
}
