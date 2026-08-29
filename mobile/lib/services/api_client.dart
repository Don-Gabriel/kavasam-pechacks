import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kavasam_mobile/models/risk_result.dart';

class KavasamApiException implements Exception {
  const KavasamApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class KavasamApiClient {
  KavasamApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'KAVASAM_API_URL',
            defaultValue: 'http://localhost:8000',
          );

  final http.Client _client;
  final String baseUrl;
  String? _accessToken;

  Future<void> authenticateForDemo() async {
    if (_accessToken != null) return;
    final login = await _send('/auth/login', {
      'phone_number': '+919876543210',
    }, authenticated: false);
    final otp = login['dev_otp'] as String?;
    if (otp == null) {
      throw const KavasamApiException(
        'Development OTP is hidden. Sign in through the production authentication flow.',
      );
    }
    final verified = await _send('/auth/verify', {
      'session_id': login['session_id'],
      'otp': otp,
    }, authenticated: false);
    _accessToken = verified['access_token'] as String;
  }

  Future<RiskResult> analyzeMessage({
    required String text,
    required String language,
  }) async {
    await authenticateForDemo();
    final json = await _send('/fraud/analyze-message', {
      'text': text,
      'language': language,
    });
    return RiskResult.fromJson(json);
  }

  Future<RiskResult> analyzeCall({
    required String transcript,
    required String language,
  }) async {
    await authenticateForDemo();
    final json = await _send('/call/analyze', {
      'transcript': transcript,
      'language': language,
    });
    return RiskResult.fromJson(json);
  }

  Future<RiskResult> checkPayment({
    required String upiId,
    required String merchantName,
    required double amount,
    required String context,
  }) async {
    await authenticateForDemo();
    final json = await _send('/payment/check', {
      'upi_id': upiId,
      'merchant_name': merchantName,
      'amount': amount,
      'context': context,
    });
    return RiskResult.fromJson(json);
  }

  Future<Map<String, dynamic>> _send(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const KavasamApiException(
        'Kavasam could not reach the protection service. Check that the backend is running.',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KavasamApiException(
        decoded['detail']?.toString() ?? 'Request failed',
      );
    }
    return decoded;
  }

  void close() => _client.close();
}
