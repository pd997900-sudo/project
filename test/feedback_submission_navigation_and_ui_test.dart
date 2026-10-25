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
import 'package:roadwatch/screens/reporter/feedback_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoadWatch – Feedback Submission Navigation & UI State Tests', () {
    late Complaint completedComplaint;
    late UserModel reporterUser;

    setUp(() {
      reporterUser = UserModel(
        id: 'reporter_uuid_001',
        name: 'Pujitha',
        email: 'pujitha@roadwatch.org',
        phone: '+91 9876543210',
        role: 'reporter',
        createdAt: DateTime.now(),
      );

      completedComplaint = Complaint(
        complaintId: 'COMP-FEEDBACK-999',
        reporterId: 'reporter_uuid_001',
        reporterName: 'Pujitha',
        reporterPhone: '+91 9876543210',
        title: 'Pothole Repair on 5th Cross Road',
        description: 'Road damage was filled and paved with asphalt.',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 12.9716,
        longitude: 77.5946,
        address: '5th Cross Road, Bangalore',
        imageUrl: 'https://example.com/repair.jpg',
        afterImageUrl: 'https://example.com/repair_after.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );
    });

    testWidgets('1. First submission immediately shows green "Your Feedback & Rating" card with exact rating & comments, without reopening empty form',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([completedComplaint.toJson()]),
      });

      final authProv = AuthProvider();
      await authProv.ensureStorageLoaded();
      authProv.setCurrentUserForTesting(reporterUser);

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();
      final chatProv = ChatProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>.value(value: chatProv),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(complaint: completedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, unrated: shows "Repair Work Completed!" banner and "Provide Rating & Feedback" button
      expect(find.text('Repair Work Completed!'), findsOneWidget);
      expect(find.text('How satisfied are you with the road repair quality?'), findsOneWidget);
      expect(find.text('Provide Rating & Feedback'), findsOneWidget);
      expect(find.text('Your Feedback & Rating'), findsNothing);

      // Scroll to and tap "Provide Rating & Feedback" to navigate to FeedbackScreen
      final provideBtn = find.text('Provide Rating & Feedback');
      await tester.ensureVisible(provideBtn);
      await tester.pumpAndSettle();
      await tester.tap(provideBtn);
      await tester.pumpAndSettle();

      // Verify we are on FeedbackScreen
      expect(find.text('Repair Quality Feedback'), findsOneWidget);
      expect(find.text('Submit Feedback'), findsOneWidget);

      // Select 4 stars
      final starIcons = find.byIcon(Icons.star_rounded);
      await tester.tap(starIcons.at(3)); // 4th star (index 3)
      await tester.pumpAndSettle();
      expect(find.text('4 / 5 Stars'), findsOneWidget);

      // Enter comments
      final commentField = find.byType(TextField);
      await tester.enterText(commentField, 'Smooth repair and great team response!');
      await tester.pumpAndSettle();

      // Press "Submit Feedback"
      final submitButton = find.text('Submit Feedback');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Returned to ComplaintTrackingScreen:
      // Verify green "Your Feedback & Rating" card is IMMEDIATELY displayed with exact rating and comments
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('Thank you for rating our repair team!'), findsOneWidget);
      expect(find.text('4.0 / 5.0'), findsOneWidget);
      expect(find.text('"Smooth repair and great team response!"'), findsOneWidget);
      expect(find.text('Edit Your Rating & Feedback'), findsOneWidget);

      // The empty form and initial prompt are no longer displayed
      expect(find.text('Repair Work Completed!'), findsNothing);
      expect(find.text('Provide Rating & Feedback'), findsNothing);
      expect(find.text('Repair Quality Feedback'), findsNothing);
    });

    testWidgets('2. Tapping "Edit Your Rating & Feedback" prefills existing rating & comments, and updating returns updated green card',
        (tester) async {
      final existingFeedback = FeedbackModel(
        feedbackId: 'FB-EXISTING-1',
        complaintId: completedComplaint.complaintId,
        reporterId: reporterUser.id,
        reporterName: reporterUser.name,
        rating: 4.0,
        comments: 'Initial 4 star repair feedback',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );

      final ratedComplaint = completedComplaint.copyWith(
        feedback: existingFeedback,
        allFeedbacks: [existingFeedback],
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([ratedComplaint.toJson()]),
      });

      final authProv = AuthProvider();
      await authProv.ensureStorageLoaded();
      authProv.setCurrentUserForTesting(reporterUser);

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();
      final chatProv = ChatProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>.value(value: chatProv),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(complaint: ratedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Displays existing green feedback card
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('4.0 / 5.0'), findsOneWidget);
      expect(find.text('"Initial 4 star repair feedback"'), findsOneWidget);
      expect(find.text('Edit Your Rating & Feedback'), findsOneWidget);

      // Tap "Edit Your Rating & Feedback"
      final editBtn = find.text('Edit Your Rating & Feedback');
      await tester.ensureVisible(editBtn);
      await tester.pumpAndSettle();
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // On FeedbackScreen: prefilled with existing rating, comments, and "Update Feedback" button
      expect(find.text('Repair Quality Feedback'), findsOneWidget);
      expect(find.text('4 / 5 Stars'), findsOneWidget);
      expect(find.text('Initial 4 star repair feedback'), findsOneWidget);
      expect(find.text('Update Feedback'), findsOneWidget);

      // Update rating to 5 stars
      final starIcons = find.byIcon(Icons.star_rounded);
      await tester.tap(starIcons.at(4)); // 5th star
      await tester.pumpAndSettle();
      expect(find.text('5 / 5 Stars'), findsOneWidget);

      // Update comments
      final commentField = find.byType(TextField);
      await tester.enterText(commentField, 'Upgraded: Outstanding craftsmanship!');
      await tester.pumpAndSettle();

      // Tap "Update Feedback"
      final updateButton = find.text('Update Feedback');
      await tester.ensureVisible(updateButton);
      await tester.tap(updateButton);
      await tester.pumpAndSettle();

      // Returned to ComplaintTrackingScreen:
      // Immediately shows updated green card
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Upgraded: Outstanding craftsmanship!"'), findsOneWidget);
      expect(find.text('Edit Your Rating & Feedback'), findsOneWidget);
    });

    testWidgets('3. Reopening complaint screen and refreshing app preserves green card without reverting to empty form',
        (tester) async {
      final existingFeedback = FeedbackModel(
        feedbackId: 'FB-SAVED-1',
        complaintId: completedComplaint.complaintId,
        reporterId: reporterUser.id,
        reporterName: reporterUser.name,
        rating: 5.0,
        comments: 'Verified persistent feedback',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final ratedComplaint = completedComplaint.copyWith(
        feedback: existingFeedback,
        allFeedbacks: [existingFeedback],
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([ratedComplaint.toJson()]),
      });

      final authProv = AuthProvider();
      await authProv.ensureStorageLoaded();
      authProv.setCurrentUserForTesting(reporterUser);

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();
      final chatProv = ChatProvider();

      // 1. Initial open
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>.value(value: chatProv),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(complaint: ratedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Verified persistent feedback"'), findsOneWidget);

      // 2. Trigger refreshComplaints
      await complaintProv.refreshComplaints();
      await tester.pumpAndSettle();

      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Verified persistent feedback"'), findsOneWidget);
      expect(find.text('Repair Work Completed!'), findsNothing);
    });

    testWidgets('4. Failed submission preserves rating and comments on form and does not show green card prematurely',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      // Complaint is not in complaintProv so submitFeedback will fail
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: FeedbackScreen(complaint: completedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select 3 stars
      final starIcons = find.byIcon(Icons.star_rounded);
      await tester.tap(starIcons.at(2)); // 3 stars
      await tester.pumpAndSettle();

      // Enter comments
      final commentField = find.byType(TextField);
      await tester.enterText(commentField, 'Failed attempt test comment');
      await tester.pumpAndSettle();

      // Tap Submit Feedback
      final submitButton = find.text('Submit Feedback');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Stays on form
      expect(find.text('Repair Quality Feedback'), findsOneWidget);

      // Success SnackBar is NOT shown
      expect(find.text('Feedback submitted successfully!'), findsNothing);

      // Rating and comments are preserved on the form
      expect(find.text('3 / 5 Stars'), findsOneWidget);
      expect(find.text('Failed attempt test comment'), findsOneWidget);
    });
  });
}
