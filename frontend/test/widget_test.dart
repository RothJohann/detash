import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genapp_template_frontend/app.dart';
import 'package:genapp_template_frontend/screens/workflow_screen.dart';

void main() {
  testWidgets('affiche le shell template', (tester) async {
    await tester.pumpWidget(const GenappTemplateApp());
    expect(find.text('GENAPP Template'), findsAtLeastNWidgets(1));
    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
    expect(find.text('Signalements'), findsNothing);

    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Signalements'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Ajouter capture'),
      find.byType(ListView),
      const Offset(0, -180),
    );
    expect(find.text('Ajouter capture'), findsOneWidget);
    expect(find.text('Prendre photo'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Rattacher à un test'),
      find.byType(ListView),
      const Offset(0, -180),
    );
    expect(find.text('Rattacher à un test'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Envoyer vers APPGEN'),
      find.byType(ListView),
      const Offset(0, -180),
    );
    expect(find.text('Envoyer vers APPGEN'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  // S136: garde-fou de la topologie (a) sans backend (D-033). Avant le portage
  // Dart du moteur, chaque etape passait par un POST vers le backend et ce test
  // echouait des le premier noeud avec une URL injoignable.
  testWidgets('le parcours se deroule avec un backend injoignable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkflowScreen(backendUrl: 'http://127.0.0.1:9'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Erreur runtime'), findsNothing);
    expect(find.text('Bienvenue'), findsOneWidget);

    await tester.tap(find.text('Étape réalisée, continuer'));
    await tester.pumpAndSettle();

    expect(
      find.text('Quel domaine métier cible cette GENAPP ?'),
      findsOneWidget,
    );
    expect(find.textContaining('Erreur runtime'), findsNothing);
  });
}
