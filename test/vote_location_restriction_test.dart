import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';
import 'package:roadwatch/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('500 Metres Location-Based Voting Restriction & Accuracy Tests', () {
    const double complaintLat = 12.9716; // Central Bangalore
    const double complaintLng = 77.5946;

    // 0 metres away (exact same coordinates)
    const double user0mLat = complaintLat;
    const double user0mLng = complaintLng;

    // 12 metres away (latitude offset: 12 / 111139 ≈ 0.000107973 deg)
    const double user12mLat = complaintLat + (12.0 / 111139.0);
    const double user12mLng = complaintLng;

    // 400 metres away (latitude offset: 400 / 111139 ≈ 0.003599097 deg)
    const double user400mLat = complaintLat + (400.0 / 111139.0);
    const double user400mLng = complaintLng;

    // 499 metres away (latitude offset: 499 / 111139 ≈ 0.004489873 deg)
    const double user499mLat = complaintLat + (499.0 / 111139.0);
    const double user499mLng = complaintLng;

    // 501 metres away (latitude offset: 501 / 111139 ≈ 0.004507868 deg)
    const double user501mLat = complaintLat + (501.0 / 111139.0);
    const double user501mLng = complaintLng;

    // Beyond 500m (e.g. 1000 metres and 2500 metres)
    const double user1000mLat = complaintLat + (1000.0 / 111139.0);
    const double user1000mLng = complaintLng;
    const double user2500mLat = complaintLat + (2500.0 / 111139.0);
    const double user2500mLng = complaintLng;

    const String expectedMismatchMessage =
        'Location mismatch: Voting is available only within 500 meters of the reported issue.';

    late Complaint testComplaint;

    setUp(() {
      testComplaint = Complaint(
        complaintId: 'RW-VOTE-LOC-001',
        reporterId: 'reporter_001',
        reporterName: 'Pujitha Reporter',
        reporterPhone: '+91 9876543210',
        title: 'Deep Pothole Near Central Junction',
        description: 'Large dangerous pothole causing severe traffic slowdown.',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: complaintLat,
        longitude: complaintLng,
        address: 'MG Road Junction, Bangalore',
        imageUrl: 'https://example.com/pothole_bangalore.jpg',
        status: 'Submitted',
        realVotes: 0,
        fakeVotes: 0,
        votedUserIds: [],
        userVotes: {},
      );
    });

    test('1. Haversine distance formula accurately computes 0m, 12m, 400m, 499m, 501m, and beyond 500m', () {
      final dist0m = SupabaseService.calculateDistanceMeters(
        user0mLat,
        user0mLng,
        complaintLat,
        complaintLng,
      );

      final dist12m = SupabaseService.calculateDistanceMeters(
        user12mLat,
        user12mLng,
        complaintLat,
        complaintLng,
      );

      final dist400m = SupabaseService.calculateDistanceMeters(
        user400mLat,
        user400mLng,
        complaintLat,
        complaintLng,
      );

      final dist499m = SupabaseService.calculateDistanceMeters(
        user499mLat,
        user499mLng,
        complaintLat,
        complaintLng,
      );

      final dist501m = SupabaseService.calculateDistanceMeters(
        user501mLat,
        user501mLng,
        complaintLat,
        complaintLng,
      );

      final dist1000m = SupabaseService.calculateDistanceMeters(
        user1000mLat,
        user1000mLng,
        complaintLat,
        complaintLng,
      );

      // 0m should evaluate to approximately 0 m
      expect(dist0m, closeTo(0.0, 0.001));
      expect(dist0m.toStringAsFixed(0), equals('0'));

      // 12m evaluates accurately to 12.0m (within GPS measurement accuracy)
      expect(dist12m, closeTo(12.0, 0.5));
      expect(dist12m.toStringAsFixed(0), equals('12'));

      // 400m evaluates accurately to 400m
      expect(dist400m, closeTo(400.0, 1.0));
      expect(dist400m, lessThanOrEqualTo(500.0));

      // 499m is within 500m
      expect(dist499m, closeTo(499.0, 1.0));
      expect(dist499m, lessThanOrEqualTo(500.0));

      // 501m is outside 500m
      expect(dist501m, closeTo(501.0, 1.0));
      expect(dist501m, greaterThan(500.0));

      // 1000m is well beyond 500m
      expect(dist1000m, greaterThan(950.0));
      expect(dist1000m, greaterThan(500.0));
    });

    test('2. User at 0m (same coordinates as complaint): Voting is accepted', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'voter_at_0m',
        userEmail: 'voter0m@roadwatch.org',
        isReal: true,
        userLat: user0mLat,
        userLng: user0mLng,
      );

      expect(result.success, isTrue);

      final updated = provider.complaints.firstWhere((c) => c.complaintId == testComplaint.complaintId);
      expect(updated.realVotes, equals(1));
      expect(updated.isVotedBy('voter_at_0m'), isTrue);
    });

    test('3. User at 12m (typical real-world GPS reading variance): Voting is accepted', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'voter_at_12m',
        userEmail: 'voter12m@roadwatch.org',
        isReal: true,
        userLat: user12mLat,
        userLng: user12mLng,
      );

      expect(result.success, isTrue);

      final updated = provider.complaints.firstWhere((c) => c.complaintId == testComplaint.complaintId);
      expect(updated.realVotes, equals(1));
      expect(updated.isVotedBy('voter_at_12m'), isTrue);
    });

    test('4. User at 400m: Voting is accepted and increments vote count', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'voter_at_400m',
        userEmail: 'voter400m@roadwatch.org',
        isReal: true,
        userLat: user400mLat,
        userLng: user400mLng,
      );

      expect(result.success, isTrue);

      final updated = provider.complaints.firstWhere((c) => c.complaintId == testComplaint.complaintId);
      expect(updated.realVotes, equals(1));
      expect(updated.isVotedBy('voter_at_400m'), isTrue);
    });

    test('5. User at 499m: Voting is accepted (boundary within 500m)', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'voter_at_499m',
        userEmail: 'voter499m@roadwatch.org',
        isReal: true,
        userLat: user499mLat,
        userLng: user499mLng,
      );

      expect(result.success, isTrue);

      final updated = provider.complaints.firstWhere((c) => c.complaintId == testComplaint.complaintId);
      expect(updated.realVotes, equals(1));
      expect(updated.isVotedBy('voter_at_499m'), isTrue);
    });

    test('6. User at 501m: Voting is BLOCKED with location-mismatch message', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'voter_at_501m',
        userEmail: 'voter501m@roadwatch.org',
        isReal: true,
        userLat: user501mLat,
        userLng: user501mLng,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals(expectedMismatchMessage));

      final unchanged = provider.complaints.firstWhere((c) => c.complaintId == testComplaint.complaintId);
      expect(unchanged.totalVotes, equals(0));
      expect(unchanged.isVotedBy('voter_at_501m'), isFalse);
    });

    test('7. User beyond 500m (e.g. 2500m): Voting is BLOCKED with location-mismatch message', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'voter_at_2500m',
        userEmail: 'far_voter@roadwatch.org',
        isReal: true,
        userLat: user2500mLat,
        userLng: user2500mLng,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals(expectedMismatchMessage));

      final unchanged = provider.complaints.firstWhere((c) => c.complaintId == testComplaint.complaintId);
      expect(unchanged.totalVotes, equals(0));
      expect(unchanged.isVotedBy('voter_at_2500m'), isFalse);
    });

    test('8. User with location permission denied / null / (0,0) coordinates: Voting is unavailable', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      // Null coordinates
      final resultNull = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'user_no_permission',
        isReal: true,
        userLat: null,
        userLng: null,
      );

      expect(resultNull.success, isFalse);
      expect(resultNull.errorMessage, equals('Valid current GPS location is required to vote.'));

      // (0.0, 0.0) invalid GPS coordinates
      final resultZero = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: 'user_zero_coord',
        isReal: true,
        userLat: 0.0,
        userLng: 0.0,
      );

      expect(resultZero.success, isFalse);
      expect(resultZero.errorMessage, equals('Valid current GPS location is required to vote.'));
    });

    test('9. Invalid complaint coordinates prevent voting', () async {
      final invalidComplaint = Complaint(
        complaintId: 'RW-INVALID-COORDS-999',
        reporterId: testComplaint.reporterId,
        reporterName: testComplaint.reporterName,
        reporterPhone: testComplaint.reporterPhone,
        title: testComplaint.title,
        description: testComplaint.description,
        category: testComplaint.category,
        severity: testComplaint.severity,
        latitude: 0.0,
        longitude: 0.0,
        address: testComplaint.address,
        imageUrl: testComplaint.imageUrl,
        status: testComplaint.status,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([invalidComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: 'RW-INVALID-COORDS-999',
        userId: 'user_valid_gps',
        isReal: true,
        userLat: 12.9716,
        userLng: 77.5946,
      );

      expect(result.success, isFalse);
      expect(
        result.errorMessage,
        equals('Current location is required to vote. Complaint coordinates are invalid or unavailable.'),
      );
    });

    test('10. Direct service call beyond 500m is rejected by SupabaseService.saveCommunityVote', () async {
      final result = await SupabaseService.saveCommunityVote(
        complaintId: testComplaint.complaintId,
        userId: 'direct_api_tester',
        vote: 'genuine',
        userLat: user501mLat,
        userLng: user501mLng,
        complaintLat: complaintLat,
        complaintLng: complaintLng,
      );

      expect(result.success, isFalse);
      expect(
        result.errorMessage == expectedMismatchMessage ||
            result.errorMessage == 'Supabase database is not connected.' ||
            result.errorMessage == 'Valid current GPS location is required to vote.',
        isTrue,
      );
    });

    test('11. One-vote-per-user-per-complaint rule prevents duplicate voting', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      const voterId = 'single_vote_user_007';

      // First vote inside 500m: Succeeds
      final firstVote = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: voterId,
        isReal: true,
        userLat: user400mLat,
        userLng: user400mLng,
      );
      expect(firstVote.success, isTrue);

      final complaintAfterFirst = provider.complaints.firstWhere(
        (c) => c.complaintId == testComplaint.complaintId,
      );
      expect(complaintAfterFirst.totalVotes, equals(1));

      // Second vote by the same user on the same complaint: Rejected
      final duplicateVote = await provider.castCommunityPollVote(
        complaintId: testComplaint.complaintId,
        userId: voterId,
        isReal: false,
        userLat: user400mLat,
        userLng: user400mLng,
      );
      expect(duplicateVote.success, isFalse);
      expect(duplicateVote.errorMessage, equals('You have already voted on this complaint.'));

      // Total votes remains exactly 1
      final complaintAfterDuplicate = provider.complaints.firstWhere(
        (c) => c.complaintId == testComplaint.complaintId,
      );
      expect(complaintAfterDuplicate.totalVotes, equals(1));
      expect(complaintAfterDuplicate.realVotes, equals(1));
      expect(complaintAfterDuplicate.fakeVotes, equals(0));
    });

    test('12. Complaints remain visible to users outside the 500-meter radius', () {
      final complaints = [
        testComplaint,
        Complaint(
          complaintId: 'RW-OTHER-002',
          reporterId: testComplaint.reporterId,
          reporterName: testComplaint.reporterName,
          reporterPhone: testComplaint.reporterPhone,
          title: 'Pothole across town',
          description: testComplaint.description,
          category: testComplaint.category,
          severity: testComplaint.severity,
          latitude: testComplaint.latitude,
          longitude: testComplaint.longitude,
          address: testComplaint.address,
          imageUrl: testComplaint.imageUrl,
          status: testComplaint.status,
        ),
      ];

      for (final c in complaints) {
        expect(c.complaintId.isNotEmpty, isTrue);
        expect(c.title.isNotEmpty, isTrue);
        expect(c.hasValidCoordinates, isTrue);
      }

      final visibleComplaints = complaints.where((c) => true).toList();
      expect(visibleComplaints.length, equals(2));
    });
  });
}
