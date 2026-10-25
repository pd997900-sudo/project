import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/complaint_model.dart';
import '../providers/auth_provider.dart';
import '../providers/complaint_provider.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';
import 'view_voters_dialog.dart';

/// Community Poll-Based Complaint Verification Widget
/// Title: "Is this reported issue genuine?"
/// Options: "🟢 Genuine Issue" & "🔴 Fake Issue"
/// Strictly enforces 500-meter GPS location-based voting restriction.
class CommunityVerificationPollCard extends StatefulWidget {
  final Complaint complaint;
  final bool showHeader;
  final bool isCompact;
  final bool? allowVoting;

  const CommunityVerificationPollCard({
    super.key,
    required this.complaint,
    this.showHeader = true,
    this.isCompact = false,
    this.allowVoting,
  });

  @override
  State<CommunityVerificationPollCard> createState() => _CommunityVerificationPollCardState();
}

class _CommunityVerificationPollCardState extends State<CommunityVerificationPollCard> {
  static const double maxVotingRadiusMeters = 500.0;

  bool _isSubmitting = false;
  bool _isCheckingLocation = true;
  double? _userLatitude;
  double? _userLongitude;
  double? _distanceMeters;
  String? _locationStatusMessage;
  bool _hasLocationPermissionError = false;
  bool _hasGpsError = false;
  bool _hasInvalidComplaintCoords = false;

  @override
  void initState() {
    super.initState();
    final isRejected = widget.complaint.isRejected;
    final isWorkStarted = widget.complaint.isWorkStartedOrBeyond;
    if ((widget.allowVoting ?? true) && !isRejected && !isWorkStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkLocationAndDistance(showLoading: true);
      });
    } else {
      _isCheckingLocation = false;
    }
  }

  @override
  void didUpdateWidget(covariant CommunityVerificationPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isRejected = widget.complaint.isRejected;
    if ((widget.allowVoting ?? true) &&
        !isRejected &&
        (oldWidget.complaint.complaintId != widget.complaint.complaintId ||
            oldWidget.complaint.latitude != widget.complaint.latitude ||
            oldWidget.complaint.longitude != widget.complaint.longitude ||
            oldWidget.complaint.status != widget.complaint.status)) {
      _checkLocationAndDistance(showLoading: true);
    } else if (isRejected) {
      _isCheckingLocation = false;
    }
  }

  /// Rechecks current GPS location and calculates distance to complaint coordinates
  Future<void> _checkLocationAndDistance({bool showLoading = true}) async {
    // 1. Verify complaint has valid coordinates
    if (!widget.complaint.hasValidCoordinates) {
      if (mounted) {
        setState(() {
          _hasInvalidComplaintCoords = true;
          _distanceMeters = null;
          _isCheckingLocation = false;
          _locationStatusMessage =
              'Current location is required to vote. Complaint coordinates are invalid or unavailable.';
        });
      }
      return;
    }

    if (showLoading && mounted) {
      setState(() {
        _isCheckingLocation = true;
        _locationStatusMessage = null;
        _hasLocationPermissionError = false;
        _hasGpsError = false;
        _hasInvalidComplaintCoords = false;
      });
    }

    try {
      // 2. Check location services
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _hasGpsError = true;
            _distanceMeters = null;
            _isCheckingLocation = false;
            _locationStatusMessage =
                'Current location is required to vote. Please enable GPS location services.';
          });
        }
        return;
      }

      // 3. Check and request location permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _hasLocationPermissionError = true;
            _distanceMeters = null;
            _isCheckingLocation = false;
            _locationStatusMessage =
                'Current location is required to vote. Please allow location access in your device or browser settings.';
          });
        }
        return;
      }

      // 4. Acquire fresh GPS position (highest accuracy)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      // Check GPS accuracy: show helpful retry message if reading is too inaccurate
      if (position.accuracy > (kIsWeb ? 200.0 : 100.0)) {
        if (mounted) {
          setState(() {
            _userLatitude = position.latitude;
            _userLongitude = position.longitude;
            _distanceMeters = null;
            _isCheckingLocation = false;
            _locationStatusMessage =
                'GPS accuracy is weak (±${position.accuracy.toStringAsFixed(0)} m). Please step into an open area or enable high-accuracy GPS and try again.';
          });
        }
        return;
      }

      final distance = SupabaseService.calculateDistanceMeters(
        position.latitude,
        position.longitude,
        widget.complaint.latitude,
        widget.complaint.longitude,
      );

      if (mounted) {
        setState(() {
          _userLatitude = position.latitude;
          _userLongitude = position.longitude;
          _distanceMeters = distance;
          _isCheckingLocation = false;
          _hasLocationPermissionError = false;
          _hasGpsError = false;
          _hasInvalidComplaintCoords = false;
          _locationStatusMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Location check error: $e');
      if (mounted) {
        setState(() {
          _distanceMeters = null;
          _isCheckingLocation = false;
          _locationStatusMessage =
              'Current location is required to vote. Unable to determine current GPS position.';
        });
      }
    }
  }

  Future<void> _handleVote(BuildContext context, bool isReal) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    final currentUser = auth.currentUser;
    if (widget.complaint.isRejected) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('This complaint was rejected as fake by the community. Voting is closed.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.emergencyRed,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (widget.complaint.isCompleted) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Voting closed — work completed.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.primaryDark,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (widget.complaint.isWorkStartedOrBeyond) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Voting closed — work has started.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.primaryDark,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (currentUser == null || currentUser.id.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('⚠️ You must be logged in to vote on complaints.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.emergencyRed,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!widget.complaint.hasValidCoordinates) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('⚠️ Current location is required to vote. Complaint coordinates are invalid or unavailable.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.emergencyRed,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    // Requirement 6: Recheck the user's current GPS location immediately before submitting a vote
    Position? freshPosition;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'GPS location service is disabled.';
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw 'Location permission is denied.';
      }

      freshPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Error getting fresh GPS position before voting: $e');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _locationStatusMessage = 'Current location is required to vote. Please enable GPS and allow location access.';
      });
      messenger.showSnackBar(
        SnackBar(
          content: const Text('⚠️ Current location is required to vote. Please enable GPS and grant location permission.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.emergencyRed,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Handle GPS accuracy carefully: show a helpful retry message if reading is too inaccurate
    if (freshPosition.accuracy > (kIsWeb ? 200.0 : 100.0)) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('GPS accuracy is weak (±${freshPosition.accuracy.toStringAsFixed(0)} m). Please step into an open area or enable high-accuracy GPS and try again.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.emergencyRed,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Calculate fresh distance using Haversine formula
    final freshDistance = SupabaseService.calculateDistanceMeters(
      freshPosition.latitude,
      freshPosition.longitude,
      widget.complaint.latitude,
      widget.complaint.longitude,
    );

    _userLatitude = freshPosition.latitude;
    _userLongitude = freshPosition.longitude;
    _distanceMeters = freshDistance;

    // Enforce 500-meter distance restriction
    if (freshDistance > maxVotingRadiusMeters) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Location mismatch: Voting is available only within 500 meters of the reported issue. (Current distance: ${_distanceMeters! < 1000 ? '${_distanceMeters!.toStringAsFixed(0)} m' : '${(_distanceMeters! / 1000).toStringAsFixed(1)} km'})'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: AppTheme.emergencyRed,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final res = await complaintProv.castCommunityPollVote(
      complaintId: widget.complaint.complaintId,
      userId: currentUser.id,
      userEmail: currentUser.email,
      isReal: isReal,
      userLat: freshPosition.latitude,
      userLng: freshPosition.longitude,
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    messenger.hideCurrentSnackBar();

    if (res.success) {
      if (SupabaseService.isConnected) {
        complaintProv.refreshComplaints();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isReal ? Icons.check_circle_rounded : Icons.report_problem_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isReal
                      ? 'Vote saved: 🟢 Genuine Issue. Thank you!'
                      : 'Vote saved: 🔴 Fake Issue. Report flagged.',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: isReal ? AppTheme.successGreen : AppTheme.emergencyRed,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      debugPrint('❌ Supabase Save Vote Error details: ${res.errorMessage}');
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  res.errorMessage ?? 'Unable to save vote. Database permission error.',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () => messenger.hideCurrentSnackBar(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);

    final isRejected = widget.complaint.isRejected;
    final isCompleted = widget.complaint.isCompleted;
    final isWorkStarted = widget.complaint.isWorkStartedOrBeyond && !isCompleted;

    // Voting is enabled if allowVoting is true, complaint is NOT rejected, and work has NOT started
    final canVote = (widget.allowVoting ?? true) && !isRejected && !widget.complaint.isWorkStartedOrBeyond;

    // Get current user ID, Email & Device Voter ID
    final currentUserId = auth.currentUser?.id ?? '';
    final currentUserEmail = auth.currentUser?.email ?? '';
    final deviceVoterId = complaintProv.deviceVoterId ?? '';

    final hasVoted = widget.complaint.isVotedBy(currentUserId, currentUserEmail, deviceVoterId);
    final rawVote = widget.complaint.getVoteOf(currentUserId, currentUserEmail, deviceVoterId);

    final isGenuineVote = rawVote == 'Genuine Issue' || rawVote == 'real' || rawVote == 'genuine';
    final isFakeVote = rawVote == 'Fake Issue' || rawVote == 'fake';

    final totalVotes = widget.complaint.totalVotes;
    final realPct = widget.complaint.realPercentage;
    final fakePct = widget.complaint.fakePercentage;

    final isWithin500m = _distanceMeters != null && _distanceMeters! <= maxVotingRadiusMeters;
    final isOutside500m = _distanceMeters != null && _distanceMeters! > maxVotingRadiusMeters;

    return GlassCard(
      borderRadius: 20,
      padding: EdgeInsets.all(widget.isCompact ? 14 : 18),
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.how_to_vote_rounded, color: AppTheme.primaryBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Is this reported issue genuine?',
                    style: TextStyle(
                      fontSize: widget.isCompact ? 13 : 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildConsensusBadge(),
              ],
            ),
            if (canVote) ...[
              const SizedBox(height: 6),
              Text(
                'Vote to help verify this complaint and prioritize repair work:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 14),
          ],

          // Community Verification Result Banner
          _buildConsensusBanner(),
          const SizedBox(height: 14),

          // Final rejected status notice: permanently close voting and display clear rejection message
          if (isRejected) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.emergencyRed.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.4), width: 1.2),
              ),
              child: const Row(
                children: [
                  Icon(Icons.block_rounded, color: AppTheme.emergencyRed, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This complaint was rejected as fake by the community. Voting is closed.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.emergencyRed,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isCompleted) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF00C853).withOpacity(0.35), width: 1.2),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF00C853), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Voting closed — work completed.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isWorkStarted) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.35), width: 1.2),
              ),
              child: const Row(
                children: [
                  Icon(Icons.construction_rounded, color: AppTheme.primaryBlue, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Voting closed — work has started.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (canVote) ...[
            if (!widget.complaint.hasValidCoordinates || _hasInvalidComplaintCoords) ...[
              // Invalid Complaint Coordinates Warning Card
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade400, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_off_rounded, color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Current location is required to vote. Complaint coordinates are invalid or unavailable.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF795548)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_locationStatusMessage != null) ...[
              // Permission Denied or GPS Unavailable Card
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade400, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.near_me_disabled_rounded, color: Colors.amber.shade900, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locationStatusMessage!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF795548)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _checkLocationAndDistance(showLoading: true),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Check Location', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_isCheckingLocation) ...[
              // Location Checking Indicator
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Verifying GPS distance to reported issue...',
                        style: TextStyle(fontSize: 12, color: AppTheme.primaryDark),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isOutside500m) ...[
              // Outside 500 m Restriction Notice Card
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFB74D), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_off_rounded, color: Color(0xFFE65100), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Location mismatch: Voting is available only within 500 meters of the reported issue.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You are currently ${_distanceMeters! < 1000 ? '${_distanceMeters!.toStringAsFixed(0)} m' : '${(_distanceMeters! / 1000).toStringAsFixed(1)} km'} away. Move closer to the issue location (within 500 meters) to verify and cast your vote.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _checkLocationAndDistance(showLoading: true),
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Recheck Distance', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isWithin500m) ...[
              // Within 500 m Proximity Badge
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.near_me_rounded, color: Color(0xFF1B5E20), size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Within 500 m (${_distanceMeters! < 1000 ? '${_distanceMeters!.toStringAsFixed(0)} m' : '${(_distanceMeters! / 1000).toStringAsFixed(2)} km'} away) — Voting enabled',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                      ),
                    ),
                    InkWell(
                      onTap: () => _checkLocationAndDistance(showLoading: false),
                      child: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF1B5E20)),
                    ),
                  ],
                ),
              ),

              // Voting Action Buttons (Available within 500 m)
              Row(
                children: [
                  // Genuine Issue Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (hasVoted || _isSubmitting)
                          ? null
                          : () => _handleVote(context, true),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(isGenuineVote ? '✅' : '🟢', style: const TextStyle(fontSize: 15)),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isGenuineVote ? 'Voted Genuine' : 'Genuine Issue',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isGenuineVote
                            ? const Color(0xFF00E676)
                            : (hasVoted ? Colors.grey.shade300 : const Color(0xFF00E676)),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: isGenuineVote
                            ? const Color(0xFF00E676)
                            : Colors.grey.shade300,
                        disabledForegroundColor: isGenuineVote ? Colors.white : Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: isGenuineVote ? 3 : 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Fake Issue Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (hasVoted || _isSubmitting)
                          ? null
                          : () => _handleVote(context, false),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(isFakeVote ? '❌' : '🔴', style: const TextStyle(fontSize: 15)),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isFakeVote ? 'Voted Fake' : 'Fake Issue',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFakeVote
                            ? AppTheme.emergencyRed
                            : (hasVoted ? Colors.grey.shade300 : AppTheme.emergencyRed),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: isFakeVote
                            ? AppTheme.emergencyRed
                            : Colors.grey.shade300,
                        disabledForegroundColor: isFakeVote ? Colors.white : Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: isFakeVote ? 3 : 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
          ],

          // Poll Results Progress Bar & Percentage Display (Always Visible)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 4,
                  spacing: 8,
                  children: [
                    Text(
                      '🟢 Genuine Issue: ${widget.complaint.realVotes} (${realPct.toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                    ),
                    Text(
                      '🔴 Fake Issue: ${widget.complaint.fakeVotes} (${fakePct.toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.emergencyRed),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Clean Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 12,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        // Fake Issue Bar (Red) or Grey track if 0 votes
                        Container(color: totalVotes == 0 ? Colors.grey.shade300 : AppTheme.emergencyRed.withOpacity(0.85)),
                        // Genuine Issue Bar (Green)
                        if (totalVotes > 0)
                          FractionallySizedBox(
                            widthFactor: (realPct / 100.0).clamp(0.0, 1.0),
                            child: Container(color: const Color(0xFF00E676)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 6,
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                          ),
                          child: Text(
                            'Genuine Votes: ${widget.complaint.realVotes}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.emergencyRed.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.4)),
                          ),
                          child: Text(
                            'Fake Votes: ${widget.complaint.fakeVotes}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.emergencyRed),
                          ),
                        ),
                      ],
                    ),
                    if (hasVoted)
                      Text(
                        '✓ You voted: ${isGenuineVote ? 'Genuine' : 'Fake'}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // View Voters Button (Displayed for all users)
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final freshComplaint = complaintProv.getComplaintById(widget.complaint.complaintId) ?? widget.complaint;
                ViewVotersDialog.show(context, freshComplaint);
              },
              icon: const Icon(Icons.people_alt_rounded, size: 18, color: AppTheme.primaryBlue),
              label: const Text(
                'View Voters',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlue,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppTheme.primaryBlue, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: AppTheme.primaryBlue.withOpacity(0.04),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsensusBanner() {
    final bool isRejected = widget.complaint.isRejected;
    final totalVotes = widget.complaint.totalVotes;
    final isGenuineHigher = widget.complaint.realVotes >= widget.complaint.fakeVotes && totalVotes > 0;
    final isFakeHigher = widget.complaint.fakeVotes > widget.complaint.realVotes && totalVotes > 0;

    String consensusText;
    String prioritizationText;
    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;

    if (isRejected) {
      consensusText = 'Community Decision: Rejected as Fake Issue';
      prioritizationText = '❌ Rejected by community inspectors. Voting permanently closed.';
      bgColor = AppTheme.emergencyRed.withOpacity(0.12);
      borderColor = AppTheme.emergencyRed;
      textColor = AppTheme.emergencyRed;
      icon = Icons.cancel_rounded;
    } else if (isGenuineHigher) {
      consensusText = 'Community Consensus: Genuine Issue';
      prioritizationText = '⚡ Community Verified — Eligible for repair prioritization';
      bgColor = const Color(0xFF00E676).withOpacity(0.12);
      borderColor = const Color(0xFF00E676);
      textColor = const Color(0xFF1B5E20);
      icon = Icons.verified_rounded;
    } else if (isFakeHigher) {
      consensusText = 'Community Consensus: Fake Issue';
      prioritizationText = '⚠️ Community Disputed — Not prioritized for repair';
      bgColor = AppTheme.emergencyRed.withOpacity(0.12);
      borderColor = AppTheme.emergencyRed;
      textColor = AppTheme.emergencyRed;
      icon = Icons.report_problem_rounded;
    } else {
      consensusText = 'Community Consensus: Verification Pending';
      prioritizationText = '⏳ Awaiting community votes for prioritization';
      bgColor = AppTheme.primaryBlue.withOpacity(0.08);
      borderColor = AppTheme.primaryBlue.withOpacity(0.4);
      textColor = AppTheme.primaryDark;
      icon = Icons.pending_actions_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  consensusText,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
                ),
                const SizedBox(height: 2),
                Text(
                  prioritizationText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textColor.withOpacity(0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsensusBadge() {
    if (widget.complaint.isRejected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.emergencyRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.emergencyRed),
        ),
        child: const Text('Voting Closed', style: TextStyle(color: AppTheme.emergencyRed, fontSize: 10, fontWeight: FontWeight.bold)),
      );
    }
    final totalVotes = widget.complaint.totalVotes;
    if (widget.complaint.realVotes >= widget.complaint.fakeVotes && totalVotes > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF00E676).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF00E676)),
        ),
        child: const Text('Community Verified', style: TextStyle(color: Color(0xFF1B5E20), fontSize: 10, fontWeight: FontWeight.bold)),
      );
    } else if (widget.complaint.fakeVotes > widget.complaint.realVotes && totalVotes > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.emergencyRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.emergencyRed),
        ),
        child: const Text('Community Disputed', style: TextStyle(color: AppTheme.emergencyRed, fontSize: 10, fontWeight: FontWeight.bold)),
      );
    } else if (widget.complaint.isWorkStartedOrBeyond) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.emergencyRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.emergencyRed),
        ),
        child: const Text('Voting Closed', style: TextStyle(color: AppTheme.emergencyRed, fontSize: 10, fontWeight: FontWeight.bold)),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.5)),
        ),
        child: const Text('Voting Open', style: TextStyle(color: AppTheme.primaryBlue, fontSize: 10, fontWeight: FontWeight.bold)),
      );
    }
  }
}
