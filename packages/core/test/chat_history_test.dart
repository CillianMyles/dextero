import 'dart:async';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'owns immutable per-conversation ordering and replays a cursor',
    () async {
      final store = InMemoryChatHistoryStore(
        identifiers: _SequenceIdentifiers(),
        clock: () => DateTime.utc(2026),
      );
      addTearDown(store.close);
      final conversation = await store.createConversation();

      final first = await store.append(
        conversation.id,
        const PendingChatEntry(
          kind: ChatEntryKind.userMessage,
          status: ChatEntryStatus.submitted,
          content: 'Hello',
          correlationId: 'correlation-1',
          source: ChatEntrySource.user,
        ),
      );
      final second = await store.append(
        conversation.id,
        const PendingChatEntry(
          kind: ChatEntryKind.lifecycle,
          status: ChatEntryStatus.queued,
          content: 'Message queued',
          correlationId: 'correlation-1',
          source: ChatEntrySource.dextero,
        ),
      );

      expect(first.sequence, 0);
      expect(second.sequence, 1);
      expect(first.entryId, isNot(second.entryId));
      expect(
        await store.history(conversation.id),
        orderedEquals([first, second]),
      );
      expect(
        await store.watch(conversation.id, afterSequence: 0).first,
        same(second),
      );
    },
  );

  test('buffers appends made while a watcher replays history', () async {
    final store = InMemoryChatHistoryStore(identifiers: _SequenceIdentifiers());
    addTearDown(store.close);
    final conversation = await store.createConversation();
    await store.append(
      conversation.id,
      const PendingChatEntry(
        kind: ChatEntryKind.userMessage,
        status: ChatEntryStatus.submitted,
        content: 'one',
        correlationId: 'correlation-1',
        source: ChatEntrySource.user,
      ),
    );

    final entries = <ChatHistoryEntry>[];
    final firstSeen = Completer<void>();
    final subscription = store.watch(conversation.id).listen((entry) {
      entries.add(entry);
      if (!firstSeen.isCompleted) firstSeen.complete();
    });
    await firstSeen.future;
    await store.append(
      conversation.id,
      const PendingChatEntry(
        kind: ChatEntryKind.assistantMessage,
        status: ChatEntryStatus.completed,
        content: 'two',
        correlationId: 'correlation-1',
        source: ChatEntrySource.codex,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(entries.map((entry) => entry.sequence), [0, 1]);
    await subscription.cancel();
  });

  test('rejects unknown conversations and invalid cursors', () async {
    final store = InMemoryChatHistoryStore();
    addTearDown(store.close);

    await expectLater(store.history('missing'), throwsStateError);
    expect(
      () => store.watch('missing', afterSequence: -2),
      throwsArgumentError,
    );
  });
}

final class _SequenceIdentifiers implements IdentifierGenerator {
  var _next = 0;

  @override
  String next(String prefix) => '${prefix}_${_next++}';
}
