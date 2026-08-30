import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';

/// Shared risk-report card used by the security analysis tab, the QR report
/// screen, and per-link results, so every surface renders verdicts the same way.
class AnalysisResultView extends StatelessWidget {
  const AnalysisResultView({
    super.key,
    required this.result,
    this.title,
    this.compact = false,
  });

  final SecurityAnalysis result;
  final String? title;
  final bool compact;

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
        padding: EdgeInsets.all(compact ? 13 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
            ],
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
                      fontSize: compact ? 15 : 18,
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
                '${url.redirectCount} redirect(s) · '
                '${url.usesShortener ? 'shortener detected' : 'no known shortener'} · '
                '${url.hostChanged ? 'destination changed' : 'destination stable'} · '
                '${url.reachable ? 'reachable' : 'unreachable'}',
                style: const TextStyle(fontSize: 12),
              ),
              if (url.redirectChain.length > 1) ...[
                const SizedBox(height: 6),
                const Text(
                  'Redirect path',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
                ...url.redirectChain.map(
                  (hop) => Text(
                    '↳ $hop',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
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
