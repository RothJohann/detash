import 'graph_engine.dart';
import 'graph_runtime_models.dart';

/// Contrat d'exécution d'un graphe, indépendant du lieu d'exécution (S136).
///
/// Deux implémentations interchangeables:
/// - [LocalGraphRuntime]: exécute le graphe dans l'app, sans réseau;
/// - `GraphRuntimeApi`: délègue au backend via `/graphs/runtime/*`.
///
/// Le payload rendu est identique dans les deux cas: c'est ce qui permet de
/// basculer une surface d'un mode à l'autre sans toucher à son code.
abstract class GraphRuntime {
  /// Vérifie la définition du graphe sans démarrer d'exécution.
  Future<void> validateGraph(Map<String, dynamic> graph);

  /// Démarre une exécution, ou reprend [state] s'il est fourni.
  Future<GraphRuntimePayload> start(
    Map<String, dynamic> graph, {
    Map<String, dynamic>? state,
  });

  /// Soumet une réponse et avance jusqu'au prochain nœud interactif.
  Future<GraphRuntimePayload> answer(
    Map<String, dynamic> graph,
    Map<String, dynamic> state,
    dynamic value,
  );
}

/// Exécution locale du graphe, sans backend (S136).
///
/// Rend vraie la topologie (a) « sans backend » de D-033: une GENAPP publiée
/// déroule son parcours hors ligne, sans hébergement ni aller-retour réseau à
/// chaque étape. Le calcul est synchrone; l'API reste asynchrone pour rester
/// substituable au client HTTP.
class LocalGraphRuntime implements GraphRuntime {
  const LocalGraphRuntime();

  @override
  Future<void> validateGraph(Map<String, dynamic> graph) async {
    GraphEngine(graph);
  }

  @override
  Future<GraphRuntimePayload> start(
    Map<String, dynamic> graph, {
    Map<String, dynamic>? state,
  }) async {
    final engine = GraphEngine(graph);
    return _payload(engine, engine.start(state));
  }

  @override
  Future<GraphRuntimePayload> answer(
    Map<String, dynamic> graph,
    Map<String, dynamic> state,
    dynamic value,
  ) async {
    final engine = GraphEngine(graph);
    final loaded = engine.loadState(state);
    return _payload(engine, engine.answer(loaded, value));
  }

  /// Miroir exact de `_runtime_payload` (`graph_runtime/api.py`).
  GraphRuntimePayload _payload(GraphEngine engine, GraphState state) {
    return GraphRuntimePayload.fromJson(<String, dynamic>{
      'graph_id': engine.graphId,
      'is_finished': state.isFinished,
      'state': engine.snapshot(state),
      'current_node': engine.currentNode(state),
    });
  }
}
