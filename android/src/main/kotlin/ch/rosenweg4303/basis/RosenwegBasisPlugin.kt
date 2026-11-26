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
import io.flutter.embedding.engine.plugins.FlutterPlugin
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
 *  - geraetRufen             ContentResolver.call auf content://ch.rosenweg4303.telefon.anlage
 *                            {methode, arg, extras} -> Bundle als Map (nur Strings, Zahlen, bool)
 *
 * Richtung Dart: "ruecksprung" (Uri als Text), sobald RuecksprungActivity eine
 * Antwort von Authentik bekommt.
 */
class RosenwegBasisPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var kanal: MethodChannel? = null
    private var person: EventChannel? = null
    private var personQuelle: GeraetPerson? = null
    private var kontext: Context? = null
    private val netz = Executors.newSingleThreadExecutor()
    private val haupt = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kontext = binding.applicationContext
        kanal = MethodChannel(binding.binaryMessenger, KANAL).also { it.setMethodCallHandler(this) }
        // Geteilte Telefone: An-/Abmeldung am Telefon (eigener Kanal, GeraetPerson.kt)
        val quelle = GeraetPerson(binding.applicationContext)
        personQuelle = quelle
        person = EventChannel(binding.binaryMessenger, GeraetPerson.KANAL).also { it.setStreamHandler(quelle) }
        aktiv = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kanal?.setMethodCallHandler(null)
        kanal = null
        person?.setStreamHandler(null)
        person = null
        personQuelle?.onCancel(null)   // Empfaenger abmelden
        personQuelle = null
        if (aktiv === this) aktiv = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val c = kontext ?: return result.error("kein_kontext", "Plugin nicht verbunden", null)
        when (call.method) {
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

        @Volatile internal var aktiv: RosenwegBasisPlugin? = null

        /** Ruecksprung, den noch niemand abgeholt hat (nur im Speicher des Prozesses). */
        @Volatile internal var ausstehend: String? = null

        internal fun ruecksprung(uri: String) {
            val p = aktiv
            if (p == null) ausstehend = uri else p.melden(uri)
        }
    }
}

/**
 * Ruecksprung der Anmeldung (<applicationId>:/anmeldung), keine Oberflaeche.
 * Reicht die Antwort an Dart weiter und holt die App wieder nach vorn — wie
 * RosenwegAnmeldungActivity in commons-rosenweg, nur dass der Tausch gegen das
 * Token in Dart passiert (dort liegt der PKCE-Verifier).
 */
class RuecksprungActivity : Activity() {
    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        intent?.data?.toString()?.let { RosenwegBasisPlugin.ruecksprung(it) }
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            startActivity(it.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        finish()
    }
}
