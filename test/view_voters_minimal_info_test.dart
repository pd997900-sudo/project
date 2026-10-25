import 'package:flutter_test/flutter_test.dart';
import 'package:roadwatch/services/supabase_service.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';
import 'package:intl/intl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('View Voters Minimal Information & IST Timestamp Tests', () {
    test('1. VoterInfo correctly holds name, vote date & time, and vote status', () {
      final utcTimestamp = DateTime.parse('2026-10-10T09:05:00.000Z');
      final voter = VoterInfo(
        userId: 'user-uuid-101',
        name: 'Aarav Sharma',
        vote: 'genuine',
        createdAt: utcTimestamp,
      );

      expect(voter.userId, equals('user-uuid-101'));
      expect(voter.name, equals('Aarav Sharma'));
      expect(voter.isGenuine, isTrue);
      expect(voter.createdAt, equals(utcTimestamp));
    });

    test('2. Indian Standard Time (IST) formatting adds +5:30 to UTC timestamp', () {
      final utcTimestamp = DateTime.parse('2026-10-10T09:05:00.000Z');
      final istTime = utcTimestamp.toUtc().add(const Duration(hours: 5, minutes: 30));

      final formattedIST = '${DateFormat('MMM d, yyyy • hh:mm a').format(istTime)} IST';
      expect(formattedIST, contains('Oct 10, 2026'));
      expect(formattedIST, contains('02:35 PM IST'));
    });

    test('3. Fallback voter name defaults to Registered User when name is empty', () async {
      final complaint = Complaint(
        complaintId: 'RW-TEST-999',
        reporterId: 'reporter_999',
        reporterName: 'Reporter 999',
        reporterPhone: '+1 555-0999',
        title: 'Test Issue',
        description: 'Test description',
        category: 'Pothole',
        severity: 'Medium',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Bangalore, India',
        imageUrl: 'https://example.com/test.jpg',
        status: 'Submitted',
        userVotes: {
          'anonymous_voter_uuid': 'genuine',
        },
      );

      final provider = ComplaintProvider();
      final voters = await provider.getVotersForComplaint(complaint);

      expect(voters.length, equals(1));
      expect(voters.first.name, equals('Registered User'));
      expect(voters.first.isGenuine, isTrue);
    });

    test('4. Voter email handles extract display username when full name is missing', () async {
      final complaint = Complaint(
        complaintId: 'RW-TEST-888',
        reporterId: 'reporter_888',
        reporterName: 'Reporter 888',
        reporterPhone: '+1 555-0888',
        title: 'Test Issue 2',
        description: 'Test description 2',
        category: 'Drainage',
        severity: 'Low',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Bangalore, India',
        imageUrl: 'https://example.com/test2.jpg',
        status: 'Submitted',
        userVotes: {
          'priya.patel@example.com': 'fake',
        },
      );

      final provider = ComplaintProvider();
      final voters = await provider.getVotersForComplaint(complaint);

      expect(voters.length, equals(1));
      expect(voters.first.name, equals('priya.patel'));
      expect(voters.first.isGenuine, isFalse);
    });
  });
}
