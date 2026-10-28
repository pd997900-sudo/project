import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../models/india_districts.dart';
import '../auth/sign_in_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final Function(int tabIndex)? onNavigateTab;
  const AdminDashboardScreen({super.key, this.onNavigateTab});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String? _selectedState;
  String? _selectedDistrict;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ComplaintProvider>().refreshComplaints();
    });
  }

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final authProv = Provider.of<AuthProvider>(context);
    final user = authProv.currentUser;

    // Filter complaints based on local dashboard state/district filter
    var complaints = complaintProv.complaints;
    if (_selectedState != null && _selectedState != 'All') {
      complaints = complaints.where((c) => c.stateDisplay.toLowerCase() == _selectedState!.toLowerCase()).toList();
    }
    if (_selectedDistrict != null && _selectedDistrict != 'All') {
      complaints = complaints.where((c) => c.districtDisplay.toLowerCase() == _selectedDistrict!.toLowerCase()).toList();
    }

    final totalReports = complaints.length;
    final activeCount = complaints.where((c) => c.isActive).length;
    final inProgressCount = complaints.where((c) =>
        c.status.toLowerCase() == 'accepted' ||
        c.status.toLowerCase() == 'work started' ||
        c.status.toLowerCase() == 'repair in progress' ||
        c.status.toLowerCase() == 'near completion').length;
    final completedCount = complaints.where((c) => c.isCompleted || c.status.toLowerCase() == 'completed').length;
    final emergencyCount = complaints.where((c) => c.isEmergency && c.status.toLowerCase() != 'completed' && c.status.toLowerCase() != 'rejected').length;
    final resolutionRate = totalReports > 0 ? ((completedCount / totalReports) * 100).toStringAsFixed(1) : '0.0';

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RoadWatch National Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('India-Level Central Command', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () => complaintProv.refreshComplaints(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await authProv.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SignInScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: RefreshIndicator(
          onRefresh: () => complaintProv.refreshComplaints(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Admin Banner Card
                GlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(16),
                  backgroundColor: AppTheme.primaryDark.withOpacity(0.9),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield_outlined, color: Colors.amber, size: 32),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Logged in as ${user?.name ?? "Central Administrator"}',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'All-India Jurisdiction • State & District Governance',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // State and District Quick Filter
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune_rounded, color: AppTheme.primaryBlue, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Territorial Scope & Filter',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // State Dropdown
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedState ?? 'All',
                                decoration: const InputDecoration(
                                  labelText: 'State',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(value: 'All', child: Text('All States (India)')),
                                  ...IndiaDistricts.states.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedState = val;
                                    _selectedDistrict = 'All';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            // District Dropdown
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedDistrict ?? 'All',
                                decoration: const InputDecoration(
                                  labelText: 'District',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(value: 'All', child: Text('All Districts')),
                                  ...IndiaDistricts.getDistricts(_selectedState == 'All' ? null : _selectedState)
                                      .map((d) => DropdownMenuItem(value: d, child: Text(d))),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedDistrict = val;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Key National Metrics
                const Text(
                  'National Performance KPIs',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                ),
                const SizedBox(height: 10),

                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: [
                    _buildMetricCard(
                      label: 'Total Complaints',
                      value: '$totalReports',
                      icon: Icons.assignment_outlined,
                      color: AppTheme.primaryBlue,
                    ),
                    _buildMetricCard(
                      label: 'Active Issues',
                      value: '$activeCount',
                      icon: Icons.pending_actions_rounded,
                      color: AppTheme.warningOrange,
                    ),
                    _buildMetricCard(
                      label: 'Repairs In Progress',
                      value: '$inProgressCount',
                      icon: Icons.build_circle_outlined,
                      color: Colors.purple,
                    ),
                    _buildMetricCard(
                      label: 'Resolved & Closed',
                      value: '$completedCount ($resolutionRate%)',
                      icon: Icons.verified_rounded,
                      color: AppTheme.successGreen,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Emergency Banner Card
                if (emergencyCount > 0)
                  Card(
                    color: AppTheme.emergencyRed.withOpacity(0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.emergencyRed, width: 1.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppTheme.emergencyRed, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$emergencyCount Emergency Hazards Requiring Immediate Action',
                                  style: const TextStyle(
                                    color: AppTheme.emergencyRed,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const Text(
                                  'High risk road craters, deep cave-ins, and severe water logging.',
                                  style: TextStyle(color: Colors.black87, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              if (widget.onNavigateTab != null) {
                                widget.onNavigateTab!(1); // Go to complaints tab
                              }
                            },
                            child: const Text('View', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // Quick Management Shortcuts
                const Text(
                  'Administrative Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _buildActionTile(
                        icon: Icons.people_outline_rounded,
                        title: 'Community Users',
                        subtitle: 'Assign & manage district teams',
                        color: Colors.blue.shade700,
                        onTap: () {
                          if (widget.onNavigateTab != null) widget.onNavigateTab!(2);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionTile(
                        icon: Icons.handyman_rounded,
                        title: 'Repair Crews',
                        subtitle: 'Manage local repair squads',
                        color: Colors.teal.shade700,
                        onTap: () {
                          if (widget.onNavigateTab != null) widget.onNavigateTab!(3);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // District Breakdown Section
                const Text(
                  'Complaints by District Breakdown',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                ),
                const SizedBox(height: 10),

                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: complaintProv.complaintsCountByDistrict.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No complaints registered across districts yet.'),
                            ),
                          )
                        : Column(
                            children: complaintProv.complaintsCountByDistrict.entries.map((entry) {
                              final count = entry.value;
                              final ratio = totalReports > 0 ? (count / totalReports) : 0.0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        Text('$count issues', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: ratio,
                                        minHeight: 6,
                                        backgroundColor: Colors.grey.shade200,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          count > 5 ? AppTheme.emergencyRed : AppTheme.primaryBlue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                Icon(icon, color: color, size: 22),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

