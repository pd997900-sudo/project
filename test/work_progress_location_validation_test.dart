import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';
import 'package:roadwatch/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Work Progress 500m Location Validation & Community Actions Tests', () {
    // Reference complaint coordinates (Original Reporter GPS)
    const double complaintLat = 13.0298; // Chennai
    const double complaintLng = 80.0168;

    // Location at 400m (latitude +0.003599 deg ≈ 400 m)
    const double user400mLat = complaintLat + (400.0 / 111139.0);
    const double user400mLng = complaintLng;

    // Location at 499m (latitude +0.0044898 deg ≈ 499 m)
    const double user499mLat = complaintLat + (499.0 / 111139.0);
    const double user499mLng = complaintLng;

    // Location at 501m (latitude +0.0045078 deg ≈ 501 m)
    const double user501mLat = complaintLat + (501.0 / 111139.0);
    const double user501mLng = complaintLng;

    // Location far away (approx 50 km away)
    const double userFarAwayLat = 13.4500;
    const double userFarAwayLng = 80.1500;

    const String expectedMismatchMessage =
        'Location mismatch: capture the progress photo within 500 metres of the original reported complaint location.';

    const String expectedMissingGpsMessage =
        'Progress photo GPS coordinates are missing or invalid. A new photo with valid GPS coordinates captured at the complaint location is required.';

    late Complaint testComplaint;

    setUp(() {
      testComplaint = Complaint(
        complaintId: 'RW-LOC-TEST-500',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha Citizen',
        reporterPhone: '+91 9876543210',
        title: 'Dangerous Pothole on Main Road',
        description: 'Large crater in road asphalt causing vehicle accidents.',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: complaintLat,
        longitude: complaintLng,
        address: 'Poonamallee High Road, Chennai',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        progressPercentage: 0.0,
        realVotes: 5,
        fakeVotes: 0,
        votedUserIds: ['voter_1', 'voter_2'],
        userVotes: {'voter_1': 'real', 'voter_2': 'real'},
      );
    });

    test('1. Haversine distance formula accurately identifies <= 500m vs > 500m', () {
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

      final distFar = SupabaseService.calculateDistanceMeters(
        userFarAwayLat,
        userFarAwayLng,
        complaintLat,
        complaintLng,
      );

      // Verify <= 500 metres
      expect(dist400m, lessThanOrEqualTo(500.0));
      expect(dist400m, closeTo(400.0, 1.0));

      expect(dist499m, lessThanOrEqualTo(500.0));
      expect(dist499m, closeTo(499.0, 1.0));

      // Verify > 500 metres
      expect(dist501m, greaterThan(500.0));
      expect(dist501m, closeTo(501.0, 1.0));

      // Verify far away distance
      expect(distFar, greaterThan(40000.0));
    });

    test('2. Case A: Community User verifies complaint from another location - NO location restriction', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      expect(provider.complaints.first.status, equals('Submitted'));

      // Community user verifies from a location 50 km away
      final verifyResult = await provider.verifyComplaint(testComplaint.complaintId);
      expect(verifyResult.success, isTrue);

      final verifiedComplaint = provider.complaints.firstWhere(
        (c) => c.complaintId == testComplaint.complaintId,
      );
      expect(verifiedComplaint.status, equals('Verified'));
      expect(verifiedComplaint.isVerifiedByCommunity, isTrue);
    });

    test('3. Case A: Community User rejects complaint from another location - NO location restriction', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      // Community user marks fake from 50 km away
      final rejectResult = await provider.markFakeComplaint(testComplaint.complaintId);
      expect(rejectResult.success, isTrue);

      final rejectedComplaint = provider.complaints.firstWhere(
        (c) => c.complaintId == testComplaint.complaintId,
      );
      expect(rejectedComplaint.status, equals('Rejected'));
      expect(rejectedComplaint.isRejected, isTrue);
    });

    test('4. Case A: Community User accepts repair work and starts work from another location - NO location restriction', () async {
      final verified = testComplaint.copyWith(status: 'Verified');
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([verified.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      // Accept repair work from 50 km away
      final acceptResult = await provider.acceptComplaint(
        verified.complaintId,
        'community_worker_99',
        'Civic Repair Team',
      );
      expect(acceptResult.success, isTrue);

      var complaintInState = provider.complaints.firstWhere(
        (c) => c.complaintId == verified.complaintId,
      );
      expect(complaintInState.status, equals('Accepted'));
      expect(complaintInState.acceptedByCommunityUser, equals('community_worker_99'));

      // Start work from 50 km away
      await provider.startWork(verified.complaintId);
      complaintInState = provider.complaints.firstWhere(
        (c) => c.complaintId == verified.complaintId,
      );
      expect(complaintInState.status, equals('Work Started'));
    });

    test('5. Progress photo submission at 400m (within 500m) is ALLOWED and updates progress', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.updateWorkProgress(
        complaintId: accepted.complaintId,
        progressNote: 'Asphalt layering underway at 400m.',
        percentage: 50.0,
        imageUrl: 'https://example.com/progress_400m.jpg',
        latitude: user400mLat,
        longitude: user400mLng,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      expect(result.success, isTrue);

      final complaintAfter = provider.complaints.firstWhere(
        (c) => c.complaintId == accepted.complaintId,
      );
      expect(complaintAfter.progressPercentage, equals(50.0));
      expect(complaintAfter.updates.last.latitude, equals(user400mLat));
      expect(complaintAfter.updates.last.longitude, equals(user400mLng));
    });

    test('6. Progress photo submission at 499m (within boundary) is ALLOWED and updates progress', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.updateWorkProgress(
        complaintId: accepted.complaintId,
        progressNote: 'Safety cones placed at 499m boundary.',
        percentage: 55.0,
        imageUrl: 'https://example.com/progress_499m.jpg',
        latitude: user499mLat,
        longitude: user499mLng,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      expect(result.success, isTrue);

      final complaintAfter = provider.complaints.firstWhere(
        (c) => c.complaintId == accepted.complaintId,
      );
      expect(complaintAfter.progressPercentage, equals(55.0));
      expect(complaintAfter.updates.last.latitude, equals(user499mLat));
      expect(complaintAfter.updates.last.longitude, equals(user499mLng));
    });

    test('7. Progress photo submission at 501m (beyond 500m) is BLOCKED with exact location mismatch error', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final initialPercentage = provider.complaints.first.progressPercentage;

      final result = await provider.updateWorkProgress(
        complaintId: accepted.complaintId,
        progressNote: 'Photo taken at 501m.',
        percentage: 60.0,
        imageUrl: 'https://example.com/progress_501m.jpg',
        latitude: user501mLat,
        longitude: user501mLng,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals(expectedMismatchMessage));

      final complaintAfter = provider.complaints.firstWhere(
        (c) => c.complaintId == accepted.complaintId,
      );
      expect(complaintAfter.progressPercentage, equals(initialPercentage));
    });

    test('8. Progress photo submission beyond 500m (e.g. 50 km) is BLOCKED with location mismatch message', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.updateWorkProgress(
        complaintId: accepted.complaintId,
        progressNote: 'Photo taken far away.',
        percentage: 60.0,
        imageUrl: 'https://example.com/progress_far.jpg',
        latitude: userFarAwayLat,
        longitude: userFarAwayLng,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals(expectedMismatchMessage));
    });

    test('9. Missing photo GPS metadata (null coordinates) with photo is BLOCKED with exact error', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.updateWorkProgress(
        complaintId: accepted.complaintId,
        progressNote: 'Null coordinate photo submission test.',
        percentage: 40.0,
        imageUrl: 'https://example.com/progress_nocoords.jpg',
        latitude: null,
        longitude: null,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals(expectedMissingGpsMessage));

      final complaintAfter = provider.complaints.firstWhere((c) => c.complaintId == accepted.complaintId);
      expect(complaintAfter.progressPercentage, equals(20.0));
    });

    test('10. Invalid photo GPS metadata (0.0, 0.0) with photo is BLOCKED with exact error', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.updateWorkProgress(
        complaintId: accepted.complaintId,
        progressNote: 'Zero coordinate photo submission test.',
        percentage: 40.0,
        imageUrl: 'https://example.com/progress_nocoords.jpg',
        latitude: 0.0,
        longitude: 0.0,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals(expectedMissingGpsMessage));

      final complaintAfter = provider.complaints.firstWhere((c) => c.complaintId == accepted.complaintId);
      expect(complaintAfter.progressPercentage, equals(20.0));
    });

    test('11. Progress log update WITHOUT photo is not blocked by location restriction', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.updateWorkProgress(
        complaintId: accepted.complaintId,
        progressNote: 'Material delivery scheduled for tomorrow morning.',
        percentage: 30.0,
        imageUrl: null, // No photo
        latitude: userFarAwayLat,
        longitude: userFarAwayLng,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      expect(result.success, isTrue);

      final complaintAfter = provider.complaints.firstWhere(
        (c) => c.complaintId == accepted.complaintId,
      );
      expect(complaintAfter.progressPercentage, equals(30.0));
    });

    test('12. Original complaint coordinates are preserved and not overwritten by user location', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([testComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      await provider.updateWorkProgress(
        complaintId: testComplaint.complaintId,
        progressNote: 'Verified at location.',
        percentage: 50.0,
        imageUrl: 'https://example.com/progress_valid.jpg',
        latitude: user400mLat,
        longitude: user400mLng,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Team',
      );

      final complaintAfter = provider.complaints.firstWhere(
        (c) => c.complaintId == testComplaint.complaintId,
      );

      expect(complaintAfter.latitude, equals(complaintLat));
      expect(complaintAfter.longitude, equals(complaintLng));
    });

    test('13. Image upload failure returns actionable error and does not update progress', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      SupabaseService.mockUploadProgressImage = ({required fileName, required imageBytes, userId}) async {
        SupabaseService.lastStorageError = 'Network timeout while uploading image';
        return null;
      };

      try {
        final result = await provider.updateWorkProgress(
          complaintId: accepted.complaintId,
          progressNote: 'Testing image upload failure.',
          percentage: 50.0,
          imageUrl: 'data:image/jpeg;base64,${base64Encode([1, 2, 3, 4])}',
          latitude: user400mLat,
          longitude: user400mLng,
          communityUserId: 'comm_user_1',
          communityUserName: 'Civic Team',
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Failed to upload progress image'));

        final complaintAfter = provider.complaints.firstWhere((c) => c.complaintId == accepted.complaintId);
        expect(complaintAfter.progressPercentage, equals(20.0));
      } finally {
        SupabaseService.mockUploadProgressImage = null;
      }
    });

    test('14. Database save failure returns actionable error and does not update progress', () async {
      final accepted = testComplaint.copyWith(
        status: 'Work Started',
        acceptedByCommunityUser: 'comm_user_1',
        communityUserName: 'Civic Team',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([accepted.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      SupabaseService.mockSaveProgressUpdateInDatabase = ({
        required complaintId,
        required communityUserId,
        required communityUserName,
        required progressNote,
        imageUrl,
        required workPercentage,
        required status,
        required allUpdates,
        latitude,
        longitude,
        address,
        capturedAt,
        complaint,
      }) async {
        return SaveProgressResult(
          success: false,
          errorMessage: 'PostgreSQL connection terminated unexpectedly',
        );
      };

      try {
        final result = await provider.updateWorkProgress(
          complaintId: accepted.complaintId,
          progressNote: 'Testing database failure.',
          percentage: 60.0,
          imageUrl: 'https://example.com/progress_valid.jpg',
          latitude: user400mLat,
          longitude: user400mLng,
          communityUserId: 'comm_user_1',
          communityUserName: 'Civic Team',
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, contains('PostgreSQL connection terminated unexpectedly'));

        final complaintAfter = provider.complaints.firstWhere((c) => c.complaintId == accepted.complaintId);
        expect(complaintAfter.progressPercentage, equals(20.0));
      } finally {
        SupabaseService.mockSaveProgressUpdateInDatabase = null;
      }
    });

    test('15. Chimakurthi same address with GPS coordinates > 500m is rejected based on numeric distance', () async {
      const chimakurthiComplaintLat = 15.5821;
      const chimakurthiComplaintLng = 79.8693;

      // Photo taken 600m away in Chimakurthi (lat difference 0.0054 deg ≈ 600m)
      const chimakurthiPhotoLat = 15.5875;
      const chimakurthiPhotoLng = 79.8693;

      final chimakurthiComplaint = testComplaint.copyWith(
        complaintId: 'RW-CHIMAKURTHI-01',
        latitude: chimakurthiComplaintLat,
        longitude: chimakurthiComplaintLng,
        address: 'Main Bazaar Road, Chimakurthi, Andhra Pradesh, India',
        status: 'Work Started',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([chimakurthiComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final distance = SupabaseService.calculateDistanceMeters(
        chimakurthiPhotoLat,
        chimakurthiPhotoLng,
        chimakurthiComplaintLat,
        chimakurthiComplaintLng,
      );
      expect(distance, greaterThan(500.0));

      final result = await provider.updateWorkProgress(
        complaintId: chimakurthiComplaint.complaintId,
        progressNote: 'Photo taken across town in Chimakurthi',
        percentage: 50.0,
        imageUrl: 'https://example.com/chimakurthi_far.jpg',
        latitude: chimakurthiPhotoLat,
        longitude: chimakurthiPhotoLng,
        address: 'RTC Bus Stand, Chimakurthi, Andhra Pradesh, India',
      );

      // Must be blocked despite both displaying Chimakurthi because numeric distance > 500m
      expect(result.success, isFalse);
      expect(result.errorMessage, equals(expectedMismatchMessage));
    });

    test('16. Chimakurthi same address within 500m numeric distance (e.g. 400m) is allowed', () async {
      const chimakurthiComplaintLat = 15.5821;
      const chimakurthiComplaintLng = 79.8693;

      // Photo taken 400m away in Chimakurthi (lat difference: 400 / 111139 ≈ 0.0036 deg)
      const chimakurthiPhotoLat = chimakurthiComplaintLat + (400.0 / 111139.0);
      const chimakurthiPhotoLng = 79.8693;

      final chimakurthiComplaint = testComplaint.copyWith(
        complaintId: 'RW-CHIMAKURTHI-02',
        latitude: chimakurthiComplaintLat,
        longitude: chimakurthiComplaintLng,
        address: 'Main Bazaar Road, Chimakurthi, Andhra Pradesh, India',
        status: 'Work Started',
        progressPercentage: 20.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([chimakurthiComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final distance = SupabaseService.calculateDistanceMeters(
        chimakurthiPhotoLat,
        chimakurthiPhotoLng,
        chimakurthiComplaintLat,
        chimakurthiComplaintLng,
      );
      expect(distance, lessThanOrEqualTo(500.0));

      final result = await provider.updateWorkProgress(
        complaintId: chimakurthiComplaint.complaintId,
        progressNote: 'Photo taken at 400m in Chimakurthi',
        percentage: 50.0,
        imageUrl: 'https://example.com/chimakurthi_close.jpg',
        latitude: chimakurthiPhotoLat,
        longitude: chimakurthiPhotoLng,
        address: 'Main Bazaar Road, Chimakurthi, Andhra Pradesh, India',
      );

      expect(result.success, isTrue);
      final updated = provider.complaints.firstWhere((c) => c.complaintId == chimakurthiComplaint.complaintId);
      expect(updated.progressPercentage, equals(50.0));
    });
  });
}
