package org.chessandcheckers.app

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.chessandcheckers.plugins.R

/**
 * Mensagem de amigo com o app fechado, pelo Firebase Cloud Messaging.
 *
 * O servidor (`pocketbase/worker/push.mjs`) manda mensagem `data`, e não
 * `notification`, justamente para a decisão ficar aqui: com o app na frente não
 * se mostra nada (a bolinha da gaveta já avisa); fechado ou no fundo, a
 * notificação sai com o nome do amigo e o texto. Tocar abre o app com o id do
 * amigo na intent ([EXTRA_CHAT]), e o menu abre a conversa
 * (`GodotAppPlugin.takeChatLaunch`).
 *
 * O token novo fica guardado ([KEY_TOKEN]); o app o manda para a conta quando
 * abre (`GodotAppPlugin.pushToken`).
 */
class PushService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TOKEN, token).apply()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (inForeground()) return
        val data = message.data
        // Versão nova, mandada pela esteira de release ao tópico `updates`: o
        // mesmo aviso da consulta em segundo plano, na hora em que ela sai.
        if (data["type"] == "update") {
            data["version"]?.let { UpdateWorker.announce(this, it) }
            return
        }
        val friend = data["friend"] ?: return
        notify(this, friend, data["title"] ?: "Um amigo", data["body"] ?: "")
    }

    private fun inForeground(): Boolean {
        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        return state.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    companion object {
        const val PREFS = "cascapp_push"
        const val KEY_TOKEN = "token"
        const val EXTRA_CHAT = "org.chessandcheckers.app.CHAT"
        private const val CHANNEL = "friend-messages"

        /** Sem a permissão (Android 13+), não avisa: a mensagem espera o app abrir. */
        fun notify(context: Context, friend: String, title: String, body: String) {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
            launch.putExtra(EXTRA_CHAT, friend)
            // Um pedido por amigo: tocar na de um não abre a conversa de outro.
            val open = PendingIntent.getActivity(
                context, friend.hashCode(), launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val manager = context.getSystemService(NotificationManager::class.java)
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Mensagens de amigos", NotificationManager.IMPORTANCE_HIGH)
                )
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            builder.setSmallIcon(Icon.createWithResource(context, R.drawable.cascapp_message))
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(open)
                .setAutoCancel(true)
            // Uma notificação por amigo: a nova substitui a anterior dele.
            manager.notify(friend.hashCode(), builder.build())
        }
    }
}
