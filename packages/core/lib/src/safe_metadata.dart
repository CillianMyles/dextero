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
    final path = _safePath(arguments['path']);
    final detail = path == null ? '' : ' for $path';
    final heading = _escapeBidirectionalControls(
      '${_safeToolName(toolName)} requires approval$detail',
    );
    final oldText = arguments['oldText'];
    final newText = arguments['newText'];
    if (oldText is! String || newText is! String) return text(heading);
    final oldPreview = message(
      _prefixedLines(_escapeBidirectionalControls(oldText), '-'),
      maxCharacters: maxApprovalEditSideCharacters,
    );
    final newPreview = message(
      _prefixedLines(_escapeBidirectionalControls(newText), '+'),
      maxCharacters: maxApprovalEditSideCharacters,
    );
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
          preview.truncated || oldPreview.truncated || newPreview.truncated,
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
