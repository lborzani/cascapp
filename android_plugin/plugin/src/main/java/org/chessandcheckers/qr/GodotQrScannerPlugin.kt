package org.chessandcheckers.qr

import android.content.Context
import android.graphics.Color
import android.util.Size
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.annotation.NonNull
import androidx.annotation.OptIn
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Leitor de QR **dentro da própria activity do jogo**.
 *
 * A versão anterior usava o Google Code Scanner, que abre uma activity do Play
 * Services. Isso mandava o jogo para segundo plano, e um app deste tamanho com a
 * câmera e o ML Kit carregando em cima é candidato natural a ser recolhido por
 * memória — o sintoma era o app "reiniciar" ao voltar da leitura, perdendo o
 * pareamento. Não dá para impedir o sistema de recolher um processo em segundo
 * plano; dá para nunca ir para segundo plano.
 *
 * Aqui a prévia é uma `View` devolvida por [getPluginView], que a Godot encaixa
 * por cima da superfície do jogo. Nenhuma troca de activity, nenhum ciclo de
 * vida perdido. O custo é a permissão de CAMERA, que o Code Scanner dispensava.
 *
 * O plugin é seu próprio [LifecycleOwner]: o CameraX exige um, e depender do
 * tipo concreto da activity da Godot amarraria o plugin a um detalhe que muda
 * entre versões da engine.
 */
@OptIn(ExperimentalGetImage::class)
class GodotQrScannerPlugin(godot: Godot) : GodotPlugin(godot), LifecycleOwner {

    companion object {
        private const val SIGNAL_RESULT = "scan_result"
        private const val SIGNAL_CANCELLED = "scan_cancelled"
        private const val SIGNAL_ERROR = "scan_error"
        private const val PREFS = "chess_and_checkers_pairing"
        private const val KEY_PENDING = "pending_scan"
    }

    private val lifecycleRegistry = LifecycleRegistry(this)
    private var container: FrameLayout? = null
    private var previewView: PreviewView? = null
    private var analysisExecutor: ExecutorService? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var scanner: BarcodeScanner? = null
    private var scanning = false

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry

    @NonNull
    override fun getPluginName() = "GodotQrScanner"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(SIGNAL_RESULT, String::class.java),
        SignalInfo(SIGNAL_CANCELLED),
        SignalInfo(SIGNAL_ERROR, String::class.java)
    )

    /**
     * A Godot chama isto na criação da activity e encaixa a view devolvida por
     * cima do jogo. Ela nasce invisível e só aparece durante a leitura.
     */
    override fun onMainCreate(activity: android.app.Activity?): View? {
        if (activity == null) return null
        if (container != null) return container

        val root = FrameLayout(activity)
        root.setBackgroundColor(Color.BLACK)
        root.visibility = View.GONE

        val preview = PreviewView(activity)
        preview.scaleType = PreviewView.ScaleType.FILL_CENTER
        root.addView(
            preview,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        val hint = TextView(activity)
        hint.text = "Aponte para o QR da outra tela"
        hint.setTextColor(Color.WHITE)
        hint.textSize = 16f
        hint.gravity = Gravity.CENTER
        hint.setPadding(0, 48, 0, 0)
        root.addView(
            hint,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        )

        val cancel = Button(activity)
        cancel.text = "Cancelar"
        cancel.setOnClickListener {
            stopScan()
            emitSignal(SIGNAL_CANCELLED)
        }
        val cancelParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        )
        cancelParams.bottomMargin = 96
        root.addView(cancel, cancelParams)

        container = root
        previewView = preview
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        return root
    }

    @UsedByGodot
    fun startScan() {
        val activity = activity ?: return
        if (scanning) return
        activity.runOnUiThread { bindCamera() }
    }

    @UsedByGodot
    fun stopScan() {
        val activity = activity ?: return
        activity.runOnUiThread { unbindCamera() }
    }

    private fun bindCamera() {
        val activity = activity ?: return
        val root = container ?: return
        val preview = previewView ?: return

        scanning = true
        root.visibility = View.VISIBLE
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
        analysisExecutor = Executors.newSingleThreadExecutor()
        scanner = BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        )

        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener({
            try {
                val provider = future.get()
                cameraProvider = provider
                provider.unbindAll()

                val previewUseCase = Preview.Builder().build()
                previewUseCase.setSurfaceProvider(preview.surfaceProvider)

                val analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(
                                    Size(1280, 720),
                                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                                )
                            )
                            .build()
                    )
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(analysisExecutor!!) { proxy -> analyse(proxy) }

                provider.bindToLifecycle(
                    this, CameraSelector.DEFAULT_BACK_CAMERA, previewUseCase, analysis
                )
            } catch (error: Exception) {
                unbindCamera()
                emitSignal(SIGNAL_ERROR, error.message ?: "Não foi possível abrir a câmera.")
            }
        }, androidx.core.content.ContextCompat.getMainExecutor(activity))
    }

    private fun analyse(proxy: androidx.camera.core.ImageProxy) {
        val image = proxy.image
        val client = scanner
        if (image == null || client == null || !scanning) {
            proxy.close()
            return
        }
        val input = InputImage.fromMediaImage(image, proxy.imageInfo.rotationDegrees)
        client.process(input)
            .addOnSuccessListener { barcodes ->
                val value = barcodes.firstOrNull { !it.rawValue.isNullOrEmpty() }?.rawValue
                if (value != null && scanning) {
                    // Gravado antes de emitir: se o processo morrer entre uma
                    // coisa e outra, o payload sobrevive para a próxima abertura.
                    activity?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        ?.edit()?.putString(KEY_PENDING, value)?.apply()
                    stopScan()
                    emitSignal(SIGNAL_RESULT, value)
                }
            }
            .addOnCompleteListener { proxy.close() }
    }

    private fun unbindCamera() {
        scanning = false
        cameraProvider?.unbindAll()
        cameraProvider = null
        scanner?.close()
        scanner = null
        analysisExecutor?.shutdown()
        analysisExecutor = null
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        container?.visibility = View.GONE
    }

    @UsedByGodot
    fun takePendingScan(): String {
        val prefs = activity?.getSharedPreferences(PREFS, Context.MODE_PRIVATE) ?: return ""
        val value = prefs.getString(KEY_PENDING, "") ?: ""
        prefs.edit().remove(KEY_PENDING).apply()
        return value
    }

    @UsedByGodot
    fun clearPendingScan() {
        activity?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()
            ?.remove(KEY_PENDING)?.apply()
    }
}
