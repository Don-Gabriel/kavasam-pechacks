import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/phone.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';

class GuardianScreen extends StatefulWidget {
  const GuardianScreen({
    super.key,
    required this.service,
    required this.bridge,
    required this.deviceId,
    required this.protectedUserConfig,
    required this.busy,
    required this.onSetup,
    required this.onRefresh,
    required this.onRemove,
  });

  final CloudSafetyService service;
  final PhoneBridge bridge;
  final String deviceId;
  final GuardianConfig protectedUserConfig;
  final bool busy;
  final Future<void> Function() onSetup;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRemove;

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  GuardianViewerConfig _viewer = const GuardianViewerConfig();
  List<GuardianReport> _reports = const [];
  List<HighRiskAnalysis> _local = const [];
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final viewer = await widget.bridge.getGuardianViewerConfig();
    final local = await widget.bridge.getHighRiskAnalyses();
    var reports = <GuardianReport>[];
    var message = _message;
    if (viewer.isSignedIn && widget.service.isConfigured) {
      try {
        reports = await widget.service.guardianReports(viewer.sessionToken);
      } on Object catch (error) {
        message = error.toString();
      }
    }
    if (!mounted) return;
    setState(() {
      _viewer = viewer;
      _local = local;
      _reports = reports;
      _message = message;
      _loading = false;
    });
  }

  Future<void> _claim() async {
    final phone = TextEditingController();
    final code = TextEditingController();
    final values = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open guardian reports'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Use the phone number that received the Kavasam invite and its 4-digit reference code.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Guardian phone number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Reference code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (phone.text.trim(), code.text.trim())),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    phone.dispose();
    code.dispose();
    if (values == null || values.$1.isEmpty || values.$2.length != 4) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final claim = await widget.service.claimGuardianRelationship(
        guardianPhone: values.$1,
        referenceCode: values.$2,
        guardianDeviceId: widget.deviceId,
      );
      _viewer = await widget.bridge.saveGuardianViewerConfig(
        GuardianViewerConfig(
          guardianId: claim.guardianId,
          primaryAlias: claim.primaryAlias,
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
          _loading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await widget.bridge.clearGuardianViewerConfig();
    await _load();
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
          'Set up help for this phone, or securely view danger reports for someone you protect.',
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          _Status(text: _message!),
        ],
        const SizedBox(height: 14),
        _Section(
          icon: Icons.elderly_rounded,
          title: 'This phone is protected',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.protectedUserConfig.isVerified
                    ? '${widget.protectedUserConfig.primaryAlias} · guardian verified'
                    : widget.protectedUserConfig.isConfigured
                    ? 'Invitation pending · ${widget.protectedUserConfig.guardianPhone}'
                    : 'No guardian has been added yet.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: widget.busy ? null : widget.onSetup,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(
                      widget.protectedUserConfig.isConfigured
                          ? 'Change guardian'
                          : 'Add guardian',
                    ),
                  ),
                  if (widget.protectedUserConfig.isConfigured &&
                      !widget.protectedUserConfig.isVerified)
                    OutlinedButton(
                      onPressed: widget.busy ? null : widget.onRefresh,
                      child: const Text('Check opt-in'),
                    ),
                  if (widget.protectedUserConfig.isConfigured)
                    TextButton(
                      onPressed: widget.busy ? null : widget.onRemove,
                      child: const Text('Remove'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'When a tracked call scores above 80, Kavasam keeps the report locally for 7 days and sends the verified guardian an SMS alert.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        _Section(
          icon: Icons.family_restroom_rounded,
          title: 'I am the guardian',
          child: _viewer.isSignedIn
              ? Column(
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
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter the invitation details once. Kavasam stores a revocable session token on this phone—not the protected person’s call audio.',
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _loading || !widget.service.isConfigured
                          ? null
                          : _claim,
                      icon: const Icon(Icons.verified_user_rounded),
                      label: const Text('Verify guardian access'),
                    ),
                  ],
                ),
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
            const _Status(text: 'No danger reports have been received.')
          else
            ..._reports.map((report) => _ReportCard(report: report)),
        ],
        const SizedBox(height: 16),
        const Text(
          'Stored on this phone · 7 days · scores above 80 only',
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

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
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
