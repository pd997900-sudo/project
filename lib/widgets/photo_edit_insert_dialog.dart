import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PhotoEditInsertDialog extends StatefulWidget {
  final String imageUrl;
  final Function(String finalUrl) onInsertPhoto;
  final bool isProfilePhoto;

  const PhotoEditInsertDialog({
    super.key,
    required this.imageUrl,
    required this.onInsertPhoto,
    this.isProfilePhoto = false,
  });

  @override
  State<PhotoEditInsertDialog> createState() => _PhotoEditInsertDialogState();
}

class _PhotoEditInsertDialogState extends State<PhotoEditInsertDialog> {
  double _scale = 1.0;
  int _rotationQuarterTurns = 0;

  Widget _buildPreviewImage(String url, {required Widget Function() errorBuilder}) {
    final cleanUrl = url.trim();
    if (cleanUrl.startsWith('data:')) {
      try {
        final base64Str = cleanUrl.contains(',') ? cleanUrl.split(',').last : cleanUrl;
        return Image.memory(
          base64Decode(base64Str),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => errorBuilder(),
        );
      } catch (_) {
        return errorBuilder();
      }
    } else if (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://') || cleanUrl.startsWith('blob:')) {
      return Image.network(
        cleanUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => errorBuilder(),
      );
    } else {
      try {
        final file = File(cleanUrl);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => errorBuilder(),
          );
        }
      } catch (_) {}
      return Image.network(
        cleanUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => errorBuilder(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.crop_rounded, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    Text(
                      widget.isProfilePhoto ? 'Edit & Insert Profile Photo' : 'Preview & Insert Damage Photo',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Photo Preview Container
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: widget.isProfilePhoto
                    ? Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primaryBlue, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                          ],
                        ),
                        child: ClipOval(
                          child: SizedBox(
                            width: 140,
                            height: 140,
                            child: RotatedBox(
                              quarterTurns: _rotationQuarterTurns,
                              child: Transform.scale(
                                scale: _scale,
                                child: _buildPreviewImage(
                                  widget.imageUrl,
                                  errorBuilder: () => const Icon(Icons.person, size: 80, color: AppTheme.primaryDark),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.4), width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 190,
                            width: double.infinity,
                            child: RotatedBox(
                              quarterTurns: _rotationQuarterTurns,
                              child: Transform.scale(
                                scale: _scale,
                                child: _buildPreviewImage(
                                  widget.imageUrl,
                                  errorBuilder: () => const Icon(Icons.broken_image_rounded, size: 60, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 14),

            // Edit Controls (Zoom & Rotate)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out_rounded, color: AppTheme.primaryDark),
                  tooltip: 'Zoom Out',
                  onPressed: () {
                    if (_scale > 0.8) setState(() => _scale -= 0.15);
                  },
                ),
                Text(
                  'Zoom ${(_scale * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in_rounded, color: AppTheme.primaryDark),
                  tooltip: 'Zoom In',
                  onPressed: () {
                    if (_scale < 2.0) setState(() => _scale += 0.15);
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.rotate_right_rounded, color: AppTheme.primaryBlue),
                  tooltip: 'Rotate Photo',
                  onPressed: () {
                    setState(() => _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4);
                  },
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Action Buttons (Cancel / Insert)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onInsertPhoto(widget.imageUrl);
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Insert Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
