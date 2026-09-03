import 'dart:io';

abstract interface class TerminalIo {
  bool get hasInputTerminal;

  bool get hasOutputTerminal;

  void write(String value);

  void writeln(String value);

  void error(String value);

  String? readLine();
}

final class SystemTerminalIo implements TerminalIo {
  const SystemTerminalIo();

  @override
  bool get hasInputTerminal => stdin.hasTerminal;

  @override
  bool get hasOutputTerminal => stdout.hasTerminal;

  @override
  void write(String value) => stdout.write(value);

  @override
  void writeln(String value) => stdout.writeln(value);

  @override
  void error(String value) => stderr.writeln(value);

  @override
  String? readLine() => stdin.readLineSync();
}
