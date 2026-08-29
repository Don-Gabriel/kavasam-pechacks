import 'package:flutter/material.dart';
import 'package:kavasam_mobile/core/theme.dart';
import 'package:kavasam_mobile/screens/call_guard_screen.dart';
import 'package:kavasam_mobile/screens/message_analyzer_screen.dart';
import 'package:kavasam_mobile/screens/payment_guard_screen.dart';
import 'package:kavasam_mobile/services/api_client.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.paattiMode,
    required this.onPaattiModeChanged,
  });

  final KavasamApiClient apiClient;
  final bool paattiMode;
  final ValueChanged<bool> onPaattiModeChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
              sliver: SliverList.list(
                children: [
                  const _BrandBar(),
                  const SizedBox(height: 24),
                  const _SafetyHero(),
                  const SizedBox(height: 24),
                  _PaattiModeCard(
                    enabled: paattiMode,
                    onChanged: onPaattiModeChanged,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'What do you want to check?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ProtectionTile(
                    icon: Icons.message_outlined,
                    iconColor: KavasamColors.forest,
                    iconBackground: KavasamColors.mint,
                    title: 'Check a suspicious message',
                    subtitle: 'Paste SMS, WhatsApp, or email text',
                    onTap: () => _open(
                      context,
                      MessageAnalyzerScreen(apiClient: apiClient),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProtectionTile(
                    icon: Icons.qr_code_scanner_rounded,
                    iconColor: const Color(0xFF9A5B00),
                    iconBackground: const Color(0xFFFFF0D5),
                    title: 'Check before you pay',
                    subtitle: 'Review a UPI ID, merchant, and request',
                    onTap: () => _open(
                      context,
                      PaymentGuardScreen(apiClient: apiClient),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProtectionTile(
                    icon: Icons.phone_in_talk_outlined,
                    iconColor: const Color(0xFF7755AA),
                    iconBackground: const Color(0xFFF0E9FA),
                    title: 'Suspicious call mode',
                    subtitle: 'User-controlled call transcript analysis',
                    onTap: () =>
                        _open(context, CallGuardScreen(apiClient: apiClient)),
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

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _BrandBar extends StatelessWidget {
  const _BrandBar();

  @override
  Widget build(BuildContext context) {
    return Row(
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KAVASAM',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            Text(
              'Your money safety companion',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const Spacer(),
        const Badge(
          backgroundColor: KavasamColors.mint,
          textColor: KavasamColors.forest,
          label: Text('Protected'),
        ),
      ],
    );
  }
}

class _SafetyHero extends StatelessWidget {
  const _SafetyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: KavasamColors.forest,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              'PAUSE • CHECK • PROTECT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Stop fraud before\nmoney leaves.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Share only what you choose. Kavasam explains pressure tactics before you act.',
            style: TextStyle(color: Color(0xFFD9EFE8), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _PaattiModeCard extends StatelessWidget {
  const _PaattiModeCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        secondary: const CircleAvatar(
          backgroundColor: KavasamColors.mint,
          foregroundColor: KavasamColors.forest,
          child: Icon(Icons.record_voice_over_outlined),
        ),
        title: const Text(
          'Paatti Mode',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Larger controls and simpler guidance'),
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

class _ProtectionTile extends StatelessWidget {
  const _ProtectionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 20,
          color: KavasamColors.forest,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Kavasam never monitors calls or messages in the background. Analysis starts only when you ask.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}
