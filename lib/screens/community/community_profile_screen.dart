import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/profile_avatar_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../services/supabase_service.dart';
import '../auth/sign_in_screen.dart';

class CommunityProfileScreen extends StatelessWidget {
  final VoidCallback? onBack;

  const CommunityProfileScreen({super.key, this.onBack});

  void _showEditProfileDialog(BuildContext context, AuthProvider authProvider) {
    final user = authProvider.currentUser;
    final initialName = (user != null && user.hasValidName) ? user.name : '';
    final nameCtrl = TextEditingController(text: initialName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Volunteer Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Crew Lead Name',
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
    final auth = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final user = auth.currentUser;

    final acceptedCount = complaintProv.complaints.where((c) => c.status == 'Accepted' || c.status == 'Work Started' || c.status == 'Repair In Progress').length;
    final completedCount = complaintProv.completedCount;

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
        title: const Text('Community User Profile'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Volunteer Avatar Card
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
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (user != null && !user.hasValidName) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => _showEditProfileDialog(context, auth),
                        icon: const Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.warningOrange),
                        label: const Text(
                          'Set Display Name',
                          style: TextStyle(color: AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? 'mark.repair@community.org',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.warningOrange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Role: Community Volunteer / Maintenance Crew',
                        style: TextStyle(
                          color: AppTheme.warningOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Activity Stats
              Row(
                children: [
                  Expanded(
                    child: GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            '$acceptedCount',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.warningOrange),
                          ),
                          const SizedBox(height: 4),
                          const Text('Active Works', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                            '$completedCount',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                          ),
                          const SizedBox(height: 4),
                          const Text('Completed Works', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Actions Menu
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline, color: AppTheme.primaryBlue),
                      title: const Text('Edit Volunteer Details'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showEditProfileDialog(context, auth),
                    ),
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.verified_sharp, color: AppTheme.primaryBlue),
                      title: Text('Crew Verification Badge'),
                      subtitle: Text('Certified Civic Maintenance Partner'),
                      trailing: Icon(Icons.check_circle, color: AppTheme.primaryBlue),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Logout Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await auth.logout('community');
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const SignInScreen()),
                        (route) => false,
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.emergencyRed,
                    side: const BorderSide(color: AppTheme.emergencyRed),
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
