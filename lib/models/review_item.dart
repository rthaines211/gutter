class ReviewItem {
  final String seriesId;
  final String name;
  final String state;
  final String localCoverUrl;
  final String guessVolumeId;
  final String guessSource;
  final String guessName;
  final String guessPublisher;
  final String guessYear;
  final int guessIssueCount;
  final String guessCoverUrl;

  const ReviewItem({
    required this.seriesId,
    required this.name,
    required this.state,
    required this.localCoverUrl,
    required this.guessVolumeId,
    required this.guessSource,
    required this.guessName,
    required this.guessPublisher,
    required this.guessYear,
    required this.guessIssueCount,
    required this.guessCoverUrl,
  });

  bool get hasGuess => guessVolumeId.isNotEmpty;
  bool get isCollection => state == 'collection';

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        seriesId: j['series_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        state: j['state'] as String? ?? '',
        localCoverUrl: j['local_cover_url'] as String? ?? '',
        guessVolumeId: j['guess_volume_id'] as String? ?? '',
        guessSource: j['guess_source'] as String? ?? '',
        guessName: j['guess_name'] as String? ?? '',
        guessPublisher: j['guess_publisher'] as String? ?? '',
        guessYear: j['guess_year'] as String? ?? '',
        guessIssueCount: (j['guess_issue_count'] as num?)?.toInt() ?? 0,
        guessCoverUrl: j['guess_cover_url'] as String? ?? '',
      );
}

class VolumeHit {
  final String source;
  final String volumeId;
  final String name;
  final String year;
  final String publisher;
  final int issueCount;
  final String coverUrl;

  const VolumeHit({
    required this.source,
    required this.volumeId,
    required this.name,
    required this.year,
    required this.publisher,
    required this.issueCount,
    required this.coverUrl,
  });

  factory VolumeHit.fromJson(Map<String, dynamic> j) => VolumeHit(
        source: j['source'] as String? ?? '',
        volumeId: j['volume_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        year: j['year'] as String? ?? '',
        publisher: j['publisher'] as String? ?? '',
        issueCount: (j['issue_count'] as num?)?.toInt() ?? 0,
        coverUrl: j['cover_url'] as String? ?? '',
      );
}
