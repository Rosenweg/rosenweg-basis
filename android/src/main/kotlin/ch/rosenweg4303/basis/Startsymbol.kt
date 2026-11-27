// SPDX-License-Identifier: GPL-3.0-or-later
package ch.rosenweg4303.basis

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * Startsymbol in der Gruppenfarbe (rosenweg-basis docs/gruppenfarbe.md).
 *
 * Die App hat je Farbe eine activity-alias auf MainActivity mit MAIN/LAUNCHER und dem Symbol
 * der Farbe: `.SymbolBewohner`, `.SymbolVerwaltung`, `.SymbolTechnik` (werkzeug/logo/
 * farben-einbauen.py). Genau eine ist eingeschaltet. Umschalten: erst die neue ein, dann die
 * anderen aus (so gibt es immer ein Startsymbol), DONT_KILL_APP, nur wenn sich etwas aendert.
 *
 * Achtung: Manche Launcher laden danach kurz neu und entfernen eine Verknuepfung der App vom
 * Startbildschirm (sie zeigte auf die alte Alias). Die App bleibt in der App-Liste.
 */
object Startsymbol {
    private const val TAG = "RosenwegStartsymbol"

    private fun aliasName(gruppe: String) = "Symbol" + gruppe.replaceFirstChar { it.uppercase() }

    /** true = umgeschaltet; false = schon so oder die App hat keine Farb-Aliasse. */
    fun setzen(c: Context, gruppe: String): Boolean {
        val pm = c.packageManager
        val alle = try {
            val flags = PackageManager.GET_ACTIVITIES or PackageManager.MATCH_DISABLED_COMPONENTS
            val info = if (Build.VERSION.SDK_INT >= 33) {
                pm.getPackageInfo(c.packageName, PackageManager.PackageInfoFlags.of(flags.toLong()))
            } else {
                @Suppress("DEPRECATION") pm.getPackageInfo(c.packageName, flags)
            }
            info.activities.orEmpty().map { it.name }.filter { it.substringAfterLast('.').startsWith("Symbol") }
        } catch (e: Exception) {
            Log.w(TAG, "Aktivitaeten nicht lesbar", e)
            return false
        }
        val ziel = alle.firstOrNull { it.substringAfterLast('.') == aliasName(gruppe) } ?: return false
        fun an(name: String): Boolean {
            val s = pm.getComponentEnabledSetting(ComponentName(c.packageName, name))
            if (s == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return true
            if (s == PackageManager.COMPONENT_ENABLED_STATE_DISABLED) return false
            // DEFAULT: wie im Manifest
            return try {
                pm.getActivityInfo(ComponentName(c.packageName, name), PackageManager.MATCH_DISABLED_COMPONENTS).enabled
            } catch (e: Exception) { false }
        }
        val aendern = !an(ziel) || alle.any { it != ziel && an(it) }
        if (!aendern) return false
        pm.setComponentEnabledSetting(ComponentName(c.packageName, ziel),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        for (n in alle) if (n != ziel) {
            pm.setComponentEnabledSetting(ComponentName(c.packageName, n),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
        }
        Log.i(TAG, "Startsymbol -> $ziel")
        return true
    }
}
