import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../config/runtime_config.dart';
import '../models/affiliation_product.dart';

/// Module d'affiliation embarqué dans la GENAPP (S114).
///
/// Lit le tag injecté à la génération (`RuntimeConfig.affiliationTag`, S113),
/// construit les liens affiliés et enregistre les clics (best-effort). Le suivi
/// de revenu réel se fait côté réseau (ex. tableau de bord Amazon Associates via
/// le tag); le tracking backend est un bonus optionnel (S033).
class AffiliationService {
  AffiliationService({this.backendUrl = '', http.Client? client})
      : _client = client ?? http.Client();

  final String backendUrl;
  final http.Client _client;

  /// Vrai si l'affiliation a été configurée à la génération (tag non vide).
  static bool get isEnabled => RuntimeConfig.affiliationTag.trim().isNotEmpty;
  static String get network => RuntimeConfig.affiliationNetwork.trim().toLowerCase();
  static String get tag => RuntimeConfig.affiliationTag.trim();

  /// Mention de divulgation d'affiliation, obligatoire là où figurent les liens
  /// (Amazon Operating Agreement, FTC/UE). Vide si l'affiliation est inactive.
  static String get disclosure {
    if (tag.isEmpty) {
      return '';
    }
    if (network == 'amazon') {
      return 'En tant que Partenaire Amazon, je réalise un bénéfice sur les '
          'achats remplissant les conditions requises.';
    }
    return 'Cette page contient des liens affiliés : un achat peut me rémunérer, '
        'sans surcoût pour vous.';
  }

  Future<List<AffiliationProduct>> loadProducts() async {
    final raw = await rootBundle.loadString('assets/affiliation/products.json');
    final data = jsonDecode(raw);
    final rawList = (data is Map<String, dynamic> && data['products'] is List)
        ? data['products'] as List
        : const <dynamic>[];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(AffiliationProduct.fromJson)
        .where((product) => product.productUrl.trim().isNotEmpty)
        .toList();
  }

  /// Ajoute le tag d'affiliation au lien produit (Amazon: paramètre `tag`).
  /// Réseaux non gérés: lien inchangé (le tag est porté côté réseau) — à étendre.
  String affiliateUrl(String productUrl) {
    final currentTag = tag;
    if (currentTag.isEmpty) {
      return productUrl;
    }
    if (network == 'amazon') {
      final separator = productUrl.contains('?') ? '&' : '?';
      return '$productUrl${separator}tag=$currentTag';
    }
    return productUrl;
  }

  /// Enregistre un clic (best-effort). No-op silencieux sans backend joignable.
  Future<void> recordClick(String productId) async {
    final base = backendUrl.trim();
    if (base.isEmpty) {
      return;
    }
    try {
      await _client
          .post(
            Uri.parse('$base/affiliation/click'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'productId': productId,
              'network': network,
              'tag': tag,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort: l'attribution de revenu se fait côté réseau via le tag.
    }
  }
}
