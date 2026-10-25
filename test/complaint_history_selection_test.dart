import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/auth_provider.dart';
import 'package:roadwatch/providers/complaint_provider.dart';
import 'package:roadwatch/providers/chat_provider.dart';
import 'package:roadwatch/screens/reporter/complaint_history_screen.dart';
import 'package:roadwatch/screens/reporter/complaint_tracking_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Complaint History Selection & Tracking Screen Fix Tests', () {
    late Complaint pendingPothole;
    late Complaint rejectedPothole;
    late Complaint completedPothole;

    setUp(() {
      final now = DateTime.now();

      // Three complaints that share the EXACT same title "Pothole"
      // to guarantee collision if title-based lookup is used.
      pendingPothole = Complaint(
        complaintId: 'RW-POTHOLE-PENDING',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        reporterPhone: '+91 9876543210',
        title: 'Pothole',
        description: 'Dangerous pothole on Sector 4 road',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 13.0298,
        longitude: 80.0168,
        address: 'Sector 4, Main Road',
        imageUrl: 'https://example.com/pothole1.jpg',
        status: 'Submitted',
        progressPercentage: 0.0,
        createdAt: now.subtract(const Duration(hours: 5)),
      );

      rejectedPothole = Complaint(
        complaintId: 'RW-POTHOLE-REJECTED',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        reporterPhone: '+91 9876543210',
        title: 'Pothole',
        description: 'Reported pothole verified and deemed duplicate / fake by inspectors',
        category: 'Pothole',
        severity: 'Moderate',
        latitude: 13.0305,
        longitude: 80.0175,
        address: 'Sector 5, Cross Street',
        imageUrl: 'https://example.com/pothole2.jpg',
        status: 'Rejected',
        progressPercentage: 0.0,
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      );

      completedPothole = Complaint(
        complaintId: 'RW-POTHOLE-COMPLETED',
        reporterId: 'reporter_pujitha',
        reporterName: 'Pujitha',
        reporterPhone: '+91 9876543210',
        title: 'Pothole',
        description: 'Pothole repaired and asphalt laid',
        category: 'Pothole',
        severity: 'Low',
        latitude: 13.0310,
        longitude: 80.0180,
        address: 'Sector 6, Ring Road',
        imageUrl: 'https://example.com/pothole3.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
        createdAt: now.subtract(const Duration(days: 2)),
      );

      SharedPreferences.setMockInitialValues({
        'roadwatch_complaints_db_v1': jsonEncode([
          pendingPothole.toJson(),
          rejectedPothole.toJson(),
          completedPothole.toJson(),
        ]),
      });
    });

    Widget createTestApp({
      required ComplaintProvider complaintProv,
      required AuthProvider authProv,
      ChatProvider? chatProv,
      Widget? child,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ComplaintProvider>.value(value: complaintProv),
          ChangeNotifierProvider<AuthProvider>.value(value: authProv),
          ChangeNotifierProvider<ChatProvider>.value(value: chatProv ?? ChatProvider()),
        ],
        child: MaterialApp(
          home: child ?? const ComplaintHistoryScreen(initialTab: 'All'),
        ),
      );
    }

    testWidgets('1. Tapping a Rejected complaint in ComplaintHistoryScreen opens the exact rejected complaint (not preceding pending complaint with same title)',
        (tester) async {
      final complaintProv = ComplaintProvider();
      final authProv = AuthProvider();

      await tester.pumpWidget(createTestApp(
        complaintProv: complaintProv,
        authProv: authProv,
      ));
      await tester.pumpAndSettle();

      // Both complaints should be displayed in the history list under 'All' tab
      expect(find.text('RW-POTHOLE-PENDING • 5/1/2026 • 12:00 PM', skipOffstage: false), findsNothing); // format check
      expect(find.textContaining('RW-POTHOLE-PENDING'), findsOneWidget);
      expect(find.textContaining('RW-POTHOLE-REJECTED'), findsOneWidget);

      // Locate the card for the Rejected complaint using ValueKey
      final rejectedCardFinder = find.byKey(const ValueKey('RW-POTHOLE-REJECTED'));
      expect(rejectedCardFinder, findsOneWidget);

      // Tap on the Rejected complaint card
      await tester.tap(rejectedCardFinder);
      await tester.pumpAndSettle();

      // Verify that ComplaintTrackingScreen is now opened
      expect(find.byType(ComplaintTrackingScreen), findsOneWidget);

      // Verify AppBar and Header display RW-POTHOLE-REJECTED and NOT RW-POTHOLE-PENDING
      expect(find.text('Complaint RW-POTHOLE-REJECTED'), findsOneWidget);
      expect(find.text('Complaint RW-POTHOLE-PENDING'), findsNothing);

      // Verify Status badge shows Rejected
      expect(find.text('Rejected'), findsWidgets);

      // Verify tracking stages for rejected complaint: ['Submitted', 'Under Verification', 'Rejected']
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Under Verification'), findsOneWidget);
      expect(find.text('Final Decision: Rejected'), findsOneWidget);

      // Ensure Work Started or Repair In Progress is NOT present in rejected stages
      expect(find.text('Work Started'), findsNothing);
      expect(find.text('Repair In Progress'), findsNothing);
    });

    testWidgets('2. Tapping the Pending complaint opens the exact pending complaint',
        (tester) async {
      final complaintProv = ComplaintProvider();
      final authProv = AuthProvider();

      await tester.pumpWidget(createTestApp(
        complaintProv: complaintProv,
        authProv: authProv,
      ));
      await tester.pumpAndSettle();

      final pendingCardFinder = find.byKey(const ValueKey('RW-POTHOLE-PENDING'));
      expect(pendingCardFinder, findsOneWidget);

      await tester.tap(pendingCardFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ComplaintTrackingScreen), findsOneWidget);
      expect(find.text('Complaint RW-POTHOLE-PENDING'), findsOneWidget);
      expect(find.text('Complaint RW-POTHOLE-REJECTED'), findsNothing);
    });

    testWidgets('3. Searching by complaint ID filters correctly and tapping opens the exact complaint',
        (tester) async {
      final complaintProv = ComplaintProvider();
      final authProv = AuthProvider();

      await tester.pumpWidget(createTestApp(
        complaintProv: complaintProv,
        authProv: authProv,
      ));
      await tester.pumpAndSettle();

      // Search for REJECTED
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'RW-POTHOLE-REJECTED');
      await tester.pumpAndSettle();

      // Only REJECTED should be visible in filtered list
      expect(find.byKey(const ValueKey('RW-POTHOLE-REJECTED')), findsOneWidget);
      expect(find.byKey(const ValueKey('RW-POTHOLE-PENDING')), findsNothing);

      // Tap the filtered item
      await tester.tap(find.byKey(const ValueKey('RW-POTHOLE-REJECTED')));
      await tester.pumpAndSettle();

      expect(find.byType(ComplaintTrackingScreen), findsOneWidget);
      expect(find.text('Complaint RW-POTHOLE-REJECTED'), findsOneWidget);
    });

    testWidgets('4. Status tabs filter complaints correctly',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final complaintProv = ComplaintProvider();
      final authProv = AuthProvider();

      await tester.pumpWidget(createTestApp(
        complaintProv: complaintProv,
        authProv: authProv,
      ));
      await tester.pumpAndSettle();

      // Switch to 'Pending' tab
      await tester.tap(find.text('Pending'));
      await tester.pumpAndSettle();

      // In Pending tab: Rejected and Completed must NOT be shown
      expect(find.byKey(const ValueKey('RW-POTHOLE-PENDING')), findsOneWidget);
      expect(find.byKey(const ValueKey('RW-POTHOLE-REJECTED')), findsNothing);
      expect(find.byKey(const ValueKey('RW-POTHOLE-COMPLETED')), findsNothing);

      // Switch to 'Completed' tab
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('RW-POTHOLE-COMPLETED')), findsOneWidget);
      expect(find.byKey(const ValueKey('RW-POTHOLE-PENDING')), findsNothing);
      expect(find.byKey(const ValueKey('RW-POTHOLE-REJECTED')), findsNothing);

      // Switch back to 'All' tab
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('RW-POTHOLE-PENDING')), findsOneWidget);
      expect(find.byKey(const ValueKey('RW-POTHOLE-REJECTED')), findsOneWidget);
      expect(find.byKey(const ValueKey('RW-POTHOLE-COMPLETED')), findsOneWidget);
    });

    testWidgets('5. ComplaintTrackingScreen build strictly matches target complaintId and does not fall back to title match',
        (tester) async {
      final complaintProv = ComplaintProvider();
      final authProv = AuthProvider();

      // Open ComplaintTrackingScreen directly with rejectedPothole
      await tester.pumpWidget(createTestApp(
        complaintProv: complaintProv,
        authProv: authProv,
        child: ComplaintTrackingScreen(
          complaint: rejectedPothole,
          complaintId: rejectedPothole.complaintId,
        ),
      ));
      await tester.pumpAndSettle();

      // Even though pendingPothole is index 0 in complaintProv.complaints and has identical title 'Pothole',
      // ComplaintTrackingScreen must resolve to RW-POTHOLE-REJECTED
      expect(find.text('Complaint RW-POTHOLE-REJECTED'), findsOneWidget);
      expect(find.text('Complaint RW-POTHOLE-PENDING'), findsNothing);
      expect(find.text('Final Decision: Rejected'), findsOneWidget);
    });
  });
}
