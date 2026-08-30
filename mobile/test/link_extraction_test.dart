import 'package:flutter_test/flutter_test.dart';
import 'package:kavasam_mobile/models/security_analysis.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';

void main() {
  test('extracts distinct http/www links and trims trailing punctuation', () {
    final links = CloudSafetyService.extractLinks(
      'Your parcel is held. Pay at https://scam.example/pay, '
      'or visit www.scam.example. Again: https://scam.example/pay!',
    );
    expect(links, [
      'https://scam.example/pay',
      'www.scam.example',
    ]);
  });

  test('returns no links for plain text', () {
    expect(CloudSafetyService.extractLinks('Please call me back'), isEmpty);
  });

  test('caps the number of links analysed', () {
    final text = List.generate(
      10,
      (i) => 'https://site$i.example',
    ).join(' ');
    expect(CloudSafetyService.extractLinks(text).length, 5);
  });

  test('combined analysis reports the worst risk across payload and links', () {
    const safeMessage = SecurityAnalysis(
      risk: 10,
      level: 'low',
      category: 'ok',
      summary: 'looks fine',
      reasons: [],
      recommendedActions: [],
      indicators: [],
      source: 'rules-fallback',
      extractedTextPreview: '',
    );
    const dangerLink = SecurityAnalysis(
      risk: 92,
      level: 'critical',
      category: 'Suspicious link',
      summary: 'hidden destination',
      reasons: [],
      recommendedActions: [],
      indicators: [],
      source: 'rules-fallback',
      extractedTextPreview: '',
    );
    const combined = CombinedAnalysis(
      primary: safeMessage,
      primaryLabel: 'Message',
      links: [LinkAnalysis(url: 'https://x.example', result: dangerLink)],
    );
    expect(combined.worstRisk, 92);
  });
}
