import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/risk_result.dart';
import 'package:kavasam_mobile/models/upi_payment_request.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/risk_result_card.dart';
import 'package:kavasam_mobile/widgets/incident_actions.dart';
import 'package:kavasam_mobile/widgets/spoken_warning_button.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrGuardScreen extends StatefulWidget {
  const QrGuardScreen({super.key, required this.apiClient});

  final KavasamApiClient apiClient;

  @override
  State<QrGuardScreen> createState() => _QrGuardScreenState();
}

class _QrGuardScreenState extends State<QrGuardScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
    autoZoom: true,
  );
  String? _rawValue;
  UpiPaymentRequest? _payment;
  RiskResult? _result;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (_rawValue != null || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    await _scanner.stop();
    setState(() {
      _rawValue = value;
      _payment = UpiPaymentRequest.tryParse(value);
      _loading = true;
      _error = null;
    });
    try {
      final payment = _payment;
      final result = payment == null
          ? await widget.apiClient.analyzeMessage(
              text: value,
              language: 'English',
            )
          : await widget.apiClient.checkPayment(
              upiId: payment.upiId,
              merchantName: payment.payeeName,
              amount: payment.amount,
              context: payment.note,
            );
      if (mounted) setState(() => _result = result);
    } on KavasamApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _rawValue = null;
      _payment = null;
      _result = null;
      _error = null;
    });
    await _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PayGuard QR Scan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              _rawValue == null
                  ? 'Point at a payment QR'
                  : 'Payment destination decoded',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _rawValue == null
                  ? 'Kavasam checks who will receive the money before you open a UPI app.'
                  : 'No payment has been opened or authorized.',
            ),
            const SizedBox(height: 20),
            if (_rawValue == null)
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: 360,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(controller: _scanner, onDetect: _detected),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 230,
                            height: 230,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _DecodedPayment(payment: _payment, rawValue: _rawValue!),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _scanAgain,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan another QR'),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 28),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 10),
              const Center(
                child: Text('Checking receiver and payment signals…'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 18),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 24),
              RiskResultCard(result: _result!),
              const SizedBox(height: 12),
              SpokenWarningButton(
                text: _result!.warning,
                language: 'English',
                apiClient: widget.apiClient,
              ),
              const SizedBox(height: 12),
              IncidentActions(apiClient: widget.apiClient, result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DecodedPayment extends StatelessWidget {
  const _DecodedPayment({required this.payment, required this.rawValue});

  final UpiPaymentRequest? payment;
  final String rawValue;

  @override
  Widget build(BuildContext context) {
    final item = payment;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: item == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Non-UPI QR content',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(rawValue),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.payeeName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                _Detail(label: 'UPI ID', value: item.upiId),
                _Detail(
                  label: 'Amount',
                  value: item.amount > 0
                      ? '₹${item.amount.toStringAsFixed(2)}'
                      : 'Entered in payment app',
                ),
                if (item.note.isNotEmpty)
                  _Detail(label: 'Note', value: item.note),
              ],
            ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
