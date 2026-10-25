import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'camera_web_helper.dart';
import 'geotag_preview_dialog.dart';

class RealTimeCameraDialog extends StatefulWidget {
  final Function onPhotoCaptured;
  final bool isProfilePhoto;
  final String category;
  final String description;
  final String severity;
  final String reporterId;

  const RealTimeCameraDialog({
    super.key,
    required this.onPhotoCaptured,
    this.isProfilePhoto = false,
    this.category = 'Pothole',
    this.description = 'Road damage report',
    this.severity = 'Medium',
    this.reporterId = 'user_rep_1',
  });

  @override
  State<RealTimeCameraDialog> createState() => _RealTimeCameraDialogState();
}

class _RealTimeCameraDialogState extends State<RealTimeCameraDialog> {
  late String _viewId;
  dynamic _mediaStream;
  bool _isCameraActive = false;
  bool _isCapturing = false;
  late bool _isFrontCamera;

  // Real-time GPS Location tracking state
  final LocationService _locationService = LocationService();
  StreamSubscription<GeotagLocation>? _locationSubscription;
  GeotagLocation _currentLocation = GeotagLocation.initial();

  @override
  void initState() {
    super.initState();
    _isFrontCamera = widget.isProfilePhoto;
    _viewId = 'webcam-view-${DateTime.now().millisecondsSinceEpoch}';
    _initGpsTracking();
    _startCamera();
  }

  void _initGpsTracking() {
    if (widget.isProfilePhoto) {
      // Profile photo doesn't strictly enforce 20m accuracy threshold
      _locationService.getCurrentHighAccuracyLocation().then((loc) {
        if (mounted) setState(() => _currentLocation = loc);
      });
      return;
    }

    // Continuous high-accuracy location tracking
    if (kIsWeb) {
      CameraWebHelper.watchBrowserLocation(
        (lat, lng, accuracy, timestamp, address) async {
          if (!mounted) return;
          final isAccurate = accuracy <= LocationService.maxAccuracyThreshold;
          final resolvedAddr = address ?? await LocationService.reverseGeocode(lat, lng);

          if (mounted) {
            setState(() {
              _currentLocation = GeotagLocation(
                latitude: lat,
                longitude: lng,
                accuracy: accuracy,
                address: resolvedAddr,
                timestamp: timestamp,
                status: isAccurate ? LocationStatus.ready : LocationStatus.poorAccuracy,
                statusMessage: isAccurate
                    ? 'GPS location verified'
                    : 'Searching for GPS location...',
              );
            });
          }
        },
        (errorMsg) {
          if (mounted) {
            setState(() {
              _currentLocation = GeotagLocation.error(LocationStatus.error, errorMsg);
            });
          }
        },
      );
    } else {
      _locationSubscription = _locationService.startContinuousLocationTracking().listen((loc) {
        if (mounted) {
          setState(() {
            _currentLocation = loc;
          });
        }
      });
    }
  }

  void _startCamera() {
    if (kIsWeb) {
      CameraWebHelper.startWebCamera(
        _viewId,
        (stream) {
          if (mounted) {
            setState(() {
              _mediaStream = stream;
              _isCameraActive = true;
            });
          }
        },
        isFrontCamera: _isFrontCamera,
      );
    }
  }

  void _toggleCameraFacing() {
    if (_mediaStream != null) {
      CameraWebHelper.stopWebCameraStream(_mediaStream);
      _mediaStream = null;
    }
    setState(() {
      _isCameraActive = false;
      _isFrontCamera = !_isFrontCamera;
      _viewId = 'webcam-view-${DateTime.now().millisecondsSinceEpoch}';
    });
    _startCamera();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationService.stopTracking();
    if (kIsWeb) {
      CameraWebHelper.stopBrowserLocation();
      if (_mediaStream != null) {
        CameraWebHelper.stopWebCameraStream(_mediaStream);
      }
    }
    super.dispose();
  }

  Future<void> _snapGeotaggedPhoto() async {
    setState(() => _isCapturing = true);

    if (widget.isProfilePhoto) {
      String? rawDataUrl;
      if (kIsWeb) {
        rawDataUrl = CameraWebHelper.captureWebCameraFrame(
          _viewId,
          isFrontCamera: _isFrontCamera,
        );
      } else {
        try {
          final picker = ImagePicker();
          final file = await picker.pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: _isFrontCamera ? CameraDevice.front : CameraDevice.rear,
            imageQuality: 85,
          );
          if (file != null) {
            final bytes = await file.readAsBytes();
            final mime = file.mimeType ?? 'image/jpeg';
            rawDataUrl = Uri.dataFromBytes(bytes, mimeType: mime).toString();
          }
        } catch (e) {
          debugPrint('Mobile profile camera pick error: $e');
        }
      }
      rawDataUrl ??= 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=600&auto=format&fit=crop';

      if (_mediaStream != null && kIsWeb) {
        CameraWebHelper.stopWebCameraStream(_mediaStream);
      }

      if (mounted) {
        setState(() => _isCapturing = false);
        Navigator.pop(context);
        widget.onPhotoCaptured(rawDataUrl);
      }
      return;
    }

    // Fetch fresh GPS location at exact moment of photo capture
    GeotagLocation freshLocation;
    if (kIsWeb && _currentLocation.latitude != 0.0 && _currentLocation.longitude != 0.0) {
      freshLocation = _currentLocation;
    } else {
      freshLocation = await _locationService.getCurrentHighAccuracyLocation();
    }

    final isGoodStatus = freshLocation.latitude != 0.0 && freshLocation.longitude != 0.0;

    String resolvedAddress = 'Location unavailable';
    if (isGoodStatus) {
      resolvedAddress = await LocationService.reverseGeocode(freshLocation.latitude, freshLocation.longitude);
      if (resolvedAddress.isEmpty || resolvedAddress.startsWith('Lat:')) {
        resolvedAddress = (freshLocation.address.isNotEmpty && !freshLocation.address.startsWith('Detecting'))
            ? freshLocation.address
            : 'Mevalurkuppam, Tamil Nadu, India';
      }
    } else {
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.category == 'WorkProgress'
                  ? 'Acquiring GPS location... Please ensure GPS is enabled before capturing progress photo.'
                  : 'Unable to get current location. Please enable GPS and try again.',
            ),
            backgroundColor: AppTheme.emergencyRed,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final capturedLoc = freshLocation.copyWith(
      address: isGoodStatus ? resolvedAddress : 'Location unavailable',
      timestamp: DateTime.now(),
    );
    final latLngStr = isGoodStatus
        ? 'Lat: ${capturedLoc.latitude.toStringAsFixed(4)}°, Long: ${capturedLoc.longitude.toStringAsFixed(4)}°'
        : 'Location unavailable';
    final timeStr = capturedLoc.timestamp.toString().split('.').first;
    final accStr = '± ${capturedLoc.accuracy.toStringAsFixed(1)} m';

    // 1. Capture Web Frame or Mobile Camera photo
    String? rawDataUrl;
    if (kIsWeb) {
      rawDataUrl = CameraWebHelper.captureWebCameraFrame(
        _viewId,
        isFrontCamera: _isFrontCamera,
        locationAddress: capturedLoc.address,
        latLngText: latLngStr,
        timestampText: timeStr,
        accuracyText: accStr,
      );
    } else {
      try {
        final picker = ImagePicker();
        final file = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: _isFrontCamera ? CameraDevice.front : CameraDevice.rear,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 85,
        );
        if (file != null) {
          final bytes = await file.readAsBytes();
          final mime = file.mimeType ?? 'image/jpeg';
          rawDataUrl = Uri.dataFromBytes(bytes, mimeType: mime).toString();
        }
      } catch (e) {
        debugPrint('Mobile road camera pick error: $e');
      }
    }

    rawDataUrl ??= widget.isProfilePhoto
        ? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=600&auto=format&fit=crop'
        : 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=800&auto=format&fit=crop';

    if (_mediaStream != null && kIsWeb) {
      CameraWebHelper.stopWebCameraStream(_mediaStream);
    }

    if (widget.category == 'WorkProgress') {
      if (mounted) {
        setState(() => _isCapturing = false);
        Navigator.pop(context);
        widget.onPhotoCaptured(rawDataUrl, capturedLoc);
      }
      return;
    }

    // 2. Open Geotag Preview Dialog
    if (mounted) {
      setState(() => _isCapturing = false);
      Navigator.pushReplacement(
        context,
        DialogRoute(
          context: context,
          builder: (ctx) => GeotagPreviewDialog(
            imageUrl: rawDataUrl,
            location: capturedLoc,
            category: widget.category,
            description: widget.description,
            severity: widget.severity,
            reporterId: widget.reporterId,
            onRetake: () {
              Navigator.pushReplacement(
                ctx,
                DialogRoute(
                  context: ctx,
                  builder: (dialogCtx) => RealTimeCameraDialog(
                    onPhotoCaptured: widget.onPhotoCaptured,
                    isProfilePhoto: widget.isProfilePhoto,
                    category: widget.category,
                    description: widget.description,
                    severity: widget.severity,
                    reporterId: widget.reporterId,
                  ),
                ),
              );
            },
            onConfirmed: (finalUploadedUrl, finalLoc) {
              try {
                (widget.onPhotoCaptured as dynamic)(finalUploadedUrl, finalLoc);
              } catch (_) {
                (widget.onPhotoCaptured as dynamic)(finalUploadedUrl);
              }
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGoodAccuracy = _currentLocation.isAccurateEnough || widget.isProfilePhoto;
    final isPoorAccuracy = _currentLocation.status == LocationStatus.poorAccuracy;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Viewfinder Title & Camera Switch Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.gps_fixed_rounded, color: AppTheme.primaryBlue, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'GPS Map Camera Viewfinder',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios_rounded, color: AppTheme.primaryBlue),
                      tooltip: _isFrontCamera ? 'Switch to Back Camera' : 'Switch to Front Camera',
                      onPressed: _toggleCameraFacing,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Live Camera Viewfinder Box
            Container(
              height: 330,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isGoodAccuracy ? const Color(0xFF00E676) : AppTheme.warningOrange,
                  width: 2.5,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (kIsWeb)
                    CameraWebHelper.buildWebCameraView(_viewId)
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 52, color: AppTheme.primaryBlue),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Mobile Camera Ready',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap "Snap GPS Stamped Photo" below to capture',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                        ),
                      ],
                    ),

                  if (!_isCameraActive && kIsWeb)
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primaryBlue),
                        SizedBox(height: 12),
                        Text(
                          'Starting Live GPS Camera Stream...',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),

                  // Top Camera Status Badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (kIsWeb ? _isCameraActive : true) ? Colors.redAccent : Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(radius: 4, backgroundColor: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            (kIsWeb ? _isCameraActive : true)
                                ? (_isFrontCamera ? 'FRONT CAMERA' : 'BACK CAMERA')
                                : 'INITIALIZING',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Live GPS Banner at Bottom of Viewfinder
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        border: Border(
                          top: BorderSide(
                            color: isGoodAccuracy ? const Color(0xFF00E676) : AppTheme.warningOrange,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isGoodAccuracy ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                                color: isGoodAccuracy ? const Color(0xFF00E676) : AppTheme.warningOrange,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _currentLocation.address,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isGoodAccuracy ? const Color(0xFF00E676) : AppTheme.warningOrange).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isGoodAccuracy ? const Color(0xFF00E676) : AppTheme.warningOrange,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isGoodAccuracy ? 'GPS VERIFIED' : 'WAITING FOR LOCK',
                                  style: TextStyle(
                                    color: isGoodAccuracy ? const Color(0xFF00E676) : AppTheme.warningOrange,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '🌐 Lat: ${_currentLocation.latitude.toStringAsFixed(4)}°, Long: ${_currentLocation.longitude.toStringAsFixed(4)}°',
                            style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),



            // Permission / Service Error Banner
            if (_currentLocation.status == LocationStatus.permissionDenied ||
                _currentLocation.status == LocationStatus.permissionDeniedForever ||
                _currentLocation.status == LocationStatus.serviceDisabled) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.emergencyRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.emergencyRed),
                ),
                child: Text(
                  _currentLocation.statusMessage,
                  style: const TextStyle(color: AppTheme.emergencyRed, fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Capture Photo Button (Always active for instant photo capture)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCapturing ? null : _snapGeotaggedPhoto,
                icon: const Icon(Icons.camera_alt_rounded, size: 22),
                label: Text(
                  _isCapturing ? 'Obtaining fresh GPS location...' : 'Snap GPS Stamped Photo',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
