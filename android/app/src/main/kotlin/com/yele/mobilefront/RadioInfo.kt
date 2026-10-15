package com.yele.mobilefront

import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrength
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

/**
 * Lecture des informations radio de la SIM qui porte les DONNÉES MOBILES.
 *
 * Partagé par l'écran de test (MainActivity) et la collecte passive
 * (SignalCollectorService), pour que les deux relèvent exactement la même
 * chose.
 *
 * ISS-02 — double SIM : `getSystemService(TELEPHONY_SERVICE)` renvoie le
 * TelephonyManager de la SIM *par défaut*, presque toujours la SIM 1. Quand
 * l'utilisateur fait passer ses données par la SIM 2, l'opérateur affiché
 * était donc faux. On cible ici explicitement l'abonnement de données.
 *
 * ISS-01 — RSRP / RSRQ / SINR : lus sur la cellule de service, en 4G et en 5G.
 */
object RadioInfo {

    /** Valeur des API Android pour « mesure indisponible »
     *  (CellInfo.UNAVAILABLE, constante publiée seulement en API 29). */
    private const val UNAVAILABLE = Int.MAX_VALUE

    /** TelephonyManager de l'abonnement qui porte les données mobiles. */
    fun dataTelephony(context: Context): TelephonyManager? {
        val base = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            ?: return null
        val subId = SubscriptionManager.getDefaultDataSubscriptionId()
        if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) return base
        return try {
            base.createForSubscriptionId(subId)
        } catch (_: Exception) {
            base
        }
    }

    /**
     * Numéro d'emplacement (1 ou 2) de la SIM de données, ou null.
     * Nécessite READ_PHONE_STATE ; null sinon.
     */
    fun dataSimSlot(context: Context): Int? {
        val subId = SubscriptionManager.getDefaultDataSubscriptionId()
        if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) return null
        return try {
            val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager ?: return null
            sm.getActiveSubscriptionInfo(subId)?.simSlotIndex?.plus(1)
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    /** Nombre de SIM actives (1 si inconnu). */
    fun activeSimCount(context: Context): Int = try {
        val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
            as? SubscriptionManager
        sm?.activeSubscriptionInfoCount ?: 1
    } catch (_: Exception) {
        1
    }

    /**
     * Mesures radio de la cellule de service : clés `signalDbm`, `signalLevel`,
     * `rsrp`, `rsrq`, `sinr` (dB), et `nr` = true si une porteuse 5G est vue
     * (5G NSA, où `dataNetworkType` annonce encore « LTE »). Les valeurs
     * indisponibles sont omises.
     */
    fun signal(context: Context, tm: TelephonyManager): Map<String, Any> {
        val out = HashMap<String, Any>()

        // Android 10+ : forces de signal de l'abonnement ciblé, sans
        // permission de localisation.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val strengths = tm.signalStrength?.cellSignalStrengths.orEmpty()
                strengths.forEach { fill(out, it) }
                if (out.isNotEmpty()) return out
            } catch (_: Exception) {
            }
        }

        // Repli : cellule enregistrée dans allCellInfo (permission de
        // localisation requise ; les erreurs sont ignorées).
        try {
            tm.allCellInfo?.firstOrNull { it.isRegistered }?.let { cell ->
                when (cell) {
                    is CellInfoLte -> fill(out, cell.cellSignalStrength)
                    is CellInfoWcdma -> fill(out, cell.cellSignalStrength)
                    is CellInfoGsm -> fill(out, cell.cellSignalStrength)
                    else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        fillNrCell(out, cell)
                    }
                }
            }
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }
        return out
    }

    private fun fill(out: HashMap<String, Any>, s: CellSignalStrength) {
        // Le premier signal lu (cellule principale) fixe dBm et niveau.
        if (!out.containsKey("signalDbm") && s.dbm != UNAVAILABLE) {
            out["signalDbm"] = s.dbm
            out["signalLevel"] = s.level
        }
        if (s is CellSignalStrengthLte) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putIfValid(out, "rsrp", s.rsrp)
                putIfValid(out, "rsrq", s.rsrq)
                putIfValid(out, "sinr", s.rssnr)
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            fillNr(out, s)
        }
        // 2G/3G (GSM, WCDMA) : pas de RSRP/RSRQ, seul le dBm a un sens.
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun fillNr(out: HashMap<String, Any>, s: CellSignalStrength) {
        if (s !is CellSignalStrengthNr) return
        out["nr"] = true
        // En 5G NSA, la cellule LTE d'ancrage est lue en premier : la mesure
        // 5G, plus pertinente pour le débit, la remplace.
        putIfValid(out, "rsrp", s.ssRsrp, overwrite = true)
        putIfValid(out, "rsrq", s.ssRsrq, overwrite = true)
        putIfValid(out, "sinr", s.ssSinr, overwrite = true)
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun fillNrCell(out: HashMap<String, Any>, cell: android.telephony.CellInfo) {
        if (cell is CellInfoNr) fill(out, cell.cellSignalStrength)
    }

    private fun putIfValid(
        out: HashMap<String, Any>, key: String, value: Int, overwrite: Boolean = false,
    ) {
        if (value == UNAVAILABLE) return
        if (overwrite || !out.containsKey(key)) out[key] = value
    }

    /** Libellé de la technologie radio, "5G" si une porteuse NR est vue. */
    fun techLabel(type: Int, nrSeen: Boolean = false): String? {
        val base = when (type) {
            TelephonyManager.NETWORK_TYPE_GPRS,
            TelephonyManager.NETWORK_TYPE_EDGE,
            TelephonyManager.NETWORK_TYPE_CDMA,
            TelephonyManager.NETWORK_TYPE_1xRTT,
            TelephonyManager.NETWORK_TYPE_IDEN,
            TelephonyManager.NETWORK_TYPE_GSM -> "2G"

            TelephonyManager.NETWORK_TYPE_UMTS,
            TelephonyManager.NETWORK_TYPE_EVDO_0,
            TelephonyManager.NETWORK_TYPE_EVDO_A,
            TelephonyManager.NETWORK_TYPE_HSDPA,
            TelephonyManager.NETWORK_TYPE_HSUPA,
            TelephonyManager.NETWORK_TYPE_HSPA,
            TelephonyManager.NETWORK_TYPE_EVDO_B,
            TelephonyManager.NETWORK_TYPE_EHRPD,
            TelephonyManager.NETWORK_TYPE_HSPAP,
            TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "3G"

            TelephonyManager.NETWORK_TYPE_LTE,
            TelephonyManager.NETWORK_TYPE_IWLAN -> "4G"

            TelephonyManager.NETWORK_TYPE_NR -> "5G"

            else -> null
        }
        return if (base == "4G" && nrSeen) "5G" else base
    }

    /** Techno de données de l'abonnement ciblé (READ_PHONE_STATE requis). */
    @Suppress("DEPRECATION")
    fun dataNetworkType(tm: TelephonyManager): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) tm.dataNetworkType
        else tm.networkType
}
