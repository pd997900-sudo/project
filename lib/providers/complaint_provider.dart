import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/complaint_model.dart';
import '../models/india_districts.dart';
import '../models/repair_team_model.dart';
import '../services/supabase_service.dart';
import '../services/location_service.dart';

class WorkProgressResult {
  final bool success;
  final String? errorMessage;
  final String? uploadedImageUrl;

  WorkProgressResult({
    required this.success,
    this.errorMessage,
    this.uploadedImageUrl,
  });
}

class ComplaintProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _complaintsStorageKey = 'roadwatch_complaints_db_v1';
  static const String _userVotesStorageKey = 'roadwatch_user_community_votes_v2';
  static const String _deviceVoterIdKey = 'roadwatch_device_voter_id_v1';

  List<Complaint> _complaints = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasPendingRefresh = false;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  String? _selectedStateFilter;
  String? _selectedDistrictFilter;
  String _selectedCategoryFilter = 'All';
  String _selectedSeverityFilter = 'All';
  String? _deviceVoterId;
  RealtimeChannel? _realtimeChannel;

  Future<void>? _activeLoadFuture;

  String? get deviceVoterId => _deviceVoterId;

  ComplaintProvider() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    _initComplaints();
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() {
    try {
      _realtimeChannel = SupabaseService.subscribeToDataChanges(
        onDataChanged: (table, eventType) {
          debugPrint('🔄 [Realtime] DB change on "$table" ($eventType). Triggering refresh...');
          refreshComplaints();
        },
      );
    } catch (e) {
      debugPrint('Notice setting up realtime channel subscription: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 [AppLifecycle] App resumed to foreground: refreshing complaints from Supabase...');
      refreshComplaints();
    }
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    try {
      _realtimeChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _initComplaints() async {
    await refreshComplaints();
  }

  Future<void> _loadComplaintsFromStorage() async {
    _isRefreshing = true;
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Ensure persistent device voter ID exists
      _deviceVoterId = prefs.getString(_deviceVoterIdKey);
      if (_deviceVoterId == null || _deviceVoterId!.isEmpty) {
        _deviceVoterId = 'voter_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
        await prefs.setString(_deviceVoterIdKey, _deviceVoterId!);
      }

      // Load persistent local votes map (complaintId -> { voterKey -> voteValue })
      final Map<String, Map<String, String>> localUserVotes = {};
      final storedVotesJson = prefs.getString(_userVotesStorageKey);
      if (storedVotesJson != null && storedVotesJson.isNotEmpty) {
        try {
          final Map<String, dynamic> decodedVotes = jsonDecode(storedVotesJson);
          decodedVotes.forEach((cid, votesMap) {
            if (votesMap is Map) {
              localUserVotes[cid.trim().toLowerCase()] = Map<String, String>.from(
                votesMap.map((k, v) => MapEntry(k.toString().trim().toLowerCase(), v.toString().trim())),
              );
            }
          });
        } catch (e) {
          debugPrint('Error parsing persistent local user votes: $e');
        }
      }

      final Map<String, Complaint> map = {};

      // 1. Load stored user-submitted & updated complaints from SharedPreferences
      final storedJson = prefs.getString(_complaintsStorageKey);
      if (storedJson != null && storedJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(storedJson);
          final storedComplaints = decoded.map((item) => Complaint.fromJson(item)).toList();
          for (var sc in storedComplaints) {
            if (sc.complaintId.isNotEmpty) {
              map[sc.complaintId.trim().toLowerCase()] = sc;
            }
          }
        } catch (e) {
          debugPrint('Error parsing stored complaints: $e');
        }
      }

      // 2. Load from Supabase PostgreSQL 'reports', 'complaint_votes', & 'progress_updates' tables if connected
      List<Map<String, dynamic>> remoteVotes = [];
      if (SupabaseService.isConnected) {
        try {
          remoteVotes = await SupabaseService.getCommunityVotes();
        } catch (e) {
          debugPrint('Notice fetching remote votes: $e');
        }
      }

      final Map<String, List<Map<String, dynamic>>> votesByComplaint = {};
      for (var v in remoteVotes) {
        final cid = v['complaint_id']?.toString().trim().toLowerCase() ?? '';
        if (cid.isNotEmpty) {
          votesByComplaint.putIfAbsent(cid, () => []).add(v);
        }
      }

      final Map<String, List<ProgressUpdate>> updatesByComplaint = {};
      final Map<String, FeedbackModel> feedbackByComplaint = {};
      final Map<String, List<FeedbackModel>> feedbacksByComplaint = {};

      if (SupabaseService.isConnected) {
        final remoteReports = await SupabaseService.getReports();
        final remoteUpdatesMap = await SupabaseService.getAllProgressUpdates();
        List<Map<String, dynamic>> remoteFeedbacks = [];
        try {
          remoteFeedbacks = await SupabaseService.getAllComplaintFeedbacks();
        } catch (e) {
          debugPrint('Notice fetching remote feedbacks: $e');
        }

        for (var fb in remoteFeedbacks) {
          final cid = fb['complaint_id']?.toString().trim().toLowerCase() ?? '';
          if (cid.isNotEmpty) {
            try {
              final parsed = FeedbackModel.fromJson(fb);
              // remoteFeedbacks is ordered by updated_at DESC, so the first one seen is the latest
              if (!feedbackByComplaint.containsKey(cid)) {
                feedbackByComplaint[cid] = parsed;
              }
              feedbacksByComplaint.putIfAbsent(cid, () => []);
              final list = feedbacksByComplaint[cid]!;
              final existingIdx = list.indexWhere((existing) =>
                existing.reporterId.isNotEmpty &&
                existing.reporterId.toLowerCase() == parsed.reporterId.toLowerCase()
              );
              if (existingIdx == -1) {
                list.add(parsed);
              }
            } catch (e) {
              debugPrint('Notice parsing remote feedback: $e');
            }
          }
        }

        for (var u in remoteUpdatesMap) {
          final cid = u['complaint_id']?.toString().trim().toLowerCase() ?? '';
          if (cid.isNotEmpty) {
            final rawId = u['id']?.toString().trim();
            final rawUpdateId = u['update_id']?.toString().trim();
            final pu = ProgressUpdate(
              id: (rawId != null && rawId.isNotEmpty && Complaint.isUuid(rawId)) ? rawId : null,
              updateId: (rawUpdateId != null && rawUpdateId.isNotEmpty)
                  ? rawUpdateId
                  : (rawId ?? 'UPD-${DateTime.now().millisecondsSinceEpoch}'),
              complaintId: u['complaint_id']?.toString() ?? '',
              communityUserId: u['community_user_id']?.toString() ?? '',
              communityUserName: u['community_user_name']?.toString() ?? 'Community Crew',
              progressNote: u['progress_note']?.toString() ?? u['notes']?.toString() ?? '',
              imageUrl: u['image_url']?.toString(),
              workPercentage: Complaint.parseDouble(u['work_percentage'] ?? u['percentage'], 0.0),
              status: u['status']?.toString() ?? 'In Progress',
              createdAt: u['created_at'] != null ? Complaint.parseTimestamptz(u['created_at']) ?? DateTime.now() : DateTime.now(),
              latitude: Complaint.parseNullableDouble(u['latitude']),
              longitude: Complaint.parseNullableDouble(u['longitude']),
              address: u['address']?.toString(),
              capturedAt: u['captured_at'] != null ? Complaint.parseTimestamptz(u['captured_at']) : null,
            );
            updatesByComplaint.putIfAbsent(cid, () => []).add(pu);
          }
        }

        for (var reportMap in remoteReports) {
          final c = Complaint.fromJson(reportMap);
          if (c.complaintId.isNotEmpty) {
            var complaintObj = c;
            final lowerId = c.complaintId.trim().toLowerCase();
            final reportIdStr = reportMap['id']?.toString().trim().toLowerCase();
            final complaintIdStr = reportMap['complaint_id']?.toString().trim().toLowerCase();

            // Merge dedicated progress_updates table rows if present matching any ID variant
            final matchingUpdates = <ProgressUpdate>[];
            final keysToCheck = <String>{
              lowerId,
              if (reportIdStr != null && reportIdStr.isNotEmpty) reportIdStr,
              if (complaintIdStr != null && complaintIdStr.isNotEmpty) complaintIdStr,
            };
            for (var k in keysToCheck) {
              if (updatesByComplaint.containsKey(k)) {
                matchingUpdates.addAll(updatesByComplaint[k]!);
              }
            }

            if (matchingUpdates.isNotEmpty) {
              final merged = Complaint.deduplicateUpdates([...complaintObj.updates, ...matchingUpdates]);
              merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final latestUpdate = merged.last;
              final isAlreadyCompleted = complaintObj.isCompleted ||
                  complaintObj.status.trim().toLowerCase() == 'completed' ||
                  complaintObj.status.trim().toLowerCase() == 'repaired';
              complaintObj = complaintObj.copyWith(
                updates: merged,
                progressPercentage: isAlreadyCompleted ? 100.0 : latestUpdate.workPercentage,
                status: isAlreadyCompleted
                    ? 'Completed'
                    : latestUpdate.workPercentage >= 100.0
                        ? 'Completed'
                        : latestUpdate.workPercentage >= 85.0
                            ? 'Near Completion'
                            : 'Repair In Progress',
              );
            }

            // Find matching feedback from dedicated complaint_feedback table
            FeedbackModel? remoteFb;
            final allFbList = <FeedbackModel>[];
            for (var k in keysToCheck) {
              if (feedbackByComplaint.containsKey(k) && remoteFb == null) {
                remoteFb = feedbackByComplaint[k];
              }
              if (feedbacksByComplaint.containsKey(k)) {
                for (var fbItem in feedbacksByComplaint[k]!) {
                  if (!allFbList.any((existing) => existing.reporterId == fbItem.reporterId)) {
                    allFbList.add(fbItem);
                  }
                }
              }
            }

            // Preserve local complaint updates if existing
            if (map.containsKey(lowerId)) {
              final existing = map[lowerId]!;
              final mergedUpdates = Complaint.deduplicateUpdates([...complaintObj.updates, ...existing.updates]);
              mergedUpdates.sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final mergedFeedbacks = <FeedbackModel>[...allFbList];
              for (var ef in existing.allFeedbacks) {
                if (!mergedFeedbacks.any((f) => f.reporterId == ef.reporterId)) {
                  mergedFeedbacks.add(ef);
                }
              }
              map[lowerId] = complaintObj.copyWith(
                updates: mergedUpdates,
                feedback: remoteFb ?? complaintObj.feedback ?? existing.feedback,
                allFeedbacks: mergedFeedbacks.isNotEmpty ? mergedFeedbacks : (remoteFb != null ? [remoteFb] : complaintObj.allFeedbacks),
              );
            } else {
              map[lowerId] = complaintObj.copyWith(
                feedback: remoteFb ?? complaintObj.feedback,
                allFeedbacks: allFbList.isNotEmpty ? allFbList : (remoteFb != null ? [remoteFb] : complaintObj.allFeedbacks),
              );
            }
          }
        }
      }

      // Requirement 6: Do not use hardcoded or demo complaints; fetch only real Supabase reports.
      // Purge any lingering hardcoded mock complaints (RW-8901, RW-8902, etc.)
      for (var mc in SupabaseService.mockComplaints) {
        map.remove(mc.complaintId.trim().toLowerCase());
      }

      // 4. Attach and merge all persisted progress_updates for EVERY complaint in map (including mock complaints)
      if (SupabaseService.isConnected && updatesByComplaint.isNotEmpty) {
        map.forEach((cidKey, complaintObj) {
          final lowerId = complaintObj.complaintId.trim().toLowerCase();
          final matchingUpdates = <ProgressUpdate>[];
          final keysToCheck = <String>{
            lowerId,
            complaintObj.complaintId.trim(),
            cidKey.trim().toLowerCase(),
          };
          for (var k in keysToCheck) {
            final normK = k.toLowerCase();
            if (updatesByComplaint.containsKey(normK)) {
              matchingUpdates.addAll(updatesByComplaint[normK]!);
            }
          }
          if (matchingUpdates.isNotEmpty) {
            final merged = Complaint.deduplicateUpdates([...complaintObj.updates, ...matchingUpdates]);
            merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            final latestUpdate = merged.last;
            final isAlreadyCompleted = complaintObj.isCompleted ||
                complaintObj.status.trim().toLowerCase() == 'completed' ||
                complaintObj.status.trim().toLowerCase() == 'repaired';
            map[cidKey] = complaintObj.copyWith(
              updates: merged,
              progressPercentage: isAlreadyCompleted ? 100.0 : latestUpdate.workPercentage,
              status: isAlreadyCompleted
                  ? 'Completed'
                  : latestUpdate.workPercentage >= 100.0
                      ? 'Completed'
                      : latestUpdate.workPercentage >= 85.0
                          ? 'Near Completion'
                          : 'Repair In Progress',
              communityUserName: latestUpdate.communityUserName.isNotEmpty
                  ? latestUpdate.communityUserName
                  : complaintObj.communityUserName,
              acceptedByCommunityUser: latestUpdate.communityUserId.isNotEmpty
                  ? latestUpdate.communityUserId
                  : complaintObj.acceptedByCommunityUser,
              afterImageUrl: (isAlreadyCompleted || latestUpdate.workPercentage >= 95.0)
                  ? (latestUpdate.imageUrl ?? complaintObj.afterImageUrl)
                  : complaintObj.afterImageUrl,
              completionNotes: (isAlreadyCompleted || latestUpdate.workPercentage >= 95.0)
                  ? (latestUpdate.progressNote.isNotEmpty ? latestUpdate.progressNote : complaintObj.completionNotes)
                  : complaintObj.completionNotes,
            );
          }
        });
      }

      // 4b. Attach remote feedbacks to mock or remaining complaints
      if (feedbackByComplaint.isNotEmpty || feedbacksByComplaint.isNotEmpty) {
        map.forEach((cidKey, complaintObj) {
          final lowerId = complaintObj.complaintId.trim().toLowerCase();
          final matchingFb = feedbackByComplaint[lowerId] ??
              feedbackByComplaint[complaintObj.complaintId.trim().toLowerCase()] ??
              feedbackByComplaint[cidKey.trim().toLowerCase()];
          final matchingAll = feedbacksByComplaint[lowerId] ??
              feedbacksByComplaint[complaintObj.complaintId.trim().toLowerCase()] ??
              feedbacksByComplaint[cidKey.trim().toLowerCase()] ??
              [];
          if (matchingFb != null || matchingAll.isNotEmpty) {
            final merged = <FeedbackModel>[...matchingAll];
            for (var ef in complaintObj.allFeedbacks) {
              if (!merged.any((f) => f.reporterId.isNotEmpty && f.reporterId.toLowerCase() == ef.reporterId.toLowerCase())) {
                merged.add(ef);
              }
            }
            map[cidKey] = complaintObj.copyWith(
              feedback: matchingFb ?? complaintObj.feedback,
              allFeedbacks: merged.isNotEmpty ? merged : (matchingFb != null ? [matchingFb] : complaintObj.allFeedbacks),
            );
          }
        });
      }

      // 4. Calculate exact real and fake votes for every complaint in map directly from Supabase votes or local storage per exact complaint ID
      map.forEach((cidKey, complaintObj) {
        final lowerId = complaintObj.complaintId.trim().toLowerCase();

        int realC = 0;
        int fakeC = 0;
        final List<String> votedIds = [];
        final Map<String, String> uVotes = {};

        if (SupabaseService.isConnected) {
          // Find matching votes in votesByComplaint by exact complaintId or key
          final matchingVoteRows = <Map<String, dynamic>>[];
          if (votesByComplaint.containsKey(lowerId)) {
            matchingVoteRows.addAll(votesByComplaint[lowerId]!);
          }
          if (votesByComplaint.containsKey(cidKey) && cidKey != lowerId) {
            matchingVoteRows.addAll(votesByComplaint[cidKey]!);
          }

          final Map<String, String> userVoteMap = {};
          for (var v in matchingVoteRows) {
            final uId = v['user_id']?.toString().trim() ?? '';
            final vVal = v['vote']?.toString() ?? 'genuine';
            if (uId.isNotEmpty) {
              final isReal = vVal == 'Genuine Issue' || vVal == 'real' || vVal == 'genuine';
              userVoteMap[uId] = isReal ? 'Genuine Issue' : 'Fake Issue';
            }
          }

          userVoteMap.forEach((uId, vVal) {
            final isReal = vVal == 'Genuine Issue';
            if (isReal) {
              realC++;
            } else {
              fakeC++;
            }
            votedIds.add(uId);
            uVotes[uId] = vVal;
          });
        } else {
          // Offline fallback: load votes strictly from localUserVotes matching exact complaint ID
          if (localUserVotes.containsKey(lowerId)) {
            final votesMap = localUserVotes[lowerId]!;
            votesMap.forEach((voterKey, voteVal) {
              final cleanVoter = voterKey.trim();
              if (cleanVoter.isEmpty || cleanVoter == 'device_voter' || cleanVoter == 'session_voter' || cleanVoter == 'device_has_voted') return;
              final isReal = voteVal == 'Genuine Issue' || voteVal == 'real' || voteVal == 'genuine';
              if (isReal) {
                realC++;
              } else {
                fakeC++;
              }
              if (!votedIds.contains(cleanVoter)) votedIds.add(cleanVoter);
              uVotes[cleanVoter] = voteVal;
            });
          } else if (complaintObj.userVotes.isNotEmpty) {
            realC = complaintObj.realVotes;
            fakeC = complaintObj.fakeVotes;
            votedIds.addAll(complaintObj.votedUserIds);
            uVotes.addAll(complaintObj.userVotes);
          }
        }

        map[cidKey] = complaintObj.copyWith(
          realVotes: realC,
          fakeVotes: fakeC,
          votedUserIds: votedIds,
          userVotes: uVotes,
        );
      });

      _complaints = map.values.toList();
      _complaints.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Persist the freshest Supabase reports to local storage so mobile cache is identical
      await _saveComplaintsToStorage();
    } catch (e) {
      debugPrint('Error loading complaints: $e');
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Manually refresh complaints from Supabase with awaitable synchronization
  Future<void> refreshComplaints() async {
    if (_activeLoadFuture != null) {
      await _activeLoadFuture;
      return;
    }

    final load = _loadComplaintsFromStorage();
    _activeLoadFuture = load;
    try {
      await load;
    } finally {
      if (_activeLoadFuture == load) {
        _activeLoadFuture = null;
      }
    }
  }

  Future<void> _saveComplaintsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Optimize base64 photos to stay within browser localStorage 5MB quota limit
      final jsonList = _complaints.map((c) {
        final jsonMap = c.toJson();

        String optimizeImg(dynamic val) {
          if (val is String && val.trim().isNotEmpty) {
            final str = val.trim();
            // Only replace raw base64 data URLs that exceed localStorage quota.
            // Never replace real HTTP/HTTPS URLs (including Supabase Storage public URLs).
            if (str.startsWith('data:') || (!str.startsWith('http') && str.length > 1000)) {
              return 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=800&auto=format&fit=crop';
            }
            return str;
          }
          return val?.toString() ?? '';
        }

        jsonMap['image_url'] = optimizeImg(jsonMap['image_url']);
        jsonMap['before_image_url'] = optimizeImg(jsonMap['before_image_url']);
        jsonMap['after_image_url'] = optimizeImg(jsonMap['after_image_url']);

        if (jsonMap['updates'] is List) {
          jsonMap['updates'] = (jsonMap['updates'] as List).map((u) {
            if (u is Map) {
              final copyU = Map<String, dynamic>.from(u);
              copyU['image_url'] = optimizeImg(copyU['image_url']);
              return copyU;
            }
            return u;
          }).toList();
        }

        return jsonMap;
      }).toList();

      final jsonStr = jsonEncode(jsonList);
      final saved = await prefs.setString(_complaintsStorageKey, jsonStr);
      if (saved == false) {
        debugPrint('Warning: SharedPreferences setString returned false (storage quota)');
      }
    } catch (e) {
      debugPrint('Error saving complaints to storage: $e');
    }
  }

  List<Complaint> get complaints => _complaints;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get selectedFilter => _selectedFilter;

  // Filtered lists for Reporter
  List<Complaint> get reporterComplaints => _complaints;

  /// Active, unresolved complaints for Live Incident Map (excludes completed/repaired and rejected issues)
  List<Complaint> get activeComplaints => _complaints.where((c) => c.isActive).toList();
  int get totalCount => _complaints.length;
  int get pendingCount => _complaints.where((c) => c.status != 'Completed' && c.status != 'Rejected').length;
  int get completedCount => _complaints.where((c) => c.status == 'Completed').length;
  int get emergencyCount => _complaints.where((c) => c.isEmergency && c.status != 'Completed' && c.status != 'Rejected').length;
  int get activeReportsCount => _complaints.where((c) => c.isActive).length;
  int get inRepairCount => _complaints.where((c) => c.status.toLowerCase() == 'accepted' || c.status.toLowerCase() == 'work started' || c.status.toLowerCase() == 'repair in progress' || c.status.toLowerCase() == 'near completion').length;

  String? get selectedStateFilter => _selectedStateFilter;
  String? get selectedDistrictFilter => _selectedDistrictFilter;
  String get selectedCategoryFilter => _selectedCategoryFilter;
  String get selectedSeverityFilter => _selectedSeverityFilter;

  void setSelectedStateFilter(String? state) {
    _selectedStateFilter = state;
    _selectedDistrictFilter = null;
    notifyListeners();
  }

  void setSelectedDistrictFilter(String? district) {
    _selectedDistrictFilter = district;
    notifyListeners();
  }

  void setSelectedCategoryFilter(String category) {
    _selectedCategoryFilter = category;
    notifyListeners();
  }

  void setSelectedSeverityFilter(String severity) {
    _selectedSeverityFilter = severity;
    notifyListeners();
  }

  Map<String, int> get complaintsCountByState {
    final Map<String, int> map = {};
    for (var c in _complaints) {
      final s = c.stateDisplay;
      map[s] = (map[s] ?? 0) + 1;
    }
    return map;
  }

  Map<String, int> get complaintsCountByDistrict {
    final Map<String, int> map = {};
    for (var c in _complaints) {
      final d = c.districtDisplay;
      map[d] = (map[d] ?? 0) + 1;
    }
    return map;
  }

  List<Complaint> complaintsForDistrict(String district, [String? state]) {
    final cleanDist = district.trim().toLowerCase();
    final cleanSt = state?.trim().toLowerCase();
    return _complaints.where((c) {
      final cd = c.districtDisplay.toLowerCase();
      final cs = c.stateDisplay.toLowerCase();
      final distMatch = cd == cleanDist || cd.contains(cleanDist) || cleanDist.contains(cd);
      if (!distMatch) return false;
      if (cleanSt != null && cleanSt.isNotEmpty) {
        return cs == cleanSt || cs.contains(cleanSt);
      }
      return true;
    }).toList();
  }

  List<Complaint> complaintsForRepairTeam(String repairTeamId) {
    final cleanId = repairTeamId.trim().toLowerCase();
    return _complaints.where((c) => (c.repairTeamId ?? '').toLowerCase() == cleanId).toList();
  }

  List<Complaint> filteredComplaintsForDistrict(String district, [String? state]) {
    final base = complaintsForDistrict(district, state);
    return _applyDistrictFilters(base);
  }

  List<Complaint> get adminFilteredComplaints {
    List<Complaint> list = _complaints;
    if (_selectedStateFilter != null && _selectedStateFilter!.isNotEmpty && _selectedStateFilter != 'All') {
      list = list.where((c) => c.stateDisplay.toLowerCase() == _selectedStateFilter!.toLowerCase()).toList();
    }
    if (_selectedDistrictFilter != null && _selectedDistrictFilter!.isNotEmpty && _selectedDistrictFilter != 'All') {
      list = list.where((c) => c.districtDisplay.toLowerCase() == _selectedDistrictFilter!.toLowerCase()).toList();
    }
    return _applyDistrictFilters(list);
  }

  List<Complaint> _applyDistrictFilters(List<Complaint> input) {
    return input.where((c) {
      final matchesSearch = _searchQuery.isEmpty ||
          c.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.complaintId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.address.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.districtDisplay.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      // Status
      if (_selectedFilter == 'Pending Verification') {
        if (!(c.status == 'Submitted' || c.status == 'Under Verification')) return false;
      } else if (_selectedFilter == 'Emergency') {
        if (!(c.isEmergency && c.status != 'Completed' && c.status != 'Rejected')) return false;
      } else if (_selectedFilter == 'Accepted') {
        if (!(c.status == 'Accepted' || c.status == 'Work Started' || c.status == 'Repair In Progress')) return false;
      } else if (_selectedFilter == 'Completed') {
        if (!(c.status == 'Completed')) return false;
      }

      // Category
      if (_selectedCategoryFilter != 'All') {
        if (c.category.toLowerCase() != _selectedCategoryFilter.toLowerCase()) return false;
      }

      // Severity
      if (_selectedSeverityFilter != 'All') {
        if (c.severity.toLowerCase() != _selectedSeverityFilter.toLowerCase()) return false;
      }

      return true;
    }).toList();
  }

  // Filtered complaints for Community User (defaults to full list with query and tab filter)
  List<Complaint> get filteredComplaints {
    return _complaints.where((c) {
      final matchesSearch = c.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.complaintId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.address.toLowerCase().contains(_searchQuery.toLowerCase());
      
      if (!matchesSearch) return false;

      if (_selectedFilter == 'Pending Verification') {
        return c.status == 'Submitted' || c.status == 'Under Verification';
      } else if (_selectedFilter == 'Emergency') {
        return c.isEmergency && c.status != 'Completed' && c.status != 'Rejected';
      } else if (_selectedFilter == 'Accepted') {
        return c.status == 'Accepted' || c.status == 'Work Started' || c.status == 'Repair In Progress';
      } else if (_selectedFilter == 'Completed') {
        return c.status == 'Completed';
      }
      return true;
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilter(String filter) {
    _selectedFilter = filter;
    notifyListeners();
  }

  /// Get complaint by ID (case-insensitive)
  Complaint? getComplaintById(String complaintId) {
    final cleanId = complaintId.trim().toLowerCase();
    try {
      return _complaints.firstWhere(
        (c) => c.complaintId.trim().toLowerCase() == cleanId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Find duplicate active complaint at same location/category in memory
  Complaint? findDuplicateComplaint({
    required String category,
    required double latitude,
    required double longitude,
    required String address,
    double radiusMeters = 500.0,
  }) {
    final cleanCategory = SupabaseService.normalizeCategory(category);
    final cleanAddr = address.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final inputTokens = cleanAddr
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && t != 'road' && t != 'street' && t != 'india')
        .toSet();

    for (var c in _complaints) {
      // Ignore completed, fake, or rejected issues
      if (c.status == 'Completed' || c.status == 'Rejected' || c.status == 'Fake') continue;

      // Check category match using normalized category
      final isSameCategory = SupabaseService.normalizeCategory(c.category) == cleanCategory;
      if (!isSameCategory) continue;

      // Check location distance (meters)
      final distanceInMeters = SupabaseService.calculateDistanceMeters(latitude, longitude, c.latitude, c.longitude);
      
      // Token-set intersection matching
      final existingAddr = c.address.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
      final existingTokens = existingAddr
          .split(RegExp(r'\s+'))
          .where((t) => t.length > 2 && t != 'road' && t != 'street' && t != 'india')
          .toSet();

      final matchingTokens = inputTokens.intersection(existingTokens);
      final isTokenMatch = matchingTokens.length >= 2;
      final isSubstringMatch = (cleanAddr.isNotEmpty && existingAddr.isNotEmpty) &&
          (cleanAddr.contains(existingAddr) || existingAddr.contains(cleanAddr));

      // Duplicate found if within configurable radius OR key location tokens match
      if (distanceInMeters <= radiusMeters || isTokenMatch || isSubstringMatch) {
        return c;
      }
    }
    return null;
  }

  /// Async duplicate check against both local state and Supabase database
  Future<Complaint?> checkAndFindDuplicate({
    required String category,
    required double latitude,
    required double longitude,
    required String address,
    double radiusMeters = 500.0,
  }) async {
    // 1. Check local complaints first
    final localMatch = findDuplicateComplaint(
      category: category,
      latitude: latitude,
      longitude: longitude,
      address: address,
      radiusMeters: radiusMeters,
    );
    if (localMatch != null) return localMatch;

    // 2. Check Supabase DB if connected
    if (SupabaseService.isConnected) {
      final dbDupMap = await SupabaseService.findDuplicateReportInDatabase(
        category: category,
        latitude: latitude,
        longitude: longitude,
        address: address,
        radiusMeters: radiusMeters,
      );

      if (dbDupMap != null) {
        final cid = (dbDupMap['id'] ?? dbDupMap['complaint_id'] ?? '').toString();
        Complaint dbComplaint;
        final existingIdx = _complaints.indexWhere((c) => c.complaintId.toLowerCase() == cid.toLowerCase());
        if (existingIdx != -1) {
          dbComplaint = _complaints[existingIdx];
        } else {
          dbComplaint = Complaint.fromJson(dbDupMap);
          _complaints.insert(0, dbComplaint);
        }
        return dbComplaint;
      }
    }
    return null;
  }

  /// Automatically generate Complaint ID: RW-XXXX
  String _generateComplaintId() {
    final random = Random();
    final num = 1000 + random.nextInt(9000);
    return 'RW-$num';
  }

  /// Reporter submits a new damage complaint
  Future<Complaint?> submitComplaint({
    required String reporterId,
    required String reporterName,
    String reporterPhone = '',
    required String title,
    required String description,
    required String category,
    required String severity,
    required double latitude,
    required double longitude,
    required String address,
    required String imageUrl,
    double gpsAccuracy = 5.0,
    String? state,
    String? district,
    String? city,
  }) async {
    _isLoading = true;
    notifyListeners();

    // Check duplicate first before creating
    final activeDuplicate = await checkAndFindDuplicate(
      category: category,
      latitude: latitude,
      longitude: longitude,
      address: address,
    );

    if (activeDuplicate != null) {
      debugPrint('⚠️ Aborting submitComplaint: active duplicate complaint exists (${activeDuplicate.complaintId})');
      _isLoading = false;
      notifyListeners();
      return activeDuplicate;
    }

    final now = DateTime.now();
    String finalImg = imageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1515162816999-a0c47dc192f7?w=800&auto=format&fit=crop'
        : imageUrl;

    // If image is a base64 / data URL, upload to Supabase Storage first
    if (finalImg.startsWith('data:image')) {
      try {
        final commaIdx = finalImg.indexOf(',');
        if (commaIdx != -1) {
          final bytes = base64Decode(finalImg.substring(commaIdx + 1));
          final fileName = 'report_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final uploaded = await SupabaseService.uploadReportImage(
            fileName: fileName,
            imageBytes: bytes,
            userId: reporterId,
          );
          if (uploaded != null && uploaded.isNotEmpty) {
            finalImg = uploaded;
          }
        }
      } catch (e) {
        debugPrint('Notice uploading base64 report image: $e');
      }
    }

    String complaintId = _generateComplaintId();
    Map<String, dynamic>? supabaseRecord;

    // 1. Insert into Supabase PostgreSQL 'reports' table if connected
    if (SupabaseService.isConnected) {
      supabaseRecord = await SupabaseService.createReportInDatabase(
        imageUrl: finalImg,
        latitude: latitude,
        longitude: longitude,
        gpsAccuracy: gpsAccuracy,
        address: address,
        capturedAt: now,
        issueType: category,
        description: description,
        userId: reporterId,
        severity: severity,
        status: 'Submitted',
        state: state,
        district: district,
        city: city,
      );

      if (supabaseRecord != null) {
        if (supabaseRecord['is_duplicate'] == true) {
          debugPrint('Notice: Supabase server-side returned duplicate record');
          final existingC = Complaint.fromJson(supabaseRecord);
          final existingInMemory = _complaints.firstWhere(
            (c) => c.complaintId.toLowerCase() == existingC.complaintId.toLowerCase(),
            orElse: () {
              _complaints.insert(0, existingC);
              return existingC;
            },
          );
          _isLoading = false;
          notifyListeners();
          return existingInMemory;
        }

        final rawId = supabaseRecord['id'] ?? supabaseRecord['complaint_id'];
        if (rawId != null) {
          complaintId = rawId.toString();
        }
      } else {
        // If Supabase is connected but insert fails, stop and return null
        debugPrint('❌ Supabase report creation failed, aborting complaint submission');
        _isLoading = false;
        notifyListeners();
        return null;
      }
    }

    double finalLat = latitude;
    final parsedLat = Complaint.parseNullableDouble(supabaseRecord?['latitude']);
    if (parsedLat != null) {
      finalLat = parsedLat;
    }

    double finalLng = longitude;
    final parsedLng = Complaint.parseNullableDouble(supabaseRecord?['longitude']);
    if (parsedLng != null) {
      finalLng = parsedLng;
    }
    final String finalStatus = supabaseRecord?['status']?.toString() ?? 'Submitted';
    final DateTime finalCreatedAt = supabaseRecord?['created_at'] != null
        ? (SupabaseService.parseTimestamptz(supabaseRecord!['created_at']) ?? now)
        : now;

    final detectedGeo = IndiaDistricts.detectFromAddress(address);
    final String finalState = state ?? supabaseRecord?['state']?.toString() ?? detectedGeo?['state'] ?? 'Tamil Nadu';
    final String finalDistrict = district ?? supabaseRecord?['district']?.toString() ?? detectedGeo?['district'] ?? 'Kanchipuram';
    final String finalCity = city ?? supabaseRecord?['city']?.toString() ?? finalDistrict;

    final newComplaint = Complaint(
      complaintId: complaintId,
      reporterId: reporterId,
      reporterName: reporterName,
      reporterPhone: reporterPhone,
      title: title.isEmpty ? '$category at $address' : title,
      description: description,
      category: category,
      severity: severity,
      latitude: finalLat,
      longitude: finalLng,
      address: address,
      imageUrl: finalImg,
      beforeImageUrl: finalImg,
      status: finalStatus,
      state: finalState,
      district: finalDistrict,
      city: finalCity,
      createdAt: finalCreatedAt,
    );

    _complaints.removeWhere((c) => c.complaintId.toLowerCase() == newComplaint.complaintId.toLowerCase());
    _complaints.insert(0, newComplaint);
    _complaints.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _saveComplaintsToStorage();
    _isLoading = false;
    notifyListeners();

    if (SupabaseService.isConnected) {
      await refreshComplaints();
      // Trigger in-app confirmation notification to authenticated reporter
      try {
        await SupabaseService.triggerStatusNotification(
          complaint: newComplaint,
          status: 'Submitted',
        );
      } catch (_) {}
    }

    return newComplaint;
  }

  // ============================================================
  // DISTRICT & REPAIR TEAM MANAGEMENT METHODS
  // ============================================================

  /// Assign an eligible complaint to a local Repair Team
  Future<bool> assignComplaintToRepairTeam({
    required String complaintId,
    required String repairTeamId,
    required String repairTeamName,
    required String assignedByUserId,
  }) async {
    final success = SupabaseService.isConnected
        ? await SupabaseService.assignComplaintToRepairTeam(
            complaintId: complaintId,
            repairTeamId: repairTeamId,
            repairTeamName: repairTeamName,
            assignedByUserId: assignedByUserId,
          )
        : true;

    final idx = _complaints.indexWhere((c) => c.complaintId.toLowerCase() == complaintId.toLowerCase());
    if (idx != -1) {
      final updated = _complaints[idx].copyWith(
        status: 'Accepted',
        repairTeamId: repairTeamId,
        repairTeamName: repairTeamName,
        assignedToRepairTeamAt: DateTime.now(),
      );
      _complaints[idx] = updated;
      await _saveComplaintsToStorage();
      notifyListeners();

      // Trigger notification for assignment
      try {
        await SupabaseService.triggerStatusNotification(
          complaint: updated,
          status: 'Accepted',
          progressNote: 'Assigned to repair team: $repairTeamName',
        );
      } catch (_) {}
    }
    return success;
  }

  /// Update or correct a complaint's assigned District
  Future<bool> updateComplaintDistrict({
    required String complaintId,
    required String state,
    required String district,
    String? city,
  }) async {
    final success = SupabaseService.isConnected
        ? await SupabaseService.updateComplaintDistrict(
            complaintId: complaintId,
            state: state,
            district: district,
            city: city,
          )
        : true;

    final idx = _complaints.indexWhere((c) => c.complaintId.toLowerCase() == complaintId.toLowerCase());
    if (idx != -1) {
      _complaints[idx] = _complaints[idx].copyWith(
        state: state,
        district: district,
        city: city,
      );
      await _saveComplaintsToStorage();
      notifyListeners();
    }
    return success;
  }

  /// Fetch Repair Teams across districts with filtering
  Future<List<RepairTeam>> fetchRepairTeams({String? state, String? district}) async {
    return SupabaseService.fetchRepairTeams(state: state, district: district);
  }

  /// Create a new local Repair Team
  Future<bool> createRepairTeam(RepairTeam team) async {
    final res = await SupabaseService.createRepairTeam(team);
    notifyListeners();
    return res;
  }

  /// Update an existing Repair Team
  Future<bool> updateRepairTeam(RepairTeam team) async {
    final res = await SupabaseService.updateRepairTeam(team);
    notifyListeners();
    return res;
  }

  /// Fetch Community Users across India or filtered by state/district
  Future<List<Map<String, dynamic>>> fetchCommunityUsers({String? state, String? district}) async {
    return SupabaseService.fetchCommunityUsers(state: state, district: district);
  }

  /// Admin: Assign a Community User to a specific state and district
  Future<bool> assignCommunityUserDistrict({
    required String userId,
    required String state,
    required String district,
  }) async {
    final res = await SupabaseService.assignCommunityUserDistrict(
      userId: userId,
      state: state,
      district: district,
    );
    notifyListeners();
    return res;
  }

  /// Admin: Activate or deactivate a Community User
  Future<bool> setCommunityUserActiveStatus({
    required String userId,
    required bool isActive,
  }) async {
    final res = await SupabaseService.setCommunityUserActiveStatus(
      userId: userId,
      isActive: isActive,
    );
    notifyListeners();
    return res;
  }

  /// Cast community poll vote (Genuine Issue vs Fake Issue)
  Future<VoteSaveResult> castCommunityPollVote({
    required String complaintId,
    required String userId,
    String? userEmail,
    required bool isReal,
    double? userLat,
    double? userLng,
  }) async {
    final cleanCid = complaintId.trim().toLowerCase();
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == cleanCid ||
             c.title.trim().toLowerCase() == 'title_$cleanCid',
    );

    final current = index != -1 ? _complaints[index] : null;

    // Final status check: Permanently close voting for rejected/fake complaints
    if (current != null && current.isRejected) {
      return VoteSaveResult(
        success: false,
        errorMessage: 'This complaint was rejected as fake by the community. Voting is closed.',
      );
    }

    // Final status check: Permanently close voting once work has completed
    if (current != null && current.isCompleted) {
      return VoteSaveResult(
        success: false,
        errorMessage: 'Voting closed — work completed.',
      );
    }

    // Final status check: Permanently close voting once work has started or beyond
    if (current != null && current.isWorkStartedOrBeyond) {
      return VoteSaveResult(
        success: false,
        errorMessage: 'Voting closed — work has started.',
      );
    }

    // 1. Enforce location requirement and coordinate validity
    if (userLat == null || userLng == null || !Complaint.isValidCoordinates(userLat, userLng)) {
      return VoteSaveResult(
        success: false,
        errorMessage: 'Valid current GPS location is required to vote.',
      );
    }

    // 2. Validate complaint coordinates
    if (current == null || !current.hasValidCoordinates) {
      return VoteSaveResult(
        success: false,
        errorMessage: 'Current location is required to vote. Complaint coordinates are invalid or unavailable.',
      );
    }

    // 3. Enforce 500 m location restriction using Haversine formula
    final distanceMeters = SupabaseService.calculateDistanceMeters(
      userLat,
      userLng,
      current.latitude,
      current.longitude,
    );

    if (distanceMeters > 500.0) {
      return VoteSaveResult(
        success: false,
        errorMessage: 'Location mismatch: Voting is available only within 500 meters of the reported issue.',
      );
    }

    // 4. Enforce one-vote-per-user-per-complaint rule
    if (current.isVotedBy(userId, userEmail, _deviceVoterId)) {
      return VoteSaveResult(
        success: false,
        errorMessage: 'You have already voted on this complaint.',
      );
    }

    final voteValue = isReal ? 'genuine' : 'fake';

    // 5. Attempt persistent save to Supabase DB if connected
    VoteSaveResult saveResult;
    if (SupabaseService.isConnected) {
      saveResult = await SupabaseService.saveCommunityVote(
        complaintId: complaintId,
        userId: userId,
        vote: voteValue,
        userEmail: userEmail,
        deviceVoterId: _deviceVoterId,
        userLat: userLat,
        userLng: userLng,
        complaintLat: current.latitude,
        complaintLng: current.longitude,
      );

      if (!saveResult.success) {
        debugPrint('❌ Vote save to Supabase DB failed: ${saveResult.errorMessage}');
        if ((saveResult.errorMessage ?? '').toLowerCase().contains('rejected') && index != -1) {
          _complaints[index] = _complaints[index].copyWith(status: 'Rejected');
          await _saveComplaintsToStorage();
          notifyListeners();
        }
        return saveResult;
      }
    } else {
      saveResult = VoteSaveResult(success: true);
    }

    // 6. If DB confirmed or offline fallback, update in-memory state & SharedPreferences
    if (index != -1) {
      final current = _complaints[index];
      final prefs = await SharedPreferences.getInstance();

      _deviceVoterId ??= prefs.getString(_deviceVoterIdKey) ?? 'voter_${DateTime.now().millisecondsSinceEpoch}';

      final cleanUserId = userId.trim().isNotEmpty ? userId.trim() : _deviceVoterId!;

      final newUserVotes = Map<String, String>.from(current.userVotes);
      newUserVotes[cleanUserId.toLowerCase()] = voteValue;

      final newVotedUserIds = List<String>.from(current.votedUserIds);
      if (!newVotedUserIds.contains(cleanUserId.toLowerCase())) {
        newVotedUserIds.add(cleanUserId.toLowerCase());
      }

      // Recalculate unique real and fake vote counts
      int realCount = 0;
      int fakeCount = 0;
      final countedVoters = <String>{};

      newUserVotes.forEach((voterKey, vVal) {
        final keyNorm = voterKey.trim().toLowerCase();
        if (keyNorm.isEmpty || keyNorm == 'device_voter' || keyNorm == 'session_voter' || keyNorm == 'device_has_voted') return;
        if (!countedVoters.contains(keyNorm)) {
          countedVoters.add(keyNorm);
          final isGenuine = vVal == 'Genuine Issue' || vVal == 'real' || vVal == 'genuine';
          if (isGenuine) {
            realCount++;
          } else {
            fakeCount++;
          }
        }
      });

      Complaint updated = current.copyWith(
        realVotes: realCount,
        fakeVotes: fakeCount,
        votedUserIds: newVotedUserIds,
        userVotes: newUserVotes,
      );

      // Auto-reject if community vote strongly consensus as fake (>=60% fake & >=3 votes)
      if (updated.isCommunityFlaggedFake && updated.status == 'Submitted') {
        updated = updated.copyWith(status: 'Rejected');
        if (SupabaseService.isConnected) {
          try {
            final res = await SupabaseService.updateReportStatus(
              reportId: complaintId,
              status: 'Rejected',
            );
            await SupabaseService.triggerStatusNotification(
              complaint: updated,
              status: 'Rejected',
              targetReportId: res.reportId,
              targetReporterUserId: res.userId,
            );
          } catch (_) {}
        }
      }

      _complaints[index] = updated;

      // Save into persistent local votes map in SharedPreferences
      final storedVotesJson = prefs.getString(_userVotesStorageKey);
      Map<String, Map<String, String>> localUserVotes = {};
      if (storedVotesJson != null && storedVotesJson.isNotEmpty) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(storedVotesJson);
          decoded.forEach((cid, votesMap) {
            if (votesMap is Map) {
              localUserVotes[cid.trim().toLowerCase()] = Map<String, String>.from(
                votesMap.map((k, v) => MapEntry(k.toString().trim().toLowerCase(), v.toString().trim())),
              );
            }
          });
        } catch (_) {}
      }

      final saveKeys = <String>{
        complaintId.trim().toLowerCase(),
        current.complaintId.trim().toLowerCase(),
      };

      for (var key in saveKeys) {
        localUserVotes.putIfAbsent(key, () => {});
        localUserVotes[key]![cleanUserId.toLowerCase()] = voteValue;
      }

      await prefs.setString(_userVotesStorageKey, jsonEncode(localUserVotes));
      await _saveComplaintsToStorage();

      if (SupabaseService.isConnected) {
        try {
          await SupabaseService.updateReportVotes(
            complaintId: complaintId,
            realVotes: realCount,
            fakeVotes: fakeCount,
            votedUserIds: newVotedUserIds,
            userVotes: newUserVotes,
            complaint: updated,
          );
        } catch (_) {}
      }

      notifyListeners();
    }

    return saveResult;
  }

  /// Community User verifies a complaint
  Future<ReportUpdateResult> verifyComplaint(String complaintId, [String? communityUserId, String? communityUserName]) async {
    final cleanId = complaintId.trim();
    debugPrint('========================================');
    debugPrint('ComplaintProvider.verifyComplaint called for ID: "$cleanId"');
    debugPrint('========================================');

    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == cleanId.toLowerCase() ||
             c.title.trim().toLowerCase() == cleanId.toLowerCase(),
    );

    final targetComplaint = index != -1 ? _complaints[index] : null;

    // If already verified, return success immediately
    if (targetComplaint != null && (targetComplaint.status == 'Verified' || targetComplaint.status == 'Accepted' || targetComplaint.isWorkStartedOrBeyond)) {
      return ReportUpdateResult(success: true);
    }

    final newProgress = targetComplaint != null ? max(20.0, targetComplaint.progressPercentage) : 20.0;
    final updateTime = DateTime.now().toUtc();
    final effectiveUpdateId = 'VERIFY-${targetComplaint?.complaintId ?? cleanId}';
    final effectiveUserId = (communityUserId != null && communityUserId.trim().isNotEmpty)
        ? communityUserId.trim()
        : 'comm_verifier';
    final effectiveUserName = (communityUserName != null && communityUserName.trim().isNotEmpty)
        ? communityUserName.trim()
        : 'Community Inspector';

    final alreadyHasVerify = targetComplaint?.updates.any(
      (u) => u.status.trim().toLowerCase() == 'verified' || u.updateId == effectiveUpdateId,
    ) ?? false;

    final verifyUpdate = ProgressUpdate(
      updateId: effectiveUpdateId,
      complaintId: targetComplaint?.complaintId ?? cleanId,
      communityUserId: effectiveUserId,
      communityUserName: effectiveUserName,
      progressNote: 'Complaint verified on site as a genuine road issue.',
      workPercentage: newProgress,
      status: 'Verified',
      createdAt: updateTime,
    );

    final updatedList = alreadyHasVerify
        ? (targetComplaint?.updates ?? [verifyUpdate])
        : Complaint.deduplicateUpdates([...(targetComplaint?.updates ?? []), verifyUpdate]);

    ReportUpdateResult supabaseResult = ReportUpdateResult(success: true);

    if (SupabaseService.isConnected) {
      final saveRes = await SupabaseService.saveProgressUpdateInDatabase(
        complaintId: targetComplaint?.complaintId ?? cleanId,
        communityUserId: effectiveUserId,
        communityUserName: effectiveUserName,
        progressNote: verifyUpdate.progressNote,
        workPercentage: newProgress,
        status: 'Verified',
        allUpdates: updatedList,
        complaint: targetComplaint,
      );

      if (!saveRes.success) {
        debugPrint('❌ Failed to save verification to Supabase progress_updates: ${saveRes.errorMessage}');
        return ReportUpdateResult(
          success: false,
          errorMessage: saveRes.errorMessage ?? 'Failed to save verification to database.',
        );
      }

      supabaseResult = await SupabaseService.updateReportStatus(
        reportId: targetComplaint?.complaintId ?? cleanId,
        status: 'Verified',
        progressPercentage: newProgress,
        complaint: targetComplaint,
      );
    }

    if (supabaseResult.success) {
      if (index != -1 && targetComplaint != null) {
        _complaints[index] = targetComplaint.copyWith(
          status: 'Verified',
          progressPercentage: newProgress,
          updates: updatedList,
          updatedAt: updateTime,
        );
      } else {
        _complaints.add(Complaint(
          complaintId: cleanId,
          reporterId: 'rep_101',
          reporterName: 'Reporter name unavailable',
          reporterPhone: '',
          title: cleanId,
          description: 'Verified Complaint',
          category: 'Other',
          severity: 'Medium',
          latitude: 0.0,
          longitude: 0.0,
          address: 'Location',
          imageUrl: '',
          status: 'Verified',
          progressPercentage: newProgress,
          updates: updatedList,
          createdAt: updateTime,
        ));
      }
      await _saveComplaintsToStorage();

      // Re-sync with Supabase DB so state matches backend records exactly
      if (SupabaseService.isConnected) {
        try {
          final remoteReports = await SupabaseService.getReports();
          for (var reportMap in remoteReports) {
            final c = Complaint.fromJson(reportMap);
            final cIdLower = c.complaintId.trim().toLowerCase();
            final targetIdLower = (targetComplaint?.complaintId ?? cleanId).trim().toLowerCase();
            if (cIdLower == targetIdLower) {
              final idx = _complaints.indexWhere((item) => item.complaintId.trim().toLowerCase() == cIdLower);
              if (idx != -1) {
                _complaints[idx] = _complaints[idx].copyWith(
                  status: c.status,
                  progressPercentage: max(_complaints[idx].progressPercentage, c.progressPercentage),
                );
              }
              break;
            }
          }
        } catch (e) {
          debugPrint('Notice re-syncing complaint after verification: $e');
        }
      }

      // Trigger in-app notification for verification
      try {
        final currentComplaint = _complaints.firstWhere(
          (c) => c.complaintId.trim().toLowerCase() == cleanId.toLowerCase(),
          orElse: () => targetComplaint ?? _complaints[index != -1 ? index : 0],
        );
        await SupabaseService.triggerStatusNotification(
          complaint: currentComplaint,
          status: 'Verified',
          targetReportId: supabaseResult.reportId,
          targetReporterUserId: supabaseResult.userId,
        );
      } catch (errNotif) {
        debugPrint('Notice triggering notification for verification: $errNotif');
      }

      notifyListeners();
      return ReportUpdateResult(success: true);
    } else {
      debugPrint('❌ Failed to verify complaint $cleanId in Supabase DB: ${supabaseResult.errorMessage}');
      return supabaseResult;
    }
  }

  /// Community User marks complaint as fake
  Future<ReportUpdateResult> markFakeComplaint(String complaintId) async {
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == complaintId.trim().toLowerCase() ||
             c.title.trim().toLowerCase() == complaintId.trim().toLowerCase(),
    );

    final targetComplaint = index != -1 ? _complaints[index] : null;
    ReportUpdateResult supabaseResult = ReportUpdateResult(success: true);

    if (SupabaseService.isConnected) {
      supabaseResult = await SupabaseService.updateReportStatus(
        reportId: targetComplaint?.complaintId ?? complaintId,
        status: 'Rejected',
        progressPercentage: 0.0,
        complaint: targetComplaint,
      );
    }

    if (supabaseResult.success) {
      if (index != -1 && targetComplaint != null) {
        _complaints[index] = targetComplaint.copyWith(
          status: 'Rejected',
          progressPercentage: 0.0,
        );
      }
      await _saveComplaintsToStorage();

      // Trigger in-app notification for rejection
      try {
        final currentComplaint = _complaints.firstWhere(
          (c) => c.complaintId.trim().toLowerCase() == complaintId.trim().toLowerCase(),
          orElse: () => targetComplaint ?? _complaints[index != -1 ? index : 0],
        );
        await SupabaseService.triggerStatusNotification(
          complaint: currentComplaint,
          status: 'Rejected',
          targetReportId: supabaseResult.reportId,
          targetReporterUserId: supabaseResult.userId,
        );
      } catch (errNotif) {
        debugPrint('Notice triggering notification for rejection: $errNotif');
      }

      notifyListeners();
      return ReportUpdateResult(success: true);
    } else {
      debugPrint('❌ Failed to mark fake complaint $complaintId in Supabase DB: ${supabaseResult.errorMessage}');
      return supabaseResult;
    }
  }

  /// Community User accepts repair complaint work
  Future<ReportUpdateResult> acceptComplaint(String complaintId, String communityUserId, String communityUserName) async {
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == complaintId.trim().toLowerCase() ||
             c.title.trim().toLowerCase() == complaintId.trim().toLowerCase(),
    );

    final targetComplaint = index != -1 ? _complaints[index] : null;

    // Requirement 7: Ensure a rejected complaint cannot be accepted for repair
    if (targetComplaint != null && targetComplaint.isRejected) {
      return ReportUpdateResult(
        success: false,
        errorMessage: 'This complaint was rejected as fake and cannot be accepted for repair.',
      );
    }

    // If already accepted, return success immediately
    if (targetComplaint != null &&
        (targetComplaint.status == 'Accepted' ||
         targetComplaint.status == 'Work Started' ||
         targetComplaint.status == 'Repair In Progress')) {
      return ReportUpdateResult(success: true);
    }

    final newProgress = targetComplaint != null ? max(30.0, targetComplaint.progressPercentage) : 30.0;
    final updateTime = DateTime.now().toUtc();
    final effectiveUpdateId = 'ACCEPT-${targetComplaint?.complaintId ?? complaintId}';

    final alreadyHasAccept = targetComplaint?.updates.any(
      (u) => u.status.trim().toLowerCase() == 'accepted' || u.updateId == effectiveUpdateId,
    ) ?? false;

    final acceptUpdate = ProgressUpdate(
      updateId: effectiveUpdateId,
      complaintId: targetComplaint?.complaintId ?? complaintId,
      communityUserId: communityUserId,
      communityUserName: communityUserName,
      progressNote: 'Repair work accepted by community volunteer crew: $communityUserName.',
      workPercentage: newProgress,
      status: 'Accepted',
      createdAt: updateTime,
    );

    final updatedList = alreadyHasAccept
        ? (targetComplaint?.updates ?? [acceptUpdate])
        : Complaint.deduplicateUpdates([...(targetComplaint?.updates ?? []), acceptUpdate]);

    ReportUpdateResult supabaseResult = ReportUpdateResult(success: true);

    if (SupabaseService.isConnected) {
      final saveRes = await SupabaseService.saveProgressUpdateInDatabase(
        complaintId: targetComplaint?.complaintId ?? complaintId,
        communityUserId: communityUserId,
        communityUserName: communityUserName,
        progressNote: acceptUpdate.progressNote,
        workPercentage: newProgress,
        status: 'Accepted',
        allUpdates: updatedList,
        complaint: targetComplaint,
      );

      if (!saveRes.success) {
        debugPrint('❌ Failed to save acceptance to Supabase progress_updates: ${saveRes.errorMessage}');
        return ReportUpdateResult(
          success: false,
          errorMessage: saveRes.errorMessage ?? 'Failed to save acceptance to database.',
        );
      }

      supabaseResult = await SupabaseService.updateReportStatus(
        reportId: targetComplaint?.complaintId ?? complaintId,
        status: 'Accepted',
        progressPercentage: newProgress,
        communityUserId: communityUserId,
        communityUserName: communityUserName,
        complaint: targetComplaint,
      );
    }

    if (supabaseResult.success) {
      if (index != -1 && targetComplaint != null) {
        _complaints[index] = targetComplaint.copyWith(
          status: 'Accepted',
          acceptedByCommunityUser: communityUserId,
          communityUserName: communityUserName,
          progressPercentage: newProgress,
          updates: updatedList,
          updatedAt: updateTime,
        );
      }
      await _saveComplaintsToStorage();

      // Trigger in-app notification for repair acceptance
      try {
        final currentComplaint = _complaints.firstWhere(
          (c) => c.complaintId.trim().toLowerCase() == complaintId.trim().toLowerCase(),
          orElse: () => targetComplaint ?? _complaints[index != -1 ? index : 0],
        );
        await SupabaseService.triggerStatusNotification(
          complaint: currentComplaint,
          status: 'Accepted',
          communityUserId: communityUserId,
          communityUserName: communityUserName,
          targetReportId: supabaseResult.reportId,
          targetReporterUserId: supabaseResult.userId,
        );
      } catch (errNotif) {
        debugPrint('Notice triggering notification for acceptance: $errNotif');
      }

      notifyListeners();
      return ReportUpdateResult(success: true);
    } else {
      debugPrint('❌ Failed to accept complaint $complaintId in Supabase DB: ${supabaseResult.errorMessage}');
      return supabaseResult;
    }
  }

  /// Start repair work
  Future<ReportUpdateResult> startWork(String complaintId) async {
    final cleanId = complaintId.trim().toLowerCase();
    int index = _complaints.indexWhere((c) => c.complaintId.trim().toLowerCase() == cleanId);
    if (index == -1) {
      index = _complaints.indexWhere((c) => c.title.trim().toLowerCase() == cleanId);
    }
    if (index == -1) {
      return ReportUpdateResult(
        success: false,
        errorMessage: 'Complaint $complaintId not found.',
      );
    }
    final current = _complaints[index];
    if (current.isRejected) {
      debugPrint('startWork aborted: complaint $complaintId is rejected as fake.');
      return ReportUpdateResult(
        success: false,
        errorMessage: 'Complaint $complaintId is rejected as fake.',
      );
    }

    final newPercentage = max(40.0, current.progressPercentage);
    final updateTime = DateTime.now().toUtc();
    final effectiveUpdateId = 'START-${current.complaintId}';

    final alreadyHasStart = current.updates.any(
      (u) => u.status.trim().toLowerCase() == 'work started' || u.updateId == effectiveUpdateId,
    );

    final startUpdate = ProgressUpdate(
      updateId: effectiveUpdateId,
      complaintId: current.complaintId,
      communityUserId: current.acceptedByCommunityUser ?? 'comm_user_1',
      communityUserName: current.communityUserName ?? 'Volunteer Team',
      progressNote: 'Work started on site. Safety barriers erected.',
      workPercentage: newPercentage,
      status: 'Work Started',
      createdAt: updateTime,
    );

    final updatedList = alreadyHasStart
        ? current.updates
        : Complaint.deduplicateUpdates([...current.updates, startUpdate]);

    if (SupabaseService.isConnected) {
      final saveRes = await SupabaseService.saveProgressUpdateInDatabase(
        complaintId: current.complaintId,
        communityUserId: current.acceptedByCommunityUser ?? 'comm_user_1',
        communityUserName: current.communityUserName ?? 'Volunteer Team',
        progressNote: startUpdate.progressNote,
        workPercentage: newPercentage,
        status: 'Work Started',
        allUpdates: updatedList,
        complaint: current,
      );

      if (!saveRes.success) {
        debugPrint('❌ Failed to save start work to Supabase progress_updates: ${saveRes.errorMessage}');
        return ReportUpdateResult(
          success: false,
          errorMessage: saveRes.errorMessage ?? 'Failed to save Work Started to database.',
        );
      }

      await SupabaseService.updateReportStatus(
        reportId: current.complaintId,
        status: 'Work Started',
        progressPercentage: newPercentage,
        communityUserId: current.acceptedByCommunityUser,
        communityUserName: current.communityUserName,
        complaint: current,
      );
    }

    _complaints[index] = current.copyWith(
      status: 'Work Started',
      progressPercentage: newPercentage,
      updates: updatedList,
      updatedAt: updateTime,
    );
    await _saveComplaintsToStorage();

    // Trigger in-app notification for work started
    try {
      await SupabaseService.triggerStatusNotification(
        complaint: _complaints[index],
        status: 'Work Started',
        progressPercentage: newPercentage,
        communityUserId: current.acceptedByCommunityUser,
        communityUserName: current.communityUserName,
      );
    } catch (errNotif) {
      debugPrint('Notice triggering notification for work started: $errNotif');
    }

    notifyListeners();
    return ReportUpdateResult(success: true);
  }

  /// Update repair progress percentage and post note & photo
  Future<WorkProgressResult> updateWorkProgress({
    required String complaintId,
    required String progressNote,
    required double percentage,
    String? imageUrl,
    String? communityUserId,
    String? communityUserName,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? capturedAt,
    Complaint? complaint,
  }) async {
    final cleanId = complaintId.trim().toLowerCase();
    int index = _complaints.indexWhere((c) => c.complaintId.trim().toLowerCase() == cleanId);
    if (index == -1 && SupabaseService.isConnected) {
      try {
        final reportRow = await SupabaseService.getReportById(complaintId);
        if (reportRow != null) {
          final repId = reportRow['id']?.toString().trim().toLowerCase();
          final repCid = reportRow['complaint_id']?.toString().trim().toLowerCase();
          if (repId != null && repId.isNotEmpty) {
            index = _complaints.indexWhere((c) => c.complaintId.trim().toLowerCase() == repId);
          }
          if (index == -1 && repCid != null && repCid.isNotEmpty) {
            index = _complaints.indexWhere((c) => c.complaintId.trim().toLowerCase() == repCid);
          }
        }
      } catch (_) {}
    }
    if (index == -1) {
      if (complaint != null) {
        _complaints.add(complaint);
        index = _complaints.length - 1;
      } else {
        debugPrint('Error: Complaint $complaintId not found for progress update');
        return WorkProgressResult(
          success: false,
          errorMessage: 'Complaint $complaintId not found in active state.',
        );
      }
    }

    try {
      final current = _complaints[index];
      if (current.isRejected) {
        return WorkProgressResult(
          success: false,
          errorMessage: 'This complaint was rejected as fake and cannot receive repair progress updates.',
        );
      }

      // Enforce 500m location restriction when progress photo is submitted
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        // Resolve original reporter complaint reference coordinates
        double refLat = current.latitude;
        double refLng = current.longitude;

        if ((refLat == 0.0 && refLng == 0.0) && complaint != null && Complaint.isValidCoordinates(complaint.latitude, complaint.longitude)) {
          refLat = complaint.latitude;
          refLng = complaint.longitude;
        }

        // Only query Supabase if in-memory complaint coordinates are missing or invalid
        if (!Complaint.isValidCoordinates(refLat, refLng) && SupabaseService.isConnected) {
          try {
            final reportRow = await SupabaseService.getReportById(current.complaintId) ??
                await SupabaseService.getReportById(complaintId);
            if (reportRow != null) {
              double rLat = 0.0;
              double rLng = 0.0;
              final rawLat = reportRow['latitude'] ?? reportRow['lat'];
              final rawLng = reportRow['longitude'] ?? reportRow['lng'] ?? reportRow['lon'];
              if (rawLat is num) {
                rLat = rawLat.toDouble();
              } else if (rawLat is String) {
                rLat = double.tryParse(rawLat.trim()) ?? 0.0;
              }
              if (rawLng is num) {
                rLng = rawLng.toDouble();
              } else if (rawLng is String) {
                rLng = double.tryParse(rawLng.trim()) ?? 0.0;
              }
              if (rLat.abs() > 90.0 && rLng.abs() <= 90.0) {
                final temp = rLat;
                rLat = rLng;
                rLng = temp;
              }
              if (rLat != 0.0 || rLng != 0.0) {
                refLat = rLat;
                refLng = rLng;
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Notice resolving reference complaint coordinates in updateWorkProgress: $e');
            }
          }
        }

        if (refLat.abs() > 90.0 && refLng.abs() <= 90.0) {
          final temp = refLat;
          refLat = refLng;
          refLng = temp;
        }

        if (!Complaint.isValidCoordinates(refLat, refLng)) {
          if (kDebugMode) {
            debugPrint('⚠️ [LOCATION REJECTION] Original complaint GPS coordinates missing or invalid: ($refLat, $refLng)');
          }
          return WorkProgressResult(
            success: false,
            errorMessage: 'Original complaint GPS location is missing. Unable to validate photo location.',
          );
        }

        double photoLat = latitude ?? 0.0;
        double photoLng = longitude ?? 0.0;
        if (photoLat.abs() > 90.0 && photoLng.abs() <= 90.0) {
          final temp = photoLat;
          photoLat = photoLng;
          photoLng = temp;
        }

        if (latitude == null || longitude == null || !Complaint.isValidCoordinates(photoLat, photoLng)) {
          if (kDebugMode) {
            debugPrint('⚠️ [LOCATION REJECTION] Progress photo GPS coordinates missing or invalid: ($photoLat, $photoLng)');
          }
          return WorkProgressResult(
            success: false,
            errorMessage: 'Progress photo GPS coordinates are missing or invalid. A new photo with valid GPS coordinates captured at the complaint location is required.',
          );
        }

        final distanceMeters = SupabaseService.calculateDistanceMeters(
          photoLat,
          photoLng,
          refLat,
          refLng,
        );

        if (kDebugMode) {
          debugPrint('📍 [PROVIDER WORK PROGRESS LOCATION VALIDATION]');
          debugPrint('Complaint Reference: ($refLat, $refLng)');
          debugPrint('Photo Capture Location: ($photoLat, $photoLng)');
          debugPrint('Calculated Distance: ${distanceMeters.toStringAsFixed(1)}m');
        }

        if (distanceMeters > 500.0) {
          if (kDebugMode) {
            debugPrint('⚠️ [LOCATION REJECTION] Distance (${distanceMeters.toStringAsFixed(1)}m) > 500m. Location mismatch: photo was not captured within 500m of complaint.');
          }
          return WorkProgressResult(
            success: false,
            errorMessage: 'Location mismatch: capture the progress photo within 500 metres of the original reported complaint location.',
          );
        }
      }

      final statusStr = percentage >= 100.0
          ? 'Completed'
          : percentage >= 85.0
              ? 'Near Completion'
              : 'Repair In Progress';

      String? uploadedPublicUrl = imageUrl;

      // 1. Upload photo to Supabase Storage if imageUrl is base64 data URL
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        final rawImg = imageUrl.trim();
        if (rawImg.startsWith('data:')) {
          if (SupabaseService.isConnected || SupabaseService.mockUploadProgressImage != null) {
            try {
              final base64Str = rawImg.contains(',') ? rawImg.split(',').last : rawImg;
              final bytes = base64Decode(base64Str);
              final fileName = 'progress_${DateTime.now().millisecondsSinceEpoch}.jpg';
              final url = await SupabaseService.uploadProgressImage(
                fileName: fileName,
                imageBytes: bytes,
                userId: communityUserId ?? current.acceptedByCommunityUser,
              );
              if (url != null && url.isNotEmpty) {
                uploadedPublicUrl = url;
              } else {
                final storageErr = SupabaseService.lastStorageError ?? 'Storage upload failed';
                debugPrint('❌ Progress photo storage upload failed: $storageErr');
                return WorkProgressResult(
                  success: false,
                  errorMessage: 'Failed to upload progress image: $storageErr',
                );
              }
            } catch (e) {
              debugPrint('Error uploading progress photo bytes to Supabase: $e');
              return WorkProgressResult(
                success: false,
                errorMessage: 'Error uploading progress image: $e',
              );
            }
          } else {
            uploadedPublicUrl = rawImg;
          }
        } else {
          uploadedPublicUrl = rawImg;
        }
      }

      final effectiveUserId = (communityUserId != null && communityUserId.trim().isNotEmpty)
          ? communityUserId.trim()
          : (current.acceptedByCommunityUser?.trim().isNotEmpty == true
              ? current.acceptedByCommunityUser!
              : 'comm_user_1');

      final effectiveUserName = (communityUserName != null && communityUserName.trim().isNotEmpty)
          ? communityUserName.trim()
          : (current.communityUserName?.trim().isNotEmpty == true
              ? current.communityUserName!
              : 'Community Volunteer');

      final updateTime = DateTime.now().toUtc();
      String? effectiveAddress = address;
      if ((effectiveAddress == null ||
              effectiveAddress.trim().isEmpty ||
              effectiveAddress == 'Location' ||
              effectiveAddress == 'Location Unavailable' ||
              effectiveAddress.trim().startsWith('Detecting')) &&
          latitude != null &&
          longitude != null &&
          Complaint.isValidCoordinates(latitude, longitude)) {
        try {
          final rev = await LocationService.reverseGeocode(latitude, longitude);
          if (rev.isNotEmpty && !rev.startsWith('Detecting')) {
            effectiveAddress = rev;
          }
        } catch (_) {}
      }

      final effectiveCaptureTime = capturedAt?.toUtc() ?? updateTime;

      final newUpdate = ProgressUpdate(
        updateId: 'UPD-${DateTime.now().millisecondsSinceEpoch}',
        complaintId: current.complaintId,
        communityUserId: effectiveUserId,
        communityUserName: effectiveUserName,
        progressNote: progressNote,
        imageUrl: uploadedPublicUrl,
        workPercentage: percentage,
        status: statusStr,
        createdAt: updateTime,
        latitude: latitude,
        longitude: longitude,
        address: effectiveAddress,
        capturedAt: effectiveCaptureTime,
      );

      final updatedList = Complaint.deduplicateUpdates([...current.updates, newUpdate]);
      updatedList.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      var updatedComplaint = current.copyWith(
        status: statusStr,
        progressPercentage: percentage,
        acceptedByCommunityUser: effectiveUserId,
        communityUserName: effectiveUserName,
        afterImageUrl: percentage >= 95.0
            ? (uploadedPublicUrl ?? current.afterImageUrl)
            : current.afterImageUrl,
        completionNotes: percentage >= 95.0 ? progressNote : current.completionNotes,
        updates: updatedList,
        updatedAt: updateTime,
      );

      // 2. Save progress update to Supabase Database
      SaveProgressResult? dbResult;
      if (SupabaseService.isConnected || SupabaseService.mockSaveProgressUpdateInDatabase != null) {
        dbResult = await SupabaseService.saveProgressUpdateInDatabase(
          complaintId: current.complaintId,
          communityUserId: effectiveUserId,
          communityUserName: effectiveUserName,
          progressNote: progressNote,
          imageUrl: uploadedPublicUrl,
          workPercentage: percentage,
          status: statusStr,
          allUpdates: updatedList,
          latitude: latitude,
          longitude: longitude,
          address: effectiveAddress,
          capturedAt: effectiveCaptureTime,
          complaint: current,
        );

        if (!dbResult.success) {
          debugPrint('❌ Supabase database save returned error for progress update: ${dbResult.errorMessage}');
          return WorkProgressResult(
            success: false,
            errorMessage: dbResult.errorMessage ?? 'Failed to save progress update to Supabase DB.',
            uploadedImageUrl: uploadedPublicUrl,
          );
        }

        // Bind database primary key UUID if returned
        final generatedId = dbResult.data?['id']?.toString();
        if (generatedId != null && generatedId.isNotEmpty) {
          final withDbId = newUpdate.copyWith(id: generatedId);
          final refreshedUpdates = updatedList.map((u) => u.updateId == newUpdate.updateId ? withDbId : u).toList();
          updatedComplaint = updatedComplaint.copyWith(updates: refreshedUpdates);
        }
      }

      _complaints[index] = updatedComplaint;
      await _saveComplaintsToStorage();

      // Trigger in-app notification for progress update status changes
      if (statusStr == 'Repair In Progress' || statusStr == 'Work Started' || statusStr == 'Near Completion' || statusStr == 'Completed') {
        try {
          await SupabaseService.triggerStatusNotification(
            complaint: updatedComplaint,
            status: statusStr,
            progressPercentage: percentage,
            progressNote: progressNote,
            communityUserId: effectiveUserId,
            communityUserName: effectiveUserName,
            targetReportId: dbResult?.data?['report_id']?.toString(),
            targetReporterUserId: dbResult?.data?['user_id']?.toString(),
          );
        } catch (errNotif) {
          debugPrint('Notice triggering notification for progress update: $errNotif');
        }
      }

      notifyListeners();
      return WorkProgressResult(
        success: true,
        uploadedImageUrl: uploadedPublicUrl,
      );
    } catch (e) {
      debugPrint('Error updating work progress: $e');
      return WorkProgressResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Securely delete a progress update from a complaint
  Future<DeleteProgressResult> deleteWorkProgressUpdate({
    required String complaintId,
    required String updateId,
    String? recordId,
    required String requestingUserId,
    required String requestingUserRole,
  }) async {
    final cleanCId = complaintId.trim().toLowerCase();
    int index = _complaints.indexWhere((c) => c.complaintId.trim().toLowerCase() == cleanCId);
    if (index == -1) {
      index = _complaints.indexWhere((c) => c.title.trim().toLowerCase() == cleanCId);
    }

    if (index == -1) {
      return DeleteProgressResult(
        success: false,
        errorMessage: 'Complaint $complaintId not found.',
      );
    }

    final current = _complaints[index];

    // Find the update to be deleted by recordId (UUID) or updateId
    final cleanRecordId = recordId?.trim();
    final cleanUpdateId = updateId.trim();

    final updateIndex = current.updates.indexWhere(
      (u) => (cleanRecordId != null && cleanRecordId.isNotEmpty && u.id != null && u.id!.trim().toLowerCase() == cleanRecordId.toLowerCase()) ||
             (cleanUpdateId.isNotEmpty && u.updateId.trim() == cleanUpdateId),
    );

    if (updateIndex == -1) {
      return DeleteProgressResult(
        success: false,
        errorMessage: 'Progress update record not found in complaint.',
      );
    }

    final targetUpdate = current.updates[updateIndex];

    if (requestingUserId.trim().isEmpty) {
      return DeleteProgressResult(
        success: false,
        errorMessage: 'Authentication required: User must be signed in to delete progress updates.',
      );
    }

    // Authorization verification: only the creator or an administrator may delete
    final isAdmin = requestingUserRole.trim().toLowerCase() == 'admin';
    final isCreator = targetUpdate.communityUserId.trim().isNotEmpty &&
        targetUpdate.communityUserId.trim() == requestingUserId.trim();
    if (!isAdmin && !isCreator) {
      return DeleteProgressResult(
        success: false,
        errorMessage: 'Unauthorized: Only the creator of this progress update or an administrator can delete it.',
      );
    }

    // Do not allow deleting progress on completed complaints per requirements 6 & 9
    if (current.isCompleted || current.status.trim().toLowerCase() == 'completed') {
      return DeleteProgressResult(
        success: false,
        errorMessage: 'Cannot delete progress updates for a completed complaint.',
      );
    }

    final remainingUpdates = current.updates
        .where((u) {
          if (cleanRecordId != null && cleanRecordId.isNotEmpty && u.id != null && u.id!.trim().toLowerCase() == cleanRecordId.toLowerCase()) {
            return false;
          }
          if (cleanUpdateId.isNotEmpty && u.updateId.trim() == cleanUpdateId) {
            return false;
          }
          return true;
        })
        .toList();
    remainingUpdates.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Call Supabase DB deletion
    if (SupabaseService.isConnected) {
      final dbResult = await SupabaseService.deleteProgressUpdate(
        updateId: updateId,
        recordId: targetUpdate.id ?? recordId,
        complaintId: current.complaintId,
        requestingUserId: requestingUserId,
        requestingUserRole: requestingUserRole,
        remainingUpdates: remainingUpdates,
        imageUrl: targetUpdate.imageUrl,
        complaint: current,
      );

      if (!dbResult.success) {
        return dbResult;
      }
    }

    // Recalibrate complaint status and percentage from remaining updates
    final double newPercentage = remainingUpdates.isNotEmpty
        ? remainingUpdates.last.workPercentage
        : 0.0;
    final String newStatus = remainingUpdates.isNotEmpty
        ? (newPercentage >= 100.0
            ? 'Completed'
            : (newPercentage >= 85.0
                ? 'Near Completion'
                : 'Repair In Progress'))
        : 'Accepted';

    final updatedComplaint = current.copyWith(
      progressPercentage: newPercentage,
      status: newStatus,
      updates: remainingUpdates,
      afterImageUrl: newPercentage >= 95.0 ? current.afterImageUrl : null,
      completionNotes: newPercentage >= 95.0 ? current.completionNotes : null,
      updatedAt: DateTime.now(),
    );

    _complaints[index] = updatedComplaint;
    await _saveComplaintsToStorage();
    notifyListeners();

    return DeleteProgressResult(success: true);
  }

  /// Mark work completed and upload final after-repair photo
  Future<ReportUpdateResult> completeWork({
    required String complaintId,
    required String afterImageUrl,
    required String completionNotes,
  }) async {
    final cleanId = complaintId.trim().toLowerCase();
    int index = _complaints.indexWhere((c) => c.complaintId.trim().toLowerCase() == cleanId);
    if (index == -1) {
      index = _complaints.indexWhere((c) => c.title.trim().toLowerCase() == cleanId);
    }
    if (index == -1) {
      return ReportUpdateResult(
        success: false,
        errorMessage: 'Complaint $complaintId not found.',
      );
    }

    final current = _complaints[index];
    final finalAfterImg = afterImageUrl.isEmpty
        ? 'https://images.unsplash.com/photo-1513836279014-a89f7a76ae86?w=800&auto=format&fit=crop'
        : afterImageUrl;
    final finalNotes = completionNotes.isEmpty
        ? 'Work 100% completed & site inspected.'
        : completionNotes;

    final updateTime = DateTime.now().toUtc();
    final effectiveUpdateId = 'COMPLETE-${current.complaintId}';

    final alreadyHasComplete = current.updates.any(
      (u) => u.status.trim().toLowerCase() == 'completed' || u.updateId == effectiveUpdateId,
    );

    final completeUpdate = ProgressUpdate(
      updateId: effectiveUpdateId,
      complaintId: current.complaintId,
      communityUserId: current.acceptedByCommunityUser ?? 'comm_user_1',
      communityUserName: current.communityUserName ?? 'Volunteer Crew',
      progressNote: finalNotes,
      imageUrl: finalAfterImg,
      workPercentage: 100.0,
      status: 'Completed',
      createdAt: updateTime,
    );

    final updatedList = alreadyHasComplete
        ? current.updates
        : Complaint.deduplicateUpdates([...current.updates, completeUpdate]);

    if (SupabaseService.isConnected) {
      final saveRes = await SupabaseService.saveProgressUpdateInDatabase(
        complaintId: current.complaintId,
        communityUserId: current.acceptedByCommunityUser ?? 'comm_user_1',
        communityUserName: current.communityUserName ?? 'Volunteer Crew',
        progressNote: finalNotes,
        imageUrl: finalAfterImg,
        workPercentage: 100.0,
        status: 'Completed',
        allUpdates: updatedList,
        complaint: current,
      );

      if (!saveRes.success) {
        debugPrint('❌ Failed to save completion to Supabase progress_updates: ${saveRes.errorMessage}');
        return ReportUpdateResult(
          success: false,
          errorMessage: saveRes.errorMessage ?? 'Failed to save completion to database.',
        );
      }

      await SupabaseService.updateReportStatus(
        reportId: current.complaintId,
        status: 'Completed',
        progressPercentage: 100.0,
        communityUserId: current.acceptedByCommunityUser,
        communityUserName: current.communityUserName,
        complaint: current,
      );
    }

    _complaints[index] = current.copyWith(
      status: 'Completed',
      progressPercentage: 100.0,
      afterImageUrl: finalAfterImg,
      completionNotes: finalNotes,
      updates: updatedList,
      updatedAt: updateTime,
    );
    await _saveComplaintsToStorage();

    // Trigger in-app notification for completed work
    try {
      await SupabaseService.triggerStatusNotification(
        complaint: _complaints[index],
        status: 'Completed',
        progressPercentage: 100.0,
        progressNote: finalNotes,
        communityUserId: current.acceptedByCommunityUser,
        communityUserName: current.communityUserName,
      );
    } catch (errNotif) {
      debugPrint('Notice triggering notification for completion: $errNotif');
    }

    notifyListeners();
    return ReportUpdateResult(success: true);
  }

  /// Reporter submits rating and feedback
  Future<FeedbackSubmitResult> submitFeedback({
    required String complaintId,
    required String reporterId,
    String? reporterName,
    required double rating,
    required String comments,
  }) async {
    final cleanId = complaintId.trim();
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == cleanId.toLowerCase(),
    );
    if (index == -1) {
      return FeedbackSubmitResult(
        success: false,
        errorMessage: 'Complaint $cleanId not found.',
      );
    }

    final target = _complaints[index];
    final existingForReporter = target.feedbackForReporter(reporterId);
    final effectiveFeedbackId = (existingForReporter != null && existingForReporter.feedbackId.isNotEmpty)
        ? existingForReporter.feedbackId
        : (target.feedback != null && target.feedback!.feedbackId.isNotEmpty && target.feedback!.reporterId == reporterId
            ? target.feedback!.feedbackId
            : 'FB-${DateTime.now().millisecondsSinceEpoch}');

    final existingCreatedAt = existingForReporter?.createdAt ??
        (target.feedback != null && (target.feedback!.reporterId == reporterId || target.feedback!.reporterId == target.reporterId)
            ? target.feedback!.createdAt
            : null);

    final feedbackObj = FeedbackModel(
      feedbackId: effectiveFeedbackId,
      complaintId: target.complaintId,
      reporterId: reporterId.isNotEmpty ? reporterId : target.reporterId,
      reporterName: (reporterName != null && reporterName.isNotEmpty)
          ? reporterName
          : target.reporterName,
      rating: rating,
      comments: comments,
      createdAt: existingCreatedAt ?? DateTime.now(),
      updatedAt: existingCreatedAt != null ? DateTime.now() : null,
    );

    FeedbackModel effectiveSavedFeedback = feedbackObj;

    // Save to Supabase Database first if connected
    if (SupabaseService.isConnected) {
      final dbResult = await SupabaseService.saveReportFeedback(
        complaintId: target.complaintId,
        feedback: feedbackObj,
        complaint: target,
      );

      if (!dbResult.success) {
        debugPrint('❌ Supabase database feedback save failed: ${dbResult.errorMessage}');
        return FeedbackSubmitResult(
          success: false,
          errorMessage: dbResult.errorMessage ?? 'Failed to save feedback to database.',
        );
      }

      if (dbResult.feedback != null) {
        effectiveSavedFeedback = dbResult.feedback!.copyWith(
          complaintId: target.complaintId,
        );
      }
    }

    final updatedList = List<FeedbackModel>.from(target.allFeedbacks);
    final existingIdx = updatedList.indexWhere(
      (f) => f.reporterId.trim().toLowerCase() == effectiveSavedFeedback.reporterId.trim().toLowerCase(),
    );
    if (existingIdx != -1) {
      updatedList[existingIdx] = effectiveSavedFeedback;
    } else {
      updatedList.add(effectiveSavedFeedback);
    }

    _complaints[index] = target.copyWith(
      feedback: effectiveSavedFeedback,
      allFeedbacks: updatedList,
    );
    await _saveComplaintsToStorage();
    notifyListeners();

    return FeedbackSubmitResult(
      success: true,
      feedback: effectiveSavedFeedback,
    );
  }

  /// Updates or caches feedback for a specific complaint in local state
  void setComplaintFeedback(String complaintId, FeedbackModel feedback) {
    final cleanId = complaintId.trim().toLowerCase();
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == cleanId,
    );
    if (index != -1) {
      final updatedList = List<FeedbackModel>.from(_complaints[index].allFeedbacks);
      final existingIdx = updatedList.indexWhere(
        (f) => f.reporterId.trim().toLowerCase() == feedback.reporterId.trim().toLowerCase(),
      );
      if (existingIdx != -1) {
        updatedList[existingIdx] = feedback;
      } else {
        updatedList.add(feedback);
      }
      _complaints[index] = _complaints[index].copyWith(
        feedback: feedback,
        allFeedbacks: updatedList,
      );
      _saveComplaintsToStorage();
      notifyListeners();
    }
  }

  /// Sets all feedback entries for a specific complaint in local state
  void setComplaintFeedbacks(String complaintId, List<FeedbackModel> feedbacks) {
    final cleanId = complaintId.trim().toLowerCase();
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == cleanId,
    );
    if (index != -1) {
      _complaints[index] = _complaints[index].copyWith(
        feedback: feedbacks.isNotEmpty ? feedbacks.first : _complaints[index].feedback,
        allFeedbacks: feedbacks,
      );
      _saveComplaintsToStorage();
      notifyListeners();
    }
  }

  /// Fetches and caches all feedbacks for a complaint from Supabase or local state
  Future<List<FeedbackModel>> getFeedbacksForComplaint(String complaintId) async {
    final cleanId = complaintId.trim();
    if (SupabaseService.isConnected) {
      final remoteRows = await SupabaseService.getComplaintFeedbacks(cleanId);
      if (remoteRows.isNotEmpty) {
        final parsed = remoteRows.map((r) => FeedbackModel.fromJson(r)).toList();
        setComplaintFeedbacks(cleanId, parsed);
        return parsed;
      }
    }
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == cleanId.toLowerCase(),
    );
    if (index != -1) {
      return _complaints[index].allFeedbacks;
    }
    return [];
  }

  /// Delete complaint from database and local storage securely
  Future<ReportDeleteResult> deleteComplaint(String complaintId) async {
    final cleanId = complaintId.trim();
    final index = _complaints.indexWhere(
      (c) => c.complaintId.trim().toLowerCase() == cleanId.toLowerCase(),
    );

    if (index == -1) {
      return ReportDeleteResult(
        success: false,
        errorMessage: 'Complaint $cleanId not found.',
      );
    }

    final targetComplaint = _complaints[index];

    // 1. Enforce deletion restriction in logic layer
    if (!targetComplaint.canBeDeleted) {
      debugPrint('❌ DELETE BLOCKED: Complaint $cleanId is verified by community or completed.');
      return ReportDeleteResult(
        success: false,
        errorMessage: 'Cannot delete complaint: This complaint has already been verified by the Community or completed.',
      );
    }

    // 2. Perform Supabase database deletion if connected
    if (SupabaseService.isConnected) {
      final dbResult = await SupabaseService.deleteReport(targetComplaint.complaintId);
      if (!dbResult.success) {
        debugPrint('❌ Supabase database deletion failed: ${dbResult.errorMessage}');
        return dbResult;
      }
    }

    // 3. Remove complaint from local state only after confirmed success
    _complaints.removeAt(index);
    await _saveComplaintsToStorage();
    notifyListeners();
    return ReportDeleteResult(success: true);
  }

  /// Fetch voter details for a specific complaint from Supabase complaint_votes and profiles tables
  Future<List<VoterInfo>> getVotersForComplaint(Complaint complaint) async {
    List<VoterInfo> voters = [];

    // 1. Attempt fetching from Supabase database
    if (SupabaseService.isConnected) {
      try {
        voters = await SupabaseService.getVotersForComplaint(complaint.complaintId);
        // When connected to Supabase, the complaint_votes database table is the authoritative source.
        // Return database voters directly without merging legacy local map entries.
        return voters;
      } catch (e) {
        debugPrint('Notice fetching voters from Supabase: $e');
        rethrow;
      }
    }

    // 2. Offline fallback: deduplicate local votes by user ID
    final Set<String> existingUserIds = {};

    complaint.userVotes.forEach((voterKey, voteVal) {
      final keyClean = voterKey.trim().toLowerCase();
      if (keyClean.isEmpty || keyClean == 'device_voter' || keyClean == 'session_voter' || keyClean == 'device_has_voted') return;
      if (!existingUserIds.contains(keyClean)) {
        existingUserIds.add(keyClean);

        String displayName = 'Registered User';
        if (voterKey.contains('@')) {
          displayName = voterKey.split('@').first;
        }

        voters.add(VoterInfo(
          userId: voterKey.trim(),
          name: displayName,
          email: null,
          vote: voteVal.toLowerCase(),
        ));
      }
    });

    return voters;
  }
}

