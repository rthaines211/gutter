import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/reader_settings.dart';
import '../providers/accent_provider.dart';
import '../providers/rail_side_provider.dart';
import '../providers/zone_peek_provider.dart';
import '../config/layout_breakpoint.dart';
import 'reader_settings_form.dart';

/// The one "Aa" reader settings panel, hosted in a popover on iPad and a
/// bottom sheet on phone. Content only — the host supplies the glass.
class ReaderAaPanel extends ConsumerStatefulWidget {
  const ReaderAaPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.setBrightness,
    this.readBrightness,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  /// Injectable for tests; default to the `screen_brightness` plugin.
  final Future<void> Function(double)? setBrightness;
  final Future<double> Function()? readBrightness;

  @override
  ConsumerState<ReaderAaPanel> createState() => _ReaderAaPanelState();
}

class _ReaderAaPanelState extends ConsumerState<ReaderAaPanel> {
  // Local copy: a modal sheet host never rebuilds us with new settings.
  late ReaderSettings _s = widget.settings;
  double _brightness = 0.5;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _loadBrightness();
  }

  @override
  void didUpdateWidget(ReaderAaPanel old) {
    super.didUpdateWidget(old);
    // Only a new object is news: the phone sheet re-passes its stale opening
    // snapshot on route rebuilds, which must not wipe edits made since.
    // ReaderSettings has no ==, hence identical.
    if (!identical(widget.settings, old.settings)) _s = widget.settings;
  }

  Future<void> _loadBrightness() async {
    try {
      final read =
          widget.readBrightness ?? () => ScreenBrightness.instance.current;
      final b = await read();
      if (mounted) setState(() => _brightness = b);
    } catch (_) {}
  }

  Future<void> _setBrightness(double v) async {
    setState(() => _brightness = v);
    try {
      await (widget.setBrightness ??
          ScreenBrightness.instance.setScreenBrightness)(v);
    } catch (_) {}
  }

  void _update(ReaderSettings next) {
    setState(() => _s = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;

    Widget section(String title, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.sectionHeader),
        const SizedBox(height: 8),
        child,
      ],
    );

    Widget seg(
      String title,
      List<String> labels,
      List<String> values,
      String selected,
      ReaderSettings Function(String) apply,
    ) => section(
      title,
      SettingsSegControl(
        options: labels,
        values: values,
        selected: selected,
        accent: accent,
        onChanged: (v) => _update(apply(v)),
      ),
    );

    const gap = SizedBox(height: 18);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Reading',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: context.scheme.tx,
            ),
          ),
          gap,
          seg(
            'FIT',
            const ['Screen', 'Width', 'Height'],
            const ['fitScreen', 'fitWidth', 'fitHeight'],
            _s.pageFit,
            (v) => _s.copyWith(pageFit: v),
          ),
          gap,
          seg(
            'ZOOM',
            const ['Off', 'Panels', 'Bubbles'],
            const ['off', 'panels', 'bubbles'],
            _s.zoomMode,
            (v) => _s.copyWith(zoomMode: v),
          ),
          gap,
          section(
            'BACKGROUND',
            SettingsSwatchRow(
              swatches: kThemeSwatches,
              selected: _s.theme == 'paper' ? 'white' : _s.theme, // legacy
              accent: accent,
              onChanged: (v) => _update(_s.copyWith(theme: v)),
            ),
          ),
          gap,
          section(
            'BRIGHTNESS',
            SettingsSliderRow(
              icon: Icons.wb_sunny_outlined,
              label: 'Brightness',
              value: _brightness,
              accent: accent,
              onChanged: _setBrightness,
            ),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: seg(
                  'MODE',
                  const ['Pages', 'Scroll'],
                  const ['page', 'scroll'],
                  _s.readingMode,
                  (v) => _s.copyWith(readingMode: v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: seg(
                  'DIRECTION',
                  const ['LTR', 'RTL'],
                  const ['ltr', 'rtl'],
                  _s.readingDirection,
                  (v) => _s.copyWith(readingDirection: v),
                ),
              ),
            ],
          ),
          gap,
          _MoreRow(open: _more, onTap: () => setState(() => _more = !_more)),
          if (_more) ...[
            ControlsGroup(settings: _s, onChanged: _update, accent: accent),
            if (_s.tapZoneLayout != 'disabled')
              SettingsGroup(
                title: 'TAP ZONES',
                accent: accent,
                children: [
                  SettingsToggleRow(
                    label: 'Show on open',
                    sub: 'Flash the zones when a comic opens',
                    value: ref.watch(zonePeekProvider),
                    onChanged: ref.read(zonePeekProvider.notifier).set,
                  ),
                ],
              ),
            // Device-local, not a ReaderSettings field: it's about this
            // iPad's grip, not the comic.
            if (LayoutBreakpoint.isTablet(context))
              SettingsGroup(
                title: 'RAIL',
                accent: accent,
                children: [
                  SettingsSegRow(
                    label: 'Side',
                    options: const ['Left', 'Right'],
                    values: const ['left', 'right'],
                    selected: ref.watch(railSideProvider).name,
                    accent: accent,
                    onChanged: (v) => ref
                        .read(railSideProvider.notifier)
                        .select(RailSide.values.byName(v)),
                  ),
                ],
              ),
            SettingsGroup(
              title: 'PAGES',
              accent: accent,
              children: [
                SettingsSegRow(
                  label: 'Page turn',
                  options: const ['Slide', 'Fade', 'None'],
                  values: const ['slide', 'fade', 'none'],
                  selected: _s.pageAnimation,
                  accent: accent,
                  onChanged: (v) => _update(_s.copyWith(pageAnimation: v)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: context.scheme.hair, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Flexible(
              flex: 3,
              child: Text(
                'More reader settings',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: context.scheme.tx),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(
                'Tap zones, controls, page turn…',
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.scheme.t3),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              open ? Icons.expand_less : Icons.chevron_right,
              size: 16,
              color: context.scheme.t2,
            ),
          ],
        ),
      ),
    );
  }
}
