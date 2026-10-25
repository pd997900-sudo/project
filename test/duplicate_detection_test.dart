import 'package:flutter_test/flutter_test.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  group('Duplicate Complaint Detection & Voting Tests', () {
    late ComplaintProvider provider;

    setUp(() {
      provider = ComplaintProvider();
    });

    test('1. User A submits a new issue: initialized with zero votes', () async {
      final complaint = Complaint(
        complaintId: 'RW-1001',
        reporterId: 'user_a',
        reporterName: 'User A',
        reporterPhone: '+1 555-0101',
        title: 'Pothole on Main St',
        description: 'Large pothole',
        category: 'Pothole',
        severity: 'High',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai, 600001',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        createdAt: DateTime.now(),
      );

      expect(complaint.realVotes, equals(0));
      expect(complaint.fakeVotes, equals(0));
      expect(complaint.totalVotes, equals(0));
      expect(complaint.realPercentage, equals(0.0));
      expect(complaint.fakePercentage, equals(0.0));
    });

    test('2. User A submits the same issue again: duplicate is detected', () {
      final existingComplaint = Complaint(
        complaintId: 'RW-1001',
        reporterId: 'user_a',
        reporterName: 'User A',
        reporterPhone: '+1 555-0101',
        title: 'Pothole on Main St',
        description: 'Large pothole',
        category: 'Pothole',
        severity: 'High',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai, 600001',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        createdAt: DateTime.now(),
      );

      // Add to provider state
      provider.complaints.add(existingComplaint);

      // Same issue submitted again by User A
      final duplicate = provider.findDuplicateComplaint(
        category: 'Pothole',
        latitude: 13.0299, // 15 meters away
        longitude: 80.0169,
        address: 'Main St, Chennai, 600001',
      );

      expect(duplicate, isNotNull);
      expect(duplicate?.complaintId, equals('RW-1001'));
    });

    test('3. User B submits the same issue: duplicate is detected', () {
      final existingComplaint = Complaint(
        complaintId: 'RW-1001',
        reporterId: 'user_a',
        reporterName: 'User A',
        reporterPhone: '+1 555-0101',
        title: 'Pothole on Main St',
        description: 'Large pothole',
        category: 'Pothole',
        severity: 'High',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai, 600001',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        createdAt: DateTime.now(),
      );

      provider.complaints.add(existingComplaint);

      // User B submits same issue nearby (< 500m)
      final duplicate = provider.findDuplicateComplaint(
        category: 'Pothole',
        latitude: 13.0300, // ~30 meters away
        longitude: 80.0170,
        address: 'Main St, Chennai, 600001',
      );

      expect(duplicate, isNotNull);
      expect(duplicate?.complaintId, equals('RW-1001'));
    });

    test('4. User B votes Genuine on existing complaint: vote count increases by exactly 1', () {
      final complaint = Complaint(
        complaintId: 'RW-1001',
        reporterId: 'user_a',
        reporterName: 'User A',
        reporterPhone: '+1 555-0101',
        title: 'Pothole on Main St',
        description: 'Large pothole',
        category: 'Pothole',
        severity: 'High',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        realVotes: 0,
        fakeVotes: 0,
        votedUserIds: [],
        userVotes: {},
      );

      // User B votes Genuine
      final updatedComplaint = complaint.copyWith(
        realVotes: 1,
        fakeVotes: 0,
        votedUserIds: ['user_b'],
        userVotes: {'user_b': 'Genuine Issue'},
      );

      expect(updatedComplaint.realVotes, equals(1));
      expect(updatedComplaint.fakeVotes, equals(0));
      expect(updatedComplaint.totalVotes, equals(1));
      expect(updatedComplaint.realPercentage, equals(100.0));
      expect(updatedComplaint.isVotedBy('user_b', 'user_b@example.com', ''), isTrue);
    });

    test('5. User B tries to vote again on same complaint: repeat vote is detected & rejected', () {
      final complaintWithVote = Complaint(
        complaintId: 'RW-1001',
        reporterId: 'user_a',
        reporterName: 'User A',
        reporterPhone: '+1 555-0101',
        title: 'Pothole on Main St',
        description: 'Large pothole',
        category: 'Pothole',
        severity: 'High',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        realVotes: 1,
        fakeVotes: 0,
        votedUserIds: ['user_b'],
        userVotes: {'user_b': 'Genuine Issue'},
      );

      // Check user_b has already voted
      final hasVoted = complaintWithVote.isVotedBy('user_b', 'user_b@example.com', '');
      expect(hasVoted, isTrue);

      // Second vote attempt is blocked
      final voteOfUserB = complaintWithVote.getVoteOf('user_b', 'user_b@example.com', '');
      expect(voteOfUserB, equals('Genuine Issue'));
    });

    test('6. Different issue category or distant location (>500m) is NOT marked as duplicate', () {
      final existingComplaint = Complaint(
        complaintId: 'RW-1001',
        reporterId: 'user_a',
        reporterName: 'User A',
        reporterPhone: '+1 555-0101',
        title: 'Pothole on Main St',
        description: 'Large pothole',
        category: 'Pothole',
        severity: 'High',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai, 600001',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
      );

      provider.complaints.add(existingComplaint);

      // A. Different category at same location
      final diffCategory = provider.findDuplicateComplaint(
        category: 'Garbage',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai, 600001',
      );
      expect(diffCategory, isNull);

      // B. Same category > 500m away (e.g. 5km away)
      final distantLocation = provider.findDuplicateComplaint(
        category: 'Pothole',
        latitude: 13.0750, // ~5km away
        longitude: 80.0600,
        address: 'Park Town, Chennai',
      );
      expect(distantLocation, isNull);
    });

    test('7. Completed or closed complaints are not returned as active duplicates', () {
      final completedComplaint = Complaint(
        complaintId: 'RW-9999',
        reporterId: 'user_a',
        reporterName: 'User A',
        reporterPhone: '+1 555-0101',
        title: 'Old Fixed Pothole',
        description: 'Fixed pothole',
        category: 'Pothole',
        severity: 'High',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai, 600001',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Completed',
      );

      provider.complaints.add(completedComplaint);

      // New pothole reported after old one was completed
      final duplicate = provider.findDuplicateComplaint(
        category: 'Pothole',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main St, Chennai, 600001',
      );

      expect(duplicate, isNull);
    });
  });
}
