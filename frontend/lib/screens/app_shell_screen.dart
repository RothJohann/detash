import 'package:flutter/material.dart';

import '../config/genapp_branding.dart';
import '../config/runtime_config.dart';
import '../services/affiliation_service.dart';
import 'admin_screen.dart';
import 'affiliation_screen.dart';
import 'home_screen.dart';
import 'signalements_screen.dart';
import 'workflow_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _tabIndex = 0;
  bool _showSignalements = false;
  String _backendUrl = RuntimeConfig.defaultBackendUrl;
  String _appgenBackendUrl = RuntimeConfig.defaultAppgenBackendUrl;

  @override
  Widget build(BuildContext context) {
    final workflowTabLabel = GenappBranding.workflowDisplayLabel;
    // Build épuré (S026, D-038): retire le dogfooding (Admin, OTA, signalement).
    final epuree = RuntimeConfig.epuree;
    final pages = <Widget>[
      HomeScreen(onOpenWorkflow: () => setState(() => _tabIndex = 1)),
      WorkflowScreen(backendUrl: _backendUrl),
      if (!epuree)
        AdminScreen(
          initialBackendUrl: _backendUrl,
          initialAppgenBackendUrl: _appgenBackendUrl,
          onSaveBackendUrl: (value) {
            if (value.isEmpty) {
              return;
            }
            setState(() {
              _showSignalements = false;
              _backendUrl = value;
            });
          },
          onSaveAppgenBackendUrl: (value) {
            if (value.isEmpty) {
              return;
            }
            setState(() {
              _showSignalements = false;
              _appgenBackendUrl = value;
            });
          },
        ),
      if (AffiliationService.isEnabled)
        AffiliationScreen(backendUrl: _backendUrl),
    ];
    final body = (_showSignalements && !epuree)
        ? SignalementsScreen(
            appgenBackendUrl: _appgenBackendUrl,
            genappBackendUrl: _backendUrl,
            onOpenAdmin: () => setState(() {
              _showSignalements = false;
              _tabIndex = 2;
            }),
          )
        : pages[_tabIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detash'),
        actions: [
          if (!epuree)
            IconButton(
              onPressed: () => setState(() {
                _showSignalements = !_showSignalements;
              }),
              icon: Icon(
                _showSignalements ? Icons.close : Icons.bug_report_outlined,
              ),
              tooltip: _showSignalements ? 'Fermer Signalements' : 'Signaler',
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() {
          _showSignalements = false;
          _tabIndex = index;
        }),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: const Icon(Icons.alt_route_outlined),
            selectedIcon: const Icon(Icons.alt_route),
            label: workflowTabLabel,
          ),
          if (!epuree)
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: 'Admin',
            ),
          if (AffiliationService.isEnabled)
            const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Produits',
            ),
        ],
      ),
    );
  }
}
