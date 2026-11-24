import 'package:flutter/material.dart';

import '../config/genapp_branding.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenWorkflow,
  });

  final VoidCallback onOpenWorkflow;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'GENAPP Template',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Socle invariant V0: Flutter + FastAPI + runtime appgen-graph partagé.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onOpenWorkflow,
          icon: const Icon(Icons.alt_route),
          label: Text(GenappBranding.launchWorkflowLabel),
        ),
      ],
    );
  }
}
