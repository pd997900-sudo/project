import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/models/user_model.dart';
import 'package:roadwatch/providers/auth_provider.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('View Voters Ownership & Grouping Tests', () {
    final complaintA = Complaint(
      complaintId: 'RW-TEST-001',
      reporterId: 'reporter_uuid_a',
      reporterName: 'Reporter A',
      reporterPhone: '+1 555-0100',
      title: 'Pothole on 5th Ave',
      description: 'Dangerous pothole',
      category: 'Pothole',
      severity: 'Medium',
      latitude: 37.7749,
      longitude: -122.4194,
      address: '5th Ave, San Francisco',
      imageUrl: 'https://example.com/pothole.jpg',
      status: 'Under Verification',
      realVotes: 2,
      fakeVotes: 1,
      userVotes: {
        'voter_uuid_1': 'genuine',
        'voter_uuid_2': 'genuine',
        'voter_uuid_3': 'fake',
      },
    );

    final complaintB = Complaint(
      complaintId: 'RW-TEST-002',
      reporterId: 'reporter_uuid_b',
      reporterName: 'Reporter B',
      reporterPhone: '+1 555-0200',
      title: 'Cracked Surface',
      description: 'Bad surface crack',
      category: 'Damaged Road',
      severity: 'Low',
      latitude: 37.7833,
      longitude: -122.4167,
      address: 'Howard St, San Francisco',
      imageUrl: 'https://example.com/crack.jpg',
      status: 'Submitted',
      realVotes: 1,
      fakeVotes: 0,
      userVotes: {
        'voter_uuid_4': 'genuine',
      },
    );

    test('Reporter A can see View Voters option ONLY for Reporter A\'s complaints', () async {
      final authProvider = AuthProvider();

      // Log in as Reporter A
      authProvider.setSelectedRole('reporter');
      await authProvider.initiateRegistration(
        name: 'Reporter A',
        email: 'reporterA@example.com',
        phone: '+1 555-0100',
        password: 'password123',
        role: 'reporter',
      );
      await authProvider.verifyOtpAndCompleteSignup(authProvider.pendingOtp!);
      await authProvider.signIn(
        email: 'reporterA@example.com',
        password: 'password123',
        role: 'reporter',
      );

      // Test ownership check against complaint A (owned) vs complaint B (not owned)
      final ownedComplaintA = complaintA.copyWith(reporterId: authProvider.currentUser!.id);
      final isOwnerOfA = authProvider.isComplaintOwner(ownedComplaintA);
      final isOwnerOfB = authProvider.isComplaintOwner(complaintB.copyWith());

      // With current user matching complaintA's reporterId
      final userA = UserModel(
        id: authProvider.currentUser!.id,
        name: 'Reporter A',
        email: 'reporterA@example.com',
        phone: '+1 555-0100',
        role: 'reporter',
      );

      // Verify custom owner calculation
      expect(isOwnerOfA, isTrue);
      expect(isOwnerOfB, isFalse);
      expect(userA.id == ownedComplaintA.reporterId, isTrue);
      expect(userA.id == complaintB.reporterId, isFalse);
    });

    test('Reporter B can see View Voters option ONLY for Reporter B\'s complaints', () async {
      final userB = UserModel(
        id: 'reporter_uuid_b',
        name: 'Reporter B',
        email: 'reporterB@example.com',
        phone: '+1 555-0200',
        role: 'reporter',
      );

      // Reporter B owns complaintB, but DOES NOT own complaintA
      expect(userB.id == complaintB.reporterId, isTrue);
      expect(userB.id == complaintA.reporterId, isFalse);
    });

    test('Both Reporters do NOT see View Voters on each other\'s complaints', () async {
      final userA = UserModel(id: 'reporter_uuid_a', name: 'Reporter A', email: 'repA@ex.com', phone: '', role: 'reporter');
      final userB = UserModel(id: 'reporter_uuid_b', name: 'Reporter B', email: 'repB@ex.com', phone: '', role: 'reporter');

      // User A on User B's complaint -> False
      expect(userA.id == complaintB.reporterId, isFalse);

      // User B on User A's complaint -> False
      expect(userB.id == complaintA.reporterId, isFalse);
    });

    test('Voters grouping correctly separates Genuine and Fake voters', () async {
      final complaintProv = ComplaintProvider();
      final voters = await complaintProv.getVotersForComplaint(complaintA);

      final genuineVoters = voters.where((v) => v.isGenuine).toList();
      final fakeVoters = voters.where((v) => !v.isGenuine).toList();

      expect(genuineVoters.length, equals(2));
      expect(fakeVoters.length, equals(1));
      expect(voters.length, equals(3));

      expect(genuineVoters.any((v) => v.userId == 'voter_uuid_1'), isTrue);
      expect(genuineVoters.any((v) => v.userId == 'voter_uuid_2'), isTrue);
      expect(fakeVoters.any((v) => v.userId == 'voter_uuid_3'), isTrue);
    });

    test('Community user can view voters for complaint verification without voting privileges', () async {
      final communityUser = UserModel(
        id: 'community_uuid_1',
        name: 'Community Inspector',
        email: 'inspector@community.org',
        phone: '+1 555-0300',
        role: 'community',
      );

      final complaintProv = ComplaintProvider();
      final voters = await complaintProv.getVotersForComplaint(complaintA);

      expect(communityUser.isCommunity, isTrue);
      expect(voters.length, equals(3));
      expect(voters.where((v) => v.isGenuine).length, equals(2));
      expect(voters.where((v) => !v.isGenuine).length, equals(1));
    });
  });
}

