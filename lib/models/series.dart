import 'creator.dart';

class Series {
  final String id;
  final String name;
  final String folderPath;
  final int issueCount;
  final int readCount;
  final String coverUrl;
  final String? writer;
  final String? penciller;
  final String? publisher;
  final List<String> genres;
  final int? year;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  final int? startYear;
  final List<Creator> creators;
  final String? enrichmentStatus;

  const Series({
    required this.id,
    required this.name,
    required this.folderPath,
    required this.issueCount,
    required this.readCount,
    required this.coverUrl,
    this.writer,
    this.penciller,
    this.publisher,
    this.genres = const [],
    this.year,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.startYear,
    this.creators = const [],
    this.enrichmentStatus,
  });

  factory Series.fromJson(Map<String, dynamic> json) {
    return Series(
      id: json['id'] as String,
      name: json['name'] as String,
      folderPath: json['folder_path'] as String? ?? '',
      issueCount: json['issue_count'] as int? ?? 0,
      readCount: json['read_count'] as int? ?? 0,
      coverUrl: json['cover_url'] as String? ?? '',
      writer: json['writer'] as String?,
      penciller: json['penciller'] as String?,
      publisher: json['publisher'] as String?,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      year: json['year'] as int?,
      // Payloads synced before created_at existed lack the field; fall back to
      // updatedAt so ordering is unchanged until each series re-syncs.
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      description: json['description'] as String?,
      startYear: json['start_year'] as int?,
      creators: (json['creators'] as List<dynamic>?)
              ?.map((e) => Creator.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      enrichmentStatus: json['enrichment_status'] as String?,
    );
  }

  /// How long a genuinely-added series is flagged "new" (badge + Just Added
  /// shelf). Pre-existing series carry an epoch `created_at` sentinel from the
  /// backend backfill, so they never fall inside this window.
  static const newWindow = Duration(days: 14);

  bool get isRecentlyAdded => DateTime.now().difference(createdAt) < newWindow;

  int get unreadCount => issueCount - readCount;
  double get progress => issueCount > 0 ? readCount / issueCount : 0.0;
  bool get isCompleted => readCount >= issueCount && issueCount > 0;
  bool get isInProgress => readCount > 0 && readCount < issueCount;
  bool get isUnread => readCount == 0;
}

class SeriesDetail {
  final String id;
  final String name;
  final String folderPath;
  final int issueCount;
  final int readCount;
  final String coverUrl;
  final String? writer;
  final String? penciller;
  final String? publisher;
  final List<String> genres;
  final int? year;
  final List<SeriesIssue> issues;
  final String? description;
  final int? startYear;
  final List<Creator> creators;
  final String? enrichmentStatus;

  const SeriesDetail({
    required this.id,
    required this.name,
    required this.folderPath,
    required this.issueCount,
    required this.readCount,
    required this.coverUrl,
    this.writer,
    this.penciller,
    this.publisher,
    this.genres = const [],
    this.year,
    required this.issues,
    this.description,
    this.startYear,
    this.creators = const [],
    this.enrichmentStatus,
  });

  factory SeriesDetail.fromJson(Map<String, dynamic> json) {
    return SeriesDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      folderPath: json['folder_path'] as String? ?? '',
      issueCount: json['issue_count'] as int? ?? 0,
      readCount: json['read_count'] as int? ?? 0,
      coverUrl: json['cover_url'] as String? ?? '',
      writer: json['writer'] as String?,
      penciller: json['penciller'] as String?,
      publisher: json['publisher'] as String?,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      year: json['year'] as int?,
      issues: (json['issues'] as List<dynamic>? ?? [])
          .map((e) => SeriesIssue.fromJson(e as Map<String, dynamic>))
          .toList(),
      description: json['description'] as String?,
      startYear: json['start_year'] as int?,
      creators: (json['creators'] as List<dynamic>?)
              ?.map((e) => Creator.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      enrichmentStatus: json['enrichment_status'] as String?,
    );
  }

  SeriesIssue? get nextUnread {
    for (final issue in issues) {
      if (issue.status == 'unread' || issue.status == 'in_progress') {
        return issue;
      }
    }
    return null;
  }
}

class SeriesIssue {
  final String id;
  final String name;
  final String? number;
  final String coverUrl;
  final String status;
  final int? currentPage;
  final int? totalPages;
  final String? title;
  final String? summary;
  final String? coverDate;
  final String? format;
  final String? writer;
  final String? penciller;
  final String? writebackStatus;
  final String? writebackError;

  /// Owning series — only set by queries that span series (arc reading order).
  final String? seriesId;
  final String? seriesName;

  const SeriesIssue({
    required this.id,
    required this.name,
    this.number,
    required this.coverUrl,
    required this.status,
    this.currentPage,
    this.totalPages,
    this.title,
    this.summary,
    this.coverDate,
    this.format,
    this.writer,
    this.penciller,
    this.writebackStatus,
    this.writebackError,
    this.seriesId,
    this.seriesName,
  });

  factory SeriesIssue.fromJson(Map<String, dynamic> json) {
    return SeriesIssue(
      id: json['id'] as String,
      name: json['name'] as String,
      number: json['number'] as String?,
      coverUrl: json['cover_url'] as String? ?? '',
      status: json['status'] as String? ?? 'unread',
      currentPage: json['current_page'] as int?,
      totalPages: json['total_pages'] as int?,
      title: json['title'] as String?,
      summary: json['summary'] as String?,
      coverDate: json['cover_date'] as String?,
      format: json['format'] as String?,
      writer: json['writer'] as String?,
      penciller: json['penciller'] as String?,
      writebackStatus: json['writeback_status'] as String?,
      writebackError: json['writeback_error'] as String?,
      seriesId: json['series_id'] as String?,
      seriesName: json['series_name'] as String?,
    );
  }

  String get displayName {
    if (number != null && number!.isNotEmpty) {
      return '#$number';
    }
    // Un-numbered issues (one-shots, OGNs) fall back to the file name;
    // never show the archive extension.
    return name.replaceFirst(RegExp(r'\.(cbz|cbr|cb7|cbt|zip|rar|pdf)$', caseSensitive: false), '');
  }

  /// "#N · Title" when ComicVine issue enrichment provided a title;
  /// null otherwise (callers supply their own un-enriched fallback).
  String? get enrichedDisplayTitle =>
      (title != null && title!.isNotEmpty) ? '$displayName · $title' : null;
}
