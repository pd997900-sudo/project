import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RoadWatch app smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RoadWatchApp());
    expect(find.byType(RoadWatchApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
