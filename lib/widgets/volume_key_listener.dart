import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

/// Intercepts hardware volume key presses by monitoring system volume changes.
///
/// Pins volume at midpoint (0.5) so both up and down presses are detectable.
/// Hides system volume UI while active. Restores original volume on dispose.
class VolumeKeyListener extends StatefulWidget {
  final Widget child;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final bool enabled;

  const VolumeKeyListener({
    super.key,
    required this.child,
    required this.onVolumeUp,
    required this.onVolumeDown,
    this.enabled = true,
  });

  @override
  State<VolumeKeyListener> createState() => _VolumeKeyListenerState();
}

class _VolumeKeyListenerState extends State<VolumeKeyListener> {
  static const _midpoint = 0.5;
  double? _lastVolume;
  double? _originalVolume;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _startListening();
  }

  @override
  void didUpdateWidget(VolumeKeyListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_listening) {
      _startListening();
    } else if (!widget.enabled && _listening) {
      _stopListening();
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _startListening() async {
    _listening = true;
    await FlutterVolumeController.updateShowSystemUI(false);
    _originalVolume ??= await FlutterVolumeController.getVolume();
    await FlutterVolumeController.setVolume(_midpoint);
    _lastVolume = _midpoint;
    FlutterVolumeController.addListener(_onVolumeChanged);
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    _listening = false;
    FlutterVolumeController.removeListener();
    await FlutterVolumeController.updateShowSystemUI(true);
    if (_originalVolume != null) {
      await FlutterVolumeController.setVolume(_originalVolume!);
      _originalVolume = null;
    }
  }

  void _onVolumeChanged(double volume) {
    if (!mounted || !widget.enabled) return;
    final prev = _lastVolume;
    _lastVolume = volume;
    if (prev == null || (volume - prev).abs() < 0.001) return;

    if (volume > prev) {
      widget.onVolumeUp();
    } else {
      widget.onVolumeDown();
    }

    // Reset to midpoint so next press always has room
    FlutterVolumeController.setVolume(_midpoint);
    _lastVolume = _midpoint;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
