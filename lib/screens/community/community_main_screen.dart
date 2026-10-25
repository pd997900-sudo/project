import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/complaint_provider.dart';
import 'community_dashboard.dart';
import 'complaint_list_screen.dart';
import 'completed_works_screen.dart';
import 'community_profile_screen.dart';

class CommunityMainScreen extends StatefulWidget {
  const CommunityMainScreen({super.key});

  @override
  State<CommunityMainScreen> createState() => _CommunityMainScreenState();
}

class _CommunityMainScreenState extends State<CommunityMainScreen> {
  int _currentIndex = 0;

  void _goHome() {
    setState(() {
      _currentIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      CommunityDashboard(
        isActiveTab: _currentIndex == 0,
        onNavigateTab: (idx) {
          setState(() {
            _currentIndex = idx;
          });
        },
      ),
      ComplaintListScreen(onBack: _goHome),
      CompletedWorksScreen(onBack: _goHome),
      CommunityProfileScreen(onBack: _goHome),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goHome();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withOpacity(0.1),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              context.read<ComplaintProvider>().refreshComplaints();
              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppTheme.primaryDark,
            unselectedItemColor: Colors.grey,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.format_list_bulleted_rounded),
                activeIcon: Icon(Icons.format_list_bulleted_add),
                label: 'Complaints',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.task_alt_rounded),
                activeIcon: Icon(Icons.check_circle_rounded),
                label: 'Completed',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline_rounded),
                activeIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
