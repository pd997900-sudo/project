import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_badge.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import 'complaint_verification_screen.dart';

class ComplaintListScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ComplaintListScreen({super.key, this.onBack});

  @override
  State<ComplaintListScreen> createState() => _ComplaintListScreenState();
}

class _ComplaintListScreenState extends State<ComplaintListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ComplaintProvider>().refreshComplaints();
      }
    });
  }

  final List<String> _filters = [
    'All',
    'Pending Verification',
    'Emergency',
    'Accepted',
    'Completed',
  ];

  Widget _buildDamageImage(String? rawUrl) {
    final url = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : '';
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
        );
      } catch (_) {
        return _buildFallbackThumbnail();
      }
    } else if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:')) {
      return Image.network(
        url,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
      );
    }
    return _buildFallbackThumbnail();
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.blue.shade100,
      child: const Icon(Icons.add_road_rounded, color: Colors.blue),
    );
  }

  void _refreshComplaints() {
    if (mounted) {
      context.read<ComplaintProvider>().refreshComplaints();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProv = Provider.of<AuthProvider>(context);
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final userDistrict = authProv.userDistrict;
    final userState = authProv.userState;
    final selectedFilter = complaintProv.selectedFilter;
    final complaintsList = complaintProv.filteredComplaintsForDistrict(userDistrict, userState);

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Community Feed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('📍 $userDistrict District, $userState', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: Column(
          children: [
            // Search Input Field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (val) => complaintProv.setSearchQuery(val),
                decoration: InputDecoration(
                  hintText: 'Search complaints by ID, title or street...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue),
                  suffixIcon: complaintProv.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => complaintProv.setSearchQuery(''),
                        )
                      : null,
                ),
              ),
            ),

            // Horizontal Scroll Filter Chips Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: _filters.map((filter) {
                  final isSelected = selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(filter),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      selectedColor: AppTheme.primaryDark,
                      backgroundColor: Colors.white,
                      elevation: 2,
                      onSelected: (val) {
                        complaintProv.setFilter(filter);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 6),

            // Complaint Cards Feed List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => context.read<ComplaintProvider>().refreshComplaints(),
                child: complaintsList.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.rule_folder_outlined, size: 60, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('No complaints matching this filter.', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: complaintsList.length,
                        itemBuilder: (context, index) {
                          final c = complaintsList[index];
                          final isGenuine = c.realVotes >= c.fakeVotes && c.totalVotes > 0;
                          final isFake = c.fakeVotes > c.realVotes && c.totalVotes > 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            child: GlassCard(
                              borderRadius: 20,
                              padding: const EdgeInsets.all(16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ComplaintVerificationScreen(complaint: c),
                                  ),
                                ).then((_) => _refreshComplaints());
                              },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: _buildDamageImage(c.imageUrl),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  c.complaintId,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.primaryDark,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              SeverityBadge(severity: c.severity),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            c.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Reporter: ${c.reporterName}',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    StatusBadge(status: c.status),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isFake
                                            ? AppTheme.emergencyRed.withOpacity(0.12)
                                            : (isGenuine
                                                ? const Color(0xFF00E676).withOpacity(0.12)
                                                : AppTheme.primaryBlue.withOpacity(0.08)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isFake
                                                ? Icons.report_problem_rounded
                                                : (isGenuine ? Icons.verified_rounded : Icons.how_to_vote_rounded),
                                            size: 12,
                                            color: isFake
                                                ? AppTheme.emergencyRed
                                                : (isGenuine ? const Color(0xFF00E676) : AppTheme.primaryBlue),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            c.totalVotes == 0
                                                ? 'Poll Open'
                                                : (isGenuine
                                                    ? 'Community Verified (${c.realPercentage.toStringAsFixed(0)}%)'
                                                    : 'Community Disputed (${c.fakePercentage.toStringAsFixed(0)}%)'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isFake
                                                  ? AppTheme.emergencyRed
                                                  : (isGenuine ? const Color(0xFF2E7D32) : AppTheme.primaryBlue),
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
                        );
                      },
                    ),
                ),
            ),
          ],
        ),
      ),
    );
  }
}
