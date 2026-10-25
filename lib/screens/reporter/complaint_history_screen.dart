import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_badge.dart';
import '../../providers/complaint_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/complaint_model.dart';
import 'complaint_tracking_screen.dart';

class ComplaintHistoryScreen extends StatefulWidget {
  final String initialTab;
  final VoidCallback? onBack;
  final Function(String tab)? onTabChanged;

  const ComplaintHistoryScreen({
    super.key,
    this.initialTab = 'All',
    this.onBack,
    this.onTabChanged,
  });

  @override
  State<ComplaintHistoryScreen> createState() => _ComplaintHistoryScreenState();
}

class _ComplaintHistoryScreenState extends State<ComplaintHistoryScreen> {
  late String _activeTab;
  String _selectedSeverity = 'All';
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ComplaintProvider>().refreshComplaints();
      }
    });
  }

  Widget _buildDamageImage(String? rawUrl) {
    final url = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : '';
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
        );
      } catch (_) {
        return _buildFallbackThumbnail();
      }
    } else if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('blob:')) {
      return Image.network(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
      );
    }
    return _buildFallbackThumbnail();
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: 72,
      height: 72,
      color: AppTheme.primaryLight.withOpacity(0.2),
      child: const Icon(Icons.add_road_rounded, color: AppTheme.primaryDark),
    );
  }

  void _refreshComplaints() {
    if (mounted) {
      context.read<ComplaintProvider>().refreshComplaints();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);
    final authProv = Provider.of<AuthProvider>(context);
    final query = complaintProv.searchQuery.trim().toLowerCase();

    // Update controller text if synced externally
    if (_searchController.text != complaintProv.searchQuery) {
      _searchController.text = complaintProv.searchQuery;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
    }

    final filteredList = complaintProv.reporterComplaints.where((c) {
      final matchesSearch = query.isEmpty ||
          c.complaintId.toLowerCase().contains(query) ||
          c.title.toLowerCase().contains(query) ||
          c.address.toLowerCase().contains(query) ||
          c.category.toLowerCase().contains(query) ||
          c.severity.toLowerCase().contains(query) ||
          c.description.toLowerCase().contains(query) ||
          c.status.toLowerCase().contains(query);

      if (!matchesSearch) return false;

      // Filter by main tab
      if (_activeTab == 'Pending') {
        if (c.status == 'Completed' || c.status == 'Rejected') return false;
      } else if (_activeTab == 'Completed') {
        if (c.status != 'Completed') return false;
      }

      // Filter by severity option
      if (_selectedSeverity != 'All') {
        if (c.severity.toLowerCase() != _selectedSeverity.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();

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
        title: const Text('My Complaints History'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Search Input Box
              TextField(
                controller: _searchController,
                onChanged: (val) => complaintProv.setSearchQuery(val),
                decoration: InputDecoration(
                  hintText: 'Search by ID (e.g. RW-8945), title, or location...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue),
                  suffixIcon: complaintProv.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            complaintProv.setSearchQuery('');
                          },
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 16),

              // Filter Tabs (All, Pending, Completed)
              Row(
                children: ['All', 'Pending', 'Completed'].map((tab) {
                  final isSelected = _activeTab == tab;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeTab = tab;
                          if (tab == 'Completed') {
                            _selectedSeverity = 'All';
                          }
                        });
                        if (widget.onTabChanged != null) {
                          widget.onTabChanged!(tab);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryDark : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isSelected
                              ? [BoxShadow(color: AppTheme.primaryDark.withOpacity(0.3), blurRadius: 6)]
                              : [],
                        ),
                        child: Text(
                          tab,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Severity Filter Dropdown Menu - Shown on 'All' and 'Pending' tabs ONLY (Hidden on 'Completed')
              if (_activeTab != 'Completed') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSeverity,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryDark),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      items: [
                        DropdownMenuItem(
                          value: 'All',
                          child: Row(
                            children: const [
                              Icon(Icons.layers_outlined, color: AppTheme.primaryDark, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'All Severities (Low, Medium, Emergency)',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Low',
                          child: Row(
                            children: const [
                              Icon(Icons.check_circle_outline, color: AppTheme.successGreen, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Low Severity',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Medium',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Medium Severity',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Emergency',
                          child: Row(
                            children: const [
                              Icon(Icons.error_outline, color: AppTheme.emergencyRed, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Emergency Severity',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.emergencyRed),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSeverity = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Complaint List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => context.read<ComplaintProvider>().refreshComplaints(),
                  child: filteredList.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.inbox_outlined, size: 60, color: Colors.grey),
                                  SizedBox(height: 12),
                                  Text('No complaints found in this section.', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final c = filteredList[index];
                            final dateTimeStr = DateFormat('M/d/yyyy • hh:mm a').format(c.createdAt.toLocal());

                            return Container(
                              key: ValueKey(c.complaintId),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: GlassCard(
                                borderRadius: 18,
                                padding: const EdgeInsets.all(14),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ComplaintTrackingScreen(
                                        complaint: c,
                                        complaintId: c.complaintId,
                                      ),
                                    ),
                                  ).then((_) => _refreshComplaints());
                                },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Damage Photo Thumbnail Preview
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: _buildDamageImage(c.beforeImageUrl ?? c.imageUrl),
                                  ),
                                  const SizedBox(width: 12),

                                  // Complaint Information Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${c.complaintId} • $dateTimeStr',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.primaryDark,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            SeverityBadge(severity: c.severity),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          c.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on, size: 12, color: Colors.grey),
                                            const SizedBox(width: 3),
                                            Expanded(
                                              child: Text(
                                                c.address,
                                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // Mini Progress Bar
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: c.progressPercentage / 100.0,
                                                  backgroundColor: Colors.grey.shade200,
                                                  color: c.status == 'Completed' ? AppTheme.successGreen : AppTheme.primaryBlue,
                                                  minHeight: 5,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${c.progressPercentage.toInt()}%',
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        Wrap(
                                          alignment: WrapAlignment.spaceBetween,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                StatusBadge(status: c.status),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: c.isCommunityFlaggedFake
                                                        ? AppTheme.emergencyRed.withOpacity(0.12)
                                                        : (c.isCommunityVerifiedReal
                                                            ? const Color(0xFF00E676).withOpacity(0.12)
                                                            : AppTheme.primaryBlue.withOpacity(0.08)),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        c.isCommunityFlaggedFake
                                                            ? Icons.report_problem_rounded
                                                            : (c.isCommunityVerifiedReal ? Icons.verified_rounded : Icons.how_to_vote_rounded),
                                                        size: 11,
                                                        color: c.isCommunityFlaggedFake
                                                            ? AppTheme.emergencyRed
                                                            : (c.isCommunityVerifiedReal ? const Color(0xFF00E676) : AppTheme.primaryBlue),
                                                      ),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        '${c.realPercentage.toStringAsFixed(0)}% Real',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: c.isCommunityFlaggedFake
                                                              ? AppTheme.emergencyRed
                                                              : (c.isCommunityVerifiedReal ? const Color(0xFF2E7D32) : AppTheme.primaryBlue),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (_isOriginalReporter(authProv, c) && c.canBeDeleted) ...[
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.emergencyRed, size: 20),
                                                    tooltip: 'Delete Complaint',
                                                    onPressed: () => _confirmDeleteComplaint(context, complaintProv, c),
                                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                                    padding: EdgeInsets.zero,
                                                  ),
                                                  const SizedBox(width: 4),
                                                ],
                                                const Text(
                                                  'Track',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.primaryBlue,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const Icon(Icons.chevron_right, size: 16, color: AppTheme.primaryBlue),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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
      ),
    );
  }

  bool _isOriginalReporter(AuthProvider auth, Complaint c) {
    final user = auth.currentUser;
    if (user == null) return false;

    final userId = user.id.trim().toLowerCase();
    final userEmail = user.email.trim().toLowerCase();
    final userName = user.name.trim().toLowerCase();
    final userPrefix = userEmail.contains('@') ? userEmail.split('@').first.trim().toLowerCase() : userEmail;

    final rId = c.reporterId.trim().toLowerCase();
    final rName = c.reporterName.trim().toLowerCase();

    // 1. Direct ID match
    if (userId.isNotEmpty && (rId == userId || rId.contains(userId))) return true;

    // 2. Direct Email match
    if (userEmail.isNotEmpty && (rId == userEmail || rName == userEmail || rId.contains(userEmail) || rName.contains(userEmail))) return true;

    // 3. Email username prefix match
    if (userPrefix.length >= 3 && (rId.contains(userPrefix) || rName.contains(userPrefix))) return true;

    // 4. Name match
    if (userName.isNotEmpty && userName != 'citizen reporter' && (rName == userName || rName.contains(userName))) return true;

    return false;
  }

  void _confirmDeleteComplaint(BuildContext context, ComplaintProvider provider, Complaint complaint) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppTheme.emergencyRed, size: 24),
            SizedBox(width: 8),
            Text('Delete Complaint', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this complaint?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await provider.deleteComplaint(complaint.complaintId);
              if (context.mounted) {
                if (result.success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Complaint ${complaint.complaintId} deleted successfully!'),
                      backgroundColor: AppTheme.successGreen,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.errorMessage ?? 'Failed to delete complaint. Please try again.'),
                      backgroundColor: AppTheme.emergencyRed,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emergencyRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
