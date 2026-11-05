import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/scheme.dart';
import '../models/series.dart';
import '../providers/download_provider.dart';

/// Before a series download: how many issues, roughly how big, and whether it
/// fits. Returns the issues to queue, or null if cancelled.
Future<List<SeriesIssue>?> showSeriesDownloadSheet(
  BuildContext context, {
  required SeriesDetail detail,
  required String baseUrl,
  required Map<String, String> headers,
  required Set<String> onDevice,
  required Color accent,
}) {
  return showModalBottomSheet<List<SeriesIssue>>(
    context: context,
    backgroundColor: context.scheme.s1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _SeriesDownloadSheet(
      detail: detail,
      baseUrl: baseUrl,
      headers: headers,
      onDevice: onDevice,
      accent: accent,
    ),
  );
}

class _SeriesDownloadSheet extends StatefulWidget {
  final SeriesDetail detail;
  final String baseUrl;
  final Map<String, String> headers;
  final Set<String> onDevice;
  final Color accent;

  const _SeriesDownloadSheet({
    required this.detail,
    required this.baseUrl,
    required this.headers,
    required this.onDevice,
    required this.accent,
  });

  @override
  State<_SeriesDownloadSheet> createState() => _SeriesDownloadSheetState();
}

class _SeriesDownloadSheetState extends State<_SeriesDownloadSheet> {
  late final List<SeriesIssue> _all = widget.detail.issues
      .where((i) => !widget.onDevice.contains(i.id))
      .toList();
  late final List<SeriesIssue> _unread =
      _all.where((i) => i.status != 'completed').toList();

  /// Bytes per issue id, from HEAD on the download URL (the server answers
  /// Content-Length from the file). Null until measured; missing = unknown.
  Map<String, int>? _sizes;
  int? _free;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final client = http.Client();
    final sizes = <String, int>{};
    try {
      // ponytail: 8 at a time; a 300-issue series is ~40 quick round trips.
      for (var i = 0; i < _all.length; i += 8) {
        await Future.wait(_all.skip(i).take(8).map((issue) async {
          try {
            final res = await client
                .head(Uri.parse('${widget.baseUrl}/comics/${issue.id}/download'),
                    headers: widget.headers)
                .timeout(const Duration(seconds: 10));
            final len = int.tryParse(res.headers['content-length'] ?? '');
            if (res.statusCode == 200 && len != null) sizes[issue.id] = len;
          } catch (_) {}
        }));
        if (!mounted) return;
      }
    } finally {
      client.close();
    }
    final free = await deviceFreeBytes();
    if (mounted) {
      setState(() {
        _sizes = sizes;
        _free = free;
      });
    }
  }

  /// Total bytes, or null when any issue's size is unknown.
  int? _total(List<SeriesIssue> issues) {
    final sizes = _sizes;
    if (sizes == null) return null;
    var sum = 0;
    for (final i in issues) {
      final s = sizes[i.id];
      if (s == null) return null;
      sum += s;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final measuring = _sizes == null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Download ${widget.detail.name}',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.scheme.tx)),
            const SizedBox(height: 6),
            Text(
              measuring
                  ? 'Checking sizes…'
                  : _free == null
                      ? 'Free space unknown'
                      : '${_fmt(_free!)} free on this iPad',
              style: TextStyle(fontSize: 13, color: context.scheme.t3),
            ),
            if (measuring) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                  color: widget.accent, backgroundColor: context.scheme.s2),
            ],
            const SizedBox(height: 16),
            if (_all.isEmpty)
              Text('Every issue is already on this iPad.',
                  style: TextStyle(color: context.scheme.t2))
            else ...[
              if (_unread.isNotEmpty && _unread.length < _all.length)
                _option('Unread', _unread, primary: true),
              _option(_unread.length == _all.length ? 'All' : 'All not downloaded',
                  _all, primary: _unread.isEmpty || _unread.length == _all.length),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option(String label, List<SeriesIssue> issues, {required bool primary}) {
    final total = _total(issues);
    final tooBig = total != null && _free != null && total > _free!;
    final n = issues.length;
    final text = [
      '$label · $n ${n == 1 ? 'issue' : 'issues'}',
      if (total != null) 'about ${_fmt(total)}',
    ].join(' · ');
    final onPressed = tooBig
        ? null
        : () {
            HapticFeedback.mediumImpact();
            Navigator.pop(context, issues);
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary
              ? FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                      backgroundColor: widget.accent,
                      minimumSize: const Size(0, 48)),
                  child: Text(text))
              : OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(text)),
          if (tooBig)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Not enough space on this iPad',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.red[400])),
            ),
        ],
      ),
    );
  }
}

String _fmt(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(1)} GB'
      : '${mb.toStringAsFixed(0)} MB';
}
