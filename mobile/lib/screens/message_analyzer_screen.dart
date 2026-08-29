import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/risk_result.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/protection_scaffold.dart';
import 'package:kavasam_mobile/widgets/risk_result_card.dart';

class MessageAnalyzerScreen extends StatefulWidget {
  const MessageAnalyzerScreen({super.key, required this.apiClient});

  final KavasamApiClient apiClient;

  @override
  State<MessageAnalyzerScreen> createState() => _MessageAnalyzerScreenState();
}

class _MessageAnalyzerScreenState extends State<MessageAnalyzerScreen> {
  static const _sample =
      'I am from CBI. Your Aadhaar is linked to illegal activity. Stay on the call and transfer INR money immediately.';

  final _messageController = TextEditingController();
  String _language = 'English';
  bool _loading = false;
  String? _error;
  RiskResult? _result;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_messageController.text.trim().isEmpty) {
      setState(() => _error = 'Paste a message before checking it.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.apiClient.analyzeMessage(
        text: _messageController.text.trim(),
        language: _language,
      );
      if (mounted) setState(() => _result = result);
    } on KavasamApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProtectionScaffold(
      title: 'Message Check',
      subtitle:
          'Paste only the suspicious text you want Kavasam to inspect. Nothing is read automatically.',
      children: [
        TextField(
          controller: _messageController,
          minLines: 6,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Suspicious message',
            hintText: 'Paste an SMS, WhatsApp message, or email…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _messageController.text = _sample),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Use digital-arrest demo'),
          ),
        ),
        const SizedBox(height: 8),
        _LanguagePicker(
          value: _language,
          onChanged: (value) => setState(() => _language = value),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _loading ? null : _analyze,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.shield_outlined),
          label: Text(_loading ? 'Checking safely…' : 'Check this message'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 24),
          RiskResultCard(result: _result!),
        ],
      ],
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Explain in'),
      items: const ['English', 'Tamil', 'Hindi']
          .map(
            (language) =>
                DropdownMenuItem(value: language, child: Text(language)),
          )
          .toList(),
      onChanged: (language) {
        if (language != null) onChanged(language);
      },
    );
  }
}
