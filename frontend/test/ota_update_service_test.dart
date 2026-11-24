import 'package:flutter_test/flutter_test.dart';
import 'package:genapp_template_frontend/services/ota_update_service.dart';

// 2026-11-23 (SIG-20261123073802) : l'OTA de la GENAPP passe par APPGEN, et un
// apkUrl relatif (« /download/latest.apk ») ne s'ouvrait pas.
void main() {
  test('adresse OTA servie par APPGEN', () {
    expect(
      otaBaseUrlViaAppgen('http://192.0.2.10:8000/', 'detash'),
      'http://192.0.2.10:8000/genapps/template/projects/detash',
    );
  });

  test('apkUrl relatif résolu contre le serveur OTA', () {
    const base = 'http://192.0.2.10:8000/genapps/template/projects/detash';
    expect(
      resolveApkUrl(
              base, '/genapps/template/projects/detash/download/latest.apk')
          .toString(),
      'http://192.0.2.10:8000/genapps/template/projects/detash/download/latest.apk',
    );
    expect(resolveApkUrl(base, 'https://ex.org/a.apk').toString(),
        'https://ex.org/a.apk');
    expect(resolveApkUrl(base, ''), isNull);
  });
}
