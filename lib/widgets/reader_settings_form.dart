import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/platform.dart';
import '../config/scheme.dart';
import '../models/reader_settings.dart';
import '../services/sleep_shortcut.dart';
import '../services/bedtime_reminder.dart';

// ---------------------------------------------------------------------------
// Settings group container — card with section title + dividers
// ---------------------------------------------------------------------------

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.accent,
    required this.children,
  });

  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: context.sectionHeader.copyWith(color: accent),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.scheme.s1,
              borderRadius: BorderRadius.circular(AppTheme.r16),
            ),
            child: Column(children: _interleave(context, children)),
          ),
        ],
      ),
    );
  }

  List<Widget> _interleave(BuildContext context, List<Widget> items) {
    if (items.isEmpty) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(
          Divider(
            color: context.scheme.hair,
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
        );
      }
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// SettingsSegRow — label + segmented control
// ---------------------------------------------------------------------------

class SettingsSegRow extends StatelessWidget {
  const SettingsSegRow({
    super.key,
    required this.label,
    required this.options,
    required this.values,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final List<String> values;
  final String selected;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: context.scheme.tx,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          SettingsSegControl(
            options: options,
            values: values,
            selected: selected,
            accent: accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class SettingsSegControl extends StatelessWidget {
  const SettingsSegControl({
    super.key,
    required this.options,
    required this.values,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  final List<String> options;
  final List<String> values;
  final String selected;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(options.length, (i) {
          final isActive = values[i] == selected;
          final seg = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(values[i]);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38, // + 3pt track padding each side = 44pt target
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                options[i],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? Scheme.onAccent(accent) : context.scheme.t2,
                ),
              ),
            ),
          );
          return Expanded(child: seg);
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SettingsToggleRow — label + optional subtitle + switch
// ---------------------------------------------------------------------------

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.sub,
  });

  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.scheme.tx,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    style: TextStyle(fontSize: 12, color: context.scheme.t3),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppTheme.green,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SettingsSwatchRow — theme color swatches
// ---------------------------------------------------------------------------

class ThemeSwatch {
  const ThemeSwatch({
    required this.label,
    required this.color,
    required this.value,
  });
  final String label;
  final Color color;
  final String value;
}

const kThemeSwatches = [
  ThemeSwatch(label: 'Black', color: Color(0xFF000000), value: 'black'),
  ThemeSwatch(label: 'Sepia', color: Color(0xFFE8D9B5), value: 'sepia'),
  ThemeSwatch(label: 'Paper', color: Color(0xFFFFFFFF), value: 'white'),
];

class SettingsSwatchRow extends StatelessWidget {
  const SettingsSwatchRow({
    super.key,
    required this.swatches,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  final List<ThemeSwatch> swatches;
  final String selected;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in swatches)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(s.value);
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s.value == selected
                            ? accent
                            : context.scheme.hairStrong,
                        width: s.value == selected ? 2.5 : 1,
                      ),
                    ),
                    child: s.value == selected
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: _checkColor(s.color),
                          )
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.label,
                    style: TextStyle(fontSize: 12, color: context.scheme.t2),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Color _checkColor(Color bg) =>
      bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

// ---------------------------------------------------------------------------
// SettingsSliderRow — icon + label + slider
// ---------------------------------------------------------------------------

class SettingsSliderRow extends StatelessWidget {
  const SettingsSliderRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final IconData icon;
  final String label; // semantics only; the section title is visible
  final double value;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.scheme.t3),
        Expanded(
          child: Semantics(
            label: label,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accent,
                inactiveTrackColor: context.scheme.s3,
                thumbColor: context.scheme.tx,
                overlayColor: accent.withValues(alpha: 0.2),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
            ),
          ),
        ),
        Icon(icon, size: 22, color: context.scheme.t2),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Composed group widgets — card-style groups used by ReaderAaPanel
// ---------------------------------------------------------------------------

class ControlsGroup extends StatelessWidget {
  const ControlsGroup({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.accent,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: 'CONTROLS',
      accent: accent,
      children: [
        SettingsSegRow(
          label: 'Tap zones',
          options: const ['Standard', 'Off', 'Edge', 'Thumb'],
          values: const ['standard', 'disabled', 'edge', 'thumb'],
          selected: settings.tapZoneLayout,
          accent: accent,
          onChanged: (v) => onChanged(settings.copyWith(tapZoneLayout: v)),
        ),
        SettingsToggleRow(
          label: 'Volume keys',
          sub: 'Hardware buttons for page turns',
          value: settings.volumeKeys,
          onChanged: (v) => onChanged(settings.copyWith(volumeKeys: v)),
        ),
        SettingsToggleRow(
          label: 'Lock zoom',
          sub: 'Keep zoom level across pages',
          value: settings.zoomLock,
          onChanged: (v) => onChanged(settings.copyWith(zoomLock: v)),
        ),
        SettingsToggleRow(
          label: 'Keep screen on',
          value: settings.keepScreenOn,
          onChanged: (v) => onChanged(settings.copyWith(keepScreenOn: v)),
        ),
        if (settings.zoomMode == 'panels')
          SettingsToggleRow(
            label: 'Dim around panel',
            sub: 'Darken the rest of the page',
            value: settings.panelDim,
            onChanged: (v) => onChanged(settings.copyWith(panelDim: v)),
          ),
      ],
    );
  }
}

/// Sleep timer + bedtime rows. Set once, so they live in app Settings
/// (the moon button still starts the timer from the reader).
List<Widget> sleepSettingsRows({
  required ReaderSettings settings,
  required ValueChanged<ReaderSettings> onChanged,
  required Color accent,
}) =>
    [
        SettingsSegRow(
          label: 'Starting time',
          options: const ['5m', '10m', '15m', '30m', '45m'],
          values: const ['5', '10', '15', '30', '45'],
          selected: settings.sleepTimerMin.toString(),
          accent: accent,
          onChanged: (v) =>
              onChanged(settings.copyWith(sleepTimerMin: int.parse(v))),
        ),
        SettingsSegRow(
          label: 'Warning',
          options: const ['30s', '1m', '2m'],
          values: const ['30', '60', '120'],
          selected: settings.sleepWarningSec.toString(),
          accent: accent,
          onChanged: (v) =>
              onChanged(settings.copyWith(sleepWarningSec: int.parse(v))),
        ),
        // Shortcuts is iOS-only.
        if (!isAndroid)
        Consumer(
          builder: (context, ref, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            SettingsToggleRow(
              label: 'Run Shortcut at sleep',
              sub: 'Runs "$kSleepShortcutName" from the Shortcuts app, '
                  'e.g. to turn on Do Not Disturb',
              value: ref.watch(sleepShortcutProvider).value ?? false,
              onChanged: ref.read(sleepShortcutProvider.notifier).set,
            ),
            // One tap: turn it on and open the ready-made Shortcut to Add.
            InkWell(
              onTap: () {
                ref.read(sleepShortcutProvider.notifier).set(true);
                addSleepShortcut();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Expanded(
                    child: Text('Get the "$kSleepShortcutName" Shortcut',
                        style: TextStyle(
                            fontSize: 15,
                            color: context.scheme.tx,
                            fontWeight: FontWeight.w500)),
                  ),
                  Text('Add', style: TextStyle(fontSize: 15, color: accent)),
                ]),
              ),
            ),
          ]),
        ),
        Consumer(builder: (context, ref, _) {
          final r = ref.watch(bedtimeReminderProvider).value ??
              const BedtimeReminder();
          final notifier = ref.read(bedtimeReminderProvider.notifier);
          final start = TimeOfDay(hour: r.startMin ~/ 60, minute: r.startMin % 60);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SettingsToggleRow(
              label: 'Bedtime reminder',
              sub: 'Nudge once a night when you open a comic late',
              value: r.on,
              onChanged: notifier.setOn,
            ),
            if (r.on)
              InkWell(
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: start);
                  if (t != null) notifier.setStart(t.hour * 60 + t.minute);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Text('Starting at',
                          style: TextStyle(
                              fontSize: 15,
                              color: context.scheme.tx,
                              fontWeight: FontWeight.w500)),
                    ),
                    Text(start.format(context),
                        style: TextStyle(fontSize: 15, color: accent)),
                  ]),
                ),
              ),
          ]);
        }),
    ];
