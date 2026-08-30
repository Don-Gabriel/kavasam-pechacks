import 'package:flutter/material.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';

/// Speaks a scam warning aloud. Prefers ElevenLabs audio from the gateway
/// (English or Tamil); if that is unavailable it falls back to the device's
/// own text-to-speech so the user still hears an alert.
class SpeakWarningButton extends StatefulWidget {
  const SpeakWarningButton({
    super.key,
    required this.bridge,
    required this.service,
    required this.text,
  });

  final PhoneBridge bridge;
  final CloudSafetyService service;
  final String text;

  @override
  State<SpeakWarningButton> createState() => _SpeakWarningButtonState();
}

class _SpeakWarningButtonState extends State<SpeakWarningButton> {
  String? _busyLanguage;

  Future<void> _warn(String language) async {
    if (_busyLanguage != null) return;
    setState(() => _busyLanguage = language);
    String? note;
    try {
      final audio = await widget.service.warningAudio(
        text: widget.text,
        language: language,
      );
      await widget.bridge.playWarningAudio(audio);
    } on Object {
      // Fall back to the device voice. Offline Tamil text is unavailable, so the
      // spoken fallback uses English wording.
      final spoken = await widget.bridge.speakWarning(widget.text, 'en');
      note = spoken
          ? 'ElevenLabs voice unavailable — used the device voice.'
          : 'Could not play a spoken warning on this device.';
    } finally {
      if (mounted) setState(() => _busyLanguage = null);
      if (note != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(note)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.volume_up_rounded, size: 18),
          SizedBox(width: 6),
          Text('Warn aloud', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
      ActionChip(
        avatar: _busyLanguage == 'en'
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.campaign_rounded, size: 16),
        label: const Text('English'),
        onPressed: _busyLanguage == null ? () => _warn('en') : null,
      ),
      ActionChip(
        avatar: _busyLanguage == 'ta'
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.campaign_rounded, size: 16),
        label: const Text('தமிழ்'),
        onPressed: _busyLanguage == null ? () => _warn('ta') : null,
      ),
    ],
  );
}
