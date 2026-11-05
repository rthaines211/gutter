import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/creator.dart';
import 'package:comic_reader_app/models/creator_profile.dart';
import 'package:comic_reader_app/config/creator_roles.dart';

void main() {
  group('Creator.fromJson id', () {
    test('defaults id to 0 when missing', () {
      final c = Creator.fromJson({'name': 'A', 'role': 'writer'});
      expect(c.id, 0);
    });

    test('round-trips id through toJson', () {
      const c = Creator(id: 40724, name: 'Tom King', role: 'writer');
      final json = c.toJson();
      expect(json['id'], 40724);
      expect(Creator.fromJson(json).id, 40724);
    });
  });

  group('roleGroup', () {
    test('writer maps to writer', () {
      expect(roleGroup('writer'), CreatorRoleGroup.writer);
    });

    test('penciller maps to art', () {
      expect(roleGroup('penciller'), CreatorRoleGroup.art);
    });

    test('penciler, inker, colorist, artist map to art', () {
      expect(roleGroup('penciler'), CreatorRoleGroup.art);
      expect(roleGroup('inker'), CreatorRoleGroup.art);
      expect(roleGroup('colorist'), CreatorRoleGroup.art);
      expect(roleGroup('artist'), CreatorRoleGroup.art);
    });

    test('cover maps to covers', () {
      expect(roleGroup('cover'), CreatorRoleGroup.covers);
    });

    test('letterer and unknown roles map to null', () {
      expect(roleGroup('letterer'), isNull);
      expect(roleGroup('editor'), isNull);
    });

    test('lowercases and trims before mapping', () {
      expect(roleGroup('  Writer  '), CreatorRoleGroup.writer);
      expect(roleGroup('PENCILLER'), CreatorRoleGroup.art);
    });
  });

  group('CreatorSummary', () {
    test('fromJson parses fields', () {
      final s = CreatorSummary.fromJson({
        'id': 40724,
        'name': 'Tom King',
        'roles': ['writer'],
        'seriesIds': ['s1', 's2'],
      });
      expect(s.id, 40724);
      expect(s.name, 'Tom King');
      expect(s.roles, ['writer']);
      expect(s.seriesIds, ['s1', 's2']);
    });
  });

  group('CreatorProfile.fromJson', () {
    Map<String, dynamic> baseJson({dynamic bibliography, bool pending = false}) => {
          'id': 40724,
          'name': 'Tom King',
          'roles': ['writer'],
          'seriesIds': ['s1'],
          'volumesOwned': 1,
          'volumesTotal': 2,
          'bibliography': bibliography,
          'bibliographyPending': pending,
        };

    test('bibliography null stays null', () {
      final p = CreatorProfile.fromJson(baseJson(bibliography: null));
      expect(p.bibliography, isNull);
      expect(p.bibliographyPending, false);
    });

    test('bibliographyPending true parses', () {
      final p = CreatorProfile.fromJson(baseJson(bibliography: null, pending: true));
      expect(p.bibliographyPending, true);
    });

    test('one volume with partial ownership parses owned == partial', () {
      final p = CreatorProfile.fromJson(baseJson(bibliography: [
        {
          'volumeId': 9,
          'name': 'Batman',
          'startYear': 2016,
          'publisher': 'DC',
          'coverUrl': 'http://x/c.jpg',
          'roles': ['writer'],
          'personIssues': 12,
          'totalIssues': 24,
          'ownedIssues': 5,
          'owned': 'partial',
          'seriesId': 's1',
        }
      ]));
      expect(p.bibliography, isNotNull);
      expect(p.bibliography!.single.owned, OwnedState.partial);
      expect(p.bibliography!.single.seriesId, 's1');
      expect(p.bibliography!.single.volumeId, 9);
    });

    test('seriesId omitted parses to null', () {
      final p = CreatorProfile.fromJson(baseJson(bibliography: [
        {
          'volumeId': 9,
          'name': 'Batman',
          'startYear': 2016,
          'publisher': 'DC',
          'coverUrl': '',
          'roles': ['writer'],
          'personIssues': 12,
          'totalIssues': 24,
          'ownedIssues': 0,
          'owned': 'none',
        }
      ]));
      expect(p.bibliography!.single.seriesId, isNull);
      expect(p.bibliography!.single.owned, OwnedState.none);
    });
  });

  group('VolumeInfo.fromJson', () {
    test('parses description', () {
      final v = VolumeInfo.fromJson({
        'volumeId': 9,
        'name': 'Batman',
        'startYear': 2016,
        'publisher': 'DC',
        'coverUrl': 'http://x/c.jpg',
        'totalIssues': 24,
        'description': 'The Dark Knight.',
      });
      expect(v.description, 'The Dark Knight.');
      expect(v.totalIssues, 24);
    });
  });

  group('PersonMatch.fromJson', () {
    test('parses fields', () {
      final m = PersonMatch.fromJson({'id': 1, 'name': 'Tom King', 'volumes': 3});
      expect(m.id, 1);
      expect(m.name, 'Tom King');
      expect(m.volumes, 3);
    });
  });
}
