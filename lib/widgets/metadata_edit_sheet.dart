import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../models/series.dart';
import '../providers/metadata_editor.dart';

// ---------------------------------------------------------------------------
// Constants (Task 7 reuses kIssueFormats / kFormatLabels)
// ---------------------------------------------------------------------------

const kIssueFormats = [
  'single',
  'annual',
  'one-shot',
  'tpb',
  'hc',
  'omnibus',
];

const kFormatLabels = {
  'single': 'Single Issue',
  'annual': 'Annual',
  'one-shot': 'One-Shot',
  'tpb': 'Trade Paperback',
  'hc': 'Hardcover',
  'omnibus': 'Omnibus',
};

// ---------------------------------------------------------------------------
// Entry point (Task 6 / Task 8 call this exact signature)
// ---------------------------------------------------------------------------

Future<void> showMetadataEditSheet({
  required BuildContext context,
  required WidgetRef ref,
  SeriesDetail? series,
  SeriesIssue? issue,
  required String seriesId,
  required Color accent,
}) async {
  assert(
    (series == null) != (issue == null),
    'Exactly one of series/issue must be non-null',
  );
  HapticFeedback.selectionClick();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MetadataEditSheet(
      series: series,
      issue: issue,
      seriesId: seriesId,
      accent: accent,
    ),
  );
}

// ---------------------------------------------------------------------------
// The form widget — exposed so widget tests can pump it directly
// ---------------------------------------------------------------------------

class MetadataEditSheet extends ConsumerStatefulWidget {
  const MetadataEditSheet({
    super.key,
    this.series,
    this.issue,
    required this.seriesId,
    required this.accent,
  });

  final SeriesDetail? series;
  final SeriesIssue? issue;
  final String seriesId;
  final Color accent;

  @override
  ConsumerState<MetadataEditSheet> createState() => _MetadataEditSheetState();
}

class _MetadataEditSheetState extends ConsumerState<MetadataEditSheet> {
  // ---- Issue controllers ----
  late final TextEditingController _titleCtrl;
  late final TextEditingController _numberCtrl;
  late final TextEditingController _writerCtrl;
  late final TextEditingController _pencillerCtrl;
  late final TextEditingController _summaryCtrl;

  // ---- Series controllers ----
  late final TextEditingController _nameCtrl;
  late final TextEditingController _publisherCtrl;
  late final TextEditingController _seriesWriterCtrl;
  late final TextEditingController _seriesPencillerCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _genresCtrl;
  late final TextEditingController _descriptionCtrl;

  // ---- Format dropdown (issue mode) ----
  String? _selectedFormat;

  // ---- Snapshot of initial values for diff on save ----
  late final Map<String, String?> _initialValues;

  bool get _isIssueMode => widget.issue != null;

  @override
  void initState() {
    super.initState();
    if (_isIssueMode) {
      final iss = widget.issue!;
      _titleCtrl = TextEditingController(text: iss.title ?? '');
      _numberCtrl = TextEditingController(text: iss.number ?? '');
      _writerCtrl = TextEditingController(text: iss.writer ?? '');
      _pencillerCtrl = TextEditingController(text: iss.penciller ?? '');
      _summaryCtrl = TextEditingController(text: iss.summary ?? '');
      _selectedFormat = iss.format;

      _initialValues = {
        'title': iss.title ?? '',
        'number': iss.number ?? '',
        'writer': iss.writer ?? '',
        'penciller': iss.penciller ?? '',
        'summary': iss.summary ?? '',
        'format': iss.format,
      };

      // Unused in issue mode — init to avoid LateInitializationError
      _nameCtrl = TextEditingController();
      _publisherCtrl = TextEditingController();
      _seriesWriterCtrl = TextEditingController();
      _seriesPencillerCtrl = TextEditingController();
      _yearCtrl = TextEditingController();
      _genresCtrl = TextEditingController();
      _descriptionCtrl = TextEditingController();
    } else {
      final s = widget.series!;
      _nameCtrl = TextEditingController(text: s.name);
      _publisherCtrl = TextEditingController(text: s.publisher ?? '');
      _seriesWriterCtrl = TextEditingController(text: s.writer ?? '');
      _seriesPencillerCtrl = TextEditingController(text: s.penciller ?? '');
      _yearCtrl = TextEditingController(text: s.year?.toString() ?? '');
      _genresCtrl = TextEditingController(text: s.genres.join(', '));
      _descriptionCtrl = TextEditingController(text: s.description ?? '');

      _initialValues = {
        'name': s.name,
        'publisher': s.publisher ?? '',
        'writer': s.writer ?? '',
        'penciller': s.penciller ?? '',
        'year': s.year?.toString() ?? '',
        'genres': s.genres.join(', '),
        'description': s.description ?? '',
      };

      // Unused in series mode
      _titleCtrl = TextEditingController();
      _numberCtrl = TextEditingController();
      _writerCtrl = TextEditingController();
      _pencillerCtrl = TextEditingController();
      _summaryCtrl = TextEditingController();
      _selectedFormat = null;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _numberCtrl.dispose();
    _writerCtrl.dispose();
    _pencillerCtrl.dispose();
    _summaryCtrl.dispose();
    _nameCtrl.dispose();
    _publisherCtrl.dispose();
    _seriesWriterCtrl.dispose();
    _seriesPencillerCtrl.dispose();
    _yearCtrl.dispose();
    _genresCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Save — only-changed-fields diff
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    final editor = ref.read(metadataEditorProvider);
    final fields = <String, dynamic>{};

    if (_isIssueMode) {
      void diffText(String key, TextEditingController ctrl) {
        if (ctrl.text != (_initialValues[key] ?? '')) {
          fields[key] = ctrl.text;
        }
      }

      diffText('title', _titleCtrl);
      diffText('number', _numberCtrl);
      diffText('writer', _writerCtrl);
      diffText('penciller', _pencillerCtrl);
      diffText('summary', _summaryCtrl);

      // Format: null (_selectedFormat) means "Not set" → send '' so the
      // backend clears it (validFormats accepts '' as clear). Never send null.
      final formatChanged = _selectedFormat != _initialValues['format'];
      if (formatChanged) {
        fields['format'] = _selectedFormat ?? '';
      }

      if (fields.isEmpty) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }

      await editor.saveIssue(widget.issue!.id, fields);
    } else {
      void diffText(String key, TextEditingController ctrl) {
        if (ctrl.text != (_initialValues[key] ?? '')) {
          fields[key] = ctrl.text;
        }
      }

      diffText('name', _nameCtrl);
      diffText('publisher', _publisherCtrl);
      diffText('writer', _seriesWriterCtrl);
      diffText('penciller', _seriesPencillerCtrl);
      diffText('description', _descriptionCtrl);

      final yearText = _yearCtrl.text;
      if (yearText != (_initialValues['year'] ?? '')) {
        // Omit year entirely when cleared — backend has no clear semantics
        // for int* year and an all-null patch 400s. Only include if non-empty.
        if (yearText.isNotEmpty) {
          final yearParsed = int.tryParse(yearText);
          if (yearParsed != null) {
            fields['year'] = yearParsed;
          }
        }
        // If yearText.isEmpty: key is omitted from the patch (intentional).
      }

      final genresText = _genresCtrl.text;
      if (genresText != (_initialValues['genres'] ?? '')) {
        fields['genres'] = genresText.isEmpty
            ? <String>[]
            : genresText
                .split(',')
                .map((g) => g.trim())
                .where((g) => g.isNotEmpty)
                .toList();
      }

      if (fields.isEmpty) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }

      await editor.saveSeries(widget.seriesId, fields);
    }

    if (mounted) {
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Metadata saved')));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.scheme.hairStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    _isIssueMode ? 'Edit Issue' : 'Edit Series',
                    style: TextStyle(
                      color: context.scheme.tx,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _save,
                    child: Text(
                      'Save',
                      style: TextStyle(
                        color: widget.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // PDF caption
            if (_isIssueMode &&
                widget.issue!.name.toLowerCase().endsWith('.pdf'))
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  'PDF: metadata is stored in the library database, not written to the file',
                  style: TextStyle(
                    color: context.scheme.t3,
                    fontSize: 12,
                  ),
                ),
              ),

            Divider(color: context.scheme.hair, height: 1),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: _isIssueMode
                    ? _buildIssueForm(context)
                    : _buildSeriesForm(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Issue form
  // ---------------------------------------------------------------------------

  Widget _buildIssueForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(context, label: 'Title', controller: _titleCtrl),
        const SizedBox(height: 12),
        _field(context, label: 'Number', controller: _numberCtrl),
        const SizedBox(height: 12),
        _formatDropdown(context),
        const SizedBox(height: 12),
        _field(context, label: 'Writer', controller: _writerCtrl),
        const SizedBox(height: 12),
        _field(context, label: 'Penciller', controller: _pencillerCtrl),
        const SizedBox(height: 12),
        _field(context,
            label: 'Summary', controller: _summaryCtrl, maxLines: 4),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Series form
  // ---------------------------------------------------------------------------

  Widget _buildSeriesForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(context, label: 'Name', controller: _nameCtrl),
        const SizedBox(height: 12),
        _field(context, label: 'Publisher', controller: _publisherCtrl),
        const SizedBox(height: 12),
        _field(context, label: 'Writer', controller: _seriesWriterCtrl),
        const SizedBox(height: 12),
        _field(context, label: 'Penciller', controller: _seriesPencillerCtrl),
        const SizedBox(height: 12),
        _field(
          context,
          label: 'Year',
          controller: _yearCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        _field(
          context,
          label: 'Genres (comma-separated)',
          controller: _genresCtrl,
        ),
        const SizedBox(height: 12),
        _field(
          context,
          label: 'Description',
          controller: _descriptionCtrl,
          maxLines: 4,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared field widget
  // ---------------------------------------------------------------------------

  Widget _field(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.scheme.t2,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(color: context.scheme.tx, fontSize: 15),
          decoration: InputDecoration(
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
              borderSide: BorderSide(color: context.scheme.hair),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: widget.accent),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Format dropdown
  // ---------------------------------------------------------------------------

  Widget _formatDropdown(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Format',
          style: TextStyle(
            color: context.scheme.t2,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: context.scheme.s3,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.scheme.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedFormat,
              isExpanded: true,
              dropdownColor: context.scheme.s3,
              style: TextStyle(color: context.scheme.tx, fontSize: 15),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Not set',
                      style: TextStyle(color: context.scheme.t3)),
                ),
                ...kIssueFormats.map(
                  (f) => DropdownMenuItem<String?>(
                    value: f,
                    child: Text(kFormatLabels[f] ?? f),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _selectedFormat = v),
            ),
          ),
        ),
      ],
    );
  }
}
