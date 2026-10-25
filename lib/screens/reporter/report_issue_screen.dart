import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/map_view_widget.dart';
import '../../widgets/real_time_camera_dialog.dart';
import '../../widgets/photo_edit_insert_dialog.dart';
import '../../models/complaint_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import 'complaint_tracking_screen.dart';

class ReportIssueScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ReportIssueScreen({super.key, this.onBack});

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'Pothole';
  String _selectedSeverity = 'Medium';
  String? _capturedImageUrl;

  double? _selectedLat;
  double? _selectedLng;
  String? _selectedAddress;

  // Photo GPS location metadata
  double? _photoLat;
  double? _photoLng;
  double? _photoAccuracy;
  String? _photoAddress;

  bool _isDetectingLocation = false;
  bool _isLocationConfirmed = false;
  bool _isSubmitting = false;
  String? _locationErrorMessage;

  final List<String> _categories = [
    'Pothole',
    'Damaged Road',
    'Garbage',
    'Drainage Issue',
    'Street Light Failure',
  ];

  final List<String> _severities = [
    'Low',
    'Medium',
    'Emergency',
  ];

  @override
  void initState() {
    super.initState();
    _detectCurrentGpsLocation();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _detectCurrentGpsLocation() async {
    setState(() {
      _isDetectingLocation = true;
      _locationErrorMessage = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isDetectingLocation = false;
            _locationErrorMessage = "Unable to get current location. Please enable GPS and try again.";
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _isDetectingLocation = false;
              _locationErrorMessage = "Unable to get current location. Please enable GPS and try again.";
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isDetectingLocation = false;
            _locationErrorMessage = "Unable to get current location. Please enable GPS and try again.";
          });
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );

      final double lat = position.latitude;
      final double lng = position.longitude;

      final readableAddress = await LocationService.reverseGeocode(lat, lng);

      if (mounted) {
        setState(() {
          _selectedLat = lat;
          _selectedLng = lng;
          _selectedAddress = readableAddress;
          _isDetectingLocation = false;
          _isLocationConfirmed = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS location detected: $readableAddress'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('Device GPS accuracy query note: $e');
      if (mounted) {
        setState(() {
          _isDetectingLocation = false;
          _locationErrorMessage = "Unable to get current location. Please enable GPS and try again.";
        });
      }
    }
  }

  void _showPhotoEditDialog(String photoUrl) {
    showDialog(
      context: context,
      builder: (dialogCtx) => PhotoEditInsertDialog(
        imageUrl: photoUrl,
        isProfilePhoto: false,
        onInsertPhoto: (finalUrl) {
          setState(() {
            _capturedImageUrl = finalUrl;
          });
        },
      ),
    );
  }

  void _openCameraCapture() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    final reporterId = (user != null && user.id.trim().isNotEmpty) ? user.id.trim() : 'user_rep_1';

    showDialog(
      context: context,
      builder: (camCtx) => RealTimeCameraDialog(
        isProfilePhoto: false,
        category: _selectedCategory,
        description: _descriptionController.text.trim().isEmpty
            ? 'Road damage report at location'
            : _descriptionController.text.trim(),
        severity: _selectedSeverity,
        reporterId: reporterId,
        onPhotoCaptured: (capturedUrl, geotagLoc) {
          if (mounted) {
            setState(() {
              _capturedImageUrl = capturedUrl;
              if (geotagLoc != null && geotagLoc is GeotagLocation) {
                _photoLat = geotagLoc.latitude;
                _photoLng = geotagLoc.longitude;
                _photoAccuracy = geotagLoc.accuracy;
                _photoAddress = geotagLoc.address;

                // Automatically set complaint map pin to captured photo's coordinates
                _selectedLat = geotagLoc.latitude;
                _selectedLng = geotagLoc.longitude;
                _selectedAddress = geotagLoc.address;
                _isLocationConfirmed = true;
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Geotagged photo captured & location set to map pin!'),
                backgroundColor: AppTheme.successGreen,
              ),
            );
          }
        },
      ),
    );
  }

  bool _validateLocationMatch() {
    // 1. Check photo captured via camera
    if (_capturedImageUrl == null || _capturedImageUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a damage photo using the camera before submitting.'),
          backgroundColor: AppTheme.emergencyRed,
        ),
      );
      return false;
    }

    // 2. Check photo GPS coordinates exist
    if (_photoLat == null || _photoLng == null) {
      if (_selectedLat != null && _selectedLng != null) {
        // Fallback to selected coordinates if photo coordinates were not separated
        _photoLat = _selectedLat;
        _photoLng = _selectedLng;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS coordinates missing from captured photo. Please retake the photo with camera.'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
        return false;
      }
    }

    // 3. Check map location coordinates exist
    if (_selectedLat == null || _selectedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please detect or confirm your GPS location before submitting.'),
          backgroundColor: AppTheme.emergencyRed,
        ),
      );
      return false;
    }

    // 4. Calculate distance between photo location and map location in meters
    final double distanceInMeters = Geolocator.distanceBetween(
      _photoLat!,
      _photoLng!,
      _selectedLat!,
      _selectedLng!,
    );

    // Permitted distance tolerance based on GPS accuracy (clamped between 80m and 250m)
    final double accuracy = _photoAccuracy ?? 10.0;
    final double permittedTolerance = (accuracy * 2.5).clamp(80.0, 250.0);

    if (distanceInMeters > permittedTolerance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location mismatch! The photo location and selected map location do not match. Please capture the photo at the complaint location and try again.',
          ),
          backgroundColor: AppTheme.emergencyRed,
          duration: Duration(seconds: 5),
        ),
      );
      return false;
    }

    return true;
  }

  void _submitComplaint({bool forceSubmit = false}) async {
    if (_isSubmitting) return;

    // First validate camera photo and location matching
    if (!_validateLocationMatch()) {
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a description of the road damage.'),
          backgroundColor: AppTheme.emergencyRed,
        ),
      );
      return;
    }

    if (_selectedLat == null || _selectedLng == null || _selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please detect or confirm your GPS location before submitting.'),
          backgroundColor: AppTheme.emergencyRed,
        ),
      );
      return;
    }

    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);

    // Check if same issue category at this location has already been submitted
    if (!forceSubmit) {
      final existingDuplicate = await complaintProv.checkAndFindDuplicate(
        category: _selectedCategory,
        latitude: _selectedLat!,
        longitude: _selectedLng!,
        address: _selectedAddress!,
      );

      if (existingDuplicate != null) {
        if (mounted) {
          _showAlreadySubmittedDialog(existingDuplicate);
        }
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.currentUser;

      final activeReporterId = (user != null && user.id.trim().isNotEmpty)
          ? user.id.trim()
          : (user?.email.trim().isNotEmpty == true ? user!.email.trim() : 'user_rep_1');

      final activeReporterName = (user != null && user.hasValidName)
          ? user.name.trim()
          : 'Reporter name unavailable';

      final existingIds = complaintProv.complaints.map((c) => c.complaintId.toLowerCase()).toSet();

      final newComplaint = await complaintProv.submitComplaint(
        reporterId: activeReporterId,
        reporterName: activeReporterName,
        title: _titleController.text.trim().isEmpty
            ? '$_selectedCategory at $_selectedAddress'
            : _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        severity: _selectedSeverity,
        latitude: _selectedLat!,
        longitude: _selectedLng!,
        address: _selectedAddress!,
        imageUrl: _capturedImageUrl!,
        gpsAccuracy: _photoAccuracy ?? 5.0,
      );

      if (mounted) {
        if (newComplaint != null) {
          // If returned complaint is an existing active complaint (duplicate)
          final isDuplicate = existingIds.contains(newComplaint.complaintId.toLowerCase());

          if (isDuplicate) {
            _showAlreadySubmittedDialog(newComplaint);
          } else {
            _resetForm();
            _showSuccessSubmissionDialog(newComplaint);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save complaint to database. Please check your connection and try again.'),
              backgroundColor: AppTheme.emergencyRed,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error submitting complaint: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission error: $e'),
            backgroundColor: AppTheme.emergencyRed,
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

  void _showAlreadySubmittedDialog(Complaint complaint) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Amber warning badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100.withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.amber.shade800,
                      child: const Icon(
                        Icons.report_problem_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'This issue has already been reported!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This issue has already been reported by another citizen and registered in the system.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 20),

                // Complaint details card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      _buildSuccessDetailRow(
                        Icons.confirmation_number_outlined,
                        'Complaint ID',
                        complaint.complaintId,
                        isBold: true,
                        valueColor: AppTheme.primaryBlue,
                      ),
                      const Divider(height: 16),
                      _buildSuccessDetailRow(
                        Icons.category_outlined,
                        'Category',
                        complaint.category,
                      ),
                      const Divider(height: 16),
                      _buildSuccessDetailRow(
                        Icons.info_outline_rounded,
                        'Status',
                        complaint.status,
                        isBold: true,
                        valueColor: complaint.status == 'Completed'
                            ? AppTheme.successGreen
                            : AppTheme.primaryBlue,
                      ),
                      const Divider(height: 16),
                      _buildSuccessDetailRow(
                        Icons.location_on_outlined,
                        'Location',
                        complaint.address,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Photo & Description Preview
                if (complaint.imageUrl.isNotEmpty || complaint.description.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (complaint.imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            complaint.imageUrl,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 70,
                              height: 70,
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.image, color: Colors.grey),
                            ),
                          ),
                        ),
                      if (complaint.imageUrl.isNotEmpty) const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          complaint.description.isNotEmpty ? complaint.description : complaint.title,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                // Community Votes Breakdown
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '🟢 Genuine Votes',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${complaint.realVotes} (${complaint.realPercentage.toStringAsFixed(0)}%)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(height: 30, width: 1, color: Colors.grey.shade300),
                      Column(
                        children: [
                          Text(
                            '🔴 Fake Votes',
                            style: const TextStyle(fontSize: 11, color: AppTheme.emergencyRed, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${complaint.fakeVotes} (${complaint.fakePercentage.toStringAsFixed(0)}%)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Repair Progress if available
                if (complaint.progressPercentage > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Repair Progress',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${complaint.progressPercentage.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: complaint.progressPercentage / 100.0,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      color: AppTheme.successGreen,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // View Existing Complaint button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text(
                      'View Existing Complaint',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ComplaintTrackingScreen(complaint: complaint),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Back to Dashboard button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      _resetForm();
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      'Back to Dashboard',
                      style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Submit anyway link
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _submitComplaint(forceSubmit: true);
                  },
                  child: Text(
                    'Submit as New Report Anyway',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      decoration: TextDecoration.underline,
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


  void _resetForm() {
    setState(() {
      _titleController.clear();
      _descriptionController.clear();
      _capturedImageUrl = null;
      _photoLat = null;
      _photoLng = null;
      _photoAccuracy = null;
      _photoAddress = null;
      _selectedCategory = 'Pothole';
      _selectedSeverity = 'Medium';
      _isLocationConfirmed = false;
    });
  }

  void _showSuccessSubmissionDialog(Complaint complaint) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated green success badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.successGreen.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: AppTheme.successGreen,
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Submitted Successfully!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your road damage complaint has been registered and sent for verification & repair.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),

                // Complaint details card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildSuccessDetailRow(
                        Icons.confirmation_number_outlined,
                        'Complaint ID',
                        complaint.complaintId,
                        isBold: true,
                        valueColor: AppTheme.primaryBlue,
                      ),
                      const Divider(height: 16),
                      _buildSuccessDetailRow(
                        Icons.category_outlined,
                        'Category',
                        complaint.category,
                      ),
                      const Divider(height: 16),
                      _buildSuccessDetailRow(
                        Icons.warning_amber_rounded,
                        'Severity',
                        complaint.severity,
                        valueColor: complaint.severityColor,
                      ),
                      const Divider(height: 16),
                      _buildSuccessDetailRow(
                        Icons.location_on_outlined,
                        'Location',
                        complaint.address,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Action buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.track_changes, size: 20),
                    label: const Text(
                      'Track Complaint Status',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ComplaintTrackingScreen(complaint: complaint),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      'Back to Dashboard',
                      style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w600),
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

  Widget _buildSuccessDetailRow(
    IconData icon,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? AppTheme.primaryDark,
            ),
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);

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
        title: const Text('Report Road Damage'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Upload Card (Camera Only)
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.camera_alt_rounded, color: AppTheme.primaryBlue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Complaint Photo (Camera Only)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_capturedImageUrl != null) ...[
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _showPhotoEditDialog(_capturedImageUrl!),
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    Image.network(
                                      _capturedImageUrl!,
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Expanded(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.zoom_in_rounded, color: Colors.white, size: 18),
                                                SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    'Tap photo to view / edit',
                                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_photoLat != null && _photoLng != null) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppTheme.successGreen,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.gps_fixed, color: Colors.white, size: 12),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'GPS Stamped',
                                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _capturedImageUrl = null;
                                    _photoLat = null;
                                    _photoLng = null;
                                    _photoAccuracy = null;
                                    _photoAddress = null;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openCameraCapture,
                          icon: const Icon(Icons.camera_alt_rounded, size: 18),
                          label: const Text('Retake Photo with Camera', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ] else ...[
                      InkWell(
                        onTap: _openCameraCapture,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.primaryBlue.withOpacity(0.4),
                              style: BorderStyle.solid,
                              width: 1.5,
                            ),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppTheme.primaryBlue,
                                child: Icon(Icons.camera_alt_rounded, size: 28, color: Colors.white),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Take Photo with Camera',
                                style: TextStyle(
                                  color: AppTheme.primaryDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Live camera capture with GPS geotagging',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
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

              const SizedBox(height: 20),

              // Location Section Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.location_on_rounded, color: AppTheme.emergencyRed, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Location',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (_selectedLat != null && _selectedLng != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_isLocationConfirmed ? AppTheme.successGreen : AppTheme.primaryBlue).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _isLocationConfirmed ? AppTheme.successGreen : AppTheme.primaryBlue, width: 0.8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isLocationConfirmed ? Icons.check_circle_rounded : Icons.gps_fixed_rounded,
                                  color: _isLocationConfirmed ? AppTheme.successGreen : AppTheme.primaryBlue,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isLocationConfirmed ? 'CONFIRMED' : 'GPS DETECTED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _isLocationConfirmed ? AppTheme.successGreen : AppTheme.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // "Use My Current Location" Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDetectingLocation ? null : _detectCurrentGpsLocation,
                        icon: _isDetectingLocation
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Icon(Icons.my_location_rounded, size: 20),
                        label: Text(
                          _isDetectingLocation ? 'Detecting your current location...' : 'Use My Current Location',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                      ),
                    ),

                    // Loading State Indicator Message
                    if (_isDetectingLocation) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
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
                                'Detecting your current location...',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Error / Permission Denied / Disabled Location Banner with Retry Button
                    if (_locationErrorMessage != null && !_isDetectingLocation) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _locationErrorMessage!,
                                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: _detectCurrentGpsLocation,
                                icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.red),
                                label: const Text('Retry', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Photo Location vs Selected Map Pin Comparison Badge
                    if (_photoLat != null && _photoLng != null && _selectedLat != null && _selectedLng != null) ...[
                      const SizedBox(height: 12),
                      Builder(builder: (context) {
                        final dist = Geolocator.distanceBetween(_photoLat!, _photoLng!, _selectedLat!, _selectedLng!);
                        final accuracy = _photoAccuracy ?? 10.0;
                        final tolerance = (accuracy * 2.5).clamp(80.0, 250.0);
                        final matches = dist <= tolerance;

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: matches ? AppTheme.successGreen.withOpacity(0.08) : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: matches ? AppTheme.successGreen : Colors.red.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    matches ? Icons.verified_rounded : Icons.warning_amber_rounded,
                                    color: matches ? AppTheme.successGreen : Colors.red,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      matches ? 'Photo GPS Location Matches Map Pin' : 'Location Mismatch Warning',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: matches ? AppTheme.successGreen : Colors.red,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${dist.toStringAsFixed(1)}m offset',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: matches ? AppTheme.successGreen : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              if (!matches) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Map pin is too far from photo GPS location. Drag map pin back to photo site before submitting.',
                                  style: TextStyle(fontSize: 11, color: Colors.red),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],

                    // Detected Location Map & Readout & Confirm Location Button
                    if (_selectedLat != null && _selectedLng != null && !_isDetectingLocation) ...[
                      const SizedBox(height: 14),
                      MapViewWidget(
                        initialLat: _selectedLat!,
                        initialLng: _selectedLng!,
                        initialAddress: _selectedAddress,
                        isPickerMode: true,
                        onLocationSelected: (lat, lng, addr) {
                          setState(() {
                            _selectedLat = lat;
                            _selectedLng = lng;
                            _selectedAddress = addr;
                            _isLocationConfirmed = false;
                          });
                        },
                      ),

                      const SizedBox(height: 12),

                      // Readable Address & Lat/Lng Readout Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.place_rounded, color: AppTheme.emergencyRed, size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _selectedAddress ?? 'Selected Location',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Lat: ${_selectedLat!.toStringAsFixed(5)}°, Lng: ${_selectedLng!.toStringAsFixed(5)}°',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.successGreen.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'GPS Verified',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Confirm Location Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isLocationConfirmed = true;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Location confirmed and attached to complaint!'),
                                backgroundColor: AppTheme.successGreen,
                              ),
                            );
                          },
                          icon: Icon(
                            _isLocationConfirmed ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          label: Text(
                            _isLocationConfirmed ? 'Location Confirmed ✓' : 'Confirm Location',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isLocationConfirmed ? AppTheme.successGreen : AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Issue Category & Severity Form Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Selection Dropdown
                    const Text(
                      'Issue Category',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _categories
                          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCategory = val);
                      },
                    ),

                    const SizedBox(height: 18),

                    // Severity Selector Pills
                    const Text(
                      'Severity Level',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: _severities.map((sev) {
                        final isSelected = _selectedSeverity == sev;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedSeverity = sev),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primaryDark : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primaryDark
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Text(
                                sev,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 18),

                    // Description Text Area
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Complaint Description',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Provide details about the damage size, traffic risk, or landmark details...',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Submit Button
              GradientButton(
                text: _isSubmitting ? 'Submitting Complaint...' : 'Submit Complaint',
                icon: Icons.send_rounded,
                isLoading: _isSubmitting || complaintProv.isLoading,
                onPressed: _isSubmitting ? null : _submitComplaint,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
