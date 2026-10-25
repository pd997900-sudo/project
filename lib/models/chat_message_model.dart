class ChatMessage {
  final String messageId;
  final String complaintId;
  final String senderId;
  final String senderName;
  final String senderRole; // 'reporter' or 'community'
  final String messageText;
  final DateTime createdAt;
  final bool isRead;

  ChatMessage({
    required this.messageId,
    required this.complaintId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.messageText,
    DateTime? createdAt,
    this.isRead = false,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isReporter => senderRole.toLowerCase() == 'reporter';
  bool get isCommunity => senderRole.toLowerCase() == 'community';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawId = json['message_id'] ?? json['id'];
    return ChatMessage(
      messageId: rawId != null ? rawId.toString() : 'msg_${DateTime.now().millisecondsSinceEpoch}',
      complaintId: (json['complaint_id'] ?? json['complaintId'] ?? '').toString(),
      senderId: (json['sender_id'] ?? json['senderId'] ?? '').toString(),
      senderName: (json['sender_name'] ?? json['senderName'] ?? 'User').toString(),
      senderRole: (json['sender_role'] ?? json['senderRole'] ?? 'reporter').toString(),
      messageText: (json['message_text'] ?? json['messageText'] ?? json['message'] ?? '').toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isRead: json['is_read'] == true || json['is_read'] == 'true',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'complaint_id': complaintId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'message_text': messageText,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
    };
  }

  ChatMessage copyWith({
    bool? isRead,
  }) {
    return ChatMessage(
      messageId: messageId,
      complaintId: complaintId,
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      messageText: messageText,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
