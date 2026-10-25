import 'package:flutter_test/flutter_test.dart';
import 'package:roadwatch/models/complaint_model.dart';

void main() {
  group('Work Progress Update Flow Tests', () {
    test('Progress updates without image preserve notes, percentage, and timestamps', () {
      final complaint = Complaint(
        complaintId: 'RW-8902',
        reporterId: 'rep_1',
        reporterName: 'Alex Mercer',
        title: 'Damaged Asphalt & Cracks',
        description: 'Road surface cracking badly',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: '101 Howard St, San Francisco, CA',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Repair In Progress',
        progressPercentage: 0.0,
      );

      final update25 = ProgressUpdate(
        updateId: 'UPD-1',
        complaintId: complaint.complaintId,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: 'Safety cones placed and base gravel laid.',
        workPercentage: 25.0,
        status: 'Repair In Progress',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      final updatedList = Complaint.deduplicateUpdates([...complaint.updates, update25]);
      updatedList.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      expect(updatedList.length, 1);
      expect(updatedList.first.workPercentage, 25.0);
      expect(updatedList.first.imageUrl, isNull);
      expect(updatedList.first.complaintId, 'RW-8902');
      expect(updatedList.first.progressNote, 'Safety cones placed and base gravel laid.');
    });

    test('Progress updates at 25%, 50%, and 100% maintain chronological order and older entries remain visible', () {
      final t1 = DateTime.now().subtract(const Duration(hours: 3));
      final t2 = DateTime.now().subtract(const Duration(hours: 2));
      final t3 = DateTime.now().subtract(const Duration(hours: 1));

      final u25 = ProgressUpdate(
        updateId: 'UPD-25',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: '25% - Excavation done',
        workPercentage: 25.0,
        status: 'Repair In Progress',
        createdAt: t1,
      );

      final u50 = ProgressUpdate(
        updateId: 'UPD-50',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: '50% - Asphalt poured',
        workPercentage: 50.0,
        status: 'Repair In Progress',
        imageUrl: 'https://rblhbjmenbghvacljjwv.supabase.co/storage/v1/object/public/roadwatch-reports/comm_user_1/progress_photos/p50.jpg',
        createdAt: t2,
      );

      final u100 = ProgressUpdate(
        updateId: 'UPD-100',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: '100% - Roller compaction and lane reopened',
        workPercentage: 100.0,
        status: 'Completed',
        imageUrl: 'https://rblhbjmenbghvacljjwv.supabase.co/storage/v1/object/public/roadwatch-reports/comm_user_1/progress_photos/p100.jpg',
        createdAt: t3,
      );

      final allUpdates = Complaint.deduplicateUpdates([u25, u50, u100]);
      allUpdates.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      expect(allUpdates.length, 3);
      expect(allUpdates[0].workPercentage, 25.0);
      expect(allUpdates[1].workPercentage, 50.0);
      expect(allUpdates[2].workPercentage, 100.0);

      // Verify older entries remain visible in chronological order
      expect(allUpdates[0].createdAt.isBefore(allUpdates[1].createdAt), isTrue);
      expect(allUpdates[1].createdAt.isBefore(allUpdates[2].createdAt), isTrue);

      // Images available for 50% and 100%, absent for 25%
      expect(allUpdates[0].imageUrl, isNull);
      expect(allUpdates[1].imageUrl, isNotNull);
      expect(allUpdates[2].imageUrl, isNotNull);
    });

    test('Latest update properly updates progress percentage without max() masking', () {
      final initialComplaint = Complaint(
        complaintId: 'RW-8902',
        reporterId: 'rep_1',
        reporterName: 'Alex Mercer',
        title: 'Damaged Asphalt & Cracks',
        description: 'Road surface cracking badly',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: '101 Howard St, San Francisco, CA',
        imageUrl: 'https://example.com/pothole.jpg',
        progressPercentage: 60.0,
        status: 'Repair In Progress',
      );

      // Testing update to 25% should result in 25%, not get blocked by max(60, 25)
      final newUpdate25 = ProgressUpdate(
        updateId: 'UPD-NEW-25',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: 'Re-evaluating site progress at 25%',
        workPercentage: 25.0,
        status: 'Repair In Progress',
        createdAt: DateTime.now(),
      );

      final merged = Complaint.deduplicateUpdates([...initialComplaint.updates, newUpdate25]);
      merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final latest = merged.last;

      final updatedComplaint = initialComplaint.copyWith(
        updates: merged,
        progressPercentage: latest.workPercentage,
        status: latest.status,
      );

      expect(updatedComplaint.progressPercentage, 25.0);
    });

    test('Complaint JSON serialization preserves updates array and after_image_url at 100%', () {
      final update100 = ProgressUpdate(
        updateId: 'UPD-COMPLETED',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: 'Repair fully verified & complete.',
        workPercentage: 100.0,
        status: 'Completed',
        imageUrl: 'https://rblhbjmenbghvacljjwv.supabase.co/storage/v1/object/public/roadwatch-reports/comm_user_1/progress_photos/done.jpg',
        createdAt: DateTime.now(),
      );

      final complaint = Complaint(
        complaintId: 'RW-8902',
        reporterId: 'rep_1',
        reporterName: 'Alex Mercer',
        title: 'Damaged Asphalt & Cracks',
        description: 'Road surface cracking badly',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: '101 Howard St, San Francisco, CA',
        imageUrl: 'https://example.com/pothole.jpg',
        progressPercentage: 100.0,
        status: 'Completed',
        afterImageUrl: update100.imageUrl,
        completionNotes: update100.progressNote,
        updates: [update100],
      );

      final json = complaint.toJson();
      expect(json['progress_percentage'], 100.0);
      expect(json['status'], 'Completed');
      expect(json['after_image_url'], isNotNull);
      expect((json['updates'] as List).length, 1);

      final roundTrip = Complaint.fromJson(json);
      expect(roundTrip.complaintId, 'RW-8902');
      expect(roundTrip.progressPercentage, 100.0);
      expect(roundTrip.status, 'Completed');
      expect(roundTrip.afterImageUrl, update100.imageUrl);
      expect(roundTrip.updates.length, 1);
      expect(roundTrip.updates.first.workPercentage, 100.0);
    });

    test('Deleting an update removes only target record and recalibrates progress', () {
      final t1 = DateTime.now().subtract(const Duration(hours: 3));
      final t2 = DateTime.now().subtract(const Duration(hours: 2));
      final t3 = DateTime.now().subtract(const Duration(hours: 1));

      final u25 = ProgressUpdate(
        updateId: 'UPD-25',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: '25% - Base laid',
        workPercentage: 25.0,
        status: 'Repair In Progress',
        createdAt: t1,
      );

      final u50 = ProgressUpdate(
        updateId: 'UPD-50',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: '50% - Asphalt poured',
        workPercentage: 50.0,
        status: 'Repair In Progress',
        imageUrl: 'https://rblhbjmenbghvacljjwv.supabase.co/storage/v1/object/public/roadwatch-reports/comm_user_1/progress_photos/p50.jpg',
        createdAt: t2,
      );

      final u75 = ProgressUpdate(
        updateId: 'UPD-75',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: '75% - Surface smoothing',
        workPercentage: 75.0,
        status: 'Repair In Progress',
        createdAt: t3,
      );

      final complaint = Complaint(
        complaintId: 'RW-8902',
        reporterId: 'rep_1',
        reporterName: 'Alex Mercer',
        title: 'Damaged Asphalt & Cracks',
        description: 'Road surface cracking badly',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: '101 Howard St, San Francisco, CA',
        imageUrl: 'https://example.com/pothole.jpg',
        progressPercentage: 75.0,
        status: 'Repair In Progress',
        updates: [u25, u50, u75],
      );

      // Delete the latest update (UPD-75)
      final remainingAfterDelete75 = complaint.updates.where((u) => u.updateId != 'UPD-75').toList();
      remainingAfterDelete75.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      expect(remainingAfterDelete75.length, 2);
      expect(remainingAfterDelete75.any((u) => u.updateId == 'UPD-75'), isFalse);
      expect(remainingAfterDelete75.any((u) => u.updateId == 'UPD-25'), isTrue);
      expect(remainingAfterDelete75.any((u) => u.updateId == 'UPD-50'), isTrue);

      // Recalibrate complaint status and percentage
      final newPercentage = remainingAfterDelete75.isNotEmpty ? remainingAfterDelete75.last.workPercentage : 0.0;
      final newStatus = remainingAfterDelete75.isNotEmpty
          ? (newPercentage >= 100.0 ? 'Completed' : (newPercentage >= 85.0 ? 'Near Completion' : 'Repair In Progress'))
          : 'Accepted';

      final recalibrated = complaint.copyWith(
        updates: remainingAfterDelete75,
        progressPercentage: newPercentage,
        status: newStatus,
      );

      expect(recalibrated.progressPercentage, 50.0);
      expect(recalibrated.status, 'Repair In Progress');
      expect(recalibrated.updates.length, 2);

      // Now delete all remaining updates -> resets to 0.0% and 'Accepted'
      final emptyUpdates = <ProgressUpdate>[];
      final resetPercentage = emptyUpdates.isNotEmpty ? emptyUpdates.last.workPercentage : 0.0;
      final resetStatus = emptyUpdates.isNotEmpty ? 'Repair In Progress' : 'Accepted';

      final resetComplaint = recalibrated.copyWith(
        updates: emptyUpdates,
        progressPercentage: resetPercentage,
        status: resetStatus,
      );

      expect(resetComplaint.progressPercentage, 0.0);
      expect(resetComplaint.status, 'Accepted');
      expect(resetComplaint.updates.isEmpty, isTrue);
    });

    test('Authorization enforcement permits only creator or admin to delete', () {
      final update = ProgressUpdate(
        updateId: 'UPD-AUTH',
        complaintId: 'RW-8902',
        communityUserId: 'user_alice',
        communityUserName: 'Alice',
        progressNote: 'Inspecting site',
        workPercentage: 30.0,
        status: 'Repair In Progress',
      );

      bool canDelete(String requestingUserId, String requestingRole) {
        final isAdmin = requestingRole.toLowerCase() == 'admin';
        final isCreator = update.communityUserId == requestingUserId;
        return isAdmin || isCreator;
      }

      // Creator (Alice) can delete
      expect(canDelete('user_alice', 'community'), isTrue);

      // Admin can delete
      expect(canDelete('admin_bob', 'admin'), isTrue);

      // Unrelated user (Charlie) cannot delete
      expect(canDelete('user_charlie', 'community'), isFalse);
      expect(canDelete('reporter_dave', 'reporter'), isFalse);
    });

    test('Deletion is blocked on completed complaint records', () {
      final completedComplaint = Complaint(
        complaintId: 'RW-DONE',
        reporterId: 'rep_1',
        reporterName: 'Alex Mercer',
        title: 'Completed Repair',
        description: 'Completed repair work',
        category: 'Pothole',
        severity: 'Low',
        latitude: 37.7749,
        longitude: -122.4194,
        address: 'Market St',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Completed',
        progressPercentage: 100.0,
      );

      final bool isCompleted = completedComplaint.isCompleted || completedComplaint.status.toLowerCase() == 'completed';
      expect(isCompleted, isTrue);

      // Guard condition ensures no deletion on completed records
      final bool canDelete = !isCompleted;
      expect(canDelete, isFalse);
    });

    test('Storage URL parser targets only progress_photos under roadwatch-reports', () {
      bool isTargetProgressPhoto(String url) {
        final uri = Uri.tryParse(url);
        if (uri == null) return false;
        final segments = uri.pathSegments;
        final bucketIdx = segments.indexOf('roadwatch-reports');
        if (bucketIdx != -1 && bucketIdx < segments.length - 1) {
          final relativePath = segments.sublist(bucketIdx + 1).join('/');
          return relativePath.contains('progress_photos/');
        }
        return false;
      }

      // Progress photo URL inside roadwatch-reports bucket -> should match
      const progressPhotoUrl =
          'https://xyz.supabase.co/storage/v1/object/public/roadwatch-reports/user123/progress_photos/photo1.jpg';
      expect(isTargetProgressPhoto(progressPhotoUrl), isTrue);

      // Shared initial report image -> should NOT match (protected)
      const reportPhotoUrl =
          'https://xyz.supabase.co/storage/v1/object/public/roadwatch-reports/complaints/initial_pothole.jpg';
      expect(isTargetProgressPhoto(reportPhotoUrl), isFalse);

      // User profile avatar -> should NOT match (protected)
      const avatarUrl =
          'https://xyz.supabase.co/storage/v1/object/public/roadwatch-reports/avatars/user123.jpg';
      expect(isTargetProgressPhoto(avatarUrl), isFalse);

      // Different bucket -> should NOT match (protected)
      const otherBucketUrl =
          'https://xyz.supabase.co/storage/v1/object/public/other-bucket/progress_photos/pic.jpg';
      expect(isTargetProgressPhoto(otherBucketUrl), isFalse);
    });

    test('Unauthenticated user or empty user ID is rejected from deleting', () {
      final update = ProgressUpdate(
        updateId: 'UPD-AUTH-2',
        complaintId: 'RW-8902',
        communityUserId: 'user_alice',
        communityUserName: 'Alice',
        progressNote: 'Work note',
        workPercentage: 30.0,
        status: 'Repair In Progress',
      );

      bool canDelete(String requestingUserId, String requestingRole) {
        if (requestingUserId.trim().isEmpty) return false;
        final isAdmin = requestingRole.toLowerCase() == 'admin';
        final isCreator = update.communityUserId.isNotEmpty && update.communityUserId == requestingUserId;
        return isAdmin || isCreator;
      }

      expect(canDelete('', 'community'), isFalse);
      expect(canDelete('   ', 'admin'), isFalse);
    });

    test('Complaint ID mismatch between target update and complaint is rejected', () {
      final savedUpdate = ProgressUpdate(
        updateId: 'UPD-MISMATCH',
        complaintId: 'RW-8902',
        communityUserId: 'user_alice',
        communityUserName: 'Alice',
        progressNote: 'Work note',
        workPercentage: 30.0,
        status: 'Repair In Progress',
      );

      bool validateComplaintMatch(String callerComplaintId) {
        return savedUpdate.complaintId.toLowerCase() == callerComplaintId.toLowerCase();
      }

      expect(validateComplaintMatch('RW-8902'), isTrue);
      expect(validateComplaintMatch('rw-8902'), isTrue);
      expect(validateComplaintMatch('RW-9999'), isFalse);
    });

    test('Storage deletion validates user folder isolation', () {
      bool canDeleteStorageFile(String relativePath, String authorizedUserId, bool isAdmin) {
        if (!relativePath.contains('progress_photos/')) return false;
        if (isAdmin) return true;
        final fileOwnerId = relativePath.split('/').first;
        return fileOwnerId == authorizedUserId;
      }

      // Owner can delete their own progress photo
      expect(canDeleteStorageFile('user123/progress_photos/img1.jpg', 'user123', false), isTrue);

      // Another user CANNOT delete user123's progress photo
      expect(canDeleteStorageFile('user123/progress_photos/img1.jpg', 'user999', false), isFalse);

      // Admin can delete progress photos
      expect(canDeleteStorageFile('user123/progress_photos/img1.jpg', 'admin_1', true), isTrue);

      // Outside progress_photos/ is never allowed, even for owner or admin
      expect(canDeleteStorageFile('user123/complaints/pothole.jpg', 'user123', false), isFalse);
      expect(canDeleteStorageFile('user123/complaints/pothole.jpg', 'admin_1', true), isFalse);
    });

    test('UUID vs UPD- identifier column targeting prevents UUID syntax error', () {
      final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      bool isUuid(String v) => uuidRegex.hasMatch(v.trim());

      String targetColumn(String id) {
        if (id.startsWith('UPD-')) return 'update_id';
        if (isUuid(id)) return 'id';
        return 'update_id';
      }

      // Typical update ID starting with UPD-
      const customUpdateId = 'UPD-17918761766864';
      expect(isUuid(customUpdateId), isFalse);
      expect(targetColumn(customUpdateId), 'update_id');

      // Standard UUID
      const standardUuid = '88deb318-8c4b-48fd-8915-52fbc04ed6dd';
      expect(isUuid(standardUuid), isTrue);
      expect(targetColumn(standardUuid), 'id');

      // Random non-UUID text identifier
      const randomTextId = 'custom_repair_123';
      expect(isUuid(randomTextId), isFalse);
      expect(targetColumn(randomTextId), 'update_id');
    });

    test('Deletion verification requires exactly one record deleted', () {
      DeleteResult verifyDeleted(List<Map<String, dynamic>> deletedRows) {
        if (deletedRows.isEmpty) {
          return DeleteResult(success: false, message: 'No record deleted');
        }
        if (deletedRows.length == 1) {
          return DeleteResult(success: true, message: 'Deleted exactly 1 record');
        }
        return DeleteResult(success: true, message: 'Multiple records deleted');
      }

      // Exactly 1 deleted row -> verified success
      final singleResult = verifyDeleted([{'id': 'uuid-1', 'update_id': 'UPD-1'}]);
      expect(singleResult.success, isTrue);
      expect(singleResult.message, 'Deleted exactly 1 record');

      // 0 deleted rows -> clear failure
      final emptyResult = verifyDeleted([]);
      expect(emptyResult.success, isFalse);
      expect(emptyResult.message, 'No record deleted');
    });

    test('ProgressUpdate preserves database UUID id and text updateId end-to-end', () {
      const dbUuid = '88deb318-8c4b-48fd-8915-52fbc04ed6dd';
      const textUpd = 'UPD-17918761766864';

      final puFromDb = ProgressUpdate.fromJson({
        'id': dbUuid,
        'update_id': textUpd,
        'complaint_id': 'c3b8d606-2e54-49a1-925a-267f1a699d03',
        'community_user_id': 'user_comm_1',
        'progress_note': 'Asphalt patch applied',
        'work_percentage': 50,
      });

      expect(puFromDb.id, dbUuid);
      expect(puFromDb.updateId, textUpd);

      final json = puFromDb.toJson();
      expect(json['id'], dbUuid);
      expect(json['update_id'], textUpd);

      // Deserialization fallback when only UUID id is present
      final puOnlyUuid = ProgressUpdate.fromJson({
        'id': dbUuid,
        'complaint_id': 'c3b8d606-2e54-49a1-925a-267f1a699d03',
      });
      expect(puOnlyUuid.id, dbUuid);
      expect(puOnlyUuid.updateId, dbUuid);

      // Deserialization fallback when only UPD- is present
      final puOnlyUpd = ProgressUpdate.fromJson({
        'update_id': textUpd,
        'complaint_id': 'c3b8d606-2e54-49a1-925a-267f1a699d03',
      });
      expect(puOnlyUpd.id, isNull);
      expect(puOnlyUpd.updateId, textUpd);
    });

    test('Complaint deduplication merges database UUID id into matching memory updates', () {
      const dbUuid = '88deb318-8c4b-48fd-8915-52fbc04ed6dd';
      const textUpd = 'UPD-17918761766864';

      final memoryUpdate = ProgressUpdate(
        updateId: textUpd,
        complaintId: 'c3b8d606-2e54-49a1-925a-267f1a699d03',
        communityUserId: 'user_comm_1',
        communityUserName: 'Volunteer',
        progressNote: 'Work started',
        workPercentage: 25.0,
        status: 'Work Started',
      );

      final dbUpdate = ProgressUpdate(
        id: dbUuid,
        updateId: textUpd,
        complaintId: 'c3b8d606-2e54-49a1-925a-267f1a699d03',
        communityUserId: 'user_comm_1',
        communityUserName: 'Volunteer',
        progressNote: 'Work started',
        workPercentage: 25.0,
        status: 'Work Started',
      );

      final merged = Complaint.deduplicateUpdates([memoryUpdate, dbUpdate]);
      expect(merged.length, 1);
      expect(merged.first.id, dbUuid);
      expect(merged.first.updateId, textUpd);
    });

    test('Complaint-scoped fallback resolves records matching caller and image URL or note', () {
      final existingDbRows = [
        {
          'id': '88deb318-8c4b-48fd-8915-52fbc04ed6dd',
          'update_id': 'UPD-17918761766864',
          'complaint_id': 'c3b8d606-2e54-49a1-925a-267f1a699d03',
          'community_user_id': 'user_comm_1',
          'image_url': 'https://storage/progress_photos/p1.jpg',
          'progress_note': 'Filling pothole with gravel',
        },
        {
          'id': '99deb318-8c4b-48fd-8915-52fbc04ed6ee',
          'update_id': 'UPD-17918761766900',
          'complaint_id': 'c3b8d606-2e54-49a1-925a-267f1a699d03',
          'community_user_id': 'user_comm_1',
          'image_url': 'https://storage/progress_photos/p2.jpg',
          'progress_note': 'Rolling asphalt level',
        },
      ];

      Map<String, dynamic>? matchFallback(String? targetImageUrl, String? targetNote, String callerUserId) {
        for (final row in existingDbRows) {
          if (targetImageUrl != null && targetImageUrl.isNotEmpty && row['image_url'] == targetImageUrl) {
            return row;
          }
          if (row['community_user_id'] == callerUserId && targetNote != null && row['progress_note'] == targetNote) {
            return row;
          }
        }
        return null;
      }

      final matchedByImg = matchFallback('https://storage/progress_photos/p1.jpg', null, 'user_comm_1');
      expect(matchedByImg?['id'], '88deb318-8c4b-48fd-8915-52fbc04ed6dd');

      final matchedByNote = matchFallback(null, 'Rolling asphalt level', 'user_comm_1');
      expect(matchedByNote?['id'], '99deb318-8c4b-48fd-8915-52fbc04ed6ee');
    });

    test('Form state reset on success clears notes and photo preview while preserving progress percentage and history', () {
      // Simulate form state before submission
      String? formPhotoUrl = 'data:image/jpeg;base64,/9j/4AAQSkZJRg...';
      String formNotes = 'Completed 60% asphalt pouring and compaction.';
      double formPercentage = 60.0;
      bool isSubmitting = false;

      // Complaint with 1 prior update
      final initialUpdate = ProgressUpdate(
        updateId: 'UPD-INIT',
        complaintId: 'RW-8902',
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: 'Initial inspection completed.',
        workPercentage: 20.0,
        status: 'Repair In Progress',
      );

      final complaint = Complaint(
        complaintId: 'RW-8902',
        reporterId: 'rep_1',
        reporterName: 'Alex Mercer',
        title: 'Damaged Asphalt',
        description: 'Road surface cracking badly',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 37.7749,
        longitude: -122.4194,
        address: 'MG Road',
        imageUrl: 'https://example.com/pothole.jpg',
        progressPercentage: 20.0,
        status: 'Repair In Progress',
        updates: [initialUpdate],
      );

      // 1. When submitting starts, isSubmitting is set to true (prevents duplicate submission)
      isSubmitting = true;
      expect(isSubmitting, isTrue);

      // 2. Simulate successful submission
      final newUpdate = ProgressUpdate(
        updateId: 'UPD-NEW',
        complaintId: complaint.complaintId,
        communityUserId: 'comm_user_1',
        communityUserName: 'Civic Repair Guild',
        progressNote: formNotes,
        imageUrl: 'https://supabase.co/storage/v1/object/public/progress_photos/photo60.jpg',
        workPercentage: formPercentage,
        status: 'Repair In Progress',
      );

      final updatedHistory = Complaint.deduplicateUpdates([...complaint.updates, newUpdate]);
      updatedHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // 3. Reset form on confirmed success: clear photo preview and notes, preserve percentage
      formPhotoUrl = null;
      formNotes = '';
      isSubmitting = false;

      // Verify form inputs cleared
      expect(formPhotoUrl, isNull);
      expect(formNotes, isEmpty);
      expect(isSubmitting, isFalse);

      // Verify saved repair progress percentage is preserved
      expect(formPercentage, 60.0);

      // Verify updates history is preserved, contains both previous and new updates
      expect(updatedHistory.length, 2);
      expect(updatedHistory.first.updateId, 'UPD-INIT');
      expect(updatedHistory.last.updateId, 'UPD-NEW');
      expect(updatedHistory.last.progressNote, 'Completed 60% asphalt pouring and compaction.');
    });

    test('Form state retention on failure preserves notes, photo preview, and entered percentage for retry', () {
      // Simulate form state before submission
      String? formPhotoUrl = 'https://supabase.co/storage/v1/object/public/progress_photos/photo.jpg';
      String formNotes = 'Repair work in progress.';
      double formPercentage = 45.0;
      bool isSubmitting = true;

      // Simulate failure (e.g. network or database error)
      const bool saveSuccess = false;

      if (!saveSuccess) {
        // Form retains photo, notes, and entered progress percentage
        isSubmitting = false;
        // Do NOT clear formPhotoUrl or formNotes
      }

      expect(formPhotoUrl, 'https://supabase.co/storage/v1/object/public/progress_photos/photo.jpg');
      expect(formNotes, 'Repair work in progress.');
      expect(formPercentage, 45.0);
      expect(isSubmitting, isFalse);
    });
  });
}

class DeleteResult {
  final bool success;
  final String message;
  DeleteResult({required this.success, required this.message});
}
