import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:kavasam_mobile/models/phone.dart';

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
      'locale': locale,
    });
    return CloudSafetyAssessment.fromJson(value);
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    if (!isConfigured) {
      throw const CloudSafetyException('Cloud gateway is not configured.');
    }
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasScheme ||
        (base.scheme != 'https' &&
            base.host != 'localhost' &&
            base.host != '127.0.0.1')) {
      throw const CloudSafetyException(
        'The cloud gateway must use HTTPS (localhost is allowed for development).',
      );
    }
    final request = await _client
        .postUrl(base.resolve(path))
        .timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    request.headers.set('accept', 'application/json');
    request.write(jsonEncode(payload));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSafetyException(
        response.statusCode == 429
            ? 'Cloud analysis is busy. Local protection is still active.'
            : 'Cloud analysis failed (${response.statusCode}). Local protection is still active.',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const CloudSafetyException('Cloud gateway returned invalid data.');
    }
    return Map<String, Object?>.from(decoded);
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
