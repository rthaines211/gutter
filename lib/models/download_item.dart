enum DownloadStatus { queued, downloading, completed, failed }

class DownloadItem {
  final String comicId;
  final String sourceId;
  final String seriesId;
  final String seriesName;
  final String comicName;
  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;
  final DateTime addedAt;
  final String? error;

  const DownloadItem({
    required this.comicId,
    required this.sourceId,
    required this.seriesId,
    required this.seriesName,
    required this.comicName,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.status,
    required this.addedAt,
    this.error,
  });

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

  String get formattedSize {
    final mb = totalBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  DownloadItem copyWith({
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    String? error,
  }) {
    return DownloadItem(
      comicId: comicId,
      sourceId: sourceId,
      seriesId: seriesId,
      seriesName: seriesName,
      comicName: comicName,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      addedAt: addedAt,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
        'comic_id': comicId,
        'source_id': sourceId,
        'series_id': seriesId,
        'series_name': seriesName,
        'comic_name': comicName,
        'total_bytes': totalBytes,
        'downloaded_bytes': downloadedBytes,
        'status': status.name,
        'added_at': addedAt.toIso8601String(),
        if (error != null) 'error': error,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      comicId: json['comic_id'] as String,
      sourceId: json['source_id'] as String,
      seriesId: json['series_id'] as String? ?? '',
      seriesName: json['series_name'] as String? ?? '',
      comicName: json['comic_name'] as String? ?? '',
      totalBytes: json['total_bytes'] as int? ?? 0,
      downloadedBytes: json['downloaded_bytes'] as int? ?? 0,
      // Unknown names (e.g. 'extracting' from older journals) restore as queued.
      status: DownloadStatus.values.asNameMap()[json['status']] ??
          DownloadStatus.queued,
      addedAt: DateTime.parse(json['added_at'] as String),
      error: json['error'] as String?,
    );
  }
}
