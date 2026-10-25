import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

/// Interactive dialog for previewing captured photo with real-time GPS geotag metadata
class GeotagPreviewDialog extends StatefulWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final GeotagLocation location;
  final String category;
  final String description;
  final String severity;
  final String reporterId;
  final VoidCallback onRetake;
  final Function(String finalUploadedUrl, GeotagLocation loc) onConfirmed;

  const GeotagPreviewDialog({
    super.key,
    this.imageBytes,
    this.imageUrl,
    required this.location,
    required this.category,
    required this.description,
    required this.severity,
    required this.reporterId,
    required this.onRetake,
    required this.onConfirmed,
  });

  @override
  State<GeotagPreviewDialog> createState() => _GeotagPreviewDialogState();
}

class _GeotagPreviewDialogState extends State<GeotagPreviewDialog> {
  bool _isUploading = false;
  String? _uploadStatusText;
  late GeotagLocation _activeLocation;

  @override
  void initState() {
    super.initState();
    _activeLocation = widget.location;
  }

  void _showEditAddressDialog() {
    final controller = TextEditingController(text: _activeLocation.address);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_location_alt_rounded, color: AppTheme.primaryBlue),
            SizedBox(width: 8),
            Text('Edit / Confirm Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter or adjust your exact current physical address:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: 'e.g. Mevalurkuppam, Tamil Nadu, India',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newAddr = controller.text.trim();
              if (newAddr.isNotEmpty) {
                setState(() {
                  _activeLocation = _activeLocation.copyWith(address: newAddr);
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Save Address'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleConfirmAndUpload() async {
    setState(() {
      _isUploading = true;
      _uploadStatusText = 'Uploading geotagged photo to Supabase Storage...';
    });

    try {
      String finalImageUrl = widget.imageUrl ?? '';

      // Upload to Supabase Storage if image bytes available
      if (widget.imageBytes != null && widget.imageBytes!.isNotEmpty) {
        final fileName = 'road_damage_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final uploadedUrl = await SupabaseService.uploadReportImage(
          fileName: fileName,
          imageBytes: widget.imageBytes!,
          userId: widget.reporterId,
        );
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          finalImageUrl = uploadedUrl;
        }
      } else if (finalImageUrl.isEmpty && widget.imageUrl != null) {
        finalImageUrl = widget.imageUrl!;
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        Navigator.pop(context); // Close geotag preview dialog
        widget.onConfirmed(finalImageUrl, _activeLocation);
      }
    } catch (e) {
      debugPrint('Confirm photo upload error: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        Navigator.pop(context);
        widget.onConfirmed(widget.imageUrl ?? '', _activeLocation);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(_activeLocation.timestamp);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 580,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_rounded, color: AppTheme.successGreen, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Preview Geotagged Photo',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Image Preview Frame
              Container(
                height: 320,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.4), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.imageBytes != null && widget.imageBytes!.isNotEmpty)
                      Image.memory(
                        widget.imageBytes!,
                        fit: BoxFit.cover,
                      )
                    else if (widget.imageUrl != null && widget.imageUrl!.startsWith('data:image'))
                      Image.memory(
                        base64Decode(widget.imageUrl!.split(',').last),
                        fit: BoxFit.cover,
                      )
                    else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                      Image.network(
                        widget.imageUrl!,
                        fit: BoxFit.cover,
                      )
                    else
                      const Center(
                        child: Icon(Icons.photo_rounded, color: Colors.white38, size: 80),
                      ),

                    // Top Badge Overlay
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00E676), width: 1),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.gps_fixed_rounded, color: Color(0xFF00E676), size: 14),
                            SizedBox(width: 6),
                            Text(
                              'GPS STAMPED',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Captured Metadata Breakdown Card
              GlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _buildMetaRow(
                      Icons.location_on_rounded,
                      'Address',
                      _activeLocation.address,
                      iconColor: AppTheme.emergencyRed,
                      onEdit: _showEditAddressDialog,
                    ),
                    const Divider(height: 14),
                    _buildMetaRow(
                      Icons.public_rounded,
                      'Coordinates',
                      'Lat: ${_activeLocation.latitude.toStringAsFixed(6)}°, Long: ${_activeLocation.longitude.toStringAsFixed(6)}°',
                      iconColor: AppTheme.primaryBlue,
                    ),
                    const Divider(height: 14),
                    _buildMetaRow(
                      Icons.access_time_rounded,
                      'Captured At',
                      dateStr,
                      iconColor: Colors.amber.shade800,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (_isUploading) ...[
                Column(
                  children: [
                    const LinearProgressIndicator(color: AppTheme.primaryBlue),
                    const SizedBox(height: 10),
                    Text(
                      _uploadStatusText ?? 'Uploading to Supabase Storage & PostgreSQL...',
                      style: const TextStyle(color: AppTheme.primaryDark, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ] else ...[
                // Action Buttons: Retake vs Confirm & Upload
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // close preview
                          widget.onRetake(); // return to camera viewfinder
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retake Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryDark,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _handleConfirmAndUpload,
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: const Text('Confirm & Upload', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.successGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String title, String value, {Color iconColor = AppTheme.primaryBlue, VoidCallback? onEdit}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
              ),
            ],
          ),
        ),
        if (onEdit != null) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded, size: 12, color: AppTheme.primaryBlue),
                  SizedBox(width: 4),
                  Text('Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
