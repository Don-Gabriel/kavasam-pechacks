import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/incoming_evidence.dart';
import 'package:kavasam_mobile/models/risk_result.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/protection_scaffold.dart';
import 'package:kavasam_mobile/widgets/incident_actions.dart';
import 'package:kavasam_mobile/widgets/risk_result_card.dart';
import 'package:kavasam_mobile/widgets/spoken_warning_button.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class CallGuardScreen extends StatefulWidget {
  const CallGuardScreen({
    super.key,
    required this.apiClient,
    this.screenedCall,
  });

  final KavasamApiClient apiClient;
  final IncomingEvidence? screenedCall;

  @override
  State<CallGuardScreen> createState() => _CallGuardScreenState();
}

class _CallGuardScreenState extends State<CallGuardScreen> {
  static const _sample =
      'I am a police officer. You are under digital arrest. Stay on this call, do not tell your family, and pay the fine immediately.';

  final _transcriptController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  String _language = 'English';
  bool _consented = false;
  bool _loading = false;
  String? _error;
  RiskResult? _result;
  bool _listening = false;
  String _committedTranscript = '';

  @override
  void dispose() {
    _speech.stop();
    _transcriptController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      if (_transcriptController.text.trim().isNotEmpty) await _analyze();
      return;
    }
    if (!_consented) {
      setState(
        () =>
            _error = 'Confirm the visible microphone analysis before starting.',
      );
      return;
    }
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      setState(
        () => _error = 'Microphone access is required for Protect Call mode.',
      );
      return;
    }
    final available = await _speech.initialize(
      onError: (error) {
        if (mounted) {
          setState(() {
            _listening = false;
            _error = 'Speech recognition stopped: ${error.errorMsg}';
          });
        }
      },
      onStatus: (status) {
        if (mounted && (status == 'done' || status == 'notListening')) {
          setState(() => _listening = false);
        }
      },
    );
    if (!available) {
      setState(
        () => _error =
            'Android speech recognition is not available on this device.',
      );
      return;
    }
    _committedTranscript = _transcriptController.text.trim();
    setState(() {
      _listening = true;
      _error = null;
      _result = null;
    });
    await _speech.listen(
      onResult: (result) {
        final liveWords = result.recognizedWords.trim();
        final combined = [_committedTranscript, liveWords]
            .where((part) => part.isNotEmpty)
            .join(_committedTranscript.isEmpty ? '' : '\n');
        _transcriptController.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
        if (mounted) setState(() {});
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: switch (_language) {
          'Tamil' => 'ta_IN',
          'Hindi' => 'hi_IN',
          _ => 'en_IN',
        },
        listenFor: const Duration(seconds: 50),
        pauseFor: const Duration(seconds: 6),
      ),
    );
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
          'Put the call on speaker, then start visible microphone protection. Android does not give Kavasam hidden access to call audio.',
      children: [
        if (widget.screenedCall != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.screenedCall!.verification == 'failed'
                  ? const Color(0xFFFFE5E2)
                  : const Color(0xFFEAF5EE),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_callback_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Android screened this call',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${widget.screenedCall!.text} • network verification ${widget.screenedCall!.verification ?? 'unavailable'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _listening
                ? const Color(0xFFFFE5E2)
                : const Color(0xFFEAF5EE),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              Icon(
                _listening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                size: 42,
                color: _listening ? Colors.red.shade700 : Colors.green.shade800,
              ),
              const SizedBox(height: 8),
              Text(
                _listening ? 'PROTECTING THIS CALL' : 'Protect Call',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _toggleListening,
                  style: FilledButton.styleFrom(
                    backgroundColor: _listening ? Colors.red.shade700 : null,
                  ),
                  icon: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                  label: Text(
                    _listening ? 'Stop and analyze' : 'Start visible listening',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _transcriptController,
          minLines: 6,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'Authorized call transcript',
            hintText: 'Live words appear here, or type what the caller said…',
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
          title: const Text('I am choosing visible microphone analysis'),
          subtitle: const Text(
            'No background monitoring, hidden recording, or call interception',
          ),
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
          const SizedBox(height: 12),
          SpokenWarningButton(
            text: _result!.warning,
            language: _language,
            apiClient: widget.apiClient,
          ),
          const SizedBox(height: 12),
          IncidentActions(apiClient: widget.apiClient, result: _result!),
        ],
      ],
    );
  }
}
