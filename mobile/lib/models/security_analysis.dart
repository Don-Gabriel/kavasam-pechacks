class UrlAssessment {
  const UrlAssessment({
    required this.originalHost,
    required this.finalHost,
    required this.redirectCount,
    required this.redirectChain,
    required this.usesShortener,
    required this.hostChanged,
    required this.reachable,
  });

  final String originalHost;
  final String finalHost;
  final int redirectCount;
  final List<String> redirectChain;
  final bool usesShortener;
  final bool hostChanged;
  final bool reachable;

  factory UrlAssessment.fromJson(Map<Object?, Object?> value) => UrlAssessment(
    originalHost: value['originalHost']?.toString() ?? '',
    finalHost: value['finalHost']?.toString() ?? '',
    redirectCount: (value['redirectCount'] as num?)?.toInt() ?? 0,
    redirectChain: (value['redirectChain'] as List<Object?>? ?? const [])
        .map((item) => item.toString())
        .toList(),
    usesShortener: value['usesShortener'] == true,
    hostChanged: value['hostChanged'] == true,
    reachable: value['reachable'] == true,
  );
}

class SecurityAnalysis {
  const SecurityAnalysis({
    required this.risk,
    required this.level,
    required this.category,
    required this.summary,
    required this.reasons,
    required this.recommendedActions,
    required this.indicators,
    required this.source,
    required this.extractedTextPreview,
    this.urlAssessment,
  });

  final int risk;
  final String level;
  final String category;
  final String summary;
  final List<String> reasons;
  final List<String> recommendedActions;
  final List<String> indicators;
  final String source;
  final String extractedTextPreview;
  final UrlAssessment? urlAssessment;

  bool get isDangerous => risk > 80;

  factory SecurityAnalysis.fromJson(Map<String, Object?> value) {
    final url = value['urlAssessment'];
    return SecurityAnalysis(
      risk: (value['risk'] as num?)?.toInt() ?? 0,
      level: value['level']?.toString() ?? 'low',
      category: value['category']?.toString() ?? 'unknown',
      summary: value['summary']?.toString() ?? '',
      reasons: (value['reasons'] as List<Object?>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      recommendedActions:
          (value['recommendedActions'] as List<Object?>? ?? const [])
              .map((item) => item.toString())
              .toList(),
      indicators: (value['indicators'] as List<Object?>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      source: value['source']?.toString() ?? 'rules-fallback',
      extractedTextPreview: value['extractedTextPreview']?.toString() ?? '',
      urlAssessment: url is Map
          ? UrlAssessment.fromJson(Map<Object?, Object?>.from(url))
          : null,
    );
  }
}

class HighRiskAnalysis {
  const HighRiskAnalysis({
    required this.reportId,
    required this.callSessionId,
    required this.number,
    required this.displayName,
    required this.occurredAt,
    required this.risk,
    required this.riskLabel,
    required this.summary,
    required this.source,
    required this.vectorDatabase,
    required this.signals,
    required this.expiresAt,
  });

  final String reportId;
  final String callSessionId;
  final String number;
  final String displayName;
  final DateTime occurredAt;
  final int risk;
  final String riskLabel;
  final String summary;
  final String source;
  final String vectorDatabase;
  final List<String> signals;
  final DateTime expiresAt;

  factory HighRiskAnalysis.fromMap(Map<Object?, Object?> value) =>
      HighRiskAnalysis(
        reportId: value['reportId']?.toString() ?? '',
        callSessionId: value['callSessionId']?.toString() ?? '',
        number: value['number']?.toString() ?? '',
        displayName: value['displayName']?.toString() ?? '',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          (value['occurredAt'] as num?)?.toInt() ?? 0,
        ),
        risk: (value['risk'] as num?)?.toInt() ?? 0,
        riskLabel: value['riskLabel']?.toString() ?? 'Dangerous',
        summary: value['summary']?.toString() ?? '',
        source: value['source']?.toString() ?? '',
        vectorDatabase: value['vectorDatabase']?.toString() ?? '',
        signals: (value['signals'] as List<Object?>? ?? const [])
            .map((item) => item.toString())
            .toList(),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (value['expiresAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

class GuardianViewerConfig {
  const GuardianViewerConfig({
    this.guardianId = '',
    this.primaryAlias = '',
    this.sessionToken = '',
    this.expiresAt,
  });

  final String guardianId;
  final String primaryAlias;
  final String sessionToken;
  final DateTime? expiresAt;

  bool get isSignedIn =>
      guardianId.isNotEmpty &&
      sessionToken.isNotEmpty &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory GuardianViewerConfig.fromMap(Map<Object?, Object?> value) {
    final milliseconds = (value['expiresAt'] as num?)?.toInt() ?? 0;
    return GuardianViewerConfig(
      guardianId: value['guardianId']?.toString() ?? '',
      primaryAlias: value['primaryAlias']?.toString() ?? '',
      sessionToken: value['sessionToken']?.toString() ?? '',
      expiresAt: milliseconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(milliseconds)
          : null,
    );
  }
}

class GuardianClaim {
  const GuardianClaim({
    required this.guardianId,
    required this.sessionToken,
    required this.primaryAlias,
    required this.expiresAt,
    required this.message,
  });

  final String guardianId;
  final String sessionToken;
  final String primaryAlias;
  final DateTime expiresAt;
  final String message;

  factory GuardianClaim.fromJson(Map<String, Object?> value) => GuardianClaim(
    guardianId: value['guardianId']?.toString() ?? '',
    sessionToken: value['sessionToken']?.toString() ?? '',
    primaryAlias: value['primaryAlias']?.toString() ?? '',
    expiresAt:
        DateTime.tryParse(value['expiresAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    message: value['message']?.toString() ?? '',
  );
}

class GuardianReport {
  const GuardianReport({
    required this.reportId,
    required this.primaryAlias,
    required this.callerLast4,
    required this.occurredAt,
    required this.risk,
    required this.riskLabel,
    required this.summary,
    required this.signals,
  });

  final String reportId;
  final String primaryAlias;
  final String callerLast4;
  final DateTime occurredAt;
  final int risk;
  final String riskLabel;
  final String summary;
  final List<String> signals;

  factory GuardianReport.fromJson(Map<Object?, Object?> value) =>
      GuardianReport(
        reportId: value['reportId']?.toString() ?? '',
        primaryAlias: value['primaryAlias']?.toString() ?? '',
        callerLast4: value['callerLast4']?.toString() ?? '',
        occurredAt:
            DateTime.tryParse(value['occurredAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        risk: (value['risk'] as num?)?.toInt() ?? 0,
        riskLabel: value['riskLabel']?.toString() ?? 'Dangerous',
        summary: value['summary']?.toString() ?? '',
        signals: (value['signals'] as List<Object?>? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
}
