import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/india_districts.dart';
import '../../models/repair_team_model.dart';
import '../../providers/complaint_provider.dart';

class AdminRepairTeamsScreen extends StatefulWidget {
  const AdminRepairTeamsScreen({super.key});

  @override
  State<AdminRepairTeamsScreen> createState() => _AdminRepairTeamsScreenState();
}

class _AdminRepairTeamsScreenState extends State<AdminRepairTeamsScreen> {
  List<RepairTeam> _teams = [];
  bool _isLoading = true;
  String? _selectedState = 'All';
  String? _selectedDistrict = 'All';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);
    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
    final list = await complaintProv.fetchRepairTeams(
      state: _selectedState == 'All' ? null : _selectedState,
      district: _selectedDistrict == 'All' ? null : _selectedDistrict,
    );

    if (mounted) {
      setState(() {
        _teams = list;
        _isLoading = false;
      });
    }
  }

  void _showAddOrEditTeamDialog([RepairTeam? existing]) {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final leadCtrl = TextEditingController(text: existing?.leadName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.contactPhone ?? '');
    final emailCtrl = TextEditingController(text: existing?.contactEmail ?? '');
    String state = existing?.state ?? (_selectedState != 'All' ? _selectedState! : 'Tamil Nadu');
    String district = existing?.district ?? (_selectedDistrict != 'All' ? _selectedDistrict! : 'Kanchipuram');
    String specialization = existing?.specialization ?? 'Pothole Patching & Asphalt Repair';

    final specializations = [
      'Pothole Patching & Asphalt Repair',
      'Heavy Road & Highway Repairs',
      'Drainage, Potholes & Shoulder Works',
      'Urban Pothole & Surface Leveling',
      'Monsoon Pothole Repair & Cold Mix',
      'Emergency Hazard Rapid Response',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final districts = IndiaDistricts.getDistricts(state);
          if (!districts.contains(district)) {
            district = districts.first;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.handyman_rounded, color: AppTheme.primaryDark),
                const SizedBox(width: 8),
                Text(isEditing ? 'Edit Repair Team' : 'Add Local Repair Team', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Team Name *', hintText: 'e.g. Kanchipuram Road Squad'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: state,
                    decoration: const InputDecoration(labelText: 'State *'),
                    items: IndiaDistricts.states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          state = val;
                          district = IndiaDistricts.getDistricts(val).first;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: district,
                    decoration: const InputDecoration(labelText: 'District *'),
                    items: districts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => district = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: specializations.contains(specialization) ? specialization : specializations.first,
                    decoration: const InputDecoration(labelText: 'Specialization'),
                    isExpanded: true,
                    items: specializations.map((sp) => DropdownMenuItem(value: sp, child: Text(sp, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => specialization = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: leadCtrl,
                    decoration: const InputDecoration(labelText: 'Team Lead Name', hintText: 'e.g. R. Murugan'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Contact Phone', hintText: '+91 98401 23456'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Contact Email', hintText: 'team@roadwatch.org'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a team name.')),
                    );
                    return;
                  }

                  final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
                  final team = RepairTeam(
                    id: existing?.id ?? 'team_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    state: state,
                    district: district,
                    specialization: specialization,
                    leadName: leadCtrl.text.trim(),
                    contactPhone: phoneCtrl.text.trim(),
                    contactEmail: emailCtrl.text.trim(),
                    isActive: existing?.isActive ?? true,
                  );

                  bool ok;
                  if (isEditing) {
                    ok = await complaintProv.updateRepairTeam(team);
                  } else {
                    ok = await complaintProv.createRepairTeam(team);
                  }

                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  await _loadTeams();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? (isEditing ? 'Repair team updated!' : 'Repair team registered successfully!')
                            : 'Team saved locally.'),
                        backgroundColor: AppTheme.successGreen,
                      ),
                    );
                  }
                },
                child: Text(isEditing ? 'Save Changes' : 'Register Team'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _toggleTeamActive(RepairTeam team, bool newStatus) async {
    final complaintProv = Provider.of<ComplaintProvider>(context, listen: false);
    final updated = team.copyWith(isActive: newStatus);
    await complaintProv.updateRepairTeam(updated);
    await _loadTeams();
  }

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);

    var filtered = _teams.where((t) {
      if (_selectedState != 'All' && _selectedState != null) {
        if (t.state.toLowerCase() != _selectedState!.toLowerCase()) return false;
      }
      if (_selectedDistrict != 'All' && _selectedDistrict != null) {
        if (t.district.toLowerCase() != _selectedDistrict!.toLowerCase()) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!t.name.toLowerCase().contains(q) &&
            !t.district.toLowerCase().contains(q) &&
            !t.leadName.toLowerCase().contains(q) &&
            !t.specialization.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('District Repair Teams'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTeams,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryDark,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Repair Team', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showAddOrEditTeamDialog(),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: Column(
          children: [
            // Filter and Search Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search repair squads by name, district, specialization...',
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
                  Row(
                    children: [
                      // State Filter
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedState ?? 'All',
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
                              _selectedState = val;
                              _selectedDistrict = 'All';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // District Filter
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedDistrict ?? 'All',
                          decoration: const InputDecoration(
                            labelText: 'District',
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All Districts')),
                            ...IndiaDistricts.getDistricts(_selectedState == 'All' ? null : _selectedState)
                                .map((d) => DropdownMenuItem(value: d, child: Text(d))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedDistrict = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filtered.length} Repair Crew${filtered.length == 1 ? "" : "s"} listed',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                  ),
                  Text(
                    'Active: ${filtered.where((t) => t.isActive).length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                  ),
                ],
              ),
            ),

            // Teams List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.handyman_outlined, size: 60, color: Colors.grey.shade400),
                              const SizedBox(height: 10),
                              const Text('No repair teams found for the selected filter.', style: TextStyle(color: Colors.black54)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final team = filtered[index];

                            // Count actual complaints assigned to this team
                            final assignedComplaints = complaintProv.complaintsForRepairTeam(team.id);
                            final completedComplaints = assignedComplaints.where((c) => c.isCompleted).length;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: team.isActive ? Colors.blue.shade100 : Colors.grey.shade200,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.handyman_rounded,
                                            color: team.isActive ? AppTheme.primaryDark : Colors.grey,
                                            size: 24,
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
                                                  Expanded(
                                                    child: Text(
                                                      team.name,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: team.isActive ? Colors.green.shade50 : Colors.red.shade50,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: team.isActive ? Colors.green.shade300 : Colors.red.shade300,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      team.isActive ? 'Active' : 'Inactive',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: team.isActive ? Colors.green.shade800 : Colors.red.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                team.specialization,
                                                style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),

                                    // Location and Lead Details
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.location_on_rounded, size: 12, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${team.district}, ${team.state}',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (team.leadName.isNotEmpty)
                                          Text('Lead: ${team.leadName}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      ],
                                    ),

                                    if (team.contactPhone.isNotEmpty || team.contactEmail.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          if (team.contactPhone.isNotEmpty)
                                            Text('📞 ${team.contactPhone}   ', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                          if (team.contactEmail.isNotEmpty)
                                            Text('✉️ ${team.contactEmail}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 10),

                                    // Assigned Complaints Stats & Actions Row
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Assigned Tasks: ${assignedComplaints.length} (Resolved: $completedComplaints)',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                                        ),
                                        Row(
                                          children: [
                                            Switch(
                                              value: team.isActive,
                                              activeColor: AppTheme.successGreen,
                                              onChanged: (val) => _toggleTeamActive(team, val),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryBlue),
                                              tooltip: 'Edit Team',
                                              onPressed: () => _showAddOrEditTeamDialog(team),
                                            ),
                                          ],
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

