import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/providers/complaint_provider.dart';
import 'package:roadwatch/theme/app_theme.dart';
import 'package:roadwatch/widgets/status_badge.dart';
import 'package:roadwatch/widgets/map_view_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoadWatch Severity Normalization & Color Mapping Tests', () {
    test('Normalizes severity strings correctly with trimming and case-insensitivity', () {
      // Emergency / Critical / High
      expect(Complaint.normalizeSeverity('Emergency'), equals('Emergency'));
      expect(Complaint.normalizeSeverity('emergency'), equals('Emergency'));
      expect(Complaint.normalizeSeverity(' EMERGENCY '), equals('Emergency'));
      expect(Complaint.normalizeSeverity('Critical'), equals('Emergency'));
      expect(Complaint.normalizeSeverity('CRITICAL'), equals('Emergency'));
      expect(Complaint.normalizeSeverity('High'), equals('Emergency'));
      expect(Complaint.normalizeSeverity('high'), equals('Emergency'));
      expect(Complaint.normalizeSeverity(' HIGH '), equals('Emergency'));

      // Medium
      expect(Complaint.normalizeSeverity('Medium'), equals('Medium'));
      expect(Complaint.normalizeSeverity('medium'), equals('Medium'));
      expect(Complaint.normalizeSeverity(' MEDIUM '), equals('Medium'));
      expect(Complaint.normalizeSeverity('Moderate'), equals('Medium'));
      expect(Complaint.normalizeSeverity('med'), equals('Medium'));
      expect(Complaint.normalizeSeverity('amber'), equals('Medium'));
      expect(Complaint.normalizeSeverity('yellow'), equals('Medium'));

      // Low
      expect(Complaint.normalizeSeverity('Low'), equals('Low'));
      expect(Complaint.normalizeSeverity('low'), equals('Low'));
      expect(Complaint.normalizeSeverity(' LOW '), equals('Low'));
      expect(Complaint.normalizeSeverity(' low '), equals('Low'));

      // Null, empty, and unknown fallbacks
      expect(Complaint.normalizeSeverity(null), equals('Low'));
      expect(Complaint.normalizeSeverity(''), equals('Low'));
      expect(Complaint.normalizeSeverity('   '), equals('Low'));
      expect(Complaint.normalizeSeverity('Unknown'), equals('Low'));
    });

    test('Maps severity to correct Color values', () {
      // Red for Emergency / Critical / High
      expect(Complaint.getSeverityColor('Emergency'), equals(AppTheme.emergencyRed));
      expect(Complaint.getSeverityColor('emergency'), equals(AppTheme.emergencyRed));
      expect(Complaint.getSeverityColor('Critical'), equals(AppTheme.emergencyRed));
      expect(Complaint.getSeverityColor('High'), equals(AppTheme.emergencyRed));

      // Yellow / Amber for Medium
      expect(Complaint.getSeverityColor('Medium'), equals(const Color(0xFFF59E0B)));
      expect(Complaint.getSeverityColor('medium'), equals(const Color(0xFFF59E0B)));
      expect(Complaint.getSeverityColor('Moderate'), equals(const Color(0xFFF59E0B)));

      // Green for Low
      expect(Complaint.getSeverityColor('Low'), equals(AppTheme.successGreen));
      expect(Complaint.getSeverityColor('low'), equals(AppTheme.successGreen));
      expect(Complaint.getSeverityColor(' LOW '), equals(AppTheme.successGreen));
      expect(Complaint.getSeverityColor(null), equals(AppTheme.successGreen));
    });

    test('Maps severity to correct Hex colors for map pins', () {
      // Red hex for Emergency / Critical / High
      expect(Complaint.getSeverityHexColor('Emergency'), equals('#E53935'));
      expect(Complaint.getSeverityHexColor('emergency'), equals('#E53935'));
      expect(Complaint.getSeverityHexColor('Critical'), equals('#E53935'));
      expect(Complaint.getSeverityHexColor('High'), equals('#E53935'));

      // Yellow / Amber hex for Medium
      expect(Complaint.getSeverityHexColor('Medium'), equals('#F59E0B'));
      expect(Complaint.getSeverityHexColor('medium'), equals('#F59E0B'));

      // Green hex for Low
      expect(Complaint.getSeverityHexColor('Low'), equals('#43A047'));
      expect(Complaint.getSeverityHexColor('low'), equals('#43A047'));
      expect(Complaint.getSeverityHexColor(' LOW '), equals('#43A047'));
      expect(Complaint.getSeverityHexColor(''), equals('#43A047'));
      expect(Complaint.getSeverityHexColor(null), equals('#43A047'));
    });

    test('Complaint instances return correct severityColor and severityHexColor', () {
      final emergency = Complaint(
        complaintId: 'TEST-EMG',
        reporterId: 'u1',
        reporterName: 'Reporter 1',
        title: 'Emergency Pothole',
        description: 'Dangerous',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 13.0,
        longitude: 80.0,
        address: 'Test Rd',
        imageUrl: '',
        status: 'Submitted',
      );

      final medium = Complaint(
        complaintId: 'TEST-MED',
        reporterId: 'u2',
        reporterName: 'Reporter 2',
        title: 'Medium Crack',
        description: 'Moderate damage',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 13.1,
        longitude: 80.1,
        address: 'Test Rd 2',
        imageUrl: '',
        status: 'Submitted',
      );

      final low = Complaint(
        complaintId: 'TEST-LOW',
        reporterId: 'u3',
        reporterName: 'Reporter 3',
        title: 'Minor Surface Scratch',
        description: 'Small scratch',
        category: 'Damaged Road',
        severity: 'Low',
        latitude: 13.2,
        longitude: 80.2,
        address: 'Test Rd 3',
        imageUrl: '',
        status: 'Submitted',
      );

      final lowUntrimmed = Complaint(
        complaintId: 'TEST-LOW-SPACE',
        reporterId: 'u4',
        reporterName: 'Reporter 4',
        title: 'Untrimmed Low',
        description: 'Small scratch',
        category: 'Damaged Road',
        severity: '  Low  ',
        latitude: 13.3,
        longitude: 80.3,
        address: 'Test Rd 4',
        imageUrl: '',
        status: 'Repair In Progress',
      );

      // Verify Emergency
      expect(emergency.severityColor, equals(AppTheme.emergencyRed));
      expect(emergency.severityHexColor, equals('#E53935'));
      expect(emergency.isEmergency, isTrue);

      // Verify Medium
      expect(medium.severityColor, equals(const Color(0xFFF59E0B)));
      expect(medium.severityHexColor, equals('#F59E0B'));
      expect(medium.isEmergency, isFalse);

      // Verify Low always renders GREEN
      expect(low.severityColor, equals(AppTheme.successGreen));
      expect(low.severityHexColor, equals('#43A047'));
      expect(low.severityHexColor, isNot(equals('#FFFF00')));
      expect(low.severityHexColor, isNot(equals('#F59E0B')));
      expect(low.isEmergency, isFalse);

      // Verify Untrimmed Low also renders GREEN
      expect(lowUntrimmed.severityColor, equals(AppTheme.successGreen));
      expect(lowUntrimmed.severityHexColor, equals('#43A047'));
      expect(lowUntrimmed.severityHexColor, isNot(equals('#FFFF00')));
    });

    test('Low severity complaint status does not alter its green severity color', () {
      final statuses = [
        'Submitted',
        'Under Verification',
        'Verified',
        'Accepted',
        'Work Started',
        'Repair In Progress',
        'Completed',
      ];

      for (final s in statuses) {
        final c = Complaint(
          complaintId: 'TEST-STATUS-$s',
          reporterId: 'u1',
          reporterName: 'Reporter 1',
          title: 'Low complaint with status $s',
          description: 'Description',
          category: 'Pothole',
          severity: 'Low',
          latitude: 13.0,
          longitude: 80.0,
          address: 'Test Rd',
          imageUrl: '',
          status: s,
        );

        expect(c.severityHexColor, equals('#43A047'), reason: 'Status $s should not change Low severity color');
        expect(c.severityColor, equals(AppTheme.successGreen));
      }
    });

    test('Complaint.fromJson parses and defaults severity correctly', () {
      // Explicit Low
      final jsonLow = {
        'complaint_id': 'JSON-1',
        'severity': 'Low',
        'status': 'Submitted',
      };
      final parsedLow = Complaint.fromJson(jsonLow);
      expect(parsedLow.severity, equals('Low'));
      expect(parsedLow.severityHexColor, equals('#43A047'));

      // Untrimmed lower-case low
      final jsonLowCase = {
        'complaint_id': 'JSON-2',
        'severity': ' low ',
        'status': 'Submitted',
      };
      final parsedLowCase = Complaint.fromJson(jsonLowCase);
      expect(parsedLowCase.severityHexColor, equals('#43A047'));

      // Null severity defaults to Low (Green), NOT Yellow
      final jsonNull = {
        'complaint_id': 'JSON-3',
        'severity': null,
        'status': 'Submitted',
      };
      final parsedNull = Complaint.fromJson(jsonNull);
      expect(parsedNull.severityHexColor, equals('#43A047'));
      expect(parsedNull.severityColor, equals(AppTheme.successGreen));

      // Missing severity key defaults to Low (Green)
      final jsonMissing = {
        'complaint_id': 'JSON-4',
        'status': 'Submitted',
      };
      final parsedMissing = Complaint.fromJson(jsonMissing);
      expect(parsedMissing.severityHexColor, equals('#43A047'));
    });

    testWidgets('SeverityBadge renders with correct colors for Emergency, Medium, and Low', (tester) async {
      // Low badge
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SeverityBadge(severity: 'Low'),
          ),
        ),
      );
      expect(find.text('LOW'), findsOneWidget);
      final lowIcon = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline));
      expect(lowIcon.color, equals(AppTheme.successGreen));

      // Medium badge
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SeverityBadge(severity: 'Medium'),
          ),
        ),
      );
      expect(find.text('MEDIUM'), findsOneWidget);
      final medIcon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
      expect(medIcon.color, equals(const Color(0xFFF57F17)));

      // Emergency badge
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SeverityBadge(severity: 'Emergency'),
          ),
        ),
      );
      expect(find.text('EMERGENCY'), findsOneWidget);
      final emgIcon = tester.widget<Icon>(find.byIcon(Icons.warning_rounded));
      expect(emgIcon.color, equals(AppTheme.emergencyRed));

      // High badge also renders red
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SeverityBadge(severity: 'High'),
          ),
        ),
      );
      expect(find.text('HIGH'), findsOneWidget);
      final highIcon = tester.widget<Icon>(find.byIcon(Icons.warning_rounded));
      expect(highIcon.color, equals(AppTheme.emergencyRed));
    });

    testWidgets('MapViewWidget displays updated legend with Red=Emergency, Yellow=Medium, Green=Low', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('_channel') ||
            details.exceptionAsString().contains('LateInitializationError')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ComplaintProvider>(
              create: (_) => ComplaintProvider(),
              child: const MapViewWidget(
                initialLat: 13.0,
                initialLng: 80.0,
                isPickerMode: false,
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('Map View: Pins (Red=Emergency, Yellow=Medium, Green=Low)'),
        findsOneWidget,
      );
    });
  });
}
