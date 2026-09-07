import 'dart:async';

import 'src/generated/protocol.dart';
import 'src/generated/serverpod.dart' hide Message;

/// Only the transactional storage experiment; not a ChatHistoryStore adapter.
class SpikeStore {
  SpikeStore(this.session);

  final Session session;

  Future<Message> append(
    int conversationId,
    String content, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) => session.db.transaction((transaction) async {
    final conversation = await Conversation.db.findById(
      session,
      conversationId,
      transaction: transaction,
    );
    if (conversation == null) throw StateError('Unknown conversation');
    final message = await Message.db.insertRow(
      session,
      Message(
        conversationId: conversationId,
        sequence: conversation.nextSequence,
        content: content,
        source: 'user',
      ),
      transaction: transaction,
    );
    await Conversation.db.updateRow(
      session,
      conversation.copyWith(nextSequence: conversation.nextSequence + 1),
      transaction: transaction,
    );
    if (beforeCommit != null) await beforeCommit();
    if (failBeforeCommit) throw StateError('Injected failure before commit');
    return message;
  });
}
