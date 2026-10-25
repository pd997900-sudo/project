import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/map_view_widget.dart';
import '../../widgets/profile_avatar_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import 'complaint_tracking_screen.dart';

class ReporterDashboard extends StatefulWidget {
  final Function(int index, {String? initialTab})? onNavigateTab;
  final bool isActiveTab;

  const ReporterDashboard({super.key, this.onNavigateTab, this.isActiveTab = true});

  @override
  State<ReporterDashboard> createState() => _ReporterDashboardState();
}

class _ReporterDashboardState extends State<ReporterDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ComplaintProvider>().refreshComplaints();
      }
    });
  }

  @override
  void didUpdateWidget(ReporterDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActiveTab && !oldWidget.isActiveTab) {
      context.read<ComplaintProvider>().refreshComplaints();
    }
  }

  Widget _buildDamageImage(String? rawUrl) {
    final url = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : '';
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
        );
      } catch (_) {
        return _buildFallbackThumbnail();
      }
    } else if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:')) {
      return Image.network(
        url,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
      );
    }
    return _buildFallbackThumbnail();
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: 60,
      height: 60,
      color: Colors.blue.shade100,
      child: const Icon(Icons.add_road_rounded, color: Colors.blue),
    );
  }

  void _refreshComplaints() {
    if (mounted) {
      context.read<ComplaintProvider>().refreshComplaints();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final complaintProvider = Provider.of<ComplaintProvider>(context);
    final user = authProvider.currentUser;

    final total = complaintProvider.totalCount;
    final pending = complaintProvider.pendingCount;
    final completed = complaintProvider.completedCount;
    final recentComplaints = complaintProvider.complaints.take(3).toList();

    return Container(
      decoration: AppTheme.mainScreenBackground,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => context.read<ComplaintProvider>().refreshComplaints(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Top Bar Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        ProfileAvatarWidget(
                          avatarUrl: user?.avatarUrl,
                          radius: 22,
                          onTap: () {
                            if (widget.onNavigateTab != null) widget.onNavigateTab!(4);
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (user != null && user.hasValidName) ? 'Hello, ${user.name} 👋' : 'Hello, Citizen 👋',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Text(
                                'Reporter Dashboard',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      if (widget.onNavigateTab != null) widget.onNavigateTab!(3); // Go to Notifications
                    },
                    icon: Stack(
                      children: [
                        const Icon(Icons.notifications_outlined, size: 28, color: AppTheme.primaryDark),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppTheme.emergencyRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Hero Banner - Quick Action Report Damage
              GlassCard(
                borderRadius: 24,
                padding: const EdgeInsets.all(20),
                backgroundColor: AppTheme.primaryDark,
                opacity: 0.95,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Spotted Road Damage?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Report potholes, damaged roads, or drainage issues in under 60 seconds.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (widget.onNavigateTab != null) widget.onNavigateTab!(1); // Go to Report Issue
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.primaryDark,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.add_a_photo, size: 18),
                            label: const Text('Report New Damage', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.warning_amber_rounded, size: 70, color: Colors.white24),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Complaint Summary Statistics Grid Cards
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: InkWell(
                      onTap: () {
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(2, initialTab: 'All'); // Go to Tracking screen
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Complaint Overview',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.primaryBlue),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (widget.onNavigateTab != null) widget.onNavigateTab!(2, initialTab: 'All'); // Go to Tracking screen
                    },
                    child: const Text('View All', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(2, initialTab: 'All');
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.assignment, color: AppTheme.primaryBlue, size: 24),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '$total',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('Total Submitted', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(2, initialTab: 'Pending');
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.hourglass_top_rounded, color: AppTheme.warningOrange, size: 24),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '$pending',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.warningOrange),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('Pending Work', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(2, initialTab: 'Completed');
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 24),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '$completed',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('Repaired', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Interactive City Map View displaying locations
              const Text(
                'Live Incident Map',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              MapViewWidget(
                key: const ValueKey('reporter_live_incident_map'),
                initialLat: complaintProvider.activeComplaints.isNotEmpty
                    ? complaintProvider.activeComplaints.first.latitude
                    : 13.0298,
                initialLng: complaintProvider.activeComplaints.isNotEmpty
                    ? complaintProvider.activeComplaints.first.longitude
                    : 80.0168,
                complaints: complaintProvider.activeComplaints,
                onlyActive: true,
                isVisible: widget.isActiveTab,
                onComplaintTap: (complaint) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComplaintTrackingScreen(
                        complaint: complaint,
                        complaintId: complaint.complaintId,
                      ),
                    ),
                  ).then((_) => _refreshComplaints());
                },
              ),

              const SizedBox(height: 24),

              // Recent Complaints Activity Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (widget.onNavigateTab != null) widget.onNavigateTab!(2); // Go to Complaint History
                    },
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              ...recentComplaints.map((c) => Container(
                key: ValueKey(c.complaintId),
                margin: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ComplaintTrackingScreen(
                          complaint: c,
                          complaintId: c.complaintId,
                        ),
                      ),
                    ).then((_) => _refreshComplaints());
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildDamageImage(c.imageUrl),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    c.complaintId,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryDark,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SeverityBadge(severity: c.severity),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            StatusBadge(status: c.status),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
