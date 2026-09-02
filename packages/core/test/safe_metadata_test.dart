import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'preserves message formatting and credentials while removing controls',
    () {
      final summary = SafeMetadata.message(
        'Line one\n\n  code\tvalue\n'
        'secret=hidden Bearer raw-token sk-abcdefghijklmnop\x1b[2J',
      );

      expect(
        summary.text,
        'Line one\n\n  code  value\n'
        'secret=hidden Bearer raw-token sk-abcdefghijklmnop',
      );
      expect(summary.truncated, isFalse);
    },
  );

  test('includes complete tool failure details', () {
    final summary = SafeMetadata.toolResult(
      'run_command',
      'password=hunter2 and raw stderr',
      success: false,
    );

    expect(summary.text, 'run_command failed: password=hunter2 and raw stderr');
  });

  test('includes the complete command and structured output', () {
    final started = SafeMetadata.toolCall('run_command', const {
      'command': '/usr/bin/sed',
      'arguments': ['-n', '1,20p', 'a file.txt', '--flag', 'example-value'],
    });
    final completed = SafeMetadata.toolResult('run_command', const {
      'exit_code': 7,
      'stdout': 'first\nsecond\n',
      'stderr': 'token=super-secret\nfailed\n',
      'truncated': false,
    }, success: true);

    expect(
      started.text,
      'run_command started: /usr/bin/sed -n 1,20p "a file.txt" '
      '--flag example-value',
      reason: started.text,
    );
    expect(completed.text, contains('run_command completed (exit 7)'));
    expect(completed.text, contains('stdout:\nfirst\nsecond'));
    expect(completed.text, contains('stderr:\ntoken=super-secret\nfailed'));
  });

  test('caps command output and carries upstream truncation', () {
    final summary = SafeMetadata.toolResult('run_shell', {
      'exit_code': 0,
      'stdout': 'x' * 5000,
      'stderr': '',
      'truncated': true,
    }, success: true);

    expect(summary.text.length, SafeMetadata.maxToolResultCharacters);
    expect(summary.truncated, isTrue);
  });
}
