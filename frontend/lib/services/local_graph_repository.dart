import 'dart:convert';

import 'package:flutter/services.dart';

class LocalGraphRepository {
  const LocalGraphRepository();

  Future<Map<String, dynamic>> loadDefaultGraph() async {
    final raw = await rootBundle
        .loadString('assets/graphs/genapp-template-onboarding-v0.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Le graphe GENAPP doit être un objet JSON.');
    }
    return decoded;
  }
}
