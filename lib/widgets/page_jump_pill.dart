import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';

/// Tappable "N / total" pill that turns into a "GO TO" page-jump field.
///
/// Sits on the bottom bar's [LiquidGlass], so it reads scheme tokens (not
/// hardcoded white) — the glass tint is light in Sepia Paper, so white text
/// would be illegible there.
class PageJumpPill extends StatefulWidget {
  /// 0-based.
  final int currentPage;
  final int totalPages;

  /// Called with the 0-based target page.
  final ValueChanged<int> onJump;

  /// Field border and Go button fill; matches the scrubber's slider accent.
  final Color accent;

  const PageJumpPill({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onJump,
    this.accent = AppTheme.accent,
  });

  @override
  State<PageJumpPill> createState() => _PageJumpPillState();
}

class _PageJumpPillState extends State<PageJumpPill> {
  bool _editing = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Losing focus (tap elsewhere, keyboard dismissed) reverts to the pill
    // without submitting — only Go/submit commits a jump.
    if (!_focusNode.hasFocus && _editing) {
      setState(() => _editing = false);
    }
  }

  void _startEditing() {
    _controller.clear();
    setState(() => _editing = true);
  }

  void _submit() {
    final n = int.tryParse(_controller.text);
    if (n != null) {
      widget.onJump(n.clamp(1, widget.totalPages) - 1);
    }
    _focusNode.unfocus();
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _editing ? _buildField(context) : _buildPill(context);
  }

  Widget _buildPill(BuildContext context) {
    final scheme = context.scheme;
    return GestureDetector(
      key: const Key('pageJumpPill.pill'),
      behavior: HitTestBehavior.opaque,
      onTap: _startEditing,
      // 44pt hit box around the 32pt pill.
      child: SizedBox(
        height: 44,
        child: Center(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.hairStrong,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${widget.currentPage + 1} / ${widget.totalPages}',
              style: context.monoCaption.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.52,
                color: scheme.tx,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context) {
    final scheme = context.scheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: widget.accent, width: 1.5),
    );
    // Swallow taps on the row itself so they don't fall through to the
    // reader's tap-zone overlay behind the bar. The row is one tap region
    // with the field, so tapping Go isn't a tap outside that unfocuses it.
    return TextFieldTapRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'GO TO',
              style: context.monoCaption.copyWith(
                fontSize: 12,
                letterSpacing: 0.84,
                color: scheme.t2,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 52,
              height: 32,
              child: TextField(
                key: const Key('pageJumpPill.field'),
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                // iOS doesn't unfocus on an outside tap by default.
                onTapOutside: (_) => _focusNode.unfocus(),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: context.monoCaption.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.tx,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: scheme.s2,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '/ ${widget.totalPages}',
              style: context.monoCaption.copyWith(
                fontSize: 12,
                color: scheme.t2,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              key: const Key('pageJumpPill.go'),
              behavior: HitTestBehavior.opaque,
              onTap: _submit,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Go',
                      style: TextStyle(
                        color: Scheme.onAccent(widget.accent),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
