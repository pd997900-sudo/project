import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/complaint_provider.dart';
import 'reporter_dashboard.dart';
import 'report_issue_screen.dart';
import 'complaint_history_screen.dart';
import 'notifications_screen.dart';
import 'reporter_profile_screen.dart';

class ReporterMainScreen extends StatefulWidget {
  const ReporterMainScreen({super.key});

  @override
  State<ReporterMainScreen> createState() => _ReporterMainScreenState();
}

class _NavHistoryEntry {
  final int tabIndex;
  final String historyTab;

  const _NavHistoryEntry({required this.tabIndex, this.historyTab = 'All'});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _NavHistoryEntry &&
          runtimeType == other.runtimeType &&
          tabIndex == other.tabIndex &&
          historyTab == other.historyTab;

  @override
  int get hashCode => tabIndex.hashCode ^ historyTab.hashCode;
}



class _ReporterMainScreenState extends State<ReporterMainScreen> {
  final List<_NavHistoryEntry> _historyStack = [
    const _NavHistoryEntry(tabIndex: 0, historyTab: 'All'),
  ];

  _NavHistoryEntry get _currentEntry => _historyStack.isNotEmpty
      ? _historyStack.last
      : const _NavHistoryEntry(tabIndex: 0, historyTab: 'All');

  void _pushNav(int index, {String? initialTab}) {
    final targetTab = initialTab ?? (index == 2 ? _currentEntry.historyTab : 'All');
    final nextEntry = _NavHistoryEntry(tabIndex: index, historyTab: targetTab);

    if (_currentEntry != nextEntry) {
      setState(() {
        _historyStack.add(nextEntry);
      });
    }
  }

  void _handleBack() {
    if (_historyStack.length > 1) {
      setState(() {
        _historyStack.removeLast();
      });
    } else if (_currentEntry.tabIndex != 0) {
      setState(() {
        _historyStack.clear();
        _historyStack.add(const _NavHistoryEntry(tabIndex: 0, historyTab: 'All'));
      });
    }
  }

  void _onBottomNavTapped(int index) {
    context.read<ComplaintProvider>().refreshComplaints();
    if (index == 0) {
      setState(() {
        _historyStack.clear();
        _historyStack.add(const _NavHistoryEntry(tabIndex: 0, historyTab: 'All'));
      });
    } else {
      _pushNav(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _currentEntry.tabIndex;
    final currentHistoryTab = _currentEntry.historyTab;

    final screens = [
      ReporterDashboard(
        isActiveTab: currentTab == 0,
        onNavigateTab: (idx, {initialTab}) {
          _pushNav(idx, initialTab: initialTab);
        },
      ),
      ReportIssueScreen(onBack: () => _onBottomNavTapped(0)),
      ComplaintHistoryScreen(
        key: ValueKey(currentHistoryTab),
        initialTab: currentHistoryTab,
        onBack: _handleBack,
        onTabChanged: (newTab) {
          _pushNav(2, initialTab: newTab);
        },
      ),
      NotificationsScreen(
        isActiveTab: currentTab == 3,
        onBack: _handleBack,
      ),
      ReporterProfileScreen(onBack: _handleBack),
    ];

    return PopScope(
      canPop: _historyStack.length <= 1 && currentTab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: currentTab,
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
              currentIndex: currentTab,
              onTap: _onBottomNavTapped,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: AppTheme.primaryDark,
              unselectedItemColor: Colors.grey,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.add_circle_outline_rounded),
                  activeIcon: Icon(Icons.add_circle_rounded),
                  label: 'Report',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.track_changes_outlined),
                  activeIcon: Icon(Icons.track_changes_rounded),
                  label: 'Tracking',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.notifications_outlined),
                  activeIcon: Icon(Icons.notifications_rounded),
                  label: 'Alerts',
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
