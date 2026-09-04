import 'dart:io';

import 'package:dextero_core/src/filesystem_identity.dart';

Future<void> main(List<String> arguments) async {
  stdout.writeln(await resolveFilesystemIdentity(Directory(arguments.single)));
}
