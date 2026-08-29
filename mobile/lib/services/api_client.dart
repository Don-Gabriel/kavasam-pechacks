import 'dart:convert';
import 'dart:io';

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

  Future<RiskResult> analyzeImage({
    required String path,
    required String mimeType,
    required String context,
    required String language,
  }) async {
    await authenticateForDemo();
    final bytes = await File(path).readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      throw const KavasamApiException(
        'This image is larger than 5 MB. Share a screenshot or a smaller image.',
      );
    }
    final json = await _send('/fraud/analyze-image', {
      'image_base64': base64Encode(bytes),
      'mime_type': mimeType,
      'context': context,
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

  Future<Map<String, dynamic>> addGuardian({
    required String name,
    required String phone,
  }) async {
    await authenticateForDemo();
    return _send('/guardian/add', {
      'guardian_name': name,
      'guardian_phone': phone,
    });
  }

  Future<Map<String, dynamic>> alertGuardian({
    required String eventId,
    required String message,
  }) async {
    await authenticateForDemo();
    return _send('/guardian/alert', {'event_id': eventId, 'message': message});
  }

  Future<Map<String, dynamic>> generateReport({
    required String eventId,
    String notes = '',
  }) async {
    await authenticateForDemo();
    return _send('/report/generate', {
      'event_id': eventId,
      'incident_notes': notes,
    });
  }

  Future<List<int>> synthesizeWarning({
    required String text,
    required String language,
  }) async {
    await authenticateForDemo();
    final response = await _send('/voice/warning', {
      'text': text,
      'language': language,
    });
    return base64Decode(response['audio_base64'] as String);
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
