import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// État réseau à un instant donné.
///
/// Distingue deux notions volontairement séparées :
///  - [connectionType] : par où passe Internet *maintenant* (WiFi ou mobile) ;
///  - [cellularTech] / [simOperator] : la techno et l'opérateur de la **SIM**,
///    lisibles même quand Internet passe par le WiFi.
class NetworkStatus {
  /// 'WiFi', 'Mobile', 'Ethernet', 'Aucune', 'Web' ou 'Inconnu'.
  final String connectionType;

  /// Techno radio mobile : '2G'/'3G'/'4G'/'5G', ou null si indisponible.
  final String? cellularTech;

  /// Nom de l'opérateur SIM (Android). null/n.d. sur iOS 16+ ou sans SIM.
  /// Toujours celui de la SIM qui porte les données mobiles (ISS-02).
  final String? simOperator;

  /// Emplacement (1 ou 2) de la SIM de données, et nombre de SIM actives.
  final int? simSlot;
  final int simCount;

  /// Mesures radio de la cellule de service (ISS-01), null si indisponibles :
  /// puissance (dBm), RSRP et RSRQ (4G/5G), SINR (dB).
  final int? signalDbm;
  final int? rsrp;
  final int? rsrq;
  final int? sinr;

  const NetworkStatus({
    required this.connectionType,
    this.cellularTech,
    this.simOperator,
    this.simSlot,
    this.simCount = 1,
    this.signalDbm,
    this.rsrp,
    this.rsrq,
    this.sinr,
  });

  bool get isWifi => connectionType == 'WiFi';

  /// Vrai si le test passe par le réseau mobile : seules ces mesures portent
  /// des informations radio et d'opérateur SIM (ISS-03).
  bool get usesMobile => connectionType == 'Mobile';

  /// « 4G · Orange (SIM 2) », ou « Non utilisé (Wi-Fi) » : en Wi-Fi, le réseau
  /// mobile n'est PAS celui du test et ne doit pas être présenté comme tel.
  String get mobileLabel {
    if (!usesMobile) {
      return isWifi ? 'Non utilisé (Wi-Fi)' : '—';
    }
    return formatMobile(cellularTech, simOperator,
        simSlot: simCount > 1 ? simSlot : null);
  }

  /// Badge réseau affiché et stocké : 'WiFi' en WiFi, sinon la techno mobile.
  String get networkBadge =>
      isWifi ? 'WiFi' : (cellularTech ?? connectionType);

  @override
  String toString() => 'NetworkStatus($connectionType, tech=$cellularTech, '
      'sim=$simOperator, slot=$simSlot, rsrp=$rsrp, rsrq=$rsrq, sinr=$sinr)';
}

/// « 4G · Orange (SIM 2) », « 4G », ou « — » selon ce qui est disponible.
String formatMobile(String? tech, String? sim, {int? simSlot}) {
  final parts =
      [tech, sim].where((e) => e != null && e.isNotEmpty).join(' · ');
  if (parts.isEmpty) return '—';
  return simSlot != null ? '$parts (SIM $simSlot)' : parts;
}

/// « RSRP -95 dBm · RSRQ -11 dB · SINR 8 dB », ou null si rien n'est mesuré.
String? formatRadio({int? rsrp, int? rsrq, int? sinr, int? signalDbm}) {
  final parts = <String>[
    if (rsrp != null) 'RSRP $rsrp dBm',
    if (rsrq != null) 'RSRQ $rsrq dB',
    if (sinr != null) 'SINR $sinr dB',
  ];
  if (parts.isEmpty && signalDbm != null) parts.add('Signal $signalDbm dBm');
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Service d'information réseau : type de connexion (connectivity_plus) +
/// opérateur SIM et techno radio (canal natif [_channel]).
class NetworkInfoService {
  final logger = Logger();
  final Connectivity _connectivity = Connectivity();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  // Repli MCC/MNC → nom d'opérateur, utilisé uniquement quand le nom natif est
  // vide. Le nom fourni par le système reste la source principale. Limité au
  // Burkina Faso (pays de déploiement) pour éviter des libellés erronés.
  static const Map<String, String> operatorsByMccMnc = {
    '61301': 'Telmob (Onatel)', // MCC 613 = Burkina Faso
    '61302': 'Orange Burkina Faso',
    '61303': 'Telecel Faso',
  };

  /// Récupère l'état réseau complet.
  Future<NetworkStatus> getStatus() async {
    if (kIsWeb) {
      return const NetworkStatus(connectionType: 'Web');
    }

    final connectionType = await _connectionType();

    String? cellularTech;
    String? simOperator;
    int? simSlot, signalDbm, rsrp, rsrq, sinr;
    int simCount = 1;

    // Sur Android, on s'assure d'avoir la permission avant de lire.
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('requestPhonePermission');
      } catch (_) {
        // Permission non demandable : lecture en mode dégradé.
      }
    }

    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('getTelephony');
      if (info != null) {
        cellularTech = (info['cellularTech'] as String?)?.trim();
        if (cellularTech != null && cellularTech.isEmpty) cellularTech = null;

        simOperator = (info['simOperator'] as String?)?.trim();
        if (simOperator == null || simOperator.isEmpty) {
          final mccMnc = (info['mccMnc'] as String?)?.trim();
          simOperator = _operatorFromMccMnc(mccMnc);
        }
        int? asInt(String k) => (info[k] as num?)?.toInt();
        simSlot = asInt('simSlot');
        simCount = asInt('simCount') ?? 1;
        signalDbm = asInt('signalDbm');
        rsrp = asInt('rsrp');
        rsrq = asInt('rsrq');
        sinr = asInt('sinr');
      }
    } on MissingPluginException {
      // Canal natif absent (ex. tests) : on reste sur le type de connexion.
    } catch (e) {
      logger.w('Lecture téléphonie échouée: $e');
    }

    final status = NetworkStatus(
      connectionType: connectionType,
      cellularTech: cellularTech,
      simOperator: simOperator,
      simSlot: simSlot,
      simCount: simCount,
      signalDbm: signalDbm,
      rsrp: rsrp,
      rsrq: rsrq,
      sinr: sinr,
    );
    logger.i('📶 $status');
    return status;
  }

  Future<String> _connectionType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // connectivity_plus 6.x renvoie une liste ; on prend le lien actif.
      if (results.contains(ConnectivityResult.wifi)) return 'WiFi';
      if (results.contains(ConnectivityResult.mobile)) return 'Mobile';
      if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
      if (results.contains(ConnectivityResult.none)) return 'Aucune';
      return 'Inconnu';
    } catch (e) {
      logger.e('Erreur détection connexion: $e');
      return 'Inconnu';
    }
  }

  String? _operatorFromMccMnc(String? mccMnc) {
    if (mccMnc == null || mccMnc.isEmpty) return null;
    return operatorsByMccMnc[mccMnc];
  }

  // ── Compatibilité : anciens appels ponctuels ────────────────────────────────

  /// Badge réseau (WiFi / 4G / …). Conserve l'ancienne signature.
  Future<String?> getNetworkType() async => (await getStatus()).networkBadge;
}
