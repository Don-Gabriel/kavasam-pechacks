import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';
import 'package:kavasam_mobile/screens/analysis_report_screen.dart';
import 'package:kavasam_mobile/screens/qr_scanner_screen.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';
import 'package:kavasam_mobile/widgets/analysis_result_view.dart';

class SecurityAnalysisScreen extends StatefulWidget {
  const SecurityAnalysisScreen({
    super.key,
    required this.service,
    required this.cloudConsent,
    this.bridge,
  });

  final CloudSafetyService service;
  final bool cloudConsent;
  final PhoneBridge? bridge;

  @override
  State<SecurityAnalysisScreen> createState() => _SecurityAnalysisScreenState();
}

class _SecurityAnalysisScreenState extends State<SecurityAnalysisScreen> {
  final _message = TextEditingController();
  final _link = TextEditingController();
  SecurityAnalysis? _result;
  CombinedAnalysis? _combined;
  String? _error;
  bool _busy = false;

  bool get _ready => widget.cloudConsent && widget.service.isConfigured;

  @override
  void dispose() {
    _message.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _run(Future<SecurityAnalysis> Function() action) async {
    if (!_ready || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _combined = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Analyses the pasted message and each link it carries, in parallel.
  Future<void> _analyzeMessage() async {
    if (!_ready || _busy || _message.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _combined = null;
    });
    try {
      final combined = await widget.service.analyzeMessageWithLinks(
        _message.text,
      );
      if (mounted) setState(() => _combined = combined);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanQr() async {
    if (!_ready || _busy) return;
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScannerScreen()),
    );
    if (payload == null || payload.trim().isEmpty || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AnalysisReportScreen(
          heading: 'QR analysis',
          payload: payload,
          runner: () => widget.service.analyzeQrPayload(payload),
          bridge: widget.bridge,
          service: widget.service,
        ),
      ),
    );
  }

  Future<void> _pickPdf() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    final file = selection?.files.single;
    if (file?.bytes == null) return;
    await _run(
      () => widget.service.analyzeFile(
        kind: 'email_pdf',
        fileName: file!.name,
        mimeType: 'application/pdf',
        bytes: file.bytes!,
      ),
    );
  }

  Future<void> _pickScreenshot() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = selection?.files.single;
    if (file?.bytes == null) return;
    final extension = file!.extension?.toLowerCase();
    final mime = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    await _run(
      () => widget.service.analyzeFile(
        kind: 'screenshot',
        fileName: file.name,
        mimeType: mime,
        bytes: file.bytes!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('security-analysis'),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
    children: [
      Text(
        'Analyze suspicious content',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0B1F3A),
        ),
      ),
      const SizedBox(height: 5),
      const Text(
        'Nothing is uploaded until you choose Analyze. Files are processed in memory and are not retained by Kavasam.',
      ),
      if (!_ready) ...[
        const SizedBox(height: 12),
        const _Notice(
          text:
              'Enable Optional cloud AI in Insights and use a build with the Kavasam gateway URL to use these tools.',
        ),
      ],
      const SizedBox(height: 16),
      _AnalysisCard(
        icon: Icons.sms_outlined,
        title: 'Message analysis',
        subtitle:
            'Paste an SMS, chat message, or email text. Any links inside are '
            'checked separately at the same time.',
        child: Column(
          children: [
            TextField(
              controller: _message,
              onChanged: (_) => setState(() {}),
              minLines: 3,
              maxLines: 7,
              maxLength: 20000,
              decoration: const InputDecoration(
                hintText: 'Paste the received message here…',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !_ready || _busy || _message.text.trim().isEmpty
                    ? null
                    : _analyzeMessage,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Analyze message'),
              ),
            ),
          ],
        ),
      ),
      _AnalysisCard(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Email PDF analysis',
        subtitle: 'Download or print the email as PDF, then upload it here.',
        child: OutlinedButton.icon(
          onPressed: _ready && !_busy ? _pickPdf : null,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Choose email PDF'),
        ),
      ),
      _AnalysisCard(
        icon: Icons.link_rounded,
        title: 'Hyperlink analysis',
        subtitle:
            'Checks shortening services, redirects, destination changes, and unsafe hosts.',
        child: Column(
          children: [
            TextField(
              controller: _link,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.com/path',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !_ready || _busy || _link.text.trim().isEmpty
                    ? null
                    : () => _run(() => widget.service.analyzeUrl(_link.text)),
                icon: const Icon(Icons.travel_explore_rounded),
                label: const Text('Inspect destination'),
              ),
            ),
          ],
        ),
      ),
      Row(
        children: [
          Expanded(
            child: _FileAction(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Scan QR',
              body: 'Open the camera to scan a QR code and see its report.',
              onTap: _ready && !_busy ? _scanQr : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FileAction(
              icon: Icons.screenshot_monitor_rounded,
              title: 'Screenshot',
              body: 'Upload a PNG, JPEG, or WebP for visual scam analysis.',
              onTap: _ready && !_busy ? _pickScreenshot : null,
            ),
          ),
        ],
      ),
      if (_busy) ...[
        const SizedBox(height: 18),
        const LinearProgressIndicator(),
      ],
      if (_error != null) ...[
        const SizedBox(height: 16),
        _Notice(text: _error!, error: true),
      ],
      if (_result != null) ...[
        const SizedBox(height: 16),
        AnalysisResultView(
          result: _result!,
          bridge: widget.bridge,
          service: widget.service,
        ),
      ],
      if (_combined != null) ...[
        const SizedBox(height: 16),
        AnalysisResultView(
          result: _combined!.primary,
          title: _combined!.primaryLabel,
          bridge: widget.bridge,
          service: widget.service,
        ),
        if (_combined!.links.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Links in this message (${_combined!.links.length})',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Each link is checked on its own — a safe-sounding message can '
            'still carry a dangerous link.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          ..._combined!.links.map(_linkCard),
        ],
      ],
    ],
  );

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

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF006D77)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(subtitle),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _FileAction extends StatelessWidget {
  const _FileAction({
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF006D77)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFE8E6) : const Color(0xFFE6F4F1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text),
  );
}

