class UpiPaymentRequest {
  const UpiPaymentRequest({
    required this.upiId,
    required this.payeeName,
    required this.amount,
    required this.note,
    required this.rawValue,
  });

  final String upiId;
  final String payeeName;
  final double amount;
  final String note;
  final String rawValue;

  static UpiPaymentRequest? tryParse(String rawValue) {
    final uri = Uri.tryParse(rawValue.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'upi') return null;
    final upiId = uri.queryParameters['pa']?.trim() ?? '';
    if (upiId.isEmpty) return null;
    return UpiPaymentRequest(
      upiId: upiId,
      payeeName: uri.queryParameters['pn']?.trim().isNotEmpty == true
          ? uri.queryParameters['pn']!.trim()
          : 'Unknown receiver',
      amount: double.tryParse(uri.queryParameters['am'] ?? '') ?? 0,
      note: uri.queryParameters['tn']?.trim() ?? '',
      rawValue: rawValue,
    );
  }
}
