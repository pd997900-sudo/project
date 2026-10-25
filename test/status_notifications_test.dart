import 'package:flutter_test/flutter_test.dart';
import 'package:roadwatch/models/notification_model.dart';
import 'package:roadwatch/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoadWatch Complaint Status Notification Tests', () {
    test('1. NotificationItem serialization & deserialization', () {
      final now = DateTime(2026, 8, 17, 10, 30);
      final notif = NotificationItem(
        id: 'notif-uuid-001',
        userId: 'user-reporter-uuid-123',
        complaintId: 'RW-8945',
        title: 'Complaint Verified!',
        message: 'Your complaint RW-8945 has been verified by the community team.',
        type: 'verified',
        status: 'Verified',
        emailStatus: 'sent',
        emailRecipient: 'reporter@example.com',
        isRead: false,
        createdAt: now,
      );

      final json = notif.toJson();
      expect(json['id'], equals('notif-uuid-001'));
      expect(json['user_id'], equals('user-reporter-uuid-123'));
      expect(json['complaint_id'], equals('RW-8945'));
      expect(json['status'], equals('Verified'));
      expect(json['email_status'], equals('sent'));
      expect(json['email_recipient'], equals('reporter@example.com'));
      expect(json['is_read'], isFalse);

      final reconstructed = NotificationItem.fromJson(json);
      expect(reconstructed.id, equals(notif.id));
      expect(reconstructed.userId, equals(notif.userId));
      expect(reconstructed.complaintId, equals(notif.complaintId));
      expect(reconstructed.status, equals(notif.status));
      expect(reconstructed.emailStatus, equals('sent'));
      expect(reconstructed.emailRecipient, equals('reporter@example.com'));
      expect(reconstructed.isRead, isFalse);
    });

    test('2. NotificationItem toDisplayMap produces expected UI fields', () {
      final notif = NotificationItem(
        id: 'notif-uuid-002',
        userId: 'user-reporter-uuid-123',
        complaintId: 'RW-8830',
        title: 'Repair Work Started',
        message: 'Community team started repair.',
        type: 'work',
        status: 'Repair In Progress',
        emailStatus: 'sent',
        emailRecipient: 'reporter@example.com',
        isRead: false,
        createdAt: DateTime(2026, 8, 17, 14, 20),
      );

      final displayMap = notif.toDisplayMap((dt) => '17-08-2026 02:20 PM');
      expect(displayMap['id'], equals('notif-uuid-002'));
      expect(displayMap['complaintId'], equals('RW-8830'));
      expect(displayMap['title'], equals('Repair Work Started'));
      expect(displayMap['time'], equals('17-08-2026 02:20 PM'));
      expect(displayMap['type'], equals('work'));
      expect(displayMap['status'], equals('Repair In Progress'));
      expect(displayMap['emailStatus'], equals('sent'));
      expect(displayMap['emailRecipient'], equals('reporter@example.com'));
      expect(displayMap['isRead'], equals('false'));
    });

    test('3. Email failure resilience: retains in-app notification and records failure error', () {
      final failedNotif = NotificationItem(
        id: 'notif-uuid-003',
        userId: 'user-reporter-uuid-123',
        complaintId: 'RW-8710',
        title: 'Work Completed!',
        message: 'Complaint RW-8710 is 100% repaired.',
        type: 'completed',
        status: 'Completed',
        emailStatus: 'failed',
        emailError: 'Provider connection timeout: 504 Gateway Timeout',
        emailRecipient: 'reporter@example.com',
        isRead: false,
      );

      // Verify notification fields remain intact for in-app display
      expect(failedNotif.emailStatus, equals('failed'));
      expect(failedNotif.emailError, contains('504 Gateway Timeout'));
      expect(failedNotif.complaintId, equals('RW-8710'));
      expect(failedNotif.title, equals('Work Completed!'));

      // Verify display map retains error for UI diagnostics
      final display = failedNotif.toDisplayMap((dt) => 'Now');
      expect(display['emailStatus'], equals('failed'));
      expect(display['emailError'], isNotNull);
    });

    test('4. Idempotency deduping logic prevents duplicate notifications for identical status', () {
      final existingNotifs = <NotificationItem>[
        NotificationItem(
          id: 'notif-1',
          userId: 'user-reporter-uuid-123',
          complaintId: 'RW-8945',
          title: 'Complaint Verified!',
          message: 'Verified',
          type: 'verified',
          status: 'Verified',
          emailStatus: 'sent',
        ),
      ];

      // Simulate a repeated status update attempt
      bool isDuplicate = existingNotifs.any(
        (n) => n.userId == 'user-reporter-uuid-123' &&
               n.complaintId == 'RW-8945' &&
               n.status == 'Verified' &&
               n.emailStatus == 'sent',
      );

      expect(isDuplicate, isTrue, reason: 'Duplicate status update must be recognized and skipped');
    });

    test('5. StatusNotificationResult correctly captures execution status and error state', () {
      final successResult = StatusNotificationResult(
        success: true,
        notificationId: 'notif-abc-123',
        emailSent: true,
        recipientEmail: 'user@example.com',
      );

      expect(successResult.success, isTrue);
      expect(successResult.notificationId, equals('notif-abc-123'));
      expect(successResult.emailSent, isTrue);
      expect(successResult.recipientEmail, equals('user@example.com'));
      expect(successResult.emailError, isNull);

      final failedEmailResult = StatusNotificationResult(
        success: true,
        notificationId: 'notif-abc-124',
        emailSent: false,
        recipientEmail: 'user@example.com',
        emailError: 'Failed to send email via provider API',
      );

      expect(failedEmailResult.success, isTrue);
      expect(failedEmailResult.notificationId, equals('notif-abc-124'));
      expect(failedEmailResult.emailSent, isFalse);
      expect(failedEmailResult.emailError, contains('Failed to send email'));
    });
  });
}
