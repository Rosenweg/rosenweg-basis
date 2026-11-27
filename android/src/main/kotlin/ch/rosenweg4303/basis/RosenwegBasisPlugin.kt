// SPDX-License-Identifier: GPL-3.0-or-later
package ch.rosenweg4303.basis

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import ch.rosenweg4303.cloud.RosenwegAnmeldeSchirm
import ch.rosenweg4303.cloud.RosenwegAnmeldung
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Android-Teil von rosenweg_basis. Ein Kanal "ch.rosenweg4303.basis":
 *
 *  - dnsServer               DNS-Server des aktiven Netzes (Haus-Erkennung)
 *  - ruecksprungAusstehend   Ruecksprung der Anmeldung, der kam, bevor Dart lauschte
 *                            (App war im Hintergrund beendet); einmalig
 *  - geraetDa                Rosenweg Geraet installiert (geteiltes Telefon)?
 *  - updaterPruefen          "Nach Updates suchen": RosenwegUpdater.jetztPruefen (zeigt selbst
 *                            "Aktuell" / "Neue Fassung X - Installieren" / Fehler) -> true
 *  - nfcStand                "fehlt" | "aus" | "an"; nfcEinstellungen (NFC-Einstellungen oeffnen)
 *                            Karte lesen: EventChannel "ch.rosenweg4303.basis/karte" (NfcKarte.kt)
 *  - startsymbolSetzen       {gruppe} -> Startsymbol in der Gruppenfarbe (Startsymbol.kt), true = gewechselt
 *  - geraetRufen             ContentResolver.call auf content://ch.rosenweg4303.telefon.anlage
 *                            {methode, arg, extras} -> Bundle als Map (nur Strings, Zahlen, bool)
 *
 * Anmeldung auf Handys ohne Rosenweg Geraet - ueber commons-rosenweg (cloud), wie in den
 * Kotlin-Apps (Stefan 26.11.2026: ein Anmeldeschirm fuer alle, nur einmal gepflegt):
 *  - kontoStand              {angemeldet, name, email, mitKarte}
 *  - anmeldeSchirm           RosenwegAnmeldeSchirm (Karte oder Rosenweg-Konto) -> true = angemeldet;
 *                            Argument "gruppe" (bewohner/verwaltung/technik) = Farbe
 *  - zugangsToken            Zugang fuer die API (Browser oder Karte), null = abgemeldet;
 *                            Fehler "netz" = Server nur gerade nicht erreichbar
 *  - zugangUngueltig, abmelden (nur diese App)
 *  - bestaetigen             Browser mit prompt=login; angemeldetUm zeigt, wann es geklappt hat
 *
 * Den Ruecksprung des Browsers (<applicationId>:/anmeldung) nimmt RosenwegAnmeldungActivity aus
 * commons-rosenweg an; Dart-Ruecksprung gibt es auf Android nicht mehr (ruecksprungAusstehend
 * bleibt fuer die Schnittstelle, liefert null).
 */
class RosenwegBasisPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private var kanal: MethodChannel? = null
    private var person: EventChannel? = null
    private var personQuelle: GeraetPerson? = null
    private var karte: EventChannel? = null
    private var karteQuelle: NfcKarte? = null
    private var kontext: Context? = null
    private val netz = Executors.newSingleThreadExecutor()
    private val haupt = Handler(Looper.getMainLooper())
    private var aktivitaet: ActivityPluginBinding? = null
    private var schirmErgebnis: MethodChannel.Result? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        aktivitaet = binding
        binding.addActivityResultListener(this)
        karteQuelle?.aktivitaet(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        aktivitaet?.removeActivityResultListener(this)
        aktivitaet = null
        karteQuelle?.aktivitaet(null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != ANMELDESCHIRM) return false
        val r = schirmErgebnis ?: return true
        schirmErgebnis = null
        val c = kontext
        r.success(c != null && RosenwegAnmeldung.angemeldet(c))
        return true
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kontext = binding.applicationContext
        kanal = MethodChannel(binding.binaryMessenger, KANAL).also { it.setMethodCallHandler(this) }
        // Geteilte Telefone: An-/Abmeldung am Telefon (eigener Kanal, GeraetPerson.kt)
        val quelle = GeraetPerson(binding.applicationContext)
        personQuelle = quelle
        person = EventChannel(binding.binaryMessenger, GeraetPerson.KANAL).also { it.setStreamHandler(quelle) }
        // Rosenweg-Karte in der App lesen (NfcKarte.kt)
        val k = NfcKarte(binding.applicationContext)
        karteQuelle = k
        karte = EventChannel(binding.binaryMessenger, NfcKarte.KANAL).also { it.setStreamHandler(k) }
        aktiv = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kanal?.setMethodCallHandler(null)
        kanal = null
        person?.setStreamHandler(null)
        person = null
        personQuelle?.onCancel(null)   // Empfaenger abmelden
        personQuelle = null
        karte?.setStreamHandler(null)
        karte = null
        karteQuelle?.onCancel(null)
        karteQuelle?.aktivitaet(null)
        karteQuelle = null
        if (aktiv === this) aktiv = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val c = kontext ?: return result.error("kein_kontext", "Plugin nicht verbunden", null)
        when (call.method) {
            "startsymbolSetzen" -> {
                val c = kontext
                val g = call.argument<String>("gruppe")
                result.success(c != null && g != null && Startsymbol.setzen(c, g))
            }
            "dnsServer" -> {
                // Android hat keine resolv.conf; die Server stehen in den
                // LinkProperties des aktiven Netzes (wie rosenweg-vm MainActivity.kt).
                val cm = c.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val server = cm.activeNetwork?.let { cm.getLinkProperties(it)?.dnsServers }
                    ?.mapNotNull { it.hostAddress } ?: emptyList()
                result.success(server)
            }
            "ruecksprungAusstehend" -> {
                val u = ausstehend
                ausstehend = null
                result.success(u)
            }
            "updaterPruefen" -> {
                ch.rosenweg4303.updater.RosenwegUpdater.jetztPruefen(aktivitaet?.activity ?: c)
                result.success(true)
            }
            "geraetDa" -> result.success(
                try {
                    c.packageManager.resolveContentProvider(ANLAGE_AUTHORITY, 0) != null
                } catch (e: Exception) {
                    false
                }
            )
            "geraetRufen" -> {
                val methode = call.argument<String>("methode") ?: return result.error("argument", "methode fehlt", null)
                val arg = call.argument<String>("arg")
                val extras = call.argument<Map<String, Any?>>("extras")
                // Der Provider geht ins Netz: nie im UI-Thread.
                netz.execute {
                    val antwort: Any? = try {
                        val b = Bundle()
                        extras?.forEach { (k, v) ->
                            when (v) {
                                is String -> b.putString(k, v)
                                is Int -> b.putInt(k, v)
                                is Long -> b.putLong(k, v)
                                is Boolean -> b.putBoolean(k, v)
                                null -> {}
                                else -> b.putString(k, v.toString())
                            }
                        }
                        val r = c.contentResolver.call(Uri.parse("content://$ANLAGE_AUTHORITY"), methode, arg, b)
                        r?.let { bundle -> bundle.keySet().associateWith { k -> einfach(bundle, k) } } ?: emptyMap<String, Any?>()
                    } catch (e: SecurityException) {
                        mapOf("fehler_art" to "signatur")
                    } catch (e: IllegalArgumentException) {
                        mapOf("fehler_art" to "nicht_installiert")
                    } catch (e: Exception) {
                        Log.w(TAG, "geraetRufen $methode: ${e.javaClass.simpleName}")
                        mapOf("fehler_art" to "unbekannt", "fehler" to (e.message ?: e.javaClass.simpleName))
                    }
                    haupt.post { result.success(antwort) }
                }
            }
            "kontoStand" -> result.success(mapOf(
                "angemeldet" to RosenwegAnmeldung.angemeldet(c),
                "name" to RosenwegAnmeldung.name(c),
                "email" to RosenwegAnmeldung.email(c),
                "mitKarte" to RosenwegAnmeldung.mitKarte(c),
            ))
            "anmeldeSchirm" -> {
                val a = aktivitaet?.activity ?: return result.error("keine_aktivitaet", "App nicht im Vordergrund", null)
                if (RosenwegAnmeldung.angemeldet(c)) return result.success(true)
                schirmErgebnis?.success(false)
                schirmErgebnis = result
                // Farbe wie das Logo der App (RosenwegApp.gruppe). Als Text statt
                // RosenwegAnmeldeSchirm.EXTRA_GRUPPE, damit es auch mit cloud < 0.13.6 baut
                // (dort wird das Extra nicht gelesen: blau).
                val i = Intent(a, RosenwegAnmeldeSchirm::class.java)
                call.argument<String>("gruppe")?.let { i.putExtra("ch.rosenweg4303.cloud.GRUPPE", it) }
                a.startActivityForResult(i, ANMELDESCHIRM)
            }
            "zugangsToken" -> netz.execute {
                // blockiert (Erneuern ueber das Netz): nie im UI-Thread
                try {
                    val t = RosenwegAnmeldung.zugangsToken(c)
                    haupt.post { result.success(t) }
                } catch (e: java.io.IOException) {
                    haupt.post { result.error("netz", "Server nicht erreichbar", null) }
                } catch (e: Exception) {
                    Log.w(TAG, "zugangsToken: ${e.javaClass.simpleName}")
                    haupt.post { result.error("unbekannt", e.javaClass.simpleName, null) }
                }
            }
            "zugangUngueltig" -> {
                RosenwegAnmeldung.zugangUngueltig()
                result.success(null)
            }
            "abmelden" -> {
                RosenwegAnmeldung.abmelden(c)
                result.success(null)
            }
            "angemeldetUm" -> result.success(RosenwegAnmeldung.angemeldetUm(c))
            "bestaetigen" -> {
                val a = aktivitaet?.activity ?: return result.error("keine_aktivitaet", "App nicht im Vordergrund", null)
                RosenwegAnmeldung.starten(a, true)
                result.success(null)
            }
            "nfcStand" -> result.success(karteQuelle?.stand() ?: "fehlt")
            "nfcEinstellungen" -> {
                karteQuelle?.einstellungen(aktivitaet?.activity)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun einfach(b: Bundle, k: String): Any? = when (val v = b.get(k)) {
        is String, is Int, is Long, is Boolean, is Double -> v
        null -> null
        else -> v.toString()
    }

    internal fun melden(uri: String) {
        val k = kanal
        if (k == null) {
            ausstehend = uri
            return
        }
        haupt.post {
            k.invokeMethod("ruecksprung", uri, object : MethodChannel.Result {
                override fun success(r: Any?) {}
                override fun error(code: String, msg: String?, details: Any?) {
                    ausstehend = uri
                }
                override fun notImplemented() {
                    // Dart lauscht (noch) nicht: fuer den naechsten Start aufheben.
                    ausstehend = uri
                }
            })
        }
    }

    companion object {
        const val TAG = "RosenwegBasis"
        const val KANAL = "ch.rosenweg4303.basis"
        const val ANLAGE_AUTHORITY = "ch.rosenweg4303.telefon.anlage"
        private const val ANMELDESCHIRM = 4303

        @Volatile internal var aktiv: RosenwegBasisPlugin? = null

        /** Ruecksprung, den noch niemand abgeholt hat (nur im Speicher des Prozesses). */
        @Volatile internal var ausstehend: String? = null

        internal fun ruecksprung(uri: String) {
            val p = aktiv
            if (p == null) ausstehend = uri else p.melden(uri)
        }
    }
}
