// test/services/label_editor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/label_editor.dart';

LabelEditor _editor({
  LabelMode mode = LabelMode.panels,
  List<Box>? prefillBoxes,
  List<String>? prefillKinds,
  ({List<Box> boxes, List<String> kinds, List<int> order, String note})?
      saved,
}) {
  final boxes = prefillBoxes ?? [];
  return LabelEditor(
    mode: mode,
    prefillBoxes: boxes,
    prefillKinds: prefillKinds ?? boxes.map((_) => 'balloon').toList(),
    saved: saved,
  );
}

void main() {
  group('construction', () {
    test('saved label wins over prefill; missing order means not fresh', () {
      final prefill = [
        [0.0, 0.0, 0.5, 0.5],
      ];
      final saved = (
        boxes: [
          [0.1, 0.1, 0.6, 0.6],
        ],
        kinds: ['balloon'],
        order: <int>[],
        note: 'hi',
      );
      final e = _editor(prefillBoxes: prefill, saved: saved);

      expect(e.boxes, saved.boxes);
      expect(e.note, 'hi');
      expect(e.orderFresh, false);
      expect(e.needsNumbering, true);
      expect(e.canSave, false);
    });

    test('saved order matching box count is trusted as fresh', () {
      final boxes = [
        [0.0, 0.0, 0.5, 0.5],
        [0.5, 0.5, 1.0, 1.0],
      ];
      final saved = (
        boxes: boxes,
        kinds: ['balloon', 'balloon'],
        order: [1, 0],
        note: '',
      );
      final e = _editor(prefillBoxes: [], saved: saved);

      expect(e.orderFresh, true);
      expect(e.canSave, true);
    });
  });

  test('editing a box invalidates order', () {
    final boxes = [
      [0.0, 0.0, 0.5, 0.5],
    ];
    final e = _editor(prefillBoxes: boxes);
    e.setOrder([0], forBoxes: e.boxesKey);
    expect(e.orderFresh, true);
    expect(e.canSave, true);

    e.moveBoxTo(0, [0.1, 0.1, 0.6, 0.6]);

    expect(e.orderFresh, false);
    expect(e.canSave, false);
  });

  test('setOrder for stale boxes is ignored', () {
    final boxes = [
      [0.0, 0.0, 0.5, 0.5],
    ];
    final e = _editor(prefillBoxes: boxes);
    final staleKey = e.boxesKey;
    e.moveBoxTo(0, [0.1, 0.1, 0.6, 0.6]);

    e.setOrder([0], forBoxes: staleKey);

    expect(e.orderFresh, false);
    expect(e.order, isEmpty);
  });

  test('undo reverses add, move, delete, kind, clear in LIFO order', () {
    final e = _editor(mode: LabelMode.balloons, prefillBoxes: []);

    // add box A
    e.addBox([0.0, 0.0, 0.1, 0.1]);
    expect(e.boxes.length, 1);

    // move box A (commitDrag pushes the undo entry)
    final original = e.boxes[0];
    e.moveBoxTo(0, [0.2, 0.2, 0.3, 0.3]);
    e.commitDrag(0, original);
    expect(e.boxes[0], [0.2, 0.2, 0.3, 0.3]);

    // add box B, then delete it
    e.addBox([0.5, 0.5, 0.6, 0.6]);
    e.select(1);
    e.deleteSelected();
    expect(e.boxes.length, 1);

    // kind toggle on box A
    e.select(0);
    e.toggleKind();
    expect(e.kinds[0], 'caption');

    // clear everything
    e.clear();
    expect(e.boxes, isEmpty);

    // LIFO undo: clear -> kind -> delete -> add(B) -> move -> add(A)
    e.undo();
    expect(e.boxes.length, 1, reason: 'undo clear');
    expect(e.kinds[0], 'caption');

    e.undo();
    expect(e.kinds[0], 'balloon', reason: 'undo kind toggle');

    e.undo();
    expect(e.boxes.length, 2, reason: 'undo delete brings box B back');

    e.undo();
    expect(e.boxes.length, 1, reason: 'undo add(B) removes it again');

    e.undo();
    expect(e.boxes[0], original, reason: 'undo move');

    e.undo();
    expect(e.boxes, isEmpty, reason: 'undo add(A) removes the last box');

    expect(e.canUndo, false);
  });

  test('addBox ignores slivers under 0.02', () {
    final e = _editor(prefillBoxes: []);
    e.addBox([0.0, 0.0, 0.01, 0.5]); // too narrow
    e.addBox([0.0, 0.0, 0.5, 0.01]); // too short
    expect(e.boxes, isEmpty);

    e.addBox([0.0, 0.0, 0.021, 0.021]);
    expect(e.boxes.length, 1);
  });

  test('toggleKind is a no-op in panels mode', () {
    final e = _editor(
      mode: LabelMode.panels,
      prefillBoxes: [
        [0.0, 0.0, 0.5, 0.5],
      ],
    );
    e.select(0);
    e.toggleKind();
    expect(e.kinds[0], 'balloon');
    expect(e.canUndo, false);
  });

  test('tapOrder numbers each box once; canSave only when all numbered', () {
    final boxes = [
      [0.0, 0.0, 0.3, 0.3],
      [0.3, 0.3, 0.6, 0.6],
    ];
    final e = _editor(prefillBoxes: boxes);
    e.restartOrder();
    e.toOrderStep();

    e.tapOrder(0);
    expect(e.canSave, false);

    e.tapOrder(0); // already numbered, ignored
    expect(e.order, [0]);

    e.tapOrder(1);
    expect(e.order, [0, 1]);
    expect(e.canSave, true);
  });

  test('markNone gives a saveable empty body', () {
    final e = _editor(
      prefillBoxes: [
        [0.0, 0.0, 0.5, 0.5],
      ],
    );
    e.markNone();

    expect(e.canSave, true);
    expect(e.toSaveBody(w: 10, h: 20), {
      'w': 10,
      'h': 20,
      'note': '',
      'boxes': <List<double>>[],
      'order': <int>[],
    });
  });

  test('toSaveBody trims the note like JS', () {
    final e = _editor(prefillBoxes: []);
    e.note = '  hello  ';
    expect(e.toSaveBody(w: 1, h: 1)['note'], 'hello');
  });

  test(
    'panels saved data with empty kinds is aligned to boxes; '
    'delete and undo both work',
    () {
      final boxes = [
        [0.0, 0.0, 0.5, 0.5],
        [0.5, 0.5, 1.0, 1.0],
      ];
      final saved = (
        boxes: boxes,
        kinds: <String>[], // panels labels never carry kinds
        order: [0, 1],
        note: '',
      );
      final e = _editor(prefillBoxes: [], saved: saved);

      expect(e.kinds, ['balloon', 'balloon']);

      e.select(1);
      e.deleteSelected();
      expect(e.boxes.length, 1);
      expect(e.kinds.length, 1);

      e.undo();
      expect(e.boxes.length, 2);
      expect(e.kinds, ['balloon', 'balloon']);
    },
  );

  test('prefill kinds shorter than prefill boxes is aligned on reset', () {
    final boxes = [
      [0.0, 0.0, 0.5, 0.5],
      [0.5, 0.5, 1.0, 1.0],
    ];
    final e = LabelEditor(
      mode: LabelMode.panels,
      prefillBoxes: boxes,
      prefillKinds: const [], // misaligned prefill, as JS's x.kind||'balloon'
    );
    expect(e.kinds, ['balloon', 'balloon']);

    e.clear();
    e.resetToPrefill();
    expect(e.kinds, ['balloon', 'balloon']);
  });

  test('balloons body carries kinds; panels body does not', () {
    final boxes = [
      [0.123456, 0.2, 0.5, 0.6],
    ];
    final balloons = _editor(
      mode: LabelMode.balloons,
      prefillBoxes: boxes,
      prefillKinds: ['caption'],
    );
    balloons.restartOrder();
    balloons.toOrderStep();
    balloons.tapOrder(0);

    final balloonsBody = balloons.toSaveBody(w: 100, h: 200);
    expect(balloonsBody['kinds'], ['caption']);
    expect(balloonsBody['boxes'], [
      [0.1235, 0.2, 0.5, 0.6],
    ]);

    final panels = _editor(prefillBoxes: boxes);
    panels.restartOrder();
    panels.toOrderStep();
    panels.tapOrder(0);
    final panelsBody = panels.toSaveBody(w: 100, h: 200);
    expect(panelsBody.containsKey('kinds'), false);
  });

  group('hitTest', () {
    test('prefers selected edge, else smallest box', () {
      final host = [0.0, 0.0, 1.0, 1.0];
      final inset = [0.3, 0.3, 0.4, 0.4];
      final boxes = [host, inset];

      // Inside the inset, not near any edge: smallest box wins regardless
      // of selection.
      expect(
        LabelEditor.hitTest(
          boxes,
          0.35,
          0.35,
          selected: -1,
          grabX: 0.01,
          grabY: 0.01,
        ),
        1,
      );

      // Near the host's left edge (x=0), with the host selected: the
      // selected box's own edge wins even though it's not the smallest.
      expect(
        LabelEditor.hitTest(
          boxes,
          0.0,
          0.5,
          selected: 0,
          grabX: 0.02,
          grabY: 0.02,
        ),
        0,
      );

      // Same point, nothing selected: falls back to smallest-under-point
      // (only the host covers the far edge; inset is not under the point).
      expect(
        LabelEditor.hitTest(
          boxes,
          0.0,
          0.5,
          selected: -1,
          grabX: 0.02,
          grabY: 0.02,
        ),
        0,
      );

      // Outside both boxes (with grab margin): no hit.
      expect(
        LabelEditor.hitTest(
          boxes,
          2.0,
          2.0,
          selected: -1,
          grabX: 0.02,
          grabY: 0.02,
        ),
        null,
      );
    });

    test('edgesAt reports which edges are near the hit box', () {
      final boxes = [
        [0.2, 0.2, 0.6, 0.6],
      ];
      final e = LabelEditor.edgesAt(
        boxes,
        0.2,
        0.4,
        selected: -1,
        grabX: 0.02,
        grabY: 0.02,
      );
      expect(e, isNotNull);
      expect(e!.l, true);
      expect(e.r, false);
      expect(e.t, false);
      expect(e.b, false);
    });

    test(
      'skip excludes numbered boxes so a numbered inset lets its '
      'unnumbered host be hit underneath',
      () {
        final host = [0.0, 0.0, 1.0, 1.0];
        final inset = [0.3, 0.3, 0.4, 0.4];
        final boxes = [host, inset];
        final numbered = {1}; // inset already numbered, host is not

        // Without skip: inset (smaller, under the point) wins as usual.
        expect(
          LabelEditor.hitTest(
            boxes,
            0.35,
            0.35,
            selected: -1,
            grabX: 0.01,
            grabY: 0.01,
          ),
          1,
        );

        // With skip excluding already-numbered boxes: falls through to the
        // host underneath instead of no-oping on the numbered inset.
        expect(
          LabelEditor.hitTest(
            boxes,
            0.35,
            0.35,
            selected: -1,
            grabX: 0.01,
            grabY: 0.01,
            skip: numbered.contains,
          ),
          0,
        );

        final e = LabelEditor.edgesAt(
          boxes,
          0.35,
          0.35,
          selected: -1,
          grabX: 0.01,
          grabY: 0.01,
          skip: numbered.contains,
        );
        expect(e, isNotNull);
      },
    );
  });

  group('moved / resized', () {
    test('moved clamps to page', () {
      final orig = [0.1, 0.1, 0.3, 0.3];
      final b = LabelEditor.moved(orig, -1.0, -1.0);
      expect(b[0], closeTo(0.0, 1e-9));
      expect(b[1], closeTo(0.0, 1e-9));
      expect(b[2], closeTo(0.2, 1e-9));
      expect(b[3], closeTo(0.2, 1e-9));

      final b2 = LabelEditor.moved(orig, 1.0, 1.0);
      expect(b2[2], 1.0);
      expect(b2[3], 1.0);
      expect(b2[2] - b2[0], closeTo(0.2, 1e-9));
    });

    test('resized keeps min size', () {
      final orig = [0.2, 0.2, 0.3, 0.3];
      final b = LabelEditor.resized(
        orig,
        (l: true, r: false, t: false, b: false),
        0.5, // drag left edge past the right edge
        0.2,
      );
      expect(b[0], closeTo(0.295, 1e-9));
      expect(b[2], 0.3);
    });
  });
}
