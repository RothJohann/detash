class RuntimeConfig {
  const RuntimeConfig._();

  static const String defaultBackendUrl = 'http://100.85.10.28:8001';
  static const String defaultAppgenBackendUrl = "http://100.85.10.28:8000";

  // Monétisation — affiliation (S113). Injectés à la génération de la GENAPP,
  // éditables ensuite. Vide = affiliation inactive.
  static const String affiliationNetwork = "amazon";
  static const String affiliationTag = "idnsol0d-21";

  // Build épuré / publiable (S026, D-038). Fixé au build via
  // --dart-define=EPUREE=true : masque le dogfooding (Admin, OTA, signalement).
  // Défaut false = build dogfooding.
  static const bool epuree = bool.fromEnvironment('EPUREE', defaultValue: false);
}
