import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../providers/auth_provider.dart';
import 'auth/sign_in_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final selectedRole = authProvider.selectedRole;

    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientBackgroundDecoration,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Select Your Role',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose how you will participate in the RoadWatch community.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 40),

                // Role Option 1: Reporter
                Expanded(
                  child: GlassCard(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(24),
                    opacity: selectedRole == 'reporter' ? 0.95 : 0.4,
                    backgroundColor: selectedRole == 'reporter'
                        ? Colors.white
                        : Colors.white.withOpacity(0.2),
                    onTap: () {
                      authProvider.setSelectedRole('reporter');
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: selectedRole == 'reporter'
                                ? AppTheme.primaryDark
                                : Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_pin_circle_rounded,
                            size: 48,
                            color: selectedRole == 'reporter'
                                ? Colors.white
                                : Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Reporter (Citizen)',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: selectedRole == 'reporter'
                                ? AppTheme.primaryDark
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Report road damage, upload photos, pin map locations, and track repair status.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: selectedRole == 'reporter'
                                ? Colors.black87
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Role Option 2: Community User
                Expanded(
                  child: GlassCard(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(24),
                    opacity: selectedRole == 'community' ? 0.95 : 0.4,
                    backgroundColor: selectedRole == 'community'
                        ? Colors.white
                        : Colors.white.withOpacity(0.2),
                    onTap: () {
                      authProvider.setSelectedRole('community');
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: selectedRole == 'community'
                                ? AppTheme.primaryDark
                                : Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.engineering_rounded,
                            size: 48,
                            color: selectedRole == 'community'
                                ? Colors.white
                                : Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Community User (Volunteer / Crew)',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: selectedRole == 'community'
                                ? AppTheme.primaryDark
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Verify reports, mark fake complaints, accept repair tasks, and upload completed photos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: selectedRole == 'community'
                                ? Colors.black87
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Continue Button
                GradientButton(
                  text: 'Continue as ${selectedRole == "reporter" ? "Reporter" : "Community User"}',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SignInScreen(portalRole: selectedRole),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
