package org.chessandcheckers.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.chessandcheckers.plugins.R
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Pergunta ao GitHub, com o app fechado, se saiu versão nova, e avisa com uma
 * notificação. Tocar nela (ou em "Atualizar") abre o app, que já começa a baixar
 * (`GodotAppPlugin.takeUpdateLaunch`, `scenes/main_menu.gd`).
 *
 * A regra é a de `net/update_check.gd`: vale a release mais nova que não é
 * rascunho nem pré-release e já tem o APK anexado. Avisa uma vez por versão.
 * Falha de rede ou de JSON é silêncio; a próxima rodada tenta de novo.
 */
class UpdateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val url = prefs.getString(KEY_URL, null) ?: return Result.success()
        val installed = prefs.getString(KEY_INSTALLED, null) ?: return Result.success()
        val newest = try {
            newest(url)
        } catch (e: Exception) {
            null
        } ?: return Result.success()
        val notified = prefs.getString(KEY_NOTIFIED, "") ?: ""
        if (compare(newest, installed) > 0 && compare(newest, notified) > 0 && notify(applicationContext, newest)) {
            prefs.edit().putString(KEY_NOTIFIED, newest).apply()
        }
        return Result.success()
    }

    private fun newest(url: String): String? {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = TIMEOUT_MS
        connection.readTimeout = TIMEOUT_MS
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            val releases = JSONArray(connection.inputStream.bufferedReader().use { it.readText() })
            var best: String? = null
            for (index in 0 until releases.length()) {
                val release = releases.optJSONObject(index) ?: continue
                if (release.optBoolean("draft") || release.optBoolean("prerelease") || !hasApk(release)) continue
                val version = release.optString("tag_name").removePrefix("v")
                if (version.isNotEmpty() && (best == null || compare(version, best) > 0)) best = version
            }
            return best
        } finally {
            connection.disconnect()
        }
    }

    private fun hasApk(release: JSONObject): Boolean {
        val assets = release.optJSONArray("assets") ?: return false
        return (0 until assets.length()).any {
            assets.optJSONObject(it)?.optString("name")?.endsWith(".apk") == true
        }
    }

    companion object {
        const val PREFS = "cascapp_update"
        const val KEY_URL = "url"
        const val KEY_INSTALLED = "installed"
        const val KEY_NOTIFIED = "notified"
        /** Marca da abertura pelo toque na notificação. */
        const val EXTRA_UPDATE = "org.chessandcheckers.app.UPDATE"
        const val NOTIFICATION_ID = 0xC45
        private const val CHANNEL = "updates"
        private const val TIMEOUT_MS = 10_000

        /** O mesmo que `AppVersion.compare`: "1.51" contra "1.9" compara 51 com 9. */
        fun compare(a: String, b: String): Int {
            val left = a.trim().removePrefix("v").split(".")
            val right = b.trim().removePrefix("v").split(".")
            for (index in 0 until maxOf(left.size, right.size)) {
                val x = left.getOrNull(index)?.toIntOrNull() ?: 0
                val y = right.getOrNull(index)?.toIntOrNull() ?: 0
                if (x != y) return x - y
            }
            return 0
        }

        /** Sem a permissão (Android 13+), não avisa, e a versão fica para a próxima rodada. */
        private fun notify(context: Context, version: String): Boolean {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return false
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return false
            launch.putExtra(EXTRA_UPDATE, true)
            val open = PendingIntent.getActivity(
                context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val manager = context.getSystemService(NotificationManager::class.java)
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Versão nova", NotificationManager.IMPORTANCE_DEFAULT)
                )
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val icon = Icon.createWithResource(context, R.drawable.cascapp_update)
            builder.setSmallIcon(icon)
                .setContentTitle("Versão $version disponível")
                .setContentText("Toque para atualizar: o app baixa e abre na versão nova.")
                .setContentIntent(open)
                .setAutoCancel(true)
                .addAction(Notification.Action.Builder(icon, "Atualizar", open).build())
            manager.notify(NOTIFICATION_ID, builder.build())
            return true
        }
    }
}
