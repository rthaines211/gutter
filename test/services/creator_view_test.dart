import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader_app/config/creator_roles.dart';
import 'package:comic_reader_app/models/creator.dart';
import 'package:comic_reader_app/models/creator_profile.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/creator_view.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

Series _series(
  String id, {
  String name = 'Series',
  int issueCount = 10,
  int readCount = 0,
  List<Creator> creators = const [],
  DateTime? createdAt,
}) {
  final at = createdAt ?? DateTime.parse('2026-01-01T00:00:00Z');
  return Series(
    id: id,
    name: name,
    folderPath: '/comics/$id',
    issueCount: issueCount,
    readCount: readCount,
    coverUrl: '/library/$id/cover',
    creators: creators,
    createdAt: at,
    updatedAt: at,
  );
}

MirrorSeries _mirror(
  Series series, {
  DateTime? lastReadAt,
  String? nextUnreadIssueId,
}) =>
    MirrorSeries(
      series: series,
      lastReadAt: lastReadAt,
      nextUnreadIssueId: nextUnreadIssueId,
    );

BibliographyVolume _vol(List<String> roles) => BibliographyVolume(
      volumeId: 1,
      name: 'Vol',
      startYear: 2020,
      publisher: 'DC',
      coverUrl: '',
      roles: roles,
      personIssues: 1,
      totalIssues: 1,
      ownedIssues: 0,
      owned: OwnedState.none,
    );

void main() {
  group('ownedByCreator', () {
    test('matches by ID, ignoring a same-name different-ID creator', () {
      final target = _series('s1',
          creators: [const Creator(id: 1, name: 'Tom King', role: 'writer')]);
      final impostor = _series('s2',
          creators: [const Creator(id: 2, name: 'Tom King', role: 'writer')]);
      final result =
          ownedByCreator([_mirror(target), _mirror(impostor)], id: 1, name: 'Tom King');
      expect(result.map((m) => m.series.id), ['s1']);
    });

    test('matches by case-insensitive name when ID is 0', () {
      final target = _series('s1',
          creators: [const Creator(id: 0, name: 'Tom King', role: 'writer')]);
      final other = _series('s2',
          creators: [const Creator(id: 0, name: 'Scott Snyder', role: 'writer')]);
      final result = ownedByCreator([_mirror(target), _mirror(other)],
          id: 0, name: 'tom king');
      expect(result.map((m) => m.series.id), ['s1']);
    });

    test('matches legacy writer/penciller fields via splitCreators', () {
      final at = DateTime.parse('2026-01-01T00:00:00Z');
      final legacy = Series(
        id: 's3',
        name: 'Legacy',
        folderPath: '/comics/s3',
        issueCount: 1,
        readCount: 0,
        coverUrl: '',
        writer: 'Tom King, Scott Snyder',
        createdAt: at,
        updatedAt: at,
      );
      final result =
          ownedByCreator([_mirror(legacy)], id: 0, name: 'Scott Snyder');
      expect(result.map((m) => m.series.id), ['s3']);
    });
  });

  group('pickSpotlight', () {
    test('prefers the most recent in-progress series over the most-read creator',
        () {
      final writer = const CreatorSummary(
          id: 1, name: 'Tom King', roles: ['writer'], seriesIds: ['s1']);
      final prolific = const CreatorSummary(
          id: 2, name: 'Prolific Hack', roles: ['writer'], seriesIds: ['s2']);

      final inProgress = _series('s1', readCount: 3, issueCount: 10, creators: [
        const Creator(id: 1, name: 'Tom King', role: 'writer'),
      ]);
      final mostRead = _series('s2', readCount: 50, issueCount: 50, creators: [
        const Creator(id: 2, name: 'Prolific Hack', role: 'writer'),
      ]);

      final all = [
        _mirror(inProgress, lastReadAt: DateTime.parse('2026-01-05T00:00:00Z')),
        _mirror(mostRead, lastReadAt: DateTime.parse('2026-01-01T00:00:00Z')),
      ];

      expect(pickSpotlight([writer, prolific], all), writer);
    });

    test('falls back to the art-group creator when no writer is credited', () {
      final artist = const CreatorSummary(
          id: 3, name: 'Jim Lee', roles: ['penciller'], seriesIds: ['s1']);
      final series = _series('s1', readCount: 1, issueCount: 10, creators: [
        const Creator(id: 3, name: 'Jim Lee', role: 'penciller'),
      ]);
      final all = [
        _mirror(series, lastReadAt: DateTime.parse('2026-01-05T00:00:00Z')),
      ];
      expect(pickSpotlight([artist], all), artist);
    });

    test('falls back to the creator with the most issuesRead when nothing is in progress',
        () {
      final low = const CreatorSummary(
          id: 1, name: 'Low', roles: ['writer'], seriesIds: ['s1']);
      final high = const CreatorSummary(
          id: 2, name: 'High', roles: ['writer'], seriesIds: ['s2']);
      final lowSeries = _series('s1', readCount: 2, creators: [
        const Creator(id: 1, name: 'Low', role: 'writer'),
      ]);
      final highSeries = _series('s2', readCount: 9, creators: [
        const Creator(id: 2, name: 'High', role: 'writer'),
      ]);
      final all = [_mirror(lowSeries), _mirror(highSeries)];
      expect(pickSpotlight([low, high], all), high);
    });

    test('returns null with no reading history', () {
      final creator = const CreatorSummary(
          id: 1, name: 'Nobody', roles: ['writer'], seriesIds: ['s1']);
      final series = _series('s1', readCount: 0, creators: [
        const Creator(id: 1, name: 'Nobody', role: 'writer'),
      ]);
      expect(pickSpotlight([creator], [_mirror(series)]), isNull);
    });
  });

  group('defaultGroup', () {
    test('returns covers for 300 cover volumes vs 4 writer volumes', () {
      final vols = [
        ...List.generate(300, (_) => _vol(['cover'])),
        ...List.generate(4, (_) => _vol(['writer'])),
      ];
      expect(defaultGroup(vols), CreatorRoleGroup.covers);
    });

    test('breaks a tie in favor of writer over art and covers', () {
      final vols = [
        _vol(['writer']),
        _vol(['penciller']),
        _vol(['cover']),
      ];
      expect(defaultGroup(vols), CreatorRoleGroup.writer);
    });
  });

  group('issuesRead', () {
    test('sums readCount across owned series', () {
      final owned = [
        _mirror(_series('s1', readCount: 3)),
        _mirror(_series('s2', readCount: 4)),
      ];
      expect(issuesRead(owned), 7);
    });
  });

  group('ownedOnlyProfile', () {
    test('has null bibliography and roles from the owned series', () {
      final owned = [
        _mirror(_series('s1', creators: [
          const Creator(id: 1, name: 'Tom King', role: 'writer'),
        ])),
      ];
      final profile = ownedOnlyProfile(1, 'Tom King', owned);
      expect(profile.bibliography, isNull);
      expect(profile.bibliographyPending, false);
      expect(profile.roles, ['writer']);
      expect(profile.seriesIds, ['s1']);
    });
  });

  group('nextByCreator', () {
    test('prefers the in-progress series, then the newest owned series', () {
      final creator = const CreatorSummary(
          id: 1, name: 'Tom King', roles: ['writer'], seriesIds: ['s1', 's2']);
      final older = _mirror(
        _series('s1',
            creators: [const Creator(id: 1, name: 'Tom King', role: 'writer')],
            createdAt: DateTime.parse('2026-01-01T00:00:00Z')),
        nextUnreadIssueId: 'c-old',
      );
      final inProgress = _mirror(
        _series('s2',
            creators: [const Creator(id: 1, name: 'Tom King', role: 'writer')],
            createdAt: DateTime.parse('2025-01-01T00:00:00Z'),
            readCount: 1,
            issueCount: 5),
        lastReadAt: DateTime.parse('2026-01-05T00:00:00Z'),
        nextUnreadIssueId: 'c-in-progress',
      );
      final result = nextByCreator(creator, [older, inProgress]);
      expect(result, (seriesId: 's2', issueId: 'c-in-progress'));
    });

    test('returns null when nothing is owned', () {
      final creator = const CreatorSummary(
          id: 1, name: 'Nobody', roles: ['writer'], seriesIds: []);
      expect(nextByCreator(creator, []), isNull);
    });
  });
}
