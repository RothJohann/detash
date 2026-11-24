import 'dart:convert';

import 'package:flutter/material.dart';

import 'graph_engine.dart';
import 'graph_runtime_models.dart';

/// « entre 0 et 120 », « d'au moins 0 », « d'au plus 120 », ou rien.
String _numberRangeHint(double? min, double? max) {
  String fmt(double v) => v == v.truncateToDouble()
      ? v.toInt().toString()
      : v.toString().replaceAll('.', ',');
  if (min != null && max != null) return ' entre ${fmt(min)} et ${fmt(max)}';
  if (min != null) return " d'au moins ${fmt(min)}";
  if (max != null) return " d'au plus ${fmt(max)}";
  return '';
}

typedef GraphNodeLabelResolver = String Function(String nodeId);
typedef GraphNodeSubtitleResolver = String? Function(Map<String, dynamic> node);
typedef GraphNodeDefaultTextResolver = String Function(
    Map<String, dynamic> node);
typedef GraphEndActionsBuilder = List<Widget> Function(
  BuildContext context,
  Map<String, dynamic> node,
  Map<String, dynamic> answers,
);
typedef GraphActionNodeShownHandler = void Function(
  Map<String, dynamic> node,
);
typedef GraphActionInstructionsResolver = List<String> Function(
  Map<String, dynamic> node,
  List<String> instructions,
  Map<String, dynamic> answers,
);

class GraphWorkflowView extends StatefulWidget {
  const GraphWorkflowView({
    super.key,
    required this.payload,
    required this.graphTitle,
    required this.graphDescription,
    required this.projectId,
    required this.backendUrl,
    required this.progress,
    required this.loading,
    required this.onAnswer,
    required this.onBack,
    required this.onRestart,
    required this.labelById,
    this.stepLabel = '-',
    this.versionLabel = '-',
    this.debugMode = false,
    this.showIntro = false,
    this.introTitle = '',
    this.introMessage = '',
    this.introButtonLabel = 'Continuer',
    this.onIntroContinue,
    this.showPathNumbering = true,
    this.onPathTap,
    this.nodeSubtitle,
    this.defaultTextValue,
    this.endActionsBuilder,
    this.onImportCollection,
    this.onImportFromCatalog,
    this.onActionNodeShown,
    this.actionInstructionsResolver,
    this.extraCards = const <Widget>[],
    this.bottomPadding = 32,
    this.workflowLabel = 'Workflow APPGEN',
  });

  final GraphRuntimePayload payload;
  final String graphTitle;
  final String graphDescription;
  final String stepLabel;
  final String versionLabel;
  final String projectId;
  final String backendUrl;
  final double progress;
  final bool loading;
  final bool debugMode;
  final bool showIntro;
  final String introTitle;
  final String introMessage;
  final String introButtonLabel;
  final VoidCallback? onIntroContinue;
  final bool showPathNumbering;
  final ValueChanged<int>? onPathTap;
  final Future<void> Function(dynamic value) onAnswer;
  final Future<void> Function() onBack;
  final Future<void> Function() onRestart;
  final GraphNodeLabelResolver labelById;
  final GraphNodeSubtitleResolver? nodeSubtitle;
  final GraphNodeDefaultTextResolver? defaultTextValue;
  final GraphEndActionsBuilder? endActionsBuilder;
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> node)?
      onImportCollection;
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> node)?
      onImportFromCatalog;
  final GraphActionNodeShownHandler? onActionNodeShown;
  final GraphActionInstructionsResolver? actionInstructionsResolver;
  final List<Widget> extraCards;
  final double bottomPadding;
  final String workflowLabel;

  @override
  State<GraphWorkflowView> createState() => _GraphWorkflowViewState();
}

class _GraphWorkflowViewState extends State<GraphWorkflowView> {
  final TextEditingController _textController = TextEditingController();
  final Set<String> _selectedMulti = <String>{};
  String? _selectedChoice;
  String? _lastRenderedNodeId;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GraphWorkflowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _primeNodeInputsIfNeeded();
  }

  void _clearNodeTransientValues() {
    _textController.clear();
    _selectedChoice = null;
    _selectedMulti.clear();
  }

  List<GraphChoice> _extractChoices(Map<String, dynamic> node) {
    final rawChoices = node['choices'];
    if (rawChoices is List) {
      return rawChoices
          .whereType<Map>()
          .map((raw) => GraphChoice.fromJson(Map<String, dynamic>.from(raw)))
          .toList();
    }

    final rawNext = node['next'];
    if (rawNext is Map) {
      return rawNext.keys
          .map((key) => key.toString())
          .map((value) => GraphChoice(value: value, label: value))
          .toList();
    }

    return const <GraphChoice>[];
  }

  String? _defaultChoiceValue(Map<String, dynamic> node) {
    final candidate = (node['default_choice'] ?? node['default_value'] ?? '')
        .toString()
        .trim();
    if (candidate.isEmpty) {
      return null;
    }
    final allowedValues = _extractChoices(
      node,
    ).map((choice) => choice.value).toSet();
    if (allowedValues.isEmpty || !allowedValues.contains(candidate)) {
      return null;
    }
    return candidate;
  }

  void _primeNodeInputsIfNeeded() {
    final nodeId = widget.payload.state.currentNodeId;
    if (_lastRenderedNodeId == nodeId) {
      return;
    }
    _lastRenderedNodeId = nodeId;
    _clearNodeTransientValues();

    final node = widget.payload.currentNode;
    _notifyActionNodeShownIfNeeded(node);

    final inputKey = (node['input_key'] ?? '').toString().trim();
    if (inputKey.isEmpty) {
      return;
    }
    final inputType = (node['input_type'] ?? 'choice').toString();
    final value = widget.payload.state.answers[inputKey];
    if (value == null) {
      if (inputType == 'choice') {
        _selectedChoice = _defaultChoiceValue(node);
      } else if (inputType == 'text') {
        final defaultValue = widget.defaultTextValue?.call(node) ?? '';
        if (defaultValue.trim().isNotEmpty) {
          _textController.text = defaultValue.trim();
        }
      }
      return;
    }

    if (inputType == 'text' || inputType == 'number') {
      _textController.text = value.toString();
      return;
    }
    if (inputType == 'multi' && value is List) {
      _selectedMulti
        ..clear()
        ..addAll(value.map((item) => item.toString()));
      return;
    }
    _selectedChoice = value.toString();
  }

  /// Déclenche `onActionNodeShown` une fois par nœud `action` affiché (S125).
  /// Ne filtre plus sur la présence de `pc_action`: certains nœuds décident
  /// dynamiquement quoi publier à partir des réponses du graphe plutôt que
  /// depuis un bloc statique du JSON (ex: prompt produits landing avec tag
  /// d'affiliation déjà injecté) - à l'appelant de ne rien faire si le nœud
  /// ne le concerne pas.
  void _notifyActionNodeShownIfNeeded(Map<String, dynamic> node) {
    final handler = widget.onActionNodeShown;
    if (handler == null) {
      return;
    }
    if ((node['type'] ?? '').toString() != 'action') {
      return;
    }
    handler(node);
  }

  String? _subtitle(Map<String, dynamic> node) =>
      widget.nodeSubtitle?.call(node);

  Future<void> _submitChoice() async {
    final value = _selectedChoice;
    if (value == null || value.isEmpty) {
      _showSnackBar('Sélectionne une réponse.');
      return;
    }
    await widget.onAnswer(value);
  }

  Future<void> _submitText() async {
    final value = _textController.text.trim();
    final node = widget.payload.currentNode;
    if ((node['input_type'] ?? '').toString() == 'number') {
      await _submitNumber(node, value);
      return;
    }
    // `optional: true` (question texte) : une réponse vide passe l'étape (2026-11-21).
    if (value.isEmpty && node['optional'] != true) {
      _showSnackBar('Saisis un texte.');
      return;
    }
    await widget.onAnswer(value);
  }

  /// Format `number`: on refuse ici, avec un message lisible, ce que le
  /// moteur refuserait (non numérique, hors `min`/`max`).
  Future<void> _submitNumber(Map<String, dynamic> node, String raw) async {
    final number = GraphEngine.readNumber(raw);
    final low = (node['min'] as num?)?.toDouble();
    final high = (node['max'] as num?)?.toDouble();
    if (number == null) {
      _showSnackBar('Saisis un nombre${_numberRangeHint(low, high)}.');
      return;
    }
    if ((low != null && number < low) || (high != null && number > high)) {
      _showSnackBar('Saisis un nombre${_numberRangeHint(low, high)}.');
      return;
    }
    await widget.onAnswer(GraphEngine.parseNumberAnswer(node, number));
  }

  Future<void> _submitMulti() async {
    // `min_select: 0` sur le nœud autorise une sélection vide (défaut: 1).
    final minSelect =
        (widget.payload.currentNode['min_select'] as num?)?.toInt() ?? 1;
    if (_selectedMulti.length < minSelect) {
      _showSnackBar('Choisis au moins une option.');
      return;
    }
    await widget.onAnswer(_selectedMulti.toList());
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    _primeNodeInputsIfNeeded();
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            widget.bottomPadding + MediaQuery.of(context).viewPadding.bottom,
          ),
          children: [
            _WorkflowHeader(
              workflowLabel: widget.workflowLabel,
              graphId: widget.payload.graphId,
              graphTitle: widget.graphTitle,
              graphDescription: widget.graphDescription,
              stepLabel: widget.stepLabel,
              versionLabel: widget.versionLabel,
              projectId: widget.projectId,
              backendUrl: widget.backendUrl,
              progress: widget.progress,
              isFinished: widget.payload.isFinished,
              debugMode: widget.debugMode,
            ),
            const SizedBox(height: 12),
            if (widget.showIntro) ...[
              _GraphIntroCard(
                title: widget.introTitle,
                message: widget.introMessage,
                buttonLabel: widget.introButtonLabel,
                onContinue: widget.onIntroContinue,
              ),
            ] else ...[
              _WorkflowPath(
                history: widget.payload.state.history,
                currentNodeId: widget.payload.state.currentNodeId,
                labelById: widget.labelById,
                showStepNumbering: widget.showPathNumbering,
                onStepTap: widget.onPathTap,
              ),
              const SizedBox(height: 12),
              _buildCurrentNodeCard(),
            ],
            for (final extraCard in widget.extraCards) ...[
              const SizedBox(height: 12),
              extraCard,
            ],
          ],
        ),
        if (widget.loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _initialCollectionItems(
      Map<String, dynamic> node) {
    final outputKey = (node['output_key'] ?? '').toString().trim();
    if (outputKey.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final value = widget.payload.state.answers[outputKey];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Widget _buildCurrentNodeCard() {
    final node = widget.payload.currentNode;
    final nodeType = (node['type'] ?? '').toString();
    final subtitle = _subtitle(node);
    return switch (nodeType) {
      'question' => _QuestionNodeCard(
          node: node,
          subtitle: subtitle,
          choices: _extractChoices(node),
          selectedChoice: _selectedChoice,
          selectedMulti: _selectedMulti,
          textController: _textController,
          onChoiceChanged: (value) => setState(() => _selectedChoice = value),
          onMultiChanged: (value, isSelected) {
            setState(() {
              if (isSelected) {
                _selectedMulti.add(value);
              } else {
                _selectedMulti.remove(value);
              }
            });
          },
          onSubmitChoice: _submitChoice,
          onSubmitText: _submitText,
          onSubmitMulti: _submitMulti,
          onBack: widget.onBack,
          canGoBack: widget.payload.state.history.isNotEmpty,
        ),
      'action' => _ActionNodeCard(
          node: node,
          subtitle: subtitle,
          answers: widget.payload.state.answers,
          instructionsResolver: widget.actionInstructionsResolver,
          onContinue: () => widget.onAnswer(null),
          onBack: widget.onBack,
          canGoBack: widget.payload.state.history.isNotEmpty,
        ),
      'collection' => _CollectionNodeCard(
          key: ValueKey('collection-${widget.payload.state.currentNodeId}'),
          node: node,
          subtitle: subtitle,
          initialItems: _initialCollectionItems(node),
          onSubmit: (items) => widget.onAnswer(items),
          onImport: widget.onImportCollection,
          onImportFromCatalog: widget.onImportFromCatalog,
          onBack: widget.onBack,
          canGoBack: widget.payload.state.history.isNotEmpty,
        ),
      'end' => _EndNodeCard(
          node: node,
          subtitle: subtitle,
          answers: widget.payload.state.answers,
          onRestart: widget.onRestart,
          actions: widget.endActionsBuilder?.call(
                context,
                node,
                widget.payload.state.answers,
              ) ??
              const <Widget>[],
        ),
      _ => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(node),
            ),
          ),
        ),
    };
  }
}

class _WorkflowHeader extends StatelessWidget {
  const _WorkflowHeader({
    required this.workflowLabel,
    required this.graphId,
    required this.graphTitle,
    required this.graphDescription,
    required this.stepLabel,
    required this.versionLabel,
    required this.projectId,
    required this.backendUrl,
    required this.progress,
    required this.isFinished,
    required this.debugMode,
  });

  final String workflowLabel;
  final String graphId;
  final String graphTitle;
  final String graphDescription;
  final String stepLabel;
  final String versionLabel;
  final String projectId;
  final String backendUrl;
  final double progress;
  final bool isFinished;
  final bool debugMode;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(workflowLabel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(graphTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (graphDescription.trim().isNotEmpty) Text(graphDescription),
            if (debugMode) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.developer_mode_outlined),
                title: const Text('Détails debug workflow'),
                children: [
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Étape: $stepLabel')),
                      Chip(label: Text('Version: $versionLabel')),
                      Chip(label: Text('GENAPP: $projectId')),
                      Chip(label: Text('ID graphe: $graphId')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Backend: $backendUrl'),
                ],
              ),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text(
              isFinished
                  ? 'Statut: terminé (100%)'
                  : 'Statut: en cours ($percent%)',
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphIntroCard extends StatelessWidget {
  const _GraphIntroCard({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onContinue,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Introduction', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (message.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.play_arrow),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowPath extends StatefulWidget {
  const _WorkflowPath({
    required this.history,
    required this.currentNodeId,
    required this.labelById,
    required this.showStepNumbering,
    required this.onStepTap,
  });

  final List<String> history;
  final String currentNodeId;
  final GraphNodeLabelResolver labelById;
  final bool showStepNumbering;
  final ValueChanged<int>? onStepTap;

  @override
  State<_WorkflowPath> createState() => _WorkflowPathState();
}

class _WorkflowPathState extends State<_WorkflowPath> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant _WorkflowPath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history ||
        oldWidget.currentNodeId != widget.currentNodeId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildPathChip({
    required int pathIndex,
    required String nodeId,
    required double maxWidth,
  }) {
    final stepNo = pathIndex + 1;
    final label = widget.showStepNumbering
        ? '$stepNo. ${widget.labelById(nodeId)}'
        : widget.labelById(nodeId);
    final isCurrent = nodeId == widget.currentNodeId;
    final canJumpBack = pathIndex < widget.history.length;
    final currentBackgroundColor = Colors.blue.shade100;
    final currentBorderColor = Colors.blue.shade400;
    final currentTextColor = Colors.blue.shade900;
    return ActionChip(
      backgroundColor: isCurrent ? currentBackgroundColor : null,
      disabledColor: isCurrent ? currentBackgroundColor : null,
      side: isCurrent ? BorderSide(color: currentBorderColor) : null,
      labelStyle: isCurrent
          ? TextStyle(color: currentTextColor, fontWeight: FontWeight.w600)
          : null,
      label: SizedBox(
        width: maxWidth,
        child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
      ),
      onPressed: !isCurrent && canJumpBack && widget.onStepTap != null
          ? () => widget.onStepTap!(pathIndex)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = <String>[...widget.history, widget.currentNodeId];
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final chipMaxWidth = viewportWidth < 520 ? 164.0 : 240.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < path.length; i++) ...[
                _buildPathChip(
                  pathIndex: i,
                  nodeId: path[i],
                  maxWidth: chipMaxWidth,
                ),
                if (i < path.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionNodeCard extends StatelessWidget {
  const _QuestionNodeCard({
    required this.node,
    required this.subtitle,
    required this.choices,
    required this.selectedChoice,
    required this.selectedMulti,
    required this.textController,
    required this.onChoiceChanged,
    required this.onMultiChanged,
    required this.onSubmitChoice,
    required this.onSubmitText,
    required this.onSubmitMulti,
    required this.onBack,
    required this.canGoBack,
  });

  final Map<String, dynamic> node;
  final String? subtitle;
  final List<GraphChoice> choices;
  final String? selectedChoice;
  final Set<String> selectedMulti;
  final TextEditingController textController;
  final ValueChanged<String?> onChoiceChanged;
  final void Function(String value, bool isSelected) onMultiChanged;
  final Future<void> Function() onSubmitChoice;
  final Future<void> Function() onSubmitText;
  final Future<void> Function() onSubmitMulti;
  final Future<void> Function() onBack;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    final inputType = (node['input_type'] ?? 'choice').toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Question', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              (node['prompt'] ?? 'Question').toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            if (inputType == 'text' || inputType == 'number')
              _TextQuestionInput(
                controller: textController,
                onSubmitText: onSubmitText,
                onBack: onBack,
                canGoBack: canGoBack,
                numeric: inputType == 'number',
                optional: node['optional'] == true,
                min: (node['min'] as num?)?.toDouble(),
                max: (node['max'] as num?)?.toDouble(),
              )
            else if (inputType == 'multi')
              _MultiQuestionInput(
                choices: choices,
                selectedMulti: selectedMulti,
                onMultiChanged: onMultiChanged,
                onSubmitMulti: onSubmitMulti,
                onBack: onBack,
                canGoBack: canGoBack,
              )
            else
              _ChoiceQuestionInput(
                choices: choices,
                selectedChoice: selectedChoice,
                onChoiceChanged: onChoiceChanged,
                onSubmitChoice: onSubmitChoice,
                onBack: onBack,
                canGoBack: canGoBack,
              ),
          ],
        ),
      ),
    );
  }
}

class _TextQuestionInput extends StatelessWidget {
  const _TextQuestionInput({
    required this.controller,
    required this.onSubmitText,
    required this.onBack,
    required this.canGoBack,
    this.numeric = false,
    this.optional = false,
    this.min,
    this.max,
  });

  final TextEditingController controller;
  final bool optional;
  final Future<void> Function() onSubmitText;
  final Future<void> Function() onBack;
  final bool canGoBack;
  final bool numeric;
  final double? min;
  final double? max;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          maxLines: numeric ? 1 : 4,
          keyboardType: numeric
              ? TextInputType.numberWithOptions(
                  decimal: true, signed: min == null || min! < 0)
              : TextInputType.multiline,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: numeric ? 'Un nombre...' : 'Ta réponse...',
            helperText: numeric && (min != null || max != null)
                ? 'Nombre${_numberRangeHint(min, max)}'
                : (optional ? 'Facultatif : laisse vide pour passer.' : null),
          ),
        ),
        const SizedBox(height: 12),
        _NodeActions(
          primaryLabel: 'Valider la réponse',
          primaryIcon: Icons.play_arrow,
          onPrimary: onSubmitText,
          onBack: onBack,
          canGoBack: canGoBack,
        ),
      ],
    );
  }
}

class _MultiQuestionInput extends StatelessWidget {
  const _MultiQuestionInput({
    required this.choices,
    required this.selectedMulti,
    required this.onMultiChanged,
    required this.onSubmitMulti,
    required this.onBack,
    required this.canGoBack,
  });

  final List<GraphChoice> choices;
  final Set<String> selectedMulti;
  final void Function(String value, bool isSelected) onMultiChanged;
  final Future<void> Function() onSubmitMulti;
  final Future<void> Function() onBack;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              FilterChip(
                label: Text(choice.label),
                selected: selectedMulti.contains(choice.value),
                onSelected: (isSelected) =>
                    onMultiChanged(choice.value, isSelected),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _NodeActions(
          primaryLabel: 'Valider la sélection',
          primaryIcon: Icons.play_arrow,
          onPrimary: onSubmitMulti,
          onBack: onBack,
          canGoBack: canGoBack,
        ),
      ],
    );
  }
}

class _ChoiceQuestionInput extends StatelessWidget {
  const _ChoiceQuestionInput({
    required this.choices,
    required this.selectedChoice,
    required this.onChoiceChanged,
    required this.onSubmitChoice,
    required this.onBack,
    required this.canGoBack,
  });

  final List<GraphChoice> choices;
  final String? selectedChoice;
  final ValueChanged<String?> onChoiceChanged;
  final Future<void> Function() onSubmitChoice;
  final Future<void> Function() onBack;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              ChoiceChip(
                label: Text(choice.label),
                selected: selectedChoice == choice.value,
                onSelected: (_) => onChoiceChanged(choice.value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _NodeActions(
          primaryLabel: 'Valider la réponse',
          primaryIcon: Icons.play_arrow,
          onPrimary: onSubmitChoice,
          onBack: onBack,
          canGoBack: canGoBack,
        ),
      ],
    );
  }
}

class _ActionNodeCard extends StatelessWidget {
  const _ActionNodeCard({
    required this.node,
    required this.subtitle,
    required this.answers,
    required this.instructionsResolver,
    required this.onContinue,
    required this.onBack,
    required this.canGoBack,
  });

  final Map<String, dynamic> node;
  final String? subtitle;
  final Map<String, dynamic> answers;
  final GraphActionInstructionsResolver? instructionsResolver;
  final Future<void> Function() onContinue;
  final Future<void> Function() onBack;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    var instructions = (node['instructions'] as List? ?? const <dynamic>[])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
    final resolver = instructionsResolver;
    if (resolver != null) {
      instructions = resolver(node, instructions, answers);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Action', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              (node['title'] ?? 'Étape action').toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Text((node['message'] ?? '').toString()),
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final instruction in instructions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(instruction)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            _NodeActions(
              primaryLabel: 'Étape réalisée, continuer',
              primaryIcon: Icons.check,
              onPrimary: onContinue,
              onBack: onBack,
              canGoBack: canGoBack,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rend un node `type: "collection"`: saisit une liste d'éléments structurés
/// (`item_schema`) en un seul `answer()` — pas de boucle côté moteur de
/// graphe, le "ajouter un autre ?" est entièrement géré ici côté client.
class _CollectionNodeCard extends StatefulWidget {
  const _CollectionNodeCard({
    super.key,
    required this.node,
    required this.subtitle,
    required this.initialItems,
    required this.onSubmit,
    required this.onBack,
    required this.canGoBack,
    this.onImport,
    this.onImportFromCatalog,
  });

  final Map<String, dynamic> node;
  final String? subtitle;
  final List<Map<String, dynamic>> initialItems;
  final Future<void> Function(List<Map<String, dynamic>> items) onSubmit;
  final Future<void> Function() onBack;
  final bool canGoBack;
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> node)?
      onImport;
  final Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> node)?
      onImportFromCatalog;

  @override
  State<_CollectionNodeCard> createState() => _CollectionNodeCardState();
}

class _CollectionNodeCardState extends State<_CollectionNodeCard> {
  late final List<Map<String, String>> _schema = _extractSchema();
  late final Map<String, TextEditingController> _controllers = {
    for (final field in _schema) field['key']!: TextEditingController(),
  };
  late final List<Map<String, dynamic>> _items = widget.initialItems
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  bool _importing = false;
  bool _importingFromCatalog = false;

  List<Map<String, String>> _extractSchema() {
    final raw = widget.node['item_schema'];
    if (raw is! List) {
      return const <Map<String, String>>[];
    }
    return raw
        .whereType<Map>()
        .map((field) {
          return {
            'key': (field['key'] ?? '').toString(),
            'label': (field['label'] ?? field['key'] ?? '').toString(),
            'required': field['required'] == true ? 'true' : 'false',
          };
        })
        .where((field) => field['key']!.isNotEmpty)
        .toList();
  }

  int get _minItems => (widget.node['min_items'] as num?)?.toInt() ?? 0;
  int? get _maxItems => (widget.node['max_items'] as num?)?.toInt();

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addItem() {
    final missingLabels = [
      for (final field in _schema)
        if (field['required'] == 'true' &&
            (_controllers[field['key']]?.text.trim().isEmpty ?? true))
          field['label']!,
    ];
    if (missingLabels.isNotEmpty) {
      _showSnackBar('Renseigne: ${missingLabels.join(', ')}');
      return;
    }
    final maxItems = _maxItems;
    if (maxItems != null && _items.length >= maxItems) {
      _showSnackBar('Maximum $maxItems élément(s).');
      return;
    }
    final item = <String, dynamic>{
      for (final field in _schema)
        field['key']!: _controllers[field['key']]!.text.trim(),
    };
    setState(() {
      _items.add(item);
      for (final controller in _controllers.values) {
        controller.clear();
      }
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _handleImport() async {
    final importer = widget.onImport;
    if (importer == null || _importing) {
      return;
    }
    setState(() => _importing = true);
    try {
      final fetched = await importer(widget.node);
      if (!mounted) {
        return;
      }
      if (fetched.isEmpty) {
        _showSnackBar('Aucun élément préparé trouvé pour ce projet sur le PC.');
      } else {
        setState(() {
          _items
            ..clear()
            ..addAll(fetched.map((item) => Map<String, dynamic>.from(item)));
        });
        _showSnackBar('${fetched.length} élément(s) importé(s) depuis le PC.');
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar('Import impossible: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  /// S128: importe depuis le catalogue générique, une source distincte du PC
  /// projet-par-projet (`onImport`) - un remplace la liste courante, l'autre
  /// pioche dans un catalogue réutilisable entre GENAPPs. Remplace la liste
  /// courante plutôt que fusionner, même comportement que `_handleImport`.
  Future<void> _handleImportFromCatalog() async {
    final importer = widget.onImportFromCatalog;
    if (importer == null || _importingFromCatalog) {
      return;
    }
    setState(() => _importingFromCatalog = true);
    try {
      final fetched = await importer(widget.node);
      if (!mounted) {
        return;
      }
      if (fetched.isEmpty) {
        _showSnackBar('Le catalogue générique est vide.');
      } else {
        setState(() {
          _items
            ..clear()
            ..addAll(fetched.map((item) => Map<String, dynamic>.from(item)));
        });
        _showSnackBar('${fetched.length} élément(s) importé(s) du catalogue.');
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar('Import impossible: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _importingFromCatalog = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_items.length < _minItems) {
      _showSnackBar('Ajoute au moins $_minItems élément(s).');
      return;
    }
    await widget.onSubmit(_items);
  }

  String _itemSummary(Map<String, dynamic> item) {
    if (_schema.isEmpty) {
      return item.toString();
    }
    final primaryKey = _schema.first['key']!;
    final primaryValue = (item[primaryKey] ?? '').toString();
    if (_schema.length < 2) {
      return primaryValue;
    }
    final secondaryValue = (item[_schema[1]['key']!] ?? '').toString();
    return secondaryValue.isEmpty
        ? primaryValue
        : '$primaryValue — $secondaryValue';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Liste', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              (widget.node['title'] ?? 'Éléments').toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if ((widget.node['message'] ?? '')
                .toString()
                .trim()
                .isNotEmpty) ...[
              const SizedBox(height: 8),
              Text((widget.node['message'] ?? '').toString()),
            ],
            if (widget.onImport != null) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _importing ? null : _handleImport,
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  _importing ? 'Import en cours...' : 'Importer depuis PC',
                ),
              ),
            ],
            if (widget.onImportFromCatalog != null) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed:
                    _importingFromCatalog ? null : _handleImportFromCatalog,
                icon: _importingFromCatalog
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: Text(
                  _importingFromCatalog
                      ? 'Import en cours...'
                      : 'Importer depuis le catalogue',
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_items.isEmpty)
              const Text('Aucun élément ajouté pour le moment.')
            else
              for (var i = 0; i < _items.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_itemSummary(_items[i])),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeItem(i),
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            Text(
              'Ajouter un élément',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            for (final field in _schema)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _controllers[field['key']],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: field['required'] == 'true'
                        ? '${field['label']} *'
                        : field['label'],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
            const SizedBox(height: 16),
            _NodeActions(
              primaryLabel: 'Valider la liste (${_items.length})',
              primaryIcon: Icons.check,
              onPrimary: _submit,
              onBack: widget.onBack,
              canGoBack: widget.canGoBack,
            ),
          ],
        ),
      ),
    );
  }
}

class _EndNodeCard extends StatelessWidget {
  const _EndNodeCard({
    required this.node,
    required this.subtitle,
    required this.answers,
    required this.onRestart,
    required this.actions,
  });

  final Map<String, dynamic> node;
  final String? subtitle;
  final Map<String, dynamic> answers;
  final Future<void> Function() onRestart;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fin de workflow',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              (node['title'] ?? 'Terminé').toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Text((node['summary'] ?? '').toString()),
            const SizedBox(height: 12),
            Text(
              'Réponses collectées',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (answers.isEmpty)
              const Text('Aucune réponse enregistrée.')
            else
              for (final entry in answers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${entry.key}: ${entry.value}'),
                ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay),
                  label: const Text('Relancer le workflow'),
                ),
                ...actions,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeActions extends StatelessWidget {
  const _NodeActions({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.onBack,
    required this.canGoBack,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final Future<void> Function() onPrimary;
  final Future<void> Function() onBack;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: onPrimary,
          icon: Icon(primaryIcon),
          label: Text(primaryLabel),
        ),
        OutlinedButton.icon(
          onPressed: canGoBack ? onBack : null,
          icon: const Icon(Icons.undo),
          label: const Text('Retour étape'),
        ),
      ],
    );
  }
}
