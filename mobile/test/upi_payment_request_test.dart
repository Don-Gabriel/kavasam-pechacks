import 'package:flutter_test/flutter_test.dart';
import 'package:kavasam_mobile/models/upi_payment_request.dart';

void main() {
  test('parses a real UPI payment URI without authorizing payment', () {
    final request = UpiPaymentRequest.tryParse(
      'upi://pay?pa=merchant%40okaxis&pn=Local%20Store&am=1250.50&tn=Order%2042',
    );

    expect(request, isNotNull);
    expect(request!.upiId, 'merchant@okaxis');
    expect(request.payeeName, 'Local Store');
    expect(request.amount, 1250.50);
    expect(request.note, 'Order 42');
  });

  test('rejects unrelated QR content', () {
    expect(UpiPaymentRequest.tryParse('https://example.com'), isNull);
  });
}
