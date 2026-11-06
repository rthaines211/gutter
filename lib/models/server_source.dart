import 'dart:convert';

enum SourceType {
  custom('Gutter'),
  opds('OPDS'),
  komga('Komga'),
  kavita('Kavita');

  const SourceType(this.label);

  /// The server software's name, as the Servers list shows it.
  final String label;
}

enum AuthType { none, basic, apiKey }

class ServerSource {
  final String id;
  final String name;
  final SourceType type;
  final String baseUrl;
  final AuthType authType;
  final String? username;
  final String? password;
  final String? apiKey;
  final bool isDefault;

  const ServerSource({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.authType,
    this.username,
    this.password,
    this.apiKey,
    this.isDefault = false,
  });

  factory ServerSource.createDefault({required String url}) {
    return ServerSource(
      id: 'default',
      name: 'My Server',
      type: SourceType.custom,
      baseUrl: url,
      authType: AuthType.none,
      isDefault: true,
    );
  }

  Map<String, String> get authHeaders {
    switch (authType) {
      case AuthType.none:
        return {};
      case AuthType.basic:
        final encoded = base64Encode(
          utf8.encode('${username ?? ''}:${password ?? ''}'),
        );
        return {'Authorization': 'Basic $encoded'};
      case AuthType.apiKey:
        return type == SourceType.komga || type == SourceType.kavita
            ? {'X-API-Key': apiKey ?? ''}
            : {'Authorization': 'Bearer ${apiKey ?? ''}'};
    }
  }

  ServerSource copyWith({
    String? name,
    String? baseUrl,
    AuthType? authType,
    String? username,
    String? password,
    String? apiKey,
  }) {
    return ServerSource(
      id: id,
      name: name ?? this.name,
      type: type,
      baseUrl: baseUrl ?? this.baseUrl,
      authType: authType ?? this.authType,
      username: username ?? this.username,
      password: password ?? this.password,
      apiKey: apiKey ?? this.apiKey,
      isDefault: isDefault,
    );
  }

  /// Serializes for SharedPreferences (non-sensitive fields only).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'base_url': baseUrl,
        'auth_type': authType.name,
        if (username != null) 'username': username,
        // password and apiKey stored separately in secure storage
        'is_default': isDefault,
      };

  factory ServerSource.fromJson(Map<String, dynamic> json) {
    return ServerSource(
      id: json['id'] as String,
      name: json['name'] as String,
      type: SourceType.values.byName(json['type'] as String),
      baseUrl: json['base_url'] as String,
      authType: AuthType.values.byName(json['auth_type'] as String),
      username: json['username'] as String?,
      password: json['password'] as String?,
      apiKey: json['api_key'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}
