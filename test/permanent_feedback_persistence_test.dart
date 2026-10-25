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
import 'package:roadwatch/screens/reporter/feedback_screen.dart';
import 'package:roadwatch/screens/community/complaint_verification_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoadWatch – Permanent Feedback Persistence & Rating Integrity Tests', () {
    final originalOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('_channel') ||
            details.exceptionAsString().contains('LateInitializationError')) {
          return;
        }
        originalOnError?.call(details);
      };
    });

    tearDown(() {
      FlutterError.onError = originalOnError;
    });

    test('1. FeedbackModel preserves exact 4-star rating, comments, timestamps, and updatedAt', () {
      final createdTime = DateTime(2026, 10, 20, 14, 30);
      final updatedTime = DateTime(2026, 10, 21, 10, 15);

      final fb = FeedbackModel(
        feedbackId: 'FB-TEST-444',
        complaintId: 'COMP-TEST-444',
        reporterId: 'rep-uuid-1',
        reporterName: 'Pujitha',
        rating: 4.0,
        comments: 'Great patch job, no more potholes.',
        createdAt: createdTime,
        updatedAt: updatedTime,
      );

      expect(fb.rating, equals(4.0));
      expect(fb.comments, equals('Great patch job, no more potholes.'));
      expect(fb.createdAt, equals(createdTime));
      expect(fb.updatedAt, equals(updatedTime));

      final json = fb.toJson();
      final roundTrip = FeedbackModel.fromJson(json);

      expect(roundTrip.rating, equals(4.0));
      expect(roundTrip.comments, equals('Great patch job, no more potholes.'));
      expect(roundTrip.createdAt.millisecondsSinceEpoch, equals(createdTime.millisecondsSinceEpoch));
      expect(roundTrip.updatedAt?.millisecondsSinceEpoch, equals(updatedTime.millisecondsSinceEpoch));
    });

    test('2. Complaint.copyWith with clearFeedback: true strictly clears feedback, while copyWith(feedback: null) preserves it', () {
      final fb = FeedbackModel(
        feedbackId: 'FB-01',
        complaintId: 'C-01',
        reporterId: 'rep-1',
        rating: 4.0,
        comments: '4 star work',
      );

      final complaint = Complaint(
        complaintId: 'C-01',
        reporterId: 'rep-1',
        reporterName: 'Reporter Alice',
        title: 'Road Hole',
        description: 'Repaired',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 13.0,
        longitude: 80.0,
        address: 'Main St',
        imageUrl: 'http://img.png',
        status: 'Completed',
        feedback: fb,
      );

      expect(complaint.feedback, isNotNull);
      expect(complaint.feedback!.rating, equals(4.0));

      // Regular copyWith without clearFeedback preserves feedback
      final preserved = complaint.copyWith(title: 'Updated Road Hole');
      expect(preserved.feedback, isNotNull);
      expect(preserved.feedback!.rating, equals(4.0));

      // copyWith with clearFeedback: true clears feedback
      final cleared = complaint.copyWith(clearFeedback: true);
      expect(cleared.feedback, isNull);
    });

    test('3. Submit 4-star feedback: preserves exact rating, comment, and created_at across storage reload & restart', () async {
      final initialComplaint = Complaint(
        complaintId: 'RW-PERSIST-101',
        reporterId: 'rep_pujitha_uuid',
        reporterName: 'Pujitha',
        title: 'Damaged Road Surface Fixed',
        description: 'Road resurfacing complete.',
        category: 'Damaged Road',
        severity: 'Emergency',
        latitude: 13.0827,
        longitude: 80.2707,
        address: 'Poonamallee High Rd, Chennai',
        imageUrl: 'https://example.com/repair.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([initialComplaint.toJson()]),
      });

      final provider1 = ComplaintProvider();
      await provider1.refreshComplaints();

      // Submit 4-star rating with comment
      final result = await provider1.submitFeedback(
        complaintId: 'RW-PERSIST-101',
        reporterId: 'rep_pujitha_uuid',
        reporterName: 'Pujitha',
        rating: 4.0,
        comments: 'Prompt road repair, perfectly leveled.',
      );

      expect(result.success, isTrue);
      expect(result.feedback, isNotNull);
      expect(result.feedback!.rating, equals(4.0));
      expect(result.feedback!.comments, equals('Prompt road repair, perfectly leveled.'));
      final originalCreatedAt = result.feedback!.createdAt;

      // Simulate App Restart / Reload from persistent SharedPreferences storage
      final provider2 = ComplaintProvider();
      await provider2.refreshComplaints();

      final reloadedComplaint = provider2.complaints.firstWhere((c) => c.complaintId == 'RW-PERSIST-101');
      expect(reloadedComplaint.feedback, isNotNull);
      expect(reloadedComplaint.feedback!.rating, equals(4.0));
      expect(reloadedComplaint.feedback!.rating, isNot(equals(5.0)));
      expect(reloadedComplaint.feedback!.comments, equals('Prompt road repair, perfectly leveled.'));
      expect(reloadedComplaint.feedback!.createdAt.millisecondsSinceEpoch, equals(originalCreatedAt.millisecondsSinceEpoch));
    });

    test('4. Explicit Edit preserves original created_at timestamp and sets updated_at without duplicating rows', () async {
      final originalCreatedAt = DateTime(2026, 10, 21, 9, 0);

      final initialComplaint = Complaint(
        complaintId: 'RW-PERSIST-202',
        reporterId: 'rep_pujitha_uuid',
        reporterName: 'Pujitha',
        title: 'Bridge Expansion Joint Fixed',
        description: 'Joint filled.',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 13.0827,
        longitude: 80.2707,
        address: 'Mount Road, Chennai',
        imageUrl: 'https://example.com/joint.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        feedback: FeedbackModel(
          feedbackId: 'FB-ORIGINAL-202',
          complaintId: 'RW-PERSIST-202',
          reporterId: 'rep_pujitha_uuid',
          reporterName: 'Pujitha',
          rating: 4.0,
          comments: 'Initial 4-star rating.',
          createdAt: originalCreatedAt,
        ),
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([initialComplaint.toJson()]),
      });

      final provider = ComplaintProvider();
      await provider.refreshComplaints();

      // Reporter explicitly updates feedback to 3 stars with updated comments
      final editResult = await provider.submitFeedback(
        complaintId: 'RW-PERSIST-202',
        reporterId: 'rep_pujitha_uuid',
        reporterName: 'Pujitha',
        rating: 3.0,
        comments: 'Found a bump upon driving over it; rating adjusted to 3 stars.',
      );

      expect(editResult.success, isTrue);
      final updatedFeedback = editResult.feedback!;

      // 1. Rating and comments updated
      expect(updatedFeedback.rating, equals(3.0));
      expect(updatedFeedback.comments, equals('Found a bump upon driving over it; rating adjusted to 3 stars.'));

      // 2. Original creation timestamp strictly preserved
      expect(updatedFeedback.createdAt.millisecondsSinceEpoch, equals(originalCreatedAt.millisecondsSinceEpoch));

      // 3. updated_at is populated
      expect(updatedFeedback.updatedAt, isNotNull);

      // 4. Exactly 1 feedback row exists in allFeedbacks (no duplicates created)
      final complaint = provider.complaints.firstWhere((c) => c.complaintId == 'RW-PERSIST-202');
      expect(complaint.allFeedbacks.length, equals(1));
      expect(complaint.allFeedbacks.first.rating, equals(3.0));
    });

    testWidgets('5. Community Verification Screen displays exact 4-star rating, comment, and reporter name', (tester) async {
      final complaintWithFeedback = Complaint(
        complaintId: 'RW-COMM-404',
        reporterId: 'rep_pujitha_uuid',
        reporterName: 'Pujitha',
        title: 'Deep Pothole Closed',
        description: 'Fixed completely.',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 0.0,
        longitude: 0.0,
        address: 'OMR Road, Chennai',
        imageUrl: 'https://example.com/pothole.jpg',
        afterImageUrl: 'https://example.com/pothole_fixed.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        completionNotes: 'High-density asphalt patch applied.',
        feedback: FeedbackModel(
          feedbackId: 'FB-404',
          complaintId: 'RW-COMM-404',
          reporterId: 'rep_pujitha_uuid',
          reporterName: 'Pujitha',
          rating: 4.0,
          comments: 'Smooth asphalt, high quality.',
          createdAt: DateTime(2026, 10, 22, 11, 0),
        ),
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([complaintWithFeedback.toJson()]),
      });

      final authProv = AuthProvider();
      authProv.setCurrentUserForTesting(UserModel(
        id: 'comm_user_1',
        name: 'Community Staff',
        email: 'comm@roadwatch.org',
        role: 'community',
        phone: '+91 9999999999',
      ));
      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintVerificationScreen(complaint: complaintWithFeedback),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify exact 4.0 / 5.0 is shown
      expect(find.text('4.0 / 5.0'), findsOneWidget);
      // Verify NOT showing 5.0 / 5.0
      expect(find.text('5.0 / 5.0'), findsNothing);

      // Verify exact comment is shown
      expect(find.text('"Smooth asphalt, high quality."'), findsOneWidget);

      // Verify reporter name is shown
      expect(find.textContaining('Submitted by: Pujitha'), findsOneWidget);
    });

    testWidgets('6. Community Verification Screen for completed unrated complaint shows "Awaiting Reporter Feedback" and NEVER 5.0 / 5.0', (tester) async {
      final unratedComplaint = Complaint(
        complaintId: 'RW-UNRATED-505',
        reporterId: 'rep_alice_uuid',
        reporterName: 'Alice',
        title: 'New Street Light Installed',
        description: 'Light repaired.',
        category: 'Street Light Failure',
        severity: 'Low',
        latitude: 0.0,
        longitude: 0.0,
        address: 'Anna Salai, Chennai',
        imageUrl: 'https://example.com/light.jpg',
        afterImageUrl: 'https://example.com/light_fixed.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        completionNotes: 'LED bulb replaced and verified.',
        // No feedback submitted yet
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([unratedComplaint.toJson()]),
      });

      final authProv = AuthProvider();
      authProv.setCurrentUserForTesting(UserModel(
        id: 'comm_user_1',
        name: 'Community Staff',
        email: 'comm@roadwatch.org',
        role: 'community',
        phone: '+91 9999999999',
      ));
      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintVerificationScreen(complaint: unratedComplaint),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify unrated indicator is shown
      expect(find.text('Not Yet Rated'), findsOneWidget);
      expect(find.text('Awaiting reporter evaluation'), findsOneWidget);
      expect(find.text('Repair marked completed. Awaiting reporter feedback submission.'), findsOneWidget);

      // Verify fake 5.0 rating is NEVER shown
      expect(find.text('5.0 / 5.0'), findsNothing);
      expect(find.text('"Repair completed smoothly and awaiting reporter feedback."'), findsNothing);
    });

    testWidgets('7. FeedbackScreen synchronously opens with existing 4-star rating and "Update Feedback" button', (tester) async {
      final complaint = Complaint(
        complaintId: 'RW-EDIT-606',
        reporterId: 'rep_pujitha_uuid',
        reporterName: 'Pujitha',
        title: 'Water Clogging Cleared',
        description: 'Drain cleaned.',
        category: 'Drainage Issue',
        severity: 'Medium',
        latitude: 13.0827,
        longitude: 80.2707,
        address: 'T Nagar, Chennai',
        imageUrl: 'https://example.com/drain.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        feedback: FeedbackModel(
          feedbackId: 'FB-606',
          complaintId: 'RW-EDIT-606',
          reporterId: 'rep_pujitha_uuid',
          reporterName: 'Pujitha',
          rating: 4.0,
          comments: 'Drain cleared and flowing well.',
          createdAt: DateTime(2026, 10, 21, 14, 0),
        ),
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([complaint.toJson()]),
      });

      final authProv = AuthProvider();
      authProv.setCurrentUserForTesting(UserModel(
        id: 'rep_pujitha_uuid',
        name: 'Pujitha',
        email: 'pujitha@gmail.com',
        role: 'reporter',
        phone: '+91 9876543210',
      ));
      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: FeedbackScreen(complaint: complaint),
          ),
        ),
      );

      // Verify immediate synchronous loading without delay
      expect(find.text('4 / 5 Stars'), findsOneWidget);
      expect(find.text('Drain cleared and flowing well.'), findsOneWidget);
      // Button states "Update Feedback"
      expect(find.text('Update Feedback'), findsOneWidget);
      expect(find.text('Submit Feedback'), findsNothing);
    });
  });
}
