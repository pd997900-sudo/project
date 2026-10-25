import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Role-Based Authentication Tests', () {
    test('Reporter registration assigns reporter role', () async {
      final authProvider = AuthProvider();
      authProvider.setSelectedRole('reporter');

      final success = await authProvider.initiateRegistration(
        name: 'Reporter User',
        email: 'reporter.test@example.com',
        phone: '+1 555-0100',
        password: 'password123',
        role: 'reporter',
      );

      expect(success, isTrue);

      final verifySuccess = await authProvider.verifyOtpAndCompleteSignup(authProvider.pendingOtp!);
      expect(verifySuccess, isTrue);

      // Verify sign in with reporter role on Reporter portal
      authProvider.setSelectedRole('reporter');
      final signInSuccess = await authProvider.signIn(
        email: 'reporter.test@example.com',
        password: 'password123',
      );

      expect(signInSuccess, isTrue);
      expect(authProvider.currentUser?.role, equals('reporter'));
      expect(authProvider.currentUser?.isReporter, isTrue);
    });

    test('Community registration assigns community role', () async {
      final authProvider = AuthProvider();
      authProvider.setSelectedRole('community');

      final success = await authProvider.initiateRegistration(
        name: 'Community User',
        email: 'community.test@example.com',
        phone: '+1 555-0200',
        password: 'password123',
        role: 'community',
      );

      expect(success, isTrue);

      final verifySuccess = await authProvider.verifyOtpAndCompleteSignup(authProvider.pendingOtp!);
      expect(verifySuccess, isTrue);

      // Verify sign in with community role on Community portal
      authProvider.setSelectedRole('community');
      final signInSuccess = await authProvider.signIn(
        email: 'community.test@example.com',
        password: 'password123',
      );

      expect(signInSuccess, isTrue);
      expect(authProvider.currentUser?.role, equals('community'));
      expect(authProvider.currentUser?.isCommunity, isTrue);
    });

    test('Reporter account attempting Community portal login is REJECTED', () async {
      final authProvider = AuthProvider();
      authProvider.setSelectedRole('reporter');

      await authProvider.initiateRegistration(
        name: 'Reporter User',
        email: 'reporter.only@example.com',
        phone: '+1 555-0101',
        password: 'password123',
        role: 'reporter',
      );
      await authProvider.verifyOtpAndCompleteSignup(authProvider.pendingOtp!);

      // Now attempt sign in on Community portal
      authProvider.setSelectedRole('community');
      final signInSuccess = await authProvider.signIn(
        email: 'reporter.only@example.com',
        password: 'password123',
      );

      expect(signInSuccess, isFalse);
      expect(
        authProvider.errorMessage,
        equals('This account is registered as a Reporter. Please sign in through the Reporter Portal.'),
      );
    });

    test('Community account attempting Reporter portal login is REJECTED', () async {
      final authProvider = AuthProvider();
      authProvider.setSelectedRole('community');

      await authProvider.initiateRegistration(
        name: 'Community User',
        email: 'community.only@example.com',
        phone: '+1 555-0201',
        password: 'password123',
        role: 'community',
      );
      await authProvider.verifyOtpAndCompleteSignup(authProvider.pendingOtp!);

      // Now attempt sign in on Reporter portal
      authProvider.setSelectedRole('reporter');
      final signInSuccess = await authProvider.signIn(
        email: 'community.only@example.com',
        password: 'password123',
      );

      expect(signInSuccess, isFalse);
      expect(
        authProvider.errorMessage,
        equals('This account is registered as a Community User. Please sign in through the Community Portal.'),
      );
    });
  });
}
