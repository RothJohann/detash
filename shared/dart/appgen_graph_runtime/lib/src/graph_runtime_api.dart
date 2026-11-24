import 'dart:convert';

import 'package:http/http.dart' as http;

import 'graph_runtime.dart';
import 'graph_runtime_models.dart';

/// Exécution déléguée au backend via `/graphs/runtime/*` (cockpit, aperçu).
class GraphRuntimeApi implements GraphRuntime {
  GraphRuntimeApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<void> validateGraph(Map<String, dynamic> graph) async {
    final uri = Uri.parse('$baseUrl/graphs/runtime/validate');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'graph': graph}),
    );
    if (response.statusCode != 200) {
      throw StateError(_extractErrorMessage(response));
    }
  }

  @override
  Future<GraphRuntimePayload> start(
    Map<String, dynamic> graph, {
    Map<String, dynamic>? state,
  }) async {
    final uri = Uri.parse('$baseUrl/graphs/runtime/start');
    final body = <String, dynamic>{'graph': graph};
    if (state != null) {
      body['state'] = state;
    }
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw StateError(_extractErrorMessage(response));
    }
    return GraphRuntimePayload.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<GraphRuntimePayload> answer(
    Map<String, dynamic> graph,
    Map<String, dynamic> state,
    dynamic value,
  ) async {
    final uri = Uri.parse('$baseUrl/graphs/runtime/answer');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'graph': graph, 'state': state, 'value': value}),
    );
    if (response.statusCode != 200) {
      throw StateError(_extractErrorMessage(response));
    }
    return GraphRuntimePayload.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final parsed = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = parsed['detail'];
      if (detail != null) {
        return detail.toString();
      }
    } catch (_) {
      // fallback
    }
    return 'Erreur API ${response.statusCode} sur $baseUrl';
  }
}
