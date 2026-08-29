import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kavasam_mobile/main.dart';
import 'package:kavasam_mobile/services/api_client.dart';

void main() {
  testWidgets('home presents the three prevention journeys', (tester) async {
    await tester.pumpWidget(KavasamApp(apiClient: _mockApiClient()));

    expect(find.text('KAVASAM'), findsOneWidget);
    expect(find.text('Check a suspicious message'), findsOneWidget);
    expect(find.text('Check before you pay'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('Suspicious call mode'), findsOneWidget);
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
