import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_badge.dart';
import '../../providers/complaint_provider.dart';
import '../../models/complaint_model.dart';
import 'complaint_verification_screen.dart';

class CompletedWorksScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const CompletedWorksScreen({super.key, this.onBack});

  @override
  State<CompletedWorksScreen> createState() => _CompletedWorksScreenState();
}

class _CompletedWorksScreenState extends State<CompletedWorksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshComplaints());
  }

  void _refreshComplaints() {
    if (mounted) {
      context.read<ComplaintProvider>().refreshComplaints();
    }
  }

  Widget _buildDamageImage(String? rawUrl, {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    final url = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : '';
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildFallbackBox(height, width),
        );
      } catch (_) {
        return _buildFallbackBox(height, width);
      }
    } else if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:')) {
      return Image.network(
        url,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildFallbackBox(height, width),
      );
    }
    return _buildFallbackBox(height, width);
  }

  Widget _buildFallbackBox(double? height, double? width) {
    return Container(
      height: height,
      width: width,
      color: Colors.blue.shade100,
      child: const Icon(Icons.add_road_rounded, color: Colors.blue, size: 30),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);

    final completedList = complaintProv.complaints.where((c) => c.status == 'Completed').toList();

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
        title: const Text('Completed Repair Gallery'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => context.read<ComplaintProvider>().refreshComplaints(),
                  child: completedList.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.check_circle_outline_rounded, size: 60, color: Colors.grey),
                                  SizedBox(height: 12),
                                  Text('No completed works logged yet.', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: completedList.length,
                          itemBuilder: (context, index) {
                            final c = completedList[index];
                            final formattedDate = DateFormat('MMM dd, yyyy').format(c.createdAt.toLocal());
                            final allFeedbacks = c.allFeedbacks.isNotEmpty
                                ? c.allFeedbacks
                                : (c.feedback != null ? [c.feedback!] : <FeedbackModel>[]);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ComplaintVerificationScreen(complaint: c),
                                    ),
                                  ).then((_) => _refreshComplaints());
                                },
                              child: GlassCard(
                                borderRadius: 20,
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.complaintId,
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryDark, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      StatusBadge(status: c.status),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    c.title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Completed on: $formattedDate',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 14),

                                  // Side-by-side Before & After Photos
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('BEFORE REPAIR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.emergencyRed)),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: _buildDamageImage(
                                                c.beforeImageUrl ?? c.imageUrl,
                                                height: 100,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('AFTER REPAIR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.successGreen)),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: _buildDamageImage(
                                                c.afterImageUrl ?? c.imageUrl,
                                                height: 100,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  if (c.completionNotes != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Crew Notes: ${c.completionNotes}',
                                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                                      ),
                                    ),
                                  ],

                                  if (allFeedbacks.isNotEmpty) ...[
                                    for (var fb in allFeedbacks) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF8E1),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.amber.shade200, width: 0.8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${fb.rating.toStringAsFixed(1)}/5.0 Rating: ',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                            Expanded(
                                              child: Text(
                                                fb.comments.trim().isNotEmpty
                                                    ? '"${fb.comments.trim()}"'
                                                    : '"Verified repair quality"',
                                                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
