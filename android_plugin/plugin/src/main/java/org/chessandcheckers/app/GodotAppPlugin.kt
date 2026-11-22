package org.chessandcheckers.app

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.google.firebase.messaging.FirebaseMessaging
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.TimeUnit

/**
 * O app e as versões novas: reabrir depois da atualização OTA e avisar, com o
 * app fechado, que saiu versão nova (`UpdateWorker`).
 *
 * `restart` existe pela OTA. O `.pck` baixado só vale numa abertura nova
 * (`autoload/patcher.gd` o carrega antes de qualquer outro script), e o Godot só
 * sabe se reabrir sozinho no desktop (`OS.set_restart_on_exit`). No Android o
 * pedido de abertura fica com o sistema; o processo encerrado logo depois é o
 * que garante que a abertura nova começa do zero, e não volta à tarefa antiga.
 */
class GodotAppPlugin(godot: Godot) : GodotPlugin(godot) {

    @NonNull
    override fun getPluginName() = "GodotApp"

    @UsedByGodot
    fun restart() {
        val host = activity ?: return
        val launch = host.packageManager.getLaunchIntentForPackage(host.packageName) ?: return
        val fresh = Intent.makeRestartActivityTask(launch.component)
        host.runOnUiThread {
            host.startActivity(fresh)
            Runtime.getRuntime().exit(0)
        }
    }

    /**
     * Liga a consulta em segundo plano, a cada [CHECK_HOURS] horas com internet,
     * e guarda a versão instalada para ela comparar. O menu chama a cada
     * abertura: a agenda existente fica (`KEEP`), e o aviso de uma versão já
     * instalada sai da bandeja.
     */
    @UsedByGodot
    fun watchUpdates(url: String, installed: String) {
        val host = activity ?: return
        val prefs = host.getSharedPreferences(UpdateWorker.PREFS, Context.MODE_PRIVATE)
        prefs.edit().putString(UpdateWorker.KEY_URL, url).putString(UpdateWorker.KEY_INSTALLED, installed).apply()
        if (UpdateWorker.compare(prefs.getString(UpdateWorker.KEY_NOTIFIED, "") ?: "", installed) <= 0) {
            host.getSystemService(NotificationManager::class.java).cancel(UpdateWorker.NOTIFICATION_ID)
        }
        val work = PeriodicWorkRequestBuilder<UpdateWorker>(CHECK_HOURS, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(host)
            .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, work)
        // O aviso na hora: a esteira de release manda ao tópico (`PushService`).
        // A consulta periódica fica como rede, para celular sem Play Services.
        try {
            FirebaseMessaging.getInstance().subscribeToTopic(UPDATES_TOPIC)
        } catch (_: Exception) {
        }
    }

    /**
     * Pede a permissão de notificação (Android 13+) uma vez só. Negada, o app
     * segue avisando pela tela de versão nova, ao abrir.
     */
    @UsedByGodot
    fun askToNotify() {
        val host = activity ?: return
        if (Build.VERSION.SDK_INT < 33 ||
            host.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) return
        val prefs = host.getSharedPreferences(UpdateWorker.PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_ASKED, false)) return
        prefs.edit().putBoolean(KEY_ASKED, true).apply()
        host.runOnUiThread {
            host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFY)
        }
    }

    /**
     * O app abriu (ou voltou) pelo toque na notificação de versão nova. Responde
     * `true` uma vez: a marca sai da intent ao ser lida.
     */
    @UsedByGodot
    fun takeUpdateLaunch(): Boolean {
        val intent = activity?.intent ?: return false
        if (!intent.getBooleanExtra(UpdateWorker.EXTRA_UPDATE, false)) return false
        intent.removeExtra(UpdateWorker.EXTRA_UPDATE)
        return true
    }

    /**
     * O token do Firebase deste aparelho, para a conta mandar a notificação de
     * mensagem de amigo (`PushService`). Vazio enquanto o Firebase não deu um:
     * o pedido sai agora, a resposta fica guardada, e a próxima pergunta já a
     * encontra.
     */
    @UsedByGodot
    fun pushToken(): String {
        val host = activity ?: return ""
        val prefs = host.getSharedPreferences(PushService.PREFS, Context.MODE_PRIVATE)
        val saved = prefs.getString(PushService.KEY_TOKEN, "") ?: ""
        if (saved.isEmpty()) {
            try {
                FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
                    prefs.edit().putString(PushService.KEY_TOKEN, token).apply()
                }
            } catch (_: Exception) {
                // Sem Google Play Services (ou Firebase fora): fica sem notificação.
            }
        }
        return saved
    }

    /**
     * O app abriu (ou voltou) pelo toque na notificação de mensagem: o id do
     * amigo, uma vez só. Vazio no resto das aberturas.
     */
    @UsedByGodot
    fun takeChatLaunch(): String {
        val intent = activity?.intent ?: return ""
        val friend = intent.getStringExtra(PushService.EXTRA_CHAT) ?: return ""
        intent.removeExtra(PushService.EXTRA_CHAT)
        return friend
    }

    companion object {
        private const val CHECK_HOURS = 3L
        private const val UPDATES_TOPIC = "updates"
        private const val WORK_NAME = "update-check"
        private const val KEY_ASKED = "asked_to_notify"
        private const val REQ_NOTIFY = 0xC46
    }
}
