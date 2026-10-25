import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/complaint_model.dart';
import '../providers/complaint_provider.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class ViewVotersDialog extends StatefulWidget {
  final Complaint complaint;

  const ViewVotersDialog({super.key, required this.complaint});

  static Future<void> show(BuildContext context, Complaint complaint) {
    return showDialog(
      context: context,
      builder: (context) => ViewVotersDialog(complaint: complaint),
    );
  }

  @override
  State<ViewVotersDialog> createState() => _ViewVotersDialogState();
}

class _ViewVotersDialogState extends State<ViewVotersDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;
  List<VoterInfo> _voters = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchVoters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchVoters() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
      final fetchedVoters = await complaintProv.getVotersForComplaint(widget.complaint);

      if (!mounted) return;
      setState(() {
        _voters = fetchedVoters;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final genuineVoters = _voters.where((v) => v.isGenuine).toList();
    final fakeVoters = _voters.where((v) => !v.isGenuine).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 680),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
              spreadRadius: 4,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.people_alt_rounded, color: AppTheme.primaryBlue, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Complaint Voter Details',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Complaint ID: ${widget.complaint.complaintId}',
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Summary Badges Row
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Genuine: ${widget.complaint.realVotes}',
                                style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.emergencyRed.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cancel_rounded, color: AppTheme.emergencyRed, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Fake: ${widget.complaint.fakeVotes}',
                                style: const TextStyle(
                                  color: AppTheme.emergencyRed,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              color: Colors.white.withOpacity(0.02),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primaryBlue,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: [
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🟢 Genuine Voters'),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${genuineVoters.length}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF00E676)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🔴 Fake Voters'),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.emergencyRed.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${fakeVoters.length}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.emergencyRed),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppTheme.primaryBlue),
                          SizedBox(height: 14),
                          Text(
                            'Fetching voter records from Supabase database...',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppTheme.emergencyRed, size: 44),
                                const SizedBox(height: 12),
                                const Text(
                                  'Database Error Loading Voters',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _fetchVoters,
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('Retry'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryBlue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildVoterList(genuineVoters, isGenuineList: true),
                            _buildVoterList(fakeVoters, isGenuineList: false),
                          ],
                        ),
            ),

            // Footer Close Button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: Colors.white.withOpacity(0.08),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatVoteDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Time unavailable';
    // Convert stored timestamp to device local timezone exactly once without manual offsets.
    return DateFormat('MMM d, yyyy • hh:mm a').format(dateTime.toLocal());
  }

  Widget _buildVoterList(List<VoterInfo> list, {required bool isGenuineList}) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isGenuineList ? Icons.check_circle_outline_rounded : Icons.report_problem_outlined,
                color: isGenuineList ? const Color(0xFF00E676).withOpacity(0.5) : AppTheme.emergencyRed.withOpacity(0.5),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                isGenuineList ? 'No Genuine Votes Recorded' : 'No Fake Votes Recorded',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                isGenuineList
                    ? 'No registered users have voted this complaint as genuine yet.'
                    : 'No registered users have flagged this complaint as fake yet.',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final voter = list[index];
        final rawName = voter.name.trim();
        final displayName = (rawName.isNotEmpty &&
                rawName != 'Registered Voter' &&
                rawName != 'Registered User' &&
                rawName != 'Name not available' &&
                !rawName.contains('@'))
            ? rawName
            : 'Name not available';
        final formattedDate = _formatVoteDateTime(voter.createdAt);

        final avatarLetter = (displayName != 'Name not available' && displayName.isNotEmpty)
            ? displayName[0].toUpperCase()
            : 'N';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isGenuineList
                  ? const Color(0xFF00E676).withOpacity(0.2)
                  : AppTheme.emergencyRed.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: isGenuineList
                    ? const Color(0xFF00E676).withOpacity(0.2)
                    : AppTheme.emergencyRed.withOpacity(0.2),
                child: Text(
                  avatarLetter,
                  style: TextStyle(
                    color: isGenuineList ? const Color(0xFF00E676) : AppTheme.emergencyRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Minimal Details: 1. Voter Name, 2. Vote Date & Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Voter Name (actual registered name / username or Registered User)
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Vote Submission Timestamp
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 13, color: Colors.white60),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            formattedDate,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Vote Choice Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isGenuineList
                      ? const Color(0xFF00E676).withOpacity(0.15)
                      : AppTheme.emergencyRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isGenuineList ? const Color(0xFF00E676) : AppTheme.emergencyRed,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  isGenuineList ? '🟢 Genuine' : '🔴 Fake',
                  style: TextStyle(
                    color: isGenuineList ? const Color(0xFF00E676) : AppTheme.emergencyRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
