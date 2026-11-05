import 'creator.dart';

/// An issue credit is just a [Creator] (name + role) attached to one comic.
typedef IssueCredit = Creator;

int _intOf(dynamic json, String key, [int fallback = 0]) =>
    (json[key] as num?)?.toInt() ?? fallback;

String _stringOf(dynamic json, String key, [String fallback = '']) =>
    json[key] as String? ?? fallback;

List<String> _stringListOf(dynamic json, String key) =>
    (json[key] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList();

/// One entry from `GET /creators` — a creator plus the series they touch.
class CreatorSummary {
  final int id;
  final String name;
  final List<String> roles;
  final List<String> seriesIds;

  const CreatorSummary({
    required this.id,
    required this.name,
    required this.roles,
    required this.seriesIds,
  });

  factory CreatorSummary.fromJson(Map<String, dynamic> json) => CreatorSummary(
        id: _intOf(json, 'id'),
        name: _stringOf(json, 'name'),
        roles: _stringListOf(json, 'roles'),
        seriesIds: _stringListOf(json, 'seriesIds'),
      );
}

/// Whether the signed-in library owns issues from a bibliography volume.
enum OwnedState { owned, partial, none }

OwnedState _ownedStateOf(String raw) {
  switch (raw) {
    case 'owned':
      return OwnedState.owned;
    case 'partial':
      return OwnedState.partial;
    default:
      return OwnedState.none;
  }
}

/// One volume in a creator's bibliography (`GET /creators/{id}`), with
/// ownership computed against the local library. v1 is direct ownership
/// only — there is no "owned via trade/omnibus" field.
class BibliographyVolume {
  final int volumeId;
  final String name;
  final int startYear;
  final String publisher;
  final String coverUrl;
  final List<String> roles;
  final int personIssues;
  final int totalIssues;
  final int ownedIssues;
  final OwnedState owned;
  final String? seriesId;

  const BibliographyVolume({
    required this.volumeId,
    required this.name,
    required this.startYear,
    required this.publisher,
    required this.coverUrl,
    required this.roles,
    required this.personIssues,
    required this.totalIssues,
    required this.ownedIssues,
    required this.owned,
    this.seriesId,
  });

  factory BibliographyVolume.fromJson(Map<String, dynamic> json) => BibliographyVolume(
        volumeId: _intOf(json, 'volumeId'),
        name: _stringOf(json, 'name'),
        startYear: _intOf(json, 'startYear'),
        publisher: _stringOf(json, 'publisher'),
        coverUrl: _stringOf(json, 'coverUrl'),
        roles: _stringListOf(json, 'roles'),
        personIssues: _intOf(json, 'personIssues'),
        totalIssues: _intOf(json, 'totalIssues'),
        ownedIssues: _intOf(json, 'ownedIssues'),
        owned: _ownedStateOf(_stringOf(json, 'owned')),
        seriesId: json['seriesId'] as String?,
      );
}

/// Full creator profile from `GET /creators/{personId}`.
class CreatorProfile {
  final int id;
  final String name;
  final List<String> roles;
  final List<String> seriesIds;
  final int volumesOwned;
  final int volumesTotal;
  final List<BibliographyVolume>? bibliography;
  final bool bibliographyPending;

  const CreatorProfile({
    required this.id,
    required this.name,
    required this.roles,
    required this.seriesIds,
    required this.volumesOwned,
    required this.volumesTotal,
    required this.bibliography,
    required this.bibliographyPending,
  });

  factory CreatorProfile.fromJson(Map<String, dynamic> json) {
    final rawBibliography = json['bibliography'] as List<dynamic>?;
    return CreatorProfile(
      id: _intOf(json, 'id'),
      name: _stringOf(json, 'name'),
      roles: _stringListOf(json, 'roles'),
      seriesIds: _stringListOf(json, 'seriesIds'),
      volumesOwned: _intOf(json, 'volumesOwned'),
      volumesTotal: _intOf(json, 'volumesTotal'),
      bibliography: rawBibliography
          ?.map((e) => BibliographyVolume.fromJson(e as Map<String, dynamic>))
          .toList(),
      bibliographyPending: json['bibliographyPending'] as bool? ?? false,
    );
  }
}

/// `GET /creators/volumes/{id}` — volume metadata plus description, used
/// when a bibliography volume has no local series (not owned).
class VolumeInfo {
  final int volumeId;
  final String name;
  final int startYear;
  final String publisher;
  final String coverUrl;
  final int totalIssues;
  final String description;

  const VolumeInfo({
    required this.volumeId,
    required this.name,
    required this.startYear,
    required this.publisher,
    required this.coverUrl,
    required this.totalIssues,
    required this.description,
  });

  factory VolumeInfo.fromJson(Map<String, dynamic> json) => VolumeInfo(
        volumeId: _intOf(json, 'volumeId'),
        name: _stringOf(json, 'name'),
        startYear: _intOf(json, 'startYear'),
        publisher: _stringOf(json, 'publisher'),
        coverUrl: _stringOf(json, 'coverUrl'),
        totalIssues: _intOf(json, 'totalIssues'),
        description: _stringOf(json, 'description'),
      );
}

/// One name match from `GET /creators/lookup?name=`.
class PersonMatch {
  final int id;
  final String name;
  final int volumes;

  const PersonMatch({required this.id, required this.name, required this.volumes});

  factory PersonMatch.fromJson(Map<String, dynamic> json) => PersonMatch(
        id: _intOf(json, 'id'),
        name: _stringOf(json, 'name'),
        volumes: _intOf(json, 'volumes'),
      );
}
