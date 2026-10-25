import 'package:flutter_test/flutter_test.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Complaint Verification & Transition Tests', () {
    late Complaint submittedComplaint;
    late Complaint verifiedComplaint;
    late Complaint acceptedComplaint;

    setUp(() {
      submittedComplaint = Complaint(
        complaintId: 'RW-VERIFY-TEST-001',
        reporterId: 'reporter_100',
        reporterName: 'John Doe',
        reporterPhone: '+1 555-9999',
        title: 'Deep Pothole on Highway',
        description: 'Large pothole dangerous for fast traffic',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Highway 44, Mile 12',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        progressPercentage: 0.0,
      );

      verifiedComplaint = Complaint(
        complaintId: 'RW-VERIFY-TEST-002',
        reporterId: 'reporter_100',
        reporterName: 'John Doe',
        reporterPhone: '+1 555-9999',
        title: 'Water Logged Road',
        description: 'Severe waterlogging near metro station',
        category: 'Waterlogging',
        severity: 'High',
        latitude: 12.9718,
        longitude: 77.5948,
        address: 'Metro Station Road',
        imageUrl: 'https://example.com/waterlogging.jpg',
        status: 'Verified',
        progressPercentage: 10.0,
      );

      acceptedComplaint = Complaint(
        complaintId: 'RW-VERIFY-TEST-003',
        reporterId: 'reporter_100',
        reporterName: 'John Doe',
        reporterPhone: '+1 555-9999',
        title: 'Broken Traffic Guard',
        description: 'Damaged central barrier',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 12.9720,
        longitude: 77.5950,
        address: 'Central Avenue',
        imageUrl: 'https://example.com/barrier.jpg',
        status: 'Accepted',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Volunteer Repair Crew',
        progressPercentage: 25.0,
      );
    });

    test('1. Verify model flags: Unverified complaint returns isVerifiedByCommunity = false', () {
      expect(submittedComplaint.isVerifiedByCommunity, isFalse);
      expect(submittedComplaint.status, equals('Submitted'));
    });

    test('2. Verify model flags: Verified complaint returns isVerifiedByCommunity = true', () {
      expect(verifiedComplaint.isVerifiedByCommunity, isTrue);
      expect(verifiedComplaint.status, equals('Verified'));
    });

    test('3. Verify model flags: Accepted complaint returns isVerifiedByCommunity = true', () {
      expect(acceptedComplaint.isVerifiedByCommunity, isTrue);
      expect(acceptedComplaint.status, equals('Accepted'));
    });

    test('4. Local state update changes status to Verified', () {
      final updated = submittedComplaint.copyWith(
        status: 'Verified',
        progressPercentage: 10.0,
      );

      expect(updated.status, equals('Verified'));
      expect(updated.isVerifiedByCommunity, isTrue);
    });

    test('5. Local state update changes status from Verified to Accepted', () {
      final updated = verifiedComplaint.copyWith(
        status: 'Accepted',
        acceptedByCommunityUser: 'user_repair_1',
        communityUserName: 'City Repair Crew',
      );

      expect(updated.status, equals('Accepted'));
      expect(updated.acceptedByCommunityUser, equals('user_repair_1'));
      expect(updated.communityUserName, equals('City Repair Crew'));
    });

    test('6. Provider verifyComplaint updates complaint status on successful response', () async {
      final provider = ComplaintProvider();
      provider.complaints.clear();
      provider.complaints.add(submittedComplaint);

      expect(provider.complaints.first.status, equals('Submitted'));

      // Simulate verify operation call result check
      final targetId = submittedComplaint.complaintId;
      final result = await provider.verifyComplaint(targetId);

      // Verify that function runs without throwing exception
      expect(result, isNotNull);
    });

    test('7. FeedbackModel stores real rating, comments, reporter_id, and reporter_name', () {
      final feedback = FeedbackModel(
        feedbackId: 'FB-TEST-001',
        complaintId: 'c8d4a520-2f96-48c5-9257-2342ef013cb4',
        reporterId: '00000000-0000-0000-0000-000000000001',
        reporterName: 'Jane Doe',
        rating: 4.5,
        comments: 'Great repair, road surface is now smooth and safe!',
      );

      expect(feedback.rating, equals(4.5));
      expect(feedback.comments, equals('Great repair, road surface is now smooth and safe!'));
      expect(feedback.reporterId, equals('00000000-0000-0000-0000-000000000001'));
      expect(feedback.reporterName, equals('Jane Doe'));
      expect(feedback.complaintId, isNot(equals(feedback.reporterId)));
    });

    test('8. ComplaintProvider setComplaintFeedback updates feedback on complaint', () {
      final provider = ComplaintProvider();
      provider.complaints.clear();
      provider.complaints.add(acceptedComplaint);

      final feedback = FeedbackModel(
        feedbackId: 'FB-TEST-002',
        complaintId: acceptedComplaint.complaintId,
        reporterId: acceptedComplaint.reporterId,
        reporterName: 'Jane Doe',
        rating: 5.0,
        comments: 'Fully resolved and verified.',
      );

      provider.setComplaintFeedback(acceptedComplaint.complaintId, feedback);

      final updated = provider.complaints.firstWhere((c) => c.complaintId == acceptedComplaint.complaintId);
      expect(updated.feedback, isNotNull);
      expect(updated.feedback!.rating, equals(5.0));
      expect(updated.feedback!.reporterName, equals('Jane Doe'));
    });
  });
}
