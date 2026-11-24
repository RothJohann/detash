class GraphRuntimeState {
  GraphRuntimeState({
    required this.graphId,
    required this.currentNodeId,
    required this.answers,
    required this.history,
    required this.isFinished,
    required this.lastTransitionReason,
  });

  final String graphId;
  final String currentNodeId;
  final Map<String, dynamic> answers;
  final List<String> history;
  final bool isFinished;
  final String? lastTransitionReason;

  factory GraphRuntimeState.fromJson(Map<String, dynamic> json) {
    return GraphRuntimeState(
      graphId: (json['graph_id'] ?? '').toString(),
      currentNodeId: (json['current_node_id'] ?? '').toString(),
      answers: Map<String, dynamic>.from(json['answers'] as Map? ?? const {}),
      history: (json['history'] as List? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      isFinished: json['is_finished'] == true,
      lastTransitionReason: json['last_transition_reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'graph_id': graphId,
      'current_node_id': currentNodeId,
      'answers': answers,
      'history': history,
      'is_finished': isFinished,
      'last_transition_reason': lastTransitionReason,
    };
  }
}

class GraphRuntimePayload {
  GraphRuntimePayload({
    required this.graphId,
    required this.isFinished,
    required this.state,
    required this.currentNode,
  });

  final String graphId;
  final bool isFinished;
  final GraphRuntimeState state;
  final Map<String, dynamic> currentNode;

  factory GraphRuntimePayload.fromJson(Map<String, dynamic> json) {
    return GraphRuntimePayload(
      graphId: (json['graph_id'] ?? '').toString(),
      isFinished: json['is_finished'] == true,
      state: GraphRuntimeState.fromJson(
        Map<String, dynamic>.from(json['state'] as Map),
      ),
      currentNode: Map<String, dynamic>.from(json['current_node'] as Map),
    );
  }
}

class GraphChoice {
  GraphChoice({required this.value, required this.label});

  final String value;
  final String label;

  factory GraphChoice.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] ?? '').toString();
    return GraphChoice(
      value: value,
      label: (json['label'] ?? value).toString(),
    );
  }
}
