import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/genapp_branding.dart';
import '../services/genapp_signalement_service.dart';

const List<DropdownMenuItem<String>> genappSignalementCategoryItems = [
  DropdownMenuItem(value: 'bug', child: Text('Bug')),
  DropdownMenuItem(value: 'blocage', child: Text('Blocage')),
  DropdownMenuItem(value: 'ux', child: Text('UX/UI')),
  DropdownMenuItem(value: 'network', child: Text('Réseau')),
  DropdownMenuItem(value: 'build', child: Text('Build')),
  DropdownMenuItem(
      value: 'clarification', child: Text('Clarification requise')),
  DropdownMenuItem(value: 'manque', child: Text('Manque')),
  DropdownMenuItem(value: 'question', child: Text('Question')),
  DropdownMenuItem(value: 'other', child: Text('Autre')),
];

class _PendingSignalementAttachment {
  const _PendingSignalementAttachment({
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.dataBase64,
  });

  final String filename;
  final String contentType;
  final int sizeBytes;
  final String dataBase64;
}

class SignalementsScreen extends StatefulWidget {
  const SignalementsScreen({
    super.key,
    required this.appgenBackendUrl,
    required this.genappBackendUrl,
    required this.onOpenAdmin,
  });

  final String appgenBackendUrl;
  final String genappBackendUrl;
  final VoidCallback onOpenAdmin;

  @override
  State<SignalementsScreen> createState() => _SignalementsScreenState();
}

class _SignalementsScreenState extends State<SignalementsScreen> {
  late final TextEditingController _commentController;
  late final TextEditingController _logsController;
  String _category = 'bug';
  bool _submitting = false;
  bool _pickingAttachment = false;
  String? _lastTicketId;
  String? _error;
  List<_PendingSignalementAttachment> _pendingAttachments = const [];

  bool _attachToTest = false;
  bool _loadingPlans = false;
  List<GenappTestPlanOption> _plans = const [];
  List<GenappTestCaseOption> _cases = const [];
  String? _selectedPlanId;
  String? _selectedTestId;
  int? _selectedEtapeNo;

  GenappSignalementService get _service =>
      GenappSignalementService(appgenBackendUrl: widget.appgenBackendUrl);

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
    _logsController = TextEditingController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _logsController.dispose();
    super.dispose();
  }

  String _contentTypeFromFilename(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/png';
  }

  Future<void> _pickAttachment(ImageSource source) async {
    if (_pendingAttachments.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 3 captures par signalement.')),
      );
      return;
    }
    setState(() {
      _pickingAttachment = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Capture trop lourde après compression (max 2 Mo).'),
          ),
        );
        return;
      }
      final filename = picked.name.isNotEmpty
          ? picked.name
          : 'capture-${DateTime.now().millisecondsSinceEpoch}.jpg';
      setState(() {
        _pendingAttachments = [
          ..._pendingAttachments,
          _PendingSignalementAttachment(
            filename: filename,
            contentType: _contentTypeFromFilename(filename),
            sizeBytes: bytes.length,
            dataBase64: base64Encode(bytes),
          ),
        ];
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Capture impossible: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _pickingAttachment = false;
        });
      }
    }
  }

  Future<void> _toggleAttachToTest(bool value) async {
    setState(() {
      _attachToTest = value;
      if (!value) {
        _selectedPlanId = null;
        _selectedTestId = null;
        _selectedEtapeNo = null;
        _cases = const [];
      }
    });
    if (value && _plans.isEmpty) {
      await _loadPlans();
    }
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loadingPlans = true;
      _error = null;
    });
    try {
      final plans = await _service.fetchTestPlans();
      if (!mounted) {
        return;
      }
      setState(() {
        _plans = plans.where((plan) => plan.conformant).toList();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Plans de test indisponibles: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPlans = false;
        });
      }
    }
  }

  Future<void> _selectPlan(String? planId) async {
    setState(() {
      _selectedPlanId = planId;
      _selectedTestId = null;
      _selectedEtapeNo = null;
      _cases = const [];
    });
    if (planId == null) {
      return;
    }
    try {
      final cases = await _service.fetchTestCampaign(planId);
      if (!mounted) {
        return;
      }
      setState(() {
        _cases = cases;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Cas de test indisponibles: $error';
      });
    }
  }

  GenappTestRunnerRef? _buildTestRunnerRef() {
    if (!_attachToTest ||
        _selectedPlanId == null ||
        _selectedTestId == null ||
        _selectedEtapeNo == null) {
      return null;
    }
    return GenappTestRunnerRef(
      planId: _selectedPlanId!,
      testId: _selectedTestId!,
      etapeNo: _selectedEtapeNo!,
    );
  }

  Future<void> _submit() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commentaire obligatoire.')),
      );
      return;
    }
    final appgenBackendUrl = widget.appgenBackendUrl.trim();
    final appgenUri = Uri.tryParse(appgenBackendUrl);
    if (appgenUri == null || !appgenUri.hasScheme || appgenUri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL APPGEN invalide.')),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final result = await _service.createSignalement(
        GenappSignalementDraft(
          category: _category,
          comment: comment,
          genappSlug: GenappBranding.slug,
          genappVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
          backendUrl: widget.genappBackendUrl,
          logsText: _logsController.text.trim(),
          attachments: _pendingAttachments
              .map(
                (attachment) => GenappSignalementAttachmentDraft(
                  filename: attachment.filename,
                  contentType: attachment.contentType,
                  dataBase64: attachment.dataBase64,
                ),
              )
              .toList(),
          testRunnerRef: _buildTestRunnerRef(),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastTicketId = result.id;
        _commentController.clear();
        _logsController.clear();
        _pendingAttachments = const [];
        _attachToTest = false;
        _selectedPlanId = null;
        _selectedTestId = null;
        _selectedEtapeNo = null;
        _cases = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signalement envoyé: ${result.id}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _submitting || _pickingAttachment;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Signalements',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text('Cible: GENAPP ${GenappBranding.slug}'),
        const SizedBox(height: 4),
        SelectableText('APPGEN: ${widget.appgenBackendUrl}'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: widget.onOpenAdmin,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Configurer APPGEN'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Type',
          ),
          items: genappSignalementCategoryItems,
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _category = value;
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Commentaire',
            hintText: 'Décrire le problème rencontré dans cette GENAPP.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _logsController,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Logs copiés',
            hintText: 'Coller ici une erreur, une sortie console ou un log.',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed:
                  busy ? null : () => _pickAttachment(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Ajouter capture'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _pickAttachment(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Prendre photo'),
            ),
          ],
        ),
        if (_pendingAttachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final entry in _pendingAttachments.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attachment_outlined),
              title: Text(entry.$2.filename),
              subtitle: Text(
                '${(entry.$2.sizeBytes / 1024).toStringAsFixed(0)} Ko · ${entry.$2.contentType}',
              ),
              trailing: IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.close),
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          _pendingAttachments = [
                            for (var index = 0;
                                index < _pendingAttachments.length;
                                index++)
                              if (index != entry.$1) _pendingAttachments[index],
                          ];
                        });
                      },
              ),
            ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Rattacher à un test'),
          subtitle: const Text(
            'Bascule l\'étape choisie en KO dans le TestRunner APPGEN.',
          ),
          value: _attachToTest,
          onChanged: busy ? null : (value) => _toggleAttachToTest(value),
        ),
        if (_attachToTest) ...[
          if (_loadingPlans)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_plans.isEmpty)
            const Text('Aucun plan conforme disponible.')
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedPlanId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Plan de test'),
              items: _plans
                  .map(
                    (plan) => DropdownMenuItem(
                      value: plan.planId,
                      child: Text(plan.title, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : (value) => _selectPlan(value),
            ),
            if (_selectedPlanId != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedTestId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cas de test'),
                items: _cases
                    .map(
                      (testCase) => DropdownMenuItem(
                        value: testCase.idTest,
                        child: Text(
                          '${testCase.idTest} · ${testCase.nomCas}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          _selectedTestId = value;
                          _selectedEtapeNo = null;
                        });
                      },
              ),
            ],
            if (_selectedTestId != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _selectedEtapeNo,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Étape'),
                items: _cases
                    .firstWhere(
                      (testCase) => testCase.idTest == _selectedTestId,
                      orElse: () => const GenappTestCaseOption(
                        idTest: '',
                        nomCas: '',
                        etapeNos: <int>[],
                      ),
                    )
                    .etapeNos
                    .map(
                      (etape) => DropdownMenuItem(
                        value: etape,
                        child: Text('Étape $etape'),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          _selectedEtapeNo = value;
                        });
                      },
              ),
            ],
          ],
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.bug_report_outlined),
          label: const Text('Envoyer vers APPGEN'),
        ),
        if (_lastTicketId != null) ...[
          const SizedBox(height: 12),
          Text(
            'Dernier ticket: $_lastTicketId',
            style: TextStyle(color: scheme.primary),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: scheme.error),
          ),
        ],
      ],
    );
  }
}
