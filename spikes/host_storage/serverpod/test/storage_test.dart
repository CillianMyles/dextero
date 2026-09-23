import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:host_storage_server/src/generated/protocol.dart' as server;
import 'package:host_storage_server/src/protocol/protocol.dart' as client;
import 'package:test/test.dart';

void main() {
  // The same acceptance test exercises JIT and the relocated native bundle.
  final executable = Platform.environment['STORAGE_SPIKE_EXECUTABLE'];
  final workingDirectory = Platform.environment['STORAGE_SPIKE_BUNDLE'];
  late Directory temporary;
  late String database;

  Future<Process> start(String command) async {
    final process = await Process.start(
      executable ?? Platform.resolvedExecutable,
      [
        if (executable == null) ...['run', 'bin/probe.dart'],
        command,
        database,
      ],
      workingDirectory: workingDirectory,
    );
    // Test timeouts must not leave a host using a directory teardown removes.
    addTearDown(() async {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    });
    return process;
  }

  Future<({Map<String, dynamic> data, String output})> run(
    String command,
  ) async {
    final process = await start(command);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('probe $command');
      },
    );
    final text = '${await output}\n${await errors}';
    expect(code, 0, reason: '$command\n$text');
    final result = const LineSplitter()
        .convert(text)
        .singleWhere((l) => l.startsWith('RESULT '));
    return (
      data: jsonDecode(result.substring(7)) as Map<String, dynamic>,
      output: text,
    );
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('dextero-storage-test-');
    database = '${temporary.path}/host.db';
  });
  tearDown(() => temporary.delete(recursive: true));

  test('generated server rows round-trip through the typed client model', () {
    final row = server.Message(
      conversationId: 7,
      sequence: 2,
      content: 'Tuesday',
      source: 'user',
    );
    final decoded = client.Message.fromJson(
      jsonDecode(jsonEncode(row.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.conversationId, 7);
    expect(decoded.sequence, 2);
    expect(decoded.content, 'Tuesday');
    expect(decoded.source, 'user');
  });

  test(
    'fresh database migrates and committed appends survive restart',
    () async {
      final fresh = await run('inspect');
      expect(fresh.data['messages'], isEmpty);
      final appended = await run('append');
      expect(appended.data['nextSequence'], 1);
      final restarted = await run('inspect');
      expect(restarted.data, appended.data);
    },
    // Three separate JIT launches can exceed the test runner's 30s default.
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'v1 data migrates, rollback is atomic, writers keep cursor order, crash recovers',
    () async {
      await run('seed-v1');
      final migrated = await run('inspect');
      final messages = migrated.data['messages'] as List;
      expect(messages.single['content'], 'Train on Tuesday and Thursday');
      expect(messages.single['source'], 'user');
      expect(migrated.data['nextSequence'], 1);
      expect(
        migrated.output,
        contains('Persistent logging is not supported when using SQLite'),
      );
      expect(migrated.output, contains('SPIKE_DIAGNOSTIC'));
      expect(migrated.output, contains('serverpod.SessionLogEntry'));
      expect(migrated.data['persistentSessionLogs'], 0);

      final constrained = await run('constraints');
      expect(constrained.data, migrated.data);
      expect(constrained.output, contains('SPIKE_UNIQUE_CONSTRAINT'));
      expect(constrained.output, contains('SPIKE_FOREIGN_KEY_CONSTRAINT'));

      final rolledBack = await run('rollback');
      expect(rolledBack.data, migrated.data);
      expect(rolledBack.output, contains('SPIKE_ROLLBACK'));
      final appended = await run('append');
      expect(appended.data['nextSequence'], 2);
      final concurrent = await run('concurrent');
      expect(concurrent.data['nextSequence'], 14);
      expect(
        (concurrent.data['messages'] as List).map((m) => m['sequence']),
        List.generate(14, (i) => i),
      );

      final process = await start('crash');
      final ready = Completer<void>();
      final output = <String>[];
      final subscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              output.add(line);
              if (line == 'UNCOMMITTED') ready.complete();
            },
            onDone: () {
              if (!ready.isCompleted) {
                ready.completeError(StateError('Probe exited: $output'));
              }
            },
          );
      final errors = process.stderr.transform(utf8.decoder).join();
      try {
        await ready.future.timeout(const Duration(seconds: 45));
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        await subscription.cancel();
        await errors;
      }
      final recovered = await run('inspect');
      expect(recovered.data, concurrent.data);
      final afterCrash = await run('append');
      expect(afterCrash.data['nextSequence'], 15);
      expect((afterCrash.data['messages'] as List).last['sequence'], 14);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
