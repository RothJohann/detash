import 'package:appgen_graph_runtime/appgen_graph_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GraphRuntimePayload _multiPayload({int? minSelect}) {
  return GraphRuntimePayload(
    graphId: 'g',
    isFinished: false,
    state: GraphRuntimeState(
      graphId: 'g',
      currentNodeId: 'q_multi',
      answers: <String, dynamic>{},
      history: <String>[],
      isFinished: false,
      lastTransitionReason: null,
    ),
    currentNode: <String, dynamic>{
      'id': 'q_multi',
      'type': 'question',
      'prompt': 'Quels modèles ?',
      'input_key': 'models',
      'input_type': 'multi',
      if (minSelect != null) 'min_select': minSelect,
      'choices': [
        {'value': 'a', 'label': 'A'},
        {'value': 'b', 'label': 'B'},
      ],
      'next': 'end',
    },
  );
}

Future<List<dynamic>> _submitWithoutSelection(
  WidgetTester tester,
  GraphRuntimePayload payload,
) async {
  final submitted = <dynamic>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GraphWorkflowView(
          payload: payload,
          graphTitle: 'Test',
          graphDescription: '',
          projectId: 'p',
          backendUrl: '',
          progress: 0,
          loading: false,
          onAnswer: (value) async => submitted.add(value),
          onBack: () async {},
          onRestart: () async {},
          labelById: (id) => id,
        ),
      ),
    ),
  );
  final button = find.text('Valider la sélection');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  return submitted;
}

void main() {
  testWidgets('multi sans min_select exige au moins une option',
      (tester) async {
    final submitted = await _submitWithoutSelection(tester, _multiPayload());
    expect(submitted, isEmpty);
    expect(find.text('Choisis au moins une option.'), findsOneWidget);
  });

  testWidgets('multi avec min_select 0 accepte une sélection vide',
      (tester) async {
    final submitted =
        await _submitWithoutSelection(tester, _multiPayload(minSelect: 0));
    expect(submitted, hasLength(1));
    expect(submitted.single, isEmpty);
  });

  group('question Nombre', () {
    GraphRuntimePayload numberPayload() => GraphRuntimePayload(
          graphId: 'g',
          isFinished: false,
          state: GraphRuntimeState(
            graphId: 'g',
            currentNodeId: 'q_age',
            answers: <String, dynamic>{},
            history: <String>[],
            isFinished: false,
            lastTransitionReason: null,
          ),
          currentNode: <String, dynamic>{
            'id': 'q_age',
            'type': 'question',
            'prompt': 'Quel âge ?',
            'input_key': 'age',
            'input_type': 'number',
            'min': 0,
            'max': 120,
            'next': 'end',
          },
        );

    Future<List<dynamic>> submit(WidgetTester tester, String typed) async {
      final submitted = <dynamic>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphWorkflowView(
              payload: numberPayload(),
              graphTitle: 'Test',
              graphDescription: '',
              projectId: 'p',
              backendUrl: '',
              progress: 0,
              loading: false,
              onAnswer: (value) async => submitted.add(value),
              onBack: () async {},
              onRestart: () async {},
              labelById: (id) => id,
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType,
          const TextInputType.numberWithOptions(decimal: true, signed: false));
      expect(find.text('Nombre entre 0 et 120'), findsOneWidget);
      await tester.enterText(find.byType(TextField), typed);
      final button = find.text('Valider la réponse');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      return submitted;
    }

    testWidgets('envoie un nombre, virgule acceptée', (tester) async {
      expect(await submit(tester, '12,5'), [12.5]);
    });

    testWidgets('un entier part en int', (tester) async {
      final submitted = await submit(tester, '42');
      expect(submitted.single, isA<int>());
    });

    testWidgets('refuse un texte avec un message lisible', (tester) async {
      expect(await submit(tester, 'environ 40'), isEmpty);
      expect(find.text('Saisis un nombre entre 0 et 120.'), findsOneWidget);
    });

    testWidgets('refuse hors bornes', (tester) async {
      expect(await submit(tester, '150'), isEmpty);
      expect(find.text('Saisis un nombre entre 0 et 120.'), findsOneWidget);
    });
  });

  group('question texte facultative', () {
    GraphRuntimePayload textePayload({required bool optional}) =>
        GraphRuntimePayload(
          graphId: 'g',
          isFinished: false,
          state: GraphRuntimeState(
            graphId: 'g',
            currentNodeId: 'q_contact',
            answers: <String, dynamic>{},
            history: <String>[],
            isFinished: false,
            lastTransitionReason: null,
          ),
          currentNode: <String, dynamic>{
            'id': 'q_contact',
            'type': 'question',
            'prompt': 'Adresse de contact ?',
            'input_key': 'contact_email',
            'input_type': 'text',
            if (optional) 'optional': true,
            'next': 'end',
          },
        );

    Future<List<dynamic>> valider(WidgetTester tester,
        {required bool optional}) async {
      final submitted = <dynamic>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphWorkflowView(
              payload: textePayload(optional: optional),
              graphTitle: 'Test',
              graphDescription: '',
              projectId: 'p',
              backendUrl: '',
              progress: 0,
              loading: false,
              onAnswer: (value) async => submitted.add(value),
              onBack: () async {},
              onRestart: () async {},
              labelById: (id) => id,
            ),
          ),
        ),
      );
      final button = find.text('Valider la réponse');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      return submitted;
    }

    testWidgets('vide refusé par défaut', (tester) async {
      expect(await valider(tester, optional: false), isEmpty);
      expect(find.text('Saisis un texte.'), findsOneWidget);
    });

    testWidgets('vide accepté si optional, avec une aide', (tester) async {
      expect(await valider(tester, optional: true), ['']);
      expect(find.text('Facultatif : laisse vide pour passer.'), findsOneWidget);
    });
  });
}
