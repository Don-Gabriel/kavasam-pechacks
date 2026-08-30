class DialerStatus {
  const DialerStatus({
    required this.supported,
    required this.isDefault,
    this.screeningSupported = false,
    this.isScreening = false,
    this.contactsGranted = false,
    this.callLogGranted = false,
  });

  const DialerStatus.unavailable()
    : supported = false,
      isDefault = false,
      screeningSupported = false,
      isScreening = false,
      contactsGranted = false,
      callLogGranted = false;

  final bool supported;
  final bool isDefault;
  final bool screeningSupported;
  final bool isScreening;
  final bool contactsGranted;
  final bool callLogGranted;

  bool get protectionReady => isScreening && contactsGranted;
  bool get phoneDataReady => contactsGranted && callLogGranted;

  factory DialerStatus.fromMap(Map<Object?, Object?> value) => DialerStatus(
    supported: value['supported'] == true,
    isDefault: value['isDefault'] == true,
    screeningSupported: value['screeningSupported'] == true,
    isScreening: value['isScreening'] == true,
    contactsGranted: value['contactsGranted'] == true,
    callLogGranted: value['callLogGranted'] == true,
  );
}

class RoleRequestResult {
  const RoleRequestResult({
    required this.supported,
    required this.granted,
    this.message,
  });

  final bool supported;
  final bool granted;
  final String? message;

  factory RoleRequestResult.fromMap(Map<Object?, Object?> value) =>
      RoleRequestResult(
        supported: value['supported'] == true,
        granted: value['granted'] == true,
        message: value['message']?.toString(),
      );
}

class NativeActionResult {
  const NativeActionResult({required this.ok, this.message});

  final bool ok;
  final String? message;

  factory NativeActionResult.fromMap(Map<Object?, Object?> value) =>
      NativeActionResult(
        ok: value['ok'] == true,
        message: value['message']?.toString(),
      );
}

class CallerIdentity {
  const CallerIdentity({
    required this.number,
    required this.displayName,
    required this.category,
    required this.riskScore,
    required this.riskLabel,
    required this.isContact,
    required this.isTrusted,
    required this.isBlocked,
    required this.reports,
    required this.similarity,
    required this.reasons,
  });

  final String number;
  final String displayName;
  final String category;
  final int riskScore;
  final String riskLabel;
  final bool isContact;
  final bool isTrusted;
  final bool isBlocked;
  final int reports;
  final double similarity;
  final List<String> reasons;

  bool get isSpam => riskScore >= 45 || isBlocked;

  factory CallerIdentity.fromMap(Map<Object?, Object?> value) => CallerIdentity(
    number: value['number']?.toString() ?? 'Unknown number',
    displayName: value['displayName']?.toString() ?? 'Unknown caller',
    category: value['category']?.toString() ?? 'Uncategorized',
    riskScore: (value['riskScore'] as num?)?.toInt() ?? 0,
    riskLabel: value['riskLabel']?.toString() ?? 'Unverified',
    isContact: value['isContact'] == true,
    isTrusted: value['isTrusted'] == true,
    isBlocked: value['isBlocked'] == true,
    reports: (value['reports'] as num?)?.toInt() ?? 0,
    similarity: (value['similarity'] as num?)?.toDouble() ?? 0,
    reasons: (value['reasons'] as List<Object?>? ?? const [])
        .map((reason) => reason.toString())
        .toList(),
  );
}

class SafetySignalDefinition {
  const SafetySignalDefinition({
    required this.key,
    required this.label,
    required this.reason,
    required this.weight,
  });

  final String key;
  final String label;
  final String reason;
  final int weight;

  factory SafetySignalDefinition.fromMap(Map<Object?, Object?> value) =>
      SafetySignalDefinition(
        key: value['key']?.toString() ?? '',
        label: value['label']?.toString() ?? 'Safety signal',
        reason: value['reason']?.toString() ?? '',
        weight: (value['weight'] as num?)?.toInt() ?? 0,
      );
}

class CallProtectionRules {
  const CallProtectionRules({
    this.blockPrivate = false,
    this.blockUnknown = false,
    this.blockHighRisk = false,
  });

  final bool blockPrivate;
  final bool blockUnknown;
  final bool blockHighRisk;

  factory CallProtectionRules.fromMap(Map<Object?, Object?> value) =>
      CallProtectionRules(
        blockPrivate: value['blockPrivate'] == true,
        blockUnknown: value['blockUnknown'] == true,
        blockHighRisk: value['blockHighRisk'] == true,
      );
}

class SpamAnalytics {
  const SpamAnalytics({
    required this.screened,
    required this.spam,
    required this.blocked,
    required this.unknown,
    required this.localReports,
    required this.vectorMatches,
    required this.windowDays,
    required this.trackedCalls,
    required this.suspiciousTrackedCalls,
  });

  const SpamAnalytics.empty()
    : screened = 0,
      spam = 0,
      blocked = 0,
      unknown = 0,
      localReports = 0,
      vectorMatches = 0,
      windowDays = 30,
      trackedCalls = 0,
      suspiciousTrackedCalls = 0;

  final int screened;
  final int spam;
  final int blocked;
  final int unknown;
  final int localReports;
  final int vectorMatches;
  final int windowDays;
  final int trackedCalls;
  final int suspiciousTrackedCalls;

  factory SpamAnalytics.fromMap(Map<Object?, Object?> value) => SpamAnalytics(
    screened: (value['screened'] as num?)?.toInt() ?? 0,
    spam: (value['spam'] as num?)?.toInt() ?? 0,
    blocked: (value['blocked'] as num?)?.toInt() ?? 0,
    unknown: (value['unknown'] as num?)?.toInt() ?? 0,
    localReports: (value['localReports'] as num?)?.toInt() ?? 0,
    vectorMatches: (value['vectorMatches'] as num?)?.toInt() ?? 0,
    windowDays: (value['windowDays'] as num?)?.toInt() ?? 30,
    trackedCalls: (value['trackedCalls'] as num?)?.toInt() ?? 0,
    suspiciousTrackedCalls:
        (value['suspiciousTrackedCalls'] as num?)?.toInt() ?? 0,
  );
}

class SavedContact {
  const SavedContact({
    required this.contactId,
    required this.displayName,
    required this.number,
    required this.normalizedNumber,
    required this.typeLabel,
    required this.photoUri,
    required this.starred,
  });

  final int contactId;
  final String displayName;
  final String number;
  final String normalizedNumber;
  final String typeLabel;
  final String photoUri;
  final bool starred;

  factory SavedContact.fromMap(Map<Object?, Object?> value) => SavedContact(
    contactId: (value['contactId'] as num?)?.toInt() ?? 0,
    displayName: value['displayName']?.toString() ?? 'Unknown contact',
    number: value['number']?.toString() ?? '',
    normalizedNumber: value['normalizedNumber']?.toString() ?? '',
    typeLabel: value['typeLabel']?.toString() ?? 'Phone',
    photoUri: value['photoUri']?.toString() ?? '',
    starred: value['starred'] == true,
  );
}

class PhoneCallSnapshot {
  const PhoneCallSnapshot({
    required this.number,
    required this.displayName,
    required this.riskScore,
    required this.riskLabel,
    required this.category,
    required this.isTrusted,
    required this.isBlocked,
    required this.reasons,
    required this.trackingEnabled,
    required this.trackingRiskScore,
    required this.trackingRiskLabel,
    required this.trackingSimilarity,
    required this.trackingSignals,
    required this.trackingReasons,
    required this.trackingStartedAt,
    required this.audioCaptured,
    this.captureStatus = 'off',
    this.transcript = '',
    required this.direction,
    required this.state,
    required this.muted,
    required this.speakerOn,
    required this.canHold,
  });

  final String number;
  final String displayName;
  final int riskScore;
  final String riskLabel;
  final String category;
  final bool isTrusted;
  final bool isBlocked;
  final List<String> reasons;
  final bool trackingEnabled;
  final int trackingRiskScore;
  final String trackingRiskLabel;
  final double trackingSimilarity;
  final List<String> trackingSignals;
  final List<String> trackingReasons;
  final DateTime? trackingStartedAt;
  final bool audioCaptured;
  final String captureStatus;
  final String transcript;
  final String direction;
  final String state;
  final bool muted;
  final bool speakerOn;
  final bool canHold;

  bool get isRinging => state == 'ringing';
  bool get isHeld => state == 'holding';

  factory PhoneCallSnapshot.fromMap(
    Map<Object?, Object?> value,
  ) => PhoneCallSnapshot(
    number: value['number']?.toString() ?? 'Unknown number',
    displayName:
        value['displayName']?.toString() ??
        value['number']?.toString() ??
        'Unknown caller',
    riskScore: (value['riskScore'] as num?)?.toInt() ?? 0,
    riskLabel: value['riskLabel']?.toString() ?? 'Unverified',
    category: value['category']?.toString() ?? 'Uncategorized',
    isTrusted: value['isTrusted'] == true,
    isBlocked: value['isBlocked'] == true,
    reasons: (value['reasons'] as List<Object?>? ?? const [])
        .map((reason) => reason.toString())
        .toList(),
    trackingEnabled: value['trackingEnabled'] == true,
    trackingRiskScore: (value['trackingRiskScore'] as num?)?.toInt() ?? 0,
    trackingRiskLabel: value['trackingRiskLabel']?.toString() ?? 'Tracking off',
    trackingSimilarity: (value['trackingSimilarity'] as num?)?.toDouble() ?? 0,
    trackingSignals: (value['trackingSignals'] as List<Object?>? ?? const [])
        .map((signal) => signal.toString())
        .toList(),
    trackingReasons: (value['trackingReasons'] as List<Object?>? ?? const [])
        .map((reason) => reason.toString())
        .toList(),
    trackingStartedAt: ((value['trackingStartedAt'] as num?)?.toInt() ?? 0) > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            (value['trackingStartedAt'] as num).toInt(),
          )
        : null,
    audioCaptured: value['audioCaptured'] == true,
    captureStatus: value['captureStatus']?.toString() ?? 'off',
    transcript: value['transcript']?.toString() ?? '',
    direction: value['direction']?.toString() ?? 'outgoing',
    state: value['state']?.toString() ?? 'unknown',
    muted: value['muted'] == true,
    speakerOn: value['speakerOn'] == true,
    canHold: value['canHold'] == true,
  );
}

class CloudSafetyAssessment {
  const CloudSafetyAssessment({
    required this.risk,
    required this.level,
    required this.reasons,
    required this.recommendedActions,
    required this.warningText,
    required this.source,
    required this.vectorDatabase,
    required this.vectorMatchLabel,
    required this.vectorMatchSimilarity,
  });

  final int risk;
  final String level;
  final List<String> reasons;
  final List<String> recommendedActions;
  final String warningText;
  final String source;
  final String vectorDatabase;
  final String vectorMatchLabel;
  final double? vectorMatchSimilarity;

  factory CloudSafetyAssessment.fromJson(Map<String, Object?> value) =>
      CloudSafetyAssessment(
        risk: (value['risk'] as num?)?.toInt() ?? 0,
        level: value['level']?.toString() ?? 'unknown',
        reasons: (value['reasons'] as List<Object?>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        recommendedActions:
            (value['recommendedActions'] as List<Object?>? ?? const [])
                .map((item) => item.toString())
                .toList(),
        warningText: value['warningText']?.toString() ?? '',
        source: value['source']?.toString() ?? 'gateway',
        vectorDatabase: value['vectorDatabase']?.toString() ?? 'local-fallback',
        vectorMatchLabel:
            (value['vectorMatch'] as Map<Object?, Object?>?)?['label']
                ?.toString() ??
            '',
        vectorMatchSimilarity:
            ((value['vectorMatch'] as Map<Object?, Object?>?)?['similarity']
                    as num?)
                ?.toDouble(),
      );
}

class CommunityReputation {
  const CommunityReputation({
    required this.found,
    required this.category,
    required this.risk,
    required this.riskLabel,
    required this.reportCount,
    required this.confidence,
    required this.reasons,
    required this.source,
  });

  final bool found;
  final String category;
  final int risk;
  final String riskLabel;
  final int reportCount;
  final double confidence;
  final List<String> reasons;
  final String source;

  factory CommunityReputation.fromJson(Map<String, Object?> value) =>
      CommunityReputation(
        found: value['found'] == true,
        category: value['category']?.toString() ?? 'Unknown',
        risk: (value['risk'] as num?)?.toInt() ?? 0,
        riskLabel: value['riskLabel']?.toString() ?? 'No community reports',
        reportCount: (value['reportCount'] as num?)?.toInt() ?? 0,
        confidence: (value['confidence'] as num?)?.toDouble() ?? 0,
        reasons: (value['reasons'] as List<Object?>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        source: value['source']?.toString() ?? 'none',
      );
}

class GuardianConfig {
  const GuardianConfig({
    this.primaryAlias = '',
    this.guardianPhone = '',
    this.guardianId = '',
    this.status = 'not_configured',
  });

  final String primaryAlias;
  final String guardianPhone;
  final String guardianId;
  final String status;

  bool get isConfigured =>
      primaryAlias.isNotEmpty &&
      guardianPhone.isNotEmpty &&
      guardianId.isNotEmpty;
  bool get isVerified => isConfigured && status == 'verified';

  factory GuardianConfig.fromMap(Map<Object?, Object?> value) => GuardianConfig(
    primaryAlias: value['primaryAlias']?.toString() ?? '',
    guardianPhone: value['guardianPhone']?.toString() ?? '',
    guardianId: value['guardianId']?.toString() ?? '',
    status: value['status']?.toString() ?? 'not_configured',
  );
}

class GuardianEnrollment {
  const GuardianEnrollment({
    required this.enrollmentId,
    required this.status,
    required this.expiresAt,
    required this.message,
  });

  final String enrollmentId;
  final String status;
  final DateTime expiresAt;
  final String message;

  bool get isVerified => status == 'verified';

  factory GuardianEnrollment.fromJson(Map<String, Object?> value) =>
      GuardianEnrollment(
        enrollmentId: value['enrollmentId']?.toString() ?? '',
        status: value['status']?.toString() ?? 'pending',
        expiresAt:
            DateTime.tryParse(value['expiresAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        message: value['message']?.toString() ?? '',
      );
}

class GuardianApproval {
  const GuardianApproval({
    required this.requestId,
    required this.refCode,
    required this.status,
    required this.expiresAt,
    required this.message,
  });

  final String requestId;
  final String refCode;
  final String status;
  final DateTime expiresAt;
  final String message;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDenied => status == 'rejected' || status == 'expired';

  factory GuardianApproval.fromJson(Map<String, Object?> value) =>
      GuardianApproval(
        requestId: value['requestId']?.toString() ?? '',
        refCode: value['refCode']?.toString() ?? '',
        status: value['status']?.toString() ?? 'pending',
        expiresAt:
            DateTime.tryParse(value['expiresAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        message: value['message']?.toString() ?? '',
      );
}

class CallHistoryEntry {
  const CallHistoryEntry({
    required this.number,
    required this.identity,
    required this.direction,
    required this.callType,
    required this.startedAt,
    required this.endedAt,
    required this.location,
    required this.isRead,
    required this.source,
  });

  final String number;
  final CallerIdentity identity;
  final String direction;
  final String callType;
  final DateTime startedAt;
  final DateTime endedAt;
  final String location;
  final bool isRead;
  final String source;

  Duration get duration => endedAt.difference(startedAt);

  factory CallHistoryEntry.fromMap(Map<Object?, Object?> value) =>
      CallHistoryEntry(
        number: value['number']?.toString() ?? 'Unknown number',
        identity: CallerIdentity.fromMap(value),
        direction: value['direction']?.toString() ?? 'outgoing',
        callType:
            value['callType']?.toString() ??
            value['direction']?.toString() ??
            'outgoing',
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          (value['startedAt'] as num?)?.toInt() ?? 0,
        ),
        endedAt: DateTime.fromMillisecondsSinceEpoch(
          (value['endedAt'] as num?)?.toInt() ?? 0,
        ),
        location: value['location']?.toString() ?? '',
        isRead: value['isRead'] == true,
        source: value['source']?.toString() ?? 'kavasam',
      );
}
