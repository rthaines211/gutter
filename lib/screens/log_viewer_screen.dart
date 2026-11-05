import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../services/app_logger.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  static const _errorRed = Color(0xFFFF3B30);
  static const _maxEvents = 500;

  LogCategory? _category;
  LogLevel? _minLevel;
  bool _paused = false;
  late List<LogEvent> _events;
  StreamSubscription<LogEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _events = AppLogger.instance.snapshot().reversed.toList();
    _sub = AppLogger.instance.stream().listen((event) {
      if (_paused) return;
      setState(() {
        _events.insert(0, event);
        if (_events.length > _maxEvents) {
          _events.removeRange(_maxEvents, _events.length);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Iterable<LogEvent> get _filtered {
    final minIdx =
        _minLevel == null ? 0 : LogLevel.values.indexOf(_minLevel!);
    return _events.where((e) {
      if (_category != null && e.category != _category) return false;
      if (_minLevel != null &&
          LogLevel.values.indexOf(e.level) < minIdx) {
        return false;
      }
      return true;
    });
  }

  Future<void> _export() async {
    final text = await AppLogger.instance.exportAsText();
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to export')),
      );
      return;
    }
    await Share.share(text, subject: 'Comic Reader logs');
  }

  Future<void> _clear() async {
    HapticFeedback.mediumImpact();
    await AppLogger.instance.clear();
    if (!mounted) return;
    setState(() => _events.clear());
  }

  Color _levelColor(BuildContext context, LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return context.scheme.t3;
      case LogLevel.info:
        return context.scheme.t2;
      case LogLevel.warn:
        return AppTheme.amber;
      case LogLevel.error:
        return _errorRed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered.toList();
    return Scaffold(
      backgroundColor: context.scheme.bgRaised,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        backgroundColor: context.scheme.bgRaised,
        actions: [
          IconButton(
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            tooltip: _paused ? 'Resume' : 'Pause',
            onPressed: () => setState(() => _paused = !_paused),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Export',
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            category: _category,
            minLevel: _minLevel,
            onCategory: (c) => setState(() => _category = c),
            onMinLevel: (l) => setState(() => _minLevel = l),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text('No events match this filter',
                        style: TextStyle(color: context.scheme.t3)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    separatorBuilder: (context2, index) =>
                        Divider(height: 1, color: context.scheme.hair),
                    itemBuilder: (ctx, i) {
                      final e = filtered[i];
                      return _EventRow(event: e, color: _levelColor(ctx, e.level));
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final LogCategory? category;
  final LogLevel? minLevel;
  final void Function(LogCategory?) onCategory;
  final void Function(LogLevel?) onMinLevel;

  const _FilterBar({
    required this.category,
    required this.minLevel,
    required this.onCategory,
    required this.onMinLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: context.scheme.s1,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(context, 'All', category == null, () => onCategory(null)),
                for (final c in LogCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _chip(context, c.name, category == c, () => onCategory(c)),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<LogLevel?>(
            value: minLevel,
            dropdownColor: context.scheme.s1,
            hint: Text('All', style: TextStyle(color: context.scheme.t2)),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              for (final l in LogLevel.values)
                DropdownMenuItem(value: l, child: Text('${l.name}+')),
            ],
            onChanged: onMinLevel,
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.25)
              : context.scheme.s2,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppTheme.accent : context.scheme.t2,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final LogEvent event;
  final Color color;

  const _EventRow({required this.event, required this.color});

  String _stamp() {
    final t = event.timestamp.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  void _showContext(BuildContext context) {
    if (event.context.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.scheme.s1,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.message,
                style: TextStyle(
                    color: context.scheme.tx, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final entry in event.context.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${entry.key}: ${entry.value}',
                    style: TextStyle(
                        color: context.scheme.t2, fontFamily: 'monospace')),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showContext(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 86,
              child: Text(_stamp(),
                  style: TextStyle(
                      color: context.scheme.t3,
                      fontFamily: 'monospace',
                      fontSize: 11)),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '[${event.category.name}/${event.level.name}]',
                style: TextStyle(
                    color: color,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(event.message,
                  style: TextStyle(color: context.scheme.tx, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
