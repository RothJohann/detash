class GenappBranding {
  static const String slug = "detash";
  static const String title = "Detash";
  static const String workflowTabLabel = "Détacher";

  static String get workflowDisplayLabel {
    final label = workflowTabLabel.trim();
    if (label.isEmpty || label.startsWith('__')) {
      return 'Workflow';
    }
    return label;
  }

  static String get launchWorkflowLabel {
    final label = workflowDisplayLabel;
    if (label.isEmpty) {
      return 'Lancer le workflow';
    }
    if (label.toLowerCase() == 'workflow') {
      return 'Lancer le workflow';
    }
    return 'Lancer $label';
  }
}
