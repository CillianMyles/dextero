import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:host_storage_server/src/generated/protocol.dart';
import 'package:host_storage_server/src/generated/serverpod.dart' hide Message;
import 'package:host_storage_server/store.dart';
import 'package:sqlite3/sqlite3.dart';

/// Run from the package directory, or a bundle with config/ and migrations/.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: probe <seed-v1|inspect|append|rollback|'
      'concurrent|crash> <database-path>',
    );
  }
  final command = args[0];
  final databasePath = File(args[1]).absolute.path;
  if (command == 'seed-v1') {
    if (File(databasePath).existsSync()) {
      throw StateError('Refusing to seed an existing database');
    }
    final db = sqlite3.open(databasePath);
    try {
      // Apply the actual generated v1 schema, then create pre-upgrade data.
      db.execute(
        File('migrations/20260907071459697/migration.sql').readAsStringSync(),
      );
      db.execute(
        'INSERT INTO spike_conversation (publicId, nextSequence) '
        "VALUES ('fitness', 1)",
      );
      db.execute(
        'INSERT INTO spike_message (conversationId, sequence, content) '
        "VALUES (1, 0, 'Train on Tuesday and Thursday')",
      );
      stdout.writeln('RESULT ${jsonEncode({'seeded': true})}');
    } finally {
      db.close();
    }
    return;
  }

  final pod = Serverpod(
    ['--apply-migrations'],
    config: ServerpodConfig(
      apiServer: ServerConfig(
        port: 0,
        publicHost: 'localhost',
        publicPort: 0,
        publicScheme: 'http',
      ),
      database: SqliteDatabaseConfig(filePath: databasePath),
      sessionLogs:
          SessionLogConfig.buildDefault(
            databaseEnabled: true,
            runMode: 'development',
          ).copyWith(
            // Intentionally request this to test the SQLite warning/fallback.
            persistentEnabled: true,
            consoleEnabled: true,
            consoleLogFormat: ConsoleLogFormat.json,
          ),
    ),
  );
  await pod.start(runInGuardedZone: false);
  final session = await pod.createSession();
  try {
    final store = SpikeStore(session);
    var conversation = await Conversation.db.findFirstRow(
      session,
      where: (t) => t.publicId.equals('fitness'),
    );
    conversation ??= await Conversation.db.insertRow(
      session,
      Conversation(publicId: 'fitness', nextSequence: 0),
    );
    switch (command) {
      case 'append':
        await store.append(conversation.id!, 'Follow-up after restart');
      case 'rollback':
        try {
          await store.append(
            conversation.id!,
            'must not persist',
            failBeforeCommit: true,
          );
          throw StateError('Expected the injected failure');
        } on StateError catch (error) {
          if (error.message != 'Injected failure before commit') rethrow;
          session.log('SPIKE_ROLLBACK', level: LogLevel.warning);
        }
      case 'concurrent':
        await Future.wait(
          List.generate(
            12,
            (i) => store.append(conversation!.id!, 'Concurrent $i'),
          ),
        );
      case 'crash':
        await store.append(
          conversation.id!,
          'uncommitted crash',
          beforeCommit: () async {
            stdout.writeln('UNCOMMITTED');
            await stdout.flush();
            await Completer<void>().future;
          },
        );
      case 'inspect':
        break;
      case 'constraints':
        try {
          await Message.db.insertRow(
            session,
            Message(
              conversationId: conversation.id!,
              sequence: 0,
              content: 'duplicate',
              source: 'user',
            ),
          );
          throw StateError('Unique constraint did not reject duplicate cursor');
        } on DatabaseUniqueViolationException {
          session.log('SPIKE_UNIQUE_CONSTRAINT');
        }
        try {
          await Message.db.insertRow(
            session,
            Message(
              conversationId: -1,
              sequence: 0,
              content: 'orphan',
              source: 'user',
            ),
          );
          throw StateError('Foreign key did not reject orphan');
        } on DatabaseForeignKeyViolationException {
          session.log('SPIKE_FOREIGN_KEY_CONSTRAINT');
        }
      default:
        throw ArgumentError('Unknown command: $command');
    }
    final messages = await Message.db.find(
      session,
      where: (t) => t.conversationId.equals(conversation!.id!),
      orderBy: (t) => t.sequence,
    );
    final current = await Conversation.db.findById(session, conversation.id!);
    session.log('SPIKE_DIAGNOSTIC messages=${messages.length}');
    final logs = await session.db.unsafeQuery(
      'SELECT count(*) FROM serverpod_session_log',
    );
    stdout.writeln(
      'RESULT ${jsonEncode({'nextSequence': current!.nextSequence, 'messages': messages.map((m) => m.toJson()).toList(), 'persistentSessionLogs': logs.first.first})}',
    );
  } finally {
    await session.close();
    await pod.shutdown(exitProcess: false);
  }
}
