import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kavasam_mobile/models/incoming_evidence.dart';

class NativeGuardBridge {
  NativeGuardBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.kavasam/native_guard');

  final MethodChannel _channel;
  void Function(IncomingEvidence evidence)? onEvidence;

  Future<List<IncomingEvidence>> initialize() async {
    if (!Platform.isAndroid) return const [];
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'evidenceReceived' && call.arguments is Map) {
        onEvidence?.call(
          IncomingEvidence.fromMap(
            Map<Object?, Object?>.from(call.arguments as Map),
          ),
        );
      }
    });
    final evidence = <IncomingEvidence>[];
    for (final method in const [
      'takePendingEvidence',
      'takeNotificationEvidence',
      'takeCallEvidence',
    ]) {
      final item = await _evidenceFrom(method);
      if (item != null) evidence.add(item);
    }
    return evidence;
  }

  Future<ProtectionStatus> getProtectionStatus() async {
    if (!Platform.isAndroid) return const ProtectionStatus.unavailable();
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getProtectionStatus',
      );
      return raw == null
          ? const ProtectionStatus.unavailable()
          : ProtectionStatus.fromMap(raw);
    } on PlatformException {
      return const ProtectionStatus.unavailable();
    } on MissingPluginException {
      return const ProtectionStatus.unavailable();
    }
  }

  Future<bool> openNotificationAccess() =>
      _invokeAction('openNotificationAccess');

  Future<bool> requestCallScreeningRole() =>
      _invokeAction('requestCallScreeningRole');

  Future<IncomingEvidence?> _evidenceFrom(String method) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(method);
      return raw == null ? null : IncomingEvidence.fromMap(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> _invokeAction(String method) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
