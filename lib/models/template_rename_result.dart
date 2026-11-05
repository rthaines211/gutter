class TemplateRenameResult {
  const TemplateRenameResult({
    required this.issueId,
    required this.oldName,
    required this.newName,
    required this.conflict,
    required this.applied,
  });

  final String issueId;
  final String oldName;
  final String newName;
  final bool conflict;
  final bool applied;

  factory TemplateRenameResult.fromJson(Map<String, dynamic> json) =>
      TemplateRenameResult(
        issueId: json['issue_id'] as String? ?? '',
        oldName: json['old_name'] as String? ?? '',
        newName: json['new_name'] as String? ?? '',
        conflict: json['conflict'] as bool? ?? false,
        applied: json['applied'] as bool? ?? false,
      );
}
