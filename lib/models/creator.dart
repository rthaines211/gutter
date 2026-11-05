/// One role-tagged creator from ComicVine enrichment.
class Creator {
  final int id;
  final String name;
  final String role;

  const Creator({this.id = 0, required this.name, required this.role});

  factory Creator.fromJson(Map<String, dynamic> json) => Creator(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};
}
