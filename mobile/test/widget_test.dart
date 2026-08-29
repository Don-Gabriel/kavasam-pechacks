import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kavasam_mobile/main.dart';
import 'package:kavasam_mobile/services/api_client.dart';

void main() {
  testWidgets('home presents autonomous and active protection journeys', (
    tester,
  ) async {
    await tester.pumpWidget(KavasamApp(apiClient: _mockApiClient()));

    expect(find.text('KAVASAM'), findsOneWidget);
    expect(find.text('Automatic Android shields'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Scan a payment QR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Scan a payment QR'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Check a suspicious message'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Protect this call'), findsOneWidget);
    expect(find.text('Check a suspicious message'), findsOneWidget);
  });

  testWidgets('Paatti Mode remains user-controlled', (tester) async {
    await tester.pumpWidget(KavasamApp(apiClient: _mockApiClient()));
    final switchFinder = find.byType(Switch);

    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
  });
}

KavasamApiClient _mockApiClient() {
  return KavasamApiClient(
    client: MockClient((_) async => http.Response('{}', 200)),
    baseUrl: 'http://test.local',
  );
}
