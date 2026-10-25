import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/complaint_model.dart';
import '../../models/notification_model.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import 'complaint_tracking_screen.dart';
import '../community/complaint_verification_screen.dart';
import '../chat/complaint_chat_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final bool isActiveTab;

  const NotificationsScreen({
    super.key,
    this.onBack,
    this.isActiveTab = true,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Set<String> _readIds = {};
  List<NotificationItem> _persistedNotifications = [];
  bool _isLoadingPersisted = false;
  RealtimeChannel? _realtimeChannel;
  String? _subscribedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPersistedNotifications();
    });
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActiveTab && !oldWidget.isActiveTab) {
      _loadPersistedNotifications();
    }
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime(String userId) {
    if (!SupabaseService.isConnected || SupabaseService.client == null) return;
    if (_realtimeChannel != null && _subscribedUserId == userId) return;

    try {
      _realtimeChannel?.unsubscribe();
      _subscribedUserId = userId;
      _realtimeChannel = SupabaseService.client!
          .channel('public:notifications:$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              debugPrint('🔔 [REALTIME] Notification change detected (${payload.eventType}) for user $userId');
              _loadPersistedNotifications();
            },
          )
          .subscribe();
      debugPrint('✅ Subscribed to real-time notifications for user: $userId');
    } catch (e) {
      debugPrint('Notice subscribing to realtime notifications: $e');
    }
  }

  Future<void> _loadPersistedNotifications() async {
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    String? userId = authProv.currentUser?.id;
    if (userId == null ||
        userId.isEmpty ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(userId)) {
      userId = SupabaseService.currentUser?.id;
    }
    // If still legacy mock reporter ID, resolve to known reporter UUID
    if (userId == 'user_rep_1' || userId == 'anon_user_1' || userId == 'anon_user') {
      userId = '88deb318-8c4b-48fd-8915-52fbc04ed6dd';
    }

    if (userId != null && userId.isNotEmpty && SupabaseService.isConnected) {
      _subscribeRealtime(userId);
      if (mounted) setState(() => _isLoadingPersisted = true);
      try {
        final items = await SupabaseService.getNotificationsForUser(userId);
        if (mounted) {
          setState(() {
            _persistedNotifications = items;
            _isLoadingPersisted = false;
            for (var item in items) {
              if (item.isRead) {
                _readIds.add(item.id);
              }
            }
          });
        }
      } catch (e) {
        debugPrint('Notice loading notifications in screen: $e');
        if (mounted) setState(() => _isLoadingPersisted = false);
      }
    }
  }

  final List<Map<String, String>> _initialNotifications = [
    {
      'id': 'notif_1',
      'complaintId': 'RW-8945',
      'title': 'Complaint Verified!',
      'message': 'Your complaint RW-8945 (Caved Drainage Grate) has been verified by the community team.',
      'time': '17-08-2026 04:35 PM',
      'type': 'verified',
    },
    {
      'id': 'notif_2',
      'complaintId': 'RW-8830',
      'title': 'Repair Work Started',
      'message': 'Volunteer Crew has started repair work on RW-8830 (Cracked Asphalt).',
      'time': '17-08-2026 02:20 PM',
      'type': 'work',
    },
    {
      'id': 'notif_3',
      'complaintId': 'RW-8710',
      'title': 'Work Completed!',
      'message': 'Complaint RW-8710 (Broken Street Light) is now 100% repaired. Please leave your rating.',
      'time': '16-08-2026 11:15 AM',
      'type': 'completed',
    },
    {
      'id': 'notif_4',
      'complaintId': 'RW-9012',
      'title': 'Complaint Submitted',
      'message': 'Your report RW-9012 has been logged and assigned for inspection.',
      'time': '15-08-2026 09:30 AM',
      'type': 'submitted',
    },
  ];

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;

    int hour = dt.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    final hourStr = hour.toString().padLeft(2, '0');
    final minStr = dt.minute.toString().padLeft(2, '0');

    return '$day-$month-$year $hourStr:$minStr $period';
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'work':
        return Icons.engineering_rounded;
      case 'verified':
        return Icons.verified_rounded;
      case 'accepted':
        return Icons.handshake_rounded;
      case 'submitted':
        return Icons.assignment_turned_in_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      case 'emergency':
        return Icons.warning_amber_rounded;
      case 'new_complaint':
        return Icons.mark_email_unread_rounded;
      case 'chat':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'completed':
        return AppTheme.successGreen;
      case 'work':
        return AppTheme.warningOrange;
      case 'verified':
        return AppTheme.primaryBlue;
      case 'accepted':
        return AppTheme.primaryBlue;
      case 'submitted':
        return AppTheme.primaryBlue;
      case 'rejected':
        return AppTheme.emergencyRed;
      case 'emergency':
        return AppTheme.emergencyRed;
      case 'new_complaint':
        return AppTheme.primaryBlue;
      case 'chat':
        return AppTheme.primaryBlue;
      default:
        return AppTheme.primaryLight;
    }
  }

  String _getStatusFromType(String type) {
    switch (type) {
      case 'completed':
        return 'Completed';
      case 'work':
        return 'Repair In Progress';
      case 'verified':
        return 'Verified';
      case 'accepted':
        return 'Accepted';
      case 'submitted':
        return 'Submitted';
      case 'rejected':
        return 'Rejected';
      case 'emergency':
        return 'Submitted';
      case 'new_complaint':
        return 'Submitted';
      default:
        return 'Submitted';
    }
  }

  double _getProgressFromType(String type) {
    switch (type) {
      case 'completed':
        return 1.0;
      case 'work':
        return 0.5;
      case 'accepted':
        return 0.3;
      case 'verified':
        return 0.2;
      case 'submitted':
        return 0.1;
      case 'rejected':
        return 0.0;
      default:
        return 0.1;
    }
  }

  void _handleNotificationTap(Map<String, String> notif) {
    final notifId = notif['id']!;
    final complaintId = notif['complaintId'] ?? '';

    setState(() {
      _readIds.add(notifId);
    });

    // Mark as read in Supabase if connected
    if (SupabaseService.isConnected) {
      SupabaseService.markNotificationAsRead(notifId).catchError((e) {
        debugPrint('Error marking notification as read in Supabase: $e');
      });
    }

    final provider = Provider.of<ComplaintProvider>(context, listen: false);
    Complaint? matched;

    try {
      matched = provider.complaints.firstWhere(
        (c) =>
            c.complaintId.toLowerCase() == complaintId.toLowerCase() ||
            (notif['message'] != null && notif['message']!.contains(c.complaintId)) ||
            (notif['title'] != null && notif['title']!.contains(c.complaintId)),
      );
    } catch (_) {
      matched = null;
    }

    matched ??= Complaint(
      complaintId: complaintId.isNotEmpty ? complaintId : 'RW-8900',
      reporterId: 'user_rep_1',
      reporterName: 'Reporter name unavailable',
      reporterPhone: '',
      title: notif['title'] ?? 'Road Issue Report',
      description: notif['message'] ?? 'Detailed complaint report submitted for maintenance.',
      category: 'Road Damage',
      severity: 'Medium',
      latitude: 37.7749,
      longitude: -122.4194,
      address: 'Main Avenue, City Sector',
      imageUrl: 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=800&auto=format&fit=crop',
      beforeImageUrl: 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=800&auto=format&fit=crop',
      status: _getStatusFromType(notif['type'] ?? ''),
      progressPercentage: _getProgressFromType(notif['type'] ?? ''),
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    );

    if (notif['type'] == 'chat' && matched != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComplaintChatScreen(complaint: matched!),
        ),
      );
      return;
    }

    // Show Complaint Details Modal Dialog
    _showComplaintDetailsDialog(context, notif, matched);
  }

  void _showComplaintDetailsDialog(BuildContext context, Map<String, String> notif, Complaint complaint) {
    final color = _getColor(notif['type'] ?? '');
    final icon = _getIcon(notif['type'] ?? '');

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Icon + Title + Time + Close Button
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notif['title'] ?? 'Notification Details',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                            Text(
                              notif['time'] ?? 'Just now',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Divider(height: 1, color: Colors.grey.shade200),
                  const SizedBox(height: 16),

                  // Complaint Status & ID Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDark.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Complaint ID: ${complaint.complaintId}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          complaint.status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Email Notification Delivery Status Card
                  if (notif.containsKey('emailStatus') && (notif['emailStatus'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: notif['emailStatus'] == 'sent'
                            ? AppTheme.successGreen.withValues(alpha: 0.1)
                            : notif['emailStatus'] == 'failed'
                                ? AppTheme.emergencyRed.withValues(alpha: 0.1)
                                : Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: notif['emailStatus'] == 'sent'
                              ? AppTheme.successGreen.withValues(alpha: 0.3)
                              : notif['emailStatus'] == 'failed'
                                  ? AppTheme.emergencyRed.withValues(alpha: 0.3)
                                  : Colors.blue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            notif['emailStatus'] == 'sent'
                                ? Icons.mark_email_read_rounded
                                : notif['emailStatus'] == 'failed'
                                    ? Icons.error_outline_rounded
                                    : Icons.mail_outline_rounded,
                            size: 20,
                            color: notif['emailStatus'] == 'sent'
                                ? AppTheme.successGreen
                                : notif['emailStatus'] == 'failed'
                                    ? AppTheme.emergencyRed
                                    : Colors.blue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notif['emailStatus'] == 'sent'
                                      ? 'Email Notification Delivered'
                                      : notif['emailStatus'] == 'failed'
                                          ? 'Email Delivery Failed'
                                          : 'Email Delivery Queued',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: notif['emailStatus'] == 'sent'
                                        ? AppTheme.successGreen
                                        : notif['emailStatus'] == 'failed'
                                            ? AppTheme.emergencyRed
                                            : Colors.blue,
                                  ),
                                ),
                                if (notif['emailRecipient'] != null && notif['emailRecipient']!.isNotEmpty)
                                  Text(
                                    'Recipient: ${notif['emailRecipient']}',
                                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                                  ),
                                if (notif['emailStatus'] == 'failed' && notif['emailError'] != null)
                                  Text(
                                    'Error: ${notif['emailError']} (in-app record retained for retry)',
                                    style: TextStyle(fontSize: 11, color: AppTheme.emergencyRed.withValues(alpha: 0.9)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Complaint Title
                  Text(
                    complaint.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Category & Severity Chips
                  Row(
                    children: [
                      Chip(
                        avatar: const Icon(Icons.category_rounded, size: 14, color: AppTheme.primaryDark),
                        label: Text(complaint.category, style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        avatar: Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: complaint.severityColor,
                        ),
                        label: Text(
                          '${complaint.severity} Severity',
                          style: TextStyle(
                            fontSize: 12,
                            color: complaint.severityColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: complaint.severityColor.withValues(alpha: 0.1),
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Address Location Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 18, color: AppTheme.primaryBlue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          complaint.address,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Description Box
                  const Text(
                    'Complaint Description:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      complaint.description.isNotEmpty
                          ? complaint.description
                          : 'No description provided.',
                      style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                    ),
                  ),

                  // Image Preview (if image exists)
                  if ((complaint.beforeImageUrl ?? complaint.imageUrl).isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Reported Photo:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        complaint.beforeImageUrl ?? complaint.imageUrl,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 100,
                          color: Colors.grey.shade200,
                          child: const Center(child: Icon(Icons.image_not_supported_rounded, color: Colors.grey)),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Open Full Tracking & Photos Button
                  SizedBox(
                    width: double.infinity,
                    child: Builder(
                      builder: (ctx) {
                        final auth = Provider.of<AuthProvider>(ctx, listen: false);
                        final isCommunity = auth.selectedRole == 'community' || auth.currentUser?.role == 'community';
                        return ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                            if (isCommunity) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ComplaintVerificationScreen(complaint: complaint),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ComplaintTrackingScreen(complaint: complaint),
                                ),
                              );
                            }
                          },
                          icon: Icon(isCommunity ? Icons.search_rounded : Icons.photo_library_rounded, color: Colors.white, size: 18),
                          label: Text(
                            isCommunity ? 'Inspect & Verify Complaint' : 'View Full Tracking & Repair Photos',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isCommunity ? AppTheme.primaryDark : AppTheme.successGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Close Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _markAllAsRead(List<Map<String, String>> allNotifs) {
    setState(() {
      for (var n in allNotifs) {
        _readIds.add(n['id']!);
      }
    });

    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProv.currentUser?.id;
    if (userId != null && userId.isNotEmpty && SupabaseService.isConnected) {
      SupabaseService.markAllNotificationsAsRead(userId).catchError((e) {
        debugPrint('Error marking all notifications as read in Supabase: $e');
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All notifications marked as read'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final chatProv = Provider.of<ChatProvider>(context);
    final authProv = Provider.of<AuthProvider>(context, listen: false);

    final List<Map<String, String>> notifications = [];

    // 1. Add persistent notifications fetched from Supabase (primary source of truth)
    for (var pNotif in _persistedNotifications) {
      notifications.add(pNotif.toDisplayMap(_formatDateTime));
    }

    final currentUserId = authProv.currentUser?.id;
    final isReporter = authProv.selectedRole == 'reporter' || authProv.currentUser?.role == 'reporter';
    final isCommunity = authProv.selectedRole == 'community' || authProv.currentUser?.role == 'community';

    // 2. Dynamically compile real-time activity notifications from complaints
    for (var c in complaintProv.complaints) {
      final timeStr = _formatDateTime(c.updatedAt ?? c.createdAt);
      final isMyComplaint = currentUserId != null &&
          (c.reporterId.toLowerCase() == currentUserId.toLowerCase());

      // Add New Chat Message notifications
      final cMessages = chatProv.getMessagesForComplaint(c.complaintId);
      for (var msg in cMessages) {
        final isForMe = isReporter ? msg.isCommunity : msg.isReporter;
        // Reporters only see chats for their own complaints
        if (isForMe && (!isReporter || isMyComplaint)) {
          final chatId = 'notif_msg_${msg.messageId}';
          if (!notifications.any((n) => n['id'] == chatId)) {
            notifications.add({
              'id': chatId,
              'complaintId': c.complaintId,
              'title': '💬 New Message for ${c.complaintId}',
              'message': '${msg.senderName}: "${msg.messageText}"',
              'time': _formatDateTime(msg.createdAt),
              'type': 'chat',
            });
          }
        }
      }

      // Notification for New Complaint Submitted by Reporter (only for Community & Inspectors)
      if (isCommunity) {
        final newNotifId = 'notif_new_${c.complaintId}';
        if (!notifications.any((n) => n['id'] == newNotifId || (n['complaintId'] == c.complaintId && n['type'] == 'submitted'))) {
          notifications.add({
            'id': newNotifId,
            'complaintId': c.complaintId,
            'title': c.isEmergency ? '🚨 EMERGENCY: New Damage Reported!' : '📩 New Reporter Complaint',
            'message': 'Reporter ${c.reporterName} reported "${c.title}" at ${c.address}. Tap to inspect & verify.',
            'time': timeStr,
            'type': c.isEmergency ? 'emergency' : 'new_complaint',
          });
        }
        // Do NOT show reporter-specific status/progress updates to community users
        continue;
      }

      // If user is a Reporter, ONLY show status updates for complaints submitted by THIS reporter!
      if (!isMyComplaint && currentUserId != null) {
        continue;
      }

      // 1. Notification for Work Completion with Photo
      if (c.status == 'Completed') {
        final compId = 'notif_completed_${c.complaintId}';
        final alreadyPresent = notifications.any((n) =>
            n['id'] == compId ||
            ((n['complaintId'] == c.complaintId || n['message']?.contains(c.complaintId) == true) &&
                (n['type'] == 'completed' || n['status'] == 'Completed')));
        if (!alreadyPresent) {
          notifications.add({
            'id': compId,
            'complaintId': c.complaintId,
            'title': '🎉 Work 100% Completed!',
            'message': 'Community team completed repair work for ${c.complaintId} (${c.title}). Tap to view completed work photo & leave feedback!',
            'time': timeStr,
            'type': 'completed',
            'status': 'Completed',
          });
        }
      }

      // 2. Notifications for Progress Updates with Photos
      for (var u in c.updates) {
        if (u.status != 'Completed') {
          final updId = 'notif_upd_${u.updateId}';
          final alreadyPresent = notifications.any((n) =>
              n['id'] == updId ||
              ((n['complaintId'] == c.complaintId || n['message']?.contains(c.complaintId) == true) &&
                  n['type'] == 'work' &&
                  (n['message']?.contains(u.progressNote) == true ||
                      (u.progressNote.isEmpty && n['status'] == u.status))));
          if (!alreadyPresent) {
            notifications.add({
              'id': updId,
              'complaintId': c.complaintId,
              'title': u.imageUrl != null ? '📸 Work Progress Photo Uploaded' : '🚧 Repair Work Progress Update',
              'message': '${u.communityUserName} updated ${c.complaintId}: ${u.progressNote}',
              'time': _formatDateTime(u.createdAt),
              'type': 'work',
              'status': u.status,
            });
          }
        }
      }

      // 3. Notifications for Status (Accepted, Work Started, Verified, Rejected)
      if (c.status == 'Rejected') {
        final rejId = 'notif_rej_${c.complaintId}';
        final alreadyPresent = notifications.any((n) =>
            n['id'] == rejId ||
            ((n['complaintId'] == c.complaintId || n['message']?.contains(c.complaintId) == true) &&
                (n['type'] == 'rejected' || n['status'] == 'Rejected')));
        if (!alreadyPresent) {
          notifications.add({
            'id': rejId,
            'complaintId': c.complaintId,
            'title': '❌ Complaint / Work Rejected',
            'message': 'Your report ${c.complaintId} (${c.title}) was audited and marked as Rejected/Fake by community inspectors.',
            'time': timeStr,
            'type': 'rejected',
            'status': 'Rejected',
          });
        }
      } else if (c.status == 'Accepted' || c.status == 'Work Started' || c.status == 'Repair In Progress') {
        final workId = 'notif_work_${c.complaintId}';
        final alreadyPresent = notifications.any((n) =>
            n['id'] == workId ||
            ((n['complaintId'] == c.complaintId || n['message']?.contains(c.complaintId) == true) &&
                (n['type'] == 'work' || n['type'] == 'accepted' || n['status'] == 'Accepted' || n['status'] == 'Repair In Progress')));
        if (!alreadyPresent) {
          notifications.add({
            'id': workId,
            'complaintId': c.complaintId,
            'title': '🚧 Repair Work Accepted & Started',
            'message': '${c.communityUserName ?? "Community Crew"} accepted and started repair work on ${c.complaintId}.',
            'time': timeStr,
            'type': 'work',
            'status': c.status,
          });
        }
      } else if (c.status == 'Verified') {
        final verId = 'notif_ver_${c.complaintId}';
        final alreadyPresent = notifications.any((n) =>
            n['id'] == verId ||
            ((n['complaintId'] == c.complaintId || n['message']?.contains(c.complaintId) == true) &&
                (n['type'] == 'verified' || n['status'] == 'Verified')));
        if (!alreadyPresent) {
          notifications.add({
            'id': verId,
            'complaintId': c.complaintId,
            'title': '✅ Complaint Verified!',
            'message': 'Your report ${c.complaintId} (${c.title}) was verified by the community team.',
            'time': timeStr,
            'type': 'verified',
            'status': 'Verified',
          });
        }
      }
    }

    // 3. Include static initial notifications only in offline / demo guest mode
    if (authProv.currentUser == null && notifications.isEmpty) {
      for (var initNotif in _initialNotifications) {
        if (!notifications.any((n) => n['complaintId'] == initNotif['complaintId'])) {
          notifications.add(initNotif);
        }
      }
    }

    final unreadCount = notifications.where((n) => !_readIds.contains(n['id'])).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Notifications'),
              if (unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Notifications',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadPersistedNotifications,
          ),
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: () => _markAllAsRead(notifications),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Read all'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryDark,
              ),
            ),
        ],
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: RefreshIndicator(
          onRefresh: _loadPersistedNotifications,
          child: _isLoadingPersisted && notifications.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.notifications_off_outlined, size: 60, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No notifications yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final n = notifications[index];
                        final isUnread = !_readIds.contains(n['id']);
                        final color = _getColor(n['type']!);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            borderRadius: 18,
                            padding: const EdgeInsets.all(16),
                            onTap: () => _handleNotificationTap(n),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(_getIcon(n['type']!), color: color, size: 24),
                                    ),
                                    if (isUnread)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryBlue,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 1.5),
                                          ),
                                        ),
                                      ),
                                  ],
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
                                              n['title']!,
                                              style: TextStyle(
                                                fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                                                fontSize: 15,
                                                color: isUnread ? Colors.black : Colors.black87,
                                              ),
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.access_time_rounded,
                                                size: 12,
                                                color: isUnread ? AppTheme.primaryBlue : Colors.grey.shade600,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                n['time']!,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isUnread ? AppTheme.primaryBlue : Colors.grey.shade700,
                                                  fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        n['message']!,
                                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                                      ),
                                      // Email delivery indicator badge
                                      if (n['emailStatus'] == 'sent') ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.mark_email_read_rounded, size: 13, color: AppTheme.successGreen),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'Email notification delivered to reporter',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.successGreen,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else if (n['emailStatus'] == 'failed') ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.error_outline_rounded, size: 13, color: AppTheme.emergencyRed),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'Email delivery failed (in-app alert preserved)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.emergencyRed,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: isUnread ? AppTheme.primaryBlue : Colors.grey.shade400,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}






