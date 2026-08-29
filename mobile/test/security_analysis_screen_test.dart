import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kavasam_mobile/screens/security_analysis_screen.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';

void main() {
  testWidgets('typing enables message and hyperlink analysis actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecurityAnalysisScreen(
            service: CloudSafetyService(baseUrl: 'http://127.0.0.1:8080'),
            cloudConsent: true,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField).first,
      'Urgent: share your OTP now',
    );
    await tester.pump();
    final messageButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Analyze message'),
    );
    expect(messageButton.onPressed, isNotNull);

    await tester.drag(find.byType(ListView), const Offset(0, -1100));
    await tester.pumpAndSettle();
    final linkField = find.byType(TextField).last;
    await tester.enterText(linkField, 'https://example.com');
    await tester.pump();
    final linkButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Inspect destination'),
    );
    expect(linkButton.onPressed, isNotNull);
  });
}
