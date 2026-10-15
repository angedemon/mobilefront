package com.yele.mobilefront

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.yele/telephony"
    private val phonePermissionRequestCode = 1001
    private val notificationPermissionRequestCode = 1002

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTelephony" -> result.success(telephonyInfo())
                    "requestPhonePermission" -> result.success(ensurePhonePermission())
                    "getRxBytes" -> result.success(rxBytes())
                    "getTxBytes" -> result.success(txBytes())
                    "getDeviceUuid" -> result.success(deviceUuid())
                    "startCollect" -> {
                        val interval = call.argument<Int>("intervalMinutes")
                            ?: SignalCollectorService.DEFAULT_INTERVAL_MIN
                        val apiBase = call.argument<String>("apiBaseUrl")
                        result.success(startCollect(interval, apiBase))
                    }
                    "stopCollect" -> {
                        stopCollect()
                        result.success(true)
                    }
                    "getCollectStatus" -> result.success(collectStatus())
                    // IMP-04 : état et demande des autorisations
                    "getPermissions" -> result.success(permissionStates())
                    "requestPermission" -> {
                        requestPermission(call.argument<String>("name"))
                        result.success(true)
                    }
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(true)
                    }
                    // IMP-08 : moniteur de débit et alerte de consommation
                    "startMonitor" -> result.success(startMonitor())
                    "stopMonitor" -> {
                        startService(
                            Intent(this, ThroughputMonitorService::class.java)
                                .setAction(ThroughputMonitorService.ACTION_STOP)
                        )
                        result.success(true)
                    }
                    "isMonitorRunning" -> result.success(ThroughputMonitorService.isRunning)
                    "notifyDataAlert" -> {
                        notifyDataAlert(
                            call.argument<String>("title") ?: "Yélé",
                            call.argument<String>("text") ?: "",
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Retourne true si READ_PHONE_STATE est déjà accordée ; sinon déclenche la
    /// demande runtime (le résultat sera disponible aux prochaines lectures).
    private fun ensurePhonePermission(): Boolean {
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.READ_PHONE_STATE), phonePermissionRequestCode
            )
        }
        return granted
    }

    /// Octets reçus par l'application depuis le démarrage de l'appareil, ou -1
    /// si l'appareil ne tient pas ce compteur. Inclut le trafic du WebView : la
    /// pile réseau de Chromium tourne dans le processus de l'app, donc sous le
    /// même UID.
    private fun rxBytes(): Long {
        val bytes = TrafficStats.getUidRxBytes(Process.myUid())
        return if (bytes == TrafficStats.UNSUPPORTED.toLong()) -1L else bytes
    }

    /// Octets émis par l'application (IMP-01 : données consommées par un test
    /// = octets reçus + émis). -1 si le compteur est indisponible.
    private fun txBytes(): Long {
        val bytes = TrafficStats.getUidTxBytes(Process.myUid())
        return if (bytes == TrafficStats.UNSUPPORTED.toLong()) -1L else bytes
    }

    /// Identifiant d'appareil anonyme et stable (IMP-13).
    ///
    /// ANDROID_ID est propre à l'appareil ET à la clé de signature de l'app
    /// (Android 8+) : il survit à une réinstallation et ne permet pas de
    /// suivre l'appareil d'une application à l'autre. On n'en transmet qu'une
    /// empreinte SHA-256 salée, mise en forme d'UUID : impossible d'en
    /// retrouver la valeur d'origine. Il change après une réinitialisation
    /// d'usine, ce qui est voulu.
    private fun deviceUuid(): String? {
        val androidId = try {
            android.provider.Settings.Secure.getString(
                contentResolver, android.provider.Settings.Secure.ANDROID_ID
            )
        } catch (e: Exception) {
            null
        } ?: return null
        val digest = java.security.MessageDigest.getInstance("SHA-256")
            .digest("yele-device:$androidId".toByteArray(Charsets.UTF_8))
        val hex = digest.take(16).joinToString("") { "%02x".format(it) }
        // Mise en forme 8-4-4-4-12, version 5 (dérivé d'un nom) et variante RFC.
        val chars = hex.toCharArray()
        chars[12] = '5'
        chars[16] = "89ab"[(Character.digit(chars[16], 16) and 0x3)]
        val h = String(chars)
        return "${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-" +
            "${h.substring(16, 20)}-${h.substring(20, 32)}"
    }

    // ── Autorisations (IMP-04) ──────────────────────────────────────────────

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    /// { location, preciseLocation, phone, notifications } : true si accordée.
    private fun permissionStates(): Map<String, Boolean> = mapOf(
        "location" to (granted(Manifest.permission.ACCESS_COARSE_LOCATION) ||
            granted(Manifest.permission.ACCESS_FINE_LOCATION)),
        "preciseLocation" to granted(Manifest.permission.ACCESS_FINE_LOCATION),
        "phone" to granted(Manifest.permission.READ_PHONE_STATE),
        "notifications" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            granted(Manifest.permission.POST_NOTIFICATIONS)),
    )

    private fun requestPermission(name: String?) {
        val perms = when (name) {
            "location", "preciseLocation" -> arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            )
            "phone" -> arrayOf(Manifest.permission.READ_PHONE_STATE)
            "notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                arrayOf(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                return
            }
            else -> return
        }
        ActivityCompat.requestPermissions(this, perms, 1003)
    }

    private fun openAppSettings() {
        startActivity(
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(android.net.Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    // ── Moniteur de débit et alerte de consommation (IMP-08) ────────────────

    /// false si la notification est refusée (Android 13+) : la demande est
    /// alors affichée et l'appel est à refaire.
    private fun startMonitor(): Boolean {
        if (!permissionStates().getValue("notifications")) {
            requestPermission("notifications")
            return false
        }
        ContextCompat.startForegroundService(
            this,
            Intent(this, ThroughputMonitorService::class.java)
                .setAction(ThroughputMonitorService.ACTION_START),
        )
        return true
    }

    private fun notifyDataAlert(title: String, text: String) {
        if (!permissionStates().getValue("notifications")) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE)
            as android.app.NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                android.app.NotificationChannel(
                    "yele_alerts", "Alertes de consommation",
                    android.app.NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
        val n = androidx.core.app.NotificationCompat.Builder(this, "yele_alerts")
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(androidx.core.app.NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .build()
        manager.notify(4203, n)
    }

    // ── Collecte passive en arrière-plan ────────────────────────────────────

    /// Démarre le service de collecte. Retourne false si la notification est
    /// refusée : sans elle, Android tue immédiatement un service de premier
    /// plan, et la collecte s'arrêterait sans que l'utilisateur comprenne.
    private fun startCollect(intervalMinutes: Int, apiBaseUrl: String?): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequestCode,
            )
            return false
        }

        SignalCollectorService.prefs(this).edit()
            .putInt(SignalCollectorService.KEY_INTERVAL, intervalMinutes)
            .apply {
                if (apiBaseUrl != null) {
                    putString(SignalCollectorService.KEY_API_BASE, apiBaseUrl)
                }
            }
            .apply()

        val intent = Intent(this, SignalCollectorService::class.java)
            .setAction(SignalCollectorService.ACTION_START)
        ContextCompat.startForegroundService(this, intent)
        return true
    }

    private fun stopCollect() {
        val intent = Intent(this, SignalCollectorService::class.java)
            .setAction(SignalCollectorService.ACTION_STOP)
        try {
            startService(intent)
        } catch (e: Exception) {
            // Service déjà arrêté : on met simplement l'état à jour.
            SignalCollectorService.prefs(this).edit()
                .putBoolean(SignalCollectorService.KEY_ENABLED, false).apply()
        }
    }

    /// Retourne { running, intervalMinutes, lastCollectAt, count }.
    private fun collectStatus(): Map<String, Any?> {
        val p = SignalCollectorService.prefs(this)
        return mapOf(
            "running" to SignalCollectorService.isRunning,
            "enabled" to p.getBoolean(SignalCollectorService.KEY_ENABLED, false),
            "intervalMinutes" to p.getInt(
                SignalCollectorService.KEY_INTERVAL,
                SignalCollectorService.DEFAULT_INTERVAL_MIN,
            ),
            "lastCollectAt" to p.getLong(SignalCollectorService.KEY_LAST_AT, 0L),
            "count" to p.getInt(SignalCollectorService.KEY_COUNT, 0),
        )
    }

    /// Retourne, pour la SIM qui porte les DONNÉES mobiles (ISS-02) :
    /// { simOperator, mccMnc, cellularTech, simSlot, simCount,
    ///   signalDbm, signalLevel, rsrp, rsrq, sinr } — champs absents ou null
    /// si indisponibles (ISS-01).
    private fun telephonyInfo(): Map<String, Any?> {
        val info = HashMap<String, Any?>()
        info["simOperator"] = null
        info["mccMnc"] = null
        info["cellularTech"] = null

        val tm = RadioInfo.dataTelephony(this) ?: return info
        try {
            // Nom de l'opérateur sur lequel la SIM de données est enregistrée.
            val name = tm.networkOperatorName?.trim()
            if (!name.isNullOrEmpty()) info["simOperator"] = name

            // MCC+MNC (ex. "61301") — permet un mapping fiable côté Dart.
            val mccMnc = tm.networkOperator?.trim()
            if (!mccMnc.isNullOrEmpty()) info["mccMnc"] = mccMnc
        } catch (e: SecurityException) {
            // Permission manquante : on laisse simOperator/mccMnc à null.
        } catch (e: Exception) {
            // Ignorer toute erreur constructeur.
        }

        info["simSlot"] = RadioInfo.dataSimSlot(this)
        info["simCount"] = RadioInfo.activeSimCount(this)

        val signal = try {
            RadioInfo.signal(this, tm)
        } catch (e: Exception) {
            emptyMap()
        }
        info.putAll(signal.filterKeys { it != "nr" })

        // Techno radio : nécessite READ_PHONE_STATE sur Android 10+.
        try {
            info["cellularTech"] = RadioInfo.techLabel(
                RadioInfo.dataNetworkType(tm), nrSeen = signal["nr"] == true
            )
        } catch (e: SecurityException) {
            // Permission manquante : techno inconnue.
        } catch (e: Exception) {
            // Ignorer.
        }

        return info
    }
}
