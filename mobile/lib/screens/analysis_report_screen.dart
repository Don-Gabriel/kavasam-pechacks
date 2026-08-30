import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';
import 'package:kavasam_mobile/widgets/analysis_result_view.dart';

/// Full-screen report for a scanned QR code (or any payload analysed together
/// with its embedded links). Runs the supplied analysis once on open.
class AnalysisReportScreen extends StatefulWidget {
  const AnalysisReportScreen({
    super.key,
    required this.heading,
    required this.payload,
    required this.runner,
    this.bridge,
    this.service,
  });

  final String heading;
  final String payload;
  final Future<CombinedAnalysis> Function() runner;
  final PhoneBridge? bridge;
  final CloudSafetyService? service;

  @override
  State<AnalysisReportScreen> createState() => _AnalysisReportScreenState();
}

class _AnalysisReportScreenState extends State<AnalysisReportScreen> {
  CombinedAnalysis? _analysis;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final analysis = await widget.runner();
      if (mounted) setState(() => _analysis = analysis);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.heading,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scanned content',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      widget.payload,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              const Center(
                child: Text('Checking the content and any links…'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!),
              ),
              const SizedBox(height: 12),
              Center(
                child: FilledButton.tonal(
                  onPressed: _run,
                  child: const Text('Try again'),
                ),
              ),
            ],
            if (analysis != null) ...[
              const SizedBox(height: 12),
              AnalysisResultView(
                result: analysis.primary,
                title: analysis.primaryLabel,
                bridge: widget.bridge,
                service: widget.service,
              ),
              if (analysis.links.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Links found (${analysis.links.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Each link is checked on its own — a safe-looking message can '
                  'still carry a dangerous link.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                ...analysis.links.map(_linkCard),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkCard(LinkAnalysis link) {
    final result = link.result;
    if (result == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                link.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Could not be checked: ${link.error ?? 'unknown error'}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AnalysisResultView(result: result, title: link.url, compact: true),
    );
  }
}
