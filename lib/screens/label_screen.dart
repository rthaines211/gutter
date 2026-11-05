// lib/screens/label_screen.dart
//
// iPad labeller: walks the label server's queue (or one page, from the
// reader's Fix…), drawing boxes then numbering them in reading order.
// Layout follows the approved mockup
// (.superpowers/brainstorm/1512-1793094947/content/labeller.html).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../providers/providers.dart';
import '../services/label_client.dart';
import '../services/label_editor.dart';
import '../widgets/label_canvas.dart';

const _go = Color(0xFF2F6F2F);
const _errorColor = Color(0xFFFF453A);

class LabelScreen extends ConsumerStatefulWidget {
  final LabelMode initialMode;
  final String? singleId;

  const LabelScreen({
    super.key,
    this.initialMode = LabelMode.panels,
    this.singleId,
  });

  @override
  ConsumerState<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends ConsumerState<LabelScreen> {
  late LabelMode _mode = widget.initialMode;
  LabelSession? _session;
  LabelEditor? _editor;
  LabelPage? _editorFor;

  /// Screen-local error (fetch / numbering); session.status covers saves.
  String? _error;
  bool _numbering = false;
  bool _noteOpen = false;
  final _note = TextEditingController();
  Timer? _autoNumber;

  LabelClient get _client => ref.read(labelClientProvider);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _autoNumber?.cancel();
    _session?.removeListener(_onSession);
    _session?.dispose();
    _editor?.removeListener(_onEditor);
    _editor?.dispose();
    _note.dispose();
    super.dispose();
  }

  void _start() {
    _session?.removeListener(_onSession);
    _session?.dispose();
    final s = LabelSession(
      client: _client,
      mode: _mode,
      singleId: widget.singleId,
    )
      ..attachContext(context)
      ..addListener(_onSession);
    _session = s;
    _setEditor(null);
    _run(s.load);
  }

  /// Runs a session navigation; fetch errors land in the status area.
  Future<void> _run(Future<void> Function() f) async {
    // No setState when already clear: _start runs this from initState.
    if (_error != null) setState(() => _error = null);
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    }
  }

  void _onSession() {
    final cur = _session?.current;
    if (cur != _editorFor) _setEditor(cur);
    if (mounted) setState(() {});
  }

  void _onEditor() {
    if (mounted) setState(() {});
    _scheduleAutoNumber();
  }

  /// On the Boxes step, numbers the boxes shortly after they stop changing,
  /// so the reading order shows while editing (and Order ▸ is instant).
  /// Failures stay quiet here; Order ▸ reports them.
  void _scheduleAutoNumber() {
    _autoNumber?.cancel();
    final e = _editor, page = _editorFor;
    if (e == null || page == null || e.step != LabelStep.boxes) return;
    if (!e.needsNumbering || e.boxes.isEmpty) return;
    _autoNumber = Timer(const Duration(milliseconds: 400), () async {
      if (e != _editor || !e.needsNumbering || _numbering) return;
      final key = e.boxesKey;
      try {
        final o = await _client.numberBoxes(
          _mode,
          page.w,
          page.h,
          e.boxes,
          _mode == LabelMode.balloons ? page.context : const [],
        );
        if (mounted && e == _editor) e.setOrder(o, forBoxes: key);
      } catch (_) {}
    });
  }

  void _setEditor(LabelPage? page) {
    _editor?.removeListener(_onEditor);
    _editor?.dispose();
    _editorFor = page;
    _error = null;
    _editor = page == null
        ? null
        : (LabelEditor(
            mode: _mode,
            prefillBoxes: page.prefill,
            prefillKinds: page.prefillKinds,
            saved: page.saved,
          )..addListener(_onEditor));
    _note.text = _editor?.note ?? '';
    _noteOpen = _note.text.isNotEmpty;
    _scheduleAutoNumber();
  }

  void _switchMode(LabelMode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _start();
  }

  Future<void> _toOrder() async {
    final e = _editor, page = _editorFor;
    if (e == null || page == null || _numbering) return;
    if (_error != null) setState(() => _error = null);
    if (e.needsNumbering) {
      final key = e.boxesKey;
      setState(() => _numbering = true);
      try {
        final o = await _client.numberBoxes(
          _mode,
          page.w,
          page.h,
          e.boxes,
          _mode == LabelMode.balloons ? page.context : const [],
        );
        e.setOrder(o, forBoxes: key);
      } catch (err) {
        if (mounted && e == _editor) {
          setState(() => _error = "Couldn't number the boxes: $err");
        }
        return;
      } finally {
        if (mounted) setState(() => _numbering = false);
      }
      // Boxes edited while the request was out: stay on Boxes.
      if (e != _editor || e.needsNumbering) return;
    }
    e.toOrderStep();
  }

  Future<void> _save() async {
    final e = _editor, s = _session, page = _editorFor;
    if (e == null || s == null || page == null) return;
    if (widget.singleId == null) {
      // Batch: optimistic, session moves on and flags failures itself.
      unawaited(_run(() => s.save(e)));
      return;
    }
    // Single page (reader's Fix): leave only once the PUT has landed, so a
    // failure stays on screen as SAVE FAILED. isCurrent: a double-tapped
    // Save must not pop twice.
    await _run(() => s.save(e));
    if (!mounted || !s.done.contains(page.id)) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) Navigator.of(context).pop();
  }

  void _none() {
    _editor?.markNone();
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) {
    final sc = context.scheme;
    final e = _editor;
    final page = _editorFor;
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(sc),
            Expanded(
              child: e == null || page == null
                  ? Center(
                      // Session status is set here only once there's
                      // nothing to show (e.g. an empty queue).
                      child: _error != null || (_session?.status ?? '') != ''
                          ? Text(_error ?? _session!.status,
                              style: TextStyle(color: sc.t2))
                          : const CircularProgressIndicator(),
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: LabelCanvas(
                              editor: e,
                              page: page,
                              imageUrl: _client.imageUrl(page.id),
                              mode: _mode,
                              onPrev: () => _run(_session!.prev),
                              onNext: () => _run(_session!.nextTodo),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 8,
                          child: _primary(e),
                        ),
                      ],
                    ),
            ),
            if (e != null) _strip(sc, e),
          ],
        ),
      ),
    );
  }

  Widget _topBar(Scheme sc) {
    final s = _session;
    final ids = s?.ids ?? const <String>[];
    final done = ids.where((id) => s!.done.contains(id)).length;
    final flag = s?.flagReason;
    final status = s?.status ?? '';
    final failed = status.startsWith('SAVE FAILED');
    final shown = failed ? status : (_error ?? status);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: sc.hair)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            color: sc.tx,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          if (widget.singleId == null)
            SegmentedButton<LabelMode>(
              segments: const [
                ButtonSegment(value: LabelMode.panels, label: Text('Panels')),
                ButtonSegment(
                    value: LabelMode.balloons, label: Text('Balloons')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _switchMode(v.first),
            ),
          const SizedBox(width: 10),
          if (_editorFor != null)
            Text('#${_editorFor!.id}', style: TextStyle(color: sc.t2)),
          if (flag != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF5A3A10),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('⚑ $flag',
                  style: const TextStyle(color: Color(0xFFFFCC99))),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: failed ? _errorColor : sc.t2,
                fontWeight: failed ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              value: ids.isEmpty ? 0 : done / ids.length,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: const Color(0xFF333333),
              color: const Color(0xFF66CC66),
            ),
          ),
          const SizedBox(width: 8),
          Text('$done / ${ids.length}', style: TextStyle(color: sc.tx)),
        ],
      ),
    );
  }

  Widget _strip(Scheme sc, LabelEditor e) {
    Widget btn(String label, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: sc.tx,
              side: const BorderSide(color: Color(0xFF444444)),
              backgroundColor: const Color(0xFF1B1B1B),
            ),
            child: Text(label),
          ),
        );
    final order = e.step == LabelStep.order;
    final n = e.boxes.length;
    return Container(
      height: 52,
      // Leave the thumb corner to the primary button.
      padding: const EdgeInsets.only(left: 10, right: 140),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: sc.hair)),
      ),
      child: Row(
        children: [
          if (!order) ...[
            btn('Delete', e.selected < 0 ? null : e.deleteSelected),
            btn(_mode.noneLabel, _none),
            btn('Clear', e.clear),
            btn('Reset', e.resetToPrefill),
          ] else ...[
            btn('◀ Boxes', e.backToBoxes),
            btn('Restart order', e.restartOrder),
          ],
          btn('✎ Note', () => setState(() => _noteOpen = !_noteOpen)),
          // Next unlabelled page without saving this one (the web's N).
          if (widget.singleId == null)
            btn('Skip ▸', () => _run(_session!.nextTodo)),
          if (_noteOpen)
            Expanded(
              child: TextField(
                controller: _note,
                maxLines: 1,
                style: TextStyle(color: sc.tx),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Note',
                ),
                onChanged: (v) => e.note = v,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              order
                  ? 'tap boxes in reading order · ${e.order.length} of $n'
                  : '$n ${n == 1 ? 'box' : 'boxes'}',
              style: const TextStyle(color: Color(0xFF888888)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primary(LabelEditor e) {
    final order = e.step == LabelStep.order;
    final enabled = order ? e.canSave : !_numbering;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: FilledButton(
        onPressed: enabled ? (order ? _save : _toOrder) : null,
        style: FilledButton.styleFrom(
          backgroundColor: _go,
          disabledBackgroundColor: _go,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        child: Text(order ? 'Save ▸' : 'Order ▸'),
      ),
    );
  }
}
