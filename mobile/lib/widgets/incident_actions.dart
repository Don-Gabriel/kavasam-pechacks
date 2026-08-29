import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/risk_result.dart';
import 'package:kavasam_mobile/services/api_client.dart';

class IncidentActions extends StatefulWidget {
  const IncidentActions({
    super.key,
    required this.apiClient,
    required this.result,
  });

  final KavasamApiClient apiClient;
  final RiskResult result;

  @override
  State<IncidentActions> createState() => _IncidentActionsState();
}

class _IncidentActionsState extends State<IncidentActions> {
  bool _alerting = false;
  bool _reporting = false;

  Future<void> _alertGuardian() async {
    setState(() => _alerting = true);
    try {
      final response = await widget.apiClient.alertGuardian(
        eventId: widget.result.eventId,
        message: '${widget.result.level} fraud risk: ${widget.result.warning}',
      );
      if (!mounted) return;
      final recipients = (response['recipients'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recipients > 0
                ? 'Guardian alert queued for $recipients trusted contact${recipients == 1 ? '' : 's'}.'
                : 'No guardian is linked yet. Add one from the home screen.',
          ),
        ),
      );
    } on KavasamApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _alerting = false);
    }
  }

  Future<void> _generateReport() async {
    setState(() => _reporting = true);
    try {
      final report = await widget.apiClient.generateReport(
        eventId: widget.result.eventId,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _ReportSheet(report: report),
      );
    } on KavasamApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _alerting ? null : _alertGuardian,
          icon: const Icon(Icons.family_restroom_outlined),
          label: Text(_alerting ? 'Alerting guardian…' : 'Alert my guardian'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _reporting ? null : _generateReport,
          icon: const Icon(Icons.description_outlined),
          label: Text(
            _reporting ? 'Preparing report…' : 'Prepare cybercrime report',
          ),
        ),
      ],
    );
  }
}

class _ReportSheet extends StatelessWidget {
  const _ReportSheet({required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final evidence = (report['evidence_list'] as List<dynamic>? ?? const [])
        .map((item) => item.toString());
    final actions =
        (report['recommended_complaint_details'] as List<dynamic>? ?? const [])
            .map((item) => item.toString());
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report draft ready',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              report['incident_summary']?.toString() ??
                  'Fraud incident evidence package',
            ),
            const SizedBox(height: 20),
            const Text(
              'Evidence included',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            ...evidence.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(item),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Next steps',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            ...actions.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.arrow_forward_rounded),
                title: Text(item),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.done),
              label: const Text('Keep this draft'),
            ),
          ],
        ),
      ),
    );
  }
}
