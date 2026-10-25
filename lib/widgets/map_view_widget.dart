import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';

import '../models/complaint_model.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

class MapViewWidget extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String? initialAddress;
  final bool isPickerMode;
  final Function(double lat, double lng, String address)? onLocationSelected;
  final List<Complaint>? complaints;
  final Function(Complaint complaint)? onComplaintTap;
  final bool onlyActive;
  final bool isVisible;

  const MapViewWidget({
    super.key,
    this.initialLat = 13.0298,
    this.initialLng = 80.0168,
    this.initialAddress,
    this.isPickerMode = false,
    this.onLocationSelected,
    this.complaints,
    this.onComplaintTap,
    this.onlyActive = false,
    this.isVisible = true,
  });

  @override
  State<MapViewWidget> createState() => _MapViewWidgetState();
}

class _MapViewWidgetState extends State<MapViewWidget> {
  MapLibreMapController? mapController;
  
  late double selectedLat;
  late double selectedLng;
  late String selectedAddress;
  
  bool _isLoadingLocation = false;
  bool _isStyleLoaded = false;
  bool _isBuildingMarkers = false;
  bool _needsRebuildMarkers = false;

  @override
  void initState() {
    super.initState();
    selectedLat = widget.initialLat;
    selectedLng = widget.initialLng;
    selectedAddress = (widget.initialAddress != null && widget.initialAddress!.trim().isNotEmpty)
        ? widget.initialAddress!.trim()
        : 'Detecting live GPS location...';
  }

  @override
  void didUpdateWidget(covariant MapViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool coordsChanged = oldWidget.initialLat != widget.initialLat ||
        oldWidget.initialLng != widget.initialLng;
    final bool addressChanged = oldWidget.initialAddress != widget.initialAddress;

    if (coordsChanged || addressChanged) {
      setState(() {
        selectedLat = widget.initialLat;
        selectedLng = widget.initialLng;
        if (widget.initialAddress != null && widget.initialAddress!.trim().isNotEmpty) {
          selectedAddress = widget.initialAddress!.trim();
        }
      });
      if (Complaint.isValidCoordinates(selectedLat, selectedLng)) {
        _moveCamera(selectedLat, selectedLng);
      }
    }
    
    final bool becameVisible = !oldWidget.isVisible && widget.isVisible;
    if (becameVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _buildMarkers();
          _centerOnLatestComplaint();
        }
      });
    }

    bool complaintsChanged = oldWidget.complaints != widget.complaints ||
        oldWidget.complaints?.length != widget.complaints?.length ||
        oldWidget.onlyActive != widget.onlyActive ||
        coordsChanged ||
        becameVisible;

    if (!complaintsChanged && widget.complaints != null && oldWidget.complaints != null) {
      if (oldWidget.complaints!.length != widget.complaints!.length) {
        complaintsChanged = true;
      } else {
        for (int i = 0; i < widget.complaints!.length; i++) {
          final oldC = oldWidget.complaints![i];
          final newC = widget.complaints![i];
          if (oldC.complaintId != newC.complaintId ||
              oldC.status != newC.status ||
              oldC.severity != newC.severity ||
              oldC.progressPercentage != newC.progressPercentage ||
              oldC.isActive != newC.isActive ||
              oldC.feedback != newC.feedback) {
            complaintsChanged = true;
            break;
          }
        }
      }
    }

    if (complaintsChanged) {
      _buildMarkers();
      _centerOnLatestComplaint();
    }
  }

  void _centerOnLatestComplaint() {
    if (!widget.isPickerMode && widget.complaints != null && widget.complaints!.isNotEmpty) {
      final latest = widget.complaints!.firstWhere(
        (c) => Complaint.isValidCoordinates(c.latitude, c.longitude) && (!widget.onlyActive || c.isActive),
        orElse: () => widget.complaints!.first,
      );
      if (Complaint.isValidCoordinates(latest.latitude, latest.longitude)) {
        _moveCamera(latest.latitude, latest.longitude);
      }
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    mapController = controller;
    controller.onCircleTapped.add(_onCircleTapped);
  }

  void _onStyleLoaded() {
    _isStyleLoaded = true;
    _buildMarkers();
    _centerOnLatestComplaint();
  }

  void _onCircleTapped(Circle circle) {
    if (circle.data == null) return;

    String? complaintId;
    if (circle.data is Map) {
      final mapData = circle.data as Map;
      complaintId = mapData['complaintId']?.toString().trim();
    } else {
      complaintId = circle.data?.toString().trim();
    }

    if (complaintId == null || complaintId.isEmpty) return;

    final allComplaints = widget.complaints ?? [];
    Complaint? tappedComplaint;
    for (var c in allComplaints) {
      if (c.complaintId.trim().toLowerCase() == complaintId.toLowerCase()) {
        tappedComplaint = c;
        break;
      }
    }

    if (tappedComplaint == null) return;

    // Requirement 4: Show ONLY the complaints represented by that marker or cluster.
    // Never mix complaints from unrelated locations.
    final List<Complaint> clusterComplaints = [];
    clusterComplaints.add(tappedComplaint);

    for (var c in allComplaints) {
      if (c.complaintId.trim().toLowerCase() == tappedComplaint.complaintId.trim().toLowerCase()) continue;
      if (widget.onlyActive && (!c.isActive || c.isCompleted || c.isRejected)) continue;

      // Group only complaints that are strictly at the identical coordinates or within close proximity (<= 12 meters)
      final bool isExactSame = (c.latitude == tappedComplaint.latitude && c.longitude == tappedComplaint.longitude);
      if (isExactSame || Geolocator.distanceBetween(tappedComplaint.latitude, tappedComplaint.longitude, c.latitude, c.longitude) <= 12.0) {
        clusterComplaints.add(c);
      }
    }

    clusterComplaints.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _showComplaintPopup(context, tappedComplaint, clusterComplaints);
  }

  void _showComplaintPopup(BuildContext context, Complaint tapped, List<Complaint> cluster) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final bool isMulti = cluster.length > 1;

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isMulti ? Icons.layers_rounded : Icons.location_on_rounded,
                        color: AppTheme.primaryBlue,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isMulti ? 'Incidents at this Spot (${cluster.length})' : 'Incident Details',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),

              if (isMulti)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tapped.address,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              const Divider(height: 1),
              const SizedBox(height: 12),

              // Content: If multi, list all complaints in this cluster; if single, full details card
              if (isMulti)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: cluster.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final c = cluster[index];
                      final bool isSelected = c.complaintId == tapped.complaintId;

                      return GlassCard(
                        borderRadius: 14,
                        padding: const EdgeInsets.all(12),
                        border: isSelected ? Border.all(color: AppTheme.primaryBlue, width: 1.5) : null,
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          if (widget.onComplaintTap != null) {
                            widget.onComplaintTap!(c);
                          }
                        },
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 48,
                                height: 48,
                                color: Colors.blue.shade50,
                                child: (c.imageUrl.isNotEmpty && (c.imageUrl.startsWith('http') || c.imageUrl.startsWith('data:')))
                                    ? (c.imageUrl.startsWith('data:')
                                        ? Image.memory(
                                            base64Decode(c.imageUrl.contains(',') ? c.imageUrl.split(',').last : c.imageUrl),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.add_road, color: Colors.blue),
                                          )
                                        : Image.network(
                                            c.imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.add_road, color: Colors.blue),
                                          ))
                                    : const Icon(Icons.add_road, color: Colors.blue),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        c.complaintId,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppTheme.primaryDark,
                                        ),
                                      ),
                                      // Requirement 2: Own severity badge with own severity color
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: c.severityColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          c.severity,
                                          style: TextStyle(
                                            color: c.severityColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          c.status,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      const Text(
                                        'View Details',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryBlue,
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, size: 16, color: AppTheme.primaryBlue),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                )
              else
                // Single complaint popup details
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tapped.complaintId,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tapped.severityColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tapped.severity,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: tapped.severityColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            tapped.status,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tapped.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (tapped.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        tapped.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tapped.address,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 1,
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text(
                          'View Incident Details',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          if (widget.onComplaintTap != null) {
                            widget.onComplaintTap!(tapped);
                          }
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _buildMarkers() async {
    if (mapController == null || !_isStyleLoaded) return;
    if (_isBuildingMarkers) {
      _needsRebuildMarkers = true;
      return;
    }
    _isBuildingMarkers = true;
    _needsRebuildMarkers = false;

    try {
      await mapController!.clearCircles();

      if (widget.complaints != null) {
        final eligible = widget.complaints!.where((c) {
          if (!Complaint.isValidCoordinates(c.latitude, c.longitude)) return false;
          if (widget.onlyActive && (!c.isActive || c.isCompleted || c.isRejected)) return false;
          // Requirement 6: Exclude hardcoded or demo complaints
          final cid = c.complaintId.trim().toUpperCase();
          if (cid == 'RW-8901' || cid == 'RW-8902' || cid == 'RW-8903') return false;
          return true;
        }).toList();

        // 1. Group complaints by identical or very close coordinates (within 12 meters)
        final List<List<Complaint>> coordinateGroups = [];
        for (var c in eligible) {
          bool addedToGroup = false;
          for (var group in coordinateGroups) {
            final ref = group.first;
            final bool isExactSame = (ref.latitude == c.latitude && ref.longitude == c.longitude);
            if (isExactSame || Geolocator.distanceBetween(ref.latitude, ref.longitude, c.latitude, c.longitude) <= 12.0) {
              group.add(c);
              addedToGroup = true;
              break;
            }
          }
          if (!addedToGroup) {
            coordinateGroups.add([c]);
          }
        }

        // Render older groups first, newest groups last so newest pins stay on top
        coordinateGroups.sort((a, b) {
          final aLatest = a.map((c) => c.createdAt).reduce((v, e) => v.isAfter(e) ? v : e);
          final bLatest = b.map((c) => c.createdAt).reduce((v, e) => v.isAfter(e) ? v : e);
          return aLatest.compareTo(bLatest);
        });

        // 2. Add marker for EVERY complaint:
        // - Single complaint at location: placed at actual coordinates
        // - Multiple complaints at identical/close location: apply small visual radial offset
        //   so markers do not completely overlap, while preserving actual coordinates in c.latitude / c.longitude
        // - Requirement 2: EACH marker strictly uses its OWN complaint's severity color:
        //   Emergency = Red (#E53935), Medium = Yellow (#F59E0B), Low = Green (#43A047)
        for (var group in coordinateGroups) {
          final int count = group.length;
          final Complaint ref = group.first;
          final double anchorLat = ref.latitude;
          final double anchorLng = ref.longitude;

          const double offsetMeters = 14.0;
          final double latRad = anchorLat * (pi / 180.0);
          final double deltaLat = offsetMeters / 111320.0;
          final double cosLat = cos(latRad).abs().clamp(0.1, 1.0);
          final double deltaLng = offsetMeters / (111320.0 * cosLat);

          for (int i = 0; i < count; i++) {
            final c = group[i];
            double renderLat = c.latitude;
            double renderLng = c.longitude;

            if (count > 1) {
              final double angle = (2.0 * pi * i / count) - (pi / 2.0);
              renderLat = anchorLat + deltaLat * sin(angle);
              renderLng = anchorLng + deltaLng * cos(angle);
            }

            await mapController!.addCircle(
              CircleOptions(
                geometry: LatLng(renderLat, renderLng),
                circleColor: c.severityHexColor,
                circleRadius: 8.5,
                circleStrokeColor: '#FFFFFF',
                circleStrokeWidth: 2.0,
                circleOpacity: 0.95,
              ),
              {
                'complaintId': c.complaintId,
                'anchorLat': anchorLat,
                'anchorLng': anchorLng,
                'groupSize': count,
              },
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error building map markers: $e');
    } finally {
      _isBuildingMarkers = false;
      if (_needsRebuildMarkers) {
        _buildMarkers();
      }
    }
  }

  Future<void> _moveCamera(double lat, double lng) async {
    if (mapController != null && Complaint.isValidCoordinates(lat, lng)) {
      mapController!.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(lat, lng),
        15.0,
      ));
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied, we cannot request permissions.');
      } 

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      final lat = position.latitude;
      final lng = position.longitude;

      if (widget.isPickerMode) {
        final freshAddress = await LocationService.reverseGeocode(lat, lng);
        setState(() {
          selectedLat = lat;
          selectedLng = lng;
          selectedAddress = freshAddress;
        });
        if (widget.onLocationSelected != null) {
          widget.onLocationSelected!(lat, lng, freshAddress);
        }
      }

      await _moveCamera(lat, lng);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: widget.isPickerMode ? 300 : 280,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            MapLibreMap(
              styleString: 'https://tiles.openfreemap.org/styles/liberty',
              initialCameraPosition: CameraPosition(
                target: LatLng(widget.initialLat, widget.initialLng),
                zoom: 13.0,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
              myLocationEnabled: !kIsWeb,
              onCameraIdle: () async {
                if (widget.isPickerMode && mapController != null) {
                  final position = mapController!.cameraPosition;
                  if (position != null) {
                    final lat = position.target.latitude;
                    final lng = position.target.longitude;
                    
                    if (lat != selectedLat || lng != selectedLng) {
                      final freshAddress = await LocationService.reverseGeocode(lat, lng);
                      if (mounted) {
                        setState(() {
                          selectedLat = lat;
                          selectedLng = lng;
                          selectedAddress = freshAddress;
                        });
                        if (widget.onLocationSelected != null) {
                          widget.onLocationSelected!(lat, lng, freshAddress);
                        }
                      }
                    }
                  }
                }
              },
            ),

            if (widget.isPickerMode)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 42.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDark,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8)
                          ],
                        ),
                        child: const Text(
                          'Move map to select',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.location_on_rounded,
                        size: 42,
                        color: AppTheme.emergencyRed,
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              top: 12,
              right: 12,
              child: FloatingActionButton(
                heroTag: null,
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryBlue,
                onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                child: _isLoadingLocation 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              ),
            ),
            
            // Attribution
            Positioned(
              bottom: 50,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'OpenFreeMap © OpenMapTiles Data from OpenStreetMap',
                  style: TextStyle(fontSize: 8, color: Colors.black87),
                ),
              ),
            ),

            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                borderRadius: 14,
                opacity: 0.95,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.isPickerMode
                            ? '$selectedAddress (${selectedLat.toStringAsFixed(4)}, ${selectedLng.toStringAsFixed(4)})'
                            : 'Map View: Pins (Red=Emergency, Yellow=Medium, Green=Low)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
  }
}
