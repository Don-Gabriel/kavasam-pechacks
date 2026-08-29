import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:kavasam_mobile/models/incoming_evidence.dart';
import 'package:kavasam_mobile/models/risk_result.dart';
import 'package:kavasam_mobile/models/upi_payment_request.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/protection_scaffold.dart';
import 'package:kavasam_mobile/widgets/incident_actions.dart';
import 'package:kavasam_mobile/widgets/risk_result_card.dart';
import 'package:kavasam_mobile/widgets/spoken_warning_button.dart';

class EvidenceReviewScreen extends StatefulWidget {
  const EvidenceReviewScreen({
    super.key,
    required this.apiClient,
    required this.evidence,
  });

  final KavasamApiClient apiClient;
  final IncomingEvidence evidence;

  @override
  State<EvidenceReviewScreen> createState() => _EvidenceReviewScreenState();
}

class _EvidenceReviewScreenState extends State<EvidenceReviewScreen> {
  String _language = 'English';
  String _extractedText = '';
  bool _loading = true;
  String? _error;
  RiskResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      if (widget.evidence.isImage) {
        _extractedText = await _readImageText(widget.evidence.path!);
        _result = await widget.apiClient.analyzeImage(
          path: widget.evidence.path!,
          mimeType: widget.evidence.mimeType,
          context: [
            widget.evidence.text,
            _extractedText,
          ].where((item) => item.trim().isNotEmpty).join('\n'),
          language: _language,
        );
      } else {
        final payment = UpiPaymentRequest.tryParse(widget.evidence.text);
        if (payment != null) {
          _result = await widget.apiClient.checkPayment(
            upiId: payment.upiId,
            merchantName: payment.payeeName,
            amount: payment.amount,
            context: payment.note,
          );
        } else {
          _result = await widget.apiClient.analyzeMessage(
            text: widget.evidence.text,
            language: _language,
          );
        }
      }
    } on KavasamApiException catch (error) {
      _error = error.message;
    } on Exception {
      _error =
          'Kavasam could not inspect this evidence. Try a clearer screenshot.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _readImageText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProtectionScaffold(
      title: 'Automatic Safety Check',
      subtitle:
          'Received from ${widget.evidence.source}. Kavasam started checking it automatically.',
      children: [
        if (widget.evidence.isImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.file(
              File(widget.evidence.path!),
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 14),
        ] else
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              widget.evidence.text,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _language,
          decoration: const InputDecoration(labelText: 'Explain in'),
          items: const ['English', 'Tamil', 'Hindi']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: _loading
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _language = value);
                    _analyze();
                  }
                },
        ),
        if (_loading) ...[
          const SizedBox(height: 30),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          const Center(
            child: Text('Reading evidence and checking manipulation signals…'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 18),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _analyze,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 24),
          RiskResultCard(result: _result!),
          const SizedBox(height: 12),
          SpokenWarningButton(
            text: _result!.warning,
            language: _language,
            apiClient: widget.apiClient,
          ),
          const SizedBox(height: 12),
          IncidentActions(apiClient: widget.apiClient, result: _result!),
        ],
        if (_extractedText.isNotEmpty) ...[
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Text read on this device'),
            subtitle: const Text('Used as a privacy-preserving fallback'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_extractedText),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
