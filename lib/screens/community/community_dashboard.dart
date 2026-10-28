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
import 'complaint_verification_screen.dart';
import '../reporter/notifications_screen.dart';

class CommunityDashboard extends StatefulWidget {
  final Function(int index)? onNavigateTab;
  final bool isActiveTab;

  const CommunityDashboard({super.key, this.onNavigateTab, this.isActiveTab = true});

  @override
  State<CommunityDashboard> createState() => _CommunityDashboardState();
}

class _CommunityDashboardState extends State<CommunityDashboard> {
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
  void didUpdateWidget(CommunityDashboard oldWidget) {
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
          width: 65,
          height: 65,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
        );
      } catch (_) {
        return _buildFallbackThumbnail();
      }
    } else if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:')) {
      return Image.network(
        url,
        width: 65,
        height: 65,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
      );
    }
    return _buildFallbackThumbnail();
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: 65,
      height: 65,
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
    final auth = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final user = auth.currentUser;

    final userDistrict = auth.userDistrict;
    final userState = auth.userState;
    final districtComplaints = complaintProv.complaintsForDistrict(userDistrict, userState);

    final total = districtComplaints.length;
    final emergency = districtComplaints.where((c) => c.isEmergency && c.status != 'Completed' && c.status != 'Rejected').length;
    final accepted = districtComplaints.where((c) => c.status == 'Accepted' || c.status == 'Work Started' || c.status == 'Repair In Progress').length;
    final completed = districtComplaints.where((c) => c.status == 'Completed').length;

    final urgentItems = districtComplaints.where((c) => c.isEmergency && c.status != 'Completed' && c.status != 'Rejected').toList();

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
              // Header
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
                            if (widget.onNavigateTab != null) widget.onNavigateTab!(3); // Navigate to profile
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (user != null && user.hasValidName) ? 'Team ${user.name} 🛠️' : 'Volunteer Crew 🛠️',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Text(
                                'Community & Repair Portal',
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                    },
                    icon: Stack(
                      children: [
                        const Icon(Icons.notifications_active_outlined, size: 28, color: AppTheme.primaryDark),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppTheme.emergencyRed,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Assigned District Jurisdiction Banner
              Container(
                margin: const EdgeInsets.only(top: 16, bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF0F172A), Colors.blue.shade900],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.location_on_rounded, color: Colors.amberAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ASSIGNED JURISDICTION',
                            style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$userDistrict District, $userState',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$total in District',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Emergency Dispatch Banner
              if (emergency > 0)
                GlassCard(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(18),
                  backgroundColor: AppTheme.emergencyRed,
                  opacity: 0.95,
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.white),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$emergency Emergency Repair Request${emergency > 1 ? "s" : ""}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Requires immediate inspection & safety response.',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          if (widget.onNavigateTab != null) widget.onNavigateTab!(1); // Go to Complaints Feed
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.emergencyRed,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Inspect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // 4 Key Analytics Cards Grid
              const Text(
                'Work & Operations Analytics',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      onTap: () {
                        complaintProv.setFilter('All');
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(1);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.folder_copy, color: AppTheme.primaryBlue, size: 22),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          ),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Total Complaints', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      onTap: () {
                        complaintProv.setFilter('Emergency');
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(1);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.emergency, color: AppTheme.emergencyRed, size: 22),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('$emergency', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.emergencyRed)),
                          ),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Emergency', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      onTap: () {
                        complaintProv.setFilter('Accepted');
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(1);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.handshake_rounded, color: AppTheme.warningOrange, size: 22),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('$accepted', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.warningOrange)),
                          ),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Accepted Works', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      onTap: () {
                        complaintProv.setFilter('Completed');
                        if (widget.onNavigateTab != null) widget.onNavigateTab!(1);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.task_alt_rounded, color: AppTheme.successGreen, size: 22),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('$completed', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.successGreen)),
                          ),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Completed Works', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Interactive City Map for Crew Dispatch
              const Text(
                'Community Inspection Map',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 12),
              MapViewWidget(
                key: const ValueKey('community_live_incident_map'),
                initialLat: complaintProv.activeComplaints.isNotEmpty
                    ? complaintProv.activeComplaints.first.latitude
                    : 13.0298,
                initialLng: complaintProv.activeComplaints.isNotEmpty
                    ? complaintProv.activeComplaints.first.longitude
                    : 80.0168,
                complaints: complaintProv.activeComplaints,
                onlyActive: true,
                isVisible: widget.isActiveTab,
                onComplaintTap: (complaint) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComplaintVerificationScreen(complaint: complaint),
                    ),
                  ).then((_) => _refreshComplaints());
                },
              ),

              const SizedBox(height: 24),

              // Urgent Dispatch Feed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Urgent Priority Tasks',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  TextButton(
                    onPressed: () {
                      if (widget.onNavigateTab != null) widget.onNavigateTab!(1); // Go to Complaints Feed
                    },
                    child: const Text('View Feed'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ...urgentItems.take(2).map((c) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  borderRadius: 18,
                  padding: const EdgeInsets.all(14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ComplaintVerificationScreen(complaint: c),
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
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
