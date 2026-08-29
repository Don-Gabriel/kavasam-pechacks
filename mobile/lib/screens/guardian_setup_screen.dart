import 'package:flutter/material.dart';
import 'package:kavasam_mobile/services/api_client.dart';
import 'package:kavasam_mobile/widgets/protection_scaffold.dart';

class GuardianSetupScreen extends StatefulWidget {
  const GuardianSetupScreen({super.key, required this.apiClient});
  final KavasamApiClient apiClient;

  @override
  State<GuardianSetupScreen> createState() => _GuardianSetupScreenState();
}

class _GuardianSetupScreenState extends State<GuardianSetupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+91');
  bool _loading = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    if (_name.text.trim().isEmpty ||
        !RegExp(r'^\+?[1-9]\d{9,14}$').hasMatch(_phone.text.trim())) {
      setState(
        () =>
            _error = 'Enter a name and a valid phone number with country code.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await widget.apiClient.addGuardian(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
      );
      if (mounted) {
        setState(
          () => _message =
              '${response['guardian_name']} is linked. Approval status: ${response['status']}.',
        );
      }
    } on KavasamApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProtectionScaffold(
      title: 'Trusted Guardian',
      subtitle:
          'Choose someone who can help verify suspicious requests. Kavasam never gives them control of your phone or money.',
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Guardian name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _link,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text(_loading ? 'Linking…' : 'Link trusted guardian'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5EE),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 12),
                Expanded(child: Text(_message!)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
