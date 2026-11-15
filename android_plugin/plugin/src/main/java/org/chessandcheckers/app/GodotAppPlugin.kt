package org.chessandcheckers.app

import android.content.Intent
import androidx.annotation.NonNull
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Reabre o app: pede ao Android a atividade de entrada numa tarefa limpa e
 * encerra o processo atual.
 *
 * Existe pela atualização OTA. O `.pck` baixado só vale numa abertura nova
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
}
