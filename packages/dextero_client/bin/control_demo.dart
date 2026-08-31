import 'dart:io';

import 'package:dextero_client/dextero_client.dart';

Future<void> main() async {
  final token = Platform.environment['DEXTERO_CONTROL_TOKEN'];
  if (token == null) {
    stderr.writeln('DEXTERO_CONTROL_TOKEN is required.');
    exitCode = 64;
    return;
  }

  final host =
      Platform.environment['DEXTERO_CONTROL_URL'] ?? 'http://localhost:8080/';
  final client = Client(host)
    ..authKeyProvider = DexteroTokenAuthProvider(token);

  try {
    final status = await client.control.status();
    stdout.writeln(
      '${status.name} ${status.version}: '
      '${status.persistence} persistence, '
      'database required=${status.databaseRequired}',
    );

    await for (final event in client.control.runDemo(3)) {
      stdout.writeln(
        '${event.taskId} #${event.sequence} '
        '${event.kind.name}: ${event.message}',
      );
    }
  } finally {
    client.close();
  }
}
