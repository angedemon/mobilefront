import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/control_session.dart';
import '../services/device_tools_service.dart';
import '../services/network_info_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

/// Code de campagne accepté par le serveur.
final campaignPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Mode Contrôle : campagne de drive test / walk test de l'autorité.
///
/// Réservé aux comptes d'agents habilités. L'agent saisit le code de la
/// campagne, choisit le rythme des cycles et appuie une seule fois sur
/// « Démarrer » : la mesure continue ensuite seule, écran éteint, jusqu'à
/// l'arrêt.
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final _session = ControlSession.instance;
  final _campaign = TextEditingController();
  int _intervalMin = 3;
  bool _keepScreenOn = true;
  bool? _agent; // null = vérification en cours ou serveur injoignable
  bool _checking = true;
  DeviceHealth _health = DeviceHealth.unknown;
  NetworkStatus? _network;
  bool _phoneGranted = true;
  bool _locationGranted = true;

  @override
  void initState() {
    super.initState();
    _campaign.text = _session.state.value.campaign;
    _refresh();
  }

  @override
  void dispose() {
    _campaign.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final agent = await _session.api.isAgent();
    final health = await _session.health();
    final network = await NetworkInfoService().getStatus();
    final perms = await DeviceToolsService().permissions();
    bool granted(String k) => perms.any((p) => p.key == k && p.granted);
    if (!mounted) return;
    setState(() {
      _agent = agent;
      _health = health;
      _network = network;
      _phoneGranted = granted('phone');
      _locationGranted = granted('location');
      _checking = false;
    });
  }

  Future<void> _start() async {
    final code = _campaign.text.trim();
    if (!campaignPattern.hasMatch(code)) {
      _snack('Code de campagne invalide : lettres, chiffres, « - » et « _ », '
          'sans espace (ex. OUAGA-2026-11).');
      return;
    }
    // Vérifications avant le départ : une mesure de contrôle ne vaut que sur
    // le réseau mobile, avec la position et les informations radio.
    await _refresh();
    if (!mounted) return;
    final problem = startProblem(
        network: _network, phoneGranted: _phoneGranted, locationGranted: _locationGranted);
    if (problem != null) {
      _snack(problem);
      return;
    }
    await _session.setKeepScreenOn(_keepScreenOn);
    await _session.start(code, interval: Duration(minutes: _intervalMin));
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter la campagne ?'),
        content: const Text('La mesure s\'arrête sur ce téléphone. Les mesures '
            'en attente seront envoyées à la prochaine campagne ou à la '
            'prochaine ouverture du mode Contrôle.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuer la mesure')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: YeleColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Arrêter')),
        ],
      ),
    );
    if (ok != true) return;
    await _session.stop();
    await _session.setKeepScreenOn(false);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'Mode Contrôle',
      route: '/control',
      body: Container(
        color: YeleColors.panel,
        child: ValueListenableBuilder<ControlState>(
          valueListenable: _session.state,
          builder: (context, s, _) => ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _intro(),
              const SizedBox(height: 14),
              if (s.running) ..._running(s) else ..._setup(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: YeleColors.header,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Drive test et walk test de l\'autorité. Réservé aux agents '
          'habilités : les mesures vont dans un espace séparé, jamais sur la '
          'carte publique.',
          style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
        ),
      );

  // ── Préparation ──────────────────────────────────────────────────────────

  List<Widget> _setup() {
    if (AccountService.current.value == null) {
      return [
        _card(
          icon: Icons.lock_outline,
          title: 'Connexion requise',
          text: 'Connectez-vous avec le compte d\'agent fourni par '
              'l\'administrateur.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).pushNamed('/account'),
            child: const Text('Se connecter'),
          ),
        ),
      ];
    }
    if (_checking) {
      return [const Center(child: CircularProgressIndicator())];
    }
    if (_agent == false) {
      return [
        _card(
          icon: Icons.block,
          title: 'Compte non habilité',
          text: 'Le compte ${AccountService.current.value!.email} n\'est pas '
              'déclaré comme agent de contrôle. Contactez l\'administrateur.',
        ),
      ];
    }
    return [
      if (_agent == null)
        _card(
          icon: Icons.cloud_off,
          title: 'Serveur injoignable',
          text: 'Habilitation non vérifiée. Vous pouvez démarrer : les mesures '
              'seront gardées sur le téléphone et envoyées dès que possible.',
        ),
      TextField(
        controller: _campaign,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Code de la campagne',
          helperText: 'Fourni par le chef de campagne (ex. OUAGA-2026-11)',
        ),
      ),
      const SizedBox(height: 18),
      const Text('Un cycle de mesure toutes les',
          style: TextStyle(color: YeleColors.ink, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final m in const [1, 2, 3, 5, 10])
            ChoiceChip(
              label: Text('$m min'),
              selected: _intervalMin == m,
              onSelected: (_) => setState(() => _intervalMin = m),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _keepScreenOn,
        onChanged: (v) => setState(() => _keepScreenOn = v),
        title: const Text('Garder l\'écran allumé'),
        subtitle: const Text('Pour suivre la mesure au véhicule. La mesure '
            'continue aussi écran éteint.'),
      ),
      _checkTile(
        ok: _network != null && _network!.usesMobile,
        okText: 'Données mobiles : ${_network?.mobileLabel ?? ''}',
        koText: _network?.isWifi == true
            ? 'Wi-Fi actif : coupez-le, le test passerait par la box'
            : 'Pas de réseau mobile : activez les données mobiles',
      ),
      _checkTile(
        ok: _phoneGranted,
        okText: 'Autorisation « Téléphone » accordée (signal radio, SIM)',
        koText: 'Autorisation « Téléphone » manquante : pas de signal radio',
        action: () async {
          await DeviceToolsService().request('phone');
          await Future.delayed(const Duration(seconds: 2));
          _refresh();
        },
      ),
      _checkTile(
        ok: _locationGranted,
        okText: 'Localisation autorisée',
        koText: 'Localisation refusée : les mesures ne seraient pas placées',
        action: () async {
          await DeviceToolsService().request('location');
          await Future.delayed(const Duration(seconds: 2));
          _refresh();
        },
      ),
      _batteryTile(),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Vérifier à nouveau'),
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: YeleColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: _start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Démarrer la campagne', style: TextStyle(fontSize: 16)),
      ),
      const SizedBox(height: 10),
      const Text(
        'Avant de partir : téléphone en charge, GPS activé, une SIM par '
        'téléphone (un téléphone par opérateur), données mobiles activées et '
        'Wi-Fi désactivé.',
        style: TextStyle(color: YeleColors.muted, fontSize: 12.5),
      ),
    ];
  }

  Widget _checkTile({
    required bool ok,
    required String okText,
    required String koText,
    Future<void> Function()? action,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(ok ? Icons.check_circle : Icons.error_outline,
          color: ok ? YeleColors.good : YeleColors.danger),
      title: Text(ok ? okText : koText),
      trailing: ok || action == null
          ? null
          : TextButton(onPressed: action, child: const Text('Autoriser')),
    );
  }

  Widget _batteryTile() {
    final ok = _health.ignoringBatteryOptimizations;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ok ? Icons.battery_charging_full : Icons.battery_alert,
          color: ok ? YeleColors.good : YeleColors.warn),
      title: Text(ok
          ? 'Optimisation de batterie désactivée'
          : 'Optimisation de batterie active'),
      subtitle: Text(ok
          ? 'Android ne coupera pas la mesure.'
          : 'Android pourrait couper la mesure écran éteint.'),
      trailing: ok
          ? null
          : TextButton(
              onPressed: () async {
                await _session.requestBatteryExemption();
                await Future.delayed(const Duration(seconds: 2));
                _refresh();
              },
              child: const Text('Désactiver'),
            ),
    );
  }

  // ── Campagne en cours ────────────────────────────────────────────────────

  List<Widget> _running(ControlState s) {
    final h = s.health;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: YeleColors.primary, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.fiber_manual_record, color: YeleColors.danger, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Campagne ${s.campaign}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: YeleColors.ink)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(s.status, style: const TextStyle(color: YeleColors.muted)),
            const Divider(height: 22),
            Row(children: [
              _metric('${s.cycles}', 'cycles'),
              _metric('${s.failed}', 'en échec'),
              _metric('${s.pending}', 'à envoyer'),
            ]),
            if (s.lastSummary != null) ...[
              const SizedBox(height: 12),
              Text('Dernier cycle : ${s.lastSummary}',
                  style: const TextStyle(color: YeleColors.ink)),
            ],
            const SizedBox(height: 8),
            Text(
              'Batterie ${h.batteryPercent ?? '—'} %'
              '${h.charging ? ' (en charge)' : ''} · '
              '${h.batteryTempC?.toStringAsFixed(0) ?? '—'} °C',
              style: const TextStyle(color: YeleColors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
      if (s.warning != null) ...[
        const SizedBox(height: 10),
        _card(icon: Icons.warning_amber, title: 'Attention', text: s.warning!),
      ],
      const SizedBox(height: 18),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: YeleColors.danger,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: _stop,
        icon: const Icon(Icons.stop),
        label: const Text('Arrêter la campagne'),
      ),
    ];
  }

  Widget _metric(String value, String label) => Expanded(
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: YeleColors.primary)),
          Text(label, style: const TextStyle(color: YeleColors.muted, fontSize: 12)),
        ]),
      );

  Widget _card(
          {required IconData icon,
          required String title,
          required String text,
          Widget? action}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: YeleColors.warn),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: YeleColors.ink)),
            ]),
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(color: YeleColors.ink)),
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      );
}

/// Ce qui empêche de démarrer une campagne, ou null si tout est prêt.
/// Fonction pure, testée.
String? startProblem({
  required NetworkStatus? network,
  required bool phoneGranted,
  required bool locationGranted,
}) {
  if (network != null && network.isWifi) {
    return 'Coupez le Wi-Fi : en Wi-Fi, le test mesure la box et non '
        "l'opérateur mobile.";
  }
  if (network != null && !network.usesMobile) {
    return 'Activez les données mobiles avant de démarrer.';
  }
  if (!locationGranted) {
    return 'Autorisez la localisation : chaque mesure doit être placée.';
  }
  if (!phoneGranted) {
    return "Autorisez « Téléphone » : sans elle, pas d'opérateur ni de signal radio.";
  }
  return null;
}
