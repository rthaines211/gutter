class ScanStatus {
  final bool isScanning;
  final int scanned;
  final int total;
  final int newCount;
  final int removedCount;
  final DateTime? startedAt;
  final int durationMs;
  final DateTime? lastScanAt;
  final bool pipelineRunning;

  const ScanStatus({
    this.isScanning = false,
    this.scanned = 0,
    this.total = 0,
    this.newCount = 0,
    this.removedCount = 0,
    this.startedAt,
    this.durationMs = 0,
    this.lastScanAt,
    this.pipelineRunning = false,
  });

  factory ScanStatus.fromJson(Map<String, dynamic> json) {
    return ScanStatus(
      isScanning: json['is_scanning'] as bool? ?? false,
      scanned: json['scanned'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      newCount: json['new_count'] as int? ?? 0,
      removedCount: json['removed_count'] as int? ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String)
          : null,
      durationMs: json['duration_ms'] as int? ?? 0,
      lastScanAt: json['last_scan_at'] != null
          ? DateTime.tryParse(json['last_scan_at'] as String)
          : null,
      pipelineRunning: json['pipeline_running'] as bool? ?? false,
    );
  }

  bool get isBusy => isScanning || pipelineRunning;

  double get progress => total > 0 ? scanned / total : 0;
}
