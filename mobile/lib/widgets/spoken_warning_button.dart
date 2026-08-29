import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:kavasam_mobile/services/api_client.dart';

class SpokenWarningButton extends StatefulWidget {
  const SpokenWarningButton({
    super.key,
    required this.text,
    required this.language,
    this.apiClient,
  });

  final String text;
  final String language;
  final KavasamApiClient? apiClient;

  @override
  State<SpokenWarningButton> createState() => _SpokenWarningButtonState();
}

class _SpokenWarningButtonState extends State<SpokenWarningButton> {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  bool _speaking = false;

  @override
  void dispose() {
    _tts.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    if (widget.apiClient != null) {
      try {
        final audio = await widget.apiClient!.synthesizeWarning(
          text: widget.text,
          language: widget.language,
        );
        await _player.play(BytesSource(Uint8List.fromList(audio)));
        await _player.onPlayerComplete.first;
        if (mounted) setState(() => _speaking = false);
        return;
      } on KavasamApiException {
        // Natural voice is optional. Android TTS is the reliable offline fallback.
      }
    }
    await _tts.setLanguage(switch (widget.language) {
      'Tamil' => 'ta-IN',
      'Hindi' => 'hi-IN',
      _ => 'en-IN',
    });
    await _tts.setSpeechRate(0.42);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(widget.text);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _toggle,
      icon: Icon(
        _speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
      ),
      label: Text(_speaking ? 'Stop warning' : 'Read warning aloud'),
    );
  }
}
