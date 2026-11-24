/// Moteur appgen-graph exécutable en local (S136).
///
/// Port Dart de `src/shared/backend/graph_runtime/engine.py`, qui reste le
/// **contrat faisant autorité**. Toute évolution du moteur doit être portée des
/// deux côtés et couverte par les tests de parité
/// (`test/graph_engine_test.dart`, miroir de `tests/unit/test_graph_engine.py`).
///
/// Aucune I/O, aucune dépendance Flutter: une GENAPP déroule son parcours sans
/// backend joignable (D-033 topologie a, PA-20260825-024).
library;

const Set<String> supportedNodeTypes = <String>{
  'question',
  'action',
  'router',
  'end',
  'group',
  'collection',
};

/// Formats de question à une seule étape suivante (`next` chaîne). Les autres
/// (`choice`) portent une destination par choix (`next` map).
const Set<String> singleNextInputTypes = <String>{'text', 'multi', 'number'};

/// Graphe invalide: la définition ne respecte pas le contrat appgen-graph.
class GraphValidationError implements Exception {
  GraphValidationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Exécution impossible: l'état ou la valeur fournie ne permet pas de continuer.
class GraphRuntimeError implements Exception {
  GraphRuntimeError(this.message);

  final String message;

  @override
  String toString() => message;
}

dynamic _deepCopy(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCopy(entry.value),
    };
  }
  if (value is List) {
    return value.map<dynamic>(_deepCopy).toList();
  }
  return value;
}

/// Vérité au sens Python (`bool(value)`), pour l'opérateur `var` nu.
bool _truthy(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

/// État de progression d'une exécution de graphe.
class GraphState {
  GraphState({
    required this.graphId,
    required this.currentNodeId,
    Map<String, dynamic>? answers,
    List<String>? history,
    this.isFinished = false,
    this.lastTransitionReason,
  })  : answers = answers ?? <String, dynamic>{},
        history = history ?? <String>[];

  factory GraphState.fromJson(Map<String, dynamic> payload) {
    final rawAnswers = payload['answers'];
    final rawHistory = payload['history'];
    return GraphState(
      graphId: (payload['graph_id'] ?? '').toString(),
      currentNodeId: (payload['current_node_id'] ?? '').toString(),
      answers: rawAnswers is Map
          ? Map<String, dynamic>.from(_deepCopy(rawAnswers) as Map)
          : <String, dynamic>{},
      history: rawHistory is List
          ? rawHistory.map((item) => item.toString()).toList()
          : <String>[],
      isFinished: payload['is_finished'] == true,
      lastTransitionReason: payload['last_transition_reason']?.toString(),
    );
  }

  String graphId;
  String currentNodeId;
  Map<String, dynamic> answers;
  List<String> history;
  bool isFinished;
  String? lastTransitionReason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'graph_id': graphId,
      'current_node_id': currentNodeId,
      'answers': _deepCopy(answers),
      'history': List<String>.from(history),
      'is_finished': isFinished,
      'last_transition_reason': lastTransitionReason,
    };
  }

  GraphState copy() => GraphState.fromJson(toJson());
}

/// Exécute une définition appgen-graph (JSON déjà décodé).
class GraphEngine {
  GraphEngine(Map<String, dynamic> graphDefinition)
      : graphDefinition =
            Map<String, dynamic>.from(_deepCopy(graphDefinition) as Map) {
    graphId = (this.graphDefinition['id'] ?? '').toString().trim();
    startNodeId = (this.graphDefinition['start_node'] ?? '').toString().trim();
    final rawFallback =
        (this.graphDefinition['fallback_node'] ?? '').toString().trim();
    fallbackNodeId = rawFallback.isEmpty ? null : rawFallback;
    nodes = _normalizeNodes(this.graphDefinition['nodes']);
    _validateGraph();
  }

  final Map<String, dynamic> graphDefinition;
  late final String graphId;
  late final String startNodeId;
  late final String? fallbackNodeId;
  late final Map<String, Map<String, dynamic>> nodes;

  /// Crée ou restaure un état, puis résout routers et nœuds masqués.
  GraphState start([dynamic state]) {
    if (state == null) {
      return _advanceAuto(
        GraphState(graphId: graphId, currentNodeId: startNodeId),
      );
    }
    return loadState(state);
  }

  /// Charge un état sérialisé et le normalise pour ce graphe.
  GraphState loadState(dynamic state) {
    final GraphState runtimeState = state is GraphState
        ? state.copy()
        : GraphState.fromJson(Map<String, dynamic>.from(state as Map));

    if (runtimeState.graphId.isNotEmpty && runtimeState.graphId != graphId) {
      throw GraphRuntimeError(
        "State belongs to graph '${runtimeState.graphId}', "
        "expected '$graphId'.",
      );
    }
    runtimeState.graphId = graphId;

    if (!nodes.containsKey(runtimeState.currentNodeId)) {
      runtimeState.currentNodeId = startNodeId;
      runtimeState.history = <String>[];
      runtimeState.lastTransitionReason = 'state_reset_invalid_node';
      runtimeState.isFinished = false;
    }

    return _advanceAuto(runtimeState);
  }

  /// Sérialise l'état pour persistance ou transport.
  Map<String, dynamic> snapshot(GraphState state) => state.toJson();

  /// Copie sûre du nœud courant.
  Map<String, dynamic> currentNode(GraphState state) {
    return Map<String, dynamic>.from(
      _deepCopy(nodes[state.currentNodeId]) as Map,
    );
  }

  /// Avance d'un pas interactif depuis le nœud courant.
  GraphState answer(GraphState state, [dynamic value]) {
    final node = nodes[state.currentNodeId]!;
    final nodeType = node['type'].toString();

    final String nextId;
    final String reason;

    if (nodeType == 'end') {
      state.isFinished = true;
      state.lastTransitionReason = 'already_end';
      return state;
    }

    if (nodeType == 'router') {
      nextId = _resolveRouter(node, state.answers);
      reason = 'router';
    } else if (nodeType == 'action') {
      nextId = _requireString(node['next'], '${node['id']}.next');
      reason = 'action_complete';
    } else if (nodeType == 'question') {
      if ((node['input_type'] ?? 'choice').toString() == 'number') {
        value = parseNumberAnswer(node, value);
      }
      nextId = _resolveQuestionNext(node, value);
      final inputKey =
          _requireString(node['input_key'], '${node['id']}.input_key');
      state.answers[inputKey] = value;
      reason = 'question_answered';
    } else if (nodeType == 'group') {
      nextId = _requireString(node['next'], '${node['id']}.next');
      reason = 'group_resolved';
    } else if (nodeType == 'collection') {
      nextId = _requireString(node['next'], '${node['id']}.next');
      final outputKey =
          _requireString(node['output_key'], '${node['id']}.output_key');
      state.answers[outputKey] = _validateCollectionValue(node, value);
      reason = 'collection_submitted';
    } else {
      throw GraphRuntimeError('Unsupported node type at runtime: $nodeType');
    }

    _transition(state, nextId, reason);
    return _advanceAuto(state);
  }

  /// Traverse automatiquement les routers et les nœuds masqués par `when`.
  GraphState _advanceAuto(GraphState state) {
    var hops = 0;
    final maxHops = nodes.length * 4 < 1 ? 1 : nodes.length * 4;

    while (hops < maxHops) {
      final node = nodes[state.currentNodeId]!;
      final nodeType = node['type'].toString();

      if (nodeType == 'end') {
        state.isFinished = true;
        final reason = state.lastTransitionReason;
        if (reason == null || reason.isEmpty) {
          state.lastTransitionReason = 'reached_end';
        }
        return state;
      }

      if (_shouldSkipNode(node, state.answers)) {
        _transition(state, _resolveSkipTarget(node), 'node_skipped');
        hops += 1;
        continue;
      }

      if (nodeType == 'router') {
        _transition(state, _resolveRouter(node, state.answers), 'router');
        hops += 1;
        continue;
      }

      state.isFinished = false;
      return state;
    }

    throw GraphRuntimeError(
      'Auto-advance exceeded maximum hops; check for graph loops.',
    );
  }

  void _transition(GraphState state, String nextNodeId, String reason) {
    if (!nodes.containsKey(nextNodeId)) {
      throw GraphRuntimeError("Next node '$nextNodeId' is missing.");
    }
    state.history.add(state.currentNodeId);
    state.currentNodeId = nextNodeId;
    state.lastTransitionReason = reason;
    state.isFinished = false;
  }

  Map<String, Map<String, dynamic>> _normalizeNodes(dynamic rawNodes) {
    if (rawNodes is Map) {
      final result = <String, Map<String, dynamic>>{};
      for (final entry in rawNodes.entries) {
        final nodeId = entry.key.toString();
        if (entry.value is! Map) {
          throw GraphValidationError("Node '$nodeId' must be an object.");
        }
        final normalized =
            Map<String, dynamic>.from(_deepCopy(entry.value) as Map);
        normalized.putIfAbsent('id', () => nodeId);
        result[nodeId] = normalized;
      }
      return result;
    }

    if (rawNodes is List) {
      final result = <String, Map<String, dynamic>>{};
      for (var index = 0; index < rawNodes.length; index++) {
        final rawNode = rawNodes[index];
        if (rawNode is! Map) {
          throw GraphValidationError('Node at index $index must be an object.');
        }
        final normalized = Map<String, dynamic>.from(_deepCopy(rawNode) as Map);
        final nodeId = (normalized['id'] ?? '').toString().trim();
        if (nodeId.isEmpty) {
          throw GraphValidationError('Node at index $index has no id.');
        }
        if (result.containsKey(nodeId)) {
          throw GraphValidationError("Duplicate node id '$nodeId'.");
        }
        result[nodeId] = normalized;
      }
      return result;
    }

    throw GraphValidationError(
      "Graph field 'nodes' must be an array or object map.",
    );
  }

  void _validateGraph() {
    if (graphId.isEmpty) {
      throw GraphValidationError("Graph field 'id' is required.");
    }
    if (startNodeId.isEmpty) {
      throw GraphValidationError("Graph field 'start_node' is required.");
    }
    if (!nodes.containsKey(startNodeId)) {
      throw GraphValidationError(
        "Graph start_node '$startNodeId' does not exist in nodes.",
      );
    }
    final fallback = fallbackNodeId;
    if (fallback != null && !nodes.containsKey(fallback)) {
      throw GraphValidationError(
        "Graph fallback_node '$fallback' does not exist in nodes.",
      );
    }

    for (final entry in nodes.entries) {
      final node = entry.value;
      final nodeType =
          _requireString(node['type'], '${entry.key}.type').toLowerCase();
      if (!supportedNodeTypes.contains(nodeType)) {
        throw GraphValidationError(
          "Node '${entry.key}' has unsupported type '$nodeType'.",
        );
      }
      node['type'] = nodeType;

      if (nodeType == 'collection') {
        _validateCollectionSchema(node);
      }

      for (final ref in _collectNextReferences(node)) {
        if (!nodes.containsKey(ref)) {
          throw GraphValidationError(
            "Node '${entry.key}' points to missing node '$ref'.",
          );
        }
      }
    }
  }

  List<String> _collectNextReferences(Map<String, dynamic> node) {
    final nodeType = node['type'].toString();
    final nodeId = node['id'];
    final refs = <String>[];

    final defaultNext = node['default_next'];
    if (defaultNext != null) {
      refs.add(_requireString(defaultNext, '$nodeId.default_next'));
    }

    if (nodeType == 'action') {
      refs.add(_requireString(node['next'], '$nodeId.next'));
      return refs;
    }

    if (nodeType == 'question') {
      _requireString(node['input_key'], '$nodeId.input_key');
      final inputType = (node['input_type'] ?? 'choice').toString();
      final nextField = node['next'];
      if (inputType == 'number') {
        _validateNumberBounds(node);
      }
      if (singleNextInputTypes.contains(inputType)) {
        refs.add(_requireString(nextField, '$nodeId.next'));
      } else {
        if (nextField is! Map || nextField.isEmpty) {
          throw GraphValidationError(
            "Question '$nodeId' requires a non-empty next map.",
          );
        }
        for (final entry in nextField.entries) {
          refs.add(_requireString(entry.value, '$nodeId.next[${entry.key}]'));
        }
      }
      return refs;
    }

    if (nodeType == 'router') {
      final routes = node['routes'];
      if (routes is! List || routes.isEmpty) {
        throw GraphValidationError(
          "Router '$nodeId' requires non-empty routes.",
        );
      }
      for (var index = 0; index < routes.length; index++) {
        final route = routes[index];
        if (route is! Map) {
          throw GraphValidationError(
            "Router '$nodeId' route[$index] must be an object.",
          );
        }
        refs.add(_requireString(route['next'], '$nodeId.routes[$index].next'));
      }
      if (!node.containsKey('default_next')) {
        throw GraphValidationError("Router '$nodeId' requires default_next.");
      }
      return refs;
    }

    if (nodeType == 'group' || nodeType == 'collection') {
      refs.add(_requireString(node['next'], '$nodeId.next'));
      return refs;
    }

    return refs;
  }

  /// Valide la forme d'un nœud `collection` au chargement du graphe.
  ///
  /// Une collection capture une liste d'éléments structurés en une seule
  /// réponse au lieu d'une boucle native: le moteur reste un simple parcours de
  /// DAG, la relance « ajouter un autre ? » vit entièrement côté client.
  void _validateCollectionSchema(Map<String, dynamic> node) {
    final nodeId = node['id'];
    _requireString(node['output_key'], '$nodeId.output_key');

    final schema = node['item_schema'];
    if (schema is! List || schema.isEmpty) {
      throw GraphValidationError(
        "Collection '$nodeId' requires a non-empty item_schema.",
      );
    }

    final seenKeys = <String>{};
    for (var index = 0; index < schema.length; index++) {
      final field = schema[index];
      if (field is! Map) {
        throw GraphValidationError(
          "Collection '$nodeId' item_schema[$index] must be an object.",
        );
      }
      final key =
          _requireString(field['key'], '$nodeId.item_schema[$index].key');
      if (seenKeys.contains(key)) {
        throw GraphValidationError(
          "Collection '$nodeId' item_schema has duplicate key '$key'.",
        );
      }
      seenKeys.add(key);
    }

    final minItems = node.containsKey('min_items') ? node['min_items'] : 0;
    if (minItems is! int || minItems < 0) {
      throw GraphValidationError(
        "Collection '$nodeId' min_items must be a non-negative int.",
      );
    }
    final maxItems = node['max_items'];
    if (maxItems != null && (maxItems is! int || maxItems < minItems)) {
      throw GraphValidationError(
        "Collection '$nodeId' max_items must be an int >= min_items.",
      );
    }
  }

  List<Map<String, dynamic>> _validateCollectionValue(
    Map<String, dynamic> node,
    dynamic value,
  ) {
    final nodeId = node['id'];
    final List<dynamic> items;
    if (value == null) {
      items = <dynamic>[];
    } else if (value is List) {
      items = value;
    } else {
      throw GraphRuntimeError("Collection '$nodeId' expects a list value.");
    }

    final schema = (node['item_schema'] as List?) ?? const <dynamic>[];
    final knownKeys = <String>[
      for (final field in schema)
        if (field is Map) field['key'].toString(),
    ];
    final requiredKeys = <String>[
      for (final field in schema)
        if (field is Map && field['required'] == true) field['key'].toString(),
    ];

    final minItems = (node['min_items'] as int?) ?? 0;
    final maxItems = node['max_items'] as int?;

    if (items.length < minItems) {
      throw GraphRuntimeError(
        "Collection '$nodeId' requires at least $minItems item(s), "
        'got ${items.length}.',
      );
    }
    if (maxItems != null && items.length > maxItems) {
      throw GraphRuntimeError(
        "Collection '$nodeId' accepts at most $maxItems item(s), "
        'got ${items.length}.',
      );
    }

    final normalized = <Map<String, dynamic>>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item is! Map) {
        throw GraphRuntimeError(
          "Collection '$nodeId' item[$index] must be an object.",
        );
      }
      for (final key in requiredKeys) {
        if ((item[key] ?? '').toString().trim().isEmpty) {
          throw GraphRuntimeError(
            "Collection '$nodeId' item[$index] missing required field '$key'.",
          );
        }
      }
      normalized.add(<String, dynamic>{
        for (final key in knownKeys) key: item[key] ?? '',
      });
    }
    return normalized;
  }

  String _resolveQuestionNext(Map<String, dynamic> node, dynamic value) {
    final inputType = (node['input_type'] ?? 'choice').toString();
    final nextField = node['next'];

    if (singleNextInputTypes.contains(inputType)) {
      return _requireString(nextField, '${node['id']}.next');
    }

    if (nextField is! Map) {
      throw GraphRuntimeError("Question '${node['id']}' next map is invalid.");
    }
    if (nextField.containsKey(value)) {
      return _requireString(nextField[value], '${node['id']}.next[$value]');
    }

    final key = value.toString();
    if (nextField.containsKey(key)) {
      return _requireString(nextField[key], '${node['id']}.next[$key]');
    }

    final fallback = node['default_next'] ?? fallbackNodeId;
    if (fallback != null) {
      return _requireString(fallback, '${node['id']}.default_next');
    }

    throw GraphRuntimeError(
      "Question '${node['id']}' has no next transition for answer '$value'.",
    );
  }

  String _resolveRouter(
    Map<String, dynamic> node,
    Map<String, dynamic> answers,
  ) {
    final routes = (node['routes'] as List?) ?? const <dynamic>[];
    for (final route in routes) {
      if (route is! Map) {
        continue;
      }
      if (evaluateCondition(route['when'], answers)) {
        return _requireString(route['next'], '${node['id']}.route.next');
      }
    }
    return _requireString(node['default_next'], '${node['id']}.default_next');
  }

  bool _shouldSkipNode(
    Map<String, dynamic> node,
    Map<String, dynamic> answers,
  ) {
    if (!node.containsKey('when')) {
      return false;
    }
    return !evaluateCondition(node['when'], answers);
  }

  String _resolveSkipTarget(Map<String, dynamic> node) {
    if (_truthy(node['default_next'])) {
      return _requireString(node['default_next'], '${node['id']}.default_next');
    }
    if (_truthy(node['next'])) {
      return _requireString(node['next'], '${node['id']}.next');
    }
    final fallback = fallbackNodeId;
    if (fallback != null) {
      return fallback;
    }
    throw GraphRuntimeError(
      "Node '${node['id']}' skipped by condition but no "
      'default_next/fallback available.',
    );
  }

  /// Évalue une condition appgen-graph contre les réponses déjà collectées.
  bool evaluateCondition(dynamic condition, Map<String, dynamic> answers) {
    if (condition == null) return true;
    if (condition is bool) return condition;
    if (condition is num) return condition != 0;
    if (condition is String) return condition.trim().isNotEmpty;
    if (condition is List) {
      return condition.every((item) => evaluateCondition(item, answers));
    }
    if (condition is! Map) {
      throw GraphRuntimeError(
        'Unsupported condition type: ${condition.runtimeType}',
      );
    }

    if (condition.containsKey('and')) {
      final values = condition['and'];
      if (values is! List) {
        throw GraphRuntimeError("Condition 'and' must be a list.");
      }
      return values.every((item) => evaluateCondition(item, answers));
    }

    if (condition.containsKey('or')) {
      final values = condition['or'];
      if (values is! List) {
        throw GraphRuntimeError("Condition 'or' must be a list.");
      }
      return values.any((item) => evaluateCondition(item, answers));
    }

    if (condition.containsKey('not')) {
      return !evaluateCondition(condition['not'], answers);
    }

    if (condition.containsKey('missing')) {
      final keys = condition['missing'];
      if (keys is! List) {
        throw GraphRuntimeError("Condition 'missing' must be a list.");
      }
      return keys.any((key) => _getPath(answers, key.toString()) == null);
    }

    if (condition.containsKey('exists')) {
      return _getPath(answers, condition['exists'].toString()) != null;
    }

    if (condition.containsKey('==')) {
      final operands = _binaryOperands(condition['==']);
      return _sameValue(
        _resolveOperand(operands[0], answers),
        _resolveOperand(operands[1], answers),
      );
    }

    if (condition.containsKey('!=')) {
      final operands = _binaryOperands(condition['!=']);
      return !_sameValue(
        _resolveOperand(operands[0], answers),
        _resolveOperand(operands[1], answers),
      );
    }

    for (final op in const <String>['>', '>=', '<', '<=']) {
      if (condition.containsKey(op)) {
        final operands = _binaryOperands(condition[op]);
        final left = _toNumber(_resolveOperand(operands[0], answers));
        final right = _toNumber(_resolveOperand(operands[1], answers));
        switch (op) {
          case '>':
            return left > right;
          case '>=':
            return left >= right;
          case '<':
            return left < right;
          default:
            return left <= right;
        }
      }
    }

    if (condition.containsKey('in')) {
      final operands = _binaryOperands(condition['in']);
      return _membership(
        _resolveOperand(operands[1], answers),
        _resolveOperand(operands[0], answers),
      );
    }

    if (condition.containsKey('contains')) {
      final operands = _binaryOperands(condition['contains']);
      return _membership(
        _resolveOperand(operands[0], answers),
        _resolveOperand(operands[1], answers),
      );
    }

    if (condition.containsKey('var')) {
      return _truthy(_resolveOperand(condition, answers));
    }

    throw GraphRuntimeError(
      'Unsupported condition operator: ${condition.keys.toList()}',
    );
  }

  dynamic _resolveOperand(dynamic operand, Map<String, dynamic> answers) {
    if (operand is Map && operand.containsKey('var')) {
      final varExpr = operand['var'];
      final String path;
      dynamic defaultValue;
      if (varExpr is List) {
        path = varExpr.isNotEmpty ? varExpr[0].toString() : '';
        defaultValue = varExpr.length > 1 ? varExpr[1] : null;
      } else {
        path = varExpr.toString();
      }
      final value = _getPath(answers, path);
      return value ?? defaultValue;
    }
    return operand;
  }

  /// Égalité par valeur: deux listes ou maps JSON distinctes ne sont jamais
  /// `==` en Dart, là où Python compare leur contenu.
  static bool _sameValue(dynamic left, dynamic right) {
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameValue(left[index], right[index])) return false;
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key)) return false;
        if (!_sameValue(entry.value, right[entry.key])) return false;
      }
      return true;
    }
    return left == right;
  }

  /// `value in collection` au sens Python, sans lever sur type incompatible.
  static bool _membership(dynamic collection, dynamic value) {
    if (collection is List) {
      return collection.any((item) => _sameValue(item, value));
    }
    if (collection is String) {
      return value is String && collection.contains(value);
    }
    if (collection is Map) {
      return collection.containsKey(value);
    }
    return false;
  }

  static List<dynamic> _binaryOperands(dynamic value) {
    if (value is! List || value.length != 2) {
      throw GraphRuntimeError(
        'Binary operator requires a list of two operands.',
      );
    }
    return value;
  }

  static dynamic _getPath(Map<String, dynamic> data, String dottedPath) {
    if (dottedPath.isEmpty) {
      return null;
    }
    dynamic current = data;
    for (final part in dottedPath.split('.')) {
      if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  static double? _bound(Map<String, dynamic> node, String key) {
    final raw = node[key];
    if (raw == null) return null;
    if (raw is! num) {
      throw GraphValidationError(
          "Question '${node['id']}' $key must be a number.");
    }
    return raw.toDouble();
  }

  static void _validateNumberBounds(Map<String, dynamic> node) {
    final low = _bound(node, 'min');
    final high = _bound(node, 'max');
    if (low != null && high != null && low > high) {
      throw GraphValidationError(
          "Question '${node['id']}' min is greater than max.");
    }
  }

  /// Lit un nombre saisi (« 12,5 », « 1 200 »), ou `null` si ce n'en est pas un.
  static double? readNumber(dynamic value) {
    if (value is bool) return null;
    if (value is num) return value.toDouble();
    final text = (value ?? '')
        .toString()
        .replaceAll(RegExp(r'[\s  ]'), '')
        .replaceAll(',', '.');
    final parsed = double.tryParse(text);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

  /// Réponse d'une question `number`, normalisée (même règle que Python):
  /// un entier reste un `int` pour que `== 18` compare juste, et une valeur
  /// non numérique ou hors `min`/`max` est refusée avant toute condition.
  static num parseNumberAnswer(Map<String, dynamic> node, dynamic value) {
    final number = readNumber(value);
    if (number == null) {
      throw GraphRuntimeError(
          "Question '${node['id']}' expects a number, got '$value'.");
    }
    final low = _bound(node, 'min');
    final high = _bound(node, 'max');
    if ((low != null && number < low) || (high != null && number > high)) {
      throw GraphRuntimeError(
          "Question '${node['id']}' answer $number is out of bounds [$low, $high].");
    }
    return number == number.truncateToDouble() ? number.toInt() : number;
  }

  static double _toNumber(dynamic value) {
    if (value is bool) return value ? 1.0 : 0.0;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    if (parsed == null) {
      throw GraphRuntimeError("Cannot compare non-numeric value '$value'.");
    }
    return parsed;
  }

  static String _requireString(dynamic value, String fieldName) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw GraphValidationError(
        "Field '$fieldName' must be a non-empty string.");
  }
}
