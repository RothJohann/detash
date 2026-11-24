import 'dart:convert';

import 'package:http/http.dart' as http;

class OtaPublishedVersion {
  const OtaPublishedVersion({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;

  factory OtaPublishedVersion.fromJson(Map<String, dynamic> json) {
    return OtaPublishedVersion(
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
      versionName: json['versionName']?.toString() ?? '-',
      apkUrl: json['apkUrl']?.toString() ?? '',
    );
  }

  String get label => '$versionName+$versionCode';
}

/// Adresse OTA d'une GENAPP servie par APPGEN (2026-11-23) : le téléphone joint
/// déjà APPGEN, la GENAPP n'a plus besoin de son propre serveur pour se mettre
/// à jour.
String otaBaseUrlViaAppgen(String appgenUrl, String slug) {
  final base = appgenUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return '$base/genapps/template/projects/${Uri.encodeComponent(slug)}';
}

/// `apkUrl` peut être relatif au serveur (« /download/latest.apk ») : le
/// résoudre contre l'adresse OTA, sinon le lien ne s'ouvre pas.
Uri? resolveApkUrl(String baseUrl, String apkUrl) {
  final apk = Uri.tryParse(apkUrl.trim());
  if (apk == null || apkUrl.trim().isEmpty) {
    return null;
  }
  if (apk.hasScheme) {
    return apk;
  }
  final base = Uri.tryParse(baseUrl.trim());
  return base == null || !base.hasScheme ? null : base.resolveUri(apk);
}

class OtaUpdateService {
  OtaUpdateService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<OtaPublishedVersion> fetchPublishedVersion() async {
    final response = await _client.get(Uri.parse('$baseUrl/version'));
    if (response.statusCode != 200) {
      throw StateError(_extractErrorMessage(response));
    }
    return OtaPublishedVersion.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) {
        final detail = parsed['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail;
        }
        if (detail != null) {
          return detail.toString();
        }
      }
    } catch (_) {
      // fallback below
    }
    return 'Erreur API ${response.statusCode} sur $baseUrl';
  }
}
