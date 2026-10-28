import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/complaint_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/real_time_camera_dialog.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/location_service.dart';
import '../../services/supabase_service.dart';

class WorkProgressScreen extends StatefulWidget {
  final Complaint complaint;

  const WorkProgressScreen({super.key, required this.complaint});

  @override
  State<WorkProgressScreen> createState() => _WorkProgressScreenState();
}

class _WorkProgressScreenState extends State<WorkProgressScreen> {
  final _noteController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late double _workPercentage;
  String? _progressImageUrl;
  GeotagLocation? _progressGeotagLocation;
  bool _isSubmitting = false;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  void _showFeedbackSnackBar(
    String message, {
    Color backgroundColor = AppTheme.primaryDark,
    Duration duration = const Duration(seconds: 4),
  }) {
    final snackBar = SnackBar(
      content: Text(
        message,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: backgroundColor,
      duration: duration,
    );
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(snackBar);
    } else if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

  void _showLocationMismatchSnackBar() {
    debugPrint('🚨 [LOCATION MISMATCH SNACKBAR TRIGGERED] Displaying visible red SnackBar on current screen');
    _showFeedbackSnackBar(
      'Location mismatch: capture the progress photo within 500 metres of the original reported complaint location.',
      backgroundColor: AppTheme.emergencyRed,
      duration: const Duration(seconds: 5),
    );
  }

  @override
  void initState() {
    super.initState();
    final initialProgress = widget.complaint.progressPercentage;
    _workPercentage = (initialProgress.isNaN || initialProgress.isInfinite)
        ? 0.0
        : initialProgress.clamp(0.0, 100.0);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _removeProgressImage() {
    setState(() {
      _progressImageUrl = null;
      _progressGeotagLocation = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progress photo removed.'),
        backgroundColor: AppTheme.primaryDark,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Obtain actual GPS coordinates and accuracy at the moment of photo capture
  Future<GeotagLocation?> _acquireCurrentGpsLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Notice: GPS location services disabled.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      final address = await LocationService.reverseGeocode(position.latitude, position.longitude);

      return GeotagLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        address: address,
        timestamp: DateTime.now(),
        status: LocationStatus.ready,
        statusMessage: 'GPS location acquired',
      );
    } catch (e) {
      debugPrint('Notice acquiring fresh GPS location: $e');
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          final address = await LocationService.reverseGeocode(lastPos.latitude, lastPos.longitude);
          return GeotagLocation(
            latitude: lastPos.latitude,
            longitude: lastPos.longitude,
            accuracy: lastPos.accuracy,
            address: address,
            timestamp: DateTime.now(),
            status: LocationStatus.ready,
            statusMessage: 'Last known GPS location acquired',
          );
        }
      } catch (_) {}
      return null;
    }
  }

  Future<void> _pickImageFromCamera() async {
    if (kIsWeb) {
      _openLiveCameraDialog();
      return;
    }

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null) {
        var geotagLoc = await _acquireCurrentGpsLocation();
        if (geotagLoc != null && Complaint.isValidCoordinates(geotagLoc.latitude, geotagLoc.longitude)) {
          if (geotagLoc.address.isEmpty ||
              geotagLoc.address == 'Location Unavailable' ||
              geotagLoc.address == 'Location' ||
              geotagLoc.address.startsWith('Detecting')) {
            try {
              final resolved = await LocationService.reverseGeocode(geotagLoc.latitude, geotagLoc.longitude);
              if (resolved.isNotEmpty && !resolved.startsWith('Detecting')) {
                geotagLoc = geotagLoc.copyWith(address: resolved);
              }
            } catch (_) {}
          }
        }
        final bytes = await picked.readAsBytes();
        final mimeType = picked.mimeType ?? 'image/jpeg';
        final imageUrl = Uri.dataFromBytes(bytes, mimeType: mimeType).toString();
        if (mounted) {
          setState(() {
            _progressImageUrl = imageUrl;
            _progressGeotagLocation = geotagLoc;
          });
          if (geotagLoc != null && Complaint.isValidCoordinates(geotagLoc.latitude, geotagLoc.longitude)) {
            _showFeedbackSnackBar(
              'Live progress photo & GPS coordinates captured successfully!',
              backgroundColor: AppTheme.successGreen,
              duration: const Duration(seconds: 2),
            );
          } else {
            _showFeedbackSnackBar(
              'Progress photo captured, but GPS location was unavailable. Please ensure GPS is enabled.',
              backgroundColor: const Color(0xFFF59E0B),
              duration: const Duration(seconds: 4),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Notice capturing photo with native camera: $e');
      if (mounted) {
        _openLiveCameraDialog();
      }
    }
  }

  void _openLiveCameraDialog() {
    showDialog(
      context: context,
      builder: (camCtx) => RealTimeCameraDialog(
        isProfilePhoto: false,
        category: 'WorkProgress',
        onPhotoCaptured: (capturedUrl, [geotagLoc]) async {
          GeotagLocation? loc;
          if (geotagLoc != null &&
              geotagLoc is GeotagLocation &&
              Complaint.isValidCoordinates(geotagLoc.latitude, geotagLoc.longitude)) {
            loc = geotagLoc;
          } else {
            loc = await _acquireCurrentGpsLocation();
          }

          if (loc != null && Complaint.isValidCoordinates(loc.latitude, loc.longitude)) {
            if (loc.address.isEmpty ||
                loc.address == 'Location Unavailable' ||
                loc.address == 'Location' ||
                loc.address.startsWith('Detecting')) {
              try {
                final resolved = await LocationService.reverseGeocode(loc.latitude, loc.longitude);
                if (resolved.isNotEmpty && !resolved.startsWith('Detecting')) {
                  loc = loc.copyWith(address: resolved);
                }
              } catch (_) {}
            }
          }

          if (mounted) {
            setState(() {
              _progressImageUrl = capturedUrl;
              _progressGeotagLocation = loc;
            });
            if (loc != null && Complaint.isValidCoordinates(loc.latitude, loc.longitude)) {
              _showFeedbackSnackBar(
                'Live camera photo & GPS coordinates captured successfully!',
                backgroundColor: AppTheme.successGreen,
                duration: const Duration(seconds: 2),
              );
            } else {
              _showFeedbackSnackBar(
                'Live photo captured, but GPS location was unavailable. Please ensure GPS is enabled.',
                backgroundColor: const Color(0xFFF59E0B),
                duration: const Duration(seconds: 4),
              );
            }
          }
        },
      ),
    );
  }

  void _showImageSourcePicker() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt_rounded, color: AppTheme.primaryBlue),
            SizedBox(width: 10),
            Text('Attach Progress Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryBlue,
                child: Icon(Icons.camera_alt_rounded, color: Colors.white),
              ),
              title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Capture a live progress photo using camera'),
              onTap: () {
                Navigator.pop(dialogCtx);
                _pickImageFromCamera();
              },
            ),

            if (_progressImageUrl != null) ...[
              const Divider(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: const CircleAvatar(
                  backgroundColor: Colors.red,
                  child: Icon(Icons.delete_outline_rounded, color: Colors.white),
                ),
                title: const Text('Delete / Remove Photo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                subtitle: const Text('Remove current attached photo'),
                onTap: () {
                  Navigator.pop(dialogCtx);
                  _removeProgressImage();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(String rawUrl, {BoxFit fit = BoxFit.contain, double? height, double? width}) {
    final url = rawUrl.trim();
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          fit: fit,
          width: width,
          height: height,
        );
      } catch (_) {}
    }
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => Container(
        height: height ?? 200,
        color: Colors.grey.shade200,
        child: const Center(child: Icon(Icons.image_not_supported_rounded, color: Colors.grey, size: 40)),
      ),
    );
  }

  void _sendProgressUpdate() async {
    if (_isSubmitting) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait, your progress update is being submitted...'),
          backgroundColor: AppTheme.primaryDark,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final noteText = _noteController.text.trim();

    // 1. Validate inputs: percentage and progress notes (photo is optional)
    if (noteText.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter progress log notes before sending.'),
          backgroundColor: AppTheme.emergencyRed,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_workPercentage < 0 || _workPercentage > 100) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid work percentage (0% to 100%).'),
          backgroundColor: AppTheme.emergencyRed,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
    final authProv = Provider.of<AuthProvider>(context, listen: false);

    final currentComplaint = complaintProv.complaints.firstWhere(
      (c) => c.complaintId.trim().toLowerCase() == widget.complaint.complaintId.trim().toLowerCase(),
      orElse: () => widget.complaint,
    );

    // Requirement 7: Ensure a rejected complaint cannot receive repair progress updates
    if (currentComplaint.isRejected) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This complaint was rejected as fake and cannot receive repair progress updates.'),
          backgroundColor: AppTheme.emergencyRed,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // 2. Validate location ONLY when sending work progress with a photo
      GeotagLocation? submissionLocation;

      if (_progressImageUrl != null && _progressImageUrl!.trim().isNotEmpty) {
        // Resolve reference coordinates: must always be the original Reporter complaint's saved latitude and longitude
        double refLat = currentComplaint.latitude;
        double refLng = currentComplaint.longitude;

        if (!Complaint.isValidCoordinates(refLat, refLng) && Complaint.isValidCoordinates(widget.complaint.latitude, widget.complaint.longitude)) {
          refLat = widget.complaint.latitude;
          refLng = widget.complaint.longitude;
        }

        // Only query Supabase if in-memory coordinates are missing or invalid
        if (!Complaint.isValidCoordinates(refLat, refLng) && SupabaseService.isConnected) {
          try {
            final reportRow = await SupabaseService.getReportById(currentComplaint.complaintId) ??
                await SupabaseService.getReportById(widget.complaint.complaintId);
            if (reportRow != null) {
              double rLat = 0.0;
              double rLng = 0.0;
              final rawLat = reportRow['latitude'] ?? reportRow['lat'];
              final rawLng = reportRow['longitude'] ?? reportRow['lng'] ?? reportRow['lon'];
              if (rawLat is num) {
                rLat = rawLat.toDouble();
              } else if (rawLat is String) {
                rLat = double.tryParse(rawLat.trim()) ?? 0.0;
              }
              if (rawLng is num) {
                rLng = rawLng.toDouble();
              } else if (rawLng is String) {
                rLng = double.tryParse(rawLng.trim()) ?? 0.0;
              }
              if (rLat.abs() > 90.0 && rLng.abs() <= 90.0) {
                final temp = rLat;
                rLat = rLng;
                rLng = temp;
              }
              if (rLat != 0.0 || rLng != 0.0) {
                refLat = rLat;
                refLng = rLng;
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Notice resolving reference complaint coordinates from Supabase: $e');
            }
          }
        }

        if (refLat.abs() > 90.0 && refLng.abs() <= 90.0) {
          final temp = refLat;
          refLat = refLng;
          refLng = temp;
        }

        if (!Complaint.isValidCoordinates(refLat, refLng)) {
          if (kDebugMode) {
            debugPrint('⚠️ [LOCATION REJECTION] Original complaint GPS location is missing or invalid: ($refLat, $refLng)');
          }
          if (mounted) {
            setState(() {
              _isSubmitting = false;
            });
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Original complaint GPS location is missing. Unable to validate photo location.'),
                backgroundColor: AppTheme.emergencyRed,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        // Read the captured photo's actual GPS coordinates from the photo's saved geotag metadata/state.
        // Never substitute the Community user's later/current location for the original photo's captured location.
        final GeotagLocation? photoLocation = _progressGeotagLocation;
        double photoLat = photoLocation?.latitude ?? 0.0;
        double photoLng = photoLocation?.longitude ?? 0.0;
        if (photoLat.abs() > 90.0 && photoLng.abs() <= 90.0) {
          final temp = photoLat;
          photoLat = photoLng;
          photoLng = temp;
        }

        final bool hasValidPhotoCoords = photoLocation != null &&
            Complaint.isValidCoordinates(photoLat, photoLng);

        if (!hasValidPhotoCoords) {
          if (kDebugMode) {
            debugPrint('⚠️ [LOCATION REJECTION] Progress photo GPS coordinates missing or unavailable: ($photoLat, $photoLng)');
          }
          if (mounted) {
            setState(() {
              _isSubmitting = false;
            });
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Progress photo GPS coordinates are unavailable. Please ensure location permissions are enabled and capture the photo at the repair site.'),
                backgroundColor: AppTheme.emergencyRed,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        // Calculate distance between progress photo capture coordinates and original complaint coordinates using Haversine formula
        final double photoDistance = SupabaseService.calculateDistanceMeters(
          photoLat,
          photoLng,
          refLat,
          refLng,
        );

        if (kDebugMode) {
          debugPrint('📍 [WORK PROGRESS LOCATION VALIDATION]');
          debugPrint('Complaint Reference: ($refLat, $refLng)');
          debugPrint('Photo Capture Location: ($photoLat, $photoLng)');
          debugPrint('Photo Accuracy: ±${photoLocation.accuracy.toStringAsFixed(1)}m');
        }
        debugPrint('📏 [DEBUG LOCATION VALIDATION] Measured distance: ${photoDistance.toStringAsFixed(1)}m, Allowed threshold: 500.0m');

        // Enforce 500 metres location restriction: photo capture location MUST be within 500 metres of original complaint
        if (photoDistance > 500.0) {
          debugPrint('⚠️ [DEBUG BRANCH: LOCATION MISMATCH DETECTED] Distance (${photoDistance.toStringAsFixed(1)}m) > 500.0m. Location mismatch: photo was not captured within 500m of complaint.');
          if (mounted) {
            setState(() {
              _isSubmitting = false;
            });
            _showLocationMismatchSnackBar();
          }
          return;
        } else {
          debugPrint('✅ [DEBUG BRANCH: WITHIN 500M] Distance (${photoDistance.toStringAsFixed(1)}m) <= 500.0m. Location valid, proceeding with submission.');
        }

        // Resolve readable address from coordinates if not already present
        String photoAddress = photoLocation.address;
        if (photoAddress.isEmpty ||
            photoAddress == 'Location' ||
            photoAddress == 'Location Unavailable' ||
            photoAddress.startsWith('Detecting')) {
          try {
            final rev = await LocationService.reverseGeocode(photoLat, photoLng);
            if (rev.isNotEmpty && !rev.startsWith('Detecting')) {
              photoAddress = rev;
            }
          } catch (_) {}
        }

        submissionLocation = photoLocation.copyWith(
          latitude: photoLat,
          longitude: photoLng,
          address: photoAddress,
        );
      }

      // 3. Save the progress update to Supabase and wait for confirmed success
      final result = await complaintProv.updateWorkProgress(
        complaintId: currentComplaint.complaintId,
        progressNote: noteText,
        percentage: _workPercentage.roundToDouble(),
        imageUrl: _progressImageUrl,
        communityUserId: authProv.currentUser?.id,
        communityUserName: authProv.currentUser?.name,
        latitude: submissionLocation?.latitude,
        longitude: submissionLocation?.longitude,
        address: submissionLocation?.address,
        capturedAt: submissionLocation?.timestamp,
        complaint: currentComplaint,
      );

      if (!mounted) return;

      if (result.success) {
        // Clear photo preview, notes, temporary state immediately
        setState(() {
          _noteController.clear();
          _progressImageUrl = null;
          _progressGeotagLocation = null;
        });

        // Show brief Flutter SnackBar only once after confirmed database success
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Progress update submitted successfully!'),
            backgroundColor: AppTheme.successGreen,
            duration: Duration(seconds: 3),
          ),
        );

        // Safely refresh provider in background to sync latest persisted updates across all portals
        try {
          await complaintProv.refreshComplaints().timeout(const Duration(seconds: 5));
        } catch (refreshErr) {
          if (kDebugMode) {
            debugPrint('Notice background refresh complaints after progress update: $refreshErr');
          }
        }

        if (!mounted) return;

        // Leave/refresh the page after database confirms the save
        Navigator.of(context).maybePop();
      } else {
        // Retain photo, notes, and progress percentage on failure
        if (result.uploadedImageUrl != null && result.uploadedImageUrl!.isNotEmpty) {
          setState(() {
            _progressImageUrl = result.uploadedImageUrl;
          });
        }

        final errMsg = result.errorMessage ?? 'Failed to save progress update to Supabase DB.';
        debugPrint('❌ [SEND PROGRESS UPDATE FAILED]: $errMsg');
        if (errMsg.startsWith('Location mismatch')) {
          debugPrint('⚠️ [DEBUG BRANCH: PROVIDER LOCATION MISMATCH] Provider returned location mismatch error.');
          _showLocationMismatchSnackBar();
        } else {
          debugPrint('⚠️ [DEBUG BRANCH: OTHER SUBMISSION ERROR] Displaying error feedback.');
          _showFeedbackSnackBar(
            'Submission failed: $errMsg',
            backgroundColor: AppTheme.emergencyRed,
            duration: const Duration(seconds: 5),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('❌ [SEND PROGRESS UPDATE EXCEPTION]: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving progress update: $e'),
            backgroundColor: AppTheme.emergencyRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteProgressUpdate(ProgressUpdate update, Complaint currentComplaint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppTheme.emergencyRed, size: 24),
            SizedBox(width: 8),
            Text(
              'Delete Progress Update',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this progress update? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: AppTheme.primaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emergencyRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _executeDeleteProgressUpdate(update, currentComplaint);
    }
  }

  Future<void> _executeDeleteProgressUpdate(ProgressUpdate update, Complaint currentComplaint) async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
      final authProv = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProv.currentUser;

      if (currentUser == null || currentUser.id.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication required: Please sign in to delete progress updates.'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
        return;
      }

      final userId = currentUser.id.trim();
      final userRole = currentUser.role.trim();

      final result = await complaintProv.deleteWorkProgressUpdate(
        complaintId: currentComplaint.complaintId,
        updateId: update.updateId,
        recordId: update.id,
        requestingUserId: userId,
        requestingUserRole: userRole,
      );

      if (!mounted) return;

      if (result.success) {
        await complaintProv.refreshComplaints();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Progress update deleted successfully'),
            backgroundColor: AppTheme.successGreen,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        final errMsg = result.errorMessage ?? 'Failed to delete progress update.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deletion failed: $errMsg'),
            backgroundColor: AppTheme.emergencyRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting progress update: $e'),
            backgroundColor: AppTheme.emergencyRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showPhotoViewerDialog(
    String imageUrl, {
    GeotagLocation? geotagLoc,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? timestamp,
    bool isDraftPhoto = true,
  }) {
    final double lat = geotagLoc?.latitude ?? latitude ?? 0.0;
    final double lng = geotagLoc?.longitude ?? longitude ?? 0.0;
    final bool hasValidCoords = Complaint.isValidCoordinates(lat, lng);

    String displayAddress = 'Location unavailable';
    if (geotagLoc?.address != null &&
        geotagLoc!.address.isNotEmpty &&
        geotagLoc.address != 'Location Unavailable' &&
        geotagLoc.address != 'Location' &&
        geotagLoc.address != 'Detecting live GPS location...' &&
        !geotagLoc.address.startsWith('Detecting')) {
      displayAddress = geotagLoc.address;
    } else if (address != null &&
        address.isNotEmpty &&
        address != 'Location Unavailable' &&
        address != 'Location' &&
        !address.startsWith('Detecting')) {
      displayAddress = address;
    } else if (hasValidCoords) {
      displayAddress = 'Lat: ${lat.toStringAsFixed(5)}°, Long: ${lng.toStringAsFixed(5)}°';
    }

    final String coordString = hasValidCoords
        ? 'Lat: ${lat.toStringAsFixed(6)}°, Long: ${lng.toStringAsFixed(6)}°'
        : 'Coordinates unavailable';

    final DateTime? captureTime = geotagLoc?.timestamp ?? timestamp;
    final String timeString = captureTime != null
        ? DateFormat('M/d/yyyy • hh:mm a').format(captureTime.toLocal())
        : 'Time unavailable';

    String dynamicAddress = displayAddress;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (hasValidCoords &&
              (dynamicAddress == 'Location unavailable' || dynamicAddress.startsWith('Lat:'))) {
            LocationService.reverseGeocode(lat, lng).then((resolved) {
              if (resolved.isNotEmpty &&
                  !resolved.startsWith('Detecting') &&
                  !resolved.startsWith('Lat:') &&
                  ctx.mounted) {
                setDialogState(() {
                  dynamicAddress = resolved;
                });
              }
            });
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.center_focus_strong_rounded, color: AppTheme.primaryBlue, size: 22),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Full Photo Inspection & Geotag Details',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 420),
                    width: double.infinity,
                    color: Colors.black,
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: _buildImageWidget(imageUrl, fit: BoxFit.contain, width: double.infinity),
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 18,
                                color: hasValidCoords ? AppTheme.emergencyRed : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'GPS Address',
                                      style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dynamicAddress,
                                      style: TextStyle(
                                        color: hasValidCoords ? Colors.white : Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.my_location_rounded,
                                  size: 16,
                                  color: hasValidCoords ? AppTheme.primaryBlue : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'GPS Coordinates',
                                        style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        coordString,
                                        style: TextStyle(
                                          color: hasValidCoords ? Colors.white : Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 16,
                                  color: Colors.amberAccent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Capture Time',
                                        style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        timeString,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
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
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isDraftPhoto)
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _pickImageFromCamera();
                            },
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            label: const Text('Change Photo'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogCtx);
                              _removeProgressImage();
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                            label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('Close', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);
}

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final authProv = Provider.of<AuthProvider>(context);
    final currentUser = authProv.currentUser;
    final currentComplaint = complaintProv.complaints.firstWhere(
      (c) => c.complaintId.trim().toLowerCase() == widget.complaint.complaintId.trim().toLowerCase(),
      orElse: () => widget.complaint,
    );

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
        title: Text('Work Progress: ${currentComplaint.complaintId}'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                backgroundColor: AppTheme.primaryDark,
                opacity: 0.95,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentComplaint.title,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentComplaint.address,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Current Progress', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          '${currentComplaint.progressPercentage.toInt()}%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (currentComplaint.isRejected) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.emergencyRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.4), width: 1.2),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.block_rounded, color: AppTheme.emergencyRed, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This complaint was rejected as fake by the community. It cannot receive repair progress updates.',
                          style: TextStyle(
                            color: AppTheme.emergencyRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Percentage Slider Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Update Work Percentage',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primaryBlue.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '${_workPercentage.round()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.primaryBlue,
                        inactiveTrackColor: AppTheme.primaryBlue.withOpacity(0.18),
                        trackHeight: 6.0,
                        thumbColor: AppTheme.primaryBlue,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10.0,
                          pressedElevation: 4.0,
                        ),
                        overlayColor: AppTheme.primaryBlue.withOpacity(0.15),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20.0),
                        trackShape: const RoundedRectSliderTrackShape(),
                        valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                        valueIndicatorColor: AppTheme.primaryDark,
                        valueIndicatorTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      child: Slider(
                        value: _workPercentage.clamp(0.0, 100.0),
                        min: 0.0,
                        max: 100.0,
                        activeColor: AppTheme.primaryBlue,
                        inactiveColor: AppTheme.primaryBlue.withOpacity(0.18),
                        label: '${_workPercentage.round()}%',
                        onChanged: (val) {
                          setState(() {
                            _workPercentage = val.clamp(0.0, 100.0);
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('0% Started', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)))),
                          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('50% In Progress', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)))),
                          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('100% Done', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Upload Progress Photo Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.add_a_photo, color: AppTheme.primaryBlue, size: 20),
                            SizedBox(width: 8),
                            Text('Upload Progress Image', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (_progressImageUrl != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: _pickImageFromCamera,
                                icon: const Icon(Icons.edit, size: 14, color: AppTheme.primaryBlue),
                                label: const Text('Change', style: TextStyle(fontSize: 12, color: AppTheme.primaryBlue)),
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: _removeProgressImage,
                                icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red),
                                label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _progressImageUrl != null
                          ? () => _showPhotoViewerDialog(_progressImageUrl!, geotagLoc: _progressGeotagLocation, isDraftPhoto: true)
                          : _pickImageFromCamera,
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
                        ),
                        child: _progressImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    _buildImageWidget(_progressImageUrl!, fit: BoxFit.contain, width: double.infinity, height: 220),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                      color: Colors.black.withValues(alpha: 0.65),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
                                          SizedBox(width: 6),
                                          Text(
                                            'Tap photo to open full screen & view details',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: GestureDetector(
                                        onTap: _removeProgressImage,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                            ],
                                          ),
                                          child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_rounded, color: AppTheme.primaryBlue, size: 36),
                                  SizedBox(height: 6),
                                  Text('Tap to capture photo with Camera', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryDark)),
                                  SizedBox(height: 4),
                                  Text('Take a live repair progress photo using camera', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Progress Notes Field
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Progress Log Notes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Enter updates on asphalt layering, safety cones, concrete setting...',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Action Buttons
              GradientButton(
                text: _isSubmitting
                    ? 'Sending Progress Update...'
                    : currentComplaint.isRejected
                        ? 'Voting & Progress Closed (Rejected)'
                        : 'Send Progress Update',
                icon: _isSubmitting ? null : (currentComplaint.isRejected ? Icons.block_rounded : Icons.send_rounded),
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _sendProgressUpdate,
              ),

              if (currentComplaint.updates.isNotEmpty) ...[
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Saved Progress Updates History',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${Complaint.deduplicateUpdates(currentComplaint.updates).length} Saved',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...(() {
                  final list = Complaint.deduplicateUpdates(currentComplaint.updates);
                  list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                  return list;
                })().map((u) {
                  final bool hasLoc = Complaint.isValidCoordinates(u.latitude, u.longitude);
                  final String locAddr = (u.address != null &&
                          u.address!.trim().isNotEmpty &&
                          u.address != 'Location' &&
                          u.address != 'Location Unavailable' &&
                          !u.address!.startsWith('Detecting'))
                      ? u.address!
                      : (hasLoc ? 'Lat: ${u.latitude!.toStringAsFixed(4)}°, Long: ${u.longitude!.toStringAsFixed(4)}°' : 'Location unavailable');

                  final bool isComplaintCompleted = currentComplaint.isCompleted || currentComplaint.status.toLowerCase() == 'completed';
                  final bool isCreator = currentUser != null &&
                      currentUser.id.trim().isNotEmpty &&
                      u.communityUserId.trim().isNotEmpty &&
                      currentUser.id.trim() == u.communityUserId.trim();
                  final bool isAdmin = currentUser?.role.trim().toLowerCase() == 'admin';
                  final bool canDelete = !isComplaintCompleted && (isCreator || isAdmin);

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
                                  if (canDelete) ...[
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: 'Delete Progress Update',
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          key: ValueKey('delete_progress_${u.updateId}'),
                                          onTap: _isSubmitting ? null : () => _confirmDeleteProgressUpdate(u, currentComplaint),
                                          borderRadius: BorderRadius.circular(8),
                                          hoverColor: Colors.red.withValues(alpha: 0.15),
                                          child: Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withValues(alpha: 0.10),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.red.withValues(alpha: 0.25), width: 1),
                                            ),
                                            child: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16,
                                              color: AppTheme.emergencyRed,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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
                              onTap: () => _showPhotoViewerDialog(
                                u.imageUrl!,
                                latitude: u.latitude,
                                longitude: u.longitude,
                                address: u.address,
                                timestamp: u.capturedAt ?? u.createdAt,
                                isDraftPhoto: false,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    _buildImageWidget(
                                      u.imageUrl!,
                                      height: 140,
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
                                            'Tap to view saved progress photo & geotag details',
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

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
