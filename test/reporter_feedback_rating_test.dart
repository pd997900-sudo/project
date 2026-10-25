import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/auth_provider.dart';
import 'package:roadwatch/providers/complaint_provider.dart';
import 'package:roadwatch/screens/reporter/feedback_screen.dart';
import 'package:roadwatch/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reporter Repair Quality Feedback Rating Tests', () {
    late Complaint unratedComplaint;
    late Complaint ratedComplaint;

    setUp(() {
      unratedComplaint = Complaint(
        complaintId: 'RW-TEST-100',
        reporterId: 'rep_test_1',
        reporterName: 'Reporter Alice',
        reporterPhone: '+91 9999988888',
        title: 'Deep Pothole Fixed',
        description: 'Pothole has been repaired.',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'MG Road, Bangalore',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      ratedComplaint = Complaint(
        complaintId: 'RW-TEST-200',
        reporterId: 'rep_test_2',
        reporterName: 'Reporter Bob',
        reporterPhone: '+91 9999977777',
        title: 'Road Resurfacing Completed',
        description: 'Road resurfacing work finished.',
        category: 'Damaged Road',
        severity: 'Emergency',
        latitude: 12.9716,
        longitude: 77.5946,
        address: 'Brigade Road, Bangalore',
        imageUrl: 'https://example.com/resurface.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        feedback: FeedbackModel(
          feedbackId: 'FB-TEST-200',
          complaintId: 'RW-TEST-200',
          reporterId: 'rep_test_2',
          reporterName: 'Reporter Bob',
          rating: 4.0,
          comments: 'Smooth road surface and good work.',
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
      );
    });

    test('1. FeedbackModel.fromJson defaults rating to 0.0, not 5.0 or 3.5', () {
      final jsonNoRating = {
        'feedback_id': 'FB-001',
        'complaint_id': 'RW-001',
        'reporter_id': 'rep_1',
        'comments': 'No rating provided',
      };

      final feedback = FeedbackModel.fromJson(jsonNoRating);
      expect(feedback.rating, equals(0.0));
      expect(feedback.rating, isNot(equals(5.0)));
      expect(feedback.rating, isNot(equals(3.5)));
    });

    test('2. Unrated complaint initializes with null or unrated feedback', () {
      expect(unratedComplaint.feedback, isNull);
      expect(unratedComplaint.hasValidFeedback, isFalse);

      expect(ratedComplaint.feedback, isNotNull);
      expect(ratedComplaint.feedback!.rating, equals(4.0));
      expect(ratedComplaint.hasValidFeedback, isTrue);
    });

    testWidgets('3. Unrated complaint opens with rating 0 / not selected, all stars unselected, and Submit button disabled',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: FeedbackScreen(complaint: unratedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify display shows 0 / Not Selected
      expect(find.text('0 / Not Selected'), findsOneWidget);
      expect(find.text('5.0 / 5.0 Stars'), findsNothing);
      expect(find.text('3.5 / 5.0 Stars'), findsNothing);

      // Verify RatingBar exists and initialRating is 0
      final ratingBarFinder = find.byType(RatingBar);
      expect(ratingBarFinder, findsOneWidget);
      final ratingBarWidget = tester.widget<RatingBar>(ratingBarFinder);
      expect(ratingBarWidget.initialRating, equals(0.0));
      expect(ratingBarWidget.unratedColor, equals(Colors.grey.shade400));

      // Verify Submit Feedback button is present
      expect(find.text('Submit Feedback'), findsOneWidget);

      // Verify merely opening the screen did not create or mutate feedback on the complaint
      expect(unratedComplaint.feedback, isNull);
    });

    testWidgets('4. Selecting 4 stars updates display to "4 / 5 Stars" and enables Submit Feedback button',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: FeedbackScreen(complaint: unratedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find star icon widgets inside RatingBar and tap the 4th star
      final starIcons = find.byIcon(Icons.star_rounded);
      // There are 5 stars inside RatingBar
      expect(starIcons, findsNWidgets(5));
      await tester.tap(starIcons.at(3)); // 4th star (index 3)
      await tester.pumpAndSettle();

      // Verify text updated to 4 / 5 Stars
      expect(find.text('4 / 5 Stars'), findsOneWidget);
      expect(find.text('0 / Not Selected'), findsNothing);
    });

    testWidgets('5. Reopening screen for previously rated complaint preserves rating and comments, and does not overwrite',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: FeedbackScreen(complaint: ratedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify previously saved rating is displayed
      expect(find.text('4 / 5 Stars'), findsOneWidget);
      expect(find.text('0 / Not Selected'), findsNothing);

      // Verify comments text field has previously saved comments
      expect(find.text('Smooth road surface and good work.'), findsOneWidget);

      // Button should say Update Feedback
      expect(find.text('Update Feedback'), findsOneWidget);

      // Verify initialRating on RatingBar matches 4.0
      final ratingBar = tester.widget<RatingBar>(find.byType(RatingBar));
      expect(ratingBar.initialRating, equals(4.0));
    });

    testWidgets('6. Successful feedback submission saves rating and shows exact SnackBar "Feedback submitted successfully!"',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([unratedComplaint.toJson()]),
      });

      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: FeedbackScreen(complaint: unratedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 4 stars
      final starIcons = find.byIcon(Icons.star_rounded);
      await tester.tap(starIcons.at(3));
      await tester.pumpAndSettle();

      // Enter comments
      final commentField = find.byType(TextField);
      await tester.enterText(commentField, 'Great road repair!');
      await tester.pumpAndSettle();

      // Tap Submit Feedback
      final submitButton = find.text('Submit Feedback');
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Verify SnackBar with exact message
      expect(find.text('Feedback submitted successfully!'), findsOneWidget);

      // Verify complaint in provider has saved feedback
      final updated = complaintProv.complaints.firstWhere((c) => c.complaintId == unratedComplaint.complaintId);
      expect(updated.feedback, isNotNull);
      expect(updated.feedback!.rating, equals(4.0));
      expect(updated.feedback!.comments, equals('Great road repair!'));
    });

    test('7. Dedicated complaint_feedback table name constant is defined and reports table is isolated', () {
      expect(SupabaseService.complaintFeedbackTableName, equals('complaint_feedback'));
      expect(SupabaseService.reportsTableName, equals('reports'));
      expect(SupabaseService.complaintFeedbackTableName, isNot(equals(SupabaseService.reportsTableName)));
    });

    testWidgets('8. Failed submission retains selected rating and comments and does not show success SnackBar',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();

      // Complaint not in provider list will cause submitFeedback to return error
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: MaterialApp(
            home: FeedbackScreen(complaint: unratedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 3 stars
      final starIcons = find.byIcon(Icons.star_rounded);
      await tester.tap(starIcons.at(2)); // 3rd star
      await tester.pumpAndSettle();

      // Enter comments
      final commentField = find.byType(TextField);
      await tester.enterText(commentField, 'Temporary potholes still present.');
      await tester.pumpAndSettle();

      expect(find.text('3 / 5 Stars'), findsOneWidget);

      // Tap Submit Feedback
      final submitButton = find.text('Submit Feedback');
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // "Feedback submitted successfully!" must NOT be shown
      expect(find.text('Feedback submitted successfully!'), findsNothing);

      // Retains selected rating and comments
      expect(find.text('3 / 5 Stars'), findsOneWidget);
      expect(find.text('Temporary potholes still present.'), findsOneWidget);
    });
  });
}
