package com.yele.mobilefront

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Relance la collecte après un redémarrage du téléphone, si l'utilisateur ne
 * l'avait pas arrêtée lui-même.
 *
 * Limite connue : à partir d'Android 14, le système refuse le démarrage d'un
 * service de premier plan de type `location` depuis l'arrière-plan, y compris
 * au démarrage. La tentative échoue alors silencieusement et la collecte
 * reprend à la prochaine ouverture de l'application. C'est pourquoi l'échec
 * est ici absorbé plutôt que remonté : il est attendu sur ces versions.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        resumeControl(context)
        if (!SignalCollectorService.prefs(context)
                .getBoolean(SignalCollectorService.KEY_ENABLED, false)
        ) return

        val service = Intent(context, SignalCollectorService::class.java)
            .setAction(SignalCollectorService.ACTION_START)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, service)
            } else {
                context.startService(service)
            }
        } catch (_: Exception) {
            // Démarrage refusé par le système : reprise au prochain lancement.
        }
    }

    /**
     * Mode Contrôle : une campagne était en cours au moment de l'arrêt.
     * Le service de maintien en éveil est relancé quand le système l'accepte
     * (avant Android 14) ; dans tous les cas, l'agent est prévenu par une
     * notification qui ouvre l'app, où la boucle de mesure reprend seule.
     */
    private fun resumeControl(context: Context) {
        val prefs = ControlService.prefs(context)
        if (!prefs.getBoolean(ControlService.KEY_ACTIVE, false)) return
        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, ControlService::class.java)
                    .setAction(ControlService.ACTION_START)
                    .putExtra(
                        ControlService.EXTRA_CAMPAIGN,
                        prefs.getString(ControlService.KEY_CAMPAIGN, "")
                    )
            )
        } catch (_: Exception) {
            // Refusé depuis l'arrière-plan (Android 14+) : la notification
            // ci-dessous ramène l'agent dans l'app.
        }
        notifyResume(context, prefs.getString(ControlService.KEY_CAMPAIGN, "") ?: "")
    }

    private fun notifyResume(context: Context, campaign: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as android.app.NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                android.app.NotificationChannel(
                    "yele_control_resume", "Reprise du mode Contrôle",
                    android.app.NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }
        val open = android.app.PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            android.app.PendingIntent.FLAG_IMMUTABLE or
                android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = androidx.core.app.NotificationCompat.Builder(context, "yele_control_resume")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Campagne $campaign interrompue")
            .setContentText("Le téléphone a redémarré. Touchez pour reprendre la mesure.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(4302, notification)
        } catch (_: SecurityException) {
            // Notifications refusées : la reprise se fera à l'ouverture de l'app.
        }
    }
}
