import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/rename_templates_provider.dart';
import '../widgets/metadata_edit_sheet.dart'; // kIssueFormats, kFormatLabels

class RenameTemplatesScreen extends ConsumerStatefulWidget {
  const RenameTemplatesScreen({super.key});

  @override
  ConsumerState<RenameTemplatesScreen> createState() =>
      _RenameTemplatesScreenState();
}

class _RenameTemplatesScreenState
    extends ConsumerState<RenameTemplatesScreen> {
  // All format keys (issue-specific first, then the fallback 'default').
  static final _keys = [...kIssueFormats, 'default'];

  // Label for each key; 'default' has a friendly display name.
  static String _labelFor(String key) =>
      key == 'default' ? 'Default' : (kFormatLabels[key] ?? key);

  final Map<String, TextEditingController> _controllers = {};
  // Inline validation errors keyed by format key. Non-null = field is invalid.
  final Map<String, String?> _errors = {};
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(Map<String, String> templates) {
    for (final key in _keys) {
      final value = templates[key] ?? '';
      final existing = _controllers[key];
      if (existing == null) {
        _controllers[key] = TextEditingController(text: value);
      } else {
        existing.text = value;
      }
      if (value.isNotEmpty) _seededKeys.add(key);
    }
    _seeded = true;
  }

  // Track which keys were seeded with a non-empty server value.
  // Only those keys require a non-empty value on save.
  final Set<String> _seededKeys = {};

  /// Returns true if all previously-filled fields still have content.
  bool _validate() {
    final newErrors = <String, String?>{};
    for (final key in _keys) {
      final text = _controllers[key]?.text.trim() ?? '';
      // Only flag empty when the field was originally non-empty (seeded by
      // the server). A field that was always empty means "no template for
      // this format" and is valid — it will simply be omitted from the PUT.
      if (_seededKeys.contains(key) && text.isEmpty) {
        newErrors[key] = 'Template cannot be empty';
      } else {
        newErrors[key] = null;
      }
    }
    setState(() => _errors.addAll(newErrors));
    return newErrors.values.every((e) => e == null);
  }

  Future<void> _save() async {
    if (!_validate()) return; // block save — inline errors shown
    setState(() => _saving = true);
    try {
      final templates = {
        for (final key in _keys)
          if (_controllers[key]?.text.isNotEmpty ?? false)
            key: _controllers[key]!.text.trim(),
      };
      await ref.read(renameTemplatesProvider.notifier).save(templates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rename templates saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncTemplates = ref.watch(renameTemplatesProvider);

    return Scaffold(
      backgroundColor: context.scheme.s1,
      appBar: AppBar(
        backgroundColor: context.scheme.s1,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Rename Templates',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _seeded ? _save : null,
              child: const Text(
                'Save',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.blue,
                ),
              ),
            ),
        ],
      ),
      body: asyncTemplates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            'Failed to load templates: $err',
            style: TextStyle(color: context.scheme.t2),
          ),
        ),
        data: (templates) {
          if (!_seeded) {
            // Seed controllers once when data first arrives.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _seed(templates));
              }
            });
            // Also seed synchronously so build proceeds with controllers ready.
            _seed(templates);
          }
          return _buildForm();
        },
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Help text
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.scheme.s2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Use {series}, {number:03}, {year}, {title}, {volume}, {format} placeholders. '
            'Unknown placeholders are removed along with adjacent empty brackets.',
            style: TextStyle(
              fontSize: 13,
              color: context.scheme.t2,
              height: 1.5,
            ),
          ),
        ),

        // One card per format key
        for (final key in _keys) _buildFieldCard(key),
      ],
    );
  }

  Widget _buildFieldCard(String key) {
    final ctrl = _controllers[key];
    if (ctrl == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _labelFor(key),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.scheme.t3,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('template_field_$key'),
              controller: ctrl,
              style: TextStyle(fontSize: 14.5, color: context.scheme.tx),
              decoration: InputDecoration(
                hintText: 'e.g. {series} #{number:03} ({year})',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: context.scheme.t4,
                ),
                errorText: _errors[key],
                filled: true,
                fillColor: context.scheme.s3,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppTheme.blue,
                    width: 1.5,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.red, width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.red, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() {
                // Clear error as soon as the user starts typing
                if (v.trim().isNotEmpty) _errors[key] = null;
              }),
            ),
            if (ctrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Preview: ${renderTemplateExample(ctrl.text)}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.scheme.t3,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
