import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/complaint_model.dart';
import '../../models/repair_team_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/map_view_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/community_verification_poll_card.dart';
import '../chat/complaint_chat_screen.dart';
import 'work_progress_screen.dart';
import '../../services/supabase_service.dart';

class ComplaintVerificationScreen extends StatefulWidget {
  final Complaint complaint;

  const ComplaintVerificationScreen({super.key, required this.complaint});

  @override
  State<ComplaintVerificationScreen> createState() => _ComplaintVerificationScreenState();
}

class _ComplaintVerificationScreenState extends State<ComplaintVerificationScreen> {
  bool _isVerifying = false;
  bool _isMarkingFake = false;
  bool _isAccepting = false;
  FeedbackModel? _remoteFeedback;
  List<FeedbackModel> _remoteFeedbacks = [];
  String? _resolvedReporterName;

  @override
  void initState() {
    super.initState();
    _loadFeedbackAndReporter();
  }

  @override
  void didUpdateWidget(ComplaintVerificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.complaint.complaintId != widget.complaint.complaintId) {
      _resolvedReporterName = null;
      _remoteFeedback = null;
      _remoteFeedbacks = [];
      _loadFeedbackAndReporter();
    }
  }

  Future<void> _loadFeedbackAndReporter() async {
    if (!mounted) return;

    try {
      final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
      final currentComplaint = complaintProv.complaints.firstWhere(
        (c) => c.complaintId.trim().toLowerCase() == widget.complaint.complaintId.trim().toLowerCase(),
        orElse: () => widget.complaint,
      );

      FeedbackModel? feedback = currentComplaint.feedback ?? widget.complaint.feedback;
      if (_remoteFeedbacks.isEmpty && currentComplaint.allFeedbacks.isNotEmpty) {
        _remoteFeedbacks = List.from(currentComplaint.allFeedbacks);
      }
      if (_remoteFeedback == null && feedback != null) {
        _remoteFeedback = feedback;
      }

      // 1. Fetch all public.complaint_feedback from Supabase if connected
      if (SupabaseService.isConnected) {
        final remoteRows = await SupabaseService.getComplaintFeedbacks(currentComplaint.complaintId);
        if (remoteRows.isNotEmpty) {
          final parsedList = remoteRows.map((r) => FeedbackModel.fromJson(r)).toList();
          feedback = parsedList.first;
          if (mounted) {
            setState(() {
              _remoteFeedback = feedback;
              _remoteFeedbacks = parsedList;
            });
            complaintProv.setComplaintFeedbacks(currentComplaint.complaintId, parsedList);
          }
        } else {
          final remoteRow = await SupabaseService.getComplaintFeedback(currentComplaint.complaintId);
          if (remoteRow != null) {
            final parsed = FeedbackModel.fromJson(remoteRow);
            feedback = parsed;
            if (mounted) {
              setState(() {
                _remoteFeedback = parsed;
                _remoteFeedbacks = [parsed];
              });
              complaintProv.setComplaintFeedback(currentComplaint.complaintId, parsed);
            }
          }
        }
      }

      // 2. Identify the reporter ID from the feedback record or complaint
      // Correctly matches IDs without assuming complaint ID and reporter ID are interchangeable
      final effectiveReporterId = (feedback != null &&
              feedback.reporterId.trim().isNotEmpty &&
              feedback.reporterId.trim() != 'anon_user_1')
          ? feedback.reporterId.trim()
          : (currentComplaint.reporterId.trim().isNotEmpty &&
                  currentComplaint.reporterId.trim() != 'anon_user_1'
              ? currentComplaint.reporterId.trim()
              : '');

      String? reporterName;

      // 3. Fetch name from existing Supabase public.user_profiles table using reporter user ID
      if (effectiveReporterId.isNotEmpty && SupabaseService.isConnected) {
        // Reuse project's established profile lookup service
        final namesMap = await SupabaseService.fetchUserFullNames([effectiveReporterId]);
        reporterName = namesMap[effectiveReporterId.toLowerCase()];

        // Direct user_profiles query fallback if not in batch map
        if ((reporterName == null || reporterName.isEmpty) && SupabaseService.isUserProfilesAvailable) {
          try {
            final profileRow = await SupabaseService.client!
                .from('user_profiles')
                .select('full_name')
                .eq('user_id', effectiveReporterId)
                .maybeSingle();
            if (profileRow != null && profileRow['full_name'] != null) {
              final fn = profileRow['full_name'].toString().trim();
              if (fn.isNotEmpty &&
                  !fn.contains('@') &&
                  fn != 'Citizen User' &&
                  fn != 'Registered User' &&
                  fn != 'Citizen Reporter' &&
                  fn != 'Name not available' &&
                  fn != 'Reporter name unavailable') {
                reporterName = fn;
              }
            }
          } catch (e) {
            debugPrint('Notice querying user_profiles in verification screen: $e');
          }
        }
      }

      // 4. Secondary fallback: check feedback.reporterName or complaint.reporterName if valid and not email
      if (reporterName == null || reporterName.isEmpty) {
        final candidateNames = [
          feedback?.reporterName,
          currentComplaint.reporterName,
          widget.complaint.reporterName,
        ];
        for (var cn in candidateNames) {
          final clean = cn?.trim() ?? '';
          if (clean.isNotEmpty &&
              !clean.contains('@') &&
              clean != 'Citizen User' &&
              clean != 'Registered User' &&
              clean != 'Citizen Reporter' &&
              clean != 'Name not available' &&
              clean != 'Reporter name unavailable' &&
              clean != 'Reporter') {
            reporterName = clean;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _resolvedReporterName = (reporterName != null && reporterName.isNotEmpty) ? reporterName : 'Reporter';
        });
      }
    } catch (e) {
      debugPrint('Notice loading feedback reporter: $e');
    }
  }

  Widget _buildDamageImage(String? rawUrl, {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    final url = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : '';
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildFallbackBox(height, width),
        );
      } catch (_) {
        return _buildFallbackBox(height, width);
      }
    } else if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:')) {
      return Image.network(
        url,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildFallbackBox(height, width),
      );
    }
    return _buildFallbackBox(height, width);
  }

  Widget _buildFallbackBox(double? height, double? width) {
    return Container(
      height: height,
      width: width,
      color: Colors.blue.shade100,
      child: const Icon(Icons.add_road_rounded, color: Colors.blue, size: 40),
    );
  }

  void _showUnauthorizedDistrictAlert(BuildContext context, String userDistrict, String complaintDistrict) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppTheme.emergencyRed),
            SizedBox(width: 8),
            Text('District Restriction', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'This complaint belongs to $complaintDistrict District.\n\nYour account is assigned to $userDistrict District. You can only verify, vote on, or update repair progress for complaints within your assigned jurisdiction.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  void _showAssignRepairTeamDialog(BuildContext context, Complaint complaint) async {
    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final teams = await complaintProv.fetchRepairTeams(
      state: complaint.stateDisplay,
      district: complaint.districtDisplay,
    );

    if (!mounted) return;

    if (teams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No active repair teams found for ${complaint.districtDisplay}. Please contact your Administrator.'),
          backgroundColor: AppTheme.warningOrange,
        ),
      );
      return;
    }

    RepairTeam selectedTeam = teams.first;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.handyman_rounded, color: AppTheme.primaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Assign Repair Team (${complaint.complaintId})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigning complaint to local crew in ${complaint.districtDisplay}:',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<RepairTeam>(
                  value: selectedTeam,
                  decoration: const InputDecoration(labelText: 'Select Repair Team'),
                  isExpanded: true,
                  items: teams
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text('${t.name} (${t.specialization})', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        selectedTeam = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lead: ${selectedTeam.leadName.isNotEmpty ? selectedTeam.leadName : "N/A"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      if (selectedTeam.contactPhone.isNotEmpty)
                        Text('Phone: ${selectedTeam.contactPhone}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryDark),
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  final success = await complaintProv.assignComplaintToRepairTeam(
                    complaintId: complaint.complaintId,
                    repairTeamId: selectedTeam.id,
                    repairTeamName: selectedTeam.name,
                    assignedByUserId: authProv.currentUser?.id ?? 'community_lead',
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Assigned to ${selectedTeam.name}!' : 'Failed to assign repair team'),
                        backgroundColor: success ? AppTheme.successGreen : AppTheme.emergencyRed,
                      ),
                    );
                  }
                },
                child: const Text('Confirm Assignment', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);

    final complaint = complaintProv.complaints.firstWhere(
      (c) => c.complaintId.trim().toLowerCase() == widget.complaint.complaintId.trim().toLowerCase(),
      orElse: () => widget.complaint,
    );

    final activeFeedback = _remoteFeedback ?? complaint.feedback ?? widget.complaint.feedback;
    final activeFeedbacks = <FeedbackModel>[];
    if (_remoteFeedbacks.isNotEmpty) {
      activeFeedbacks.addAll(_remoteFeedbacks);
    } else if (complaint.allFeedbacks.isNotEmpty) {
      activeFeedbacks.addAll(complaint.allFeedbacks);
    } else if (activeFeedback != null) {
      activeFeedbacks.add(activeFeedback);
    }

    // Determine reporter display name:
    // Uses resolved name from public.user_profiles, or valid cached name, or "Reporter" fallback.
    // Never exposes email addresses.
    String displayReporterName = _resolvedReporterName ?? 'Reporter';
    if (_resolvedReporterName == null) {
      final immediate = (activeFeedback?.reporterName?.trim().isNotEmpty == true && !activeFeedback!.reporterName!.contains('@'))
          ? activeFeedback.reporterName!.trim()
          : (complaint.reporterName.trim().isNotEmpty && !complaint.reporterName.contains('@') && complaint.reporterName != 'Reporter name unavailable'
              ? complaint.reporterName.trim()
              : 'Reporter');
      if (immediate != 'Citizen User' &&
          immediate != 'Registered User' &&
          immediate != 'Citizen Reporter' &&
          immediate != 'Name not available') {
        displayReporterName = immediate;
      }
    }

    final isAcceptedOrInProgress = complaint.status == 'Accepted' ||
        complaint.status == 'Work Started' ||
        complaint.status == 'Repair In Progress';

    final userRole = (auth.currentUser?.role ?? auth.selectedRole).toLowerCase();
    final isAdmin = userRole == 'admin' || auth.isAdmin;
    final userDistrict = auth.userDistrict.trim().toLowerCase();
    final complaintDistrict = complaint.districtDisplay.trim().toLowerCase();

    // Check district authorization
    final isAuthorizedDistrict = isAdmin ||
        userDistrict.isEmpty ||
        complaintDistrict.isEmpty ||
        complaintDistrict == userDistrict ||
        complaint.address.toLowerCase().contains(userDistrict);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Verification: ${complaint.complaintId}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        actions: [
          Builder(
            builder: (ctx) {
              final chatProv = Provider.of<ChatProvider>(ctx);
              final authProv = Provider.of<AuthProvider>(ctx, listen: false);
              final unread = chatProv.getUnreadCountForComplaint(complaint.complaintId, authProv.selectedRole);

              return IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded),
                    if (unread > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppTheme.emergencyRed,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                          child: Text(
                            '$unread',
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Chat with Reporter',
                onPressed: () {
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => ComplaintChatScreen(complaint: complaint),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // District Notice Banner (if out-of-district) or Jurisdiction Tag
              if (!isAuthorizedDistrict)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade300, width: 1.2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFB45309), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Out-of-District Complaint (Read-Only Mode)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF78350F)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'This complaint belongs to ${complaint.districtDisplay} (${complaint.stateDisplay}). Your account is assigned to ${auth.userDistrict}. Only authorized Community Users of ${complaint.districtDisplay} or India-Level Admins can verify or update this report.',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text(
                        'Jurisdiction: ${complaint.districtDisplay}, ${complaint.stateDisplay}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                      ),
                    ],
                  ),
                ),

              // Photo Header Card
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _buildDamageImage(
                  complaint.imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

              const SizedBox(height: 18),

              // Overview Glass Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            complaint.complaintId,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SeverityBadge(severity: complaint.severity),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      complaint.title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    StatusBadge(status: complaint.status),
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Reporter Details
                    Row(
                      children: [
                        const Icon(Icons.person, color: AppTheme.primaryBlue, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reported by: ${complaint.reporterName}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Community Verification Poll Section (Voting disabled in Community Portal — Summary only)
              CommunityVerificationPollCard(complaint: complaint, allowVoting: false),

              const SizedBox(height: 20),

              // Location Map Pin Container
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.location_on, color: AppTheme.emergencyRed, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Damage Location Coordinates',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      complaint.address.trim().isNotEmpty
                          ? complaint.address.trim()
                          : 'Location unavailable',
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    if (Complaint.isValidCoordinates(complaint.latitude, complaint.longitude))
                      MapViewWidget(
                        initialLat: complaint.latitude,
                        initialLng: complaint.longitude,
                        initialAddress: complaint.address,
                        complaints: [complaint],
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off_rounded, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            const Text(
                              'Location unavailable for this complaint',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Valid GPS coordinates were not recorded for this report.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Description Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reported Description',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      complaint.description.isEmpty
                          ? 'No detailed description provided by citizen.'
                          : complaint.description,
                      style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Message Reporter Button for Community Team
              Builder(
                builder: (ctx) {
                  final chatProv = Provider.of<ChatProvider>(ctx);
                  final authProv = Provider.of<AuthProvider>(ctx, listen: false);
                  final unread = chatProv.getUnreadCountForComplaint(complaint.complaintId, authProv.selectedRole);

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => ComplaintChatScreen(complaint: complaint),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_rounded, size: 20),
                      label: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '💬 Message Reporter',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$unread New',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              // Action Buttons & Status Banners Container
              if (complaint.status == 'Completed' || activeFeedback != null) ...[
                GlassCard(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(20),
                  backgroundColor: AppTheme.successGreen.withOpacity(0.08),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 28),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Repair Work 100% Completed & Inspected',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.successGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (complaint.completionNotes != null && complaint.completionNotes!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Completion & Inspection Summary:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          complaint.completionNotes!,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                      if (complaint.afterImageUrl != null && complaint.afterImageUrl!.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Completed After-Repair Site Photo:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _buildDamageImage(
                            complaint.afterImageUrl,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // Reporter Rating & Quality Feedback Card(s)
                if (activeFeedbacks.isNotEmpty) ...[
                  for (int fIndex = 0; fIndex < activeFeedbacks.length; fIndex++) ...[
                    if (fIndex > 0) const SizedBox(height: 14),
                    _buildFeedbackCard(
                      feedback: activeFeedbacks[fIndex],
                      complaint: complaint,
                      defaultReporterName: displayReporterName,
                      feedbackNumber: activeFeedbacks.length > 1 ? fIndex + 1 : null,
                      totalFeedbacks: activeFeedbacks.length,
                    ),
                  ],
                ] else ...[
                  // Unrated status card when complaint is completed but no reporter feedback has been submitted yet
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300, width: 1.2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.rate_review_outlined, color: Colors.blueGrey.shade700, size: 24),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reporter Rating & Feedback',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppTheme.primaryDark,
                                    ),
                                  ),
                                  Text(
                                    'Awaiting reporter evaluation',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  Icons.star_outline_rounded,
                                  color: Colors.grey.shade400,
                                  size: 26,
                                );
                              }),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Not Yet Rated',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey.shade500),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Repair marked completed. Awaiting reporter feedback submission.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade700,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else if (complaint.isRejected) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.emergencyRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.4), width: 1.2),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.block_rounded, color: AppTheme.emergencyRed, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Complaint Rejected as Fake Issue',
                              style: TextStyle(
                                color: AppTheme.emergencyRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'This complaint was rejected as fake by the community. Voting is closed.',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isAcceptedOrInProgress) ...[
                // STEP 3: Repair Work Accepted / In Progress -> Show "Update Work Progress & Upload Photos" Button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00E676), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_rounded, color: Color(0xFF1B5E20), size: 26),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Community Verified — Repair Work Accepted',
                              style: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Repair work has been accepted and is currently in progress.',
                              style: TextStyle(color: Color(0xFF1B5E20), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!isAuthorizedDistrict) {
                        _showUnauthorizedDistrictAlert(context, auth.userDistrict, complaint.districtDisplay);
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkProgressScreen(complaint: complaint),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.build_circle_rounded, color: Colors.white),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Update Work Progress & Upload Photos',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!isAuthorizedDistrict) {
                        _showUnauthorizedDistrictAlert(context, auth.userDistrict, complaint.districtDisplay);
                        return;
                      }
                      _showAssignRepairTeamDialog(context, complaint);
                    },
                    icon: const Icon(Icons.handyman_rounded, size: 18),
                    label: Text(
                      complaint.repairTeamName != null && complaint.repairTeamName!.isNotEmpty
                          ? 'Assigned Crew: ${complaint.repairTeamName} (Change)'
                          : 'Assign to Local Repair Crew',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal.shade800,
                      side: BorderSide(color: Colors.teal.shade800),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ] else if (complaint.status == 'Verified') ...[
                // STEP 2: Verified Status -> Show "Accept Repair Work" Button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF00E676), width: 1.2),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_rounded, color: Color(0xFF1B5E20), size: 26),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Community Verified — Genuine Issue',
                              style: TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Inspected and verified by community members as a genuine issue.',
                              style: TextStyle(color: Color(0xFF1B5E20), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (!isAuthorizedDistrict) {
                        _showUnauthorizedDistrictAlert(context, auth.userDistrict, complaint.districtDisplay);
                        return;
                      }
                      if (_isVerifying || _isMarkingFake || _isAccepting || complaint.isRejected) return;

                      final messenger = ScaffoldMessenger.of(context);

                      setState(() {
                        _isAccepting = true;
                      });

                      try {
                        final userId = auth.currentUser?.id ?? 'comm_user_1';
                        final userName = auth.currentUser?.name ?? 'Volunteer Repair Crew';

                        final result = await complaintProv.acceptComplaint(complaint.complaintId, userId, userName);

                        if (mounted) {
                          if (result.success) {
                            messenger.clearSnackBars();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Repair work accepted successfully!'),
                                backgroundColor: AppTheme.successGreen,
                                duration: Duration(seconds: 3),
                              ),
                            );
                          } else {
                            final msg = result.errorMessage != null && result.errorMessage!.isNotEmpty
                                ? 'Failed to accept repair work: ${result.errorMessage}'
                                : 'Failed to accept repair work. Database update error.';
                            messenger.clearSnackBars();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                backgroundColor: AppTheme.emergencyRed,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        }
                      } catch (e, stack) {
                        debugPrint('❌ Error accepting complaint: $e\n$stack');
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isAccepting = false;
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                    icon: _isAccepting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.handshake_rounded, color: Colors.white),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Accept Repair Work',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!isAuthorizedDistrict) {
                        _showUnauthorizedDistrictAlert(context, auth.userDistrict, complaint.districtDisplay);
                        return;
                      }
                      _showAssignRepairTeamDialog(context, complaint);
                    },
                    icon: const Icon(Icons.handyman_rounded, size: 18),
                    label: Text(
                      complaint.repairTeamName != null && complaint.repairTeamName!.isNotEmpty
                          ? 'Assigned Crew: ${complaint.repairTeamName} (Change)'
                          : 'Assign to Local Repair Crew',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ] else ...[
                // STEP 1: Unverified (Submitted / Under Verification) -> Show "Verify" & "Mark Fake" Buttons
                Row(
                  children: [
                    // Verify Complaint Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (!isAuthorizedDistrict) {
                            _showUnauthorizedDistrictAlert(context, auth.userDistrict, complaint.districtDisplay);
                            return;
                          }
                          final stopwatch = Stopwatch()..start();
                          final currentUserId = auth.currentUser?.id ?? 'anon_community_user';

                          debugPrint('========================================');
                          debugPrint('🔍 [DIAGNOSTIC] VERIFY BUTTON CLICKED');
                          debugPrint('Complaint ID: "${complaint.complaintId}"');
                          debugPrint('Title: "${complaint.title}"');
                          debugPrint('Current Status: "${complaint.status}"');
                          debugPrint('Auth User ID: "$currentUserId"');
                          debugPrint('========================================');

                          if (_isVerifying || _isMarkingFake || _isAccepting) return;

                          final messenger = ScaffoldMessenger.of(context);
                          messenger.clearSnackBars();

                          setState(() {
                            _isVerifying = true;
                          });

                          try {
                            final userId = auth.currentUser?.id ?? 'comm_user_1';
                            final userName = auth.currentUser?.name ?? 'Community Inspector';
                            final result = await complaintProv.verifyComplaint(complaint.complaintId, userId, userName);
                            stopwatch.stop();
                            debugPrint('⏱️ [DIAGNOSTIC] verifyComplaint completed in ${stopwatch.elapsedMilliseconds}ms with success=${result.success}');

                            if (mounted) {
                              if (result.success) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Successfully Verified!'),
                                    backgroundColor: AppTheme.successGreen,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              } else {
                                final msg = result.errorMessage != null && result.errorMessage!.isNotEmpty
                                    ? 'Failed to verify complaint: ${result.errorMessage}'
                                    : 'Failed to verify complaint in database. Please try again.';
                                debugPrint('❌ [DIAGNOSTIC] Verification failure SnackBar displayed: $msg');
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(msg),
                                    backgroundColor: AppTheme.emergencyRed,
                                    duration: const Duration(seconds: 6),
                                  ),
                                );
                              }
                            }
                          } catch (e, stack) {
                            stopwatch.stop();
                            debugPrint('❌ [DIAGNOSTIC] Exception verifying complaint after ${stopwatch.elapsedMilliseconds}ms: $e\n$stack');
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Error during verification: $e'),
                                  backgroundColor: AppTheme.emergencyRed,
                                  duration: const Duration(seconds: 6),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isVerifying = false;
                              });
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _isVerifying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.verified, size: 16),
                        label: Text(
                          _isVerifying ? 'Verifying...' : 'Verify',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Mark Fake Complaint Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (!isAuthorizedDistrict) {
                            _showUnauthorizedDistrictAlert(context, auth.userDistrict, complaint.districtDisplay);
                            return;
                          }
                          if (_isVerifying || _isMarkingFake || _isAccepting) return;

                          final messenger = ScaffoldMessenger.of(context);

                          setState(() {
                            _isMarkingFake = true;
                          });

                          try {
                            final result = await complaintProv.markFakeComplaint(complaint.complaintId);

                            if (mounted) {
                              if (result.success) {
                                messenger.clearSnackBars();
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Complaint marked as FAKE! Status = Rejected.'),
                                    backgroundColor: AppTheme.emergencyRed,
                                  ),
                                );
                              } else {
                                final msg = result.errorMessage != null && result.errorMessage!.isNotEmpty
                                    ? 'Failed to mark fake complaint: ${result.errorMessage}'
                                    : 'Failed to mark fake complaint in database. Please try again.';
                                messenger.clearSnackBars();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(msg),
                                    backgroundColor: AppTheme.emergencyRed,
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            }
                          } catch (e, stack) {
                            debugPrint('❌ Error marking fake complaint: $e\n$stack');
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isMarkingFake = false;
                              });
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.emergencyRed,
                          side: const BorderSide(color: AppTheme.emergencyRed),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _isMarkingFake
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emergencyRed),
                              )
                            : const Icon(Icons.cancel_outlined, size: 16),
                        label: Text(
                          _isMarkingFake ? 'Saving...' : 'Mark Fake',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackCard({
    required FeedbackModel feedback,
    required Complaint complaint,
    required String defaultReporterName,
    int? feedbackNumber,
    int totalFeedbacks = 1,
  }) {
    String fbReporterName = 'Reporter';
    if (feedback.reporterName != null &&
        feedback.reporterName!.trim().isNotEmpty &&
        !feedback.reporterName!.contains('@') &&
        feedback.reporterName != 'Citizen User' &&
        feedback.reporterName != 'Registered User' &&
        feedback.reporterName != 'Citizen Reporter' &&
        feedback.reporterName != 'Name not available' &&
        feedback.reporterName != 'Reporter name unavailable') {
      fbReporterName = feedback.reporterName!.trim();
    } else if (feedback.reporterId == complaint.reporterId && defaultReporterName.isNotEmpty) {
      fbReporterName = defaultReporterName;
    }

    final headerTitle = (feedbackNumber != null && totalFeedbacks > 1)
        ? 'Reporter Rating & Feedback #$feedbackNumber'
        : 'Reporter Rating & Feedback';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade300, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star_rounded, color: Colors.amber.shade800, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    Text(
                      'Submitted by: $fbReporterName',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d, yyyy • h:mm a').format(feedback.createdAt.toLocal()),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        if (feedback.updatedAt != null &&
                            feedback.updatedAt!.isAfter(feedback.createdAt.add(const Duration(seconds: 10)))) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(Edited)',
                            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blueGrey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.successGreen, width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 14, color: AppTheme.successGreen),
                    SizedBox(width: 4),
                    Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.successGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Row(
                children: List.generate(5, (index) {
                  final starVal = index + 1;
                  final rating = feedback.rating;
                  return Icon(
                    starVal <= rating
                        ? Icons.star_rounded
                        : (starVal - 0.5 <= rating
                            ? Icons.star_half_rounded
                            : Icons.star_outline_rounded),
                    color: Colors.amber.shade700,
                    size: 26,
                  );
                }),
              ),
              const SizedBox(width: 10),
              Text(
                '${feedback.rating.toStringAsFixed(1)} / 5.0',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Text(
              feedback.comments.trim().isNotEmpty
                  ? '"${feedback.comments.trim()}"'
                  : '"Repair completed smoothly and verified by community members."',
              style: const TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.black87,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
