import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/incoming_evidence.dart';
import 'package:kavasam_mobile/services/native_guard_bridge.dart';
import 'package:permission_handler/permission_handler.dart';

class ProtectionSetupScreen extends StatefulWidget {
  const ProtectionSetupScreen({super.key, required this.bridge});

  final NativeGuardBridge bridge;

  @override
  State<ProtectionSetupScreen> createState() => _ProtectionSetupScreenState();
}

class _ProtectionSetupScreenState extends State<ProtectionSetupScreen>
    with WidgetsBindingObserver {
  ProtectionStatus _status = const ProtectionStatus.unavailable();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await widget.bridge.getProtectionStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _loading = false;
      });
    }
  }

  Future<void> _enableNotifications() async {
    await Permission.notification.request();
    await widget.bridge.openNotificationAccess();
  }

  Future<void> _enableCallScreening() async {
    final supported = await widget.bridge.requestCallScreeningRole();
    if (!supported && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call screening requires Android 10 or newer.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic Protection')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              'Turn Kavasam into a shield',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Android keeps these controls in system settings. You decide which protections are active and can revoke them anytime.',
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              _SetupCard(
                icon: Icons.notifications_active_outlined,
                title: 'Message notification shield',
                description:
                    'Checks visible notification text on-device for urgent payment, credential, remote-access, and impersonation signals.',
                enabled: _status.notificationShield,
                actionLabel: 'Open Android access settings',
                onPressed: _enableNotifications,
              ),
              const SizedBox(height: 14),
              _SetupCard(
                icon: Icons.phone_callback_outlined,
                title: 'Incoming call screening',
                description:
                    'Lets Android send caller metadata to Kavasam before ringing. Calls are allowed by default; audio is never intercepted.',
                enabled: _status.callScreening,
                actionLabel: 'Make Kavasam call screener',
                onPressed: _enableCallScreening,
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF5EE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Fast notification checks happen on the phone. Only suspicious evidence you open is sent to the Kavasam backend for full analysis.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    enabled ? Icons.check_circle : Icons.pause_circle_outline,
                    size: 17,
                  ),
                  label: Text(enabled ? 'ON' : 'OFF'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(description),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: enabled
                  ? OutlinedButton.icon(
                      onPressed: onPressed,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Review system access'),
                    )
                  : FilledButton.icon(
                      onPressed: onPressed,
                      icon: const Icon(Icons.shield_outlined),
                      label: Text(actionLabel),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
