import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/foundation.dart';

final class DexteroController extends ChangeNotifier {
  DexteroController({required this.token, required this.serverUrl});

  factory DexteroController.fromEnvironment(Map<String, String> environment) {
    return DexteroController(
      token: environment['DEXTERO_CONTROL_TOKEN'],
      serverUrl: environment['DEXTERO_CONTROL_URL'] ?? 'http://localhost:8080/',
    );
  }

  final String? token;
  final String serverUrl;

  Client? _client;
  HostStatus? _hostStatus;
  String? _error;
  bool _busy = false;
  final List<TaskEvent> _events = [];

  HostStatus? get hostStatus => _hostStatus;
  String? get error => _error;
  bool get busy => _busy;
  bool get configured => token != null && token!.length >= 32;
  List<TaskEvent> get events => List.unmodifiable(_events);

  Future<void> initialize() async {
    if (!configured) {
      _error =
          'DEXTERO_CONTROL_TOKEN is missing. Start the app with `make app`.';
      notifyListeners();
      return;
    }

    final normalizedUrl = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
    _client = Client(normalizedUrl)
      ..authKeyProvider = DexteroTokenAuthProvider(token!);
    try {
      _hostStatus = await _client!.control.status();
      _error = null;
    } on Object catch (error) {
      _error = 'Cannot reach the Dextero server: $error';
    }
    notifyListeners();
  }

  Future<void> runTask(String prompt) async {
    final client = _client;
    final normalizedPrompt = prompt.trim();
    if (client == null || normalizedPrompt.isEmpty || _busy) return;

    _busy = true;
    _error = null;
    _events.clear();
    notifyListeners();
    try {
      await for (final event in client.control.runTask(normalizedPrompt)) {
        _events.add(event);
        if (event.kind == TaskEventKind.failed) _error = event.message;
        notifyListeners();
      }
    } on Object catch (error) {
      _error = 'Task stream failed: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
