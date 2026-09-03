import 'dart:async';

import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/foundation.dart';

enum ChatLoadState { loading, empty, ready, error }

abstract interface class ChatApi {
  Future<HostStatus> status();

  Future<HostStatus> selectModel(String modelName);

  Future<List<ChatEntry>> history(String conversationId);

  Future<ChatSubmission> submit(ChatSubmitRequest request);

  Future<bool> cancelRun(String conversationId, String runId);

  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  );

  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence);

  Future<void> close();
}

final class ServerpodChatApi implements ChatApi {
  ServerpodChatApi({required String serverUrl, required String token}) {
    final normalizedUrl = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
    _client = Client(normalizedUrl)
      ..authKeyProvider = DexteroTokenAuthProvider(token);
  }

  late final Client _client;

  @override
  Future<HostStatus> status() => _client.control.status();

  @override
  Future<HostStatus> selectModel(String modelName) =>
      _client.control.selectModel(modelName);

  @override
  Future<List<ChatEntry>> history(String conversationId) =>
      _client.control.history(conversationId);

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) =>
      _client.control.submitMessage(request);

  @override
  Future<bool> cancelRun(String conversationId, String runId) =>
      _client.control.cancelRun(conversationId, runId);

  @override
  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  ) => _client.control.approveWork(conversationId, runId, approvalId);

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) =>
      _client.control.streamHistory(conversationId, afterSequence);

  @override
  Future<void> close() async => _client.close();
}

final class DexteroController extends ChangeNotifier {
  DexteroController({
    required ChatApi api,
    this.configured = true,
    String Function()? correlationIdFactory,
  }) : _api = api,
       _correlationIdFactory =
           correlationIdFactory ??
           (() =>
               'app-${DateTime.now().toUtc().microsecondsSinceEpoch.toString()}');

  factory DexteroController.fromEnvironment(Map<String, String> environment) {
    final token = environment['DEXTERO_CONTROL_TOKEN'];
    final configured = token != null && token.length >= 32;
    return DexteroController(
      configured: configured,
      api: configured
          ? ServerpodChatApi(
              serverUrl:
                  environment['DEXTERO_CONTROL_URL'] ??
                  'http://localhost:8080/',
              token: token,
            )
          : const _UnavailableChatApi(),
    );
  }

  final ChatApi _api;
  final String Function() _correlationIdFactory;
  final bool configured;
  final List<ChatEntry> _entries = [];
  final Set<String> _terminalRunIds = {};
  StreamSubscription<ChatEntry>? _historySubscription;
  HostStatus? _hostStatus;
  ChatLoadState _loadState = ChatLoadState.loading;
  String? _error;
  bool _submitting = false;
  bool _cancelling = false;
  bool _approving = false;
  bool _selectingModel = false;
  String? _activeRunId;
  bool _initialized = false;

  HostStatus? get hostStatus => _hostStatus;
  ChatLoadState get loadState => _loadState;
  String? get error => _error;
  bool get submitting => _submitting;
  bool get cancelling => _cancelling;
  bool get approving => _approving;
  bool get selectingModel => _selectingModel;
  bool get busy => _submitting || _activeRunId != null;
  bool get canCancel => _activeRunId != null && !_cancelling;
  bool get canSubmit => _hostStatus != null && !busy && !_selectingModel;
  bool get canSelectModel =>
      _hostStatus != null && _entries.isEmpty && !busy && !_selectingModel;
  List<ChatEntry> get entries => List.unmodifiable(_entries);

  ChatEntry? get pendingApproval {
    final resolved = _entries
        .where(
          (entry) =>
              entry.kind == ChatEntryKind.approval &&
              entry.status != ChatEntryStatus.pending,
        )
        .map((entry) => entry.approvalId)
        .whereType<String>()
        .toSet();
    for (final entry in _entries.reversed) {
      if (entry.kind == ChatEntryKind.approval &&
          entry.status == ChatEntryStatus.pending &&
          entry.approvalId != null &&
          !resolved.contains(entry.approvalId)) {
        return entry;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _loadState = ChatLoadState.loading;
    notifyListeners();
    if (!configured) {
      _setError(
        'DEXTERO_CONTROL_TOKEN is missing. Start the app with '
        '`make app-<platform>`.',
      );
      return;
    }

    try {
      _hostStatus = await _api.status();
      _entries
        ..clear()
        ..addAll(await _api.history(_hostStatus!.conversationId));
      _entries.sort((left, right) => left.sequence.compareTo(right.sequence));
      _restoreRunState();
      _loadState = _entries.isEmpty ? ChatLoadState.empty : ChatLoadState.ready;
      _error = null;
      notifyListeners();
      _subscribeToHistory();
    } on Object catch (error) {
      _setError('Cannot reach the Dextero server: $error');
    }
  }

  Future<bool> cancelActiveRun() async {
    final status = _hostStatus;
    final runId = _activeRunId;
    if (status == null || runId == null || _cancelling) return false;

    _cancelling = true;
    _error = null;
    notifyListeners();
    try {
      final accepted = await _api.cancelRun(status.conversationId, runId);
      if (!accepted) {
        _error = 'The run had already finished before cancellation.';
      }
      return accepted;
    } on Object catch (error) {
      _error = 'Run cancellation failed: $error';
      return false;
    } finally {
      _cancelling = false;
      notifyListeners();
    }
  }

  Future<bool> approvePendingWork() async {
    final status = _hostStatus;
    final approval = pendingApproval;
    final runId = approval?.runId;
    final approvalId = approval?.approvalId;
    if (status == null || runId == null || approvalId == null || _approving) {
      return false;
    }

    _approving = true;
    _error = null;
    notifyListeners();
    try {
      final accepted = await _api.approveWork(
        status.conversationId,
        runId,
        approvalId,
      );
      if (!accepted) {
        _error = 'The action no longer needs approval.';
      }
      return accepted;
    } on Object catch (error) {
      _error = 'Approval failed: $error';
      return false;
    } finally {
      _approving = false;
      notifyListeners();
    }
  }

  Future<bool> selectModel(String modelName) async {
    final status = _hostStatus;
    final normalized = modelName.trim();
    if (status == null ||
        normalized.isEmpty ||
        normalized == status.modelName ||
        !canSelectModel) {
      return false;
    }

    _selectingModel = true;
    _error = null;
    notifyListeners();
    try {
      _hostStatus = await _api.selectModel(normalized);
      return true;
    } on Object catch (error) {
      _error = 'Model selection failed: $error';
      return false;
    } finally {
      _selectingModel = false;
      notifyListeners();
    }
  }

  Future<bool> submitMessage(String message) async {
    final status = _hostStatus;
    final normalized = message.trim();
    if (status == null || normalized.isEmpty || !canSubmit) return false;

    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final submission = await _api.submit(
        ChatSubmitRequest(
          conversationId: status.conversationId,
          message: normalized,
          modelName: status.modelName,
          correlationId: _correlationIdFactory(),
        ),
      );
      _addEntry(submission.userEntry);
      _activeRunId = submission.runId;
      if (_terminalRunIds.contains(submission.runId)) _activeRunId = null;
      _loadState = ChatLoadState.ready;
      return true;
    } on Object catch (error) {
      _error = 'Message submission failed: $error';
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void _subscribeToHistory() {
    final status = _hostStatus;
    if (status == null) return;
    final afterSequence = _entries.isEmpty ? -1 : _entries.last.sequence;
    _historySubscription = _api
        .streamHistory(status.conversationId, afterSequence)
        .listen(
          (entry) {
            _addEntry(entry);
            if (entry.runId case final runId?
                when entry.kind == ChatEntryKind.lifecycle &&
                    {
                      ChatEntryStatus.completed,
                      ChatEntryStatus.failed,
                      ChatEntryStatus.cancelled,
                    }.contains(entry.status)) {
              _terminalRunIds.add(runId);
            }
            if (entry.runId == _activeRunId &&
                entry.kind == ChatEntryKind.lifecycle &&
                {
                  ChatEntryStatus.completed,
                  ChatEntryStatus.failed,
                  ChatEntryStatus.cancelled,
                }.contains(entry.status)) {
              _activeRunId = null;
            }
            if (entry.kind == ChatEntryKind.error &&
                entry.status == ChatEntryStatus.failed) {
              _error = entry.content;
            }
            notifyListeners();
          },
          onError: (Object error) {
            _error = 'Chat history stream failed: $error';
            _activeRunId = null;
            _hostStatus = null;
            notifyListeners();
          },
          onDone: () {
            _error = 'Chat history stream disconnected.';
            _activeRunId = null;
            _hostStatus = null;
            notifyListeners();
          },
        );
  }

  void _restoreRunState() {
    _terminalRunIds.clear();
    final latestSequenceByRun = <String, int>{};
    for (final entry in _entries) {
      final runId = entry.runId;
      if (runId == null) continue;
      latestSequenceByRun[runId] = entry.sequence;
      if (entry.kind == ChatEntryKind.lifecycle &&
          {
            ChatEntryStatus.completed,
            ChatEntryStatus.failed,
            ChatEntryStatus.cancelled,
          }.contains(entry.status)) {
        _terminalRunIds.add(runId);
      }
    }
    final activeRuns =
        latestSequenceByRun.entries
            .where((run) => !_terminalRunIds.contains(run.key))
            .toList()
          ..sort((left, right) => left.value.compareTo(right.value));
    _activeRunId = activeRuns.isEmpty ? null : activeRuns.last.key;
  }

  void _addEntry(ChatEntry entry) {
    if (_entries.any((existing) => existing.entryId == entry.entryId)) return;
    _entries.add(entry);
    _entries.sort((left, right) => left.sequence.compareTo(right.sequence));
    _loadState = ChatLoadState.ready;
  }

  void _setError(String message) {
    _error = message;
    _loadState = ChatLoadState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_historySubscription?.cancel());
    unawaited(_api.close());
    super.dispose();
  }
}

final class _UnavailableChatApi implements ChatApi {
  const _UnavailableChatApi();

  Never _unavailable() => throw StateError('Dextero is not configured.');

  @override
  Future<void> close() async {}

  @override
  Future<List<ChatEntry>> history(String conversationId) async =>
      _unavailable();

  @override
  Future<bool> cancelRun(String conversationId, String runId) async =>
      _unavailable();

  @override
  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  ) async => _unavailable();

  @override
  Future<HostStatus> status() async => _unavailable();

  @override
  Future<HostStatus> selectModel(String modelName) async => _unavailable();

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) =>
      Stream.error(_unavailable());

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) async =>
      _unavailable();
}
