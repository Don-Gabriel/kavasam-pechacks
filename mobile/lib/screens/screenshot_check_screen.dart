import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kavasam_mobile/models/incoming_evidence.dart';
import 'package:kavasam_mobile/screens/evidence_review_screen.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/protection_scaffold.dart';

class ScreenshotCheckScreen extends StatelessWidget {
  const ScreenshotCheckScreen({super.key, required this.apiClient});

  final KavasamApiClient apiClient;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1800,
      imageQuality: 88,
      requestFullMetadata: false,
    );
    if (file == null || !context.mounted) return;
    final mimeType =
        file.mimeType ??
        (file.path.endsWith('.png') ? 'image/png' : 'image/jpeg');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EvidenceReviewScreen(
          apiClient: apiClient,
          evidence: IncomingEvidence(
            type: 'image',
            source: source == ImageSource.camera
                ? 'Kavasam camera'
                : 'Android gallery',
            path: file.path,
            mimeType: mimeType,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProtectionScaffold(
      title: 'Screenshot Shield',
      subtitle:
          'Inspect WhatsApp chats, payment requests, posters, emails, and QR screenshots.',
      children: [
        _ChoiceCard(
          icon: Icons.photo_library_outlined,
          title: 'Choose a screenshot',
          subtitle:
              'On-device OCR reads the text; Gemini can inspect the full image when configured.',
          onTap: () => _pick(context, ImageSource.gallery),
        ),
        const SizedBox(height: 14),
        _ChoiceCard(
          icon: Icons.camera_alt_outlined,
          title: 'Take a photo',
          subtitle:
              'Useful for printed QR codes, notices, and another phone screen.',
          onTap: () => _pick(context, ImageSource.camera),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minTileHeight: 92,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: onTap,
      ),
    );
  }
}
