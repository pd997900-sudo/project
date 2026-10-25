import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoadWatch Voting Closed On Complaint Rejection Tests', () {
    const double testLat = 12.9716;
    const double testLng = 77.5946;

    late Complaint rejectedComplaint;
    late Complaint pendingComplaint;

    setUp(() {
      rejectedComplaint = Complaint(
        complaintId: 'RW-REJECTED-001',
        reporterId: 'rep_101',
        reporterName: 'Pujitha Reporter',
        reporterPhone: '+91 9876543210',
        title: 'Reported Pothole Main Road',
        description: 'Citizen report flagged as fake by inspectors.',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: testLat,
        longitude: testLng,
        address: 'MG Road, Bangalore',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Rejected',
        realVotes: 4,
        fakeVotes: 7,
        votedUserIds: ['user_1', 'user_2', 'user_3'],
        userVotes: {'user_1': 'genuine', 'user_2': 'fake', 'user_3': 'fake'},
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      );

      pendingComplaint = Complaint(
        complaintId: 'RW-PENDING-001',
        reporterId: 'rep_102',
        reporterName: 'Anil Kumar',
        reporterPhone: '+91 9876543211',
        title: 'Open Trench Near Bus Stop',
        description: 'Trench dug up on pavement.',
        category: 'Construction Hazard',
        severity: 'Emergency',
        latitude: testLat,
        longitude: testLng,
        address: 'Indiranagar 100ft Road, Bangalore',
        imageUrl: 'https://example.com/trench.jpg',
        status: 'Submitted',
        realVotes: 2,
        fakeVotes: 0,
        votedUserIds: ['user_a', 'user_b'],
        userVotes: {'user_a': 'genuine', 'user_b': 'genuine'},
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
    });

    test('1. Model flags isRejected and isVotingClosed correctly', () {
      expect(rejectedComplaint.isRejected, isTrue);
      expect(rejectedComplaint.isVotingClosed, isTrue);

      final fakeStatusComplaint = rejectedComplaint.copyWith(status: 'Fake');
      expect(fakeStatusComplaint.isRejected, isTrue);
      expect(fakeStatusComplaint.isVotingClosed, isTrue);

      expect(pendingComplaint.isRejected, isFalse);
      expect(pendingComplaint.isVotingClosed, isFalse);

      final verifiedComplaint = pendingComplaint.copyWith(status: 'Verified');
      expect(verifiedComplaint.isRejected, isFalse);
      expect(verifiedComplaint.isVotingClosed, isFalse);
    });

    test('2. Existing votes, counts, and history are preserved on rejected complaints', () {
      expect(rejectedComplaint.realVotes, equals(4));
      expect(rejectedComplaint.fakeVotes, equals(7));
      expect(rejectedComplaint.totalVotes, equals(11));
      expect(rejectedComplaint.votedUserIds, containsAll(['user_1', 'user_2', 'user_3']));
      expect(rejectedComplaint.userVotes['user_1'], equals('genuine'));
      expect(rejectedComplaint.userVotes['user_2'], equals('fake'));
    });

    test('3. castCommunityPollVote rejects voting on rejected complaints with exact message', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([rejectedComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: rejectedComplaint.complaintId,
        userId: 'new_user_123',
        userEmail: 'new_user@example.com',
        isReal: true,
        userLat: testLat, // Exactly at complaint location (0 km)
        userLng: testLng,
      );

      expect(result.success, isFalse);
      expect(
        result.errorMessage,
        equals('This complaint was rejected as fake by the community. Voting is closed.'),
      );

      // Verify vote counts and voters list remain untouched
      final complaintInProv = provider.complaints.firstWhere((c) => c.complaintId == rejectedComplaint.complaintId);
      expect(complaintInProv.realVotes, equals(4));
      expect(complaintInProv.fakeVotes, equals(7));
      expect(complaintInProv.votedUserIds.contains('new_user_123'), isFalse);
    });

    test('4. Mark fake issue closes voting and preserves existing vote counts', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([pendingComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      expect(provider.complaints.first.isVotingClosed, isFalse);
      final initialRealVotes = provider.complaints.first.realVotes;
      final initialFakeVotes = provider.complaints.first.fakeVotes;

      // Community user marks as Fake Complaint
      final markResult = await provider.markFakeComplaint(pendingComplaint.complaintId);
      expect(markResult.success, isTrue);

      final updated = provider.complaints.first;
      expect(updated.status, equals('Rejected'));
      expect(updated.isRejected, isTrue);
      expect(updated.isVotingClosed, isTrue);

      // Existing votes are preserved
      expect(updated.realVotes, equals(initialRealVotes));
      expect(updated.fakeVotes, equals(initialFakeVotes));
      expect(updated.votedUserIds, containsAll(['user_a', 'user_b']));

      // Attempting to vote on it now must be rejected
      final voteResult = await provider.castCommunityPollVote(
        complaintId: pendingComplaint.complaintId,
        userId: 'user_c',
        userEmail: 'c@example.com',
        isReal: true,
        userLat: testLat,
        userLng: testLng,
      );

      expect(voteResult.success, isFalse);
      expect(
        voteResult.errorMessage,
        equals('This complaint was rejected as fake by the community. Voting is closed.'),
      );
    });

    test('5. Rejected complaints cannot be accepted for repair', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([rejectedComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final acceptResult = await provider.acceptComplaint(
        rejectedComplaint.complaintId,
        'comm_user_1',
        'Repair Crew',
      );

      expect(acceptResult.success, isFalse);
      expect(
        acceptResult.errorMessage,
        equals('This complaint was rejected as fake and cannot be accepted for repair.'),
      );
    });

    test('6. Rejected complaints cannot receive work progress updates', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([rejectedComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final progressResult = await provider.updateWorkProgress(
        complaintId: rejectedComplaint.complaintId,
        progressNote: 'Starting road patch work.',
        percentage: 50.0,
      );

      expect(progressResult.success, isFalse);
      expect(
        progressResult.errorMessage,
        equals('This complaint was rejected as fake and cannot receive repair progress updates.'),
      );
    });

    test('7. Pending complaints remain open for voting within 2 km', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([pendingComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      // Vote within 2 km (0.5 km away)
      const double userWithin2KmLat = 12.9750;
      const double userWithin2KmLng = 77.5946;

      final voteResult = await provider.castCommunityPollVote(
        complaintId: pendingComplaint.complaintId,
        userId: 'user_voter_ok',
        userEmail: 'voter@example.com',
        isReal: true,
        userLat: userWithin2KmLat,
        userLng: userWithin2KmLng,
      );

      expect(voteResult.success, isTrue);

      final updatedComplaint = provider.complaints.firstWhere((c) => c.complaintId == pendingComplaint.complaintId);
      expect(updatedComplaint.realVotes, equals(3));
      expect(updatedComplaint.votedUserIds.contains('user_voter_ok'), isTrue);
    });
  });
}
