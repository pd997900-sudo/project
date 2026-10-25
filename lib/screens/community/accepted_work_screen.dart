import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/status_badge.dart';
import '../../providers/complaint_provider.dart';
import 'work_progress_screen.dart';

class AcceptedWorkScreen extends StatelessWidget {
  const AcceptedWorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final complaintProv = Provider.of<ComplaintProvider>(context);

    final acceptedList = complaintProv.complaints.where((c) {
      return c.status == 'Accepted' || c.status == 'Work Started' || c.status == 'Repair In Progress';
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accepted Works'),
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: acceptedList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.handshake_outlined, size: 60, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No active accepted works right now.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: acceptedList.length,
                        itemBuilder: (context, index) {
                          final c = acceptedList[index];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            child: GlassCard(
                              borderRadius: 20,
                              padding: const EdgeInsets.all(16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => WorkProgressScreen(complaint: c),
                                  ),
                                );
                              },
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
                                  const SizedBox(height: 8),
                                  Text(
                                    c.title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.address,
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      StatusBadge(status: c.status),
                                      Text(
                                        '${c.progressPercentage.toInt()}% Progress',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryBlue,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (c.updates.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Latest Update: ${c.updates.last.communityUserName}',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${c.updates.last.workPercentage.toInt()}%',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            c.updates.last.progressNote,
                                            style: const TextStyle(fontSize: 11, color: Colors.black87),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),

                                  if (c.status == 'Accepted') ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () async {
                                          final result = await complaintProv.startWork(c.complaintId);
                                          if (context.mounted) {
                                            if (result.success) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Work Started! Status = Work Started.'),
                                                  backgroundColor: AppTheme.successGreen,
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Failed to start work: ${result.errorMessage ?? 'Database save error'}'),
                                                  backgroundColor: AppTheme.emergencyRed,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryDark,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        icon: const Icon(Icons.play_arrow_rounded),
                                        label: const Text('Start Work', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ] else ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => WorkProgressScreen(complaint: c),
                                            ),
                                          );
                                        },
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: AppTheme.primaryBlue),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        icon: const Icon(Icons.edit_note, color: AppTheme.primaryBlue),
                                        label: const Text('Update Progress & Photos', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                                      ),
                                    ),
                                  ],
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
      ),
    );
  }
}
