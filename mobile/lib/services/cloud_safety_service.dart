import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:kavasam_mobile/models/phone.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';

class CloudSafetyException implements Exception {
  const CloudSafetyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudSafetyService {
  CloudSafetyService({String? baseUrl, HttpClient? client})
    : baseUrl = (baseUrl ?? const String.fromEnvironment('KAVASAM_AI_BASE_URL'))
          .trim()
          .replaceFirst(RegExp(r'/$'), ''),
      _client = client ?? HttpClient();

  final String baseUrl;
  final HttpClient _client;

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<CommunityReputation> lookupReputation(String phoneNumber) async {
    final value = await _postJson('/v1/reputation/lookup', {
      'phoneNumber': _networkNumber(phoneNumber),
    });
    return CommunityReputation.fromJson(value);
  }

  Future<CommunityReputation> reportReputation({
    required String phoneNumber,
    required String reporterId,
    required String category,
  }) async {
    final value = await _postJson('/v1/reputation/report', {
      'phoneNumber': _networkNumber(phoneNumber),
      'reporterId': reporterId,
      'category': category,
    });
    return CommunityReputation.fromJson(value);
  }

  Future<CloudSafetyAssessment> analyze({
    required String sessionId,
    required PhoneCallSnapshot call,
    String locale = 'en-IN',
  }) async {
    final value = await _postJson('/v1/safety/analyze', {
      'schemaVersion': 1,
      'sessionId': sessionId,
      'localRisk': call.trackingRiskScore,
      'vectorSimilarity': call.trackingSimilarity,
      'signals': call.trackingSignals,
      'callerContext': {
        'savedContact': call.category == 'Contact',
        'locallyReported':
            call.category != 'Contact' && call.category != 'Uncategorized',
        'carrierVerificationFailed': call.reasons.any(
          (reason) => reason.toLowerCase().contains('carrier'),
        ),
      },
      'transcriptExcerpt': _redactedTranscript(call.transcript),
      'locale': locale,
    });
    return CloudSafetyAssessment.fromJson(value);
  }

  /// Digit runs are masked before upload so OTPs, card numbers, and phone
  /// numbers spoken aloud never leave the device.
  String _redactedTranscript(String transcript) {
    final tail = transcript.length <= 2000
        ? transcript
        : transcript.substring(transcript.length - 2000);
    return tail.replaceAll(RegExp(r'\d{3,}'), '###');
  }

  Future<SecurityAnalysis> analyzeContent({
    required String kind,
    required String text,
    String locale = 'en-IN',
  }) async {
    final value = await _postJson('/v1/content/analyze', {
      'schemaVersion': 1,
      'sessionId': newSessionId(),
      'kind': kind,
      'text': text.trim(),
      'locale': locale,
    });
    return SecurityAnalysis.fromJson(value);
  }

  Future<SecurityAnalysis> analyzeUrl(
    String url, {
    String locale = 'en-IN',
  }) async {
    final value = await _postJson('/v1/content/analyze-url', {
      'schemaVersion': 1,
      'sessionId': newSessionId(),
      'url': url.trim(),
      'locale': locale,
    });
    return SecurityAnalysis.fromJson(value);
  }

  Future<SecurityAnalysis> analyzeFile({
    required String kind,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    String locale = 'en-IN',
  }) async {
    if (bytes.length > 8 * 1024 * 1024) {
      throw const CloudSafetyException('Choose a file smaller than 8 MB.');
    }
    final value = await _postJson('/v1/content/analyze-file', {
      'schemaVersion': 1,
      'sessionId': newSessionId(),
      'kind': kind,
      'fileName': fileName,
      'mimeType': mimeType,
      'dataBase64': base64Encode(bytes),
      'locale': locale,
    });
    return SecurityAnalysis.fromJson(value);
  }

  /// Creates a Kavasam Link room and returns its six-digit code.
  Future<String> createLinkRoom(String deviceId) async {
    final value = await _postJson('/v1/link/rooms', {'deviceId': deviceId});
    final code = value['code']?.toString() ?? '';
    if (code.isEmpty) {
      throw const CloudSafetyException('The gateway did not return a code.');
    }
    return code;
  }

  /// WebSocket URL for a link room, derived from the gateway base URL.
  String linkSocketUrl(String code, String role) {
    final base = _validatedBase();
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base
        .replace(scheme: scheme, path: '/v1/link/ws/$code')
        .replace(queryParameters: {'role': role})
        .toString();
  }

  Future<GuardianEnrollment> enrollGuardian({
    required String deviceId,
    required String guardianPhone,
    required String primaryAlias,
    String locale = 'en-IN',
  }) async {
    final value = await _postJson('/v1/guardian/enrollments', {
      'deviceId': deviceId,
      'guardianPhone': _networkNumber(guardianPhone),
      'primaryAlias': primaryAlias.trim(),
      'locale': locale,
    });
    return GuardianEnrollment.fromJson(value);
  }

  Future<GuardianEnrollment> getGuardianEnrollment({
    required String enrollmentId,
    required String deviceId,
  }) async {
    final value = await _getJson('/v1/guardian/enrollments/$enrollmentId', {
      'deviceId': deviceId,
    });
    return GuardianEnrollment.fromJson(value);
  }

  Future<GuardianApproval> requestGuardianApproval({
    required String deviceId,
    required GuardianConfig guardian,
    required String callSessionId,
    required PhoneCallSnapshot call,
  }) async {
    final digits = call.number.replaceAll(RegExp(r'[^0-9]'), '');
    final value = await _postJson('/v1/guardian/approvals', {
      'deviceId': deviceId,
      'guardianId': guardian.guardianId,
      'guardianPhone': _networkNumber(guardian.guardianPhone),
      'callSessionId': callSessionId,
      'primaryAlias': guardian.primaryAlias,
      'callerLast4': digits.length <= 4
          ? digits
          : digits.substring(digits.length - 4),
      'risk': call.trackingRiskScore,
      'riskLabel': call.trackingRiskLabel,
      'signals': call.trackingSignals,
    });
    return GuardianApproval.fromJson(value);
  }

  Future<GuardianApproval> getGuardianApproval({
    required String requestId,
    required String deviceId,
  }) async {
    final value = await _getJson('/v1/guardian/approvals/$requestId', {
      'deviceId': deviceId,
    });
    return GuardianApproval.fromJson(value);
  }

  Future<GuardianClaim> claimGuardianRelationship({
    required String guardianPhone,
    required String referenceCode,
    required String guardianDeviceId,
  }) async {
    final value = await _postJson('/v1/guardian/claims', {
      'guardianPhone': _networkNumber(guardianPhone),
      'referenceCode': referenceCode.trim(),
      'guardianDeviceId': guardianDeviceId,
    });
    return GuardianClaim.fromJson(value);
  }

  Future<String> submitGuardianReport({
    required String reportId,
    required String deviceId,
    required GuardianConfig guardian,
    required String callSessionId,
    required PhoneCallSnapshot call,
    required CloudSafetyAssessment assessment,
  }) async {
    final digits = call.number.replaceAll(RegExp(r'[^0-9]'), '');
    final value = await _postJson('/v1/guardian/reports', {
      'reportId': reportId,
      'deviceId': deviceId,
      'guardianId': guardian.guardianId,
      'guardianPhone': _networkNumber(guardian.guardianPhone),
      'callSessionId': callSessionId,
      'callerLast4': digits.length <= 4
          ? digits
          : digits.substring(digits.length - 4),
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'risk': assessment.risk,
      'riskLabel': assessment.risk > 80 ? 'Dangerous' : assessment.level,
      'summary': assessment.warningText,
      'signals': call.trackingSignals,
    });
    return value['status']?.toString() ?? 'stored';
  }

  Future<List<GuardianReport>> guardianReports(String sessionToken) async {
    final value = await _getJson(
      '/v1/guardian/reports',
      const {},
      headers: {'authorization': 'Bearer $sessionToken'},
    );
    return (value['reports'] as List<Object?>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => GuardianReport.fromJson(Map<Object?, Object?>.from(item)),
        )
        .toList();
  }

  Future<Map<String, Object?>> _getJson(
    String path,
    Map<String, String> query, {
    Map<String, String> headers = const {},
  }) async {
    final base = _validatedBase();
    final uri = base.resolve(path).replace(queryParameters: query);
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    request.headers.set('accept', 'application/json');
    headers.forEach(request.headers.set);
    return _readJson(
      await request.close().timeout(const Duration(seconds: 15)),
    );
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    final base = _validatedBase();
    final request = await _client
        .postUrl(base.resolve(path))
        .timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    request.headers.set('accept', 'application/json');
    request.write(jsonEncode(payload));
    return _readJson(
      await request.close().timeout(const Duration(seconds: 15)),
    );
  }

  Uri _validatedBase() {
    if (!isConfigured) {
      throw const CloudSafetyException('Cloud gateway is not configured.');
    }
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasScheme ||
        (base.scheme != 'https' && !_isPrivateHost(base.host))) {
      throw const CloudSafetyException(
        'The cloud gateway must use HTTPS (localhost and private LAN '
        'addresses are allowed for development).',
      );
    }
    return base;
  }

  static bool _isPrivateHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1') return true;
    // Hotspot/LAN demo setups run the gateway on a private IPv4 address.
    return RegExp(
      r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)[0-9.]+$',
    ).hasMatch(host);
  }

  Future<Map<String, Object?>> _readJson(HttpClientResponse response) async {
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decodedError = _tryDecodeJson(body);
      final detail = decodedError?['detail']?.toString();
      throw CloudSafetyException(
        response.statusCode == 429
            ? 'Cloud analysis is busy. Local protection is still active.'
            : detail ?? 'Gateway request failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const CloudSafetyException('Cloud gateway returned invalid data.');
    }
    return Map<String, Object?>.from(decoded);
  }

  Map<String, Object?>? _tryDecodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  String _networkNumber(String value) {
    final trimmed = value.trim();
    final prefix = trimmed.startsWith('+') ? '+' : '';
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7 || digits.length > 18) {
      throw const CloudSafetyException(
        'Enter a complete phone number for community lookup.',
      );
    }
    return '$prefix$digits';
  }

  static String newSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
