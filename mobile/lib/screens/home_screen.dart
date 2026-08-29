import 'package:flutter/material.dart';
import 'package:kavasam_mobile/core/theme.dart';
import 'package:kavasam_mobile/models/incoming_evidence.dart';
import 'package:kavasam_mobile/screens/call_guard_screen.dart';
import 'package:kavasam_mobile/screens/evidence_review_screen.dart';
import 'package:kavasam_mobile/screens/guardian_setup_screen.dart';
import 'package:kavasam_mobile/screens/message_analyzer_screen.dart';
import 'package:kavasam_mobile/screens/payment_guard_screen.dart';
import 'package:kavasam_mobile/screens/protection_setup_screen.dart';
import 'package:kavasam_mobile/screens/qr_guard_screen.dart';
import 'package:kavasam_mobile/screens/screenshot_check_screen.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/services/native_guard_bridge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.guardBridge,
    required this.paattiMode,
    required this.onPaattiModeChanged,
  });

  final KavasamApiClient apiClient;
  final NativeGuardBridge guardBridge;
  final bool paattiMode;
  final ValueChanged<bool> onPaattiModeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProtectionStatus _status = const ProtectionStatus.unavailable();
  bool _routingEvidence = false;

  @override
  void initState() {
    super.initState();
    widget.guardBridge.onEvidence = _routeEvidence;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _initializeProtection(),
    );
  }

  @override
  void dispose() {
    widget.guardBridge.onEvidence = null;
    super.dispose();
  }

  Future<void> _initializeProtection() async {
    final status = await widget.guardBridge.getProtectionStatus();
    final evidence = await widget.guardBridge.initialize();
    if (mounted) setState(() => _status = status);
    for (final item in evidence) {
      if (!mounted) break;
      await _routeEvidence(item);
    }
  }

  Future<void> _routeEvidence(IncomingEvidence evidence) async {
    if (!mounted || _routingEvidence) return;
    _routingEvidence = true;
    final screen = evidence.isCall
        ? CallGuardScreen(apiClient: widget.apiClient, screenedCall: evidence)
        : EvidenceReviewScreen(apiClient: widget.apiClient, evidence: evidence);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    _routingEvidence = false;
  }

  Future<void> _openSetup() async {
    await _open(ProtectionSetupScreen(bridge: widget.guardBridge));
    final status = await widget.guardBridge.getProtectionStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _open(Widget screen) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = [
      _status.notificationShield,
      _status.callScreening,
    ].where((enabled) => enabled).length;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
              sliver: SliverList.list(
                children: [
                  const _BrandBar(),
                  const SizedBox(height: 22),
                  _SafetyHero(activeCount: activeCount, onSetup: _openSetup),
                  const SizedBox(height: 16),
                  _AutomaticShieldCard(status: _status, onTap: _openSetup),
                  const SizedBox(height: 18),
                  _PaattiModeCard(
                    enabled: widget.paattiMode,
                    onChanged: widget.onPaattiModeChanged,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Protect me now',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Fast actions for the moment something feels wrong.',
                  ),
                  const SizedBox(height: 14),
                  _ProtectionTile(
                    icon: Icons.qr_code_scanner_rounded,
                    color: const Color(0xFF9A5B00),
                    background: const Color(0xFFFFF0D5),
                    title: 'Scan a payment QR',
                    subtitle: 'Decode and check the receiver before paying',
                    badge: 'AUTO CHECK',
                    onTap: () =>
                        _open(QrGuardScreen(apiClient: widget.apiClient)),
                  ),
                  const SizedBox(height: 12),
                  _ProtectionTile(
                    icon: Icons.image_search_outlined,
                    color: const Color(0xFF315A98),
                    background: const Color(0xFFE4EEFF),
                    title: 'Check a screenshot or photo',
                    subtitle: 'OCR + multimodal fraud analysis',
                    onTap: () => _open(
                      ScreenshotCheckScreen(apiClient: widget.apiClient),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProtectionTile(
                    icon: Icons.phone_in_talk_outlined,
                    color: const Color(0xFF7755AA),
                    background: const Color(0xFFF0E9FA),
                    title: 'Protect this call',
                    subtitle: 'Visible speakerphone transcription and warnings',
                    onTap: () =>
                        _open(CallGuardScreen(apiClient: widget.apiClient)),
                  ),
                  const SizedBox(height: 12),
                  _ProtectionTile(
                    icon: Icons.message_outlined,
                    color: KavasamColors.forest,
                    background: KavasamColors.mint,
                    title: 'Check a suspicious message',
                    subtitle:
                        'Use Android Share → Check with Kavasam, or paste text',
                    badge: 'SHARE TARGET',
                    onTap: () => _open(
                      MessageAnalyzerScreen(apiClient: widget.apiClient),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProtectionTile(
                    icon: Icons.family_restroom_outlined,
                    color: const Color(0xFF8E3B63),
                    background: const Color(0xFFFBE6F0),
                    title: 'Set up a trusted guardian',
                    subtitle: 'One tap alerts when a fraud check is dangerous',
                    onTap: () =>
                        _open(GuardianSetupScreen(apiClient: widget.apiClient)),
                  ),
                  const SizedBox(height: 12),
                  _ProtectionTile(
                    icon: Icons.payments_outlined,
                    color: const Color(0xFF8B4A00),
                    background: const Color(0xFFFFE8D1),
                    title: 'Enter payment details',
                    subtitle: 'Fallback when a QR is unavailable',
                    onTap: () =>
                        _open(PaymentGuardScreen(apiClient: widget.apiClient)),
                  ),
                  const SizedBox(height: 28),
                  const _PrivacyNotice(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandBar extends StatelessWidget {
  const _BrandBar();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          color: KavasamColors.forest,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.shield_rounded, color: Colors.white),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KAVASAM',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const Text('AI protection before money moves'),
          ],
        ),
      ),
      IconButton(
        onPressed: () {},
        icon: const Icon(Icons.account_circle_outlined),
      ),
    ],
  );
}

class _SafetyHero extends StatelessWidget {
  const _SafetyHero({required this.activeCount, required this.onSetup});
  final int activeCount;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF103F32), Color(0xFF1F6B52)],
      ),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.white,
              size: 34,
            ),
            const Spacer(),
            Chip(
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              label: Text(
                '$activeCount/2 automatic shields',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Pause. Check. Protect.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Kavasam looks for manipulation before you share a secret or send money.',
          style: TextStyle(color: Colors.white, height: 1.45),
        ),
        if (activeCount < 2) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onSetup,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: KavasamColors.forest,
            ),
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Finish automatic setup'),
          ),
        ],
      ],
    ),
  );
}

class _AutomaticShieldCard extends StatelessWidget {
  const _AutomaticShieldCard({required this.status, required this.onTap});
  final ProtectionStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: KavasamColors.mint,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: KavasamColors.forest,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Automatic Android shields',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Messages ${status.notificationShield ? 'ON' : 'OFF'}  •  Calls ${status.callScreening ? 'ON' : 'OFF'}',
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _PaattiModeCard extends StatelessWidget {
  const _PaattiModeCard({required this.enabled, required this.onChanged});
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Icon(Icons.record_voice_over_outlined),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paatti Mode',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              Text('Larger text and voice-first warnings'),
            ],
          ),
        ),
        Switch(value: enabled, onChanged: onChanged),
      ],
    ),
  );
}

class _ProtectionTile extends StatelessWidget {
  const _ProtectionTile({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      minTileHeight: 88,
      leading: CircleAvatar(
        backgroundColor: background,
        foregroundColor: color,
        child: Icon(icon),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: onTap,
    ),
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();
  @override
  Widget build(BuildContext context) => const Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.verified_user_outlined, color: KavasamColors.forest),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'Consent-first by design. On-device checks run locally; full analysis is sent only for evidence you choose to review.',
        ),
      ),
    ],
  );
}
