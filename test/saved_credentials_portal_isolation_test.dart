import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/providers/auth_provider.dart';
import 'package:roadwatch/screens/auth/sign_in_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Saved Credentials Portal Isolation Tests', () {
    test('Saving Reporter credentials leaves Community saved credentials empty', () async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      // Save Reporter credentials
      await authProvider.saveCredentials(
        email: 'dindupuji04@gmail.com',
        password: 'ReporterSecret123',
        rememberMe: true,
        role: 'reporter',
      );

      // Verify Reporter credentials loaded
      expect(authProvider.getSavedEmail('reporter'), equals('dindupuji04@gmail.com'));
      expect(authProvider.getSavedPassword('reporter'), equals('ReporterSecret123'));
      expect(authProvider.getRememberMe('reporter'), isTrue);

      // Verify Community credentials remain completely null / empty
      expect(authProvider.getSavedEmail('community'), isNull);
      expect(authProvider.getSavedPassword('community'), isNull);
      expect(authProvider.getAvailableSavedEmails('community'), isEmpty);
      expect(authProvider.getAvailableSavedAccounts('community'), isEmpty);
    });

    test('Saving Community credentials leaves Reporter saved credentials unaffected', () async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      // Save Reporter credentials
      await authProvider.saveCredentials(
        email: 'dindupuji04@gmail.com',
        password: 'ReporterSecret123',
        rememberMe: true,
        role: 'reporter',
      );

      // Save Community credentials for a different account
      await authProvider.saveCredentials(
        email: 'community.lead@roadwatch.org',
        password: 'CommunityPass456',
        rememberMe: true,
        role: 'community',
      );

      // Verify each portal returns only its own saved credentials
      expect(authProvider.getSavedEmail('reporter'), equals('dindupuji04@gmail.com'));
      expect(authProvider.getSavedPassword('reporter'), equals('ReporterSecret123'));

      expect(authProvider.getSavedEmail('community'), equals('community.lead@roadwatch.org'));
      expect(authProvider.getSavedPassword('community'), equals('CommunityPass456'));

      expect(authProvider.getAvailableSavedEmails('reporter'), contains('dindupuji04@gmail.com'));
      expect(authProvider.getAvailableSavedEmails('reporter'), isNot(contains('community.lead@roadwatch.org')));

      expect(authProvider.getAvailableSavedEmails('community'), contains('community.lead@roadwatch.org'));
      expect(authProvider.getAvailableSavedEmails('community'), isNot(contains('dindupuji04@gmail.com')));
    });

    test('Unchecking Save Account for one portal clears only that portal', () async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      // Save both
      await authProvider.saveCredentials(
        email: 'reporter@roadwatch.org',
        password: 'PasswordRep123',
        rememberMe: true,
        role: 'reporter',
      );
      await authProvider.saveCredentials(
        email: 'community@roadwatch.org',
        password: 'PasswordComm456',
        rememberMe: true,
        role: 'community',
      );

      // Uncheck Save Account for Reporter (saveCredentials with rememberMe: false)
      await authProvider.saveCredentials(
        email: 'reporter@roadwatch.org',
        password: 'PasswordRep123',
        rememberMe: false,
        role: 'reporter',
      );

      // Reporter must be cleared
      expect(authProvider.getSavedEmail('reporter'), isNull);
      expect(authProvider.getSavedPassword('reporter'), isNull);
      expect(authProvider.getRememberMe('reporter'), isFalse);

      // Community must remain intact
      expect(authProvider.getSavedEmail('community'), equals('community@roadwatch.org'));
      expect(authProvider.getSavedPassword('community'), equals('PasswordComm456'));
      expect(authProvider.getRememberMe('community'), isTrue);
    });

    test('Passwords in SharedPreferences are stored encrypted, never in plain text', () async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      const plainPassword = 'SuperSecretPujithaPassword99!';
      await authProvider.saveCredentials(
        email: 'dindupuji04@gmail.com',
        password: plainPassword,
        rememberMe: true,
        role: 'reporter',
      );

      final prefs = await SharedPreferences.getInstance();
      final storedRawPassword = prefs.getString('roadwatch_reporter_saved_password_sec_v12');

      expect(storedRawPassword, isNotNull);
      // Stored value must start with encryption header
      expect(storedRawPassword!.startsWith('rw_sec_v1:'), isTrue);
      // Plain text must not appear anywhere in raw storage
      expect(storedRawPassword.contains(plainPassword), isFalse);

      final storedMapJson = prefs.getString('roadwatch_reporter_saved_credentials_map_sec_v12');
      expect(storedMapJson, isNotNull);
      expect(storedMapJson!.contains(plainPassword), isFalse);
    });

    test('Distinct storage keys are used and legacy shared keys are never populated', () async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      await authProvider.saveCredentials(
        email: 'dindupuji04@gmail.com',
        password: 'Password123',
        rememberMe: true,
        role: 'reporter',
      );

      final prefs = await SharedPreferences.getInstance();

      // Verify reporter distinct keys exist
      expect(prefs.containsKey('roadwatch_reporter_saved_email_v12'), isTrue);
      expect(prefs.containsKey('roadwatch_reporter_saved_password_sec_v12'), isTrue);
      expect(prefs.containsKey('roadwatch_reporter_remember_me_v12'), isTrue);

      // Verify community distinct keys do not exist
      expect(prefs.containsKey('roadwatch_community_saved_email_v12'), isFalse);
      expect(prefs.containsKey('roadwatch_community_saved_password_sec_v12'), isFalse);

      // Verify legacy shared keys are not populated
      expect(prefs.containsKey('roadwatch_saved_email_v10'), isFalse);
      expect(prefs.containsKey('roadwatch_saved_password_v10'), isFalse);
      expect(prefs.containsKey('roadwatch_remember_me_v10'), isFalse);
    });

    test('Removing saved account on Community does not affect Reporter portal', () async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      // Same email saved in both portals
      await authProvider.saveCredentials(
        email: 'same.user@roadwatch.org',
        password: 'PassReporter123',
        rememberMe: true,
        role: 'reporter',
      );
      await authProvider.saveCredentials(
        email: 'same.user@roadwatch.org',
        password: 'PassCommunity456',
        rememberMe: true,
        role: 'community',
      );

      // Remove from Community
      await authProvider.removeSavedAccount('same.user@roadwatch.org', 'community');

      // Community must not have it
      expect(authProvider.getSavedEmail('community'), isNull);
      expect(authProvider.getAvailableSavedEmails('community'), isNot(contains('same.user@roadwatch.org')));

      // Reporter must still have it
      expect(authProvider.getSavedEmail('reporter'), equals('same.user@roadwatch.org'));
      expect(authProvider.getSavedPassword('reporter'), equals('PassReporter123'));
      expect(authProvider.getAvailableSavedEmails('reporter'), contains('same.user@roadwatch.org'));
    });

    testWidgets('Direction 1: Save Reporter credentials and open Community login - fields blank & no leak', (tester) async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      await authProvider.saveCredentials(
        email: 'reporter@roadwatch.org',
        password: 'ReporterSecret123',
        rememberMe: true,
        role: 'reporter',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            home: SignInScreen(portalRole: 'community'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextField, 'Email Address');
      final passwordFinder = find.widgetWithText(TextField, 'Password');

      expect(emailFinder, findsOneWidget);
      expect(passwordFinder, findsOneWidget);

      final emailWidget = tester.widget<TextField>(emailFinder);
      final passwordWidget = tester.widget<TextField>(passwordFinder);

      // 1. Both fields must be completely blank on fresh open
      expect(emailWidget.controller?.text, isEmpty);
      expect(passwordWidget.controller?.text, isEmpty);

      // 2. Reporter credentials must NOT be displayed
      expect(find.text('reporter@roadwatch.org'), findsNothing);

      // 3. Focus on Email field -> Community must NOT show Reporter suggestions
      await tester.tap(emailFinder);
      await tester.pumpAndSettle();

      expect(find.text('Saved Reporter Accounts'), findsNothing);
      expect(find.text('reporter@roadwatch.org'), findsNothing);
      expect(emailWidget.controller?.text, isEmpty);
      expect(passwordWidget.controller?.text, isEmpty);
    });

    testWidgets('Direction 2: Save Community credentials and open Reporter login - fields blank & no leak', (tester) async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      await authProvider.saveCredentials(
        email: 'community@roadwatch.org',
        password: 'CommunitySecret456',
        rememberMe: true,
        role: 'community',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            home: SignInScreen(portalRole: 'reporter'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextField, 'Email Address');
      final passwordFinder = find.widgetWithText(TextField, 'Password');

      expect(emailFinder, findsOneWidget);
      expect(passwordFinder, findsOneWidget);

      final emailWidget = tester.widget<TextField>(emailFinder);
      final passwordWidget = tester.widget<TextField>(passwordFinder);

      // 1. Both fields must be completely blank on fresh open
      expect(emailWidget.controller?.text, isEmpty);
      expect(passwordWidget.controller?.text, isEmpty);

      // 2. Community credentials must NOT be displayed
      expect(find.text('community@roadwatch.org'), findsNothing);

      // 3. Focus on Email field -> Reporter must NOT show Community suggestions
      await tester.tap(emailFinder);
      await tester.pumpAndSettle();

      expect(find.text('Saved Community Accounts'), findsNothing);
      expect(find.text('community@roadwatch.org'), findsNothing);
      expect(emailWidget.controller?.text, isEmpty);
      expect(passwordWidget.controller?.text, isEmpty);
    });

    testWidgets('Matching portal shows only its own saved suggestions on focus and autofills masked password', (tester) async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      await authProvider.saveCredentials(
        email: 'reporter.user@roadwatch.org',
        password: 'MyMaskedPassword999',
        rememberMe: true,
        role: 'reporter',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            home: SignInScreen(portalRole: 'reporter'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextField, 'Email Address');
      final passwordFinder = find.widgetWithText(TextField, 'Password');

      // Blank on fresh open
      expect(tester.widget<TextField>(emailFinder).controller?.text, isEmpty);
      expect(tester.widget<TextField>(passwordFinder).controller?.text, isEmpty);

      // Tap email field to show role suggestions
      await tester.tap(emailFinder);
      await tester.pumpAndSettle();

      expect(find.text('Saved Reporter Accounts'), findsOneWidget);
      expect(find.text('reporter.user@roadwatch.org'), findsOneWidget);

      // Tap suggestion to autofill
      await tester.tap(find.text('reporter.user@roadwatch.org'));
      await tester.pumpAndSettle();

      // Fields are populated with matching credentials
      expect(tester.widget<TextField>(emailFinder).controller?.text, equals('reporter.user@roadwatch.org'));
      expect(tester.widget<TextField>(passwordFinder).controller?.text, equals('MyMaskedPassword999'));

      // Password remains masked
      expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
    });

    testWidgets('Community portal shows only its own saved suggestions on focus and autofills masked password', (tester) async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      await authProvider.saveCredentials(
        email: 'volunteer@roadwatch.org',
        password: 'CommunityPassword789',
        rememberMe: true,
        role: 'community',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            home: SignInScreen(portalRole: 'community'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextField, 'Email Address');
      final passwordFinder = find.widgetWithText(TextField, 'Password');

      // Blank on fresh open
      expect(tester.widget<TextField>(emailFinder).controller?.text, isEmpty);
      expect(tester.widget<TextField>(passwordFinder).controller?.text, isEmpty);

      // Tap email field to show role suggestions
      await tester.tap(emailFinder);
      await tester.pumpAndSettle();

      expect(find.text('Saved Community Accounts'), findsOneWidget);
      expect(find.text('volunteer@roadwatch.org'), findsOneWidget);

      // Tap suggestion to autofill
      await tester.tap(find.text('volunteer@roadwatch.org'));
      await tester.pumpAndSettle();

      // Fields are populated with matching credentials
      expect(tester.widget<TextField>(emailFinder).controller?.text, equals('volunteer@roadwatch.org'));
      expect(tester.widget<TextField>(passwordFinder).controller?.text, equals('CommunityPassword789'));

      // Password remains masked
      expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);
    });

    testWidgets('Pointer down on suggestion populates email and password immediately before focus changes', (tester) async {
      final authProvider = AuthProvider();
      await authProvider.ensureStorageLoaded();

      await authProvider.saveCredentials(
        email: 'instant.click@roadwatch.org',
        password: 'InstantPass321',
        rememberMe: true,
        role: 'reporter',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: const MaterialApp(
            home: SignInScreen(portalRole: 'reporter'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailFinder = find.widgetWithText(TextField, 'Email Address');
      final passwordFinder = find.widgetWithText(TextField, 'Password');

      // Tap email field to open suggestions
      await tester.tap(emailFinder);
      await tester.pumpAndSettle();

      final suggestionFinder = find.text('instant.click@roadwatch.org');
      expect(suggestionFinder, findsOneWidget);

      // Dispatch pointer down without pointer up
      final gesture = await tester.startGesture(tester.getCenter(suggestionFinder));
      await tester.pump();

      // Fields must immediately be populated by onPointerDown
      expect(tester.widget<TextField>(emailFinder).controller?.text, equals('instant.click@roadwatch.org'));
      expect(tester.widget<TextField>(passwordFinder).controller?.text, equals('InstantPass321'));

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
