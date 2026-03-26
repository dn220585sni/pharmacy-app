/// A message exchanged between the pharmacy and the office/warehouse.
class Message {
  final String id;
  final String subject;
  final String body;
  final String senderName;

  /// 'inbox' for received messages, 'sent' for outgoing.
  final String folder;

  /// e.g. 'office', 'warehouse', 'pharmacy'
  final String senderRole;
  final DateTime date;
  final bool isRead;

  /// Thread of replies (newest first).
  final List<MessageReply> replies;

  /// Optional label / tag (e.g. 'Терміново', 'Запит', 'Інфо').
  final String? tag;

  const Message({
    required this.id,
    required this.subject,
    required this.body,
    required this.senderName,
    required this.folder,
    required this.senderRole,
    required this.date,
    this.isRead = false,
    this.replies = const [],
    this.tag,
  });

  Message copyWith({
    bool? isRead,
    List<MessageReply>? replies,
  }) {
    return Message(
      id: id,
      subject: subject,
      body: body,
      senderName: senderName,
      folder: folder,
      senderRole: senderRole,
      date: date,
      isRead: isRead ?? this.isRead,
      replies: replies ?? this.replies,
      tag: tag,
    );
  }
}

class MessageReply {
  final String id;
  final String body;
  final String senderName;
  final String senderRole;
  final DateTime date;

  const MessageReply({
    required this.id,
    required this.body,
    required this.senderName,
    required this.senderRole,
    required this.date,
  });
}
