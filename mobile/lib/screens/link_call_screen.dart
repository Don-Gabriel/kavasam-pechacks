import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/phone.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';

/// Kavasam Link: an in-app call between two Kavasam phones with live
/// two-sided transcription and scam analysis. Exists because Android
/// silences microphone capture for normal apps during cellular calls.
class LinkCallScreen extends StatefulWidget {
  const LinkCallScreen({
    super.key,
    required this.bridge,
    required this.cloudSafety,
    required this.deviceId,
    required this.safetySignals,
  });

  final PhoneBridge bridge;
  final CloudSafetyService cloudSafety;
  final String deviceId;
  final List<SafetySignalDefinition> safetySignals;

  @override
  State<LinkCallScreen> createState() => _LinkCallScreenState();
}

class _LinkCallScreenState extends State<LinkCallScreen> {
  final _joinCode = TextEditingController();
  StreamSubscription<LinkCallSnapshot?>? _events;
  LinkCallSnapshot? _link;
  CloudSafetyAssessment? _assessment;
  String? _message;
  bool _busy = false;
  bool _analyzing = false;
  int _analyzedBucket = -1;

  @override
  void initState() {
    super.initState();
    _events = widget.bridge.watchLinkCall().listen((value) {
      if (!mounted) return;
      setState(() => _link = value);
      _maybeAnalyze(value);
    }, onError: (_) {});
    widget.bridge.getLinkSnapshot().then((value) {
      if (mounted && value != null) setState(() => _link = value);
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _joinCode.dispose();
    super.dispose();
  }

  Future<void> _maybeAnalyze(LinkCallSnapshot? link) async {
    if (link == null ||
        link.status != 'active' ||
        _analyzing ||
        !widget.cloudSafety.isConfigured) {
      return;
    }
    final bucket =
        link.transcript.length ~/ 120 + link.trackingSignals.length * 1000;
    if (bucket == _analyzedBucket) return;
    _analyzing = true;
    _analyzedBucket = bucket;
    try {
      final assessment = await widget.cloudSafety.analyze(
        sessionId: CloudSafetyService.newSessionId(),
        call: link.toAnalysisSnapshot(),
      );
      if (mounted) setState(() => _assessment = assessment);
    } on Object {
      // The local risk panel keeps working when the gateway is unreachable.
    } finally {
      _analyzing = false;
    }
  }

  Future<void> _startAsHost() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final granted = await widget.bridge.requestMicPermission();
      if (!granted) {
        setState(() => _message = 'Microphone permission is required.');
        return;
      }
      final code = await widget.cloudSafety.createLinkRoom(widget.deviceId);
      final started = await widget.bridge.linkStart(
        wsUrl: widget.cloudSafety.linkSocketUrl(code, 'host'),
        code: code,
        role: 'host',
      );
      if (!started) setState(() => _message = 'The link call could not start.');
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinAsGuest() async {
    final code = _joinCode.text.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      setState(() => _message = 'Enter the 6-digit code from the other phone.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final granted = await widget.bridge.requestMicPermission();
      if (!granted) {
        setState(() => _message = 'Microphone permission is required.');
        return;
      }
      final started = await widget.bridge.linkStart(
        wsUrl: widget.cloudSafety.linkSocketUrl(code, 'guest'),
        code: code,
        role: 'guest',
      );
      if (!started) setState(() => _message = 'The link call could not start.');
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    final active = link != null && link.isActive;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KAVASAM LINK',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            if (!active) ..._setupSection(link) else ..._callSection(link),
            if (_message != null) ...[
              const SizedBox(height: 14),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _setupSection(LinkCallSnapshot? link) => [
    Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Call another Kavasam phone',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 6),
            const Text(
              'A Kavasam-to-Kavasam call carries its audio inside the app, so '
              'both sides are transcribed and scam-checked live — no '
              'speakerphone needed. Both phones must reach the same gateway.',
              style: TextStyle(fontSize: 12),
            ),
            if (link != null && (link.status == 'ended' || link.status == 'failed')) ...[
              const SizedBox(height: 10),
              Text(
                link.status == 'failed'
                    ? 'Link call failed: ${link.failure}'
                    : 'The link call ended.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _startAsHost,
                icon: const Icon(Icons.podcasts_rounded),
                label: const Text('Start a link call'),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Or join a call started on the other phone:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _joinCode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      hintText: '6-digit code',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(
                  onPressed: _busy ? null : _joinAsGuest,
                  child: const Text('Join'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _callSection(LinkCallSnapshot link) {
    final waiting = link.status != 'active';
    final risky = link.trackingRiskScore >= 45;
    final availableSignals = widget.safetySignals
        .where((signal) => !link.trackingSignals.contains(signal.key))
        .toList();
    return [
      Card(
        color: risky ? const Color(0xFF651B1B) : const Color(0xFF103A68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
          child: Column(
            children: [
              Icon(
                risky ? Icons.gpp_bad_rounded : Icons.podcasts_rounded,
                color: Colors.white,
                size: 54,
              ),
              const SizedBox(height: 10),
              Text(
                waiting
                    ? link.status == 'connecting'
                          ? 'Connecting…'
                          : 'Waiting for the other phone'
                    : 'Kavasam Link call',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (waiting && link.code.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Enter this code on the other phone:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  link.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _riskPanel(link),
              if (!waiting && availableSignals.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: availableSignals
                        .map(
                          (signal) => ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 16),
                            label: Text(signal.label),
                            onPressed: () =>
                                widget.bridge.linkAddSignal(signal.key),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LinkButton(
                    icon: link.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: link.muted ? 'Unmute' : 'Mute',
                    onPressed: () => widget.bridge.linkSetMuted(!link.muted),
                  ),
                  _LinkButton(
                    icon: Icons.volume_up_rounded,
                    label: 'Speaker',
                    onPressed: () =>
                        widget.bridge.linkSetSpeaker(!link.speakerOn),
                  ),
                  _LinkButton(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: Colors.red.shade700,
                    onPressed: widget.bridge.linkEnd,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (_assessment != null) ...[
        const SizedBox(height: 12),
        _assessmentCard(_assessment!),
      ],
      const SizedBox(height: 12),
      _transcriptCard(link),
    ];
  }

  Widget _riskPanel(LinkCallSnapshot link) {
    final highRisk = link.trackingRiskScore >= 50;
    final color = highRisk ? const Color(0xFFFF8A80) : const Color(0xFF8BE9C0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            link.trackingRiskLabel,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: link.trackingRiskScore / 100,
            color: color,
            backgroundColor: Colors.white12,
          ),
          const SizedBox(height: 6),
          Text(
            'Suspicion ${link.trackingRiskScore}/100 · live transcript analysis',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          ...link.trackingReasons
              .take(3)
              .map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• $reason',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _assessmentCard(CloudSafetyAssessment assessment) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI second opinion · ${assessment.risk}/100',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(assessment.warningText),
          ...assessment.recommendedActions
              .take(2)
              .map(
                (action) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• $action',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  Widget _transcriptCard(LinkCallSnapshot link) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live transcript',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Both sides are transcribed by the gateway. Numbers are masked '
            'before they reach either phone.',
            style: TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (link.entries.isEmpty)
            const Text(
              'Speak normally — text appears every few seconds.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            )
          else
            ...link.entries.reversed
                .take(12)
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: '${entry.speaker}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: entry.speaker == 'Caller'
                                  ? const Color(0xFF176BCE)
                                  : const Color(0xFF0B7A69),
                            ),
                          ),
                          TextSpan(text: entry.text),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    ),
  );
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF2F5B87),
  });

  final IconData icon;
  final String label;
  final Future<bool> Function() onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size(58, 58),
        ),
        icon: Icon(icon, color: Colors.white),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}
