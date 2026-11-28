// SPDX-License-Identifier: GPL-3.0-or-later
package ch.rosenweg4303.basis

import android.content.BroadcastReceiver
import android.content.Context
import android.app.NotificationManager
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * Geteilte Telefone: Rosenweg Geraet meldet jeder Katalog-App, wenn sich am Telefon
 * jemand an- oder abmeldet (Katalog.freigeben/sperren in android-sip-rosenweg:
 * Broadcasts ch.rosenweg4303.ANGEMELDET / ABGEMELDET an das Paket). Hier kommen nur
 * Broadcasts von Apps mit ch.rosenweg4303.permission.ANLAGE an (signature), also von
 * Rosenweg Geraet selbst — keine fremde App kann die App so neu laden lassen.
 *
 * Richtung Dart: EventChannel [KANAL], Ereignis "angemeldet" oder "abgemeldet".
 * Der Empfaenger lebt nur, solange Dart zuhoert (die App laeuft).
 */
internal class GeraetPerson(private val kontext: Context) : EventChannel.StreamHandler {
    private var empfaenger: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        val e = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                // Alles Gezeigte der vorigen Person sofort weg; Aufgaben und geplante Erinnerungen
                // raeumt Dart auf (Sitzung.personGewechselt), die Daten Rosenweg Geraet.
                try {
                    (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
                } catch (_: Exception) {
                }
                events.success(if (i.action == ABGEMELDET) "abgemeldet" else "angemeldet")
            }
        }
        val f = IntentFilter().apply {
            addAction(ANGEMELDET)
            addAction(ABGEMELDET)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            kontext.registerReceiver(e, f, ANLAGE, null, Context.RECEIVER_EXPORTED)
        } else {
            kontext.registerReceiver(e, f, ANLAGE, null)
        }
        empfaenger = e
    }

    override fun onCancel(arguments: Any?) {
        val e = empfaenger ?: return
        empfaenger = null
        try {
            kontext.unregisterReceiver(e)
        } catch (_: IllegalArgumentException) {
        }
    }

    companion object {
        const val KANAL = "ch.rosenweg4303.basis/person"
        const val ANGEMELDET = "ch.rosenweg4303.ANGEMELDET"
        const val ABGEMELDET = "ch.rosenweg4303.ABGEMELDET"
        const val ANLAGE = "ch.rosenweg4303.permission.ANLAGE"
    }
}
