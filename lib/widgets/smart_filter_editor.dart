import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/smart_filter.dart';
import '../providers/smart_filter_provider.dart';

class SmartFilterEditor extends ConsumerStatefulWidget {
  final SmartFilter? existing;
  final Color accent;

  const SmartFilterEditor({super.key, this.existing, this.accent = AppTheme.accent});

  @override
  ConsumerState<SmartFilterEditor> createState() => _SmartFilterEditorState();
}

class _ConditionRow {
  String field;
  String op;
  final TextEditingController valueController;

  _ConditionRow({
    required this.field,
    required this.op,
    String value = '',
  }) : valueController = TextEditingController(text: value);

  void dispose() => valueController.dispose();
}

const _fields = [
  'status',
  'issue_count',
  'publisher',
  'genre',
  'writer',
  'penciller',
  'year',
  'date_added',
];

const _fieldLabels = {
  'status': 'Status',
  'issue_count': 'Issue Count',
  'publisher': 'Publisher',
  'genre': 'Genre',
  'writer': 'Writer',
  'penciller': 'Penciller',
  'year': 'Year',
  'date_added': 'Date Added',
};

const _operatorLabels = {
  'eq': '=',
  'neq': '\u2260',
  'gt': '>',
  'gte': '\u2265',
  'lt': '<',
  'lte': '\u2264',
  'contains': 'contains',
  'within_days': 'within days',
};

Map<String, List<String>> _operatorsForField = {
  'status': ['eq', 'neq'],
  'issue_count': ['eq', 'gt', 'gte', 'lt', 'lte'],
  'publisher': ['eq', 'neq', 'contains'],
  'genre': ['eq', 'neq', 'contains'],
  'writer': ['eq', 'neq', 'contains'],
  'penciller': ['eq', 'neq', 'contains'],
  'year': ['eq', 'gt', 'gte', 'lt', 'lte'],
  'date_added': ['within_days'],
};

class _SmartFilterEditorState extends ConsumerState<SmartFilterEditor> {
  late final TextEditingController _nameController;
  final List<_ConditionRow> _conditions = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existing?.name ?? '');
    if (widget.existing != null) {
      for (final c in widget.existing!.conditions) {
        _conditions.add(_ConditionRow(
          field: c.field,
          op: c.op,
          value: c.value,
        ));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final row in _conditions) {
      row.dispose();
    }
    super.dispose();
  }

  List<String> _opsFor(String field) =>
      _operatorsForField[field] ?? ['eq'];

  void _addCondition() {
    setState(() {
      _conditions.add(_ConditionRow(field: 'status', op: 'eq'));
    });
  }

  void _removeCondition(int index) {
    setState(() {
      _conditions[index].dispose();
      _conditions.removeAt(index);
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _conditions.isEmpty) return;

    HapticFeedback.mediumImpact();

    final conditions = _conditions
        .map((r) => FilterCondition(
              field: r.field,
              op: r.op,
              value: r.valueController.text.trim(),
            ))
        .toList();

    final filter = SmartFilter(
      id: widget.existing?.id ?? 0,
      name: name,
      icon: widget.existing?.icon ?? 'filter_list',
      color: widget.existing?.color ?? '#64B5F6',
      conditions: conditions,
      position: widget.existing?.position ?? 0,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final notifier = ref.read(smartFilterNotifierProvider.notifier);
    if (_isEdit) {
      await notifier.update(widget.existing!.id, filter);
    } else {
      await notifier.create(filter);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grabber handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.scheme.t4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Text(
                _isEdit ? 'Edit Smart Filter' : 'New Smart Filter',
                style: AppTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              // Name field
              TextField(
                controller: _nameController,
                style: TextStyle(color: context.scheme.tx),
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: context.scheme.t2),
                  filled: true,
                  fillColor: context.scheme.s2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.r12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Conditions header
              Text(
                'CONDITIONS',
                style: context.sectionHeader,
              ),
              const SizedBox(height: 12),
              // Condition rows
              ..._conditions.asMap().entries.map((entry) {
                final index = entry.key;
                final row = entry.value;
                final ops = _opsFor(row.field);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      // Field dropdown
                      Expanded(
                        flex: 3,
                        child: _dropdown<String>(
                          context,
                          value: row.field,
                          items: _fields
                              .map((f) => DropdownMenuItem(
                                    value: f,
                                    child: Text(
                                      _fieldLabels[f] ?? f,
                                      style: TextStyle(
                                          color: context.scheme.tx,
                                          fontSize: 13),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              row.field = v;
                              final newOps = _opsFor(v);
                              if (!newOps.contains(row.op)) {
                                row.op = newOps.first;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Operator dropdown
                      Expanded(
                        flex: 2,
                        child: _dropdown<String>(
                          context,
                          value: ops.contains(row.op)
                              ? row.op
                              : ops.first,
                          items: ops
                              .map((o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(
                                      _operatorLabels[o] ?? o,
                                      style: TextStyle(
                                          color: context.scheme.tx,
                                          fontSize: 13),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => row.op = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Value field
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: row.valueController,
                          style: TextStyle(
                              color: context.scheme.tx, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Value',
                            hintStyle:
                                TextStyle(color: context.scheme.t3),
                            filled: true,
                            fillColor: context.scheme.s2,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.r8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Remove button
                      GestureDetector(
                        onTap: () => _removeCondition(index),
                        child: Icon(
                          Icons.remove_circle_outline,
                          color: context.scheme.t3,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              // Add condition button
              TextButton.icon(
                onPressed: _addCondition,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add condition'),
                style: TextButton.styleFrom(
                  foregroundColor: widget.accent,
                ),
              ),
              const SizedBox(height: 20),
              // Save / Cancel row
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: context.scheme.t2,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accent,
                        foregroundColor: context.scheme.tx,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.r12),
                        ),
                      ),
                      child: Text(_isEdit ? 'Update' : 'Save'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.scheme.s2,
        borderRadius: BorderRadius.circular(AppTheme.r8),
      ),
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: context.scheme.s3,
        iconEnabledColor: context.scheme.t3,
      ),
    );
  }
}
