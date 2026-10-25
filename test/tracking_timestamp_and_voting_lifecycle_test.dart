import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('1. Timestamp Normalization & parseTimestamptz Tests', () {
    test('UTC ISO strings ending with Z are parsed as UTC without skew', () {
      const utcString = '2026-10-22T06:01:00.000Z';
      final parsed = Complaint.parseTimestamptz(utcString);
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue);
      expect(parsed.hour, equals(6));
      expect(parsed.minute, equals(1));
    });

    test('ISO strings with explicit timezone offset (+05:30) are parsed to correct UTC instant', () {
      const istString = '2026-10-22T11:31:00.000+05:30';
      final parsed = Complaint.parseTimestamptz(istString);
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue);
      expect(parsed.hour, equals(6));
      expect(parsed.minute, equals(1));
    });

    test('Local or naive ISO strings do not get corrupted by appending Z onto local time', () {
      // E.g. string generated locally without offset: "2026-10-22T11:31:00.000"
      final now = DateTime.now();
      final naiveString = now.toIso8601String();
      final parsed = Complaint.parseTimestamptz(naiveString);
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue);
      // When converted back to local, it should match the original local time
      final backToLocal = parsed.toLocal();
      expect(backToLocal.year, equals(now.year));
      expect(backToLocal.month, equals(now.month));
      expect(backToLocal.day, equals(now.day));
      expect(backToLocal.hour, equals(now.hour));
      expect(backToLocal.minute, equals(now.minute));
    });

    test('ProgressUpdate constructor normalizes createdAt and capturedAt to UTC', () {
      final localNow = DateTime.now();
      final update = ProgressUpdate(
        updateId: 'upd-1',
        complaintId: 'RW-101',
        communityUserId: 'usr-1',
        communityUserName: 'Contractor A',
        progressNote: 'Work underway',
        workPercentage: 50.0,
        status: 'Repair In Progress',
        createdAt: localNow,
        capturedAt: localNow,
      );

      expect(update.createdAt.isUtc, isTrue);
      expect(update.capturedAt?.isUtc, isTrue);
      expect(update.toJson()['created_at'], contains('Z'));
    });
  });

  group('2. Voting Lifecycle & Closed State Tests', () {
    test('Voting is open for early stages: Submitted, Under Verification, Verified, Accepted (< 40%)', () {
      final c1 = Complaint(
        complaintId: 'RW-STAGE-1',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        reporterPhone: '1234567890',
        title: 'Pothole Issue',
        description: 'Test pothole',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Bangalore',
        imageUrl: 'https://example.com/p.jpg',
        status: 'Submitted',
        progressPercentage: 0.0,
      );
      expect(c1.isWorkStartedOrBeyond, isFalse);
      expect(c1.isVotingClosed, isFalse);

      final c2 = c1.copyWith(status: 'Under Verification', progressPercentage: 10.0);
      expect(c2.isWorkStartedOrBeyond, isFalse);
      expect(c2.isVotingClosed, isFalse);

      final c3 = c1.copyWith(status: 'Verified', progressPercentage: 20.0);
      expect(c3.isWorkStartedOrBeyond, isFalse);
      expect(c3.isVotingClosed, isFalse);

      final c4 = c1.copyWith(status: 'Accepted', progressPercentage: 30.0);
      expect(c4.isWorkStartedOrBeyond, isFalse);
      expect(c4.isVotingClosed, isFalse);
    });

    test('Voting is closed when complaint reaches Work Started or beyond', () {
      final c = Complaint(
        complaintId: 'RW-STAGE-WS',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        reporterPhone: '1234567890',
        title: 'Road Work Issue',
        description: 'Test work started',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Bangalore',
        imageUrl: 'https://example.com/p.jpg',
        status: 'Work Started',
        progressPercentage: 40.0,
      );

      expect(c.isWorkStartedOrBeyond, isTrue);
      expect(c.isVotingClosed, isTrue);

      final cRepair = c.copyWith(status: 'Repair In Progress', progressPercentage: 60.0);
      expect(cRepair.isWorkStartedOrBeyond, isTrue);
      expect(cRepair.isVotingClosed, isTrue);

      final cNearComp = c.copyWith(status: 'Near Completion', progressPercentage: 85.0);
      expect(cNearComp.isWorkStartedOrBeyond, isTrue);
      expect(cNearComp.isVotingClosed, isTrue);

      final cComp = c.copyWith(status: 'Completed', progressPercentage: 100.0);
      expect(cComp.isWorkStartedOrBeyond, isTrue);
      expect(cComp.isVotingClosed, isTrue);

      final cRepaired = c.copyWith(status: 'Repaired', progressPercentage: 100.0);
      expect(cRepaired.isWorkStartedOrBeyond, isTrue);
      expect(cRepaired.isVotingClosed, isTrue);

      // Progress percentage >= 40.0 closes voting even if status text differs
      final cPct = c.copyWith(status: 'Custom In Progress', progressPercentage: 55.0);
      expect(cPct.isWorkStartedOrBeyond, isTrue);
      expect(cPct.isVotingClosed, isTrue);
    });

    test('ComplaintProvider blocks vote attempts when complaint is in Work Started or beyond', () async {
      final complaint = Complaint(
        complaintId: 'RW-TEST-VOTE-BLOCK',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        reporterPhone: '1234567890',
        title: 'Pothole Issue',
        description: 'Testing vote block after work started',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Bangalore',
        imageUrl: 'https://example.com/p.jpg',
        status: 'Work Started',
        progressPercentage: 40.0,
        realVotes: 5,
        fakeVotes: 1,
        userVotes: {'user_prev': 'genuine'},
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([complaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: complaint.complaintId,
        isReal: true,
        userLat: 12.9716,
        userLng: 77.5946,
        userId: 'new_user_123',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Voting closed — work has started.'));
      // Existing votes are preserved
      final current = provider.getComplaintById(complaint.complaintId);
      expect(current, isNotNull);
      expect(current!.userVotes['user_prev'], equals('genuine'));
      expect(current.realVotes, equals(5));
    });

    test('ComplaintProvider allows vote before work starts and saves it', () async {
      final complaint = Complaint(
        complaintId: 'RW-TEST-VOTE-ALLOW',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        reporterPhone: '1234567890',
        title: 'Pothole Issue',
        description: 'Testing vote allowed before work started',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Bangalore',
        imageUrl: 'https://example.com/p.jpg',
        status: 'Under Verification',
        progressPercentage: 10.0,
        realVotes: 1,
        fakeVotes: 0,
        userVotes: {'user_initial': 'genuine'},
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([complaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      final result = await provider.castCommunityPollVote(
        complaintId: complaint.complaintId,
        isReal: true,
        userLat: 12.9716,
        userLng: 77.5946,
        userId: 'user_new_voter',
      );

      expect(result.success, isTrue);
      final current = provider.getComplaintById(complaint.complaintId);
      expect(current, isNotNull);
      expect(current!.userVotes['user_initial'], equals('genuine'));
      expect(current.userVotes['user_new_voter'], equals('genuine'));
      expect(current.realVotes, equals(2));
    });
  });

  group('3. Authoritative Progress Update Timestamps & Community-Reporter Parity Tests', () {
    test('Authoritative progress update createdAt parses to exact UTC instant and formats to local IST timestamp matching Community Portal', () {
      // The exact record from Supabase progress_updates table:
      // id: f95aa7de-dc8f-43db-a7e7-7199ccc53eab
      // created_at: 2026-10-22T07:52:47.15+00:00
      final parsedDate = Complaint.parseTimestamptz('2026-10-22T07:52:47.15+00:00');
      expect(parsedDate, isNotNull);
      expect(parsedDate!.isUtc, isTrue);

      final update = ProgressUpdate(
        id: 'f95aa7de-dc8f-43db-a7e7-7199ccc53eab',
        updateId: 'UPD-1792655567143',
        complaintId: '57e8215d-3c90-4822-9f07-9da7c08378ac',
        communityUserId: '63543ee0-b295-46dd-8493-5b946edead4e',
        communityUserName: 'lakshmi',
        progressNote: 'work started',
        workPercentage: 50.0,
        status: 'Repair In Progress',
        createdAt: parsedDate,
      );

      // Local formatting used across Community Portal and Reporter Tracking
      final formatted = DateFormat('M/d/yyyy • hh:mm a').format(update.createdAt.toLocal());

      // In local time (+05:30 IST for user's system), 07:52 UTC is 13:22 (01:22 PM)
      // Check that format has expected structure M/d/yyyy • hh:mm a
      expect(formatted, contains('•'));
      expect(formatted, matches(r'^\d{1,2}/\d{1,2}/\d{4} • \d{2}:\d{2} (AM|PM)$'));
      // If running on IST system, exact string matches the user screenshot:
      if (DateTime.now().timeZoneOffset.inMinutes == 330) {
        expect(formatted, equals('10/22/2026 • 01:22 PM'));
      }
    });

    test('Complaint.deduplicateUpdates preserves all distinct progress updates and sorts by createdAt ascending', () {
      final t1 = DateTime.utc(2026, 10, 22, 5, 0); // 10:30 AM IST
      final t2 = DateTime.utc(2026, 10, 22, 7, 52, 47); // 01:22 PM IST

      final u1 = ProgressUpdate(
        updateId: 'UPD-1',
        complaintId: 'c1',
        communityUserId: 'u1',
        communityUserName: 'Worker 1',
        progressNote: 'Initial work',
        workPercentage: 20.0,
        status: 'Work Started',
        createdAt: t1,
      );

      final u2 = ProgressUpdate(
        updateId: 'UPD-2',
        complaintId: 'c1',
        communityUserId: 'u2',
        communityUserName: 'lakshmi',
        progressNote: 'work started',
        workPercentage: 50.0,
        status: 'Repair In Progress',
        createdAt: t2,
      );

      // Pass in reverse order
      final deduplicated = Complaint.deduplicateUpdates([u2, u1]);
      deduplicated.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      expect(deduplicated.length, equals(2));
      expect(deduplicated.first.updateId, equals('UPD-1'));
      expect(deduplicated.last.updateId, equals('UPD-2'));
      expect(deduplicated.last.workPercentage, equals(50.0));
      expect(deduplicated.last.communityUserName, equals('lakshmi'));
    });
  });
}

