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
import 'package:roadwatch/screens/community/complaint_verification_screen.dart';
import 'package:roadwatch/screens/community/completed_works_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoadWatch – Multi-Reporter Feedback & Community Portal', () {
    late Complaint completedComplaint;
    final originalOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('_channel') ||
            details.exceptionAsString().contains('LateInitializationError')) {
          return;
        }
        originalOnError?.call(details);
      };

      completedComplaint = Complaint(
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        reporterPhone: '+91 9876543210',
        title: 'Road Damage Repair at Anna Nagar',
        description: 'Deep road potholes repaired with concrete patch.',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 13.0850,
        longitude: 80.2100,
        address: '2nd Avenue, Anna Nagar, Chennai',
        imageUrl: 'https://example.com/pothole.jpg',
        beforeImageUrl: 'https://example.com/pothole_before.jpg',
        afterImageUrl: 'https://example.com/pothole_after.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );
    });

    tearDown(() {
      FlutterError.onError = originalOnError;
    });

    test('Two reporters submit distinct feedback; both entries are saved in allFeedbacks without duplicate entries for same user', () async {
      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([completedComplaint.toJson()]),
      });

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      // 1. Reporter 1 (Pujitha) submits 5-star rating
      final res1 = await complaintProv.submitFeedback(
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Excellent repair! Road is completely smooth now.',
      );

      expect(res1.success, isTrue);
      expect(res1.feedback, isNotNull);
      expect(res1.feedback!.rating, equals(5.0));

      var current = complaintProv.complaints.firstWhere((c) => c.complaintId == 'COMP-MULTI-101');
      expect(current.allFeedbacks.length, equals(1));
      expect(current.feedbackForReporter('reporter_pujitha'), isNotNull);
      expect(current.feedbackForReporter('reporter_lakshmi'), isNull);

      // 2. Reporter 2 (Lakshmi - not the original creator) submits 4-star rating
      final res2 = await complaintProv.submitFeedback(
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_lakshmi',
        reporterName: 'Lakshmi',
        rating: 4.0,
        comments: 'Good concrete work, neat edges.',
      );

      expect(res2.success, isTrue);
      expect(res2.feedback, isNotNull);
      expect(res2.feedback!.rating, equals(4.0));

      current = complaintProv.complaints.firstWhere((c) => c.complaintId == 'COMP-MULTI-101');
      expect(current.allFeedbacks.length, equals(2));

      final fbPujitha = current.feedbackForReporter('reporter_pujitha');
      final fbLakshmi = current.feedbackForReporter('reporter_lakshmi');

      expect(fbPujitha, isNotNull);
      expect(fbPujitha!.rating, equals(5.0));
      expect(fbPujitha.comments, contains('Excellent repair'));

      expect(fbLakshmi, isNotNull);
      expect(fbLakshmi!.rating, equals(4.0));
      expect(fbLakshmi.comments, contains('Good concrete work'));

      // 3. Prevent duplicates: If Lakshmi submits again, her existing entry is updated, not duplicated
      final resUpdate = await complaintProv.submitFeedback(
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_lakshmi',
        reporterName: 'Lakshmi',
        rating: 4.5,
        comments: 'Updated: Road has dried nicely, 4.5 stars.',
      );

      expect(resUpdate.success, isTrue);
      current = complaintProv.complaints.firstWhere((c) => c.complaintId == 'COMP-MULTI-101');
      expect(current.allFeedbacks.length, equals(2), reason: 'Must not duplicate feedback for the same reporter');
      expect(current.feedbackForReporter('reporter_lakshmi')!.rating, equals(4.5));
    });

    testWidgets('ComplaintTrackingScreen: Pujitha sees her rating, Lakshmi sees Provide Rating, then Lakshmi submits and sees her rating', (tester) async {
      // Setup complaint with Pujitha's feedback already recorded
      final fbPujitha = FeedbackModel(
        feedbackId: 'FB-PUJITHA',
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Superb road finishing!',
      );

      final complaintWithPujithaFeedback = completedComplaint.copyWith(
        feedback: fbPujitha,
        allFeedbacks: [fbPujitha],
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([complaintWithPujithaFeedback.toJson()]),
      });

      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      // --- Part A: Pujitha views complaint ---
      authProv.setCurrentUserForTesting(UserModel(
        id: 'reporter_pujitha',
        name: 'Pujitha',
        email: 'pujitha@roadwatch.org',
        role: 'reporter',
        phone: '+91 9876543210',
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(
              key: const ValueKey('pujitha_view'),
              complaint: complaintWithPujithaFeedback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pujitha sees her submitted feedback rating and comment
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Superb road finishing!"'), findsOneWidget);
      // Blank form is not shown to Pujitha
      expect(find.text('Provide Rating & Feedback'), findsNothing);

      // --- Part B: Lakshmi views the SAME completed complaint ---
      authProv.setCurrentUserForTesting(UserModel(
        id: 'reporter_lakshmi',
        name: 'Lakshmi',
        email: 'lakshmi@roadwatch.org',
        role: 'reporter',
        phone: '+91 9123456789',
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(
              key: const ValueKey('lakshmi_view'),
              complaint: complaintWithPujithaFeedback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lakshmi has not yet submitted feedback for this complaint
      expect(find.text('Repair Work Completed!'), findsOneWidget);
      expect(find.text('Provide Rating & Feedback'), findsOneWidget);
      // Lakshmi does not see Pujitha's comment as her own
      expect(find.text('"Superb road finishing!"'), findsNothing);

      // Lakshmi submits her rating via complaintProv
      final submitLakshmiRes = await complaintProv.submitFeedback(
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_lakshmi',
        reporterName: 'Lakshmi',
        rating: 4.0,
        comments: 'Smooth patch leveled nicely.',
      );
      expect(submitLakshmiRes.success, isTrue);

      // Reopen complaint as Lakshmi
      final updatedComplaint = complaintProv.complaints.firstWhere((c) => c.complaintId == 'COMP-MULTI-101');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(
              key: const ValueKey('lakshmi_view_reopened'),
              complaint: updatedComplaint,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lakshmi now immediately sees HER submitted feedback
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('4.0 / 5.0'), findsOneWidget);
      expect(find.text('"Smooth patch leveled nicely."'), findsOneWidget);
      expect(find.text('Provide Rating & Feedback'), findsNothing);
    });

    testWidgets('Community Portal (ComplaintVerificationScreen) displays all feedback entries from multiple reporters', (tester) async {
      final fbPujitha = FeedbackModel(
        feedbackId: 'FB-1',
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Excellent quality and quick completion.',
      );

      final fbLakshmi = FeedbackModel(
        feedbackId: 'FB-2',
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_lakshmi',
        reporterName: 'Lakshmi',
        rating: 4.0,
        comments: 'Very solid work, clean surface.',
      );

      final complaintWithBothFeedbacks = completedComplaint.copyWith(
        latitude: 0.0,
        longitude: 0.0,
        feedback: fbPujitha,
        allFeedbacks: [fbPujitha, fbLakshmi],
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([complaintWithBothFeedbacks.toJson()]),
      });

      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      authProv.setCurrentUserForTesting(UserModel(
        id: 'comm_user_1',
        name: 'Community Lead Ramesh',
        email: 'ramesh@community.org',
        role: 'community',
        phone: '+91 9888877777',
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintVerificationScreen(complaint: complaintWithBothFeedbacks),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that BOTH feedback entries appear in the Community Portal
      expect(find.text('Submitted by: Pujitha'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Excellent quality and quick completion."'), findsOneWidget);

      expect(find.text('Submitted by: Lakshmi'), findsOneWidget);
      expect(find.text('4.0 / 5.0'), findsOneWidget);
      expect(find.text('"Very solid work, clean surface."'), findsOneWidget);

      // Both should show the Verified badge
      expect(find.text('Verified'), findsNWidgets(2));
    });

    testWidgets('CompletedWorksScreen displays all feedback ratings and allows opening verification screen', (tester) async {
      final fbPujitha = FeedbackModel(
        feedbackId: 'FB-1',
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Great repair.',
      );

      final fbLakshmi = FeedbackModel(
        feedbackId: 'FB-2',
        complaintId: 'COMP-MULTI-101',
        reporterId: 'reporter_lakshmi',
        reporterName: 'Lakshmi',
        rating: 4.0,
        comments: 'Looks good.',
      );

      final complaintWithBoth = completedComplaint.copyWith(
        feedback: fbPujitha,
        allFeedbacks: [fbPujitha, fbLakshmi],
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([complaintWithBoth.toJson()]),
      });

      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CompletedWorksScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Completed works screen should render both feedback entries
      expect(find.text('5.0/5.0 Rating: '), findsOneWidget);
      expect(find.text('4.0/5.0 Rating: '), findsOneWidget);
      expect(find.text('"Great repair."'), findsOneWidget);
      expect(find.text('"Looks good."'), findsOneWidget);
    });

    testWidgets('End-to-End Requirement 8: Pujitha creates, Community completes, Pujitha rates, Lakshmi rates, both persist in Community Portal and on reopening', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final authProv = AuthProvider();
      final complaintProv = ComplaintProvider();
      await complaintProv.refreshComplaints();

      // Step 1: Pujitha creates a complaint
      authProv.setCurrentUserForTesting(UserModel(
        id: 'pujitha_uuid',
        name: 'Pujitha',
        email: 'pujitha@roadwatch.org',
        role: 'reporter',
      ));

      final created = await complaintProv.submitComplaint(
        reporterId: 'pujitha_uuid',
        reporterName: 'Pujitha',
        title: 'Deep crater on Main Road',
        description: 'Large pothole damaging vehicle rims',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 0.0,
        longitude: 0.0,
        address: 'Main Road, Sector 4',
        imageUrl: 'https://example.com/pothole.jpg',
      );
      expect(created, isNotNull);
      final complaintId = created!.complaintId;

      // Step 2: Community marks it Completed via progress update to 100%
      final updateRes = await complaintProv.updateWorkProgress(
        complaintId: complaintId,
        percentage: 100.0,
        progressNote: 'Repaired with asphalt patch',
        communityUserId: 'comm_user_1',
        communityUserName: 'Community Volunteer',
      );
      expect(updateRes.success, isTrue);

      var currentComplaint = complaintProv.complaints.firstWhere((c) => c.complaintId == complaintId);
      expect(currentComplaint.status, equals('Completed'));

      // Step 3: Pujitha submits 5-star rating
      final pujithaSubmitRes = await complaintProv.submitFeedback(
        complaintId: complaintId,
        reporterId: 'pujitha_uuid',
        reporterName: 'Pujitha',
        rating: 5.0,
        comments: 'Outstanding repair, thank you!',
      );
      expect(pujithaSubmitRes.success, isTrue);

      // Verify Pujitha sees her rating when opening tracking screen
      currentComplaint = complaintProv.complaints.firstWhere((c) => c.complaintId == complaintId);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(
              key: const ValueKey('e2e_pujitha_tracking'),
              complaint: currentComplaint,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Outstanding repair, thank you!"'), findsOneWidget);

      // Step 4: Lakshmi logs in and opens the SAME completed complaint
      authProv.setCurrentUserForTesting(UserModel(
        id: 'lakshmi_uuid',
        name: 'Lakshmi',
        email: 'lakshmi@roadwatch.org',
        role: 'reporter',
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(
              key: const ValueKey('e2e_lakshmi_tracking_before'),
              complaint: currentComplaint,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Lakshmi sees unrated state with Provide Rating & Feedback button
      expect(find.text('Repair Work Completed!'), findsOneWidget);
      expect(find.text('Provide Rating & Feedback'), findsOneWidget);
      expect(find.text('"Outstanding repair, thank you!"'), findsNothing);

      // Lakshmi submits 4-star rating
      final lakshmiSubmitRes = await complaintProv.submitFeedback(
        complaintId: complaintId,
        reporterId: 'lakshmi_uuid',
        reporterName: 'Lakshmi',
        rating: 4.0,
        comments: 'Good patch, leveling is neat.',
      );
      expect(lakshmiSubmitRes.success, isTrue);

      // Step 5: Lakshmi reopens the complaint - she now sees her own rating
      currentComplaint = complaintProv.complaints.firstWhere((c) => c.complaintId == complaintId);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintTrackingScreen(
              key: const ValueKey('e2e_lakshmi_tracking_after'),
              complaint: currentComplaint,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your Feedback & Rating'), findsOneWidget);
      expect(find.text('4.0 / 5.0'), findsOneWidget);
      expect(find.text('"Good patch, leveling is neat."'), findsOneWidget);
      expect(find.text('Provide Rating & Feedback'), findsNothing);

      // Step 6: Simulate app restart / reload from storage
      final newComplaintProv = ComplaintProvider();
      await newComplaintProv.refreshComplaints();
      final persistedComplaint = newComplaintProv.complaints.firstWhere((c) => c.complaintId == complaintId);
      expect(persistedComplaint.allFeedbacks.length, equals(2));

      // Step 7: Community Portal verification screen displays BOTH ratings with timestamps
      authProv.setCurrentUserForTesting(UserModel(
        id: 'comm_lead_uuid',
        name: 'Community Official',
        email: 'official@community.org',
        role: 'community',
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<ComplaintProvider>.value(value: newComplaintProv),
            ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: ComplaintVerificationScreen(complaint: persistedComplaint),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Submitted by: Pujitha'), findsOneWidget);
      expect(find.text('5.0 / 5.0'), findsOneWidget);
      expect(find.text('"Outstanding repair, thank you!"'), findsOneWidget);

      expect(find.text('Submitted by: Lakshmi'), findsOneWidget);
      expect(find.text('4.0 / 5.0'), findsOneWidget);
      expect(find.text('"Good patch, leveling is neat."'), findsOneWidget);

      expect(find.byIcon(Icons.access_time_rounded), findsNWidgets(2));
      expect(find.text('Verified'), findsNWidgets(2));
    });
  });
}
