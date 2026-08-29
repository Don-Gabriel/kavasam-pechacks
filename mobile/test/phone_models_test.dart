import 'package:flutter_test/flutter_test.dart';
import 'package:kavasam_mobile/models/phone.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';

void main() {
  test('parses an explainable spam identity', () {
    final identity = CallerIdentity.fromMap({
      'number': '+919999999999',
      'displayName': 'Suspected caller',
      'category': 'Spam',
      'riskScore': 78,
      'riskLabel': 'Likely spam',
      'isContact': false,
      'isTrusted': false,
      'isBlocked': false,
      'reports': 2,
      'similarity': 0.84,
      'reasons': ['Reported twice', 'Repeat-call burst'],
    });

    expect(identity.isSpam, isTrue);
    expect(identity.riskScore, 78);
    expect(identity.reasons, hasLength(2));
  });

  test('parses private analytics counters', () {
    final analytics = SpamAnalytics.fromMap({
      'screened': 12,
      'spam': 3,
      'blocked': 1,
      'unknown': 7,
      'localReports': 4,
      'vectorMatches': 2,
      'windowDays': 30,
    });

    expect(analytics.screened, 12);
    expect(analytics.vectorMatches, 2);
    expect(analytics.windowDays, 30);
  });

  test('parses a saved Android contact', () {
    final contact = SavedContact.fromMap({
      'contactId': 42,
      'displayName': 'Test Contact',
      'number': '+91 90000 00000',
      'normalizedNumber': '+919000000000',
      'typeLabel': 'Mobile',
      'photoUri': '',
      'starred': true,
    });

    expect(contact.displayName, 'Test Contact');
    expect(contact.normalizedNumber, '+919000000000');
    expect(contact.starred, isTrue);
  });

  test('parses a missed system call', () {
    final call = CallHistoryEntry.fromMap({
      'number': '5550100',
      'displayName': 'Unknown caller',
      'riskScore': 10,
      'callType': 'missed',
      'direction': 'incoming',
      'startedAt': 1000,
      'endedAt': 1000,
      'source': 'system',
      'isRead': false,
    });

    expect(call.callType, 'missed');
    expect(call.source, 'system');
    expect(call.isRead, isFalse);
  });

  test('parses an active consented safety session', () {
    final call = PhoneCallSnapshot.fromMap({
      'number': '5550100',
      'displayName': 'Unknown caller',
      'riskScore': 10,
      'riskLabel': 'Unverified',
      'direction': 'incoming',
      'state': 'ringing',
      'trackingEnabled': true,
      'trackingRiskScore': 68,
      'trackingRiskLabel': 'Suspicious',
      'trackingSimilarity': 0.81,
      'trackingSignals': ['otp_pin'],
      'trackingReasons': ['Caller requested an OTP'],
      'trackingStartedAt': 1000,
      'audioCaptured': false,
    });

    expect(call.trackingEnabled, isTrue);
    expect(call.trackingRiskScore, 68);
    expect(call.trackingSignals, contains('otp_pin'));
    expect(call.audioCaptured, isFalse);
  });

  test('parses a cloud safety assessment without caller PII', () {
    final assessment = CloudSafetyAssessment.fromJson({
      'risk': 84,
      'level': 'high',
      'reasons': ['OTP request with urgency'],
      'recommendedActions': ['End the call and verify independently'],
      'warningText': 'Never share an OTP.',
      'source': 'gemini',
      'vectorDatabase': 'actian-vectorai',
      'vectorMatch': {
        'label': 'OTP or PIN credential theft',
        'similarity': 0.93,
      },
    });

    expect(assessment.risk, 84);
    expect(assessment.source, 'gemini');
    expect(assessment.vectorDatabase, 'actian-vectorai');
    expect(assessment.vectorMatchLabel, 'OTP or PIN credential theft');
    expect(assessment.vectorMatchSimilarity, 0.93);
    expect(assessment.recommendedActions, hasLength(1));
  });

  test('parses community reputation and protection rules', () {
    final reputation = CommunityReputation.fromJson({
      'found': true,
      'category': 'Financial fraud',
      'risk': 82,
      'riskLabel': 'Likely scam',
      'reportCount': 4,
      'confidence': 0.84,
      'reasons': ['4 independent reports'],
      'source': 'community',
    });
    final rules = CallProtectionRules.fromMap({
      'blockPrivate': true,
      'blockUnknown': false,
      'blockHighRisk': true,
    });

    expect(reputation.found, isTrue);
    expect(reputation.risk, 82);
    expect(rules.blockPrivate, isTrue);
    expect(rules.blockUnknown, isFalse);
    expect(rules.blockHighRisk, isTrue);
  });

  test('parses verified guardian state and approval outcome', () {
    final guardian = GuardianConfig.fromMap({
      'primaryAlias': 'Amma',
      'guardianPhone': '+919876543210',
      'guardianId': '2cbb470b-a2b0-4ea1-9c1b-2fe31a83ed12',
      'status': 'verified',
    });
    final approval = GuardianApproval.fromJson({
      'requestId': '66c43ccb-c0df-4662-bccf-81caf21b913e',
      'refCode': '4821',
      'status': 'approved',
      'expiresAt': '2026-08-29T12:05:00Z',
      'message': 'Guardian approved continuing the call.',
    });

    expect(guardian.isVerified, isTrue);
    expect(approval.isApproved, isTrue);
    expect(approval.isDenied, isFalse);
  });

  test('parses dangerous content and redirect evidence', () {
    final result = SecurityAnalysis.fromJson({
      'risk': 92,
      'level': 'critical',
      'category': 'Suspicious link',
      'summary': 'The link hides its destination.',
      'reasons': ['Known shortener'],
      'recommendedActions': ['Do not open it'],
      'indicators': ['url_shortener'],
      'source': 'rules-fallback',
      'extractedTextPreview': '',
      'urlAssessment': {
        'originalHost': 'tinyurl.com',
        'finalHost': 'tinyurl.com',
        'redirectCount': 0,
        'redirectChain': ['https://tinyurl.com/demo'],
        'usesShortener': true,
        'hostChanged': false,
        'reachable': false,
      },
    });
    expect(result.isDangerous, isTrue);
    expect(result.urlAssessment?.usesShortener, isTrue);
  });

  test('parses guardian viewer session and report', () {
    final viewer = GuardianViewerConfig.fromMap({
      'guardianId': 'guardian-1',
      'primaryAlias': 'Amma',
      'sessionToken': 'token',
      'expiresAt': DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
    });
    final report = GuardianReport.fromJson({
      'reportId': 'report-1',
      'primaryAlias': 'Amma',
      'callerLast4': '3210',
      'occurredAt': '2026-08-30T10:00:00Z',
      'risk': 91,
      'riskLabel': 'Dangerous',
      'summary': 'OTP and payment pressure detected.',
      'signals': ['otp_pin', 'payment_transfer'],
    });
    expect(viewer.isSignedIn, isTrue);
    expect(report.risk, 91);
    expect(report.signals, contains('otp_pin'));
  });
}
