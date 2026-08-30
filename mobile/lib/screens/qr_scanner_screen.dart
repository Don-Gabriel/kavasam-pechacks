import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Live-camera QR scanner. Pops with the decoded payload string, or null if
/// the user backs out. Analysis happens on the screen that receives the value.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .where((raw) => raw != null && raw.isNotEmpty)
        .cast<String>()
        .firstOrNull;
    if (value == null) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text(
        'Scan QR code',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        IconButton(
          onPressed: () => _controller.toggleTorch(),
          icon: const Icon(Icons.flash_on_rounded),
          tooltip: 'Torch',
        ),
      ],
    ),
    body: Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) => Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.no_photography_rounded,
                    color: Colors.white70,
                    size: 48,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'The camera could not start.\n${error.errorDetails?.message ?? 'Grant camera permission in Settings and try again.'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Simple viewfinder frame.
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const Positioned(
          bottom: 60,
          left: 24,
          right: 24,
          child: Text(
            'Point the camera at a QR code. It scans automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
