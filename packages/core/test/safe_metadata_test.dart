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

  test('shows a bounded, sanitized edit preview for approval', () {
    final summary = SafeMetadata.approvalRequest('edit_file', {
      'path': 'README\u202E.md',
      'oldText': 'Old heading\nold body\x1b[2J\u2066\n${'o' * 5000}',
      'newText': 'New heading\u2069\n${'n' * 5000}',
    });

    expect(summary.text, startsWith('edit_file requires approval'));
    expect(summary.text, contains(r'README\u202E.md'));
    expect(
      summary.text,
      contains('--- old text\n-Old heading\n-old body\\u001B[2J\\u2066'),
    );
    expect(summary.text, contains('+++ new text\n+New heading\\u2069'));
    expect(summary.text, isNot(contains('\x1b')));
    expect(
      summary.text,
      isNot(contains(RegExp('[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'))),
    );
    expect(
      summary.text.length,
      lessThanOrEqualTo(SafeMetadata.maxToolResultCharacters),
    );
    expect(summary.truncated, isTrue);
  });

  test('makes significant whitespace unambiguous in approval previews', () {
    final summary = SafeMetadata.approvalRequest('edit_file', {
      'path': 'spacing.txt',
      'oldText': 'indent\tvalue  \r\nline\\t \n',
      'newText': 'indent  value\nline\\t\n',
    });

    expect(
      summary.text,
      contains(
        r'-indent\tvalue\u0020\u0020\r'
        '\n'
        r'-line\\t\u0020'
        '\n-',
      ),
    );
    expect(
      summary.text,
      contains(
        r'+indent  value'
        '\n'
        r'+line\\t'
        '\n+',
      ),
    );
  });

  test('escapes Unicode line separators before prefixing approval lines', () {
    final summary = SafeMetadata.approvalRequest('edit_file', {
      'path': 'separators.txt',
      'oldText': 'old\u2028--- fake heading\u2029old tail',
      'newText': 'new\u2029+++ fake heading\u2028new tail',
    });

    expect(summary.text, contains(r'-old\u2028--- fake heading\u2029old tail'));
    expect(summary.text, contains(r'+new\u2029+++ fake heading\u2028new tail'));
    expect(summary.text, isNot(contains(RegExp('[\u2028\u2029]'))));
  });

  test('makes zero-width join controls visible in approval previews', () {
    final summary = SafeMetadata.approvalRequest('edit_file', {
      'path': 'joiners.txt',
      'oldText': 'joined\u200Cvalue',
      'newText': 'joined\u200Dvalue',
    });

    expect(summary.text, contains(r'-joined\u200Cvalue'));
    expect(summary.text, contains(r'+joined\u200Dvalue'));
    expect(summary.text, isNot(contains(RegExp('[\u200C\u200D]'))));
  });

  test('makes every default-ignorable approval range visible', () {
    const runes = <int>[
      0x00AD,
      0x034F,
      0x061C,
      0x115F,
      0x1160,
      0x17B4,
      0x17B5,
      0x180B,
      0x180F,
      0x200B,
      0x200F,
      0x202A,
      0x202E,
      0x2060,
      0x2061,
      0x2062,
      0x2063,
      0x2064,
      0x206F,
      0x3164,
      0xFE00,
      0xFE0F,
      0xFEFF,
      0xFFA0,
      0xFFF0,
      0xFFF8,
      0x1BCA0,
      0x1BCA3,
      0x1D173,
      0x1D17A,
      0xE0000,
      0xE0FFF,
    ];
    final raw = String.fromCharCodes(runes);
    final summary = SafeMetadata.approvalRequest('edit_file', {
      'path': 'ignorable.txt',
      'oldText': raw,
      'newText': raw,
    });

    for (final rune in runes) {
      final digits = rune.toRadixString(16).toUpperCase();
      final visible = rune <= 0xFFFF
          ? '\\u${digits.padLeft(4, '0')}'
          : '\\u{$digits}';
      expect(summary.text, contains(visible), reason: 'U+$digits was hidden');
      expect(summary.text.runes, isNot(contains(rune)));
    }
  });

  test('quotes and escapes the exact approval target path', () {
    final summary = SafeMetadata.approvalRequest('edit_file', {
      'path': ' leading\tname\n--- old text\x1b[2J\u202E.md\u00A0 ',
      'oldText': 'old',
      'newText': 'new',
    });

    expect(
      summary.text,
      contains(r'for " leading\tname\n--- old text\u001B[2J\u202E.md\u00A0 "'),
    );
    expect(summary.text, isNot(contains('\n--- old text\n--- old text')));
    expect(summary.text, isNot(contains('\x1b')));
  });

  test('keeps a truncated approval path quoted and bounded', () {
    final summary = SafeMetadata.approvalRequest('edit_file', {
      'path': '\u202E' * 100,
      'oldText': 'old',
      'newText': 'new',
    });
    final heading = summary.text.split('\n').first;

    expect(heading, endsWith('…"'));
    expect(
      heading.length,
      lessThanOrEqualTo(
        'edit_file requires approval for '.length +
            SafeMetadata.maxApprovalPathCharacters,
      ),
    );
    expect(summary.truncated, isTrue);
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
