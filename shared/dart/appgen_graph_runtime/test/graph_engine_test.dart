import 'package:appgen_graph_runtime/appgen_graph_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests de parité du moteur Dart (S136).
///
/// Miroir de `tests/unit/test_graph_engine.py`: mêmes fixtures, mêmes
/// assertions, dans le même ordre. Toute évolution du moteur Python doit être
/// répercutée ici, et inversement — c'est le seul garde-fou contre une
/// divergence silencieuse entre les deux implémentations.

Map<String, dynamic> buildSampleGraph() {
  return <String, dynamic>{
    'id': 'graph-demo',
    'title': 'Graph Demo',
    'start_node': 'q_start',
    'fallback_node': 'end_fallback',
    'nodes': <dynamic>[
      <String, dynamic>{
        'id': 'q_start',
        'type': 'question',
        'prompt': 'Type de cible ?',
        'input_key': 'market_type',
        'choices': <dynamic>[
          <String, dynamic>{'value': 'B2B', 'label': 'B2B'},
          <String, dynamic>{'value': 'B2C', 'label': 'B2C'},
        ],
        'next': <String, dynamic>{'B2B': 'r_segment', 'B2C': 'r_segment'},
      },
      <String, dynamic>{
        'id': 'r_segment',
        'type': 'router',
        'routes': <dynamic>[
          <String, dynamic>{
            'when': <String, dynamic>{
              '==': <dynamic>[
                <String, dynamic>{'var': 'market_type'},
                'B2B',
              ],
            },
            'next': 'a_b2b',
          },
        ],
        'default_next': 'a_b2c',
      },
      <String, dynamic>{
        'id': 'a_b2b',
        'type': 'action',
        'title': 'Action B2B',
        'next': 'end_ok',
      },
      <String, dynamic>{
        'id': 'a_b2c',
        'type': 'action',
        'title': 'Action B2C',
        'next': 'end_ok',
      },
      <String, dynamic>{
        'id': 'a_skipped',
        'type': 'action',
        'title': 'Skipped',
        'when': <String, dynamic>{'exists': 'non_existent_input'},
        'default_next': 'end_ok',
        'next': 'end_ok',
      },
      <String, dynamic>{
        'id': 'end_ok',
        'type': 'end',
        'title': 'Terminé',
        'message': 'Fin',
      },
      <String, dynamic>{
        'id': 'end_fallback',
        'type': 'end',
        'title': 'Fallback',
        'message': 'Fallback',
      },
    ],
  };
}

Map<String, dynamic> buildCollectionGraph([
  Map<String, dynamic> nodeOverrides = const <String, dynamic>{},
]) {
  final node = <String, dynamic>{
    'id': 'c_products',
    'type': 'collection',
    'output_key': 'products',
    'item_schema': <dynamic>[
      <String, dynamic>{'key': 'title', 'required': true},
      <String, dynamic>{'key': 'productUrl', 'required': true},
      <String, dynamic>{'key': 'description', 'required': false},
    ],
    'min_items': 0,
    'next': 'end_ok',
  }..addAll(nodeOverrides);

  return <String, dynamic>{
    'id': 'graph-collection',
    'start_node': 'c_products',
    'nodes': <dynamic>[
      node,
      <String, dynamic>{'id': 'end_ok', 'type': 'end'},
    ],
  };
}

void main() {
  group('GraphEngine (parité avec tests/unit/test_graph_engine.py)', () {
    test('question -> router -> action, branche B2B', () {
      final engine = GraphEngine(buildSampleGraph());
      var state = engine.start();

      expect(state.currentNodeId, 'q_start');
      expect(state.isFinished, isFalse);

      state = engine.answer(state, 'B2B');
      expect(state.currentNodeId, 'a_b2b');
      expect(state.answers['market_type'], 'B2B');
      expect(state.history, contains('q_start'));
      expect(state.history, contains('r_segment'));

      state = engine.answer(state);
      expect(state.currentNodeId, 'end_ok');
      expect(state.isFinished, isTrue);
    });

    test('reprise d un état et résolution automatique du router', () {
      final engine = GraphEngine(buildSampleGraph());
      final saved = <String, dynamic>{
        'graph_id': 'graph-demo',
        'current_node_id': 'r_segment',
        'answers': <String, dynamic>{'market_type': 'B2C'},
        'history': <dynamic>['q_start'],
        'is_finished': false,
      };
      final state = engine.start(saved);

      expect(state.currentNodeId, 'a_b2c');
      expect(state.lastTransitionReason, 'router');
      expect(state.history.last, 'r_segment');
    });

    test('choix inconnu tombe sur le fallback du graphe', () {
      final engine = GraphEngine(buildSampleGraph());
      var state = engine.start();
      state = engine.answer(state, 'UNKNOWN');
      expect(state.currentNodeId, 'end_fallback');
      expect(state.isFinished, isTrue);
    });

    test('when faux saute le nœud via default_next', () {
      final graph = buildSampleGraph()..['start_node'] = 'a_skipped';
      final engine = GraphEngine(graph);

      final state = engine.start();
      expect(state.currentNodeId, 'end_ok');
      expect(state.isFinished, isTrue);
      expect(state.lastTransitionReason, 'node_skipped');
    });

    test('aller-retour snapshot', () {
      final engine = GraphEngine(buildSampleGraph());
      var state = engine.start();
      state = engine.answer(state, 'B2B');

      final snapshot = engine.snapshot(state);
      final restored = engine.start(snapshot);
      expect(restored.currentNodeId, 'a_b2b');
      expect(restored.answers['market_type'], 'B2B');
    });

    test('état portant un autre graph_id est rejeté', () {
      final engine = GraphEngine(buildSampleGraph());
      final saved = <String, dynamic>{
        'graph_id': 'another-graph',
        'current_node_id': 'q_start',
        'answers': <String, dynamic>{},
        'history': <dynamic>[],
        'is_finished': false,
      };
      expect(() => engine.start(saved), throwsA(isA<GraphRuntimeError>()));
    });

    test('nœud d état inconnu remet au départ', () {
      final engine = GraphEngine(buildSampleGraph());
      final saved = <String, dynamic>{
        'graph_id': 'graph-demo',
        'current_node_id': 'node_missing',
        'answers': <String, dynamic>{'market_type': 'B2B'},
        'history': <dynamic>['q_start', 'r_segment'],
        'is_finished': false,
      };
      final state = engine.start(saved);
      expect(state.currentNodeId, 'q_start');
      expect(state.history, isEmpty);
      expect(state.lastTransitionReason, 'state_reset_invalid_node');
    });

    test('answer sur un nœud end est idempotent', () {
      final graph = buildSampleGraph()..['start_node'] = 'end_ok';
      final engine = GraphEngine(graph);
      var state = engine.start();

      expect(state.isFinished, isTrue);
      state = engine.answer(state, null);
      expect(state.currentNodeId, 'end_ok');
      expect(state.isFinished, isTrue);
      expect(state.lastTransitionReason, 'already_end');
    });

    test('question texte utilise un next linéaire', () {
      final graph = <String, dynamic>{
        'id': 'graph-text',
        'start_node': 'q_text',
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 'q_text',
            'type': 'question',
            'input_type': 'text',
            'input_key': 'free_text',
            'next': 'a_ok',
          },
          <String, dynamic>{'id': 'a_ok', 'type': 'action', 'next': 'end_ok'},
          <String, dynamic>{'id': 'end_ok', 'type': 'end'},
        ],
      };
      final engine = GraphEngine(graph);
      var state = engine.start();
      state = engine.answer(state, 'bonjour');
      expect(state.currentNodeId, 'a_ok');
      expect(state.answers['free_text'], 'bonjour');

      state = engine.answer(state);
      expect(state.currentNodeId, 'end_ok');
      expect(state.isFinished, isTrue);
    });

    test('opérateurs de condition', () {
      final engine = GraphEngine(buildSampleGraph());
      final answers = <String, dynamic>{
        'profile': <String, dynamic>{'tier': 'pro'},
        'score': '12',
        'tags': <dynamic>['beta', 'ios'],
        'choice': 'B2B',
      };

      expect(
        engine.evaluateCondition(
          <String, dynamic>{'exists': 'profile.tier'},
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            'missing': <dynamic>['unknown.path'],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            '>': <dynamic>[
              <String, dynamic>{'var': 'score'},
              10,
            ],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            '>=': <dynamic>[
              <String, dynamic>{'var': 'score'},
              12,
            ],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            '<': <dynamic>[1, 2],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            '<=': <dynamic>[2, 2],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            'in': <dynamic>[
              <String, dynamic>{'var': 'choice'},
              <dynamic>['B2B', 'B2C'],
            ],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            'contains': <dynamic>[
              <String, dynamic>{'var': 'tags'},
              'ios',
            ],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            'and': <dynamic>[
              <String, dynamic>{
                '==': <dynamic>[
                  <String, dynamic>{'var': 'choice'},
                  'B2B',
                ],
              },
              <String, dynamic>{
                'not': <String, dynamic>{
                  '==': <dynamic>[
                    <String, dynamic>{'var': 'profile.tier'},
                    'free',
                  ],
                },
              },
            ],
          },
          answers,
        ),
        isTrue,
      );
      expect(
        engine.evaluateCondition(
          <String, dynamic>{
            'or': <dynamic>[
              <String, dynamic>{
                '==': <dynamic>[
                  <String, dynamic>{'var': 'choice'},
                  'B2C',
                ],
              },
              <String, dynamic>{'var': 'profile.tier'},
            ],
          },
          answers,
        ),
        isTrue,
      );
    });

    test('opérateur binaire mal formé lève', () {
      final engine = GraphEngine(buildSampleGraph());
      expect(
        () => engine.evaluateCondition(
          <String, dynamic>{
            '>': <dynamic>[1],
          },
          <String, dynamic>{},
        ),
        throwsA(isA<GraphRuntimeError>()),
      );
    });

    test('boucle de routers détectée', () {
      final graph = <String, dynamic>{
        'id': 'graph-loop',
        'start_node': 'r1',
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 'r1',
            'type': 'router',
            'routes': <dynamic>[
              <String, dynamic>{'when': true, 'next': 'r2'},
            ],
            'default_next': 'r2',
          },
          <String, dynamic>{
            'id': 'r2',
            'type': 'router',
            'routes': <dynamic>[
              <String, dynamic>{'when': true, 'next': 'r1'},
            ],
            'default_next': 'r1',
          },
        ],
      };
      expect(
        () => GraphEngine(graph).start(),
        throwsA(isA<GraphRuntimeError>()),
      );
    });

    test('collection accepte des items valides et normalise les clés', () {
      final engine = GraphEngine(
        buildCollectionGraph(<String, dynamic>{'min_items': 1}),
      );
      var state = engine.start();
      state = engine.answer(state, <dynamic>[
        <String, dynamic>{
          'title': 'Produit A',
          'productUrl': 'https://example/a',
          'extra': 'drop-me',
        },
        <String, dynamic>{
          'title': 'Produit B',
          'productUrl': 'https://example/b',
        },
      ]);

      expect(state.currentNodeId, 'end_ok');
      expect(state.isFinished, isTrue);
      expect(state.answers['products'], <dynamic>[
        <String, dynamic>{
          'title': 'Produit A',
          'productUrl': 'https://example/a',
          'description': '',
        },
        <String, dynamic>{
          'title': 'Produit B',
          'productUrl': 'https://example/b',
          'description': '',
        },
      ]);
    });

    test('collection vide autorisée quand min_items vaut 0', () {
      final engine = GraphEngine(buildCollectionGraph());
      var state = engine.start();
      state = engine.answer(state, <dynamic>[]);
      expect(state.answers['products'], isEmpty);
      expect(state.isFinished, isTrue);
    });

    test('collection sous min_items lève', () {
      final engine = GraphEngine(
        buildCollectionGraph(<String, dynamic>{'min_items': 1}),
      );
      final state = engine.start();
      expect(
        () => engine.answer(state, <dynamic>[]),
        throwsA(isA<GraphRuntimeError>()),
      );
    });

    test('collection au-dessus de max_items lève', () {
      final engine = GraphEngine(
        buildCollectionGraph(<String, dynamic>{'max_items': 1}),
      );
      final state = engine.start();
      expect(
        () => engine.answer(state, <dynamic>[
          <String, dynamic>{'title': 'A', 'productUrl': 'https://x/a'},
          <String, dynamic>{'title': 'B', 'productUrl': 'https://x/b'},
        ]),
        throwsA(isA<GraphRuntimeError>()),
      );
    });

    test('collection avec champ requis manquant lève', () {
      final engine = GraphEngine(
        buildCollectionGraph(<String, dynamic>{'min_items': 1}),
      );
      final state = engine.start();
      expect(
        () => engine.answer(state, <dynamic>[
          <String, dynamic>{'title': 'Sans lien'},
        ]),
        throwsA(isA<GraphRuntimeError>()),
      );
    });

    test('collection avec valeur non-liste lève', () {
      final engine = GraphEngine(buildCollectionGraph());
      final state = engine.start();
      expect(
        () => engine.answer(state, 'not-a-list'),
        throwsA(isA<GraphRuntimeError>()),
      );
    });

    test('collection sans item_schema est invalide', () {
      final graph = buildCollectionGraph();
      (graph['nodes'] as List)[0]['item_schema'] = <dynamic>[];
      expect(() => GraphEngine(graph), throwsA(isA<GraphValidationError>()));
    });

    test('collection avec clé de schéma dupliquée est invalide', () {
      final graph = buildCollectionGraph();
      (graph['nodes'] as List)[0]['item_schema'] = <dynamic>[
        <String, dynamic>{'key': 'title', 'required': true},
        <String, dynamic>{'key': 'title', 'required': false},
      ];
      expect(() => GraphEngine(graph), throwsA(isA<GraphValidationError>()));
    });

    test('collection avec max_items sous min_items est invalide', () {
      final graph = buildCollectionGraph(<String, dynamic>{
        'min_items': 3,
        'max_items': 1,
      });
      expect(() => GraphEngine(graph), throwsA(isA<GraphValidationError>()));
    });

    test('router sans default_next est invalide', () {
      final graph = <String, dynamic>{
        'id': 'graph-invalid-router',
        'start_node': 'r1',
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 'r1',
            'type': 'router',
            'routes': <dynamic>[
              <String, dynamic>{'when': true, 'next': 'end_ok'},
            ],
          },
          <String, dynamic>{'id': 'end_ok', 'type': 'end'},
        ],
      };
      expect(() => GraphEngine(graph), throwsA(isA<GraphValidationError>()));
    });
  });

  group('LocalGraphRuntime (contrat identique au client HTTP)', () {
    test('start puis answer rendent le même payload que /graphs/runtime',
        () async {
      const runtime = LocalGraphRuntime();
      final graph = buildSampleGraph();

      final payload = await runtime.start(graph);
      expect(payload.graphId, 'graph-demo');
      expect(payload.isFinished, isFalse);
      expect(payload.currentNode['id'], 'q_start');
      expect(payload.state.currentNodeId, 'q_start');

      final answered = await runtime.answer(
        graph,
        payload.state.toJson(),
        'B2B',
      );
      expect(answered.currentNode['id'], 'a_b2b');
      expect(answered.state.answers['market_type'], 'B2B');
      expect(answered.isFinished, isFalse);
    });

    test('reprise d un état sérialisé', () async {
      const runtime = LocalGraphRuntime();
      final graph = buildSampleGraph();
      final payload = await runtime.start(graph);
      final answered = await runtime.answer(
        graph,
        payload.state.toJson(),
        'B2C',
      );

      final resumed = await runtime.start(
        graph,
        state: answered.state.toJson(),
      );
      expect(resumed.currentNode['id'], 'a_b2c');
      expect(resumed.state.answers['market_type'], 'B2C');
    });

    test('validateGraph lève sur un graphe invalide', () async {
      const runtime = LocalGraphRuntime();
      await expectLater(
        runtime.validateGraph(<String, dynamic>{'id': 'sans-start-node'}),
        throwsA(isA<GraphValidationError>()),
      );
    });
  });

  group('Format number (parité avec GraphEngineNumberTests)', () {
    Map<String, dynamic> numberGraph([Map<String, dynamic> bounds = const {}]) {
      Map<String, dynamic> cmp(String op, num n) => <String, dynamic>{
            op: <dynamic>[
              <String, dynamic>{'var': 'age'},
              n
            ],
          };
      return <String, dynamic>{
        'id': 'graph-number',
        'start_node': 'q_age',
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 'q_age',
            'type': 'question',
            'prompt': 'Âge ?',
            'input_key': 'age',
            'input_type': 'number',
            'next': 'r_age',
            ...bounds,
          },
          <String, dynamic>{
            'id': 'r_age',
            'type': 'router',
            'routes': <dynamic>[
              <String, dynamic>{'when': cmp('<', 18), 'next': 'end_mineur'},
              <String, dynamic>{
                'when': <String, dynamic>{
                  'and': <dynamic>[cmp('>=', 18), cmp('<=', 65)],
                },
                'next': 'end_actif',
              },
              <String, dynamic>{
                'when': cmp('==', 100),
                'next': 'end_centenaire'
              },
            ],
            'default_next': 'end_senior',
          },
          for (final id in [
            'end_mineur',
            'end_actif',
            'end_centenaire',
            'end_senior',
          ])
            <String, dynamic>{'id': id, 'type': 'end'},
        ],
      };
    }

    (String, dynamic) route(dynamic value,
        [Map<String, dynamic> bounds = const {}]) {
      final engine = GraphEngine(numberGraph(bounds));
      final state = engine.answer(engine.start(), value);
      return (state.currentNodeId, state.answers['age']);
    }

    test('route par tranche', () {
      expect(route('17'), ('end_mineur', 17));
      expect(route(18), ('end_actif', 18));
      expect(route('65'), ('end_actif', 65));
      expect(route('70,5'), ('end_senior', 70.5));
    });

    test('un entier reste un int pour que == compare juste', () {
      final (nodeId, value) = route('100,0');
      expect(nodeId, 'end_centenaire');
      expect(value, isA<int>());
    });

    test('formats français acceptés', () {
      expect(route('1 200').$2, 1200);
      expect(route('1 200').$2, 1200);
      expect(route(' 12,5 ').$2, 12.5);
    });

    test('réponse non numérique refusée', () {
      for (final value in [
        'environ 40',
        '',
        null,
        true,
        'NaN',
        'Infinity',
        '1_000'
      ]) {
        expect(() => route(value), throwsA(isA<GraphRuntimeError>()),
            reason: '$value');
      }
    });

    test('hors bornes refusé', () {
      final bounds = <String, dynamic>{'min': 0, 'max': 120};
      expect(() => route('-1', bounds), throwsA(isA<GraphRuntimeError>()));
      expect(() => route('121', bounds), throwsA(isA<GraphRuntimeError>()));
      expect(route('120', bounds), ('end_senior', 120));
    });

    test('bornes invalides refusées', () {
      for (final bounds in <Map<String, dynamic>>[
        {'min': '0'},
        {'max': true},
        {'min': 10, 'max': 5},
      ]) {
        expect(() => GraphEngine(numberGraph(bounds)),
            throwsA(isA<GraphValidationError>()),
            reason: '$bounds');
      }
    });
  });
}
