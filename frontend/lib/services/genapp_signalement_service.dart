import 'dart:convert';

import 'package:http/http.dart' as http;

class GenappSignalementAttachmentDraft {
  const GenappSignalementAttachmentDraft({
    required this.filename,
    required this.contentType,
    required this.dataBase64,
  });

  final String filename;
  final String contentType;
  final String dataBase64;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'filename': filename,
      'contentType': contentType,
      'dataBase64': dataBase64,
    };
  }
}

class GenappTestRunnerRef {
  const GenappTestRunnerRef({
    required this.planId,
    required this.testId,
    required this.etapeNo,
  });

  final String planId;
  final String testId;
  final int etapeNo;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'planId': planId,
      'testId': testId,
      'etapeNo': etapeNo,
    };
  }
}

class GenappTestPlanOption {
  const GenappTestPlanOption({
    required this.planId,
    required this.title,
    required this.conformant,
    required this.caseCount,
  });

  final String planId;
  final String title;
  final bool conformant;
  final int caseCount;

  factory GenappTestPlanOption.fromJson(Map<String, dynamic> json) {
    return GenappTestPlanOption(
      planId: (json['planId'] ?? '').toString(),
      title: (json['title'] ?? json['planId'] ?? '').toString(),
      conformant: json['conformant'] == true,
      caseCount: (json['caseCount'] is num)
          ? (json['caseCount'] as num).toInt()
          : 0,
    );
  }
}

class GenappTestCaseOption {
  const GenappTestCaseOption({
    required this.idTest,
    required this.nomCas,
    required this.etapeNos,
  });

  final String idTest;
  final String nomCas;
  final List<int> etapeNos;

  factory GenappTestCaseOption.fromJson(Map<String, dynamic> json) {
    final steps = json['steps'];
    final etapes = <int>[];
    if (steps is List) {
      for (final step in steps) {
        if (step is Map<String, dynamic> && step['etapeNo'] is num) {
          etapes.add((step['etapeNo'] as num).toInt());
        }
      }
    }
    return GenappTestCaseOption(
      idTest: (json['idTest'] ?? '').toString(),
      nomCas: (json['nomCas'] ?? '').toString(),
      etapeNos: etapes,
    );
  }
}

class GenappSignalementDraft {
  const GenappSignalementDraft({
    required this.category,
    required this.comment,
    required this.genappSlug,
    required this.genappVersion,
    required this.backendUrl,
    this.logsText = '',
    this.currentScreen = 'GENAPP Signalements',
    this.attachments = const <GenappSignalementAttachmentDraft>[],
    this.testRunnerRef,
  });

  final String category;
  final String comment;
  final String genappSlug;
  final String genappVersion;
  final String backendUrl;
  final String logsText;
  final String currentScreen;
  final List<GenappSignalementAttachmentDraft> attachments;
  final GenappTestRunnerRef? testRunnerRef;

  Map<String, dynamic> toJson() {
    final context = <String, dynamic>{
      'origin': 'genapp_embedded_signalement',
      'genappSlug': genappSlug,
      'attachmentCount': attachments.length,
      'logsProvided': logsText.trim().isNotEmpty,
    };
    if (testRunnerRef != null) {
      context['testRunner'] = testRunnerRef!.toJson();
    }
    return <String, dynamic>{
      'category': category,
      'comment': comment,
      'targetScope': 'genapp',
      'genappSlug': genappSlug,
      'genappVersion': genappVersion,
      'backendUrl': backendUrl,
      'currentScreen': currentScreen,
      'logsText': logsText,
      'attachments': attachments.map((item) => item.toJson()).toList(),
      'context': context,
    };
  }
}

class GenappSignalementResult {
  const GenappSignalementResult({
    required this.id,
    required this.status,
  });

  final String id;
  final String status;

  factory GenappSignalementResult.fromJson(Map<String, dynamic> json) {
    final item = json['item'];
    final payload = item is Map<String, dynamic> ? item : json;
    return GenappSignalementResult(
      id: (payload['id'] ?? '').toString(),
      status: (payload['status'] ?? '').toString(),
    );
  }
}

class GenappSignalementService {
  GenappSignalementService(
      {required this.appgenBackendUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String appgenBackendUrl;
  final http.Client _client;

  Future<GenappSignalementResult> createSignalement(
    GenappSignalementDraft draft,
  ) async {
    final normalizedBase = appgenBackendUrl.replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse('$normalizedBase/appgen/signalements');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(draft.toJson()),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError(_extractErrorMessage(response));
    }
    return GenappSignalementResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<GenappTestPlanOption>> fetchTestPlans() async {
    final normalizedBase = appgenBackendUrl.replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse('$normalizedBase/appgen/testrunner/plans');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError(_extractErrorMessage(response));
    }
    final parsed = jsonDecode(response.body);
    final plans = (parsed is Map<String, dynamic>) ? parsed['plans'] : null;
    if (plans is! List) {
      return const <GenappTestPlanOption>[];
    }
    return plans
        .whereType<Map<String, dynamic>>()
        .map(GenappTestPlanOption.fromJson)
        .toList();
  }

  Future<List<GenappTestCaseOption>> fetchTestCampaign(String planId) async {
    final normalizedBase = appgenBackendUrl.replaceFirst(RegExp(r'/$'), '');
    final uri =
        Uri.parse('$normalizedBase/appgen/testrunner/campaigns/$planId');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError(_extractErrorMessage(response));
    }
    final parsed = jsonDecode(response.body);
    final cases = (parsed is Map<String, dynamic>) ? parsed['cases'] : null;
    if (cases is! List) {
      return const <GenappTestCaseOption>[];
    }
    return cases
        .whereType<Map<String, dynamic>>()
        .map(GenappTestCaseOption.fromJson)
        .toList();
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) {
        final detail = parsed['detail'];
        if (detail != null) {
          return detail.toString();
        }
      }
    } catch (_) {
      // fallback below
    }
    return 'Erreur APPGEN ${response.statusCode}';
  }
}
