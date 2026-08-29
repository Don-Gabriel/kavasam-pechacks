import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/risk_result.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/protection_scaffold.dart';
import 'package:kavasam_mobile/widgets/risk_result_card.dart';

class PaymentGuardScreen extends StatefulWidget {
  const PaymentGuardScreen({super.key, required this.apiClient});

  final KavasamApiClient apiClient;

  @override
  State<PaymentGuardScreen> createState() => _PaymentGuardScreenState();
}

class _PaymentGuardScreenState extends State<PaymentGuardScreen> {
  final _upiController = TextEditingController();
  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  final _contextController = TextEditingController();
  bool _loading = false;
  String? _error;
  RiskResult? _result;

  @override
  void dispose() {
    _upiController.dispose();
    _merchantController.dispose();
    _amountController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  void _loadDemo() {
    setState(() {
      _upiController.text = 'refund help';
      _merchantController.text = 'Support Store';
      _amountController.text = '50000';
      _contextController.text =
          'Pay urgent verification fee to release cashback';
    });
  }

  Future<void> _check() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_upiController.text.trim().isEmpty ||
        _merchantController.text.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      setState(() => _error = 'Enter a UPI ID, merchant, and valid amount.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.apiClient.checkPayment(
        upiId: _upiController.text.trim(),
        merchantName: _merchantController.text.trim(),
        amount: amount,
        context: _contextController.text.trim(),
      );
      if (mounted) setState(() => _result = result);
    } on KavasamApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProtectionScaffold(
      title: 'PayGuard',
      subtitle:
          'Pause before authorizing payment. Verify the destination and why money was requested.',
      children: [
        TextField(
          controller: _upiController,
          decoration: const InputDecoration(
            labelText: 'UPI ID',
            hintText: 'name@bank',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _merchantController,
          decoration: const InputDecoration(
            labelText: 'Merchant or receiver name',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '₹ ',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _contextController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Why are you paying?',
            hintText: 'Example: A caller asked for a verification fee',
            alignLabelWithHint: true,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loadDemo,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Use fake-payment demo'),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _loading ? null : _check,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(
            _loading ? 'Checking destination…' : 'Check before paying',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 24),
          RiskResultCard(result: _result!),
        ],
      ],
    );
  }
}
