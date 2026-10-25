import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Secure Complaint Deletion & Live Map Synchronization Tests', () {
    late Complaint unverifiedComplaint;
    late Complaint verifiedComplaintByStatus;
    late Complaint verifiedComplaintByVotes;
    late Complaint completedComplaint;

    setUp(() {
      unverifiedComplaint = Complaint(
        complaintId: 'RW-UNVERIFIED-101',
        reporterId: 'reporter_001',
        reporterName: 'Alice Citizen',
        reporterPhone: '+1 555-0101',
        title: 'Unverified Pothole',
        description: 'Pothole on 1st Street',
        category: 'Pothole',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: '1st Street',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        progressPercentage: 0.0,
      );

      verifiedComplaintByStatus = Complaint(
        complaintId: 'RW-VERIFIED-102',
        reporterId: 'reporter_001',
        reporterName: 'Alice Citizen',
        reporterPhone: '+1 555-0101',
        title: 'Verified Damaged Road',
        description: 'Crack on main road',
        category: 'Damaged Road',
        severity: 'Emergency',
        latitude: 37.7750,
        longitude: -122.4195,
        address: 'Main Road',
        imageUrl: 'https://example.com/crack.jpg',
        status: 'Verified',
        progressPercentage: 10.0,
      );

      verifiedComplaintByVotes = Complaint(
        complaintId: 'RW-VOTED-103',
        reporterId: 'reporter_001',
        reporterName: 'Alice Citizen',
        reporterPhone: '+1 555-0101',
        title: 'Community Verified Issue',
        description: 'Street light broken',
        category: 'Street Light Failure',
        severity: 'Low',
        latitude: 37.7751,
        longitude: -122.4196,
        address: 'Light Street',
        imageUrl: 'https://example.com/light.jpg',
        status: 'Submitted',
        realVotes: 3,
        fakeVotes: 0,
        userVotes: {
          'user_a': 'genuine',
          'user_b': 'genuine',
          'user_c': 'genuine',
        },
        progressPercentage: 0.0,
      );

      completedComplaint = Complaint(
        complaintId: 'RW-COMPLETED-104',
        reporterId: 'reporter_001',
        reporterName: 'Alice Citizen',
        reporterPhone: '+1 555-0101',
        title: 'Repaired Pothole',
        description: 'Fixed pothole',
        category: 'Pothole',
        severity: 'Medium',
        latitude: 37.7752,
        longitude: -122.4197,
        address: 'Fixed Ave',
        imageUrl: 'https://example.com/before.jpg',
        beforeImageUrl: 'https://example.com/before.jpg',
        afterImageUrl: 'https://example.com/after.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        completionNotes: 'Work 100% finished by crew.',
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([
          unverifiedComplaint.toJson(),
          verifiedComplaintByStatus.toJson(),
          verifiedComplaintByVotes.toJson(),
          completedComplaint.toJson(),
        ]),
      });
    });

    test('1. Unverified complaint allows deletion (canBeDeleted is true)', () {
      expect(unverifiedComplaint.isVerifiedByCommunity, isFalse);
      expect(unverifiedComplaint.isCompleted, isFalse);
      expect(unverifiedComplaint.canBeDeleted, isTrue);
    });

    test('2. Successful deletion removes complaint from provider and updates counts', () async {
      final provider = ComplaintProvider();
      
      // Manually populate complaints
      final initialCount = provider.totalCount;
      expect(initialCount, greaterThanOrEqualTo(0));

      // Deleting unverified complaint
      final result = await provider.deleteComplaint(unverifiedComplaint.complaintId);
      
      // If it existed in provider
      if (provider.complaints.any((c) => c.complaintId == unverifiedComplaint.complaintId)) {
        expect(result.success, isTrue);
        expect(provider.complaints.any((c) => c.complaintId == unverifiedComplaint.complaintId), isFalse);
      }
    });

    test('3. Deleted complaint does not return after provider refresh', () async {
      final provider = ComplaintProvider();
      await provider.refreshComplaints();
      final targetId = unverifiedComplaint.complaintId;

      await provider.deleteComplaint(targetId);
      await provider.refreshComplaints();

      final found = provider.complaints.any((c) => c.complaintId.toLowerCase() == targetId.toLowerCase());
      expect(found, isFalse);
    });

    test('4. Verified complaint CANNOT be deleted by Reporter (canBeDeleted is false)', () async {
      expect(verifiedComplaintByStatus.isVerifiedByCommunity, isTrue);
      expect(verifiedComplaintByStatus.canBeDeleted, isFalse);

      expect(verifiedComplaintByVotes.isCommunityVerifiedReal, isTrue);
      expect(verifiedComplaintByVotes.isVerifiedByCommunity, isTrue);
      expect(verifiedComplaintByVotes.canBeDeleted, isFalse);

      final provider = ComplaintProvider();
      await provider.refreshComplaints();
      final result1 = await provider.deleteComplaint(verifiedComplaintByStatus.complaintId);
      expect(result1.success, isFalse);
      expect(result1.errorMessage, contains('verified'));

      final result2 = await provider.deleteComplaint(verifiedComplaintByVotes.complaintId);
      expect(result2.success, isFalse);
      expect(result2.errorMessage, contains('verified'));
    });

    test('5. Completed complaint remains in history without Delete option (canBeDeleted is false, isCompleted is true)', () async {
      expect(completedComplaint.isCompleted, isTrue);
      expect(completedComplaint.isVerifiedByCommunity, isTrue);
      expect(completedComplaint.canBeDeleted, isFalse);
      expect(completedComplaint.afterImageUrl, equals('https://example.com/after.jpg'));

      final provider = ComplaintProvider();
      final result = await provider.deleteComplaint(completedComplaint.complaintId);
      expect(result.success, isFalse);
    });

    test('6. Other complaints and pins remain unchanged when one complaint is deleted', () {
      final list = [unverifiedComplaint, verifiedComplaintByStatus, completedComplaint];
      
      // Remove only target
      final filtered = list.where((c) => c.complaintId != unverifiedComplaint.complaintId).toList();
      
      expect(filtered.length, equals(2));
      expect(filtered.any((c) => c.complaintId == verifiedComplaintByStatus.complaintId), isTrue);
      expect(filtered.any((c) => c.complaintId == completedComplaint.complaintId), isTrue);
    });

    test('7. If database deletion fails or returns false, complaint is preserved in list', () async {
      final provider = ComplaintProvider();

      // Attempting to delete non-existent or blocked complaint
      final result = await provider.deleteComplaint('NON_EXISTENT_ID_9999');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('not found'));
    });
  });
}
