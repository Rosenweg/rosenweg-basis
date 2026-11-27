// SPDX-License-Identifier: GPL-3.0-or-later
package ch.rosenweg4303.basis

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.nfc.NfcAdapter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import ch.rosenweg4303.anmeldeschirm.Kartenleser
import io.flutter.plugin.common.EventChannel

/**
 * Rosenweg-Karte in der App lesen (nicht nur auf dem Anmeldeschirm), z. B. fuer Rosenweg Karten
 * (Karte anlernen, nachschlagen). Derselbe Leser wie im Anmeldeschirm von commons-rosenweg
 * ([Kartenleser.FLAGS], [Kartenleser.uid], [Kartenleser.Entpreller]): nur die UID als Hex.
 *
 * Richtung Dart: EventChannel [KANAL]. Solange Dart zuhoert, ist der Reader-Modus der Activity an
 * (Android schaltet ihn beim Pausieren selbst ab; beim Fortsetzen wieder ein). Ereignis = UID.
 *
 * Methoden (ueber den Hauptkanal): nfcStand -> "fehlt" | "aus" | "an", nfcEinstellungen.
 */
internal class NfcKarte(private val kontext: Context) : EventChannel.StreamHandler {
    private val haupt = Handler(Looper.getMainLooper())
    private var senke: EventChannel.EventSink? = null
    private var aktivitaet: Activity? = null
    private var entpreller = Kartenleser.Entpreller()
    private var rueckrufe: Application.ActivityLifecycleCallbacks? = null

    fun stand(): String {
        val n = NfcAdapter.getDefaultAdapter(kontext) ?: return "fehlt"
        return if (n.isEnabled) "an" else "aus"
    }

    fun einstellungen(a: Activity?) {
        val i = Intent(Settings.ACTION_NFC_SETTINGS)
        try {
            if (a != null) a.startActivity(i) else kontext.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            val w = Intent(Settings.ACTION_WIRELESS_SETTINGS)
            if (a != null) a.startActivity(w) else kontext.startActivity(w.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /** Vom Plugin bei jedem Wechsel der Activity. */
    fun aktivitaet(a: Activity?) {
        if (a === aktivitaet) return
        aus()
        rueckrufe?.let { aktivitaet?.application?.unregisterActivityLifecycleCallbacks(it) }
        rueckrufe = null
        aktivitaet = a
        if (a == null) return
        val r = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(x: Activity) { if (x === aktivitaet) ein() }
            override fun onActivityPaused(x: Activity) { if (x === aktivitaet) aus() }
            override fun onActivityCreated(x: Activity, b: Bundle?) {}
            override fun onActivityStarted(x: Activity) {}
            override fun onActivityStopped(x: Activity) {}
            override fun onActivitySaveInstanceState(x: Activity, b: Bundle) {}
            override fun onActivityDestroyed(x: Activity) {}
        }
        a.application.registerActivityLifecycleCallbacks(r)
        rueckrufe = r
        ein()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        senke = events
        entpreller = Kartenleser.Entpreller()
        ein()
    }

    override fun onCancel(arguments: Any?) {
        senke = null
        aus()
    }

    private fun ein() {
        val a = aktivitaet ?: return
        if (senke == null) return
        val n = NfcAdapter.getDefaultAdapter(kontext) ?: return
        try {
            n.enableReaderMode(a, { tag ->
                val uid = Kartenleser.uid(tag) ?: return@enableReaderMode
                if (!entpreller.neu(uid)) return@enableReaderMode
                haupt.post { senke?.success(uid) }
            }, Kartenleser.FLAGS, null)
        } catch (e: Exception) {
            // z. B. Activity nicht im Vordergrund: beim naechsten onResume wieder
            Log.w(RosenwegBasisPlugin.TAG, "NFC ein: ${e.javaClass.simpleName}")
        }
    }

    private fun aus() {
        val a = aktivitaet ?: return
        val n = NfcAdapter.getDefaultAdapter(kontext) ?: return
        try {
            n.disableReaderMode(a)
        } catch (_: Exception) {
        }
    }

    companion object {
        const val KANAL = "ch.rosenweg4303.basis/karte"
    }
}
