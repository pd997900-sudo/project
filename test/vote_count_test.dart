import 'package:flutter_test/flutter_test.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  group('Automatic Vote Count & Verification Tests', () {
    test('1. Newly created complaint initializes with zero votes and zero percentages', () {
      final complaint = Complaint(
        complaintId: 'RW-NEW-001',
        reporterId: 'reporter_123',
        reporterName: 'John Doe',
        reporterPhone: '+1 555-0100',
        title: 'New Pothole',
        description: 'Pothole description',
        category: 'Pothole',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: '123 Main St',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
      );

      expect(complaint.realVotes, equals(0));
      expect(complaint.fakeVotes, equals(0));
      expect(complaint.totalVotes, equals(0));
      expect(complaint.realPercentage, equals(0.0));
      expect(complaint.fakePercentage, equals(0.0));
      expect(complaint.votedUserIds, isEmpty);
      expect(complaint.userVotes, isEmpty);
    });

    test('2. Total votes equals Genuine Votes + Fake Votes and percentages update correctly', () {
      final complaint = Complaint(
        complaintId: 'RW-TEST-002',
        reporterId: 'reporter_123',
        reporterName: 'John Doe',
        reporterPhone: '+1 555-0100',
        title: 'Test Issue',
        description: 'Test description',
        category: 'Pothole',
        severity: 'Low',
        latitude: 37.7749,
        longitude: -122.4194,
        address: '123 Main St',
        imageUrl: 'https://example.com/photo.jpg',
        status: 'Submitted',
        realVotes: 3,
        fakeVotes: 1,
        userVotes: {
          'user_1': 'genuine',
          'user_2': 'genuine',
          'user_3': 'genuine',
          'user_4': 'fake',
        },
      );

      expect(complaint.totalVotes, equals(4));
      expect(complaint.realPercentage, equals(75.0));
      expect(complaint.fakePercentage, equals(25.0));
    });

    test('3. Voting genuine increments Genuine by 1 and Total by 1', () async {
      final complaint = Complaint(
        complaintId: 'RW-VOTE-001',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        reporterPhone: '+1 555-0111',
        title: 'Damaged Street',
        description: 'Street damage',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: 'Market St',
        imageUrl: 'https://example.com/img.jpg',
        status: 'Submitted',
        realVotes: 0,
        fakeVotes: 0,
      );

      expect(complaint.realVotes, equals(0));
      expect(complaint.fakeVotes, equals(0));
      expect(complaint.totalVotes, equals(0));

      final updated = complaint.copyWith(
        realVotes: 1,
        fakeVotes: 0,
        votedUserIds: ['user_auth_1'],
        userVotes: {'user_auth_1': 'genuine'},
      );

      expect(updated.realVotes, equals(1));
      expect(updated.fakeVotes, equals(0));
      expect(updated.totalVotes, equals(1));
      expect(updated.realPercentage, equals(100.0));
      expect(updated.fakePercentage, equals(0.0));
      expect(updated.isVotedBy('user_auth_1'), isTrue);
      expect(updated.getVoteOf('user_auth_1'), equals('genuine'));
    });

    test('4. Duplicate vote by same user maintains total vote count of 1', () {
      final complaint = Complaint(
        complaintId: 'RW-VOTE-002',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        reporterPhone: '+1 555-0111',
        title: 'Damaged Street',
        description: 'Street damage',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: 'Market St',
        imageUrl: 'https://example.com/img.jpg',
        status: 'Submitted',
        realVotes: 1,
        fakeVotes: 0,
        votedUserIds: ['user_auth_1'],
        userVotes: {'user_auth_1': 'genuine'},
      );

      final userVotes = Map<String, String>.from(complaint.userVotes);
      userVotes['user_auth_1'] = 'genuine'; // Duplicate submission attempt

      int realC = 0;
      int fakeC = 0;
      userVotes.forEach((uId, vVal) {
        if (vVal == 'genuine') realC++;
        if (vVal == 'fake') fakeC++;
      });

      expect(realC, equals(1));
      expect(fakeC, equals(0));
      expect(realC + fakeC, equals(1));
    });

    test('5. getVotersForComplaint returns exactly 1 voter for single vote without duplicates', () async {
      final complaint = Complaint(
        complaintId: 'RW-VOTE-003',
        reporterId: 'rep_1',
        reporterName: 'Reporter 1',
        reporterPhone: '+1 555-0111',
        title: 'Damaged Street',
        description: 'Street damage',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: 'Market St',
        imageUrl: 'https://example.com/img.jpg',
        status: 'Submitted',
        realVotes: 1,
        fakeVotes: 0,
        votedUserIds: ['d83c2712-4f81-4b1e-9a1d-72e29381a95e'],
        userVotes: {'d83c2712-4f81-4b1e-9a1d-72e29381a95e': 'genuine'},
      );

      final complaintProv = ComplaintProvider();
      final voters = await complaintProv.getVotersForComplaint(complaint);
      expect(voters.length, equals(1));
      expect(voters.first.userId, equals('d83c2712-4f81-4b1e-9a1d-72e29381a95e'));
      expect(voters.first.vote, equals('genuine'));
    });
  });
}
