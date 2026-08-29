class RiskResult {
  const RiskResult({
    required this.eventId,
    required this.score,
    required this.level,
    required this.fraudType,
    required this.reasons,
    required this.warning,
    required this.recommendedAction,
  });

  final String eventId;
  final int score;
  final String level;
  final String fraudType;
  final List<String> reasons;
  final String warning;
  final String recommendedAction;

  factory RiskResult.fromJson(Map<String, dynamic> json) {
    return RiskResult(
      eventId: json['event_id'] as String,
      score: (json['risk_score'] as num).toInt(),
      level: (json['risk_level'] ?? json['status'] ?? 'UNKNOWN') as String,
      fraudType: (json['fraud_type'] ?? 'PAYMENT_CHECK') as String,
      reasons:
          ((json['reasons'] as List<dynamic>?) ??
                  [json['reason'] ?? 'No reason provided'])
              .map((item) => item.toString())
              .toList(),
      warning:
          (json['warning'] ?? json['reason'] ?? 'Review before continuing')
              as String,
      recommendedAction:
          (json['recommended_action'] ??
                  'Verify independently before continuing')
              as String,
    );
  }
}
