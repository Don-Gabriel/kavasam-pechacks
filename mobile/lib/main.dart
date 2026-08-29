import 'package:flutter/material.dart';
import 'package:kavasam_mobile/core/theme.dart';
import 'package:kavasam_mobile/screens/home_screen.dart';
import 'package:kavasam_mobile/services/api_client.dart';

void main() {
  runApp(const KavasamApp());
}

class KavasamApp extends StatefulWidget {
  const KavasamApp({super.key, this.apiClient});

  final KavasamApiClient? apiClient;

  @override
  State<KavasamApp> createState() => _KavasamAppState();
}

class _KavasamAppState extends State<KavasamApp> {
  late final KavasamApiClient _apiClient;
  bool _paattiMode = false;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? KavasamApiClient();
  }

  @override
  void dispose() {
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kavasam',
      debugShowCheckedModeBanner: false,
      theme: KavasamTheme.light(paattiMode: _paattiMode),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_paattiMode ? 1.16 : 1)),
        child: child!,
      ),
      home: HomeScreen(
        apiClient: _apiClient,
        paattiMode: _paattiMode,
        onPaattiModeChanged: (enabled) => setState(() => _paattiMode = enabled),
      ),
    );
  }
}
