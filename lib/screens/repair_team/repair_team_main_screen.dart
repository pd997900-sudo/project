import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/complaint_model.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../community/work_progress_screen.dart';
import '../community/work_completion_screen.dart';
import '../auth/sign_in_screen.dart';

class RepairTeamMainScreen extends StatefulWidget {
  const RepairTeamMainScreen({super.key});

  @override
  State<RepairTeamMainScreen> createState() => _RepairTeamMainScreenState();
}

class _RepairTeamMainScreenState extends State<RepairTeamMainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProv = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final user = authProv.currentUser;

    final userDistrict = authProv.userDistrict;
    final userState = authProv.userState;
    final repairTeamId = user?.repairTeamId;

    // Filter tasks assigned to this repair team, or in this district if repairTeamId is null/generic
    final allAssignedTasks = complaintProv.complaints.where((c) {
      if (repairTeamId != null && repairTeamId.isNotEmpty) {
        if (c.repairTeamId == repairTeamId) return true;
      }
      // Match by district if complaint is assigned to any crew or accepted/in-progress in this district
      final matchesDistrict = c.districtDisplay.trim().toLowerCase() == userDistrict.trim().toLowerCase() ||
          c.address.toLowerCase().contains(userDistrict.toLowerCase());
      final isRepairActive = c.status == 'Accepted' || c.status == 'In Progress' || c.status == 'Completed';
      return matchesDistrict && isRepairActive;
    }).toList();

    final pendingTasks = allAssignedTasks.where((c) => c.status == 'Accepted' || c.status == 'Verified').toList();
    final inProgressTasks = allAssignedTasks.where((c) => c.status == 'In Progress').toList();
    final completedTasks = allAssignedTasks.where((c) => c.status == 'Completed').toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Repair Crew Portal',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
            Text(
              '📍 $userDistrict, $userState',
              style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        backgroundColor: Colors.teal.shade800,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Tasks',
            onPressed: () => complaintProv.refreshComplaints(),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sign Out',
            onPressed: () => _confirmSignOut(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.amberAccent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: 'All (${allAssignedTasks.length})'),
            Tab(text: 'Assigned (${pendingTasks.length})'),
            Tab(text: 'In Progress (${inProgressTasks.length})'),
            Tab(text: 'Completed (${completedTasks.length})'),
          ],
        ),
      ),
      body: Container(
        color: Colors.grey.shade100,
        child: Column(
          children: [
            // Crew Info Banner
            _buildCrewBanner(context, user, userDistrict, userState),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTaskList(context, allAssignedTasks, 'No repair tasks assigned to this crew yet.'),
                  _buildTaskList(context, pendingTasks, 'No pending tasks waiting to be started.'),
                  _buildTaskList(context, inProgressTasks, 'No tasks currently in progress.'),
                  _buildTaskList(context, completedTasks, 'No completed repair tasks yet.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrewBanner(BuildContext context, dynamic user, String district, String state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.teal.shade900,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.amber.shade400,
            child: const Icon(Icons.handyman_rounded, color: Colors.black87, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.name ?? 'District Repair Crew',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'Jurisdiction: $district District, $state',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white30),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 12, color: Colors.amberAccent),
                SizedBox(width: 4),
                Text('Local Crew', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, List<Complaint> tasks, String emptyMessage) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => Provider.of<ComplaintProvider>(context, listen: false).refreshComplaints(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (ctx, idx) => _buildTaskCard(context, tasks[idx]),
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, Complaint complaint) {
    final statusColor = _getStatusColor(complaint.status);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header stripe
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: statusColor.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        complaint.status.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      complaint.category,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  'Severity: ${complaint.severity}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: complaint.severity == 'High' ? AppTheme.emergencyRed : Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complaint.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: Colors.blue),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        complaint.address,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // District & Crew Tag
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        '📍 ${complaint.districtDisplay}, ${complaint.stateDisplay}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
                      ),
                    ),
                    if (complaint.repairTeamName != null && complaint.repairTeamName!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Text(
                            'Crew: ${complaint.repairTeamName}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal.shade900),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                // Progress Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Work Progress', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        Text('${complaint.progressPercentage.toInt()}%',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (complaint.progressPercentage / 100).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          complaint.progressPercentage >= 100 ? Colors.green : Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Action Buttons for Repair Team
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                        label: const Text('Update Progress', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade800,
                          side: BorderSide(color: Colors.teal.shade800),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkProgressScreen(complaint: complaint),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Mark Complete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkCompletionScreen(complaint: complaint),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in progress':
        return Colors.blue;
      case 'accepted':
      case 'verified':
        return Colors.orange;
      case 'rejected':
      case 'fake':
        return Colors.red;
      default:
        return Colors.grey.shade700;
    }
  }

  void _confirmSignOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('Are you sure you want to sign out of the Repair Crew Portal?'),
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
      await Provider.of<AuthProvider>(context, listen: false).signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignInScreen()),
          (route) => false,
        );
      }
    }
  }
}
