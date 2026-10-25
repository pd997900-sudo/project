import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/models/user_model.dart';
import 'package:roadwatch/providers/auth_provider.dart';
import 'package:roadwatch/providers/chat_provider.dart';
import 'package:roadwatch/providers/complaint_provider.dart';
import 'package:roadwatch/screens/reporter/complaint_tracking_screen.dart';
import 'package:roadwatch/widgets/community_verification_poll_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ISSUE 1: Feedback Persistence & Isolation for All Reporters', () {
    late Complaint completedComplaint;

    setUp(() {
      completedComplaint = Complaint(
        complaintId: 'COMP-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        reporterPhone: '+91 9999911111',
        title: 'Main Street Pothole Repair',
        description: 'Large pothole on Main Street',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Main Street, City',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      );
    });

    test('Pujitha and Lakshmi can submit distinct feedback records with correct complaintId and reporterId', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([completedComplaint.toJson()]),
      });

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      // Pujitha submits feedback
      final resultPujitha = await complaintProv.submitFeedback(
        complaintId: 'COMP-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Excellent and smooth repair work!',
      );

      expect(resultPujitha.success, isTrue);
      expect(resultPujitha.feedback, isNotNull);
      expect(resultPujitha.feedback!.complaintId, equals('COMP-101'));
      expect(resultPujitha.feedback!.reporterId, equals('reporter_pujitha'));
      expect(resultPujitha.feedback!.reporterName, equals('Pujitha'));
      expect(resultPujitha.feedback!.rating, equals(5.0));

      // Lakshmi submits feedback on the same complaint
      final resultLakshmi = await complaintProv.submitFeedback(
        complaintId: 'COMP-101',
        reporterId: 'reporter_lakshmi',
        reporterName: 'Lakshmi',
        rating: 4.0,
        comments: 'Good effort, road is much safer now.',
      );

      expect(resultLakshmi.success, isTrue);
      expect(resultLakshmi.feedback, isNotNull);
      expect(resultLakshmi.feedback!.complaintId, equals('COMP-101'));
      expect(resultLakshmi.feedback!.reporterId, equals('reporter_lakshmi'));
      expect(resultLakshmi.feedback!.reporterName, equals('Lakshmi'));
      expect(resultLakshmi.feedback!.rating, equals(4.0));
      expect(resultLakshmi.feedback!.comments, equals('Good effort, road is much safer now.'));
    });

    test('Failed database write does not falsely mark feedback as submitted in provider', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([completedComplaint.toJson()]),
      });

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      // Submit feedback for non-existent complaint
      final result = await complaintProv.submitFeedback(
        complaintId: 'NON_EXISTENT_ID',
        reporterId: 'reporter_lakshmi',
        reporterName: 'Lakshmi',
        rating: 4.0,
        comments: 'Test comment',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('not found'));

      // Ensure original complaint remains without feedback
      final original = complaintProv.getComplaintById('COMP-101');
      expect(original?.feedback, isNull);
    });

    testWidgets('Lakshmi opening completed complaint with Pujitha feedback sees "Provide Rating & Feedback"',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final authProv = AuthProvider();
      await authProv.ensureStorageLoaded();
      authProv.setCurrentUserForTesting(UserModel(
        id: 'reporter_lakshmi',
        name: 'Lakshmi',
        email: 'lakshmi@roadwatch.org',
        phone: '+91 9999922222',
        role: 'reporter',
        createdAt: DateTime.now(),
      ));

      final pujithaFeedback = FeedbackModel(
        feedbackId: 'FB-PUJITHA',
        complaintId: 'COMP-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Great repair!',
        createdAt: DateTime.now(),
      );

      final complaintWithPujithaFeedback = completedComplaint.copyWith(feedback: pujithaFeedback);
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>.value(value: ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(complaint: complaintWithPujithaFeedback),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lakshmi has not submitted feedback, so the button should invite her to provide feedback
      expect(find.text('Provide Rating & Feedback'), findsOneWidget);
      expect(find.text('Repair Work Completed!'), findsOneWidget);
      expect(find.text('Edit Your Rating & Feedback'), findsNothing);
    });

    testWidgets('Pujitha opening completed complaint with her own feedback sees "Your Feedback & Rating" and Edit button',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final authProv = AuthProvider();
      await authProv.ensureStorageLoaded();
      authProv.setCurrentUserForTesting(UserModel(
        id: 'reporter_pujitha',
        name: 'Pujitha',
        email: 'dindupuji04@gmail.com',
        phone: '+91 9999911111',
        role: 'reporter',
        createdAt: DateTime.now(),
      ));

      final pujithaFeedback = FeedbackModel(
        feedbackId: 'FB-PUJITHA',
        complaintId: 'COMP-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Excellent work by community crew!',
        createdAt: DateTime.now(),
      );

      final complaintWithPujithaFeedback = completedComplaint.copyWith(feedback: pujithaFeedback);
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>.value(value: ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(complaint: complaintWithPujithaFeedback),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pujitha sees her rating and the Edit button
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('Thank you for rating our repair team!'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Excellent work by community crew!"'), findsOneWidget);
      expect(find.text('Edit Your Rating & Feedback'), findsOneWidget);
      expect(find.text('Provide Rating & Feedback'), findsNothing);
    });
  });

  group('ISSUE 2: Correct Voting-Closure Messages', () {
    late Complaint pendingComplaint;
    late Complaint workStartedComplaint;
    late Complaint completedComplaint;

    setUp(() {
      pendingComplaint = Complaint(
        complaintId: 'VOTE-001',
        reporterId: 'rep_1',
        reporterName: 'Citizen',
        reporterPhone: '+91 9000000001',
        title: 'Pothole on Cross Road',
        description: 'Pothole needing repair',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Cross Road',
        imageUrl: 'https://example.com/p1.jpg',
        status: 'Accepted',
        progressPercentage: 0.0,
        createdAt: DateTime.now(),
      );

      workStartedComplaint = Complaint(
        complaintId: 'VOTE-002',
        reporterId: 'rep_1',
        reporterName: 'Citizen',
        reporterPhone: '+91 9000000001',
        title: 'Road Damage Repair Ongoing',
        description: 'Work in progress',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Cross Road',
        imageUrl: 'https://example.com/p2.jpg',
        status: 'Work Started',
        progressPercentage: 40.0,
        createdAt: DateTime.now(),
      );

      completedComplaint = Complaint(
        complaintId: 'VOTE-003',
        reporterId: 'rep_1',
        reporterName: 'Citizen',
        reporterPhone: '+91 9000000001',
        title: 'Road Damage Repaired',
        description: 'Work finished',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Cross Road',
        imageUrl: 'https://example.com/p3.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: DateTime.now(),
      );
    });

    testWidgets('Work Started complaint displays "Voting closed — work has started."', (tester) async {
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CommunityVerificationPollCard(
                complaint: workStartedComplaint,
                allowVoting: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voting closed — work has started.'), findsOneWidget);
      expect(find.text('Voting closed — work completed.'), findsNothing);
    });

    testWidgets('Completed complaint displays "Voting closed — work completed."', (tester) async {
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CommunityVerificationPollCard(
                complaint: completedComplaint,
                allowVoting: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voting closed — work completed.'), findsOneWidget);
      expect(find.text('Voting closed — work has started.'), findsNothing);
    });

    testWidgets('Pending/Accepted complaint does not show work-started or completed closure messages', (tester) async {
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CommunityVerificationPollCard(
                complaint: pendingComplaint,
                allowVoting: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voting closed — work completed.'), findsNothing);
      expect(find.text('Voting closed — work has started.'), findsNothing);
    });
  });

  group('ISSUE 3: Enforcing Voting Cutoff in UI and Submission Logic', () {
    test('Provider rejects vote on Work Started complaint with exact message', () async {
      final workStarted = Complaint(
        complaintId: 'CUTOFF-01',
        reporterId: 'rep_1',
        reporterName: 'Citizen',
        reporterPhone: '+91 9000000001',
        title: 'Active repair',
        description: 'Road repair in progress',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Road',
        imageUrl: '',
        status: 'Work Started',
        progressPercentage: 50.0,
        createdAt: DateTime.now(),
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([workStarted.toJson()]),
      });

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      final result = await complaintProv.castCommunityPollVote(
        complaintId: 'CUTOFF-01',
        userId: 'voter_1',
        userEmail: 'voter_1@roadwatch.org',
        isReal: true,
        userLat: 13.0298,
        userLng: 80.0168,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Voting closed — work has started.'));
    });

    test('Provider rejects vote on Completed complaint with exact message', () async {
      final completed = Complaint(
        complaintId: 'CUTOFF-02',
        reporterId: 'rep_1',
        reporterName: 'Citizen',
        reporterPhone: '+91 9000000001',
        title: 'Finished repair',
        description: 'Road repair finished',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Road',
        imageUrl: '',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: DateTime.now(),
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([completed.toJson()]),
      });

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      final result = await complaintProv.castCommunityPollVote(
        complaintId: 'CUTOFF-02',
        userId: 'voter_2',
        userEmail: 'voter_2@roadwatch.org',
        isReal: true,
        userLat: 13.0298,
        userLng: 80.0168,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Voting closed — work completed.'));
    });

    test('Existing votes and counts are preserved when complaint enters completed status', () {
      final complaintWithVotes = Complaint(
        complaintId: 'CUTOFF-03',
        reporterId: 'rep_1',
        reporterName: 'Citizen',
        reporterPhone: '+91 9000000001',
        title: 'Voted Complaint',
        description: 'Road repair completed',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Road',
        imageUrl: '',
        status: 'Completed',
        progressPercentage: 100.0,
        realVotes: 15,
        fakeVotes: 2,
        votedUserIds: ['user_a', 'user_b', 'user_c'],
        userVotes: {'user_a': 'genuine', 'user_b': 'genuine', 'user_c': 'fake'},
        createdAt: DateTime.now(),
      );

      expect(complaintWithVotes.totalVotes, equals(17));
      expect(complaintWithVotes.realVotes, equals(15));
      expect(complaintWithVotes.fakeVotes, equals(2));
      expect(complaintWithVotes.isCompleted, isTrue);
      expect(complaintWithVotes.isVotingClosed, isTrue);
      expect(complaintWithVotes.isVotedBy('user_a', null, null), isTrue);
    });
  });
}
