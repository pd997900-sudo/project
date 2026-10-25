import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/complaint_model.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/community_verification_poll_card.dart';
import '../chat/complaint_chat_screen.dart';
import 'feedback_screen.dart';
import 'reporter_main_screen.dart';

class ComplaintTrackingScreen extends StatefulWidget {
  final Complaint complaint;
  final String? complaintId;

  const ComplaintTrackingScreen({
    super.key,
    required this.complaint,
    this.complaintId,
  });

  @override
  State<ComplaintTrackingScreen> createState() => _ComplaintTrackingScreenState();
}

class _ComplaintTrackingScreenState extends State<ComplaintTrackingScreen> {
  late int _selectedStageIdx;
  List<ProgressUpdate>? _authoritativeUpdates;
  FeedbackModel? _authoritativeReporterFeedback;

  Widget _buildDamageImage(String? rawUrl, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    final url = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : '';
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildFallbackBox(width, height),
        );
      } catch (_) {
        return _buildFallbackBox(width, height);
      }
    } else if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildFallbackBox(width, height),
      );
    }
    return _buildFallbackBox(width, height);
  }

  Widget _buildFallbackBox(double? width, double? height) {
    return Container(
      width: width,
      height: height,
      color: Colors.blue.shade100,
      child: const Icon(Icons.add_road_rounded, color: Colors.blue),
    );
  }

  static const List<String> trackingStages = [
    'Submitted',
    'Under Verification',
    'Verified',
    'Accepted',
    'Work Started',
    'Repair In Progress',
    'Completed',
  ];

  @override
  void initState() {
    super.initState();
    _selectedStageIdx = _getEffectiveStageIndex(widget.complaint);
    _fetchAuthoritativeUpdates();
    _fetchAuthoritativeFeedback();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<ComplaintProvider>(context, listen: false).refreshComplaints();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchAuthoritativeFeedback();
  }

  @override
  void didUpdateWidget(covariant ComplaintTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.complaint.complaintId != widget.complaint.complaintId ||
        oldWidget.complaint.status != widget.complaint.status ||
        oldWidget.complaint.allFeedbacks.length != widget.complaint.allFeedbacks.length ||
        oldWidget.complaint.feedback != widget.complaint.feedback) {
      _selectedStageIdx = _getEffectiveStageIndex(widget.complaint);
      _fetchAuthoritativeUpdates();
      _fetchAuthoritativeFeedback();
    }
  }

  Future<void> _fetchAuthoritativeFeedback() async {
    final complaintId = (widget.complaintId ?? widget.complaint.complaintId).trim();
    if (complaintId.isEmpty) return;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final supaUid = SupabaseService.client?.auth.currentUser?.id;
      final currentUserId = (supaUid != null && supaUid.isNotEmpty)
          ? supaUid
          : (auth.currentUser?.id.trim() ?? '');

      if (SupabaseService.isConnected && currentUserId.isNotEmpty) {
        final remoteRow = await SupabaseService.getComplaintFeedback(
          complaintId,
          reporterId: currentUserId,
        );
        if (remoteRow != null && mounted) {
          final fb = FeedbackModel.fromJson(remoteRow);
          if (fb.rating > 0) {
            setState(() {
              _authoritativeReporterFeedback = fb;
            });
            return;
          }
        }
      }

      // Check if local complaint or provider has feedback for this reporter
      if (mounted) {
        final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
        final latestComplaint = complaintProv.complaints.firstWhere(
          (c) => c.complaintId.trim().toLowerCase() == complaintId.toLowerCase(),
          orElse: () => widget.complaint,
        );
        final cFeedback = latestComplaint.feedbackForReporter(currentUserId) ??
            (supaUid != null && supaUid.isNotEmpty ? latestComplaint.feedbackForReporter(supaUid) : null) ??
            (auth.currentUser?.id.isNotEmpty == true ? latestComplaint.feedbackForReporter(auth.currentUser!.id) : null) ??
            (auth.currentUser?.email.isNotEmpty == true ? latestComplaint.feedbackForReporter(auth.currentUser!.email) : null) ??
            widget.complaint.feedbackForReporter(currentUserId) ??
            (latestComplaint.feedback != null && _isFeedbackAuthor(auth, latestComplaint)
                ? latestComplaint.feedback
                : (widget.complaint.feedback != null && _isFeedbackAuthor(auth, widget.complaint) ? widget.complaint.feedback : null));
        if (cFeedback != null && cFeedback.rating > 0) {
          setState(() {
            _authoritativeReporterFeedback = cFeedback;
          });
        }
      }
    } catch (e) {
      debugPrint('Notice loading authoritative feedback in tracking screen: $e');
    }
  }

  Future<void> _fetchAuthoritativeUpdates() async {
    final complaintId = (widget.complaintId ?? widget.complaint.complaintId).trim();
    if (complaintId.isEmpty || !SupabaseService.isConnected) return;
    try {
      final remoteRows = await SupabaseService.getProgressUpdatesForComplaint(complaintId);
      if (remoteRows.isNotEmpty && mounted) {
        final List<ProgressUpdate> fetched = [];
        for (var u in remoteRows) {
          final rawId = u['id']?.toString().trim();
          final rawUpdateId = u['update_id']?.toString().trim();
          fetched.add(
            ProgressUpdate(
              id: (rawId != null && rawId.isNotEmpty && Complaint.isUuid(rawId)) ? rawId : null,
              updateId: (rawUpdateId != null && rawUpdateId.isNotEmpty)
                  ? rawUpdateId
                  : (rawId ?? 'UPD-${DateTime.now().millisecondsSinceEpoch}'),
              complaintId: u['complaint_id']?.toString() ?? '',
              communityUserId: u['community_user_id']?.toString() ?? '',
              communityUserName: u['community_user_name']?.toString() ?? 'Community Crew',
              progressNote: u['progress_note']?.toString() ?? u['notes']?.toString() ?? '',
              imageUrl: u['image_url']?.toString(),
              workPercentage: Complaint.parseDouble(u['work_percentage'] ?? u['percentage'], 0.0),
              status: u['status']?.toString() ?? 'Repair In Progress',
              createdAt: u['created_at'] != null
                  ? Complaint.parseTimestamptz(u['created_at']) ?? DateTime.now()
                  : DateTime.now(),
              latitude: Complaint.parseNullableDouble(u['latitude']),
              longitude: Complaint.parseNullableDouble(u['longitude']),
              address: u['address']?.toString(),
              capturedAt: u['captured_at'] != null ? Complaint.parseTimestamptz(u['captured_at']) : null,
            ),
          );
        }
        if (mounted) {
          setState(() {
            _authoritativeUpdates = fetched;
          });
        }
      }
    } catch (e) {
      debugPrint('Notice loading authoritative progress updates: $e');
    }
  }

  List<String> _getTrackingStages(Complaint complaint) {
    if (complaint.isRejected) {
      return const [
        'Submitted',
        'Under Verification',
        'Rejected',
      ];
    }
    return trackingStages;
  }

  int _getEffectiveStageIndex(Complaint complaint) {
    if (complaint.isRejected) {
      return 2;
    }
    int idx = _getStageIndex(complaint.status);
    if (complaint.isCompleted || complaint.progressPercentage >= 100.0) {
      return 6;
    }
    if (complaint.progressPercentage >= 85.0) {
      return max(idx, 5);
    }
    if (complaint.progressPercentage > 0.0 ||
        complaint.updates.any((u) =>
            u.workPercentage > 0.0 ||
            u.status.trim().toLowerCase() == 'repair in progress' ||
            u.status.trim().toLowerCase() == 'near completion' ||
            u.updateId.startsWith('UPD-'))) {
      return max(idx, 5);
    }
    if (complaint.updates.any((u) =>
        u.status.trim().toLowerCase() == 'work started' ||
        u.updateId.startsWith('START-'))) {
      return max(idx, 4);
    }
    return idx;
  }

  int _getStageIndex(String status) {
    switch (status.toLowerCase()) {
      case 'submitted':
        return 0;
      case 'under verification':
        return 1;
      case 'verified':
        return 2;
      case 'accepted':
        return 3;
      case 'work started':
        return 4;
      case 'repair in progress':
      case 'near completion':
        return 5;
      case 'completed':
        return 6;
      case 'rejected':
      case 'fake':
        return 2;
      default:
        return 0;
    }
  }

  void _showImagePreviewDialog(
    BuildContext context,
    String imageUrl,
    String title, {
    double? lat,
    double? lng,
    String? address,
    DateTime? capturedAt,
  }) {
    final bool hasValidCoords = lat != null && lat != 0.0 && lng != null && lng != 0.0;
    String displayAddress = 'Location unavailable';
    if (address != null && address.trim().isNotEmpty && address.trim() != 'Location Unavailable' && address.trim() != 'Location') {
      displayAddress = address.trim();
    } else if (hasValidCoords) {
      displayAddress = 'Lat: ${lat.toStringAsFixed(5)}°, Long: ${lng.toStringAsFixed(5)}°';
    }

    final String coordString = hasValidCoords
        ? 'Lat: ${lat.toStringAsFixed(6)}°, Long: ${lng.toStringAsFixed(6)}°'
        : 'Coordinates unavailable';

    // Requirement 4 & 5: Format actual photo capture timestamp in IST (Asia/Kolkata, UTC+05:30).
    // If unavailable, show "Capture time unavailable". Do not invent a timestamp.
    String? captureDateString;
    String? captureTimeString;

    if (capturedAt != null) {
      final localDateTime = capturedAt.toLocal();
      captureDateString = DateFormat('d MMM yyyy').format(localDateTime);
      captureTimeString = DateFormat('hh:mm a').format(localDateTime);
    }

    showDialog(
      context: context,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.90,
              maxWidth: 540,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 6),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Fixed Header with title and accessible close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.center_focus_strong_rounded, color: AppTheme.primaryBlue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 2. Responsive scrollable body to prevent overflow on any screen height
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Photo display with interactive pinch/zoom
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            constraints: BoxConstraints(
                              maxHeight: screenHeight * 0.42,
                            ),
                            color: Colors.black26,
                            child: InteractiveViewer(
                              maxScale: 4.0,
                              minScale: 1.0,
                              child: Center(
                                child: _buildDamageImage(imageUrl, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            '🔍 Pinch or scroll to zoom in photo',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Requirement 3: Metadata card under the photo
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // GPS Location Address
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.location_on_rounded,
                                    size: 16,
                                    color: hasValidCoords ? AppTheme.emergencyRed : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'GPS Location',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.6),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          displayAddress,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white12, height: 16),

                              // Coordinates: Latitude and Longitude
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.my_location_rounded,
                                    size: 15,
                                    color: hasValidCoords ? AppTheme.primaryBlue : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Coordinates',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.6),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          coordString,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.9),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white12, height: 16),

                              // Photo Capture Date and Time in IST
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 15,
                                    color: Colors.amberAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Capture Date & Time (IST)',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.6),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        if (capturedAt != null)
                                          Text(
                                            '$captureDateString • $captureTimeString',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.9),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          )
                                        else
                                          const Text(
                                            'Capture time unavailable',
                                            style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, String> _getStageAuditLog(String stageName, [Complaint? dynamicComplaint]) {
    final complaint = dynamicComplaint ?? widget.complaint;

    final submissionTimeFormatted = DateFormat('M/d/yyyy • hh:mm a').format(complaint.createdAt.toLocal());

    ProgressUpdate? findUpdateForStage(String stage) {
      final s = stage.trim().toLowerCase();
      try {
        final allUpdates = Complaint.deduplicateUpdates(complaint.updates);
        allUpdates.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        if (s == 'under verification') {
          return allUpdates.cast<ProgressUpdate?>().firstWhere(
            (u) => u?.status.trim().toLowerCase() == 'under verification',
            orElse: () => null,
          );
        }
        if (s == 'verified') {
          return allUpdates.cast<ProgressUpdate?>().firstWhere(
            (u) => u?.status.trim().toLowerCase() == 'verified' || (u != null && u.updateId.startsWith('VERIFY-')),
            orElse: () => null,
          );
        }
        if (s == 'accepted') {
          return allUpdates.cast<ProgressUpdate?>().firstWhere(
            (u) => u?.status.trim().toLowerCase() == 'accepted' || (u != null && u.updateId.startsWith('ACCEPT-')),
            orElse: () => null,
          );
        }
        if (s == 'work started') {
          return allUpdates.cast<ProgressUpdate?>().firstWhere(
            (u) => u?.status.trim().toLowerCase() == 'work started' || (u != null && u.updateId.startsWith('START-')),
            orElse: () => null,
          );
        }
        if (s == 'repair in progress') {
          final progressUpdates = allUpdates.where((u) {
            final st = u.status.trim().toLowerCase();
            if (st == 'verified' || st == 'accepted' || st == 'completed' || st == 'repaired' || st == 'rejected') {
              return false;
            }
            if (u.updateId.startsWith('VERIFY-') || u.updateId.startsWith('ACCEPT-') || u.updateId.startsWith('COMPLETE-')) {
              return false;
            }
            return st == 'repair in progress' ||
                   st == 'near completion' ||
                   st == 'in progress' ||
                   st == 'work started' ||
                   u.updateId.startsWith('START-') ||
                   u.updateId.startsWith('UPD-') ||
                   (u.workPercentage > 0.0 && u.workPercentage < 100.0);
          }).toList();
          return progressUpdates.isNotEmpty ? progressUpdates.last : null;
        }
        if (s == 'completed') {
          return allUpdates.cast<ProgressUpdate?>().lastWhere(
            (u) => u?.status.trim().toLowerCase() == 'completed' ||
                   u?.status.trim().toLowerCase() == 'repaired' ||
                   (u != null && u.updateId.startsWith('COMPLETE-')) ||
                   (u != null && u.workPercentage >= 100.0),
            orElse: () => null,
          );
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    final stageIdx = _getStageIndex(stageName);
    final currentStageIdx = _getEffectiveStageIndex(complaint);
    final stageUpdate = findUpdateForStage(stageName);
    final bool hasReachedStage = stageIdx <= currentStageIdx || stageUpdate != null;

    String getActualOrUnavailableTime(ProgressUpdate? update, String pendingFallback) {
      if (update != null) {
        return DateFormat('M/d/yyyy • hh:mm a').format(update.createdAt.toLocal());
      }
      if (hasReachedStage) {
        return 'Time unavailable';
      }
      return pendingFallback;
    }

    switch (stageName) {
      case 'Submitted':
        return {
          'time': submissionTimeFormatted,
          'seenInfo': 'Notification Sent to RoadWatch Admin System',
          'action': 'Complaint logged by citizen reporter ${complaint.reporterName}. Geo-location coordinates and damage image stored.',
          'officer': 'Citizen App System',
          'status': 'Registered',
        };
      case 'Under Verification':
        final matchingUpdate = findUpdateForStage('under verification');
        final stageTime = getActualOrUnavailableTime(matchingUpdate, 'Pending Verification');
        final hasTimeFormatted = stageTime.contains('•');
        final timeSuffix = hasTimeFormatted ? ' at ${stageTime.split('•').last.trim()}' : '';
        return {
          'time': stageTime,
          'seenInfo': hasReachedStage
              ? 'Notification Viewed & Acknowledged by Field Team$timeSuffix'
              : 'Awaiting Field Team Assignment',
          'action': hasReachedStage
              ? 'Field verification team assigned to inspect road defect at ${complaint.address}.'
              : 'Stage pending verification assignment.',
          'officer': 'Field Inspection Team',
          'status': hasReachedStage ? 'Notification Seen & Under Audit' : 'Pending Verification',
        };
      case 'Verified':
        final matchingUpdate = findUpdateForStage('verified');
        final stageTime = getActualOrUnavailableTime(matchingUpdate, 'Pending Verification');
        final inspector = matchingUpdate?.communityUserName.isNotEmpty == true
            ? matchingUpdate!.communityUserName
            : 'Road Safety Inspector';
        return {
          'time': stageTime,
          'seenInfo': hasReachedStage
              ? 'Verified On-Site by $inspector'
              : 'Awaiting Inspection Approval',
          'action': hasReachedStage
              ? 'On-site measurement complete. Damage classified as ${complaint.severity} severity. Dispatch approval granted.'
              : 'Stage pending inspector verification.',
          'officer': inspector,
          'status': hasReachedStage ? 'Verified & Approved' : 'Pending Approval',
        };
      case 'Accepted':
        final matchingUpdate = findUpdateForStage('accepted');
        final stageTime = getActualOrUnavailableTime(matchingUpdate, 'Pending Assignment');
        final crewName = matchingUpdate?.communityUserName.isNotEmpty == true
            ? matchingUpdate!.communityUserName
            : (complaint.communityUserName ?? 'Community Volunteer Crew');
        return {
          'time': stageTime,
          'seenInfo': hasReachedStage
              ? 'Job Accepted by $crewName'
              : 'Awaiting Crew Acceptance',
          'action': hasReachedStage
              ? 'Crew Lead accepted notification. Repair tools, asphalt batch, and safety equipment assigned.'
              : 'Stage pending community crew acceptance.',
          'officer': crewName,
          'status': hasReachedStage ? 'Assigned to Crew' : 'Pending Assignment',
        };
      case 'Work Started':
        final matchingUpdate = findUpdateForStage('work started');
        final stageTime = getActualOrUnavailableTime(matchingUpdate, 'Pending Work Start');
        final hasTimeFormatted = stageTime.contains('•');
        final timeSuffix = hasTimeFormatted ? ' at ${stageTime.split('•').last.trim()}' : '';
        final crewName = matchingUpdate?.communityUserName.isNotEmpty == true
            ? matchingUpdate!.communityUserName
            : (complaint.communityUserName ?? 'Field Crew Team');
        return {
          'time': stageTime,
          'seenInfo': hasReachedStage
              ? 'Work Started Notification Triggered'
              : 'Awaiting Work Initiation',
          'action': hasReachedStage
              ? 'Repair crew arrived on site$timeSuffix. Safety measures placed around work area. Repair excavation initiated.'
              : 'Stage pending work initiation on site.',
          'officer': crewName,
          'status': hasReachedStage ? 'Work Initiated' : 'Pending Start',
        };
      case 'Repair In Progress':
        final matchingUpdate = findUpdateForStage('repair in progress');
        final stageTime = getActualOrUnavailableTime(matchingUpdate, 'Pending Repair');
        final crewName = matchingUpdate?.communityUserName.isNotEmpty == true
            ? matchingUpdate!.communityUserName
            : (complaint.communityUserName ?? 'Field Crew Team');
        final pct = matchingUpdate?.workPercentage != null && matchingUpdate!.workPercentage > 0
            ? matchingUpdate.workPercentage.toInt()
            : (complaint.progressPercentage > 0 ? complaint.progressPercentage.toInt() : 50);
        return {
          'time': stageTime,
          'seenInfo': hasReachedStage
              ? 'Progress Updated by Field Crew'
              : 'Awaiting Progress Update',
          'action': hasReachedStage
              ? 'Road repair underway. Aggregate and surface treatment active (Current Progress: $pct%).'
              : 'Stage pending repair progress update.',
          'officer': crewName,
          'status': hasReachedStage ? 'Repair In Progress' : 'Pending Repair',
        };
      case 'Completed':
        final matchingUpdate = findUpdateForStage('completed');
        final stageTime = getActualOrUnavailableTime(matchingUpdate, 'Pending Completion');
        final notes = complaint.completionNotes ?? matchingUpdate?.progressNote;
        return {
          'time': stageTime,
          'seenInfo': hasReachedStage
              ? 'Final Pass Inspection Verified'
              : 'Awaiting Final Inspection',
          'action': hasReachedStage
              ? (notes != null && notes.trim().isNotEmpty
                  ? notes.trim()
                  : 'Road repair completed and quality verified. After-repair photo uploaded. Road reopened.')
              : 'Stage pending completion.',
          'officer': matchingUpdate?.communityUserName.isNotEmpty == true
              ? matchingUpdate!.communityUserName
              : 'Chief Road Inspector',
          'status': hasReachedStage ? 'Completed & Reopened' : 'Pending Completion',
        };
      case 'Rejected':
        final stageTime = complaint.updatedAt != null
            ? DateFormat('M/d/yyyy • hh:mm a').format(complaint.updatedAt!.toLocal())
            : DateFormat('M/d/yyyy • hh:mm a').format(complaint.createdAt.toLocal());
        return {
          'time': stageTime,
          'seenInfo': 'Notification Reviewed & Rejected by Community / Field Inspectors',
          'action': 'Report was audited and marked as rejected by community inspectors. Issue closed.',
          'officer': 'Community Inspection Team',
          'status': 'Rejected',
        };
      default:
        return {
          'time': 'Pending Schedule',
          'seenInfo': 'Awaiting Action',
          'action': 'Stage pending execution by field team.',
          'officer': 'Pending Assignment',
          'status': 'Pending',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final targetId = (widget.complaintId ?? widget.complaint.complaintId).trim().toLowerCase();
    var complaint = complaintProv.complaints.firstWhere(
      (c) => targetId.isNotEmpty && c.complaintId.trim().toLowerCase() == targetId,
      orElse: () => widget.complaint,
    );

    if (_authoritativeUpdates != null && _authoritativeUpdates!.isNotEmpty) {
      final merged = Complaint.deduplicateUpdates([..._authoritativeUpdates!, ...complaint.updates]);
      merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      complaint = complaint.copyWith(updates: merged);
    }

    final currentStageIdx = _getEffectiveStageIndex(complaint);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ReporterMainScreen()),
                (route) => false,
              );
            }
          },
        ),
        title: Text('Complaint ${complaint.complaintId}'),
        actions: [
          if (_isOriginalReporter(Provider.of<AuthProvider>(context, listen: false), complaint) && complaint.canBeDeleted) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.emergencyRed),
              tooltip: 'Delete Complaint',
              onPressed: () => _confirmDeleteComplaint(context, complaint),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Go to Home Dashboard',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ReporterMainScreen()),
                (route) => false,
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
              // Status Header Glass Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                backgroundColor: AppTheme.primaryDark,
                opacity: 0.95,
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
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusBadge(status: complaint.status),
                            const SizedBox(width: 6),
                            SeverityBadge(severity: complaint.severity),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      complaint.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            complaint.address,
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Progress percentage bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          complaint.isRejected ? 'Complaint Status' : 'Repair Progress',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          complaint.isRejected ? 'Rejected' : '${complaint.progressPercentage.toInt()}%',
                          style: TextStyle(
                            color: complaint.isRejected ? AppTheme.emergencyRed : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: complaint.isRejected ? 1.0 : (complaint.progressPercentage / 100.0),
                        backgroundColor: Colors.white24,
                        color: complaint.isRejected ? AppTheme.emergencyRed : AppTheme.successGreen,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Community Verification Poll Section (Interactive Voting in Reporter Portal)
              CommunityVerificationPollCard(complaint: complaint, allowVoting: true),

              const SizedBox(height: 24),

              // Photos Card: Before Repair vs After Repair (Clickable for full screen)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'Inspection & Repair Photos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Tap photo to enlarge 🔍',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  // Before Repair Photo
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        _showImagePreviewDialog(
                          context,
                          complaint.beforeImageUrl ?? complaint.imageUrl,
                          'BEFORE REPAIR PHOTO (${complaint.complaintId})',
                          lat: complaint.latitude,
                          lng: complaint.longitude,
                          address: complaint.address,
                          capturedAt: complaint.createdAt,
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: GlassCard(
                        borderRadius: 16,
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Flexible(
                                  child: Text(
                                    'BEFORE REPAIR',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.emergencyRed),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.zoom_in, size: 14, color: AppTheme.emergencyRed),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  _buildDamageImage(
                                    complaint.beforeImageUrl ?? complaint.imageUrl,
                                    height: 120,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    bottom: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.fullscreen, color: Colors.white, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // After Repair Photo (Shown ONLY when work is 100% Completed)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final bool isCompleted = complaint.status == 'Completed';
                        final String? afterImg = isCompleted
                            ? (complaint.afterImageUrl ??
                                (complaint.updates.isNotEmpty
                                    ? complaint.updates.firstWhere(
                                        (u) => u.imageUrl != null && u.imageUrl!.isNotEmpty,
                                        orElse: () => ProgressUpdate(
                                          updateId: '',
                                          complaintId: '',
                                          communityUserId: '',
                                          communityUserName: '',
                                          progressNote: '',
                                          status: 'Completed',
                                        ),
                                      ).imageUrl
                                    : null))
                            : null;

                        final bool hasAfterPhoto = isCompleted && afterImg != null && afterImg.isNotEmpty;

                        return InkWell(
                          onTap: hasAfterPhoto
                              ? () {
                                  _showImagePreviewDialog(
                                    context,
                                    afterImg,
                                    'AFTER REPAIR PHOTO (${complaint.complaintId})',
                                  );
                                }
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          child: GlassCard(
                            borderRadius: 16,
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Flexible(
                                      child: Text(
                                        'AFTER REPAIR',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(Icons.zoom_in, size: 14, color: AppTheme.successGreen),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (hasAfterPhoto) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      children: [
                                        _buildDamageImage(
                                          afterImg,
                                          height: 120,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                        Positioned(
                                          bottom: 6,
                                          right: 6,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.fullscreen, color: Colors.white, size: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'Awaiting Work Completion',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              // Community Progress Updates & Work Photos Section
              if (complaint.updates.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'Community Crew Work Photos & Notes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.successGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${Complaint.deduplicateUpdates(complaint.updates).length} Updates',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...(() {
                  final list = Complaint.deduplicateUpdates(complaint.updates);
                  list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                  return list;
                })().map((u) {
                  final bool hasLoc = u.latitude != null && u.latitude != 0.0 && u.longitude != null && u.longitude != 0.0;
                  final String locAddr = (u.address != null && u.address!.isNotEmpty && u.address != 'Location')
                      ? u.address!
                      : (hasLoc ? 'Lat: ${u.latitude!.toStringAsFixed(4)}°, Long: ${u.longitude!.toStringAsFixed(4)}°' : 'Location unavailable');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      borderRadius: 16,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.engineering_rounded, color: AppTheme.primaryBlue, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    u.communityUserName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('M/d/yyyy • hh:mm a').format(u.createdAt.toLocal()),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.successGreen,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${u.workPercentage.toInt()}% Done',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            u.progressNote,
                            style: const TextStyle(fontSize: 13, color: AppTheme.primaryDark),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.location_on_rounded, size: 14, color: hasLoc ? AppTheme.emergencyRed : Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  locAddr,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (u.imageUrl != null && u.imageUrl!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () {
                                _showImagePreviewDialog(
                                  context,
                                  u.imageUrl!,
                                  'WORK PROGRESS PHOTO (${complaint.complaintId})',
                                  lat: u.latitude,
                                  lng: u.longitude,
                                  address: u.address,
                                  capturedAt: u.capturedAt ?? u.createdAt,
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    _buildDamageImage(
                                      u.imageUrl!,
                                      height: 160,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                      color: Colors.black54,
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.zoom_in, color: Colors.white, size: 14),
                                          SizedBox(width: 4),
                                          Text(
                                            'Tap to view progress photo & geotag details',
                                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 24),

              // Interactive Expandable Status Timeline Tracker
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'Tracking',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Tap stage for details 💡',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: () {
                    final stages = _getTrackingStages(complaint);
                    return List.generate(stages.length, (idx) {
                      final stageName = stages[idx];
                      final isRejectedStage = stageName == 'Rejected';
                      final auditLog = _getStageAuditLog(stageName, complaint);
                      final isPassed = idx <= currentStageIdx ||
                          (auditLog['time'] != null &&
                              !auditLog['time']!.startsWith('Pending') &&
                              auditLog['time'] != 'Time unavailable');
                      final isCurrent = idx == currentStageIdx;
                      final isExpanded = _selectedStageIdx == idx;

                      return Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _selectedStageIdx = isExpanded ? -1 : idx;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Timeline Vertical Dot Line
                                  Column(
                                    children: [
                                      Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: isRejectedStage
                                              ? AppTheme.emergencyRed
                                              : (isPassed ? AppTheme.primaryBlue : Colors.grey.shade300),
                                          shape: BoxShape.circle,
                                          border: isCurrent
                                              ? Border.all(
                                                  color: isRejectedStage ? AppTheme.emergencyRed : AppTheme.primaryDark,
                                                  width: 3,
                                                )
                                              : null,
                                        ),
                                        child: isRejectedStage
                                            ? const Icon(Icons.close_rounded, size: 16, color: Colors.white)
                                            : (isPassed
                                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                                : null),
                                      ),
                                      if (idx < stages.length - 1)
                                        Container(
                                          width: 2,
                                          height: isExpanded ? 160 : 36,
                                          color: isRejectedStage
                                              ? AppTheme.emergencyRed
                                              : (idx < currentStageIdx ? AppTheme.primaryBlue : Colors.grey.shade300),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),

                                  // Stage Label & Accordion Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                stageName,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: isCurrent || isPassed ? FontWeight.bold : FontWeight.normal,
                                                  color: isRejectedStage
                                                      ? AppTheme.emergencyRed
                                                      : (isPassed ? const Color(0xFF0F172A) : Colors.grey),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Icon(
                                              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                              size: 20,
                                              color: isRejectedStage
                                                  ? AppTheme.emergencyRed
                                                  : (isPassed ? AppTheme.primaryBlue : Colors.grey),
                                            ),
                                          ],
                                        ),
                                        if (isCurrent)
                                          Text(
                                            isRejectedStage ? 'Final Decision: Rejected' : 'Active Current Status',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isRejectedStage ? AppTheme.emergencyRed : AppTheme.primaryBlue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),

                                        // Expanded Audit Detail Card when clicked
                                        if (isExpanded) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isRejectedStage
                                                  ? AppTheme.emergencyRed.withOpacity(0.06)
                                                  : AppTheme.primaryBlue.withOpacity(0.06),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isRejectedStage
                                                    ? AppTheme.emergencyRed.withOpacity(0.3)
                                                    : AppTheme.primaryBlue.withOpacity(0.2),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Timestamp Row
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.access_time_rounded,
                                                      size: 14,
                                                      color: isRejectedStage ? AppTheme.emergencyRed : AppTheme.primaryBlue,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        auditLog['time']!,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: isRejectedStage ? AppTheme.emergencyRed : AppTheme.primaryDark,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),

                                                // Notification Seen Info
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      isRejectedStage ? Icons.cancel_outlined : Icons.remove_red_eye_outlined,
                                                      size: 14,
                                                      color: isRejectedStage ? AppTheme.emergencyRed : AppTheme.successGreen,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        auditLog['seenInfo']!,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: isRejectedStage ? AppTheme.emergencyRed : AppTheme.successGreen,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),

                                                // Work Details
                                                Text(
                                                  '📋 Activity Log: ${auditLog['action']}',
                                                  style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.3),
                                                ),
                                                const SizedBox(height: 6),

                                                // Officer In Charge
                                                Text(
                                                  '👤 Action Officer: ${auditLog['officer']}',
                                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 14),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    });
                  }(),
                ),
              ),

              const SizedBox(height: 20),

              // Message Community Button (Directly below status timeline)
              Builder(
                builder: (ctx) {
                  ChatProvider? chatProv;
                  try {
                    chatProv = Provider.of<ChatProvider>(ctx);
                  } catch (_) {}
                  final auth = Provider.of<AuthProvider>(ctx, listen: false);
                  final unreadCount = chatProv?.getUnreadCountForComplaint(complaint.complaintId, auth.selectedRole) ?? 0;

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ComplaintChatScreen(complaint: complaint),
                          ),
                        );
                      },
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.chat_bubble_rounded, size: 20),
                          if (unreadCount > 0)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.emergencyRed,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                child: Text(
                                  '$unreadCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '💬 Message Community',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            if (unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$unreadCount New',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 3,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Feedback Banner if Completed
              if (complaint.status == 'Completed') ...[
                Builder(
                  builder: (ctx) {
                    final auth = Provider.of<AuthProvider>(ctx);
                    final supaUid = SupabaseService.client?.auth.currentUser?.id;
                    final currentUserId = (supaUid != null && supaUid.isNotEmpty)
                        ? supaUid
                        : (auth.currentUser?.id.trim() ?? '');
                    final isAuthoritativeForUser = _authoritativeReporterFeedback != null &&
                        _authoritativeReporterFeedback!.rating > 0 &&
                        (_isFeedbackModelAuthor(auth, _authoritativeReporterFeedback!) ||
                         (currentUserId.isNotEmpty && _authoritativeReporterFeedback!.reporterId.trim().toLowerCase() == currentUserId.toLowerCase()) ||
                         (supaUid != null && _authoritativeReporterFeedback!.reporterId.trim().toLowerCase() == supaUid.toLowerCase()));
                    final myFeedback = (isAuthoritativeForUser ? _authoritativeReporterFeedback : null) ??
                        complaint.feedbackForReporter(currentUserId) ??
                        (supaUid != null && supaUid.isNotEmpty ? complaint.feedbackForReporter(supaUid) : null) ??
                        (auth.currentUser?.id.isNotEmpty == true ? complaint.feedbackForReporter(auth.currentUser!.id) : null) ??
                        (auth.currentUser?.email.isNotEmpty == true ? complaint.feedbackForReporter(auth.currentUser!.email) : null) ??
                        (_isFeedbackAuthor(auth, complaint) ? complaint.feedback : null);
                    final hasMyFeedback = myFeedback != null && myFeedback.rating > 0;

                    String headerTitle = hasMyFeedback
                        ? 'Your Feedback & Rating'
                        : 'Repair Work Completed!';
                    String subtitleText = hasMyFeedback
                        ? 'Thank you for rating our repair team!'
                        : 'How satisfied are you with the road repair quality?';

                    return GlassCard(
                      borderRadius: 20,
                      padding: const EdgeInsets.all(18),
                      backgroundColor: AppTheme.successGreen,
                      opacity: 0.95,
                      child: Column(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 40),
                          const SizedBox(height: 8),
                          Text(
                            headerTitle,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitleText,
                            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          
                          // Display Submitted Feedback Rating & Comments if THIS reporter has submitted
                          if (hasMyFeedback) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.3)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ...List.generate(5, (index) => Icon(
                                        Icons.star_rounded,
                                        color: index < myFeedback.rating.round() ? Colors.amber : Colors.white60,
                                        size: 22,
                                      )),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${myFeedback.rating.toStringAsFixed(1)} / 5.0',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  if (myFeedback.comments.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      '"${myFeedback.comments}"',
                                      style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic, fontSize: 13),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: () async {
                              final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
                              final complaintForFeedback = hasMyFeedback
                                  ? complaint.copyWith(feedback: myFeedback)
                                  : complaint.copyWith(clearFeedback: true);
                              final returnedFeedback = await Navigator.push<FeedbackModel>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FeedbackScreen(complaint: complaintForFeedback),
                                ),
                              );
                              if (!mounted) return;
                              if (returnedFeedback != null && returnedFeedback.rating > 0) {
                                setState(() {
                                  _authoritativeReporterFeedback = returnedFeedback;
                                });
                              }
                              await _fetchAuthoritativeFeedback();
                              await complaintProv.refreshComplaints();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.successGreen,
                            ),
                            child: Text(
                              hasMyFeedback ? 'Edit Your Rating & Feedback' : 'Provide Rating & Feedback',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const ReporterMainScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.home_rounded, color: Colors.white),
                    label: const Text(
                      'Return to Home',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                if (_isOriginalReporter(Provider.of<AuthProvider>(context, listen: false), complaint) && complaint.canBeDeleted) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDeleteComplaint(context, complaint),
                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.emergencyRed),
                      label: const Text(
                        'Delete Complaint',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.emergencyRed),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.emergencyRed,
                        side: const BorderSide(color: AppTheme.emergencyRed),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isFeedbackModelAuthor(AuthProvider auth, FeedbackModel fb) {
    final supaUid = SupabaseService.client?.auth.currentUser?.id.trim().toLowerCase();
    final fbId = fb.reporterId.trim().toLowerCase();
    final fbName = (fb.reporterName ?? '').trim().toLowerCase();

    // 1. Supabase Auth UID check
    if (supaUid != null && supaUid.isNotEmpty) {
      if (fbId == supaUid || fbId.contains(supaUid) || supaUid.contains(fbId)) return true;
    }

    // 2. AuthProvider currentUser checks
    final user = auth.currentUser;
    if (user != null) {
      final userId = user.id.trim().toLowerCase();
      final userEmail = user.email.trim().toLowerCase();
      final userName = user.name.trim().toLowerCase();

      if (userId.isNotEmpty && (fbId == userId || fbId.contains(userId) || userId.contains(fbId))) return true;
      if (userEmail.isNotEmpty && (fbId == userEmail || fbName == userEmail || userEmail.contains(fbId))) return true;
      if (userName.isNotEmpty && (fbName == userName || userName.contains(fbName))) return true;
    }

    // 3. Match against authoritative reporter feedback if already established
    if (_authoritativeReporterFeedback != null &&
        _authoritativeReporterFeedback!.feedbackId.isNotEmpty &&
        _authoritativeReporterFeedback!.feedbackId.toLowerCase() == fb.feedbackId.toLowerCase() &&
        _authoritativeReporterFeedback!.rating > 0) {
      return true;
    }

    return false;
  }

  bool _isFeedbackAuthor(AuthProvider auth, Complaint c) {
    if (c.feedback == null) return false;
    return _isFeedbackModelAuthor(auth, c.feedback!);
  }

  bool _isOriginalReporter(AuthProvider auth, Complaint c) {
    final user = auth.currentUser;
    if (user == null) return false;

    final userId = user.id.trim().toLowerCase();
    final userEmail = user.email.trim().toLowerCase();
    final userName = user.name.trim().toLowerCase();
    final userPrefix = userEmail.contains('@') ? userEmail.split('@').first.trim().toLowerCase() : userEmail;

    final rId = c.reporterId.trim().toLowerCase();
    final rName = c.reporterName.trim().toLowerCase();

    // 1. Direct ID match
    if (userId.isNotEmpty && (rId == userId || rId.contains(userId))) return true;

    // 2. Direct Email match
    if (userEmail.isNotEmpty && (rId == userEmail || rName == userEmail || rId.contains(userEmail) || rName.contains(userEmail))) return true;

    // 3. Email username prefix match
    if (userPrefix.length >= 3 && (rId.contains(userPrefix) || rName.contains(userPrefix))) return true;

    // 4. Name match
    if (userName.isNotEmpty && userName != 'citizen reporter' && (rName == userName || rName.contains(userName))) return true;

    return false;
  }

  void _confirmDeleteComplaint(BuildContext context, Complaint complaint) {
    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppTheme.emergencyRed, size: 24),
            SizedBox(width: 8),
            Text('Delete Complaint', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this complaint?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await complaintProv.deleteComplaint(complaint.complaintId);
              if (context.mounted) {
                if (result.success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Complaint ${complaint.complaintId} deleted successfully!'),
                      backgroundColor: AppTheme.successGreen,
                    ),
                  );
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const ReporterMainScreen()),
                      (route) => false,
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.errorMessage ?? 'Failed to delete complaint. Please try again.'),
                      backgroundColor: AppTheme.emergencyRed,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emergencyRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
