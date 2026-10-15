package com.yele.mobilefront

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.TrafficStats
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Moniteur de débit en temps réel (IMP-08), à la manière de nPerf.
 *
 * Affiche dans une notification permanente le débit descendant et montant
 * de TOUT le téléphone (TrafficStats.getTotal*), rafraîchi chaque seconde,
 * ainsi que les données consommées depuis son activation. Il ne fait aucune
 * mesure active et n'envoie rien : il lit seulement les compteurs système.
 *
 * Lancé et arrêté depuis les réglages, ou depuis l'action « Arrêter » de la
 * notification.
 */
class ThroughputMonitorService : Service() {

    companion object {
        const val ACTION_START = "com.yele.mobilefront.MONITOR_START"
        const val ACTION_STOP = "com.yele.mobilefront.MONITOR_STOP"
        private const val CHANNEL_ID = "yele_throughput"
        private const val NOTIFICATION_ID = 4202
        private const val PERIOD_MS = 1000L

        @Volatile
        var isRunning = false
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastRx = 0L
    private var lastTx = 0L
    private var lastAt = 0L
    private var startRx = 0L
    private var startTx = 0L

    private val tick = object : Runnable {
        override fun run() {
            if (!isRunning) return
            update()
            handler.postDelayed(this, PERIOD_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stop()
            return START_NOT_STICKY
        }
        if (isRunning) return START_STICKY

        createChannel()
        val notification = build("Mesure en cours…", "")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this, NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        isRunning = true
        lastRx = TrafficStats.getTotalRxBytes()
        lastTx = TrafficStats.getTotalTxBytes()
        startRx = lastRx
        startTx = lastTx
        lastAt = SystemClock.elapsedRealtime()
        handler.postDelayed(tick, PERIOD_MS)
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun stop() {
        isRunning = false
        handler.removeCallbacks(tick)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun update() {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        val now = SystemClock.elapsedRealtime()
        val seconds = ((now - lastAt).coerceAtLeast(1)) / 1000.0
        // Compteurs indisponibles sur certains appareils : UNSUPPORTED = -1.
        if (rx < 0 || tx < 0) {
            notify(build("Compteurs réseau indisponibles sur ce téléphone", ""))
            return
        }
        val down = (rx - lastRx).coerceAtLeast(0) * 8 / seconds / 1_000_000
        val up = (tx - lastTx).coerceAtLeast(0) * 8 / seconds / 1_000_000
        lastRx = rx
        lastTx = tx
        lastAt = now

        val usedMb = ((rx - startRx) + (tx - startTx)).coerceAtLeast(0) / 1_048_576.0
        notify(
            build(
                "↓ ${format(down)} Mb/s   ↑ ${format(up)} Mb/s",
                "Données depuis l'activation : ${"%.1f".format(usedMb)} Mo",
            )
        )
    }

    private fun format(mbps: Double) =
        if (mbps < 10) "%.2f".format(mbps) else "%.1f".format(mbps)

    private fun notify(n: Notification) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, n)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID, "Débit en temps réel", NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Débit descendant et montant du téléphone, chaque seconde"
            setShowBadge(false)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun build(title: String, text: String): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 2,
            Intent(this, ThroughputMonitorService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(openApp)
            .addAction(0, "Arrêter", stop)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
