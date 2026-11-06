package com.yele.mobilefront

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Mode Contrôle (drive test / walk test de l'autorité) : garde le téléphone
 * éveillé pendant toute une campagne.
 *
 * Les tests eux-mêmes tournent côté Dart (même moteur que l'app citoyenne).
 * Ce service apporte ce que Dart ne peut pas obtenir seul :
 *  - un service de premier plan de type `location`, que le système n'arrête
 *    pas et qui autorise la lecture du GPS écran éteint ;
 *  - un verrou de réveil partiel : le processeur reste actif, donc la boucle
 *    de mesure continue même téléphone verrouillé ;
 *  - une notification permanente qui affiche l'avancement de la campagne.
 *
 * L'état « campagne en cours » est gardé dans les préférences : après un
 * redémarrage du téléphone, [BootReceiver] affiche une notification qui
 * ramène l'agent dans l'app, où la campagne reprend seule.
 */
class ControlService : Service() {

    companion object {
        const val ACTION_START = "com.yele.mobilefront.START_CONTROL"
        const val ACTION_STOP = "com.yele.mobilefront.STOP_CONTROL"
        const val ACTION_UPDATE = "com.yele.mobilefront.UPDATE_CONTROL"
        const val EXTRA_CAMPAIGN = "campaign"
        const val EXTRA_TEXT = "text"

        const val PREFS = "yele_control"
        const val KEY_ACTIVE = "control_active"
        const val KEY_CAMPAIGN = "control_campaign"

        private const val CHANNEL_ID = "yele_control"
        const val NOTIFICATION_ID = 4301

        // Plafond du verrou de réveil : une journée de campagne. Au-delà, il
        // est relâché même si l'arrêt n'a jamais été demandé (sécurité batterie).
        private const val WAKE_LOCK_MAX_MS = 14L * 60 * 60 * 1000

        @Volatile
        var isRunning: Boolean = false
            private set

        fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Batterie et température, lues sans démarrer le service. */
        fun health(context: Context): Map<String, Any?> {
            val status = context.registerReceiver(
                null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            val level = status?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = status?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
            val temp = status?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                ?: Int.MIN_VALUE
            val plugged = (status?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return mapOf(
                "batteryPercent" to if (level >= 0 && scale > 0) level * 100 / scale else null,
                // EXTRA_TEMPERATURE est en dixièmes de degré Celsius.
                "batteryTempC" to if (temp != Int.MIN_VALUE) temp / 10.0 else null,
                "charging" to plugged,
                "ignoringBatteryOptimizations" to
                    (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                        pm.isIgnoringBatteryOptimizations(context.packageName)),
            )
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var campaign: String = ""
    private var lastText: String = "Démarrage de la campagne…"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopControl()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                lastText = intent.getStringExtra(EXTRA_TEXT) ?: lastText
                if (isRunning) notifyNow()
                return START_STICKY
            }
        }

        campaign = intent?.getStringExtra(EXTRA_CAMPAIGN)
            ?: prefs(this).getString(KEY_CAMPAIGN, "") ?: ""
        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true
        prefs(this).edit()
            .putBoolean(KEY_ACTIVE, true)
            .putString(KEY_CAMPAIGN, campaign)
            .apply()
        acquireWakeLock()
        // START_STICKY : si Android tue le processus faute de mémoire, le
        // service est recréé et la notification ramène l'agent dans l'app.
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        isRunning = false
        super.onDestroy()
    }

    private fun stopControl() {
        prefs(this).edit().putBoolean(KEY_ACTIVE, false).apply()
        releaseWakeLock()
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "yele:control").apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_MAX_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Mode Contrôle",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Campagne de mesure en cours (drive test / walk test)"
            setShowBadge(false)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val title = if (campaign.isEmpty()) "Yélé Contrôle" else "Yélé Contrôle — $campaign"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(lastText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(lastText))
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun notifyNow() {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification())
    }
}
