import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/complaint_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../providers/complaint_provider.dart';
import '../../widgets/real_time_camera_dialog.dart';
import '../../widgets/photo_edit_insert_dialog.dart';
import '../../widgets/camera_web_helper.dart';

class WorkCompletionScreen extends StatefulWidget {
  final Complaint complaint;

  const WorkCompletionScreen({super.key, required this.complaint});

  @override
  State<WorkCompletionScreen> createState() => _WorkCompletionScreenState();
}

class _WorkCompletionScreenState extends State<WorkCompletionScreen> {
  final _completionNotesController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String? _afterImageUrl;

  @override
  void dispose() {
    _completionNotesController.dispose();
    super.dispose();
  }

  void _showPhotoEditDialog(String photoUrl) {
    showDialog(
      context: context,
      builder: (editCtx) => PhotoEditInsertDialog(
        imageUrl: photoUrl,
        onInsertPhoto: (finalUrl) {
          setState(() {
            _afterImageUrl = finalUrl;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Completion photo inserted successfully!'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
        },
      ),
    );
  }

  void _showImageSourcePicker() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.add_a_photo_rounded, color: AppTheme.successGreen),
            SizedBox(width: 10),
            Text('Upload Completion Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryDark,
                child: Icon(Icons.photo_library_rounded, color: Colors.white),
              ),
              title: const Text('Select from Gallery / Device', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(dialogCtx);
                if (kIsWeb) {
                  CameraWebHelper.pickGalleryImage((base64Url) {
                    if (mounted) {
                      setState(() {
                        _afterImageUrl = base64Url;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Completion photo added successfully!'),
                          backgroundColor: AppTheme.successGreen,
                        ),
                      );
                    }
                  });
                } else {
                  final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (picked != null) {
                    final bytes = await picked.readAsBytes();
                    final imageUrl = Uri.dataFromBytes(bytes, mimeType: 'image/jpeg').toString();
                    if (mounted) {
                      setState(() {
                        _afterImageUrl = imageUrl;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Completion photo added successfully!'),
                          backgroundColor: AppTheme.successGreen,
                        ),
                      );
                    }
                  }
                }
              },
            ),
            const Divider(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const CircleAvatar(
                backgroundColor: AppTheme.successGreen,
                child: Icon(Icons.camera_alt_rounded, color: Colors.white),
              ),
              title: const Text('Capture with Camera', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(dialogCtx);
                showDialog(
                  context: context,
                  builder: (camCtx) => RealTimeCameraDialog(
                    isProfilePhoto: false,
                    onPhotoCaptured: (capturedUrl) {
                      if (mounted) {
                        setState(() {
                          _afterImageUrl = capturedUrl;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('GPS stamped completion photo captured & added successfully!'),
                            backgroundColor: AppTheme.successGreen,
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _markCompleted() async {
    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);

    final result = await complaintProv.completeWork(
      complaintId: widget.complaint.complaintId,
      afterImageUrl: _afterImageUrl ?? 'https://images.unsplash.com/photo-1513836279014-a89f7a76ae86?w=800&auto=format&fit=crop',
      completionNotes: _completionNotesController.text.trim().isEmpty
          ? 'Road damage successfully repaired and inspect verified by community crew.'
          : _completionNotesController.text.trim(),
    );

    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Work Completed! Status = Completed. Citizen reporter notified.'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete work: ${result.errorMessage ?? 'Database update error'}'),
            backgroundColor: AppTheme.emergencyRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Complete Work: ${widget.complaint.complaintId}'),
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
                padding: const EdgeInsets.all(20),
                backgroundColor: AppTheme.successGreen,
                opacity: 0.95,
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 50),
                    const SizedBox(height: 10),
                    const Text(
                      'Final Work Completion',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Complaint ${widget.complaint.complaintId}',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Damage After Repair Photo Picker
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.photo_camera, color: AppTheme.successGreen),
                        SizedBox(width: 8),
                        Text('Attach Completed Work Photo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_afterImageUrl != null) ...[
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _showPhotoEditDialog(_afterImageUrl!),
                            child: Container(
                              height: 180,
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
                                      _afterImageUrl!,
                                      height: 180,
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
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.zoom_in_rounded, color: Colors.white, size: 18),
                                          SizedBox(width: 6),
                                          Text(
                                            'Tap photo to open & view full size / edit',
                                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
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
                                    _afterImageUrl = null;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      InkWell(
                        onTap: _showImageSourcePicker,
                        child: Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppTheme.successGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.successGreen.withOpacity(0.4), width: 1.5),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt, color: AppTheme.successGreen, size: 42),
                              SizedBox(height: 8),
                              Text('Tap to capture or upload completed road image', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.successGreen)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Completion Notes Field
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Completion Summary Notes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _completionNotesController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Enter final inspection notes, materials used, and sign-off details...',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Submit Completion Button
              GradientButton(
                text: 'Mark Work 100% Completed',
                icon: Icons.task_alt_rounded,
                gradientColors: const [
                  Color(0xFF2E7D32),
                  Color(0xFF43A047),
                  Color(0xFF66BB6A),
                ],
                onPressed: _markCompleted,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
