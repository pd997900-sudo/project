import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_badge.dart';
import '../../models/complaint_model.dart';
import '../../models/india_districts.dart';
import '../../models/repair_team_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../community/complaint_verification_screen.dart';

class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({super.key});

  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen> {
  String? _stateFilter = 'All';
  String? _districtFilter = 'All';
  String _statusFilter = 'All';
  String _categoryFilter = 'All';
  String _severityFilter = 'All';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showChangeDistrictDialog(Complaint complaint) {
    String selectedState = complaint.stateDisplay;
    String selectedDistrict = complaint.districtDisplay;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final districts = IndiaDistricts.getDistricts(selectedState);
          if (!districts.contains(selectedDistrict)) {
            selectedDistrict = districts.first;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.edit_location_alt_rounded, color: AppTheme.primaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reassign District (${complaint.complaintId})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select the correct State and District for this road damage complaint:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedState,
                  decoration: const InputDecoration(labelText: 'State'),
                  items: IndiaDistricts.states
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        selectedState = val;
                        selectedDistrict = IndiaDistricts.getDistricts(val).first;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDistrict,
                  decoration: const InputDecoration(labelText: 'District'),
                  items: districts
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        selectedDistrict = val;
                      });
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
                  final success = await complaintProv.updateComplaintDistrict(
                    complaintId: complaint.complaintId,
                    state: selectedState,
                    district: selectedDistrict,
                  );
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? 'Complaint reassigned to $selectedDistrict, $selectedState!'
                            : 'Failed to update district.'),
                        backgroundColor: success ? AppTheme.successGreen : AppTheme.emergencyRed,
                      ),
                    );
                  }
                },
                child: const Text('Save Assignment'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAssignRepairTeamDialog(Complaint complaint) async {
    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final teams = await complaintProv.fetchRepairTeams(
      state: complaint.stateDisplay,
      district: complaint.districtDisplay,
    );

    if (!mounted) return;

    if (teams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No active repair teams found for ${complaint.districtDisplay}. Please create a repair team first.'),
          backgroundColor: AppTheme.warningOrange,
        ),
      );
      return;
    }

    RepairTeam selectedTeam = teams.first;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.handyman_rounded, color: AppTheme.primaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Assign Repair Team (${complaint.complaintId})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigning to active repair crew in ${complaint.districtDisplay}:',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<RepairTeam>(
                  value: selectedTeam,
                  decoration: const InputDecoration(labelText: 'Select Repair Team'),
                  isExpanded: true,
                  items: teams
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text('${t.name} (${t.specialization})', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() {
                        selectedTeam = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lead: ${selectedTeam.leadName.isNotEmpty ? selectedTeam.leadName : "N/A"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      if (selectedTeam.contactPhone.isNotEmpty)
                        Text('Phone: ${selectedTeam.contactPhone}', style: const TextStyle(fontSize: 12)),
                      if (selectedTeam.contactEmail.isNotEmpty)
                        Text('Email: ${selectedTeam.contactEmail}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final assignedBy = authProv.currentUser?.id ?? 'admin_1';
                  final success = await complaintProv.assignComplaintToRepairTeam(
                    complaintId: complaint.complaintId,
                    repairTeamId: selectedTeam.id,
                    repairTeamName: selectedTeam.name,
                    assignedByUserId: assignedBy,
                  );
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? 'Complaint assigned to ${selectedTeam.name}!'
                            : 'Failed to assign repair team.'),
                        backgroundColor: success ? AppTheme.successGreen : AppTheme.emergencyRed,
                      ),
                    );
                  }
                },
                child: const Text('Confirm Assignment'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThumbnail(String? rawUrl) {
    final url = (rawUrl != null && rawUrl.trim().isNotEmpty) ? rawUrl.trim() : '';
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        return Image.memory(
          base64Decode(base64Str),
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
        );
      } catch (_) {
        return _buildFallbackThumbnail();
      }
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        width: 70,
        height: 70,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
      );
    }
    return _buildFallbackThumbnail();
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: 70,
      height: 70,
      color: Colors.blue.shade100,
      child: const Icon(Icons.add_road_rounded, color: Colors.blue),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);

    // Apply local filters
    var list = complaintProv.complaints;
    if (_stateFilter != null && _stateFilter != 'All') {
      list = list.where((c) => c.stateDisplay.toLowerCase() == _stateFilter!.toLowerCase()).toList();
    }
    if (_districtFilter != null && _districtFilter != 'All') {
      list = list.where((c) => c.districtDisplay.toLowerCase() == _districtFilter!.toLowerCase()).toList();
    }
    if (_statusFilter != 'All') {
      final sf = _statusFilter.toLowerCase();
      if (sf == 'pending') {
        list = list.where((c) => c.status.toLowerCase() == 'submitted' || c.status.toLowerCase() == 'under verification').toList();
      } else if (sf == 'verified') {
        list = list.where((c) => c.status.toLowerCase() == 'verified').toList();
      } else if (sf == 'accepted / assigned') {
        list = list.where((c) => c.status.toLowerCase() == 'accepted' || c.status.toLowerCase() == 'work started' || c.status.toLowerCase() == 'repair in progress').toList();
      } else if (sf == 'completed') {
        list = list.where((c) => c.isCompleted || c.status.toLowerCase() == 'completed').toList();
      }
    }
    if (_categoryFilter != 'All') {
      list = list.where((c) => c.category.toLowerCase() == _categoryFilter.toLowerCase()).toList();
    }
    if (_severityFilter != 'All') {
      list = list.where((c) => c.severity.toLowerCase() == _severityFilter.toLowerCase()).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((c) =>
          c.complaintId.toLowerCase().contains(q) ||
          c.title.toLowerCase().contains(q) ||
          c.address.toLowerCase().contains(q) ||
          c.districtDisplay.toLowerCase().contains(q) ||
          c.reporterName.toLowerCase().contains(q)).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('All-India Complaints Registry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => complaintProv.refreshComplaints(),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: Column(
          children: [
            // Search Bar & Filter Options
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by ID, location, district, reporter...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                  const SizedBox(height: 8),
                  // Dropdown Filter Row
                  Row(
                    children: [
                      // State Filter
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _stateFilter ?? 'All',
                          decoration: const InputDecoration(
                            labelText: 'State',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All States')),
                            ...IndiaDistricts.states.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _stateFilter = val;
                              _districtFilter = 'All';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // District Filter
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _districtFilter ?? 'All',
                          decoration: const InputDecoration(
                            labelText: 'District',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All Districts')),
                            ...IndiaDistricts.getDistricts(_stateFilter == 'All' ? null : _stateFilter)
                                .map((d) => DropdownMenuItem(value: d, child: Text(d))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _districtFilter = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status Filter
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All Status')),
                            DropdownMenuItem(value: 'pending', child: Text('Pending')),
                            DropdownMenuItem(value: 'verified', child: Text('Verified')),
                            DropdownMenuItem(value: 'accepted / assigned', child: Text('Assigned')),
                            DropdownMenuItem(value: 'completed', child: Text('Completed')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _statusFilter = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Results Summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Text(
                'Showing ${list.length} complaint${list.length == 1 ? "" : "s"}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
              ),
            ),

            // Complaints List
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          const Text('No complaints match the selected filter criteria.', style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final c = list[index];
                        final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(c.createdAt);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: _buildThumbnail(c.imageUrl),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(c.complaintId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark)),
                                              StatusBadge(status: c.status),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            c.title,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            c.address,
                                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(height: 1),
                                const SizedBox(height: 8),

                                // Location & Assignment Badges Row
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    // District Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.blue.shade200, width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.location_on_rounded, size: 13, color: Colors.blue),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${c.districtDisplay}, ${c.stateDisplay}',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Repair Team Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: c.isAssignedToRepairTeam ? Colors.green.shade50 : Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: c.isAssignedToRepairTeam ? Colors.green.shade200 : Colors.orange.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.handyman_rounded,
                                            size: 13,
                                            color: c.isAssignedToRepairTeam ? Colors.green.shade700 : Colors.orange.shade800,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            c.isAssignedToRepairTeam ? (c.repairTeamName ?? "Team Assigned") : "No Repair Team",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: c.isAssignedToRepairTeam ? Colors.green.shade900 : Colors.orange.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Severity Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Complaint.getSeverityColor(c.severity).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        c.severity,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Complaint.getSeverityColor(c.severity),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Footer with reporter name & date
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Reported by: ${c.reporterName}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                    Text(formattedDate, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Administrative Actions
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          textStyle: const TextStyle(fontSize: 12),
                                        ),
                                        icon: const Icon(Icons.edit_location_alt_outlined, size: 14),
                                        label: const Text('District'),
                                        onPressed: () => _showChangeDistrictDialog(c),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          textStyle: const TextStyle(fontSize: 12),
                                        ),
                                        icon: const Icon(Icons.handyman_outlined, size: 14),
                                        label: const Text('Assign Team'),
                                        onPressed: () => _showAssignRepairTeamDialog(c),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          backgroundColor: AppTheme.primaryDark,
                                          textStyle: const TextStyle(fontSize: 12),
                                        ),
                                        icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                                        label: const Text('Details'),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ComplaintVerificationScreen(complaint: c),
                                            ),
                                          );
                                        },
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
          ],
        ),
      ),
    );
  }
}

