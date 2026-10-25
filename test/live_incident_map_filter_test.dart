import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final activeC = Complaint(
      complaintId: 'RW-ACTIVE-101',
      reporterId: 'rep_1',
      reporterName: 'Reporter 1',
      title: 'Active Pothole',
      description: 'Pothole on Main St',
      category: 'Pothole',
      severity: 'Medium',
      latitude: 13.0298,
      longitude: 80.0168,
      address: 'Main St',
      imageUrl: 'https://example.com/active.jpg',
      status: 'Work Started',
      progressPercentage: 40.0,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    );
    final completedC = Complaint(
      complaintId: 'RW-COMP-102',
      reporterId: 'rep_1',
      reporterName: 'Reporter 1',
      title: 'Fixed Road',
      description: 'Pothole fixed',
      category: 'Pothole',
      severity: 'Low',
      latitude: 13.0299,
      longitude: 80.0169,
      address: 'Second St',
      imageUrl: 'https://example.com/fixed.jpg',
      status: 'Completed',
      progressPercentage: 100.0,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    SharedPreferences.setMockInitialValues({
      'roadwatch_complaints_db_v1': jsonEncode([activeC.toJson(), completedC.toJson()]),
    });
  });

  group('Live Incident Map Filtering Tests', () {
    test('Complaint.isActive returns true for active unresolved statuses', () {
      final activeStatuses = [
        'Submitted',
        'Under Verification',
        'Verified',
        'Accepted',
        'Work Started',
        'Repair In Progress',
        'Near Completion',
      ];

      for (var s in activeStatuses) {
        final c = Complaint(
          complaintId: 'RW-TEST-1',
          reporterId: 'rep_1',
          reporterName: 'Reporter 1',
          title: 'Damaged Road',
          description: 'Pothole on main street',
          category: 'Pothole',
          severity: 'Emergency',
          latitude: 13.0298,
          longitude: 80.0168,
          address: 'Main St',
          imageUrl: 'https://example.com/photo.jpg',
          status: s,
          progressPercentage: 40.0,
        );
        expect(c.isActive, isTrue, reason: 'Status $s should be active');
        expect(c.isCompleted, isFalse);
      }
    });

    test('Complaint.isActive returns false for completed and repaired statuses', () {
      final completedComplaint = Complaint(
        complaintId: 'RW-TEST-2',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        title: 'Damaged Road',
        description: 'Fixed hole',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St',
        imageUrl: 'https://example.com/photo.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
      );

      expect(completedComplaint.isActive, isFalse);
      expect(completedComplaint.isCompleted, isTrue);

      final repairedComplaint = Complaint(
        complaintId: 'RW-TEST-2B',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        title: 'Damaged Road',
        description: 'Repaired road',
        category: 'Pothole',
        severity: 'Medium',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St',
        imageUrl: 'https://example.com/photo.jpg',
        status: 'Repaired',
        progressPercentage: 100.0,
      );

      expect(repairedComplaint.isActive, isFalse);

      final rejectedComplaint = Complaint(
        complaintId: 'RW-TEST-3',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        title: 'Fake Road',
        description: 'Spam report',
        category: 'Pothole',
        severity: 'Low',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St',
        imageUrl: 'https://example.com/photo.jpg',
        status: 'Rejected',
      );

      expect(rejectedComplaint.isActive, isFalse);
      expect(rejectedComplaint.isRejected, isTrue);
    });

    test('activeComplaints excludes completed complaints while preserving counts and history', () async {
      final provider = ComplaintProvider();
      // Ensure initial load completes
      await Future.delayed(const Duration(milliseconds: 100));

      final activeList = provider.activeComplaints;
      final allList = provider.complaints;

      // 1. activeComplaints must not contain any completed complaint
      for (var c in activeList) {
        expect(c.status, isNot(equals('Completed')));
        expect(c.status.toLowerCase(), isNot(equals('repaired')));
        expect(c.isCompleted, isFalse);
        expect(c.isActive, isTrue);
      }

      // 2. all complaints list preserves completed complaints
      final completedInAll = allList.where((c) => c.status == 'Completed').toList();
      expect(completedInAll.length, equals(provider.completedCount));

      // 3. pendingCount matches active complaint logic
      expect(provider.pendingCount, equals(allList.where((c) => c.status != 'Completed' && c.status != 'Rejected').length));
    });

    test('Marking repair work completed removes complaint from activeComplaints but preserves all data in complaints', () async {
      final provider = ComplaintProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Pick an active complaint
      final active = provider.activeComplaints.first;
      final targetId = active.complaintId;
      final originalPhoto = active.imageUrl;

      // Verify it is currently in activeComplaints
      expect(provider.activeComplaints.any((c) => c.complaintId == targetId), isTrue);

      // Complete the repair work
      await provider.completeWork(
        complaintId: targetId,
        afterImageUrl: 'https://example.com/after_repair.jpg',
        completionNotes: 'Pothole asphalt patched and sealed.',
      );

      // Verify it is immediately REMOVED from activeComplaints
      expect(provider.activeComplaints.any((c) => c.complaintId == targetId), isFalse);

      // Verify complaint record is PRESERVED in complaints with all details intact
      final preserved = provider.complaints.firstWhere((c) => c.complaintId == targetId);
      expect(preserved.status, equals('Completed'));
      expect(preserved.progressPercentage, equals(100.0));
      expect(preserved.imageUrl, equals(originalPhoto));
      expect(preserved.afterImageUrl, equals('https://example.com/after_repair.jpg'));
      expect(preserved.completionNotes, equals('Pothole asphalt patched and sealed.'));
      expect(preserved.updates, isNotEmpty);
      expect(preserved.updates.last.workPercentage, equals(100.0));
    });

    test('Completed complaint remains excluded from activeComplaints even after reporter submits feedback', () async {
      final provider = ComplaintProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Pick an active complaint and complete it
      final target = provider.activeComplaints.first;
      final targetId = target.complaintId;

      await provider.completeWork(
        complaintId: targetId,
        afterImageUrl: 'https://example.com/after_repair.jpg',
        completionNotes: 'Repairs completed by community crew.',
      );

      expect(provider.activeComplaints.any((c) => c.complaintId == targetId), isFalse);

      // Reporter submits feedback & rating on the completed complaint
      final feedbackResult = await provider.submitFeedback(
        complaintId: targetId,
        reporterId: target.reporterId,
        reporterName: target.reporterName,
        rating: 5.0,
        comments: 'Excellent quality asphalt repair, smooth driving now!',
      );

      expect(feedbackResult.success, isTrue);

      // Complaint MUST still be excluded from activeComplaints (Live Incident Map pins)
      expect(provider.activeComplaints.any((c) => c.complaintId == targetId), isFalse);

      // Complaint in full history preserves the rating and comments
      final complaintInHistory = provider.complaints.firstWhere((c) => c.complaintId == targetId);
      expect(complaintInHistory.status, equals('Completed'));
      expect(complaintInHistory.hasValidFeedback, isTrue);
      expect(complaintInHistory.feedback?.rating, equals(5.0));
      expect(complaintInHistory.feedback?.comments, equals('Excellent quality asphalt repair, smooth driving now!'));
      expect(complaintInHistory.afterImageUrl, equals('https://example.com/after_repair.jpg'));
      expect(complaintInHistory.completionNotes, equals('Repairs completed by community crew.'));
    });

    test('Resolved, closed, and community-flagged fake complaints are excluded from activeComplaints', () {
      final resolved = Complaint(
        complaintId: 'RW-RESOLVED',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        title: 'Resolved Issue',
        description: 'Fixed',
        category: 'Pothole',
        severity: 'Low',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St',
        imageUrl: 'https://example.com/photo.jpg',
        status: 'Resolved',
      );
      expect(resolved.isActive, isFalse);
      expect(resolved.isCompleted, isTrue);

      final closed = Complaint(
        complaintId: 'RW-CLOSED',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        title: 'Closed Issue',
        description: 'Closed',
        category: 'Pothole',
        severity: 'Low',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St',
        imageUrl: 'https://example.com/photo.jpg',
        status: 'Closed',
      );
      expect(closed.isActive, isFalse);
      expect(closed.isCompleted, isTrue);

      final fakeVoted = Complaint(
        complaintId: 'RW-FAKE-VOTED',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        title: 'Fake Issue',
        description: 'Fake report',
        category: 'Pothole',
        severity: 'Low',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St',
        imageUrl: 'https://example.com/photo.jpg',
        status: 'Submitted',
        realVotes: 1,
        fakeVotes: 4,
      );
      expect(fakeVoted.isCommunityFlaggedFake, isTrue);
      expect(fakeVoted.isActive, isFalse);
      expect(fakeVoted.isRejected, isTrue);
    });
  });
}
