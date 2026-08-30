import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kavasam_mobile/models/phone.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';

/// Guardian pairing tab. Both the protected (elderly) phone and the guardian
/// phone run the same app: the protected phone shows a 6-character code, the
/// guardian enters it to link, and danger reports appear here — all tied to a
/// single MongoDB-backed pairing so devices never cross-connect.
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({
    super.key,
    required this.service,
    required this.bridge,
    required this.deviceId,
  });

  final CloudSafetyService service;
  final PhoneBridge bridge;
  final String deviceId;

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  PairingStatus _protected = const PairingStatus();
  GuardianViewerConfig _viewer = const GuardianViewerConfig();
  List<GuardianReport> _reports = const [];
  List<HighRiskAnalysis> _local = const [];
  String _alias = '';
  bool _loading = true;
  bool _busy = false;
  String? _message;

  bool get _ready => widget.service.isConfigured;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final config = await widget.bridge.getGuardianConfig();
    final viewer = await widget.bridge.getGuardianViewerConfig();
    final local = await widget.bridge.getHighRiskAnalyses();
    var protected = const PairingStatus();
    var reports = <GuardianReport>[];
    var message = _message;
    if (_ready) {
      try {
        protected = await widget.service.pairingStatus(widget.deviceId);
      } on Object {
        // Pairing status is best-effort; the tab still works offline.
      }
      if (viewer.isSignedIn) {
        try {
          reports = await widget.service.pairingReports(viewer.sessionToken);
        } on Object catch (error) {
          message = error.toString();
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _alias = config.primaryAlias;
      _protected = protected;
      _viewer = viewer;
      _local = local;
      _reports = reports;
      _message = message;
      _loading = false;
    });
  }

  Future<void> _createCode() async {
    var alias = _alias;
    if (alias.isEmpty) {
      alias = await _promptText(
        title: 'Set up guardian protection',
        label: 'Your name (shown to your guardian)',
        hint: 'Example: Amma',
        maxLength: 48,
      );
      if (alias.isEmpty) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.bridge.saveGuardianConfig(GuardianConfig(primaryAlias: alias));
      final status = await widget.service.pairingCode(widget.deviceId, alias);
      if (!mounted) return;
      setState(() {
        _alias = alias;
        _protected = status;
        _message = 'Share this code with the person who will watch over you.';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    setState(() => _busy = true);
    try {
      final status = await widget.service.pairingUnlink(widget.deviceId);
      if (mounted) {
        setState(() {
          _protected = status;
          _message = 'Guardian code reset. Generate a new one to re-link.';
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final alert = TextEditingController();
    final values = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link to a family member'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the 6-character code shown on their Kavasam phone.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Guardian code',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: name,
                maxLength: 48,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: alert,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Alert to (optional)',
                  hintText: 'Telegram @username or email for n8n alerts',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              code.text.trim(),
              name.text.trim(),
              alert.text.trim(),
            )),
            child: const Text('Link'),
          ),
        ],
      ),
    );
    code.dispose();
    name.dispose();
    alert.dispose();
    if (values == null) return;
    if (values.$1.length != 6 || values.$2.isEmpty) {
      setState(() => _message = 'Enter the 6-character code and your name.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final claim = await widget.service.pairingClaim(
        code: values.$1,
        guardianDeviceId: widget.deviceId,
        guardianAlias: values.$2,
        alertHandle: values.$3,
      );
      await widget.bridge.saveGuardianViewerConfig(
        GuardianViewerConfig(
          guardianId: claim.pairingId,
          primaryAlias: claim.elderlyAlias,
          sessionToken: claim.sessionToken,
          expiresAt: claim.expiresAt,
        ),
      );
      _message = claim.message;
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await widget.bridge.clearGuardianViewerConfig();
    await _load();
  }

  Future<String> _promptText({
    required String title,
    required String label,
    required String hint,
    required int maxLength,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value ?? '';
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      key: const PageStorageKey('guardian'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
      children: [
        Text(
          'Guardian',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0B1F3A),
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Link two Kavasam phones with a code. The guardian sees danger '
          'reports here and gets an alert when a scam call is detected.',
        ),
        if (!_ready) ...[
          const SizedBox(height: 12),
          const _Status(
            text:
                'Connect the Kavasam gateway (build with the gateway URL) to use guardian pairing.',
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          _Status(text: _message!),
        ],
        const SizedBox(height: 14),
        _Section(
          icon: Icons.elderly_rounded,
          title: 'This phone is protected',
          child: _protectedBody(),
        ),
        _Section(
          icon: Icons.family_restroom_rounded,
          title: 'I am the guardian',
          child: _guardianBody(),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_viewer.isSignedIn) ...[
          const SizedBox(height: 8),
          const Text(
            'Danger reports',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          if (_reports.isEmpty && !_loading)
            const _Status(text: 'No danger reports have been received yet.')
          else
            ..._reports.map((report) => _ReportCard(report: report)),
        ],
        const SizedBox(height: 16),
        const Text(
          'On this phone · dangerous tracked calls (score above 80)',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (_local.isEmpty && !_loading)
          const _Status(text: 'No dangerous tracked-call analyses are stored.')
        else
          ..._local.map(
            (item) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFFDAD6),
                  child: Text('${item.risk}'),
                ),
                title: Text(
                  item.displayName.isEmpty ? item.number : item.displayName,
                ),
                subtitle: Text(
                  '${item.summary}\nExpires ${_date(item.expiresAt)}',
                ),
                isThreeLine: true,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _protectedBody() {
    if (_protected.hasCode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your guardian code'),
          const SizedBox(height: 6),
          Row(
            children: [
              SelectableText(
                _protected.code,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: Color(0xFF176BCE),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _protected.code));
                  setState(() => _message = 'Code copied.');
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _protected.isLinked
                ? 'Linked to ${_protected.guardianAlias.isEmpty ? 'your guardian' : _protected.guardianAlias}. They will get danger alerts.'
                : 'Waiting for your guardian to enter this code.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
              TextButton(
                onPressed: _busy ? null : _unlink,
                child: const Text('Reset code'),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Generate a code and share it with a trusted family member so they '
          'can watch over your calls.',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: !_ready || _busy ? null : _createCode,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Create guardian code'),
        ),
      ],
    );
  }

  Widget _guardianBody() {
    if (_viewer.isSignedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Protecting ${_viewer.primaryAlias}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh reports'),
              ),
              TextButton(
                onPressed: _loading ? null : _signOut,
                child: const Text('Unlink'),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter the 6-character code from the phone you want to protect. '
          'A revocable session is stored on this phone — never their call audio.',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: !_ready || _busy ? null : _link,
          icon: const Icon(Icons.link_rounded),
          label: const Text('Link with a code'),
        ),
      ],
    );
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => TextEditingValue(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
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
              const SizedBox(width: 9),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFE6F4F1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});
  final GuardianReport report;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFE8E6),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFB3261E),
        foregroundColor: Colors.white,
        child: Text('${report.risk}'),
      ),
      title: Text('${report.primaryAlias} · caller ••••${report.callerLast4}'),
      subtitle: Text('${report.summary}\n${report.occurredAt.toLocal()}'),
      isThreeLine: true,
    ),
  );
}
