import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/genapp_branding.dart';
import '../services/ota_update_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
    required this.initialBackendUrl,
    required this.initialAppgenBackendUrl,
    required this.onSaveBackendUrl,
    required this.onSaveAppgenBackendUrl,
  });

  final String initialBackendUrl;
  final String initialAppgenBackendUrl;
  final ValueChanged<String> onSaveBackendUrl;
  final ValueChanged<String> onSaveAppgenBackendUrl;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final TextEditingController _controller;
  late final TextEditingController _appgenController;
  bool _loadingOta = false;
  bool _checkingBackend = false;
  String? _backendCheckMessage;
  bool? _backendCheckOk;
  String? _otaError;
  OtaPublishedVersion? _otaVersion;

  // OTA par APPGEN (2026-11-23, SIG-20261123073802) : le backend propre de la
  // GENAPP n'est ni démarré ni joignable pour une GENAPP sans backend.
  String get _otaBaseUrl => otaBaseUrlViaAppgen(
        _appgenController.text.trim(),
        GenappBranding.slug,
      );

  OtaUpdateService get _otaService => OtaUpdateService(baseUrl: _otaBaseUrl);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBackendUrl);
    _appgenController =
        TextEditingController(text: widget.initialAppgenBackendUrl);
    _refreshOta();
  }

  @override
  void didUpdateWidget(covariant AdminScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBackendUrl != widget.initialBackendUrl) {
      _controller.text = widget.initialBackendUrl;
      _refreshOta();
    }
    if (oldWidget.initialAppgenBackendUrl != widget.initialAppgenBackendUrl) {
      _appgenController.text = widget.initialAppgenBackendUrl;
      _refreshOta();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _appgenController.dispose();
    super.dispose();
  }

  Future<void> _refreshOta() async {
    setState(() {
      _loadingOta = true;
      _otaError = null;
    });
    try {
      final version = await _otaService.fetchPublishedVersion();
      if (!mounted) {
        return;
      }
      setState(() {
        _otaVersion = version;
        _loadingOta = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingOta = false;
        _otaVersion = null;
        _otaError = error.toString();
      });
    }
  }

  Future<void> _checkBackend() async {
    final rawBaseUrl = _controller.text.trim();
    final baseUri = Uri.tryParse(rawBaseUrl);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      setState(() {
        _backendCheckOk = false;
        _backendCheckMessage = 'URL backend invalide.';
      });
      return;
    }
    final healthUri = baseUri.replace(
      path: _joinPath(baseUri.path, 'health'),
      query: '',
    );
    setState(() {
      _checkingBackend = true;
      _backendCheckOk = null;
      _backendCheckMessage = null;
    });
    try {
      final response = await http.get(healthUri).timeout(
            const Duration(seconds: 8),
          );
      if (!mounted) {
        return;
      }
      final body = response.body.trim();
      final isOk = response.statusCode >= 200 && response.statusCode < 300;
      setState(() {
        _checkingBackend = false;
        _backendCheckOk = isOk;
        _backendCheckMessage =
            'HTTP ${response.statusCode}${body.isEmpty ? '' : ' - $body'}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _checkingBackend = false;
        _backendCheckOk = false;
        _backendCheckMessage = error.toString();
      });
    }
  }

  Future<void> _downloadOtaApk() async {
    final version = _otaVersion;
    if (version == null || version.apkUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun APK OTA disponible.')),
      );
      return;
    }
    final uri = resolveApkUrl(_otaBaseUrl, version.apkUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('URL OTA invalide: ${version.apkUrl}')),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) {
      return;
    }
    if (launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Téléchargement OTA ouvert.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Impossible d’ouvrir le téléchargement OTA.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Admin',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Paramètres invariants de la GENAPP.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'URL backend GENAPP',
            hintText: 'http://127.0.0.1:8100',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            widget.onSaveBackendUrl(_controller.text.trim());
            FocusScope.of(context).unfocus();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('URL backend enregistrée.')),
            );
            _refreshOta();
          },
          child: const Text('Enregistrer'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _checkingBackend ? null : _checkBackend,
          icon: const Icon(Icons.network_check_outlined),
          label:
              Text(_checkingBackend ? 'Test en cours...' : 'Tester le backend'),
        ),
        if (_backendCheckMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _backendCheckMessage!,
            style: TextStyle(
              color: _backendCheckOk == true
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Signalements',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _appgenController,
          decoration: const InputDecoration(
            labelText: 'URL backend APPGEN',
            hintText: 'http://127.0.0.1:8000',
            border: OutlineInputBorder(),
            helperText:
                'APPGEN reçoit les tickets terrain émis depuis cette GENAPP.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            widget.onSaveAppgenBackendUrl(_appgenController.text.trim());
            FocusScope.of(context).unfocus();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('URL APPGEN enregistrée.')),
            );
          },
          child: const Text('Enregistrer APPGEN'),
        ),
        const SizedBox(height: 16),
        Text(
          'OTA',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_loadingOta) const LinearProgressIndicator(),
        if (_otaVersion != null) ...[
          Text('Version publiée: ${_otaVersion!.label}'),
          const SizedBox(height: 4),
          SelectableText('APK: ${_otaVersion!.apkUrl}'),
        ],
        if (_otaError != null)
          Text(
            _otaError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loadingOta ? null : _refreshOta,
              icon: const Icon(Icons.refresh),
              label: const Text('Rafraîchir OTA'),
            ),
            OutlinedButton.icon(
              onPressed: _loadingOta ? null : _downloadOtaApk,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Télécharger APK OTA'),
            ),
          ],
        ),
      ],
    );
  }
}

String _joinPath(String basePath, String suffix) {
  final normalizedBase = basePath.trim();
  final normalizedSuffix = suffix.trim();
  if (normalizedBase.isEmpty || normalizedBase == '/') {
    return '/$normalizedSuffix';
  }
  return '${normalizedBase.replaceFirst(RegExp(r'/+$'), '')}/$normalizedSuffix';
}
