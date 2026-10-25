import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/profile_avatar_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../services/supabase_service.dart';
import '../auth/sign_in_screen.dart';

class ReporterProfileScreen extends StatelessWidget {
  final VoidCallback? onBack;

  const ReporterProfileScreen({super.key, this.onBack});

  void _showEditProfileDialog(BuildContext context, AuthProvider authProvider) {
    final user = authProvider.currentUser;
    final initialName = (user != null && user.hasValidName) ? user.name : '';
    final nameCtrl = TextEditingController(text: initialName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Profile Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'Enter your actual display name',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty && !newName.contains('@')) {
                await SupabaseService.updateCurrentUserName(newName);
                authProvider.updateProfile(
                  name: newName,
                  avatarUrl: authProvider.currentUser?.avatarUrl,
                );
              }
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Profile updated successfully!'),
                    backgroundColor: AppTheme.successGreen,
                  ),
                );
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final user = authProvider.currentUser;

    final mySubmittedCount = complaintProv.reporterComplaints.length;
    final myCompletedCount = complaintProv.reporterComplaints.where((c) => c.status == 'Completed').length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            if (onBack != null) {
              onBack!();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        title: const Text('Reporter Profile'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // User Avatar & Name Card
              GlassCard(
                borderRadius: 24,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    ProfileAvatarWidget(
                      avatarUrl: user?.avatarUrl,
                      radius: 46,
                      borderWidth: 3,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      (user != null && user.hasValidName) ? user.name : 'Name not available',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    if (user != null && !user.hasValidName) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => _showEditProfileDialog(context, authProvider),
                        icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.primaryBlue),
                        label: const Text(
                          'Set Display Name',
                          style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Role: Citizen Reporter',
                        style: TextStyle(
                          color: AppTheme.primaryDark,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Activity Stats Row
              Row(
                children: [
                  Expanded(
                    child: GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            '$mySubmittedCount',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                          ),
                          const SizedBox(height: 4),
                          const Text('Submitted', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            '$myCompletedCount',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                          ),
                          const SizedBox(height: 4),
                          const Text('Repaired', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Profile Actions Menu
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline, color: AppTheme.primaryBlue),
                      title: const Text('Edit Profile'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showEditProfileDialog(context, authProvider),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined, color: AppTheme.successGreen),
                      title: const Text('Email OTP Status'),
                      subtitle: const Text('Verified via EmailJS OTP'),
                      trailing: const Icon(Icons.check_circle, color: AppTheme.successGreen),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Logout Action Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await authProvider.logout('reporter');
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const SignInScreen()),
                        (route) => false,
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
