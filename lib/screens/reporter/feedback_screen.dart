import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import '../../models/complaint_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../../services/supabase_service.dart';

enum FeedbackScreenState {
  loading,
  notSubmitted,
  saving,
  saved,
  editMode,
}

class FeedbackScreen extends StatefulWidget {
  final Complaint complaint;

  const FeedbackScreen({super.key, required this.complaint});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late double _rating;
  late TextEditingController _commentsController;
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _isSaved = false;
  bool _isEditingExisting = false;

  FeedbackScreenState get currentState {
    if (_isSubmitting) return FeedbackScreenState.saving;
    if (_isLoading) return FeedbackScreenState.loading;
    if (_isSaved) return FeedbackScreenState.saved;
    if (_isEditingExisting || _rating > 0) return FeedbackScreenState.editMode;
    return FeedbackScreenState.notSubmitted;
  }

  @override
  void initState() {
    super.initState();
    final initialFb = widget.complaint.feedback;
    if (initialFb != null && initialFb.rating > 0) {
      _rating = initialFb.rating;
      _commentsController = TextEditingController(text: initialFb.comments);
      _isEditingExisting = true;
    } else {
      _rating = 0.0;
      _commentsController = TextEditingController();
      _isEditingExisting = false;
    }

    // Check if the current authenticated reporter has already submitted feedback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkAndLoadExistingFeedback();
    });
  }

  Future<void> _checkAndLoadExistingFeedback() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.currentUser;
      final supaUid = SupabaseService.client?.auth.currentUser?.id;
      final activeReporterId = (supaUid != null && supaUid.isNotEmpty)
          ? supaUid
          : ((user != null && user.id.trim().isNotEmpty)
              ? user.id.trim()
              : (user?.email.trim().isNotEmpty == true
                  ? user!.email.trim()
                  : (widget.complaint.feedback?.reporterId ?? widget.complaint.reporterId)));

      // 1. Check local complaint object for THIS reporter's feedback
      final localFeedback = (activeReporterId.isNotEmpty
              ? widget.complaint.feedbackForReporter(activeReporterId)
              : null) ??
          ((user == null || (widget.complaint.feedback != null && _isFeedbackAuthor(auth, widget.complaint.feedback!)))
              ? widget.complaint.feedback
              : null);

      if (localFeedback != null && localFeedback.rating > 0 && mounted) {
        setState(() {
          _rating = localFeedback.rating;
          _commentsController.text = localFeedback.comments;
          _isEditingExisting = true;
          _isLoading = false;
        });
        return;
      }

      // 2. Check Supabase DB for this specific reporter's saved feedback
      if (SupabaseService.isConnected && activeReporterId.isNotEmpty) {
        final remoteRow = await SupabaseService.getComplaintFeedback(
          widget.complaint.complaintId,
          reporterId: activeReporterId,
        );
        if (remoteRow != null && mounted) {
          final fb = FeedbackModel.fromJson(remoteRow);
          if (fb.rating > 0 && mounted) {
            setState(() {
              _rating = fb.rating;
              _commentsController.text = fb.comments;
              _isEditingExisting = true;
              _isLoading = false;
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Notice checking existing feedback in screen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isFeedbackAuthor(AuthProvider auth, FeedbackModel fb) {
    final supaUid = SupabaseService.client?.auth.currentUser?.id.trim().toLowerCase();
    final fbId = fb.reporterId.trim().toLowerCase();
    final fbName = (fb.reporterName ?? '').trim().toLowerCase();

    if (supaUid != null && supaUid.isNotEmpty) {
      if (fbId == supaUid || fbId.contains(supaUid) || supaUid.contains(fbId)) return true;
    }

    final user = auth.currentUser;
    if (user == null) return false;

    final userId = user.id.trim().toLowerCase();
    final userEmail = user.email.trim().toLowerCase();
    final userName = user.name.trim().toLowerCase();

    if (userId.isNotEmpty && (fbId == userId || fbId.contains(userId) || userId.contains(fbId))) return true;
    if (userEmail.isNotEmpty && (fbId == userEmail || fbName == userEmail || userEmail.contains(fbId))) return true;
    if (userName.isNotEmpty && (fbName == userName || userName.contains(fbName))) return true;

    return false;
  }

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  void _submitFeedback() async {
    // Requirement 5: Valid rating is required (1 to 5 stars)
    if (_rating < 1.0 || _rating > 5.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a star rating from 1 to 5 before submitting.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
      final user = auth.currentUser;

      final supaUid = SupabaseService.client?.auth.currentUser?.id;
      final activeReporterId = (supaUid != null && supaUid.isNotEmpty)
          ? supaUid
          : ((user != null && user.id.trim().isNotEmpty)
              ? user.id.trim()
              : (user?.email.trim().isNotEmpty == true
                  ? user!.email.trim()
                  : widget.complaint.reporterId));

      String activeReporterName = 'Reporter';
      if (user != null && user.name.trim().isNotEmpty && user.hasValidName) {
        activeReporterName = user.name.trim();
      } else if (user != null && user.name.trim().isNotEmpty && !user.name.contains('@')) {
        activeReporterName = user.name.trim();
      } else if (user != null && user.email.contains('@')) {
        activeReporterName = user.email.split('@').first.trim();
      } else if (widget.complaint.reporterName.isNotEmpty) {
        activeReporterName = widget.complaint.reporterName;
      }

      // Requirement 6: Save to Supabase and wait for save operation to succeed
      final result = await complaintProv.submitFeedback(
        complaintId: widget.complaint.complaintId,
        reporterId: activeReporterId,
        reporterName: activeReporterName,
        rating: _rating,
        comments: _commentsController.text.trim(),
      );

      if (!mounted) return;

      if (result.success) {
        final savedFeedback = result.feedback ??
            FeedbackModel(
              feedbackId: 'FB-${DateTime.now().millisecondsSinceEpoch}',
              complaintId: widget.complaint.complaintId,
              reporterId: activeReporterId,
              reporterName: activeReporterName,
              rating: _rating,
              comments: _commentsController.text.trim(),
            );

        // Preserve rating and comments - do NOT reset to zero
        setState(() {
          _rating = savedFeedback.rating;
          _isSubmitting = false;
          _isSaved = true;
          _isEditingExisting = true;
        });

        // Requirement 7: Show exact SnackBar message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback submitted successfully!'),
            backgroundColor: AppTheme.successGreen,
          ),
        );

        if (Navigator.canPop(context)) {
          Navigator.pop(context, savedFeedback);
        }
      } else {
        // Requirement 9: Show error message and preserve selected rating and comments
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Failed to submit feedback. Please try again.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting feedback: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRatingValid = _rating >= 1.0 && _rating <= 5.0;
    final bool hasExistingFeedback = _isEditingExisting ||
        (widget.complaint.feedback != null && widget.complaint.feedback!.rating > 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Repair Quality Feedback'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              // Header Glass Card
              GlassCard(
                borderRadius: 24,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppTheme.successGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.rate_review_rounded, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Rate Complaint ${widget.complaint.complaintId}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.complaint.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    // Interactive Star Rating Bar
                    const Text(
                      'How satisfied are you with the repair speed & quality?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    RatingBar.builder(
                      initialRating: _rating,
                      minRating: 0,
                      direction: Axis.horizontal,
                      allowHalfRating: false,
                      itemCount: 5,
                      unratedColor: Colors.grey.shade400,
                      itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                      itemBuilder: (context, _) => const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                      ),
                      onRatingUpdate: (rating) {
                        setState(() {
                          _rating = rating;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _rating <= 0
                          ? '0 / Not Selected'
                          : '${_rating == _rating.roundToDouble() ? _rating.toInt() : _rating.toStringAsFixed(1)} / 5 Stars',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Feedback Text Area Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Additional Comments & Feedback',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _commentsController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Share any notes regarding road smoothness, safety barriers, or community effort...',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Submit / Update Feedback Button
              GradientButton(
                text: hasExistingFeedback ? 'Update Feedback' : 'Submit Feedback',
                icon: Icons.send_rounded,
                isLoading: _isSubmitting,
                onPressed: (isRatingValid && !_isSubmitting) ? _submitFeedback : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
