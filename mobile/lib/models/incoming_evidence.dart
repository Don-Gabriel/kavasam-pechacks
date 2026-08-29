class IncomingEvidence {
  const IncomingEvidence({
    required this.type,
    required this.source,
    this.text = '',
    this.path,
    this.mimeType = 'text/plain',
    this.title,
    this.localScore,
    this.localReasons = const [],
    this.verification,
  });

  final String type;
  final String source;
  final String text;
  final String? path;
  final String mimeType;
  final String? title;
  final int? localScore;
  final List<String> localReasons;
  final String? verification;

  bool get isImage => type == 'image' && path != null;
  bool get isCall => type == 'call';

  factory IncomingEvidence.fromMap(Map<Object?, Object?> raw) {
    final reasons =
        raw['localReasons']?.toString().split('|') ?? const <String>[];
    return IncomingEvidence(
      type: raw['type']?.toString() ?? 'text',
      source: raw['source']?.toString() ?? 'Android',
      text: raw['text']?.toString() ?? '',
      path: raw['path']?.toString(),
      mimeType: raw['mimeType']?.toString() ?? 'text/plain',
      title: raw['title']?.toString(),
      localScore: raw['localScore'] is num
          ? (raw['localScore'] as num).toInt()
          : null,
      localReasons: reasons.where((reason) => reason.isNotEmpty).toList(),
      verification: raw['verification']?.toString(),
    );
  }
}

class ProtectionStatus {
  const ProtectionStatus({
    required this.notificationShield,
    required this.callScreening,
    required this.androidVersion,
  });

  const ProtectionStatus.unavailable()
    : notificationShield = false,
      callScreening = false,
      androidVersion = 0;

  final bool notificationShield;
  final bool callScreening;
  final int androidVersion;

  factory ProtectionStatus.fromMap(Map<Object?, Object?> raw) {
    return ProtectionStatus(
      notificationShield: raw['notificationShield'] == true,
      callScreening: raw['callScreening'] == true,
      androidVersion: (raw['androidVersion'] as num?)?.toInt() ?? 0,
    );
  }
}
