import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/risk_result.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/protection_scaffold.dart';
import 'package:kavasam_mobile/widgets/risk_result_card.dart';

class CallGuardScreen extends StatefulWidget {
  const CallGuardScreen({super.key, required this.apiClient});

  final KavasamApiClient apiClient;

  @override
  State<CallGuardScreen> createState() => _CallGuardScreenState();
}

class _CallGuardScreenState extends State<CallGuardScreen> {
  static const _sample =
      'I am a police officer. You are under digital arrest. Stay on this call, do not tell your family, and pay the fine immediately.';

  final _transcriptController = TextEditingController();
  String _language = 'English';
  bool _consented = false;
  bool _loading = false;
  String? _error;
  RiskResult? _result;

  @override
  void dispose() {
    _transcriptController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (!_consented) {
      setState(
        () => _error =
            'Confirm that the call participant authorized this analysis.',
      );
      return;
    }
    if (_transcriptController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a short call transcript to inspect.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.apiClient.analyzeCall(
        transcript: _transcriptController.text.trim(),
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
      title: 'Suspicious Call Mode',
      subtitle:
          'Kavasam never intercepts calls. This demo analyzes only a transcript you explicitly provide.',
      children: [
        TextField(
          controller: _transcriptController,
          minLines: 6,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Authorized call transcript',
            hintText: 'Type what the caller said…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _transcriptController.text = _sample),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Use digital-arrest call demo'),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _language,
          decoration: const InputDecoration(labelText: 'Explain in'),
          items: const ['English', 'Tamil', 'Hindi']
              .map(
                (language) =>
                    DropdownMenuItem(value: language, child: Text(language)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _language = value);
          },
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('I am choosing to analyze this content'),
          subtitle: const Text('No background monitoring or hidden recording'),
          value: _consented,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (value) => setState(() => _consented = value ?? false),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _analyze,
          icon: const Icon(Icons.phone_in_talk_outlined),
          label: Text(
            _loading
                ? 'Listening for warning signs…'
                : 'Analyze this transcript',
          ),
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
