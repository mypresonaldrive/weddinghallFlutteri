/// Data models: lightweight record wrappers over the API's JSON maps plus
/// typed value objects for session/config state.
library models;

class RecordItem {
  RecordItem(this.kind, this.data);

  final String kind;
  final Map<String, dynamic> data;

  String get id => (data['id'] ?? '').toString();

  RecordItem copy() => RecordItem(kind, Map<String, dynamic>.from(data));

  Map<String, dynamic> payload() {
    final body = Map<String, dynamic>.from(data);
    body.remove('id');
    return body;
  }

  String str(String key, [String fallback = '']) =>
      data[key] == null ? fallback : data[key].toString();

  String? strOrNull(String key) => data[key] == null ? null : data[key].toString();

  num numOf(String key, [num fallback = 0]) {
    final value = data[key];
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? fallback;
    return fallback;
  }

  num? numOfOrNull(String key) {
    final value = data[key];
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  List<dynamic> listOf(String key) =>
      data[key] is List ? data[key] as List<dynamic> : <dynamic>[];

  bool get isEmptyRecord => id.isEmpty;
}

RecordItem recordFromJson(String kind, Map<String, dynamic> json) =>
    RecordItem(kind, json);

class CurrentUser {
  CurrentUser({
    required this.id,
    required this.name,
    required this.email,
    this.role,
    this.tenant = '',
    this.tenantId,
    this.platformAdmin = false,
    this.mfaRequired = false,
    this.membershipStatus,
    this.needsOnboarding = false,
    this.production = false,
    this.organization,
    this.entitlement,
  });

  final String id;
  final String name;
  final String email;
  final String? role;
  final String tenant;
  final String? tenantId;
  final bool platformAdmin;
  final bool mfaRequired;
  final String? membershipStatus;
  final bool needsOnboarding;
  final bool production;
  final Map<String, dynamic>? organization;
  final Map<String, dynamic>? entitlement;

  bool get isOwner => role == 'owner';
  bool get isStaff => role == 'staff';
  bool get isClient => role == 'client';
  bool get inWorkspace => role != null;
  bool get entitlementActive => entitlement == null || entitlement!['active'] == true;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  static CurrentUser fromJson(Map<String, dynamic> json) => CurrentUser(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String?,
        tenant: json['tenant'] as String? ?? '',
        tenantId: json['tenantId'] as String?,
        platformAdmin: json['platformAdmin'] == true,
        mfaRequired: json['mfaRequired'] == true,
        membershipStatus: json['membershipStatus'] as String?,
        needsOnboarding: json['needsOnboarding'] == true,
        production: json['production'] == true,
        organization:
            json['organization'] is Map ? Map<String, dynamic>.from(json['organization'] as Map) : null,
        entitlement: json['entitlement'] is Map
            ? Map<String, dynamic>.from(json['entitlement'] as Map)
            : null,
      );
}

class AppConfig {
  AppConfig({
    required this.mode,
    this.billingEnabled = false,
    this.billingMode = 'test',
    this.registrationEnabled = true,
    this.supportEmail = '',
    this.captchaSiteKey = '',
  });

  final String mode;
  final bool billingEnabled;
  final String billingMode;
  final bool registrationEnabled;
  final String supportEmail;
  final String captchaSiteKey;

  bool get isSaas => mode == 'saas';

  static AppConfig fromJson(Map<String, dynamic> json) => AppConfig(
        mode: json['mode'] as String? ?? 'demo',
        billingEnabled: json['billingEnabled'] == true,
        billingMode: json['billingMode'] as String? ?? 'test',
        registrationEnabled: json['registrationEnabled'] != false,
        supportEmail: json['supportEmail'] as String? ?? '',
        captchaSiteKey: json['captchaSiteKey'] as String? ?? '',
      );
}

class AvailabilityHall {
  AvailabilityHall({required this.id, required this.available, required this.reason});
  final String id;
  final bool available;
  final String reason;

  static AvailabilityHall fromJson(Map<String, dynamic> json) => AvailabilityHall(
        id: json['id'] as String? ?? '',
        available: json['available'] == true,
        reason: json['reason'] as String? ?? '',
      );
}

class AvailabilityResult {
  AvailabilityResult({required this.date, required this.halls, this.duration});
  final String date;
  final List<AvailabilityHall> halls;
  final Map<String, dynamic>? duration;

  static AvailabilityResult fromJson(Map<String, dynamic> json) => AvailabilityResult(
        date: json['date'] as String? ?? '',
        duration: json['duration'] is Map
            ? Map<String, dynamic>.from(json['duration'] as Map)
            : null,
        halls: (json['halls'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(AvailabilityHall.fromJson)
            .toList(),
      );
}

/// Role-based permission checks mirroring the API rules.
class Perms {
  static bool canManage(String? role, String kind) {
    if (role == 'owner') return true;
    if (role == 'staff') {
      return kind == 'bookings' || kind == 'clients' || kind == 'payments';
    }
    return false;
  }

  static bool canCreate(String? role, String kind) => canManage(role, kind);

  static bool canDelete(String? role, String kind) => canManage(role, kind);

  static bool canViewCatalog(String? role) => role != null && role != 'client';

  static bool canBook(String? role) =>
      role == 'owner' || role == 'staff' || role == 'client';
}

double paidFor(List<RecordItem> payments, String bookingId) => payments
    .where((p) => p.str('bookingId') == bookingId)
    .fold<double>(0, (sum, p) => sum + p.numOf('amount').toDouble());

double balanceFor(RecordItem booking, List<RecordItem> payments) =>
    booking.numOf('total').toDouble() - paidFor(payments, booking.id);
