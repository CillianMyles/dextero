import 'dart:convert';

import 'tool.dart';

final class SafeSummary {
  const SafeSummary(this.text, {this.truncated = false});

  final String text;
  final bool truncated;
}

/// Produces bounded metadata for display and canonical history.
abstract final class SafeMetadata {
  static const maxDisplayCharacters = 480;
  static const maxToolResultCharacters = 4000;
  static const maxApprovalEditSideCharacters = 1800;
  static const maxApprovalPathCharacters = 240;
  static const maxMessageCharacters = 16000;

  static final _summaryWhitespace = RegExp(r'[\r\n\t]+');
  static final _repeatedSpaces = RegExp(r' {2,}');
  static final _unsafeIdentifierCharacters = RegExp(r'[^a-zA-Z0-9_.:-]');
  static final _unsafeToolNameCharacters = RegExp(r'[^a-zA-Z0-9_.-]');
  static final _safeCommandArgument = RegExp(r'^[a-zA-Z0-9_./:=+,@%-]+$');
  static final _ansiControlSequence = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
  static final _bidirectionalControls = RegExp(
    '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );
  static final _unsafeControlCharacters = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]',
  );

  static SafeSummary text(
    Object? value, {
    int maxCharacters = maxDisplayCharacters,
  }) {
    _validateLimit(maxCharacters);
    var safe = _stripUnsafeControls(value?.toString() ?? 'Unknown error')
        .replaceAll(_summaryWhitespace, ' ')
        .replaceAll(_repeatedSpaces, ' ')
        .trim();
    return _bounded(safe, maxCharacters: maxCharacters);
  }

  /// Sanitizes user-visible assistant prose while preserving paragraphs and
  /// code formatting. Terminal control characters are removed before the
  /// content reaches either UI surface.
  static SafeSummary message(
    Object? value, {
    int maxCharacters = maxMessageCharacters,
  }) {
    _validateLimit(maxCharacters);
    var safe = _stripUnsafeControls(value?.toString() ?? '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\t', '  ')
        .trim();
    return _bounded(safe, maxCharacters: maxCharacters);
  }

  static SafeSummary toolCall(String toolName, JsonMap arguments) {
    var detail = '';
    if ({'list_files', 'read_file', 'edit_file'}.contains(toolName)) {
      final path = _safePath(arguments['path']);
      if (path != null) detail = ' for $path';
    } else if ({
      'run_command',
      'run_shell',
      'command_execution',
    }.contains(toolName)) {
      final command = _displayCommand(toolName, arguments);
      if (command != null) detail = ': $command';
    }
    return text('${_safeToolName(toolName)} started$detail');
  }

  /// Describes the exact operation awaiting approval without exposing raw
  /// protocol payloads. File edits include a bounded old/new text preview.
  static SafeSummary approvalRequest(String toolName, JsonMap arguments) {
    if (toolName != 'edit_file') return toolCall(toolName, arguments);
    final path = _approvalPath(arguments['path']);
    final detail = path == null ? '' : ' for ${path.text}';
    final heading = '${_safeToolName(toolName)} requires approval$detail';
    final oldText = arguments['oldText'];
    final newText = arguments['newText'];
    if (oldText is! String || newText is! String) {
      final summary = text(heading);
      return SafeSummary(
        summary.text,
        truncated: summary.truncated || path?.truncated == true,
      );
    }
    final oldPreview = _approvalEditPreview(oldText, '-');
    final newPreview = _approvalEditPreview(newText, '+');
    final preview = message(
      <String>[
        heading,
        '--- old text',
        oldPreview.text,
        '+++ new text',
        newPreview.text,
      ].join('\n'),
      maxCharacters: maxToolResultCharacters,
    );
    return SafeSummary(
      preview.text,
      truncated:
          preview.truncated ||
          oldPreview.truncated ||
          newPreview.truncated ||
          path?.truncated == true,
    );
  }

  static String toolName(String value) {
    final safe = _safeToolName(_stripUnsafeControls(value));
    return safe.length <= 128 ? safe : safe.substring(0, 128);
  }

  static String identifier(String value) {
    final safe = _stripUnsafeControls(
      value,
    ).replaceAll(_unsafeIdentifierCharacters, '_');
    final normalized = safe.isEmpty ? 'unknown' : safe;
    return normalized.length <= 160 ? normalized : normalized.substring(0, 160);
  }

  static SafeSummary toolResult(
    String toolName,
    Object? result, {
    required bool success,
  }) {
    final outcome = success ? 'completed' : 'failed';
    if (result is! Map) {
      final detail = !success && result != null ? ': $result' : '';
      return text('${_safeToolName(toolName)} $outcome$detail');
    }
    final map = result.cast<Object?, Object?>();
    var detail = '';
    if (toolName == 'list_files' && map['entries'] is List) {
      detail = ' (${(map['entries']! as List).length} entries)';
    } else if ({'read_file', 'edit_file'}.contains(toolName)) {
      final path = _safePath(map['path']);
      if (path != null) detail = ' for $path';
    } else if ({
          'run_command',
          'run_shell',
          'command_execution',
        }.contains(toolName) &&
        map['exit_code'] is int) {
      detail = ' (exit ${map['exit_code']})';
    }
    final heading = '${_safeToolName(toolName)} $outcome$detail';
    if ({'run_command', 'run_shell', 'command_execution'}.contains(toolName)) {
      final sections = <String>[];
      for (final (label, key) in const [
        ('stdout', 'stdout'),
        ('stderr', 'stderr'),
        ('output', 'output'),
      ]) {
        final value = map[key];
        if (value is String && value.isNotEmpty) {
          sections.add('$label:\n$value');
        }
      }
      if (sections.isNotEmpty) {
        final summary = message(
          '$heading\n${sections.join('\n')}',
          maxCharacters: maxToolResultCharacters,
        );
        return SafeSummary(
          summary.text,
          truncated: summary.truncated || map['truncated'] == true,
        );
      }
    }
    if (!success) {
      final error = map['error'] ?? map['message'];
      if (error != null) return text('$heading: $error');
    }
    return text(heading);
  }

  static String _safeToolName(String name) {
    final safe = name.replaceAll(_unsafeToolNameCharacters, '_');
    return safe.isEmpty ? 'tool' : safe;
  }

  static String? _safePath(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final path = value.trim();
    return path.length <= 160 ? path : '${path.substring(0, 159)}…';
  }

  static ({String text, bool truncated})? _approvalPath(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final buffer = StringBuffer('"');
    var truncated = false;
    for (final rune in value.runes) {
      final encoded = switch (rune) {
        0x09 => r'\t',
        0x0A => r'\n',
        0x0D => r'\r',
        0x22 => r'\"',
        0x5C => r'\\',
        _
            when _isUnsafeControlRune(rune) ||
                _isBidirectionalControlRune(rune) ||
                _isInvisibleApprovalRune(rune) =>
          _visibleUnicodeEscape(rune),
        _ => String.fromCharCode(rune),
      };
      if (buffer.length + encoded.length > maxApprovalPathCharacters - 2) {
        buffer.write('…');
        truncated = true;
        break;
      }
      buffer.write(encoded);
    }
    buffer.write('"');
    return (text: buffer.toString(), truncated: truncated);
  }

  static String? _displayCommand(String toolName, JsonMap arguments) {
    final command = arguments['command'];
    if (command is! String || command.trim().isEmpty) return null;
    if (toolName != 'run_command') return command.trim();
    final rawArguments = arguments['arguments'];
    if (rawArguments is! List ||
        rawArguments.any((value) => value is! String)) {
      return command.trim();
    }
    return <String>[
      command.trim(),
      ...rawArguments.cast<String>().map(_displayArgument),
    ].join(' ');
  }

  static String _displayArgument(String value) {
    if (value.isNotEmpty && _safeCommandArgument.hasMatch(value)) {
      return value;
    }
    return jsonEncode(value);
  }

  static String _prefixedLines(String value, String prefix) => value
      .split(RegExp(r'\r\n|\r|\n'))
      .map((line) => '$prefix$line')
      .join('\n');

  static SafeSummary _approvalEditPreview(String value, String prefix) {
    final whitespaceVisible = _escapeSignificantApprovalWhitespace(value);
    final safe = _escapeBidirectionalControls(whitespaceVisible);
    return _bounded(
      _prefixedLines(safe, prefix),
      maxCharacters: maxApprovalEditSideCharacters,
    );
  }

  static String _escapeSignificantApprovalWhitespace(String value) {
    final buffer = StringBuffer();
    var pendingSpaces = 0;

    void writePendingSpaces({required bool trailing}) {
      if (pendingSpaces == 0) return;
      for (var index = 0; index < pendingSpaces; index++) {
        buffer.write(trailing ? r'\u0020' : ' ');
      }
      pendingSpaces = 0;
    }

    for (final rune in value.runes) {
      if (rune == 0x20) {
        pendingSpaces++;
        continue;
      }
      if (rune == 0x0A) {
        writePendingSpaces(trailing: true);
        buffer.write('\n');
        continue;
      }
      if (rune == 0x0D) {
        writePendingSpaces(trailing: true);
        buffer.write(r'\r');
        continue;
      }
      writePendingSpaces(trailing: false);
      if (_isUnsafeControlRune(rune)) {
        buffer.write(_visibleUnicodeEscape(rune));
        continue;
      }
      if (_isInvisibleApprovalRune(rune)) {
        buffer.write(_visibleUnicodeEscape(rune));
        continue;
      }
      switch (rune) {
        case 0x09:
          buffer.write(r'\t');
        case 0x5C:
          buffer.write(r'\\');
        default:
          buffer.writeCharCode(rune);
      }
    }
    writePendingSpaces(trailing: true);
    return buffer.toString();
  }

  static bool _isUnsafeControlRune(int rune) =>
      rune <= 0x08 ||
      rune == 0x0B ||
      rune == 0x0C ||
      (rune >= 0x0E && rune <= 0x1F) ||
      (rune >= 0x7F && rune <= 0x9F);

  static bool _isBidirectionalControlRune(int rune) =>
      rune == 0x061C ||
      rune == 0x200E ||
      rune == 0x200F ||
      (rune >= 0x202A && rune <= 0x202E) ||
      (rune >= 0x2066 && rune <= 0x2069);

  // Unicode Default_Ignorable_Code_Point plus separator-like whitespace that
  // can otherwise make two distinct approval payloads render identically.
  static bool _isInvisibleApprovalRune(int rune) =>
      rune == 0x00A0 ||
      rune == 0x00AD ||
      rune == 0x034F ||
      rune == 0x061C ||
      (rune >= 0x115F && rune <= 0x1160) ||
      rune == 0x1680 ||
      (rune >= 0x17B4 && rune <= 0x17B5) ||
      (rune >= 0x180B && rune <= 0x180F) ||
      (rune >= 0x2000 && rune <= 0x200F) ||
      (rune >= 0x2028 && rune <= 0x202F) ||
      rune == 0x205F ||
      (rune >= 0x2060 && rune <= 0x206F) ||
      rune == 0x3000 ||
      rune == 0x3164 ||
      (rune >= 0xFE00 && rune <= 0xFE0F) ||
      rune == 0xFEFF ||
      rune == 0xFFA0 ||
      (rune >= 0xFFF0 && rune <= 0xFFF8) ||
      (rune >= 0x1BCA0 && rune <= 0x1BCA3) ||
      (rune >= 0x1D173 && rune <= 0x1D17A) ||
      (rune >= 0xE0000 && rune <= 0xE0FFF);

  static String _visibleUnicodeEscape(int rune) {
    final digits = rune.toRadixString(16).toUpperCase();
    return rune <= 0xFFFF ? '\\u${digits.padLeft(4, '0')}' : '\\u{$digits}';
  }

  static String _escapeBidirectionalControls(
    String value,
  ) => value.replaceAllMapped(_bidirectionalControls, (match) {
    final codePoint = match[0]!.codeUnitAt(0);
    return '\\u${codePoint.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  });

  static String _stripUnsafeControls(String value) => value
      .replaceAll(_ansiControlSequence, '')
      .replaceAll(_unsafeControlCharacters, '');

  static SafeSummary _bounded(String value, {required int maxCharacters}) {
    final safe = value.isEmpty ? 'No content' : value;
    if (safe.length <= maxCharacters) return SafeSummary(safe);
    return SafeSummary(
      '${safe.substring(0, maxCharacters - 1).trimRight()}…',
      truncated: true,
    );
  }

  static void _validateLimit(int maxCharacters) {
    if (maxCharacters < 2) {
      throw ArgumentError.value(
        maxCharacters,
        'maxCharacters',
        'must be at least 2',
      );
    }
  }
}
