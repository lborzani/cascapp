package org.chessandcheckers.stockfish

import androidx.annotation.NonNull
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Só diz onde está o Stockfish. A conversa UCI é do GDScript
 * (`core/stockfish.gd`), por `OS.execute_with_pipe`.
 *
 * O binário viaja como `jniLibs/arm64-v8a/libstockfish.so` porque o diretório de
 * bibliotecas nativas é o único lugar de onde o Android deixa um app executar
 * arquivo próprio. Ele só existe extraído ali com `compress_native_libraries`
 * ligado no preset de exportação (legacy packaging).
 */
class GodotStockfishPlugin(godot: Godot) : GodotPlugin(godot) {

    @NonNull
    override fun getPluginName() = "GodotStockfish"

    @UsedByGodot
    fun binaryPath(): String =
        "${activity!!.applicationInfo.nativeLibraryDir}/libstockfish.so"
}
