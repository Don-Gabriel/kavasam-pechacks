import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kavasam_mobile/models/phone.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';

class PhoneBridge {
  PhoneBridge({
    MethodChannel? channel,
    EventChannel? callEvents,
    EventChannel? linkEvents,
  }) : _channel = channel ?? const MethodChannel('app.kavasam/offline_phone'),
       _callEvents = callEvents ?? const EventChannel('app.kavasam/call_events'),
       _linkEvents = linkEvents ?? const EventChannel('app.kavasam/link_events');

  final MethodChannel _channel;
  final EventChannel _callEvents;
  final EventChannel _linkEvents;

  Future<DialerStatus> getDialerStatus() async {
    final value = await _map('getDialerStatus');
    return value == null
        ? const DialerStatus.unavailable()
        : DialerStatus.fromMap(value);
  }

  Future<RoleRequestResult> requestDefaultDialer() async {
    final value = await _map('requestDefaultDialer');
    return value == null
        ? const RoleRequestResult(
            supported: false,
            granted: false,
            message: 'Default phone apps are available only on Android.',
          )
        : RoleRequestResult.fromMap(value);
  }

  Future<RoleRequestResult> requestCallScreening() async {
    final value = await _map('requestCallScreening');
    return value == null
        ? const RoleRequestResult(
            supported: false,
            granted: false,
            message: 'Caller ID screening is available only on Android.',
          )
        : RoleRequestResult.fromMap(value);
  }

  Future<bool> openDefaultAppsSettings() => _bool('openDefaultAppsSettings');

  Future<bool> requestPhonePermission() => _bool('requestPhonePermission');

  Future<bool> requestContactsPermission() =>
      _bool('requestContactsPermission');

  Future<DialerStatus> requestPhoneDataPermissions() async {
    final value = await _map('requestPhoneDataPermissions');
    return value == null
        ? const DialerStatus.unavailable()
        : DialerStatus.fromMap(value);
  }

  Future<String?> takePendingDialNumber() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takePendingDialNumber');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<NativeActionResult> placeCall(String number) async {
    final value = await _map('placeCall', {'number': number});
    return value == null
        ? const NativeActionResult(
            ok: false,
            message: 'Calling is available only on Android.',
          )
        : NativeActionResult.fromMap(value);
  }

  Future<PhoneCallSnapshot?> getCurrentCall() async {
    final value = await _map('getCurrentCall');
    return value == null ? null : PhoneCallSnapshot.fromMap(value);
  }

  Stream<PhoneCallSnapshot?> watchCurrentCall() {
    if (!Platform.isAndroid) return const Stream.empty();
    return _callEvents.receiveBroadcastStream().map((value) {
      if (value == null) return null;
      return PhoneCallSnapshot.fromMap(
        Map<Object?, Object?>.from(value as Map),
      );
    });
  }

  Future<List<CallHistoryEntry>> getHistory() async {
    if (!Platform.isAndroid) return const [];
    try {
      final values = await _channel.invokeMethod<List<Object?>>('getHistory');
      return (values ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                CallHistoryEntry.fromMap(Map<Object?, Object?>.from(value)),
          )
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<SavedContact>> getContacts() async {
    if (!Platform.isAndroid) return const [];
    try {
      final values = await _channel.invokeMethod<List<Object?>>('getContacts');
      return (values ?? const [])
          .whereType<Map>()
          .map(
            (value) => SavedContact.fromMap(Map<Object?, Object?>.from(value)),
          )
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<CallerIdentity?> getCallerIdentity(String number) async {
    final value = await _map('getCallerIdentity', {'number': number});
    return value == null ? null : CallerIdentity.fromMap(value);
  }

  Future<SpamAnalytics> getSpamAnalytics() async {
    final value = await _map('getSpamAnalytics');
    return value == null
        ? const SpamAnalytics.empty()
        : SpamAnalytics.fromMap(value);
  }

  Future<List<SafetySignalDefinition>> getSafetySignals() async {
    if (!Platform.isAndroid) return const [];
    try {
      final values = await _channel.invokeMethod<List<Object?>>(
        'getSafetySignals',
      );
      return (values ?? const [])
          .whereType<Map>()
          .map(
            (value) => SafetySignalDefinition.fromMap(
              Map<Object?, Object?>.from(value),
            ),
          )
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<CallProtectionRules> getProtectionSettings() async {
    final value = await _map('getProtectionSettings');
    return value == null
        ? const CallProtectionRules()
        : CallProtectionRules.fromMap(value);
  }

  Future<CallProtectionRules> setProtectionSetting(
    String key,
    bool value,
  ) async {
    final result = await _map('setProtectionSetting', {
      'key': key,
      'value': value,
    });
    return result == null
        ? const CallProtectionRules()
        : CallProtectionRules.fromMap(result);
  }

  Future<CallerIdentity?> reportSpam(
    String number, {
    String category = 'Spam',
  }) => _identity('reportSpam', {'number': number, 'category': category});

  Future<CallerIdentity?> setTrusted(String number, bool value) =>
      _identity('setTrusted', {'number': number, 'value': value});

  Future<CallerIdentity?> setBlocked(String number, bool value) =>
      _identity('setBlocked', {'number': number, 'value': value});

  Future<CallerIdentity?> setCallerLabel(String number, String name) =>
      _identity('setCallerLabel', {'number': number, 'name': name});

  Future<bool> answer() => _bool('answer');
  Future<bool> reject() => _bool('reject');
  Future<bool> disconnect() => _bool('disconnect');
  Future<bool> setMuted(bool value) => _bool('setMuted', {'value': value});
  Future<bool> setSpeaker(bool value) => _bool('setSpeaker', {'value': value});
  Future<bool> setHeld(bool value) => _bool('setHeld', {'value': value});
  Future<bool> sendDtmf(String digit) => _bool('sendDtmf', {'digit': digit});
  Future<bool> setSafetyTracking(bool value) =>
      _bool('setSafetyTracking', {'value': value});
  Future<bool> requestMicPermission() => _bool('requestMicPermission');
  Future<bool> setAudioCapture(bool value) =>
      _bool('setAudioCapture', {'value': value});

  /// Plays ElevenLabs warning audio (MP3 bytes) through the native player.
  Future<bool> playWarningAudio(Uint8List audio) =>
      _bool('playWarningAudio', {'audio': audio});

  /// Speaks a warning with the device's own text-to-speech as a fallback.
  Future<bool> speakWarning(String text, String language) =>
      _bool('speakWarning', {'text': text, 'language': language});

  Future<bool> stopWarning() => _bool('stopWarning');

  Future<bool> linkStart({
    required String wsUrl,
    required String code,
    required String role,
  }) => _bool('linkStart', {'wsUrl': wsUrl, 'code': code, 'role': role});
  Future<bool> linkEnd() => _bool('linkEnd');
  Future<bool> linkSetMuted(bool value) =>
      _bool('linkSetMuted', {'value': value});
  Future<bool> linkSetSpeaker(bool value) =>
      _bool('linkSetSpeaker', {'value': value});
  Future<bool> linkAddSignal(String signal) =>
      _bool('linkAddSignal', {'signal': signal});

  Future<LinkCallSnapshot?> getLinkSnapshot() async {
    final value = await _map('linkSnapshot');
    return value == null ? null : LinkCallSnapshot.fromMap(value);
  }

  Stream<LinkCallSnapshot?> watchLinkCall() {
    if (!Platform.isAndroid) return const Stream.empty();
    return _linkEvents.receiveBroadcastStream().map((value) {
      if (value == null) return null;
      return LinkCallSnapshot.fromMap(Map<Object?, Object?>.from(value as Map));
    });
  }
  Future<bool> addSafetySignal(String signal) =>
      _bool('addSafetySignal', {'signal': signal});
  Future<bool> getCloudConsent() => _bool('getCloudConsent');
  Future<bool> setCloudConsent(bool value) =>
      _bool('setCloudConsent', {'value': value});
  Future<bool> getCommunityConsent() => _bool('getCommunityConsent');
  Future<bool> setCommunityConsent(bool value) =>
      _bool('setCommunityConsent', {'value': value});

  Future<GuardianConfig> getGuardianConfig() async {
    final value = await _map('getGuardianConfig');
    return value == null
        ? const GuardianConfig()
        : GuardianConfig.fromMap(value);
  }

  Future<GuardianConfig> saveGuardianConfig(GuardianConfig config) async {
    final value = await _map('saveGuardianConfig', {
      'primaryAlias': config.primaryAlias,
      'guardianPhone': config.guardianPhone,
      'guardianId': config.guardianId,
      'status': config.status,
    });
    return value == null
        ? const GuardianConfig()
        : GuardianConfig.fromMap(value);
  }

  Future<GuardianConfig> clearGuardianConfig() async {
    final value = await _map('clearGuardianConfig');
    return value == null
        ? const GuardianConfig()
        : GuardianConfig.fromMap(value);
  }

  Future<bool> saveHighRiskAnalysis({
    required String reportId,
    required String callSessionId,
    required PhoneCallSnapshot call,
    required CloudSafetyAssessment assessment,
  }) => _bool('saveHighRiskAnalysis', {
    'reportId': reportId,
    'callSessionId': callSessionId,
    'number': call.number,
    'displayName': call.displayName,
    'occurredAt': DateTime.now().millisecondsSinceEpoch,
    'risk': assessment.risk,
    'riskLabel': assessment.risk > 80 ? 'Dangerous' : assessment.level,
    'summary': assessment.warningText,
    'source': assessment.source,
    'vectorDatabase': assessment.vectorDatabase,
    'signals': call.trackingSignals,
  });

  Future<List<HighRiskAnalysis>> getHighRiskAnalyses() async {
    if (!Platform.isAndroid) return const [];
    try {
      final values = await _channel.invokeMethod<List<Object?>>(
        'getHighRiskAnalyses',
      );
      return (values ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                HighRiskAnalysis.fromMap(Map<Object?, Object?>.from(item)),
          )
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<GuardianViewerConfig> getGuardianViewerConfig() async {
    final value = await _map('getGuardianViewerConfig');
    return value == null
        ? const GuardianViewerConfig()
        : GuardianViewerConfig.fromMap(value);
  }

  Future<GuardianViewerConfig> saveGuardianViewerConfig(
    GuardianViewerConfig config,
  ) async {
    final value = await _map('saveGuardianViewerConfig', {
      'guardianId': config.guardianId,
      'primaryAlias': config.primaryAlias,
      'sessionToken': config.sessionToken,
      'expiresAt': config.expiresAt?.millisecondsSinceEpoch ?? 0,
    });
    return value == null
        ? const GuardianViewerConfig()
        : GuardianViewerConfig.fromMap(value);
  }

  Future<GuardianViewerConfig> clearGuardianViewerConfig() async {
    final value = await _map('clearGuardianViewerConfig');
    return value == null
        ? const GuardianViewerConfig()
        : GuardianViewerConfig.fromMap(value);
  }

  Future<String> getCommunityReporterId() async {
    if (!Platform.isAndroid) return '';
    try {
      return await _channel.invokeMethod<String>('getCommunityReporterId') ??
          '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<CallerIdentity?> _identity(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final value = await _map(method, arguments);
    return value == null ? null : CallerIdentity.fromMap(value);
  }

  Future<Map<Object?, Object?>?> _map(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>(
        method,
        arguments,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> _bool(String method, [Map<String, Object?>? arguments]) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
