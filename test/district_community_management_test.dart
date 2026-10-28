import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadwatch/models/complaint_model.dart';
import 'package:roadwatch/models/india_districts.dart';
import 'package:roadwatch/models/repair_team_model.dart';
import 'package:roadwatch/models/user_model.dart';
import 'package:roadwatch/providers/auth_provider.dart';
import 'package:roadwatch/providers/complaint_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('District-Wise Community Management System Tests', () {
    test('1. IndiaDistricts catalog detects districts from locality and addresses accurately', () {
      expect(IndiaDistricts.states.contains('Tamil Nadu'), isTrue);
      expect(IndiaDistricts.getDistricts('Tamil Nadu').contains('Kanchipuram'), isTrue);
      expect(IndiaDistricts.getDistricts('Tamil Nadu').contains('Chennai'), isTrue);

      // Sriperumbudur -> Kanchipuram
      final loc1 = IndiaDistricts.detectFromAddress('Near SIPCOT Industrial Park, Sriperumbudur, Tamil Nadu 602105');
      expect(loc1!['district'], equals('Kanchipuram'));
      expect(loc1['state'], equals('Tamil Nadu'));

      // T Nagar -> Chennai
      final loc2 = IndiaDistricts.detectFromAddress('Usman Road, T Nagar, Chennai 600017');
      expect(loc2!['district'], equals('Chennai'));
      expect(loc2['state'], equals('Tamil Nadu'));

      // Whitefield -> Bengaluru Urban, Karnataka
      final loc3 = IndiaDistricts.detectFromAddress('ITPL Main Road, Whitefield, Bengaluru');
      expect(loc3!['district'], equals('Bengaluru Urban'));
      expect(loc3['state'], equals('Karnataka'));
    });

    test('2. Complaint model preserves district, state, city and repair team fields', () {
      final complaint = Complaint(
        complaintId: 'RW-DISTRICT-TEST-001',
        reporterId: 'rep_123',
        reporterName: 'Pujitha Reporter',
        title: 'Deep Crater on Gandhi Road',
        description: 'Dangerous pothole near bus terminal',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 12.8342,
        longitude: 79.7036,
        address: 'Gandhi Road, Kanchipuram, Tamil Nadu 631501',
        imageUrl: 'https://example.com/pothole.jpg',
        status: 'Submitted',
        state: 'Tamil Nadu',
        district: 'Kanchipuram',
        city: 'Kanchipuram',
        repairTeamId: 'rt_kanchi_pothole_01',
        repairTeamName: 'Kanchipuram Quick Pothole Squad',
        assignedToRepairTeamAt: DateTime(2026, 10, 28, 10, 30),
        createdAt: DateTime(2026, 10, 28, 9, 0),
      );

      expect(complaint.districtDisplay, equals('Kanchipuram'));
      expect(complaint.stateDisplay, equals('Tamil Nadu'));
      expect(complaint.isAssignedToRepairTeam, isTrue);
      expect(complaint.repairTeamName, equals('Kanchipuram Quick Pothole Squad'));

      // JSON roundtrip
      final json = complaint.toJson();
      final revived = Complaint.fromJson(json);

      expect(revived.complaintId, equals(complaint.complaintId));
      expect(revived.district, equals('Kanchipuram'));
      expect(revived.state, equals('Tamil Nadu'));
      expect(revived.city, equals('Kanchipuram'));
      expect(revived.repairTeamId, equals('rt_kanchi_pothole_01'));
      expect(revived.repairTeamName, equals('Kanchipuram Quick Pothole Squad'));
    });

    test('3. Community User filtered view isolates assigned district', () {
      final complaintProv = ComplaintProvider();

      // Seed complaints from 3 different districts
      final kanchiComplaint = Complaint(
        complaintId: 'C-KANCHI-01',
        reporterId: 'rep_01',
        reporterName: 'Reporter Kanchi',
        title: 'Road crack in Kanchipuram',
        description: 'Details',
        category: 'Damaged Road',
        severity: 'Medium',
        latitude: 12.834,
        longitude: 79.703,
        address: 'Ennaikara Street, Kanchipuram',
        imageUrl: 'data:image/jpeg;base64,mock',
        status: 'Submitted',
        state: 'Tamil Nadu',
        district: 'Kanchipuram',
        createdAt: DateTime.now(),
      );

      final chennaiComplaint = Complaint(
        complaintId: 'C-CHENNAI-01',
        reporterId: 'rep_02',
        reporterName: 'Reporter Chennai',
        title: 'Cave-in in Chennai',
        description: 'Details',
        category: 'Pothole',
        severity: 'Emergency',
        latitude: 13.082,
        longitude: 80.270,
        address: 'Anna Salai, Chennai',
        imageUrl: 'data:image/jpeg;base64,mock',
        status: 'Submitted',
        state: 'Tamil Nadu',
        district: 'Chennai',
        createdAt: DateTime.now(),
      );

      final coimbatoreComplaint = Complaint(
        complaintId: 'C-CBE-01',
        reporterId: 'rep_03',
        reporterName: 'Reporter CBE',
        title: 'Water logging in Coimbatore',
        description: 'Details',
        category: 'Drainage Issue',
        severity: 'Low',
        latitude: 11.016,
        longitude: 76.955,
        address: 'Avinashi Road, Coimbatore',
        imageUrl: 'data:image/jpeg;base64,mock',
        status: 'Submitted',
        state: 'Tamil Nadu',
        district: 'Coimbatore',
        createdAt: DateTime.now(),
      );

      complaintProv.complaints.clear();
      complaintProv.complaints.addAll([kanchiComplaint, chennaiComplaint, coimbatoreComplaint]);

      // Kanchipuram Community User should only see Kanchipuram complaints
      final kanchiFeed = complaintProv.filteredComplaintsForDistrict('Kanchipuram', 'Tamil Nadu');
      expect(kanchiFeed.length, equals(1));
      expect(kanchiFeed.first.complaintId, equals('C-KANCHI-01'));
      expect(kanchiFeed.first.districtDisplay, equals('Kanchipuram'));

      // Chennai Community User should only see Chennai complaints
      final chennaiFeed = complaintProv.filteredComplaintsForDistrict('Chennai', 'Tamil Nadu');
      expect(chennaiFeed.length, equals(1));
      expect(chennaiFeed.first.complaintId, equals('C-CHENNAI-01'));
      expect(chennaiFeed.first.districtDisplay, equals('Chennai'));

      // India-Level Admin has access to all districts
      complaintProv.setSelectedStateFilter('Tamil Nadu');
      final adminFeed = complaintProv.adminFilteredComplaints;
      expect(adminFeed.length, equals(3));
    });

    test('4. Reporter can track their complaint regardless of which district community user manages it', () {
      final complaintProv = ComplaintProvider();

      final complaintByReporterA = Complaint(
        complaintId: 'C-TRACK-01',
        reporterId: 'user_reporter_alpha',
        reporterName: 'Alpha Citizen',
        title: 'Big pothole',
        description: 'Near junction',
        category: 'Pothole',
        severity: 'Medium',
        latitude: 12.83,
        longitude: 79.70,
        address: 'Kanchipuram',
        imageUrl: 'data:image/jpeg;base64,mock',
        status: 'In Progress',
        state: 'Tamil Nadu',
        district: 'Kanchipuram',
        repairTeamName: 'Kanchi Road Crew Alpha',
        createdAt: DateTime.now(),
      );

      complaintProv.complaints.clear();
      complaintProv.complaints.add(complaintByReporterA);

      // Reporter queries their personal history
      final reporterComplaints = complaintProv.complaints.where((c) => c.reporterId == 'user_reporter_alpha').toList();
      expect(reporterComplaints.length, equals(1));
      expect(reporterComplaints.first.complaintId, equals('C-TRACK-01'));
      expect(reporterComplaints.first.repairTeamName, equals('Kanchi Road Crew Alpha'));
    });

    test('5. Assigning complaint to local repair crew updates state correctly', () async {
      final complaintProv = ComplaintProvider();

      final original = Complaint(
        complaintId: 'C-ASSIGN-01',
        reporterId: 'rep_1',
        reporterName: 'Citizen',
        title: 'Road crater',
        description: 'Needs tarmac',
        category: 'Pothole',
        severity: 'High',
        latitude: 12.83,
        longitude: 79.70,
        address: 'Kanchipuram Road',
        imageUrl: 'mock',
        status: 'Verified',
        state: 'Tamil Nadu',
        district: 'Kanchipuram',
        createdAt: DateTime.now(),
      );

      complaintProv.complaints.clear();
      complaintProv.complaints.add(original);

      final success = await complaintProv.assignComplaintToRepairTeam(
        complaintId: 'C-ASSIGN-01',
        repairTeamId: 'crew_007',
        repairTeamName: 'Kanchipuram Quick Asphalt Crew',
        assignedByUserId: 'comm_lead_01',
      );

      expect(success, isTrue);

      final updated = complaintProv.complaints.firstWhere((c) => c.complaintId == 'C-ASSIGN-01');
      expect(updated.status, equals('Accepted'));
      expect(updated.repairTeamId, equals('crew_007'));
      expect(updated.repairTeamName, equals('Kanchipuram Quick Asphalt Crew'));
      expect(updated.isAssignedToRepairTeam, isTrue);
    });

    test('6. User model distinguishes admin, community, reporter and repair team roles', () {
      final admin = UserModel(
        id: 'admin_1',
        email: 'admin@roadwatch.gov.in',
        name: 'National Admin',
        role: 'admin',
        state: 'All India',
        district: 'All Districts',
      );
      expect(admin.isAdmin, isTrue);
      expect(admin.isReporter, isFalse);
      expect(admin.isCommunity, isFalse);
      expect(admin.isRepairTeam, isFalse);

      final community = UserModel(
        id: 'comm_1',
        email: 'comm.kanchi@example.com',
        name: 'Kanchi Community Volunteer',
        role: 'community',
        state: 'Tamil Nadu',
        district: 'Kanchipuram',
      );
      expect(community.isCommunity, isTrue);
      expect(community.district, equals('Kanchipuram'));
      expect(community.state, equals('Tamil Nadu'));

      final repairCrew = UserModel(
        id: 'repair_1',
        email: 'crew.kanchi@example.com',
        name: 'Lead Foreman Kanchi',
        role: 'repair_team',
        state: 'Tamil Nadu',
        district: 'Kanchipuram',
        repairTeamId: 'team_asphalt_01',
      );
      expect(repairCrew.isRepairTeam, isTrue);
      expect(repairCrew.repairTeamId, equals('team_asphalt_01'));
    });
  });
}
