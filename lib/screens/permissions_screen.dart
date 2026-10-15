import 'package:flutter/material.dart';

import '../services/device_tools_service.dart';
import '../theme/yele_theme.dart';

/// Écran des autorisations (IMP-04) : chacune avec son usage et son état,
/// et un bouton pour l'accorder. L'état est relu au retour dans l'app, pour
/// refléter un changement fait dans les paramètres Android.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  final _tools = DeviceToolsService();
  List<PermissionInfo> _perms = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = await _tools.permissions();
    if (mounted) setState(() => _perms = p);
  }

  Future<void> _grant(PermissionInfo p) async {
    await _tools.request(p.key);
    // La boîte de dialogue Android est asynchrone : relecture peu après.
    await Future.delayed(const Duration(seconds: 1));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YeleColors.panel,
      appBar: AppBar(
        backgroundColor: YeleColors.header,
        foregroundColor: Colors.white,
        title: const Text('Autorisations', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final p in _perms)
            ListTile(
              leading: Icon(
                p.granted ? Icons.check_circle : Icons.cancel,
                color: p.granted ? YeleColors.good : YeleColors.danger,
              ),
              title: Text(p.label + (p.required ? ' (obligatoire)' : '')),
              subtitle: Text(
                  '${p.purpose}\n${p.granted ? 'Accordée' : 'Non accordée'}'),
              isThreeLine: true,
              trailing: p.granted
                  ? null
                  : TextButton(
                      onPressed: () => _grant(p),
                      child: const Text('Accorder'),
                    ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: _tools.openAppSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Ouvrir les paramètres Android de Yélé'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Une autorisation refusée deux fois ne peut plus être demandée '
              'par l\'application : accordez-la depuis les paramètres Android.',
              style: TextStyle(fontSize: 12, color: YeleColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
