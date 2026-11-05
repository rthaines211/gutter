import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/remote_control_listener.dart';

void main() {
  late StreamController<Map<String, dynamic>> commands;
  late List<String> fired;
  late int gotoPage;

  Widget build({bool enabled = true}) {
    fired = [];
    gotoPage = -1;
    return MaterialApp(
      home: RemoteControlListener(
        enabled: enabled,
        commands: commands.stream,
        onNext: () => fired.add('next'),
        onPrev: () => fired.add('prev'),
        onBookmark: () => fired.add('bookmark'),
        onNextIssue: () => fired.add('nextIssue'),
        onGoto: (p) {
          fired.add('goto');
          gotoPage = p;
        },
        child: const SizedBox(),
      ),
    );
  }

  setUp(() => commands = StreamController<Map<String, dynamic>>.broadcast());
  tearDown(() => commands.close());

  testWidgets('routes each command type to its callback', (tester) async {
    await tester.pumpWidget(build());
    for (final t in ['next', 'prev', 'bookmark', 'nextIssue']) {
      commands.add({'type': t});
    }
    await tester.pump();
    expect(fired, ['next', 'prev', 'bookmark', 'nextIssue']);
  });

  testWidgets('goto passes the page through', (tester) async {
    await tester.pumpWidget(build());
    commands.add({'type': 'goto', 'page': 11});
    await tester.pump();
    expect(fired, ['goto']);
    expect(gotoPage, 11);
  });

  testWidgets('ignores unknown command types', (tester) async {
    await tester.pumpWidget(build());
    commands.add({'type': 'selfdestruct'});
    await tester.pump();
    expect(fired, isEmpty);
  });

  testWidgets('fires nothing when disabled', (tester) async {
    await tester.pumpWidget(build(enabled: false));
    commands.add({'type': 'next'});
    await tester.pump();
    expect(fired, isEmpty);
  });

  testWidgets('unsubscribes on dispose', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    commands.add({'type': 'next'});
    await tester.pump();
    expect(fired, isEmpty);
    expect(commands.hasListener, isFalse);
  });

  testWidgets('goto with double does not throw and stream survives', (tester) async {
    await tester.pumpWidget(build());
    commands.add({'type': 'goto', 'page': 11.0});
    commands.add({'type': 'next'}); // subsequent command
    await tester.pump();
    expect(fired, ['goto', 'next']); // goto called with fallback, then next
    expect(gotoPage, 0); // double cast to int fallback
  });

  testWidgets('goto with non-numeric page does not throw and stream survives',
      (tester) async {
    await tester.pumpWidget(build());
    commands.add({'type': 'goto', 'page': 'not a number'});
    commands.add({'type': 'prev'}); // subsequent command
    await tester.pump();
    expect(fired, ['goto', 'prev']); // goto called with fallback, then prev
    expect(gotoPage, 0); // non-numeric cast to int fallback
  });

  testWidgets('rebuilds with new stream and loses old listener', (tester) async {
    await tester.pumpWidget(build());
    expect(commands.hasListener, isTrue);

    final newCommands = StreamController<Map<String, dynamic>>.broadcast();
    try {
      // Rebuild with new stream
      fired = [];
      await tester.pumpWidget(MaterialApp(
        home: RemoteControlListener(
          commands: newCommands.stream,
          onNext: () => fired.add('next'),
          onPrev: () => fired.add('prev'),
          onBookmark: () => fired.add('bookmark'),
          onNextIssue: () => fired.add('nextIssue'),
          onGoto: (p) => fired.add('goto'),
          child: const SizedBox(),
        ),
      ));

      // Old stream loses listener, new stream has one
      expect(commands.hasListener, isFalse);
      expect(newCommands.hasListener, isTrue);

      // Commands on old stream don't fire
      commands.add({'type': 'next'});
      await tester.pump();
      expect(fired, isEmpty);

      // Commands on new stream do fire
      newCommands.add({'type': 'next'});
      await tester.pump();
      expect(fired, ['next']);
    } finally {
      newCommands.close();
    }
  });

  testWidgets('enabled false→true resubscribes', (tester) async {
    late StreamController<Map<String, dynamic>> stream;
    stream = StreamController<Map<String, dynamic>>.broadcast();

    try {
      // Build disabled
      fired = [];
      await tester.pumpWidget(MaterialApp(
        home: RemoteControlListener(
          enabled: false,
          commands: stream.stream,
          onNext: () => fired.add('next'),
          onPrev: () => fired.add('prev'),
          onBookmark: () => fired.add('bookmark'),
          onNextIssue: () => fired.add('nextIssue'),
          onGoto: (p) => fired.add('goto'),
          child: const SizedBox(),
        ),
      ));

      expect(stream.hasListener, isFalse);
      stream.add({'type': 'next'});
      await tester.pump();
      expect(fired, isEmpty);

      // Rebuild enabled
      fired = [];
      await tester.pumpWidget(MaterialApp(
        home: RemoteControlListener(
          enabled: true,
          commands: stream.stream,
          onNext: () => fired.add('next'),
          onPrev: () => fired.add('prev'),
          onBookmark: () => fired.add('bookmark'),
          onNextIssue: () => fired.add('nextIssue'),
          onGoto: (p) => fired.add('goto'),
          child: const SizedBox(),
        ),
      ));

      expect(stream.hasListener, isTrue);
      stream.add({'type': 'next'});
      await tester.pump();
      expect(fired, ['next']);
    } finally {
      stream.close();
    }
  });

  testWidgets('enabled true→false unsubscribes', (tester) async {
    late StreamController<Map<String, dynamic>> stream;
    stream = StreamController<Map<String, dynamic>>.broadcast();

    try {
      // Build enabled
      fired = [];
      await tester.pumpWidget(MaterialApp(
        home: RemoteControlListener(
          enabled: true,
          commands: stream.stream,
          onNext: () => fired.add('next'),
          onPrev: () => fired.add('prev'),
          onBookmark: () => fired.add('bookmark'),
          onNextIssue: () => fired.add('nextIssue'),
          onGoto: (p) => fired.add('goto'),
          child: const SizedBox(),
        ),
      ));

      expect(stream.hasListener, isTrue);
      stream.add({'type': 'next'});
      await tester.pump();
      expect(fired, ['next']);

      // Rebuild disabled
      fired = [];
      await tester.pumpWidget(MaterialApp(
        home: RemoteControlListener(
          enabled: false,
          commands: stream.stream,
          onNext: () => fired.add('next'),
          onPrev: () => fired.add('prev'),
          onBookmark: () => fired.add('bookmark'),
          onNextIssue: () => fired.add('nextIssue'),
          onGoto: (p) => fired.add('goto'),
          child: const SizedBox(),
        ),
      ));

      expect(stream.hasListener, isFalse);
      stream.add({'type': 'next'});
      await tester.pump();
      expect(fired, isEmpty);
    } finally {
      stream.close();
    }
  });
}
