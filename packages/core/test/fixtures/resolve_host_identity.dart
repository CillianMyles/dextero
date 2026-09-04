import 'dart:convert';
import 'dart:io';

import 'package:dextero_core/dextero_core.dart';

Future<void> main(List<String> arguments) async {
  final identity = await LocalIdentityRegistry(
    stateFile: File(arguments[0]),
  ).resolve(arguments[1]);
  stdout.writeln(
    jsonEncode({
      'deviceId': identity.deviceId,
      'projectId': identity.projectId,
      'workspaceId': identity.workspaceId,
    }),
  );
}
