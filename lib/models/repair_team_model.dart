class RepairTeam {
  final String id;
  final String name;
  final String state;
  final String district;
  final String specialization;
  final String leadName;
  final String contactPhone;
  final String contactEmail;
  final bool isActive;
  final int assignedComplaintsCount;
  final int completedComplaintsCount;
  final DateTime createdAt;

  RepairTeam({
    required this.id,
    required this.name,
    required this.state,
    required this.district,
    this.specialization = 'Pothole Patching & Asphalt Repair',
    this.leadName = '',
    this.contactPhone = '',
    this.contactEmail = '',
    this.isActive = true,
    this.assignedComplaintsCount = 0,
    this.completedComplaintsCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory RepairTeam.fromJson(Map<String, dynamic> json) {
    return RepairTeam(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Local Road Repair Crew',
      state: json['state']?.toString() ?? 'Tamil Nadu',
      district: json['district']?.toString() ?? 'Kanchipuram',
      specialization: json['specialization']?.toString() ?? 'Pothole Patching & Asphalt Repair',
      leadName: json['lead_name']?.toString() ?? json['contact_person']?.toString() ?? '',
      contactPhone: json['contact_phone']?.toString() ?? json['phone']?.toString() ?? '',
      contactEmail: json['contact_email']?.toString() ?? json['email']?.toString() ?? '',
      isActive: json['is_active'] == null ? true : (json['is_active'] == true || json['is_active'].toString() == 'true'),
      assignedComplaintsCount: int.tryParse(json['assigned_complaints_count']?.toString() ?? '0') ?? 0,
      completedComplaintsCount: int.tryParse(json['completed_complaints_count']?.toString() ?? '0') ?? 0,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'state': state,
      'district': district,
      'specialization': specialization,
      'lead_name': leadName,
      'contact_phone': contactPhone,
      'contact_email': contactEmail,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  RepairTeam copyWith({
    String? id,
    String? name,
    String? state,
    String? district,
    String? specialization,
    String? leadName,
    String? contactPhone,
    String? contactEmail,
    bool? isActive,
    int? assignedComplaintsCount,
    int? completedComplaintsCount,
  }) {
    return RepairTeam(
      id: id ?? this.id,
      name: name ?? this.name,
      state: state ?? this.state,
      district: district ?? this.district,
      specialization: specialization ?? this.specialization,
      leadName: leadName ?? this.leadName,
      contactPhone: contactPhone ?? this.contactPhone,
      contactEmail: contactEmail ?? this.contactEmail,
      isActive: isActive ?? this.isActive,
      assignedComplaintsCount: assignedComplaintsCount ?? this.assignedComplaintsCount,
      completedComplaintsCount: completedComplaintsCount ?? this.completedComplaintsCount,
      createdAt: createdAt,
    );
  }
}

