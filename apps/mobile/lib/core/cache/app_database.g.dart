// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedResponsesTable extends CachedResponses
    with TableInfo<$CachedResponsesTable, CachedResponse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedResponsesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _requestKeyMeta = const VerificationMeta(
    'requestKey',
  );
  @override
  late final GeneratedColumn<String> requestKey = GeneratedColumn<String>(
    'request_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storedAtMeta = const VerificationMeta(
    'storedAt',
  );
  @override
  late final GeneratedColumn<DateTime> storedAt = GeneratedColumn<DateTime>(
    'stored_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [requestKey, etag, body, storedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_responses';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedResponse> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('request_key')) {
      context.handle(
        _requestKeyMeta,
        requestKey.isAcceptableOrUnknown(data['request_key']!, _requestKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_requestKeyMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('stored_at')) {
      context.handle(
        _storedAtMeta,
        storedAt.isAcceptableOrUnknown(data['stored_at']!, _storedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_storedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {requestKey};
  @override
  CachedResponse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedResponse(
      requestKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_key'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      storedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}stored_at'],
      )!,
    );
  }

  @override
  $CachedResponsesTable createAlias(String alias) {
    return $CachedResponsesTable(attachedDatabase, alias);
  }
}

class CachedResponse extends DataClass implements Insertable<CachedResponse> {
  final String requestKey;
  final String? etag;
  final String body;
  final DateTime storedAt;
  const CachedResponse({
    required this.requestKey,
    this.etag,
    required this.body,
    required this.storedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['request_key'] = Variable<String>(requestKey);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    map['body'] = Variable<String>(body);
    map['stored_at'] = Variable<DateTime>(storedAt);
    return map;
  }

  CachedResponsesCompanion toCompanion(bool nullToAbsent) {
    return CachedResponsesCompanion(
      requestKey: Value(requestKey),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      body: Value(body),
      storedAt: Value(storedAt),
    );
  }

  factory CachedResponse.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedResponse(
      requestKey: serializer.fromJson<String>(json['requestKey']),
      etag: serializer.fromJson<String?>(json['etag']),
      body: serializer.fromJson<String>(json['body']),
      storedAt: serializer.fromJson<DateTime>(json['storedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'requestKey': serializer.toJson<String>(requestKey),
      'etag': serializer.toJson<String?>(etag),
      'body': serializer.toJson<String>(body),
      'storedAt': serializer.toJson<DateTime>(storedAt),
    };
  }

  CachedResponse copyWith({
    String? requestKey,
    Value<String?> etag = const Value.absent(),
    String? body,
    DateTime? storedAt,
  }) => CachedResponse(
    requestKey: requestKey ?? this.requestKey,
    etag: etag.present ? etag.value : this.etag,
    body: body ?? this.body,
    storedAt: storedAt ?? this.storedAt,
  );
  CachedResponse copyWithCompanion(CachedResponsesCompanion data) {
    return CachedResponse(
      requestKey: data.requestKey.present
          ? data.requestKey.value
          : this.requestKey,
      etag: data.etag.present ? data.etag.value : this.etag,
      body: data.body.present ? data.body.value : this.body,
      storedAt: data.storedAt.present ? data.storedAt.value : this.storedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedResponse(')
          ..write('requestKey: $requestKey, ')
          ..write('etag: $etag, ')
          ..write('body: $body, ')
          ..write('storedAt: $storedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(requestKey, etag, body, storedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedResponse &&
          other.requestKey == this.requestKey &&
          other.etag == this.etag &&
          other.body == this.body &&
          other.storedAt == this.storedAt);
}

class CachedResponsesCompanion extends UpdateCompanion<CachedResponse> {
  final Value<String> requestKey;
  final Value<String?> etag;
  final Value<String> body;
  final Value<DateTime> storedAt;
  final Value<int> rowid;
  const CachedResponsesCompanion({
    this.requestKey = const Value.absent(),
    this.etag = const Value.absent(),
    this.body = const Value.absent(),
    this.storedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedResponsesCompanion.insert({
    required String requestKey,
    this.etag = const Value.absent(),
    required String body,
    required DateTime storedAt,
    this.rowid = const Value.absent(),
  }) : requestKey = Value(requestKey),
       body = Value(body),
       storedAt = Value(storedAt);
  static Insertable<CachedResponse> custom({
    Expression<String>? requestKey,
    Expression<String>? etag,
    Expression<String>? body,
    Expression<DateTime>? storedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (requestKey != null) 'request_key': requestKey,
      if (etag != null) 'etag': etag,
      if (body != null) 'body': body,
      if (storedAt != null) 'stored_at': storedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedResponsesCompanion copyWith({
    Value<String>? requestKey,
    Value<String?>? etag,
    Value<String>? body,
    Value<DateTime>? storedAt,
    Value<int>? rowid,
  }) {
    return CachedResponsesCompanion(
      requestKey: requestKey ?? this.requestKey,
      etag: etag ?? this.etag,
      body: body ?? this.body,
      storedAt: storedAt ?? this.storedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (requestKey.present) {
      map['request_key'] = Variable<String>(requestKey.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (storedAt.present) {
      map['stored_at'] = Variable<DateTime>(storedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedResponsesCompanion(')
          ..write('requestKey: $requestKey, ')
          ..write('etag: $etag, ')
          ..write('body: $body, ')
          ..write('storedAt: $storedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedResponsesTable cachedResponses = $CachedResponsesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cachedResponses];
}

typedef $$CachedResponsesTableCreateCompanionBuilder =
    CachedResponsesCompanion Function({
      required String requestKey,
      Value<String?> etag,
      required String body,
      required DateTime storedAt,
      Value<int> rowid,
    });
typedef $$CachedResponsesTableUpdateCompanionBuilder =
    CachedResponsesCompanion Function({
      Value<String> requestKey,
      Value<String?> etag,
      Value<String> body,
      Value<DateTime> storedAt,
      Value<int> rowid,
    });

class $$CachedResponsesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedResponsesTable> {
  $$CachedResponsesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get requestKey => $composableBuilder(
    column: $table.requestKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get storedAt => $composableBuilder(
    column: $table.storedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedResponsesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedResponsesTable> {
  $$CachedResponsesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get requestKey => $composableBuilder(
    column: $table.requestKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get storedAt => $composableBuilder(
    column: $table.storedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedResponsesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedResponsesTable> {
  $$CachedResponsesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get requestKey => $composableBuilder(
    column: $table.requestKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get storedAt =>
      $composableBuilder(column: $table.storedAt, builder: (column) => column);
}

class $$CachedResponsesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedResponsesTable,
          CachedResponse,
          $$CachedResponsesTableFilterComposer,
          $$CachedResponsesTableOrderingComposer,
          $$CachedResponsesTableAnnotationComposer,
          $$CachedResponsesTableCreateCompanionBuilder,
          $$CachedResponsesTableUpdateCompanionBuilder,
          (
            CachedResponse,
            BaseReferences<
              _$AppDatabase,
              $CachedResponsesTable,
              CachedResponse
            >,
          ),
          CachedResponse,
          PrefetchHooks Function()
        > {
  $$CachedResponsesTableTableManager(
    _$AppDatabase db,
    $CachedResponsesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedResponsesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedResponsesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedResponsesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> requestKey = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> storedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedResponsesCompanion(
                requestKey: requestKey,
                etag: etag,
                body: body,
                storedAt: storedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String requestKey,
                Value<String?> etag = const Value.absent(),
                required String body,
                required DateTime storedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedResponsesCompanion.insert(
                requestKey: requestKey,
                etag: etag,
                body: body,
                storedAt: storedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedResponsesTable, CachedResponse>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedResponsesTable,
                    CachedResponse
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedResponsesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedResponsesTable,
      CachedResponse,
      $$CachedResponsesTableFilterComposer,
      $$CachedResponsesTableOrderingComposer,
      $$CachedResponsesTableAnnotationComposer,
      $$CachedResponsesTableCreateCompanionBuilder,
      $$CachedResponsesTableUpdateCompanionBuilder,
      (
        CachedResponse,
        BaseReferences<_$AppDatabase, $CachedResponsesTable, CachedResponse>,
      ),
      CachedResponse,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedResponsesTableTableManager get cachedResponses =>
      $$CachedResponsesTableTableManager(_db, _db.cachedResponses);
}
