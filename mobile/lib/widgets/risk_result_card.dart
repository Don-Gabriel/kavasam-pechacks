import 'package:flutter/material.dart';
import 'package:kavasam_mobile/core/theme.dart';
import 'package:kavasam_mobile/models/risk_result.dart';

class RiskResultCard extends StatelessWidget {
  const RiskResultCard({super.key, required this.result});

  final RiskResult result;

  @override
  Widget build(BuildContext context) {
    final isDanger = result.score >= 60;
    final accent = isDanger ? KavasamColors.danger : KavasamColors.forest;
    final surface = isDanger ? KavasamColors.dangerSoft : KavasamColors.mint;
    return Semantics(
      liveRegion: true,
      label: 'Risk result ${result.score} out of 100, ${result.level}',
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  foregroundColor: accent,
                  child: Text(
                    '${result.score}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${result.level} RISK',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(result.fraudType.replaceAll('_', ' ')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              result.warning,
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.35),
            ),
            const SizedBox(height: 16),
            ...result.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 19, color: accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            Text(
              'What to do',
              style: TextStyle(color: accent, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(result.recommendedAction, style: const TextStyle(height: 1.4)),
          ],
        ),
      ),
    );
  }
}
