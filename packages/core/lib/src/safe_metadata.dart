import 'tool.dart';

final class SafeSummary {
  const SafeSummary(this.text, {this.truncated = false});

  final String text;
  final bool truncated;
}

/// Produces display metadata without retaining raw tool inputs or outputs.
abstract final class SafeMetadata {
  static const maxDisplayCharacters = 480;
  static const maxMessageCharacters = 16000;

  static SafeSummary text(
    Object? value, {
    int maxCharacters = maxDisplayCharacters,
  }) {
    _validateLimit(maxCharacters);
    var safe =
        _stripUnsafeControls(_redact(value?.toString() ?? 'Unknown error'))
            .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
            .replaceAll(RegExp(r' {2,}'), ' ')
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
    var safe = _stripUnsafeControls(_redact(value?.toString() ?? ''))
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
    } else if (toolName == 'run_process' && arguments['executable'] is String) {
      detail = ' for ${_safeExecutable(arguments['executable']! as String)}';
    }
    return text('${_safeToolName(toolName)} started$detail');
  }

  static String toolName(String value) {
    final safe = _safeToolName(_stripUnsafeControls(value));
    return safe.length <= 128 ? safe : safe.substring(0, 128);
  }

  static String identifier(String value) {
    final safe = _stripUnsafeControls(
      value,
    ).replaceAll(RegExp(r'[^a-zA-Z0-9_.:-]'), '_');
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
      return text('${_safeToolName(toolName)} $outcome');
    }
    final map = result.cast<Object?, Object?>();
    var detail = '';
    if (toolName == 'list_files' && map['entries'] is List) {
      detail = ' (${(map['entries']! as List).length} entries)';
    } else if ({'read_file', 'edit_file'}.contains(toolName)) {
      final path = _safePath(map['path']);
      if (path != null) detail = ' for $path';
    } else if ({'run_process', 'bash'}.contains(toolName) &&
        map['exitCode'] is int) {
      detail = ' (exit ${map['exitCode']})';
    }
    return text('${_safeToolName(toolName)} $outcome$detail');
  }

  static String _safeToolName(String name) {
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return safe.isEmpty ? 'tool' : safe;
  }

  static String? _safePath(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final redacted = _redact(value.trim());
    return redacted.length <= 160 ? redacted : '${redacted.substring(0, 159)}…';
  }

  static String _safeExecutable(String value) {
    final normalized = value.replaceAll('\\', '/');
    return _redact(normalized.split('/').last);
  }

  static String _redact(String value) {
    var safe = value;
    safe = safe.replaceAll(
      RegExp(r'\bbearer\s+[a-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    safe = safe.replaceAllMapped(
      RegExp(
        r'''\b(authorization|api[_-]?key|access[_-]?token|token|secret|password|cookie)\b\s*[:=]\s*["']?[^\s,"'}]+''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    safe = safe.replaceAll(RegExp(r'\bsk-[a-zA-Z0-9_-]{12,}\b'), '[REDACTED]');
    return safe;
  }

  static String _stripUnsafeControls(String value) => value
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(
        RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
        '',
      );

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
