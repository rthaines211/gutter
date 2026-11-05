// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mirror_database.dart';

// ignore_for_file: type=lint
class $SeriesRowsTable extends SeriesRows
    with TableInfo<$SeriesRowsTable, SeriesRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverSyncedAtMeta = const VerificationMeta(
    'coverSyncedAt',
  );
  @override
  late final GeneratedColumn<String> coverSyncedAt = GeneratedColumn<String>(
    'cover_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, updatedAt, coverSyncedAt, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeriesRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('cover_synced_at')) {
      context.handle(
        _coverSyncedAtMeta,
        coverSyncedAt.isAcceptableOrUnknown(
          data['cover_synced_at']!,
          _coverSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SeriesRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeriesRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      coverSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_synced_at'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $SeriesRowsTable createAlias(String alias) {
    return $SeriesRowsTable(attachedDatabase, alias);
  }
}

class SeriesRow extends DataClass implements Insertable<SeriesRow> {
  final String id;
  final String updatedAt;
  final String? coverSyncedAt;
  final String payload;
  const SeriesRow({
    required this.id,
    required this.updatedAt,
    this.coverSyncedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || coverSyncedAt != null) {
      map['cover_synced_at'] = Variable<String>(coverSyncedAt);
    }
    map['payload'] = Variable<String>(payload);
    return map;
  }

  SeriesRowsCompanion toCompanion(bool nullToAbsent) {
    return SeriesRowsCompanion(
      id: Value(id),
      updatedAt: Value(updatedAt),
      coverSyncedAt: coverSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(coverSyncedAt),
      payload: Value(payload),
    );
  }

  factory SeriesRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeriesRow(
      id: serializer.fromJson<String>(json['id']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      coverSyncedAt: serializer.fromJson<String?>(json['coverSyncedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'coverSyncedAt': serializer.toJson<String?>(coverSyncedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  SeriesRow copyWith({
    String? id,
    String? updatedAt,
    Value<String?> coverSyncedAt = const Value.absent(),
    String? payload,
  }) => SeriesRow(
    id: id ?? this.id,
    updatedAt: updatedAt ?? this.updatedAt,
    coverSyncedAt: coverSyncedAt.present
        ? coverSyncedAt.value
        : this.coverSyncedAt,
    payload: payload ?? this.payload,
  );
  SeriesRow copyWithCompanion(SeriesRowsCompanion data) {
    return SeriesRow(
      id: data.id.present ? data.id.value : this.id,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      coverSyncedAt: data.coverSyncedAt.present
          ? data.coverSyncedAt.value
          : this.coverSyncedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeriesRow(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('coverSyncedAt: $coverSyncedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, updatedAt, coverSyncedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeriesRow &&
          other.id == this.id &&
          other.updatedAt == this.updatedAt &&
          other.coverSyncedAt == this.coverSyncedAt &&
          other.payload == this.payload);
}

class SeriesRowsCompanion extends UpdateCompanion<SeriesRow> {
  final Value<String> id;
  final Value<String> updatedAt;
  final Value<String?> coverSyncedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const SeriesRowsCompanion({
    this.id = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.coverSyncedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeriesRowsCompanion.insert({
    required String id,
    required String updatedAt,
    this.coverSyncedAt = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       payload = Value(payload);
  static Insertable<SeriesRow> custom({
    Expression<String>? id,
    Expression<String>? updatedAt,
    Expression<String>? coverSyncedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (coverSyncedAt != null) 'cover_synced_at': coverSyncedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeriesRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? updatedAt,
    Value<String?>? coverSyncedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return SeriesRowsCompanion(
      id: id ?? this.id,
      updatedAt: updatedAt ?? this.updatedAt,
      coverSyncedAt: coverSyncedAt ?? this.coverSyncedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (coverSyncedAt.present) {
      map['cover_synced_at'] = Variable<String>(coverSyncedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesRowsCompanion(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('coverSyncedAt: $coverSyncedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IssueRowsTable extends IssueRows
    with TableInfo<$IssueRowsTable, IssueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IssueRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, seriesId, position, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'issue_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<IssueRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IssueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IssueRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $IssueRowsTable createAlias(String alias) {
    return $IssueRowsTable(attachedDatabase, alias);
  }
}

class IssueRow extends DataClass implements Insertable<IssueRow> {
  final String id;
  final String seriesId;
  final int position;
  final String payload;
  const IssueRow({
    required this.id,
    required this.seriesId,
    required this.position,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['series_id'] = Variable<String>(seriesId);
    map['position'] = Variable<int>(position);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  IssueRowsCompanion toCompanion(bool nullToAbsent) {
    return IssueRowsCompanion(
      id: Value(id),
      seriesId: Value(seriesId),
      position: Value(position),
      payload: Value(payload),
    );
  }

  factory IssueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IssueRow(
      id: serializer.fromJson<String>(json['id']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      position: serializer.fromJson<int>(json['position']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'seriesId': serializer.toJson<String>(seriesId),
      'position': serializer.toJson<int>(position),
      'payload': serializer.toJson<String>(payload),
    };
  }

  IssueRow copyWith({
    String? id,
    String? seriesId,
    int? position,
    String? payload,
  }) => IssueRow(
    id: id ?? this.id,
    seriesId: seriesId ?? this.seriesId,
    position: position ?? this.position,
    payload: payload ?? this.payload,
  );
  IssueRow copyWithCompanion(IssueRowsCompanion data) {
    return IssueRow(
      id: data.id.present ? data.id.value : this.id,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      position: data.position.present ? data.position.value : this.position,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IssueRow(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('position: $position, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, seriesId, position, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IssueRow &&
          other.id == this.id &&
          other.seriesId == this.seriesId &&
          other.position == this.position &&
          other.payload == this.payload);
}

class IssueRowsCompanion extends UpdateCompanion<IssueRow> {
  final Value<String> id;
  final Value<String> seriesId;
  final Value<int> position;
  final Value<String> payload;
  final Value<int> rowid;
  const IssueRowsCompanion({
    this.id = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.position = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IssueRowsCompanion.insert({
    required String id,
    required String seriesId,
    required int position,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       seriesId = Value(seriesId),
       position = Value(position),
       payload = Value(payload);
  static Insertable<IssueRow> custom({
    Expression<String>? id,
    Expression<String>? seriesId,
    Expression<int>? position,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seriesId != null) 'series_id': seriesId,
      if (position != null) 'position': position,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IssueRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? seriesId,
    Value<int>? position,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return IssueRowsCompanion(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      position: position ?? this.position,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IssueRowsCompanion(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('position: $position, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgressRowsTable extends ProgressRows
    with TableInfo<$ProgressRowsTable, ProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _comicIdMeta = const VerificationMeta(
    'comicId',
  );
  @override
  late final GeneratedColumn<String> comicId = GeneratedColumn<String>(
    'comic_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentPageMeta = const VerificationMeta(
    'currentPage',
  );
  @override
  late final GeneratedColumn<int> currentPage = GeneratedColumn<int>(
    'current_page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalPagesMeta = const VerificationMeta(
    'totalPages',
  );
  @override
  late final GeneratedColumn<int> totalPages = GeneratedColumn<int>(
    'total_pages',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chaptersMeta = const VerificationMeta(
    'chapters',
  );
  @override
  late final GeneratedColumn<String> chapters = GeneratedColumn<String>(
    'chapters',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    comicId,
    currentPage,
    totalPages,
    updatedAt,
    chapters,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progress_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('comic_id')) {
      context.handle(
        _comicIdMeta,
        comicId.isAcceptableOrUnknown(data['comic_id']!, _comicIdMeta),
      );
    } else if (isInserting) {
      context.missing(_comicIdMeta);
    }
    if (data.containsKey('current_page')) {
      context.handle(
        _currentPageMeta,
        currentPage.isAcceptableOrUnknown(
          data['current_page']!,
          _currentPageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentPageMeta);
    }
    if (data.containsKey('total_pages')) {
      context.handle(
        _totalPagesMeta,
        totalPages.isAcceptableOrUnknown(data['total_pages']!, _totalPagesMeta),
      );
    } else if (isInserting) {
      context.missing(_totalPagesMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('chapters')) {
      context.handle(
        _chaptersMeta,
        chapters.isAcceptableOrUnknown(data['chapters']!, _chaptersMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {comicId};
  @override
  ProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressRow(
      comicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}comic_id'],
      )!,
      currentPage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_page'],
      )!,
      totalPages: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_pages'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      chapters: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapters'],
      ),
    );
  }

  @override
  $ProgressRowsTable createAlias(String alias) {
    return $ProgressRowsTable(attachedDatabase, alias);
  }
}

class ProgressRow extends DataClass implements Insertable<ProgressRow> {
  final String comicId;
  final int currentPage;
  final int totalPages;
  final String updatedAt;
  final String? chapters;
  const ProgressRow({
    required this.comicId,
    required this.currentPage,
    required this.totalPages,
    required this.updatedAt,
    this.chapters,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['comic_id'] = Variable<String>(comicId);
    map['current_page'] = Variable<int>(currentPage);
    map['total_pages'] = Variable<int>(totalPages);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || chapters != null) {
      map['chapters'] = Variable<String>(chapters);
    }
    return map;
  }

  ProgressRowsCompanion toCompanion(bool nullToAbsent) {
    return ProgressRowsCompanion(
      comicId: Value(comicId),
      currentPage: Value(currentPage),
      totalPages: Value(totalPages),
      updatedAt: Value(updatedAt),
      chapters: chapters == null && nullToAbsent
          ? const Value.absent()
          : Value(chapters),
    );
  }

  factory ProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressRow(
      comicId: serializer.fromJson<String>(json['comicId']),
      currentPage: serializer.fromJson<int>(json['currentPage']),
      totalPages: serializer.fromJson<int>(json['totalPages']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      chapters: serializer.fromJson<String?>(json['chapters']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'comicId': serializer.toJson<String>(comicId),
      'currentPage': serializer.toJson<int>(currentPage),
      'totalPages': serializer.toJson<int>(totalPages),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'chapters': serializer.toJson<String?>(chapters),
    };
  }

  ProgressRow copyWith({
    String? comicId,
    int? currentPage,
    int? totalPages,
    String? updatedAt,
    Value<String?> chapters = const Value.absent(),
  }) => ProgressRow(
    comicId: comicId ?? this.comicId,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    updatedAt: updatedAt ?? this.updatedAt,
    chapters: chapters.present ? chapters.value : this.chapters,
  );
  ProgressRow copyWithCompanion(ProgressRowsCompanion data) {
    return ProgressRow(
      comicId: data.comicId.present ? data.comicId.value : this.comicId,
      currentPage: data.currentPage.present
          ? data.currentPage.value
          : this.currentPage,
      totalPages: data.totalPages.present
          ? data.totalPages.value
          : this.totalPages,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      chapters: data.chapters.present ? data.chapters.value : this.chapters,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressRow(')
          ..write('comicId: $comicId, ')
          ..write('currentPage: $currentPage, ')
          ..write('totalPages: $totalPages, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('chapters: $chapters')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(comicId, currentPage, totalPages, updatedAt, chapters);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressRow &&
          other.comicId == this.comicId &&
          other.currentPage == this.currentPage &&
          other.totalPages == this.totalPages &&
          other.updatedAt == this.updatedAt &&
          other.chapters == this.chapters);
}

class ProgressRowsCompanion extends UpdateCompanion<ProgressRow> {
  final Value<String> comicId;
  final Value<int> currentPage;
  final Value<int> totalPages;
  final Value<String> updatedAt;
  final Value<String?> chapters;
  final Value<int> rowid;
  const ProgressRowsCompanion({
    this.comicId = const Value.absent(),
    this.currentPage = const Value.absent(),
    this.totalPages = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.chapters = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressRowsCompanion.insert({
    required String comicId,
    required int currentPage,
    required int totalPages,
    required String updatedAt,
    this.chapters = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : comicId = Value(comicId),
       currentPage = Value(currentPage),
       totalPages = Value(totalPages),
       updatedAt = Value(updatedAt);
  static Insertable<ProgressRow> custom({
    Expression<String>? comicId,
    Expression<int>? currentPage,
    Expression<int>? totalPages,
    Expression<String>? updatedAt,
    Expression<String>? chapters,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (comicId != null) 'comic_id': comicId,
      if (currentPage != null) 'current_page': currentPage,
      if (totalPages != null) 'total_pages': totalPages,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (chapters != null) 'chapters': chapters,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressRowsCompanion copyWith({
    Value<String>? comicId,
    Value<int>? currentPage,
    Value<int>? totalPages,
    Value<String>? updatedAt,
    Value<String?>? chapters,
    Value<int>? rowid,
  }) {
    return ProgressRowsCompanion(
      comicId: comicId ?? this.comicId,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      updatedAt: updatedAt ?? this.updatedAt,
      chapters: chapters ?? this.chapters,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (comicId.present) {
      map['comic_id'] = Variable<String>(comicId.value);
    }
    if (currentPage.present) {
      map['current_page'] = Variable<int>(currentPage.value);
    }
    if (totalPages.present) {
      map['total_pages'] = Variable<int>(totalPages.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (chapters.present) {
      map['chapters'] = Variable<String>(chapters.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressRowsCompanion(')
          ..write('comicId: $comicId, ')
          ..write('currentPage: $currentPage, ')
          ..write('totalPages: $totalPages, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('chapters: $chapters, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String key;
  final String value;
  const SyncStateData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(key: Value(key), value: Value(value));
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncStateData copyWith({String? key, String? value}) =>
      SyncStateData(key: key ?? this.key, value: value ?? this.value);
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncStateData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueRowsTable extends QueueRows
    with TableInfo<$QueueRowsTable, QueueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('bookmark'),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#FFB74D'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    icon,
    color,
    position,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $QueueRowsTable createAlias(String alias) {
    return $QueueRowsTable(attachedDatabase, alias);
  }
}

class QueueRow extends DataClass implements Insertable<QueueRow> {
  final String id;
  final String name;
  final String icon;
  final String color;
  final int position;
  final String createdAt;
  final String updatedAt;
  const QueueRow({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['color'] = Variable<String>(color);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  QueueRowsCompanion toCompanion(bool nullToAbsent) {
    return QueueRowsCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      color: Value(color),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory QueueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      color: serializer.fromJson<String>(json['color']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'color': serializer.toJson<String>(color),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  QueueRow copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
    int? position,
    String? createdAt,
    String? updatedAt,
  }) => QueueRow(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  QueueRow copyWithCompanion(QueueRowsCompanion data) {
    return QueueRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, icon, color, position, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class QueueRowsCompanion extends UpdateCompanion<QueueRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<String> color;
  final Value<int> position;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const QueueRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueueRowsCompanion.insert({
    required String id,
    required String name,
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.position = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<QueueRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<String>? color,
    Expression<int>? position,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueueRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<String>? color,
    Value<int>? position,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return QueueRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueItemRowsTable extends QueueItemRows
    with TableInfo<$QueueItemRowsTable, QueueItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueItemRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _queueIdMeta = const VerificationMeta(
    'queueId',
  );
  @override
  late final GeneratedColumn<String> queueId = GeneratedColumn<String>(
    'queue_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [queueId, seriesId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_item_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('queue_id')) {
      context.handle(
        _queueIdMeta,
        queueId.isAcceptableOrUnknown(data['queue_id']!, _queueIdMeta),
      );
    } else if (isInserting) {
      context.missing(_queueIdMeta);
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {queueId, seriesId};
  @override
  QueueItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueItemRow(
      queueId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $QueueItemRowsTable createAlias(String alias) {
    return $QueueItemRowsTable(attachedDatabase, alias);
  }
}

class QueueItemRow extends DataClass implements Insertable<QueueItemRow> {
  final String queueId;
  final String seriesId;
  final int position;
  const QueueItemRow({
    required this.queueId,
    required this.seriesId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['queue_id'] = Variable<String>(queueId);
    map['series_id'] = Variable<String>(seriesId);
    map['position'] = Variable<int>(position);
    return map;
  }

  QueueItemRowsCompanion toCompanion(bool nullToAbsent) {
    return QueueItemRowsCompanion(
      queueId: Value(queueId),
      seriesId: Value(seriesId),
      position: Value(position),
    );
  }

  factory QueueItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueItemRow(
      queueId: serializer.fromJson<String>(json['queueId']),
      seriesId: serializer.fromJson<String>(json['seriesId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'queueId': serializer.toJson<String>(queueId),
      'seriesId': serializer.toJson<String>(seriesId),
      'position': serializer.toJson<int>(position),
    };
  }

  QueueItemRow copyWith({String? queueId, String? seriesId, int? position}) =>
      QueueItemRow(
        queueId: queueId ?? this.queueId,
        seriesId: seriesId ?? this.seriesId,
        position: position ?? this.position,
      );
  QueueItemRow copyWithCompanion(QueueItemRowsCompanion data) {
    return QueueItemRow(
      queueId: data.queueId.present ? data.queueId.value : this.queueId,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueItemRow(')
          ..write('queueId: $queueId, ')
          ..write('seriesId: $seriesId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(queueId, seriesId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueItemRow &&
          other.queueId == this.queueId &&
          other.seriesId == this.seriesId &&
          other.position == this.position);
}

class QueueItemRowsCompanion extends UpdateCompanion<QueueItemRow> {
  final Value<String> queueId;
  final Value<String> seriesId;
  final Value<int> position;
  final Value<int> rowid;
  const QueueItemRowsCompanion({
    this.queueId = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueueItemRowsCompanion.insert({
    required String queueId,
    required String seriesId,
    required int position,
    this.rowid = const Value.absent(),
  }) : queueId = Value(queueId),
       seriesId = Value(seriesId),
       position = Value(position);
  static Insertable<QueueItemRow> custom({
    Expression<String>? queueId,
    Expression<String>? seriesId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (queueId != null) 'queue_id': queueId,
      if (seriesId != null) 'series_id': seriesId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueueItemRowsCompanion copyWith({
    Value<String>? queueId,
    Value<String>? seriesId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return QueueItemRowsCompanion(
      queueId: queueId ?? this.queueId,
      seriesId: seriesId ?? this.seriesId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (queueId.present) {
      map['queue_id'] = Variable<String>(queueId.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueItemRowsCompanion(')
          ..write('queueId: $queueId, ')
          ..write('seriesId: $seriesId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ArcRowsTable extends ArcRows with TableInfo<$ArcRowsTable, ArcRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArcRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _selfContainedMeta = const VerificationMeta(
    'selfContained',
  );
  @override
  late final GeneratedColumn<int> selfContained = GeneratedColumn<int>(
    'self_contained',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<int> total = GeneratedColumn<int>(
    'total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('mylar'),
  );
  static const VerificationMeta _publisherMeta = const VerificationMeta(
    'publisher',
  );
  @override
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _startYearMeta = const VerificationMeta(
    'startYear',
  );
  @override
  late final GeneratedColumn<int> startYear = GeneratedColumn<int>(
    'start_year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _endYearMeta = const VerificationMeta(
    'endYear',
  );
  @override
  late final GeneratedColumn<int> endYear = GeneratedColumn<int>(
    'end_year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    imageUrl,
    selfContained,
    total,
    source,
    publisher,
    startYear,
    endYear,
    description,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'arc_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArcRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('self_contained')) {
      context.handle(
        _selfContainedMeta,
        selfContained.isAcceptableOrUnknown(
          data['self_contained']!,
          _selfContainedMeta,
        ),
      );
    }
    if (data.containsKey('total')) {
      context.handle(
        _totalMeta,
        total.isAcceptableOrUnknown(data['total']!, _totalMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('publisher')) {
      context.handle(
        _publisherMeta,
        publisher.isAcceptableOrUnknown(data['publisher']!, _publisherMeta),
      );
    }
    if (data.containsKey('start_year')) {
      context.handle(
        _startYearMeta,
        startYear.isAcceptableOrUnknown(data['start_year']!, _startYearMeta),
      );
    }
    if (data.containsKey('end_year')) {
      context.handle(
        _endYearMeta,
        endYear.isAcceptableOrUnknown(data['end_year']!, _endYearMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArcRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArcRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      )!,
      selfContained: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}self_contained'],
      ),
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      )!,
      startYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_year'],
      )!,
      endYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_year'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
    );
  }

  @override
  $ArcRowsTable createAlias(String alias) {
    return $ArcRowsTable(attachedDatabase, alias);
  }
}

class ArcRow extends DataClass implements Insertable<ArcRow> {
  final String id;
  final String name;
  final String imageUrl;
  final int? selfContained;
  final int total;
  final String source;
  final String publisher;
  final int startYear;
  final int endYear;
  final String description;
  const ArcRow({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.selfContained,
    required this.total,
    required this.source,
    required this.publisher,
    required this.startYear,
    required this.endYear,
    required this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['image_url'] = Variable<String>(imageUrl);
    if (!nullToAbsent || selfContained != null) {
      map['self_contained'] = Variable<int>(selfContained);
    }
    map['total'] = Variable<int>(total);
    map['source'] = Variable<String>(source);
    map['publisher'] = Variable<String>(publisher);
    map['start_year'] = Variable<int>(startYear);
    map['end_year'] = Variable<int>(endYear);
    map['description'] = Variable<String>(description);
    return map;
  }

  ArcRowsCompanion toCompanion(bool nullToAbsent) {
    return ArcRowsCompanion(
      id: Value(id),
      name: Value(name),
      imageUrl: Value(imageUrl),
      selfContained: selfContained == null && nullToAbsent
          ? const Value.absent()
          : Value(selfContained),
      total: Value(total),
      source: Value(source),
      publisher: Value(publisher),
      startYear: Value(startYear),
      endYear: Value(endYear),
      description: Value(description),
    );
  }

  factory ArcRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArcRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      imageUrl: serializer.fromJson<String>(json['imageUrl']),
      selfContained: serializer.fromJson<int?>(json['selfContained']),
      total: serializer.fromJson<int>(json['total']),
      source: serializer.fromJson<String>(json['source']),
      publisher: serializer.fromJson<String>(json['publisher']),
      startYear: serializer.fromJson<int>(json['startYear']),
      endYear: serializer.fromJson<int>(json['endYear']),
      description: serializer.fromJson<String>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'imageUrl': serializer.toJson<String>(imageUrl),
      'selfContained': serializer.toJson<int?>(selfContained),
      'total': serializer.toJson<int>(total),
      'source': serializer.toJson<String>(source),
      'publisher': serializer.toJson<String>(publisher),
      'startYear': serializer.toJson<int>(startYear),
      'endYear': serializer.toJson<int>(endYear),
      'description': serializer.toJson<String>(description),
    };
  }

  ArcRow copyWith({
    String? id,
    String? name,
    String? imageUrl,
    Value<int?> selfContained = const Value.absent(),
    int? total,
    String? source,
    String? publisher,
    int? startYear,
    int? endYear,
    String? description,
  }) => ArcRow(
    id: id ?? this.id,
    name: name ?? this.name,
    imageUrl: imageUrl ?? this.imageUrl,
    selfContained: selfContained.present
        ? selfContained.value
        : this.selfContained,
    total: total ?? this.total,
    source: source ?? this.source,
    publisher: publisher ?? this.publisher,
    startYear: startYear ?? this.startYear,
    endYear: endYear ?? this.endYear,
    description: description ?? this.description,
  );
  ArcRow copyWithCompanion(ArcRowsCompanion data) {
    return ArcRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      selfContained: data.selfContained.present
          ? data.selfContained.value
          : this.selfContained,
      total: data.total.present ? data.total.value : this.total,
      source: data.source.present ? data.source.value : this.source,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      startYear: data.startYear.present ? data.startYear.value : this.startYear,
      endYear: data.endYear.present ? data.endYear.value : this.endYear,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArcRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('selfContained: $selfContained, ')
          ..write('total: $total, ')
          ..write('source: $source, ')
          ..write('publisher: $publisher, ')
          ..write('startYear: $startYear, ')
          ..write('endYear: $endYear, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    imageUrl,
    selfContained,
    total,
    source,
    publisher,
    startYear,
    endYear,
    description,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArcRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.imageUrl == this.imageUrl &&
          other.selfContained == this.selfContained &&
          other.total == this.total &&
          other.source == this.source &&
          other.publisher == this.publisher &&
          other.startYear == this.startYear &&
          other.endYear == this.endYear &&
          other.description == this.description);
}

class ArcRowsCompanion extends UpdateCompanion<ArcRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> imageUrl;
  final Value<int?> selfContained;
  final Value<int> total;
  final Value<String> source;
  final Value<String> publisher;
  final Value<int> startYear;
  final Value<int> endYear;
  final Value<String> description;
  final Value<int> rowid;
  const ArcRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.selfContained = const Value.absent(),
    this.total = const Value.absent(),
    this.source = const Value.absent(),
    this.publisher = const Value.absent(),
    this.startYear = const Value.absent(),
    this.endYear = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArcRowsCompanion.insert({
    required String id,
    required String name,
    this.imageUrl = const Value.absent(),
    this.selfContained = const Value.absent(),
    this.total = const Value.absent(),
    this.source = const Value.absent(),
    this.publisher = const Value.absent(),
    this.startYear = const Value.absent(),
    this.endYear = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ArcRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? imageUrl,
    Expression<int>? selfContained,
    Expression<int>? total,
    Expression<String>? source,
    Expression<String>? publisher,
    Expression<int>? startYear,
    Expression<int>? endYear,
    Expression<String>? description,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (imageUrl != null) 'image_url': imageUrl,
      if (selfContained != null) 'self_contained': selfContained,
      if (total != null) 'total': total,
      if (source != null) 'source': source,
      if (publisher != null) 'publisher': publisher,
      if (startYear != null) 'start_year': startYear,
      if (endYear != null) 'end_year': endYear,
      if (description != null) 'description': description,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArcRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? imageUrl,
    Value<int?>? selfContained,
    Value<int>? total,
    Value<String>? source,
    Value<String>? publisher,
    Value<int>? startYear,
    Value<int>? endYear,
    Value<String>? description,
    Value<int>? rowid,
  }) {
    return ArcRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      selfContained: selfContained ?? this.selfContained,
      total: total ?? this.total,
      source: source ?? this.source,
      publisher: publisher ?? this.publisher,
      startYear: startYear ?? this.startYear,
      endYear: endYear ?? this.endYear,
      description: description ?? this.description,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (selfContained.present) {
      map['self_contained'] = Variable<int>(selfContained.value);
    }
    if (total.present) {
      map['total'] = Variable<int>(total.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (startYear.present) {
      map['start_year'] = Variable<int>(startYear.value);
    }
    if (endYear.present) {
      map['end_year'] = Variable<int>(endYear.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArcRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('selfContained: $selfContained, ')
          ..write('total: $total, ')
          ..write('source: $source, ')
          ..write('publisher: $publisher, ')
          ..write('startYear: $startYear, ')
          ..write('endYear: $endYear, ')
          ..write('description: $description, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ArcItemRowsTable extends ArcItemRows
    with TableInfo<$ArcItemRowsTable, ArcItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArcItemRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _arcIdMeta = const VerificationMeta('arcId');
  @override
  late final GeneratedColumn<String> arcId = GeneratedColumn<String>(
    'arc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _issueIdMeta = const VerificationMeta(
    'issueId',
  );
  @override
  late final GeneratedColumn<String> issueId = GeneratedColumn<String>(
    'issue_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [arcId, issueId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'arc_item_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArcItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('arc_id')) {
      context.handle(
        _arcIdMeta,
        arcId.isAcceptableOrUnknown(data['arc_id']!, _arcIdMeta),
      );
    } else if (isInserting) {
      context.missing(_arcIdMeta);
    }
    if (data.containsKey('issue_id')) {
      context.handle(
        _issueIdMeta,
        issueId.isAcceptableOrUnknown(data['issue_id']!, _issueIdMeta),
      );
    } else if (isInserting) {
      context.missing(_issueIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {arcId, issueId};
  @override
  ArcItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArcItemRow(
      arcId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}arc_id'],
      )!,
      issueId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issue_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $ArcItemRowsTable createAlias(String alias) {
    return $ArcItemRowsTable(attachedDatabase, alias);
  }
}

class ArcItemRow extends DataClass implements Insertable<ArcItemRow> {
  final String arcId;
  final String issueId;
  final int position;
  const ArcItemRow({
    required this.arcId,
    required this.issueId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['arc_id'] = Variable<String>(arcId);
    map['issue_id'] = Variable<String>(issueId);
    map['position'] = Variable<int>(position);
    return map;
  }

  ArcItemRowsCompanion toCompanion(bool nullToAbsent) {
    return ArcItemRowsCompanion(
      arcId: Value(arcId),
      issueId: Value(issueId),
      position: Value(position),
    );
  }

  factory ArcItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArcItemRow(
      arcId: serializer.fromJson<String>(json['arcId']),
      issueId: serializer.fromJson<String>(json['issueId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'arcId': serializer.toJson<String>(arcId),
      'issueId': serializer.toJson<String>(issueId),
      'position': serializer.toJson<int>(position),
    };
  }

  ArcItemRow copyWith({String? arcId, String? issueId, int? position}) =>
      ArcItemRow(
        arcId: arcId ?? this.arcId,
        issueId: issueId ?? this.issueId,
        position: position ?? this.position,
      );
  ArcItemRow copyWithCompanion(ArcItemRowsCompanion data) {
    return ArcItemRow(
      arcId: data.arcId.present ? data.arcId.value : this.arcId,
      issueId: data.issueId.present ? data.issueId.value : this.issueId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArcItemRow(')
          ..write('arcId: $arcId, ')
          ..write('issueId: $issueId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(arcId, issueId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArcItemRow &&
          other.arcId == this.arcId &&
          other.issueId == this.issueId &&
          other.position == this.position);
}

class ArcItemRowsCompanion extends UpdateCompanion<ArcItemRow> {
  final Value<String> arcId;
  final Value<String> issueId;
  final Value<int> position;
  final Value<int> rowid;
  const ArcItemRowsCompanion({
    this.arcId = const Value.absent(),
    this.issueId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ArcItemRowsCompanion.insert({
    required String arcId,
    required String issueId,
    required int position,
    this.rowid = const Value.absent(),
  }) : arcId = Value(arcId),
       issueId = Value(issueId),
       position = Value(position);
  static Insertable<ArcItemRow> custom({
    Expression<String>? arcId,
    Expression<String>? issueId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (arcId != null) 'arc_id': arcId,
      if (issueId != null) 'issue_id': issueId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ArcItemRowsCompanion copyWith({
    Value<String>? arcId,
    Value<String>? issueId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return ArcItemRowsCompanion(
      arcId: arcId ?? this.arcId,
      issueId: issueId ?? this.issueId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (arcId.present) {
      map['arc_id'] = Variable<String>(arcId.value);
    }
    if (issueId.present) {
      map['issue_id'] = Variable<String>(issueId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArcItemRowsCompanion(')
          ..write('arcId: $arcId, ')
          ..write('issueId: $issueId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MirrorDatabase extends GeneratedDatabase {
  _$MirrorDatabase(QueryExecutor e) : super(e);
  $MirrorDatabaseManager get managers => $MirrorDatabaseManager(this);
  late final $SeriesRowsTable seriesRows = $SeriesRowsTable(this);
  late final $IssueRowsTable issueRows = $IssueRowsTable(this);
  late final $ProgressRowsTable progressRows = $ProgressRowsTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $QueueRowsTable queueRows = $QueueRowsTable(this);
  late final $QueueItemRowsTable queueItemRows = $QueueItemRowsTable(this);
  late final $ArcRowsTable arcRows = $ArcRowsTable(this);
  late final $ArcItemRowsTable arcItemRows = $ArcItemRowsTable(this);
  late final Index idxIssueSeries = Index(
    'idx_issue_series',
    'CREATE INDEX idx_issue_series ON issue_rows (series_id)',
  );
  late final Index idxQueueItemQueue = Index(
    'idx_queue_item_queue',
    'CREATE INDEX idx_queue_item_queue ON queue_item_rows (queue_id)',
  );
  late final Index idxArcItemArc = Index(
    'idx_arc_item_arc',
    'CREATE INDEX idx_arc_item_arc ON arc_item_rows (arc_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    seriesRows,
    issueRows,
    progressRows,
    syncState,
    queueRows,
    queueItemRows,
    arcRows,
    arcItemRows,
    idxIssueSeries,
    idxQueueItemQueue,
    idxArcItemArc,
  ];
}

typedef $$SeriesRowsTableCreateCompanionBuilder =
    SeriesRowsCompanion Function({
      required String id,
      required String updatedAt,
      Value<String?> coverSyncedAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$SeriesRowsTableUpdateCompanionBuilder =
    SeriesRowsCompanion Function({
      Value<String> id,
      Value<String> updatedAt,
      Value<String?> coverSyncedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$SeriesRowsTableFilterComposer
    extends Composer<_$MirrorDatabase, $SeriesRowsTable> {
  $$SeriesRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverSyncedAt => $composableBuilder(
    column: $table.coverSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesRowsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $SeriesRowsTable> {
  $$SeriesRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverSyncedAt => $composableBuilder(
    column: $table.coverSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesRowsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $SeriesRowsTable> {
  $$SeriesRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get coverSyncedAt => $composableBuilder(
    column: $table.coverSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$SeriesRowsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $SeriesRowsTable,
          SeriesRow,
          $$SeriesRowsTableFilterComposer,
          $$SeriesRowsTableOrderingComposer,
          $$SeriesRowsTableAnnotationComposer,
          $$SeriesRowsTableCreateCompanionBuilder,
          $$SeriesRowsTableUpdateCompanionBuilder,
          (
            SeriesRow,
            BaseReferences<_$MirrorDatabase, $SeriesRowsTable, SeriesRow>,
          ),
          SeriesRow,
          PrefetchHooks Function()
        > {
  $$SeriesRowsTableTableManager(_$MirrorDatabase db, $SeriesRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> coverSyncedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesRowsCompanion(
                id: id,
                updatedAt: updatedAt,
                coverSyncedAt: coverSyncedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String updatedAt,
                Value<String?> coverSyncedAt = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => SeriesRowsCompanion.insert(
                id: id,
                updatedAt: updatedAt,
                coverSyncedAt: coverSyncedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $SeriesRowsTable,
      SeriesRow,
      $$SeriesRowsTableFilterComposer,
      $$SeriesRowsTableOrderingComposer,
      $$SeriesRowsTableAnnotationComposer,
      $$SeriesRowsTableCreateCompanionBuilder,
      $$SeriesRowsTableUpdateCompanionBuilder,
      (
        SeriesRow,
        BaseReferences<_$MirrorDatabase, $SeriesRowsTable, SeriesRow>,
      ),
      SeriesRow,
      PrefetchHooks Function()
    >;
typedef $$IssueRowsTableCreateCompanionBuilder =
    IssueRowsCompanion Function({
      required String id,
      required String seriesId,
      required int position,
      required String payload,
      Value<int> rowid,
    });
typedef $$IssueRowsTableUpdateCompanionBuilder =
    IssueRowsCompanion Function({
      Value<String> id,
      Value<String> seriesId,
      Value<int> position,
      Value<String> payload,
      Value<int> rowid,
    });

class $$IssueRowsTableFilterComposer
    extends Composer<_$MirrorDatabase, $IssueRowsTable> {
  $$IssueRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IssueRowsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $IssueRowsTable> {
  $$IssueRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IssueRowsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $IssueRowsTable> {
  $$IssueRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$IssueRowsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $IssueRowsTable,
          IssueRow,
          $$IssueRowsTableFilterComposer,
          $$IssueRowsTableOrderingComposer,
          $$IssueRowsTableAnnotationComposer,
          $$IssueRowsTableCreateCompanionBuilder,
          $$IssueRowsTableUpdateCompanionBuilder,
          (
            IssueRow,
            BaseReferences<_$MirrorDatabase, $IssueRowsTable, IssueRow>,
          ),
          IssueRow,
          PrefetchHooks Function()
        > {
  $$IssueRowsTableTableManager(_$MirrorDatabase db, $IssueRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IssueRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IssueRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IssueRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IssueRowsCompanion(
                id: id,
                seriesId: seriesId,
                position: position,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String seriesId,
                required int position,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => IssueRowsCompanion.insert(
                id: id,
                seriesId: seriesId,
                position: position,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IssueRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $IssueRowsTable,
      IssueRow,
      $$IssueRowsTableFilterComposer,
      $$IssueRowsTableOrderingComposer,
      $$IssueRowsTableAnnotationComposer,
      $$IssueRowsTableCreateCompanionBuilder,
      $$IssueRowsTableUpdateCompanionBuilder,
      (IssueRow, BaseReferences<_$MirrorDatabase, $IssueRowsTable, IssueRow>),
      IssueRow,
      PrefetchHooks Function()
    >;
typedef $$ProgressRowsTableCreateCompanionBuilder =
    ProgressRowsCompanion Function({
      required String comicId,
      required int currentPage,
      required int totalPages,
      required String updatedAt,
      Value<String?> chapters,
      Value<int> rowid,
    });
typedef $$ProgressRowsTableUpdateCompanionBuilder =
    ProgressRowsCompanion Function({
      Value<String> comicId,
      Value<int> currentPage,
      Value<int> totalPages,
      Value<String> updatedAt,
      Value<String?> chapters,
      Value<int> rowid,
    });

class $$ProgressRowsTableFilterComposer
    extends Composer<_$MirrorDatabase, $ProgressRowsTable> {
  $$ProgressRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get comicId => $composableBuilder(
    column: $table.comicId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentPage => $composableBuilder(
    column: $table.currentPage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapters => $composableBuilder(
    column: $table.chapters,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgressRowsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $ProgressRowsTable> {
  $$ProgressRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get comicId => $composableBuilder(
    column: $table.comicId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentPage => $composableBuilder(
    column: $table.currentPage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapters => $composableBuilder(
    column: $table.chapters,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgressRowsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $ProgressRowsTable> {
  $$ProgressRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get comicId =>
      $composableBuilder(column: $table.comicId, builder: (column) => column);

  GeneratedColumn<int> get currentPage => $composableBuilder(
    column: $table.currentPage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get chapters =>
      $composableBuilder(column: $table.chapters, builder: (column) => column);
}

class $$ProgressRowsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $ProgressRowsTable,
          ProgressRow,
          $$ProgressRowsTableFilterComposer,
          $$ProgressRowsTableOrderingComposer,
          $$ProgressRowsTableAnnotationComposer,
          $$ProgressRowsTableCreateCompanionBuilder,
          $$ProgressRowsTableUpdateCompanionBuilder,
          (
            ProgressRow,
            BaseReferences<_$MirrorDatabase, $ProgressRowsTable, ProgressRow>,
          ),
          ProgressRow,
          PrefetchHooks Function()
        > {
  $$ProgressRowsTableTableManager(_$MirrorDatabase db, $ProgressRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgressRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgressRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> comicId = const Value.absent(),
                Value<int> currentPage = const Value.absent(),
                Value<int> totalPages = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> chapters = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressRowsCompanion(
                comicId: comicId,
                currentPage: currentPage,
                totalPages: totalPages,
                updatedAt: updatedAt,
                chapters: chapters,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String comicId,
                required int currentPage,
                required int totalPages,
                required String updatedAt,
                Value<String?> chapters = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressRowsCompanion.insert(
                comicId: comicId,
                currentPage: currentPage,
                totalPages: totalPages,
                updatedAt: updatedAt,
                chapters: chapters,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgressRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $ProgressRowsTable,
      ProgressRow,
      $$ProgressRowsTableFilterComposer,
      $$ProgressRowsTableOrderingComposer,
      $$ProgressRowsTableAnnotationComposer,
      $$ProgressRowsTableCreateCompanionBuilder,
      $$ProgressRowsTableUpdateCompanionBuilder,
      (
        ProgressRow,
        BaseReferences<_$MirrorDatabase, $ProgressRowsTable, ProgressRow>,
      ),
      ProgressRow,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$MirrorDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$MirrorDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$MirrorDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$MirrorDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$MirrorDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$QueueRowsTableCreateCompanionBuilder =
    QueueRowsCompanion Function({
      required String id,
      required String name,
      Value<String> icon,
      Value<String> color,
      Value<int> position,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$QueueRowsTableUpdateCompanionBuilder =
    QueueRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> icon,
      Value<String> color,
      Value<int> position,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$QueueRowsTableFilterComposer
    extends Composer<_$MirrorDatabase, $QueueRowsTable> {
  $$QueueRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueRowsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $QueueRowsTable> {
  $$QueueRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueRowsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $QueueRowsTable> {
  $$QueueRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$QueueRowsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $QueueRowsTable,
          QueueRow,
          $$QueueRowsTableFilterComposer,
          $$QueueRowsTableOrderingComposer,
          $$QueueRowsTableAnnotationComposer,
          $$QueueRowsTableCreateCompanionBuilder,
          $$QueueRowsTableUpdateCompanionBuilder,
          (
            QueueRow,
            BaseReferences<_$MirrorDatabase, $QueueRowsTable, QueueRow>,
          ),
          QueueRow,
          PrefetchHooks Function()
        > {
  $$QueueRowsTableTableManager(_$MirrorDatabase db, $QueueRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueueRowsCompanion(
                id: id,
                name: name,
                icon: icon,
                color: color,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int> position = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => QueueRowsCompanion.insert(
                id: id,
                name: name,
                icon: icon,
                color: color,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $QueueRowsTable,
      QueueRow,
      $$QueueRowsTableFilterComposer,
      $$QueueRowsTableOrderingComposer,
      $$QueueRowsTableAnnotationComposer,
      $$QueueRowsTableCreateCompanionBuilder,
      $$QueueRowsTableUpdateCompanionBuilder,
      (QueueRow, BaseReferences<_$MirrorDatabase, $QueueRowsTable, QueueRow>),
      QueueRow,
      PrefetchHooks Function()
    >;
typedef $$QueueItemRowsTableCreateCompanionBuilder =
    QueueItemRowsCompanion Function({
      required String queueId,
      required String seriesId,
      required int position,
      Value<int> rowid,
    });
typedef $$QueueItemRowsTableUpdateCompanionBuilder =
    QueueItemRowsCompanion Function({
      Value<String> queueId,
      Value<String> seriesId,
      Value<int> position,
      Value<int> rowid,
    });

class $$QueueItemRowsTableFilterComposer
    extends Composer<_$MirrorDatabase, $QueueItemRowsTable> {
  $$QueueItemRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueItemRowsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $QueueItemRowsTable> {
  $$QueueItemRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get queueId => $composableBuilder(
    column: $table.queueId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueItemRowsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $QueueItemRowsTable> {
  $$QueueItemRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get queueId =>
      $composableBuilder(column: $table.queueId, builder: (column) => column);

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$QueueItemRowsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $QueueItemRowsTable,
          QueueItemRow,
          $$QueueItemRowsTableFilterComposer,
          $$QueueItemRowsTableOrderingComposer,
          $$QueueItemRowsTableAnnotationComposer,
          $$QueueItemRowsTableCreateCompanionBuilder,
          $$QueueItemRowsTableUpdateCompanionBuilder,
          (
            QueueItemRow,
            BaseReferences<_$MirrorDatabase, $QueueItemRowsTable, QueueItemRow>,
          ),
          QueueItemRow,
          PrefetchHooks Function()
        > {
  $$QueueItemRowsTableTableManager(
    _$MirrorDatabase db,
    $QueueItemRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueItemRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueItemRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueItemRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> queueId = const Value.absent(),
                Value<String> seriesId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueueItemRowsCompanion(
                queueId: queueId,
                seriesId: seriesId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String queueId,
                required String seriesId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => QueueItemRowsCompanion.insert(
                queueId: queueId,
                seriesId: seriesId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueItemRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $QueueItemRowsTable,
      QueueItemRow,
      $$QueueItemRowsTableFilterComposer,
      $$QueueItemRowsTableOrderingComposer,
      $$QueueItemRowsTableAnnotationComposer,
      $$QueueItemRowsTableCreateCompanionBuilder,
      $$QueueItemRowsTableUpdateCompanionBuilder,
      (
        QueueItemRow,
        BaseReferences<_$MirrorDatabase, $QueueItemRowsTable, QueueItemRow>,
      ),
      QueueItemRow,
      PrefetchHooks Function()
    >;
typedef $$ArcRowsTableCreateCompanionBuilder =
    ArcRowsCompanion Function({
      required String id,
      required String name,
      Value<String> imageUrl,
      Value<int?> selfContained,
      Value<int> total,
      Value<String> source,
      Value<String> publisher,
      Value<int> startYear,
      Value<int> endYear,
      Value<String> description,
      Value<int> rowid,
    });
typedef $$ArcRowsTableUpdateCompanionBuilder =
    ArcRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> imageUrl,
      Value<int?> selfContained,
      Value<int> total,
      Value<String> source,
      Value<String> publisher,
      Value<int> startYear,
      Value<int> endYear,
      Value<String> description,
      Value<int> rowid,
    });

class $$ArcRowsTableFilterComposer
    extends Composer<_$MirrorDatabase, $ArcRowsTable> {
  $$ArcRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get selfContained => $composableBuilder(
    column: $table.selfContained,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startYear => $composableBuilder(
    column: $table.startYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endYear => $composableBuilder(
    column: $table.endYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArcRowsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $ArcRowsTable> {
  $$ArcRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get selfContained => $composableBuilder(
    column: $table.selfContained,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startYear => $composableBuilder(
    column: $table.startYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endYear => $composableBuilder(
    column: $table.endYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArcRowsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $ArcRowsTable> {
  $$ArcRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<int> get selfContained => $composableBuilder(
    column: $table.selfContained,
    builder: (column) => column,
  );

  GeneratedColumn<int> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get publisher =>
      $composableBuilder(column: $table.publisher, builder: (column) => column);

  GeneratedColumn<int> get startYear =>
      $composableBuilder(column: $table.startYear, builder: (column) => column);

  GeneratedColumn<int> get endYear =>
      $composableBuilder(column: $table.endYear, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );
}

class $$ArcRowsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $ArcRowsTable,
          ArcRow,
          $$ArcRowsTableFilterComposer,
          $$ArcRowsTableOrderingComposer,
          $$ArcRowsTableAnnotationComposer,
          $$ArcRowsTableCreateCompanionBuilder,
          $$ArcRowsTableUpdateCompanionBuilder,
          (ArcRow, BaseReferences<_$MirrorDatabase, $ArcRowsTable, ArcRow>),
          ArcRow,
          PrefetchHooks Function()
        > {
  $$ArcRowsTableTableManager(_$MirrorDatabase db, $ArcRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArcRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArcRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArcRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> imageUrl = const Value.absent(),
                Value<int?> selfContained = const Value.absent(),
                Value<int> total = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> publisher = const Value.absent(),
                Value<int> startYear = const Value.absent(),
                Value<int> endYear = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArcRowsCompanion(
                id: id,
                name: name,
                imageUrl: imageUrl,
                selfContained: selfContained,
                total: total,
                source: source,
                publisher: publisher,
                startYear: startYear,
                endYear: endYear,
                description: description,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> imageUrl = const Value.absent(),
                Value<int?> selfContained = const Value.absent(),
                Value<int> total = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> publisher = const Value.absent(),
                Value<int> startYear = const Value.absent(),
                Value<int> endYear = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArcRowsCompanion.insert(
                id: id,
                name: name,
                imageUrl: imageUrl,
                selfContained: selfContained,
                total: total,
                source: source,
                publisher: publisher,
                startYear: startYear,
                endYear: endYear,
                description: description,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArcRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $ArcRowsTable,
      ArcRow,
      $$ArcRowsTableFilterComposer,
      $$ArcRowsTableOrderingComposer,
      $$ArcRowsTableAnnotationComposer,
      $$ArcRowsTableCreateCompanionBuilder,
      $$ArcRowsTableUpdateCompanionBuilder,
      (ArcRow, BaseReferences<_$MirrorDatabase, $ArcRowsTable, ArcRow>),
      ArcRow,
      PrefetchHooks Function()
    >;
typedef $$ArcItemRowsTableCreateCompanionBuilder =
    ArcItemRowsCompanion Function({
      required String arcId,
      required String issueId,
      required int position,
      Value<int> rowid,
    });
typedef $$ArcItemRowsTableUpdateCompanionBuilder =
    ArcItemRowsCompanion Function({
      Value<String> arcId,
      Value<String> issueId,
      Value<int> position,
      Value<int> rowid,
    });

class $$ArcItemRowsTableFilterComposer
    extends Composer<_$MirrorDatabase, $ArcItemRowsTable> {
  $$ArcItemRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get arcId => $composableBuilder(
    column: $table.arcId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get issueId => $composableBuilder(
    column: $table.issueId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ArcItemRowsTableOrderingComposer
    extends Composer<_$MirrorDatabase, $ArcItemRowsTable> {
  $$ArcItemRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get arcId => $composableBuilder(
    column: $table.arcId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get issueId => $composableBuilder(
    column: $table.issueId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArcItemRowsTableAnnotationComposer
    extends Composer<_$MirrorDatabase, $ArcItemRowsTable> {
  $$ArcItemRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get arcId =>
      $composableBuilder(column: $table.arcId, builder: (column) => column);

  GeneratedColumn<String> get issueId =>
      $composableBuilder(column: $table.issueId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$ArcItemRowsTableTableManager
    extends
        RootTableManager<
          _$MirrorDatabase,
          $ArcItemRowsTable,
          ArcItemRow,
          $$ArcItemRowsTableFilterComposer,
          $$ArcItemRowsTableOrderingComposer,
          $$ArcItemRowsTableAnnotationComposer,
          $$ArcItemRowsTableCreateCompanionBuilder,
          $$ArcItemRowsTableUpdateCompanionBuilder,
          (
            ArcItemRow,
            BaseReferences<_$MirrorDatabase, $ArcItemRowsTable, ArcItemRow>,
          ),
          ArcItemRow,
          PrefetchHooks Function()
        > {
  $$ArcItemRowsTableTableManager(_$MirrorDatabase db, $ArcItemRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArcItemRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArcItemRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArcItemRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> arcId = const Value.absent(),
                Value<String> issueId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ArcItemRowsCompanion(
                arcId: arcId,
                issueId: issueId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String arcId,
                required String issueId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => ArcItemRowsCompanion.insert(
                arcId: arcId,
                issueId: issueId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ArcItemRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$MirrorDatabase,
      $ArcItemRowsTable,
      ArcItemRow,
      $$ArcItemRowsTableFilterComposer,
      $$ArcItemRowsTableOrderingComposer,
      $$ArcItemRowsTableAnnotationComposer,
      $$ArcItemRowsTableCreateCompanionBuilder,
      $$ArcItemRowsTableUpdateCompanionBuilder,
      (
        ArcItemRow,
        BaseReferences<_$MirrorDatabase, $ArcItemRowsTable, ArcItemRow>,
      ),
      ArcItemRow,
      PrefetchHooks Function()
    >;

class $MirrorDatabaseManager {
  final _$MirrorDatabase _db;
  $MirrorDatabaseManager(this._db);
  $$SeriesRowsTableTableManager get seriesRows =>
      $$SeriesRowsTableTableManager(_db, _db.seriesRows);
  $$IssueRowsTableTableManager get issueRows =>
      $$IssueRowsTableTableManager(_db, _db.issueRows);
  $$ProgressRowsTableTableManager get progressRows =>
      $$ProgressRowsTableTableManager(_db, _db.progressRows);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$QueueRowsTableTableManager get queueRows =>
      $$QueueRowsTableTableManager(_db, _db.queueRows);
  $$QueueItemRowsTableTableManager get queueItemRows =>
      $$QueueItemRowsTableTableManager(_db, _db.queueItemRows);
  $$ArcRowsTableTableManager get arcRows =>
      $$ArcRowsTableTableManager(_db, _db.arcRows);
  $$ArcItemRowsTableTableManager get arcItemRows =>
      $$ArcItemRowsTableTableManager(_db, _db.arcItemRows);
}
