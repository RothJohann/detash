import 'package:appgen_graph_runtime/appgen_graph_runtime.dart';
import 'package:flutter/material.dart';

import '../services/local_graph_repository.dart';

class WorkflowScreen extends StatefulWidget {
  const WorkflowScreen({
    super.key,
    required this.backendUrl,
  });

  final String backendUrl;

  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  final LocalGraphRepository _repository = const LocalGraphRepository();

  Map<String, dynamic>? _graph;
  GraphRuntimePayload? _payload;
  String? _error;
  bool _loading = true;

  /// Exécution locale du parcours (S136): la GENAPP publiée déroule son
  /// graphe sans backend joignable (D-033 topologie a).
  static const GraphRuntime _runtime = LocalGraphRuntime();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final graph = await _repository.loadDefaultGraph();
      await _runtime.validateGraph(graph);
      final payload = await _runtime.start(graph);
      if (!mounted) {
        return;
      }
      setState(() {
        _graph = graph;
        _payload = payload;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _answer(dynamic value) async {
    final graph = _graph;
    final payload = _payload;
    if (graph == null || payload == null) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final updated =
          await _runtime.answer(graph, payload.state.toJson(), value);
      if (!mounted) {
        return;
      }
      setState(() {
        _payload = updated;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _goBackOneStep() async {
    final payload = _payload;
    if (payload == null || payload.state.history.isEmpty) {
      return;
    }
    final newHistory = List<String>.from(payload.state.history);
    final previousNode = newHistory.removeLast();
    final state = payload.state.toJson()
      ..['current_node_id'] = previousNode
      ..['history'] = newHistory
      ..['is_finished'] = false
      ..['last_transition_reason'] = 'ui_back';
    final graph = _graph;
    if (graph == null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final updated = await _runtime.start(graph, state: state);
      if (!mounted) {
        return;
      }
      setState(() {
        _payload = updated;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _nodeLabelById(String nodeId) {
    final graph = _graph;
    final nodes = graph?['nodes'];
    if (nodes is! List) {
      return nodeId;
    }
    for (final rawNode in nodes) {
      if (rawNode is! Map) {
        continue;
      }
      final node = Map<String, dynamic>.from(rawNode);
      if ((node['id'] ?? '').toString() != nodeId) {
        continue;
      }
      final title = (node['title'] ?? '').toString().trim();
      if (title.isNotEmpty) {
        return title;
      }
      final prompt = (node['prompt'] ?? '').toString().trim();
      if (prompt.isNotEmpty) {
        return prompt;
      }
      final summary = (node['summary'] ?? '').toString().trim();
      if (summary.isNotEmpty) {
        return summary;
      }
      return nodeId;
    }
    return nodeId;
  }

  double _computeProgress() {
    final payload = _payload;
    final nodes = _graph?['nodes'];
    if (payload == null || nodes is! List || nodes.isEmpty) {
      return 0;
    }
    if (payload.isFinished) {
      return 1;
    }
    return (payload.state.history.toSet().length / nodes.length)
        .clamp(0, 1)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _payload == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Erreur runtime: $_error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _start,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final payload = _payload;
    if (payload == null) {
      return const Center(child: Text('Aucun payload runtime.'));
    }

    return GraphWorkflowView(
      payload: payload,
      graphTitle: 'Workflow de validation technique',
      graphDescription:
          'Validation du socle invariant rendu avec le composant partagé APPGEN/GENAPP.',
      projectId: 'GENAPP',
      backendUrl: widget.backendUrl,
      progress: _computeProgress(),
      loading: _loading,
      debugMode: false,
      workflowLabel: 'Workflow GENAPP',
      labelById: _nodeLabelById,
      onAnswer: _answer,
      onBack: _goBackOneStep,
      onRestart: _start,
    );
  }
}
