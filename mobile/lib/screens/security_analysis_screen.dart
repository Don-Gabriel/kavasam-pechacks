import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';

class SecurityAnalysisScreen extends StatefulWidget {
  const SecurityAnalysisScreen({
    super.key,
    required this.service,
    required this.cloudConsent,
  });

  final CloudSafetyService service;
  final bool cloudConsent;

  @override
  State<SecurityAnalysisScreen> createState() => _SecurityAnalysisScreenState();
}

class _SecurityAnalysisScreenState extends State<SecurityAnalysisScreen> {
  final _message = TextEditingController();
  final _link = TextEditingController();
  SecurityAnalysis? _result;
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

  Future<void> _pickQr() async {
    final selection = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = selection?.files.single.path;
    if (path == null) return;
    final scanner = BarcodeScanner(formats: const [BarcodeFormat.qrCode]);
    try {
      final codes = await scanner.processImage(InputImage.fromFilePath(path));
      final content = codes
          .map((code) => code.rawValue?.trim())
          .whereType<String>()
          .firstOrNull;
      if (content == null || content.isEmpty) {
        setState(() => _error = 'No readable QR code was found in that image.');
        return;
      }
      final uri = Uri.tryParse(content);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        await _run(() => widget.service.analyzeUrl(content));
      } else {
        await _run(
          () => widget.service.analyzeContent(kind: 'qr', text: content),
        );
      }
    } finally {
      await scanner.close();
    }
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
        subtitle: 'Paste an SMS, chat message, or email text.',
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
                    : () => _run(
                        () => widget.service.analyzeContent(
                          kind: 'message',
                          text: _message.text,
                        ),
                      ),
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
              title: 'QR analysis',
              body: 'Choose a QR image. Its payload is decoded locally first.',
              onTap: _ready && !_busy ? _pickQr : null,
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
        _RiskResult(result: _result!),
      ],
    ],
  );
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

class _RiskResult extends StatelessWidget {
  const _RiskResult({required this.result});
  final SecurityAnalysis result;

  @override
  Widget build(BuildContext context) {
    final color = result.isDangerous
        ? const Color(0xFFB3261E)
        : result.risk >= 50
        ? const Color(0xFF9A6700)
        : const Color(0xFF157347);
    final url = result.urlAssessment;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isDangerous
                      ? Icons.dangerous_rounded
                      : Icons.verified_user_rounded,
                  color: color,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${result.isDangerous ? 'DANGEROUS' : result.level.toUpperCase()} · ${result.risk}/100',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.summary),
            if (url != null) ...[
              const SizedBox(height: 10),
              Text('Destination: ${url.finalHost}'),
              Text(
                '${url.redirectCount} redirect(s) · ${url.usesShortener ? 'shortener detected' : 'no known shortener'} · ${url.reachable ? 'reachable' : 'unreachable'}',
              ),
            ],
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Why', style: TextStyle(fontWeight: FontWeight.w900)),
              ...result.reasons.map((reason) => Text('• $reason')),
            ],
            if (result.recommendedActions.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'What to do',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              ...result.recommendedActions.map((action) => Text('• $action')),
            ],
            const SizedBox(height: 8),
            Text(
              'Analysis: ${result.source} · advisory result',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
