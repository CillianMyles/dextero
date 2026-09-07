/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod/serverpod.dart' as _is;

abstract class Message
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  Message._({
    this.id,
    required this.conversationId,
    required this.sequence,
    required this.content,
    String? source,
  }) : source = source ?? 'user';

  factory Message({
    int? id,
    required int conversationId,
    required int sequence,
    required String content,
    String? source,
  }) = _MessageImpl;

  factory Message.fromJson(Map<String, dynamic> jsonSerialization) {
    return Message(
      id: jsonSerialization['id'] as int?,
      conversationId: jsonSerialization['conversationId'] as int,
      sequence: jsonSerialization['sequence'] as int,
      content: jsonSerialization['content'] as String,
      source: jsonSerialization['source'] as String?,
    );
  }

  static final t = MessageTable();

  static const db = MessageRepository._();

  @override
  int? id;

  int conversationId;

  int sequence;

  String content;

  String source;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [Message]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  Message copyWith({
    int? id,
    int? conversationId,
    int? sequence,
    String? content,
    String? source,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Message',
      if (id != null) 'id': id,
      'conversationId': conversationId,
      'sequence': sequence,
      'content': content,
      'source': source,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'Message',
      if (id != null) 'id': id,
      'conversationId': conversationId,
      'sequence': sequence,
      'content': content,
      'source': source,
    };
  }

  static MessageInclude include() {
    return MessageInclude._();
  }

  static MessageIncludeList includeList({
    _is.WhereExpressionBuilder<MessageTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MessageTable>? orderBy,
    _is.OrderByListBuilder<MessageTable>? orderByList,
    MessageInclude? include,
  }) {
    return MessageIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Message.t),
      orderByList: orderByList?.call(Message.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _MessageImpl extends Message {
  _MessageImpl({
    int? id,
    required int conversationId,
    required int sequence,
    required String content,
    String? source,
  }) : super._(
         id: id,
         conversationId: conversationId,
         sequence: sequence,
         content: content,
         source: source,
       );

  /// Returns a shallow copy of this [Message]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  Message copyWith({
    Object? id = _Undefined,
    int? conversationId,
    int? sequence,
    String? content,
    String? source,
  }) {
    return Message(
      id: id is int? ? id : this.id,
      conversationId: conversationId ?? this.conversationId,
      sequence: sequence ?? this.sequence,
      content: content ?? this.content,
      source: source ?? this.source,
    );
  }
}

class MessageUpdateTable extends _is.UpdateTable<MessageTable> {
  MessageUpdateTable(super.table);

  _is.ColumnValue<int, int> conversationId(int value) =>
      _is.ColumnValue(table.conversationId, value);

  _is.ColumnValue<int, int> sequence(int value) =>
      _is.ColumnValue(table.sequence, value);

  _is.ColumnValue<String, String> content(String value) =>
      _is.ColumnValue(table.content, value);

  _is.ColumnValue<String, String> source(String value) =>
      _is.ColumnValue(table.source, value);
}

class MessageTable extends _is.Table<int?> {
  MessageTable({super.tableRelation}) : super(tableName: 'spike_message') {
    updateTable = MessageUpdateTable(this);
    conversationId = _is.ColumnInt('conversationId', this);
    sequence = _is.ColumnInt('sequence', this);
    content = _is.ColumnString('content', this);
    source = _is.ColumnString('source', this, hasDefault: true);
  }

  late final MessageUpdateTable updateTable;

  late final _is.ColumnInt conversationId;

  late final _is.ColumnInt sequence;

  late final _is.ColumnString content;

  late final _is.ColumnString source;

  @override
  List<_is.Column> get columns => [
    id,
    conversationId,
    sequence,
    content,
    source,
  ];
}

class MessageInclude extends _is.IncludeObject {
  MessageInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => Message.t;
}

class MessageIncludeList extends _is.IncludeList {
  MessageIncludeList._({
    _is.WhereExpressionBuilder<MessageTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(Message.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => Message.t;
}

class MessageRepository {
  const MessageRepository._();

  /// Returns a list of [Message]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<Message>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MessageTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MessageTable>? orderBy,
    _is.OrderByListBuilder<MessageTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<Message>(
      where: where?.call(Message.t),
      orderBy: orderBy?.call(Message.t),
      orderByList: orderByList?.call(Message.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Returns the first matching [Message] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<Message?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MessageTable>? where,
    int? offset,
    _is.OrderByBuilder<MessageTable>? orderBy,
    _is.OrderByListBuilder<MessageTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<Message>(
      where: where?.call(Message.t),
      orderBy: orderBy?.call(Message.t),
      orderByList: orderByList?.call(Message.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [Message] by its [id] or null if no such row exists.
  Future<Message?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<Message>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [Message]s in the list and returns the inserted rows.
  ///
  /// The returned [Message]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  ///
  /// If [noReturn] is set to `true`, the inserted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Message>> insert(
    _is.DatabaseSession session,
    List<Message> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<Message>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [Message] and returns the inserted row.
  ///
  /// The returned [Message] will have its `id` field set.
  Future<Message> insertRow(
    _is.DatabaseSession session,
    Message row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<Message>(row, transaction: transaction);
  }

  /// Upserts all [Message]s in the list and returns the resulting rows.
  ///
  /// If a row conflicts on the given [conflictColumns], the existing row is
  /// updated with the new values. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies to rows matching the
  /// given expression. Conflicting rows that don't match are skipped and not
  /// returned, so the resulting list may be shorter than [rows].
  ///
  /// The returned [Message]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Message>> upsert(
    _is.DatabaseSession session,
    List<Message> rows, {
    required _is.ColumnSelections<MessageTable> conflictColumns,
    _is.ColumnSelections<MessageTable>? updateColumns,
    _is.WhereExpressionBuilder<MessageTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<Message>(
      rows,
      conflictColumns: conflictColumns(Message.t),
      updateColumns: updateColumns?.call(Message.t),
      updateWhere: updateWhere?.call(Message.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [Message] and returns the resulting row.
  ///
  /// If the row conflicts on the given [conflictColumns], the existing row is
  /// updated. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies when the existing
  /// row matches the expression. Returns `null` if no row was affected — for
  /// example when [updateWhere] does not match the conflicting row.
  ///
  /// The returned [Message] will have its `id` field set.
  Future<Message?> upsertRow(
    _is.DatabaseSession session,
    Message row, {
    required _is.ColumnSelections<MessageTable> conflictColumns,
    _is.ColumnSelections<MessageTable>? updateColumns,
    _is.WhereExpressionBuilder<MessageTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<Message>(
      row,
      conflictColumns: conflictColumns(Message.t),
      updateColumns: updateColumns?.call(Message.t),
      updateWhere: updateWhere?.call(Message.t),
      transaction: transaction,
    );
  }

  /// Updates all [Message]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Message>> update(
    _is.DatabaseSession session,
    List<Message> rows, {
    _is.ColumnSelections<MessageTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<Message>(
      rows,
      columns: columns?.call(Message.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [Message]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<Message> updateRow(
    _is.DatabaseSession session,
    Message row, {
    _is.ColumnSelections<MessageTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<Message>(
      row,
      columns: columns?.call(Message.t),
      transaction: transaction,
    );
  }

  /// Updates a single [Message] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<Message?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<MessageUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<Message>(
      id,
      columnValues: columnValues(Message.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [Message]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Message>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<MessageUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<MessageTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<MessageTable>? orderBy,
    _is.OrderByListBuilder<MessageTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<Message>(
      columnValues: columnValues(Message.t.updateTable),
      where: where(Message.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(Message.t),
      orderByList: orderByList?.call(Message.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [Message]s in the list and returns the deleted rows.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Message>> delete(
    _is.DatabaseSession session,
    List<Message> rows, {
    _is.OrderByBuilder<MessageTable>? orderBy,
    _is.OrderByListBuilder<MessageTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<Message>(
      rows,
      orderBy: orderBy?.call(Message.t),
      orderByList: orderByList?.call(Message.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [Message].
  Future<Message> deleteRow(
    _is.DatabaseSession session,
    Message row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<Message>(row, transaction: transaction);
  }

  /// Deletes all rows matching the [where] expression.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<Message>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MessageTable> where,
    _is.OrderByBuilder<MessageTable>? orderBy,
    _is.OrderByListBuilder<MessageTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<Message>(
      where: where(Message.t),
      orderBy: orderBy?.call(Message.t),
      orderByList: orderByList?.call(Message.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<MessageTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<Message>(
      where: where?.call(Message.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [Message] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<MessageTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<Message>(
      where: where(Message.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
