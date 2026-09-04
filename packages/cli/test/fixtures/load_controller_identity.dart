import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';

Future<void> main(List<String> arguments) async {
  final identity = await CliControllerIdentityStore(
    stateFile: File(arguments.single),
  ).load(const {});
  stdout.writeln(identity.id);
}
