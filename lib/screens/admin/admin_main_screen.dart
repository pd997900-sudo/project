import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../auth/sign_in_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_complaints_screen.dart';
import 'admin_community_users_screen.dart';
import 'admin_repair_teams_screen.dart';

class AdminMainScreen extends StatefulWidget {
  final int initialTabIndex;
  const AdminMainScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
  }

  void _onNavigate(int idx) {
    setState(() {
      _currentIndex = idx;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      AdminDashboardScreen(onNavigateTab: _onNavigate),
      const AdminComplaintsScreen(),
      const AdminCommunityUsersScreen(),
      const AdminRepairTeamsScreen(),
      _buildAdminProfileScreen(context),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _currentIndex = 0;
        });
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onNavigate,
              backgroundColor: Colors.white,
              selectedItemColor: AppTheme.primaryDark,
              unselectedItemColor: Colors.grey.shade500,
              selectedFontSize: 11,
              unselectedFontSize: 10,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_rounded),
                  activeIcon: Icon(Icons.dashboard_rounded, color: AppTheme.primaryDark),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.report_problem_outlined),
                  activeIcon: Icon(Icons.report_problem_rounded, color: AppTheme.primaryDark),
                  label: 'Complaints',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_alt_outlined),
                  activeIcon: Icon(Icons.people_alt_rounded, color: AppTheme.primaryDark),
                  label: 'Community',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.handyman_outlined),
                  activeIcon: Icon(Icons.handyman_rounded, color: AppTheme.primaryDark),
                  label: 'Repair Teams',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  activeIcon: Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primaryDark),
                  label: 'Admin',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminProfileScreen(BuildContext context) {
    final authProv = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final user = authProv.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('National Administrator', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh All',
            onPressed: () => complaintProv.refreshComplaints(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Admin Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.amber.shade400,
                      child: const Icon(Icons.shield_rounded, size: 42, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      user?.name ?? 'National Administrator',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? 'admin@roadwatch.gov.in',
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade400.withOpacity(0.2),
                        border: Border.all(color: Colors.amber.shade400, width: 1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '🇮🇳 India-Level Central Control',
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'System Administration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 12),

              _buildSettingsTile(
                icon: Icons.map_rounded,
                title: 'National Scope',
                subtitle: 'All 36 States & Union Territories active',
                trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
              ),
              const SizedBox(height: 8),

              _buildSettingsTile(
                icon: Icons.security_rounded,
                title: 'Privilege Level',
                subtitle: 'Super Administrator • Unrestricted District Access',
                trailing: const Icon(Icons.lock_open_rounded, color: Colors.amber, size: 20),
              ),
              const SizedBox(height: 8),

              _buildSettingsTile(
                icon: Icons.sync_rounded,
                title: 'Sync Status',
                subtitle: 'Supabase Real-Time Sync Active',
                trailing: const Icon(Icons.cloud_done_rounded, color: Colors.blue, size: 20),
              ),

              const SizedBox(height: 32),

              ElevatedButton.icon(
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign Out of Admin Portal', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Sign Out?'),
                      content: const Text('Are you sure you want to sign out of the India-Level Admin Portal?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && context.mounted) {
                    await authProv.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const SignInScreen()),
                        (route) => false,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryDark.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryDark, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        trailing: trailing,
      ),
    );
  }
}

