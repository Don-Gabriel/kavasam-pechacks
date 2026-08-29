import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kavasam_mobile/models/phone.dart';

class PhoneBridge {
  PhoneBridge({MethodChannel? channel, EventChannel? callEvents})
    : _channel = channel ?? const MethodChannel('app.kavasam/offline_phone'),
      _callEvents = callEvents ?? const EventChannel('app.kavasam/call_events');

  final MethodChannel _channel;
  final EventChannel _callEvents;

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
