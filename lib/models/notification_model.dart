class NotificationItem {
  final String id;
  final String userId;
  final String complaintId;
  final String title;
  final String message;
  final String type; // 'submitted', 'verified', 'rejected', 'accepted', 'work', 'completed', 'chat', 'new_complaint', 'emergency'
  final String status; // 'Submitted', 'Verified', 'Rejected', 'Accepted', 'Work Started', 'Repair In Progress', 'Completed'
  final String emailStatus; // 'sent', 'failed', 'pending', 'skipped'
  final String? emailError;
  final String? emailRecipient;
  final bool isRead;
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.userId,
    required this.complaintId,
    required this.title,
    required this.message,
    required this.type,
    required this.status,
    this.emailStatus = 'pending',
    this.emailError,
    this.emailRecipient,
    this.isRead = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  NotificationItem copyWith({
    String? id,
    String? userId,
    String? complaintId,
    String? title,
    String? message,
    String? type,
    String? status,
    String? emailStatus,
    String? emailError,
    String? emailRecipient,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      complaintId: complaintId ?? this.complaintId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      status: status ?? this.status,
      emailStatus: emailStatus ?? this.emailStatus,
      emailError: emailError ?? this.emailError,
      emailRecipient: emailRecipient ?? this.emailRecipient,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate = DateTime.now();
    if (json['created_at'] != null) {
      parsedDate = DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now();
    }

    return NotificationItem(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      complaintId: (json['complaint_id'] ?? '').toString(),
      title: (json['title'] ?? 'Notification').toString(),
      message: (json['message'] ?? '').toString(),
      type: (json['type'] ?? 'verified').toString(),
      status: (json['status'] ?? '').toString(),
      emailStatus: (json['email_status'] ?? 'pending').toString(),
      emailError: json['email_error']?.toString(),
      emailRecipient: json['email_recipient']?.toString(),
      isRead: json['is_read'] == true,
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'complaint_id': complaintId,
      'title': title,
      'message': message,
      'type': type,
      'status': status,
      'email_status': emailStatus,
      if (emailError != null) 'email_error': emailError,
      if (emailRecipient != null) 'email_recipient': emailRecipient,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, String> toDisplayMap(String Function(DateTime) dateFormatter) {
    return {
      'id': id,
      'complaintId': complaintId,
      'title': title,
      'message': message,
      'time': dateFormatter(createdAt),
      'type': type,
      'status': status,
      'emailStatus': emailStatus,
      if (emailError != null) 'emailError': emailError!,
      if (emailRecipient != null) 'emailRecipient': emailRecipient!,
      'isRead': isRead ? 'true' : 'false',
    };
  }
}
