class SyncResponse {
  final int serverTime;
  final List<Map<String, dynamic>> series;
  final List<Map<String, dynamic>> progress;
  final List<String> seriesIds;
  final List<String> progressIds;
  final List<Map<String, dynamic>> queues;
  final List<String> queueIds;
  final List<Map<String, dynamic>> arcs;
  final List<String> arcIds;

  const SyncResponse({
    required this.serverTime,
    required this.series,
    required this.progress,
    required this.seriesIds,
    required this.progressIds,
    this.queues = const [],
    this.queueIds = const [],
    this.arcs = const [],
    this.arcIds = const [],
  });

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    return SyncResponse(
      serverTime: json['server_time'] as int? ?? 0,
      series: (json['series'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>(),
      progress: (json['progress'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>(),
      seriesIds: (json['series_ids'] as List<dynamic>? ?? []).cast<String>(),
      progressIds: (json['progress_ids'] as List<dynamic>? ?? [])
          .cast<String>(),
      queues: (json['queues'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>(),
      queueIds: (json['queue_ids'] as List<dynamic>? ?? []).cast<String>(),
      arcs: (json['arcs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      arcIds: (json['arc_ids'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}
