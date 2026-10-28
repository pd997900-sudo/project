import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'india_districts.dart';

class Complaint {
  final String complaintId; // e.g. RW-8902
  final String reporterId;
  final String reporterName;
  final String reporterPhone;
  final String title;
  final String description;
  final String category; // Pothole, Damaged Road, Garbage, Drainage Issue, Street Light Failure
  final String severity; // Low, Medium, Emergency
  final double latitude;
  final double longitude;
  final String address;
  final String imageUrl;
  final String? beforeImageUrl;
  final String? afterImageUrl;
  final String status; // Submitted, Under Verification, Verified, Rejected, Accepted, Work Started, Repair In Progress, Completed
  final double progressPercentage;
  final String? acceptedByCommunityUser;
  final String? communityUserName;
  final String? completionNotes;
  final String? state;
  final String? district;
  final String? city;
  final String? repairTeamId;
  final String? repairTeamName;
  final DateTime? assignedToRepairTeamAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<ProgressUpdate> updates;
  final FeedbackModel? feedback;
  final List<FeedbackModel> allFeedbacks;

  // Community Verification Poll Fields
  final int realVotes;
  final int fakeVotes;
  final List<String> votedUserIds;
  final Map<String, String> userVotes;

  Complaint({
    required this.complaintId,
    required this.reporterId,
    required this.reporterName,
    this.reporterPhone = '',
    required this.title,
    required this.description,
    required this.category,
    required this.severity,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.imageUrl,
    this.beforeImageUrl,
    this.afterImageUrl,
    required this.status,
    this.progressPercentage = 0.0,
    this.acceptedByCommunityUser,
    this.communityUserName,
    this.completionNotes,
    this.state,
    this.district,
    this.city,
    this.repairTeamId,
    this.repairTeamName,
    this.assignedToRepairTeamAt,
    DateTime? createdAt,
    this.updatedAt,
    List<ProgressUpdate>? updates,
    this.feedback,
    List<FeedbackModel>? allFeedbacks,
    this.realVotes = 0,
    this.fakeVotes = 0,
    List<String>? votedUserIds,
    Map<String, String>? userVotes,
  })  : createdAt = createdAt ?? DateTime.now(),
        updates = updates ?? [],
        allFeedbacks = allFeedbacks ?? (feedback != null ? [feedback] : []),
        votedUserIds = votedUserIds ?? [],
        userVotes = userVotes ?? {};

  /// Normalizes severity string using trimming and case-insensitive matching.
  /// Categorizes into: 'Emergency' (for Emergency, Critical, High),
  /// 'Medium' (for Medium, Moderate, Med, Amber, Yellow),
  /// or 'Low' (for Low or any fallback).
  static String normalizeSeverity(String? raw) {
    if (raw == null) return 'Low';
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'Low';
    if (s == 'emergency' || s == 'critical' || s == 'high') {
      return 'Emergency';
    }
    if (s == 'medium' || s == 'moderate' || s == 'med' || s == 'amber' || s == 'yellow') {
      return 'Medium';
    }
    return 'Low';
  }

  /// Consistent severity-to-color mapping:
  /// - Emergency / Critical / High -> RED (AppTheme.emergencyRed)
  /// - Medium -> YELLOW or AMBER (Color(0xFFF59E0B))
  /// - Low -> GREEN (AppTheme.successGreen)
  static Color getSeverityColor(String? severity) {
    final s = (severity ?? '').trim().toLowerCase();
    if (s == 'emergency' || s == 'critical' || s == 'high') {
      return AppTheme.emergencyRed;
    } else if (s == 'medium' || s == 'moderate' || s == 'med' || s == 'amber' || s == 'yellow') {
      return const Color(0xFFF59E0B);
    } else {
      return AppTheme.successGreen;
    }
  }

  /// Hex color representation for MapLibre circle layers:
  /// - Emergency / Critical / High -> RED ('#E53935')
  /// - Medium -> YELLOW or AMBER ('#F59E0B')
  /// - Low -> GREEN ('#43A047')
  static String getSeverityHexColor(String? severity) {
    final s = (severity ?? '').trim().toLowerCase();
    if (s == 'emergency' || s == 'critical' || s == 'high') {
      return '#E53935';
    } else if (s == 'medium' || s == 'moderate' || s == 'med' || s == 'amber' || s == 'yellow') {
      return '#F59E0B';
    } else {
      return '#43A047';
    }
  }

  Color get severityColor => getSeverityColor(severity);
  String get severityHexColor => getSeverityHexColor(severity);
  String get normalizedSeverity => normalizeSeverity(severity);

  bool get isEmergency {
    final s = severity.trim().toLowerCase();
    return s == 'emergency' || s == 'critical' || s == 'high';
  }

  static bool isValidCoordinates(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) return false;
    if (lat == 0.0 && lng == 0.0) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lng < -180.0 || lng > 180.0) return false;
    return true;
  }

  bool get hasValidCoordinates => isValidCoordinates(latitude, longitude);

  String get districtDisplay {
    if (district != null && district!.trim().isNotEmpty) {
      return district!.trim();
    }
    final detected = IndiaDistricts.detectFromAddress(address);
    if (detected != null && detected['district'] != null) {
      return detected['district']!;
    }
    return 'Kanchipuram';
  }

  String get stateDisplay {
    if (state != null && state!.trim().isNotEmpty) {
      return state!.trim();
    }
    final detected = IndiaDistricts.detectFromAddress(address);
    if (detected != null && detected['state'] != null) {
      return detected['state']!;
    }
    return 'Tamil Nadu';
  }

  bool get isAssignedToRepairTeam => repairTeamId != null && repairTeamId!.isNotEmpty;

  // Poll Getters
  int get totalVotes => realVotes + fakeVotes;
  double get realPercentage => totalVotes > 0 ? (realVotes / totalVotes) * 100 : 0.0;
  double get fakePercentage => totalVotes > 0 ? (fakeVotes / totalVotes) * 100 : 0.0;

  bool isVotedBy(String userId, [String? userEmail, String? deviceVoterId]) {
    final cleanId = userId.trim().toLowerCase();
    final cleanEmail = userEmail?.trim().toLowerCase();
    final cleanDevice = deviceVoterId?.trim().toLowerCase();

    if (cleanId.isEmpty && (cleanEmail == null || cleanEmail.isEmpty) && (cleanDevice == null || cleanDevice.isEmpty)) {
      return false;
    }

    for (var key in userVotes.keys) {
      final k = key.trim().toLowerCase();
      if (cleanId.isNotEmpty && k == cleanId) return true;
      if (cleanEmail != null && cleanEmail.isNotEmpty && k == cleanEmail) return true;
      if (cleanDevice != null && cleanDevice.isNotEmpty && k == cleanDevice) return true;
    }
    for (var id in votedUserIds) {
      final k = id.trim().toLowerCase();
      if (cleanId.isNotEmpty && k == cleanId) return true;
      if (cleanEmail != null && cleanEmail.isNotEmpty && k == cleanEmail) return true;
      if (cleanDevice != null && cleanDevice.isNotEmpty && k == cleanDevice) return true;
    }
    return false;
  }

  String? getVoteOf(String userId, [String? userEmail, String? deviceVoterId]) {
    final cleanId = userId.trim().toLowerCase();
    final cleanEmail = userEmail?.trim().toLowerCase();
    final cleanDevice = deviceVoterId?.trim().toLowerCase();

    if (cleanId.isEmpty && (cleanEmail == null || cleanEmail.isEmpty) && (cleanDevice == null || cleanDevice.isEmpty)) {
      return null;
    }

    for (var entry in userVotes.entries) {
      final k = entry.key.trim().toLowerCase();
      if (cleanId.isNotEmpty && k == cleanId) return entry.value;
      if (cleanEmail != null && cleanEmail.isNotEmpty && k == cleanEmail) return entry.value;
      if (cleanDevice != null && cleanDevice.isNotEmpty && k == cleanDevice) return entry.value;
    }
    return null;
  }
  bool get isCommunityVerifiedReal => totalVotes >= 3 && realPercentage >= 60.0;
  bool get isCommunityFlaggedFake => totalVotes >= 3 && fakePercentage >= 60.0;

  bool get isVerifiedByCommunity {
    final s = status.trim().toLowerCase();
    return s == 'verified' ||
        s == 'accepted' ||
        s == 'work started' ||
        s == 'repair in progress' ||
        s == 'near completion' ||
        s == 'completed' ||
        isCommunityVerifiedReal;
  }

  bool get isCompleted {
    final s = status.trim().toLowerCase();
    return s == 'completed' ||
        s == 'repaired' ||
        s == 'resolved' ||
        s == 'closed' ||
        progressPercentage >= 100.0;
  }

  bool get isRejected {
    final s = status.trim().toLowerCase();
    return s == 'rejected' || s == 'fake' || isCommunityFlaggedFake;
  }

  bool get isWorkStartedOrBeyond {
    final s = status.trim().toLowerCase();
    return s == 'work started' ||
        s == 'repair in progress' ||
        s == 'near completion' ||
        s == 'completed' ||
        s == 'repaired' ||
        s == 'resolved' ||
        s == 'closed' ||
        progressPercentage >= 40.0;
  }

  bool get isVotingClosed => isRejected || isWorkStartedOrBeyond;

  bool get canBeDeleted => !isVerifiedByCommunity && !isCompleted && !isRejected;

  /// Whether the complaint is an active, unresolved incident (excludes completed, repaired, and rejected issues).
  bool get isActive {
    final s = status.trim().toLowerCase();
    if (isCompleted ||
        s == 'completed' ||
        s == 'repaired' ||
        s == 'resolved' ||
        s == 'closed') {
      return false;
    }
    if (isRejected || s == 'rejected' || s == 'fake' || isCommunityFlaggedFake) {
      return false;
    }
    return true;
  }

  bool get hasValidFeedback =>
      (feedback != null && feedback!.rating > 0) || allFeedbacks.any((f) => f.rating > 0);

  FeedbackModel? feedbackForReporter(String? reporterId) {
    if (reporterId == null || reporterId.trim().isEmpty) return null;
    final rClean = reporterId.trim().toLowerCase();
    for (var fb in allFeedbacks) {
      if (fb.reporterId.trim().toLowerCase() == rClean) {
        return fb;
      }
    }
    if (feedback != null && feedback!.reporterId.trim().toLowerCase() == rClean) {
      return feedback;
    }
    return null;
  }

  static double parseDouble(dynamic val, [double fallback = 0.0]) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val.trim()) ?? fallback;
    }
    return fallback;
  }

  static double? parseNullableDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) {
      final s = val.trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    return null;
  }

  static int parseInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    if (val is String) {
      return int.tryParse(val.trim()) ?? fallback;
    }
    return fallback;
  }

  static Map<String, String> parseUserVotes(dynamic raw) {
    final Map<String, String> map = {};
    if (raw == null) return map;
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k != null && v != null) {
          map[k.toString().trim()] = v.toString().trim();
        }
      });
    } else if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (k != null && v != null) {
              map[k.toString().trim()] = v.toString().trim();
            }
          });
        }
      } catch (_) {}
    }
    return map;
  }

  static List<String> _parseVotedUserIds(dynamic raw) {
    final List<String> list = [];
    if (raw == null) return list;
    if (raw is List) {
      for (var item in raw) {
        if (item != null && item.toString().trim().isNotEmpty) {
          list.add(item.toString().trim());
        }
      }
    } else if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (var item in decoded) {
            if (item != null && item.toString().trim().isNotEmpty) {
              list.add(item.toString().trim());
            }
          }
        }
      } catch (_) {
        final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
        list.addAll(parts);
      }
    }
    return list;
  }

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool isUuid(String value) {
    return _uuidRegex.hasMatch(value.trim());
  }

  static List<ProgressUpdate> deduplicateUpdates(List<ProgressUpdate> list) {
    final Map<String, ProgressUpdate> uniqueMap = {};
    for (var u in list) {
      String key;
      if (u.updateId.isNotEmpty && !u.updateId.startsWith('UPD-temp')) {
        key = 'upd_${u.updateId.trim()}';
      } else if (u.id != null && u.id!.isNotEmpty && _uuidRegex.hasMatch(u.id!.trim())) {
        key = 'uuid_${u.id!.trim().toLowerCase()}';
      } else {
        key = 'attr_${u.complaintId}_${u.workPercentage}_${u.progressNote.trim()}_${u.createdAt.millisecondsSinceEpoch ~/ 2000}';
      }

      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = u;
      } else {
        // Merge updates: retain authoritative database primary key UUID and ensure GPS location is preserved
        final existing = uniqueMap[key]!;
        final bool uHasCoords = Complaint.isValidCoordinates(u.latitude, u.longitude);
        final bool existingHasCoords = Complaint.isValidCoordinates(existing.latitude, existing.longitude);

        final String? effectiveId = (existing.id != null && existing.id!.isNotEmpty)
            ? existing.id
            : u.id;

        final double? effectiveLat = uHasCoords
            ? u.latitude
            : (existingHasCoords ? existing.latitude : null);

        final double? effectiveLng = uHasCoords
            ? u.longitude
            : (existingHasCoords ? existing.longitude : null);

        final String? effectiveAddress = (u.address != null &&
                u.address!.trim().isNotEmpty &&
                u.address != 'Location' &&
                u.address != 'Location Unavailable' &&
                !u.address!.trim().startsWith('Detecting'))
            ? u.address
            : existing.address;

        final DateTime? effectiveCapturedAt = u.capturedAt ?? existing.capturedAt;

        // Base update to keep: prefer whichever has DB id, else u
        final ProgressUpdate base = ((existing.id == null || existing.id!.isEmpty) && (u.id != null && u.id!.isNotEmpty))
            ? u
            : existing;

        uniqueMap[key] = base.copyWith(
          id: effectiveId,
          latitude: effectiveLat,
          longitude: effectiveLng,
          address: effectiveAddress,
          capturedAt: effectiveCapturedAt,
        );
      }
    }
    final result = uniqueMap.values.toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  static DateTime? parseTimestamptz(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    try {
      if (str.endsWith('Z') || str.contains('+') || RegExp(r'-\d{2}:?\d{2}$').hasMatch(str)) {
        return DateTime.parse(str).toUtc();
      }
      final normalized = str.contains('T') ? str : str.replaceFirst(' ', 'T');
      // Parse local ISO string and convert to UTC so all in-memory timestamps have isUtc: true
      return DateTime.parse(normalized).toUtc();
    } catch (_) {
      return DateTime.tryParse(str)?.toUtc();
    }
  }

  factory Complaint.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] != null && isUuid(json['id'].toString()))
        ? json['id']
        : (json['complaint_id'] ?? json['id']);
    final complaintIdStr = rawId != null ? rawId.toString() : '';

    final rawUserId = json['reporter_id'] ?? json['user_id'];
    final reporterIdStr = rawUserId != null ? rawUserId.toString() : '';

    final categoryStr = json['category'] ?? json['issue_type'] ?? 'Pothole';
    final titleStr = json['title'] ?? (json['issue_type'] != null ? '${json['issue_type']} at ${json['address'] ?? 'Road'}' : 'Road Damage Report');

    DateTime parsedCreatedAt = DateTime.now();
    if (json['captured_at'] != null) {
      parsedCreatedAt = parseTimestamptz(json['captured_at']) ?? DateTime.now();
    } else if (json['created_at'] != null) {
      parsedCreatedAt = parseTimestamptz(json['created_at']) ?? DateTime.now();
    }

    final rawUpdatesList = (json['updates'] as List<dynamic>?)
            ?.map((u) => ProgressUpdate.fromJson(u is Map<String, dynamic> ? u : Map<String, dynamic>.from(u)))
            .toList() ??
        [];

    String parsedName = 'Reporter name unavailable';
    final rawName = (json['reporter_name'] ?? json['user_name'])?.toString().trim();
    if (rawName != null &&
        rawName.isNotEmpty &&
        rawName != 'Citizen User' &&
        rawName != 'Registered User' &&
        rawName != 'Citizen Reporter' &&
        rawName != 'Name not available' &&
        rawName != 'Reporter name unavailable') {
      parsedName = rawName;
    }

    final rawSeverity = json['severity']?.toString().trim();
    final parsedSeverity = (rawSeverity != null && rawSeverity.isNotEmpty)
        ? rawSeverity
        : 'Low';

    double parsedLat = parseDouble(json['latitude'] ?? json['lat'], 0.0);
    double parsedLng = parseDouble(json['longitude'] ?? json['lng'] ?? json['lon'], 0.0);
    // Correct accidentally swapped coordinates (if latitude is > 90 and longitude is <= 90)
    if (parsedLat.abs() > 90.0 && parsedLng.abs() <= 90.0) {
      final temp = parsedLat;
      parsedLat = parsedLng;
      parsedLng = temp;
    }

    return Complaint(
      complaintId: complaintIdStr.isNotEmpty ? complaintIdStr : 'RW-${DateTime.now().millisecondsSinceEpoch % 10000}',
      reporterId: reporterIdStr,
      reporterName: parsedName,
      reporterPhone: json['reporter_phone'] ?? '',
      title: titleStr,
      description: json['description'] ?? '',
      category: categoryStr,
      severity: parsedSeverity,
      latitude: parsedLat,
      longitude: parsedLng,
      address: json['address'] ?? 'Main Street, City Center',
      imageUrl: json['image_url'] ?? '',
      beforeImageUrl: json['before_image_url'] ?? json['image_url'],
      afterImageUrl: json['after_image_url'],
      status: json['status'] ?? 'Submitted',
      progressPercentage: parseDouble(json['progress_percentage'], 0.0),
      acceptedByCommunityUser: json['community_user_id']?.toString(),
      communityUserName: json['community_user_name']?.toString(),
      completionNotes: json['completion_notes']?.toString(),
      state: json['state']?.toString(),
      district: json['district']?.toString(),
      city: json['city']?.toString(),
      repairTeamId: json['repair_team_id']?.toString(),
      repairTeamName: json['repair_team_name']?.toString(),
      assignedToRepairTeamAt: json['assigned_to_repair_team_at'] != null
          ? parseTimestamptz(json['assigned_to_repair_team_at'])
          : null,
      createdAt: parsedCreatedAt,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      updates: deduplicateUpdates(rawUpdatesList),
      feedback: json['feedback'] != null
          ? FeedbackModel.fromJson(
              json['feedback'] is String
                  ? jsonDecode(json['feedback'] as String)
                  : (json['feedback'] as Map<String, dynamic>),
            )
          : null,
      allFeedbacks: (json['all_feedbacks'] as List<dynamic>?)
              ?.map((f) => FeedbackModel.fromJson(f is Map<String, dynamic> ? f : Map<String, dynamic>.from(f)))
              .toList() ??
          (json['feedback'] != null
              ? [
                  FeedbackModel.fromJson(
                    json['feedback'] is String
                        ? jsonDecode(json['feedback'] as String)
                        : (json['feedback'] as Map<String, dynamic>),
                  )
                ]
              : <FeedbackModel>[]),
      realVotes: parseInt(json['real_votes'], 0),
      fakeVotes: parseInt(json['fake_votes'], 0),
      votedUserIds: _parseVotedUserIds(json['voted_user_ids']),
      userVotes: parseUserVotes(json['user_votes']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': complaintId,
      'complaint_id': complaintId,
      'reporter_id': reporterId,
      'reporter_name': reporterName,
      'reporter_phone': reporterPhone,
      'title': title,
      'description': description,
      'category': category,
      'severity': severity,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'image_url': imageUrl,
      'before_image_url': beforeImageUrl,
      'after_image_url': afterImageUrl,
      'status': status,
      'progress_percentage': progressPercentage,
      'community_user_id': acceptedByCommunityUser,
      'community_user_name': communityUserName,
      'completion_notes': completionNotes,
      'state': state,
      'district': district,
      'city': city,
      'repair_team_id': repairTeamId,
      'repair_team_name': repairTeamName,
      'assigned_to_repair_team_at': assignedToRepairTeamAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'updates': updates.map((u) => u.toJson()).toList(),
      'feedback': feedback?.toJson(),
      'all_feedbacks': allFeedbacks.map((f) => f.toJson()).toList(),
      'real_votes': realVotes,
      'fake_votes': fakeVotes,
      'voted_user_ids': votedUserIds,
      'user_votes': userVotes,
    };
  }

  Complaint copyWith({
    String? complaintId,
    String? reporterId,
    String? reporterName,
    String? reporterPhone,
    String? title,
    String? description,
    String? category,
    String? severity,
    double? latitude,
    double? longitude,
    String? address,
    String? imageUrl,
    String? beforeImageUrl,
    String? afterImageUrl,
    String? status,
    double? progressPercentage,
    String? acceptedByCommunityUser,
    String? communityUserName,
    String? completionNotes,
    String? state,
    String? district,
    String? city,
    String? repairTeamId,
    String? repairTeamName,
    DateTime? assignedToRepairTeamAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ProgressUpdate>? updates,
    FeedbackModel? feedback,
    bool clearFeedback = false,
    List<FeedbackModel>? allFeedbacks,
    int? realVotes,
    int? fakeVotes,
    List<String>? votedUserIds,
    Map<String, String>? userVotes,
  }) {
    return Complaint(
      complaintId: complaintId ?? this.complaintId,
      reporterId: reporterId ?? this.reporterId,
      reporterName: reporterName ?? this.reporterName,
      reporterPhone: reporterPhone ?? this.reporterPhone,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      imageUrl: imageUrl ?? this.imageUrl,
      beforeImageUrl: beforeImageUrl ?? this.beforeImageUrl,
      afterImageUrl: afterImageUrl ?? this.afterImageUrl,
      status: status ?? this.status,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      acceptedByCommunityUser: acceptedByCommunityUser ?? this.acceptedByCommunityUser,
      communityUserName: communityUserName ?? this.communityUserName,
      completionNotes: completionNotes ?? this.completionNotes,
      state: state ?? this.state,
      district: district ?? this.district,
      city: city ?? this.city,
      repairTeamId: repairTeamId ?? this.repairTeamId,
      repairTeamName: repairTeamName ?? this.repairTeamName,
      assignedToRepairTeamAt: assignedToRepairTeamAt ?? this.assignedToRepairTeamAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt ?? DateTime.now(),
      updates: updates != null ? deduplicateUpdates(updates) : this.updates,
      feedback: clearFeedback ? null : (feedback ?? this.feedback),
      allFeedbacks: allFeedbacks ?? this.allFeedbacks,
      realVotes: realVotes ?? this.realVotes,
      fakeVotes: fakeVotes ?? this.fakeVotes,
      votedUserIds: votedUserIds ?? this.votedUserIds,
      userVotes: userVotes ?? this.userVotes,
    );
  }
}

class ProgressUpdate {
  final String? id; // Database UUID primary key in public.progress_updates (if available)
  final String updateId; // Human or text identifier (e.g. UPD-179187617668...)
  final String complaintId;
  final String communityUserId;
  final String communityUserName;
  final String progressNote;
  final String? imageUrl;
  final double workPercentage;
  final String status;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final String? address;
  final DateTime? capturedAt;

  ProgressUpdate({
    this.id,
    required this.updateId,
    required this.complaintId,
    required this.communityUserId,
    required this.communityUserName,
    required this.progressNote,
    this.imageUrl,
    this.workPercentage = 0.0,
    required this.status,
    DateTime? createdAt,
    this.latitude,
    this.longitude,
    this.address,
    DateTime? capturedAt,
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc(),
       capturedAt = capturedAt?.toUtc();

  factory ProgressUpdate.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString().trim();
    final rawUpdateId = json['update_id']?.toString().trim();

    // Check if rawId is a valid UUID
    final String? dbId = (rawId != null && rawId.isNotEmpty && Complaint.isUuid(rawId))
        ? rawId
        : null;

    // Resolve text updateId: prefer update_id, fallback to rawId
    String textUpdateId = '';
    if (rawUpdateId != null && rawUpdateId.isNotEmpty) {
      textUpdateId = rawUpdateId;
    } else if (rawId != null && rawId.isNotEmpty) {
      textUpdateId = rawId;
    }

    double? lat = Complaint.parseNullableDouble(json['latitude'] ?? json['lat']);
    double? lng = Complaint.parseNullableDouble(json['longitude'] ?? json['lng'] ?? json['lon']);
    if (lat != null && lng != null && lat.abs() > 90.0 && lng.abs() <= 90.0) {
      final temp = lat;
      lat = lng;
      lng = temp;
    }

    return ProgressUpdate(
      id: dbId,
      updateId: textUpdateId,
      complaintId: json['complaint_id'] ?? '',
      communityUserId: json['community_user_id'] ?? '',
      communityUserName: json['community_user_name'] ?? 'Community Volunteer',
      progressNote: json['progress_note'] ?? '',
      imageUrl: json['image_url'],
      workPercentage: Complaint.parseDouble(json['work_percentage'] ?? json['percentage'], 0.0),
      status: json['status'] ?? 'Work Started',
      createdAt: json['created_at'] != null
          ? (Complaint.parseTimestamptz(json['created_at']) ?? DateTime.now().toUtc())
          : DateTime.now().toUtc(),
      latitude: lat,
      longitude: lng,
      address: json['address']?.toString(),
      capturedAt: json['captured_at'] != null
          ? Complaint.parseTimestamptz(json['captured_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null && id!.isNotEmpty) 'id': id,
      'update_id': updateId,
      'complaint_id': complaintId,
      'community_user_id': communityUserId,
      'community_user_name': communityUserName,
      'progress_note': progressNote,
      'image_url': imageUrl,
      'work_percentage': workPercentage,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'captured_at': capturedAt?.toUtc().toIso8601String(),
    };
  }

  ProgressUpdate copyWith({
    String? id,
    String? updateId,
    String? complaintId,
    String? communityUserId,
    String? communityUserName,
    String? progressNote,
    String? imageUrl,
    double? workPercentage,
    String? status,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? capturedAt,
  }) {
    return ProgressUpdate(
      id: id ?? this.id,
      updateId: updateId ?? this.updateId,
      complaintId: complaintId ?? this.complaintId,
      communityUserId: communityUserId ?? this.communityUserId,
      communityUserName: communityUserName ?? this.communityUserName,
      progressNote: progressNote ?? this.progressNote,
      imageUrl: imageUrl ?? this.imageUrl,
      workPercentage: workPercentage ?? this.workPercentage,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}

class FeedbackModel {
  final String feedbackId;
  final String complaintId;
  final String reporterId;
  final String? reporterName;
  final double rating; // 1.0 to 5.0
  final String comments;
  final DateTime createdAt;
  final DateTime? updatedAt;

  FeedbackModel({
    required this.feedbackId,
    required this.complaintId,
    required this.reporterId,
    this.reporterName,
    required this.rating,
    required this.comments,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory FeedbackModel.fromJson(Map<String, dynamic> json) {
    return FeedbackModel(
      feedbackId: json['feedback_id'] ?? json['id'] ?? '',
      complaintId: json['complaint_id'] ?? '',
      reporterId: json['reporter_id'] ?? '',
      reporterName: json['reporter_name'],
      rating: Complaint.parseDouble(json['rating'], 0.0),
      comments: json['comments'] ?? '',
      createdAt: json['created_at'] != null
          ? Complaint.parseTimestamptz(json['created_at']) ?? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? Complaint.parseTimestamptz(json['updated_at']) ?? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'feedback_id': feedbackId,
      'complaint_id': complaintId,
      'reporter_id': reporterId,
      'reporter_name': reporterName,
      'rating': rating,
      'comments': comments,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  FeedbackModel copyWith({
    String? feedbackId,
    String? complaintId,
    String? reporterId,
    String? reporterName,
    double? rating,
    String? comments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FeedbackModel(
      feedbackId: feedbackId ?? this.feedbackId,
      complaintId: complaintId ?? this.complaintId,
      reporterId: reporterId ?? this.reporterId,
      reporterName: reporterName ?? this.reporterName,
      rating: rating ?? this.rating,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
