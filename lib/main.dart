import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/complaint_provider.dart';
import 'providers/chat_provider.dart';
import 'services/supabase_service.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep the application in portrait mode.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Supabase.
  await SupabaseService.initialize();

  runApp(const RoadWatchApp());
}

class RoadWatchApp extends StatelessWidget {
  const RoadWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProvider<ComplaintProvider>(
          create: (_) => ComplaintProvider(),
        ),
        ChangeNotifierProvider<ChatProvider>(
          create: (_) => ChatProvider(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RoadWatch',
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}