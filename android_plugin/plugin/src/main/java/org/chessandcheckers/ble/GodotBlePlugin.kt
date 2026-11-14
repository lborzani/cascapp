package org.chessandcheckers.ble

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.annotation.NonNull
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Lado Android de `net/ble_link.gd`: dois celulares conversam por Bluetooth LE,
 * sem internet, sem parear nas configurações e sem diálogo de "tornar visível".
 *
 * - O anfitrião abre um canal L2CAP orientado a conexão (API 29+) e anuncia por
 *   BLE o código da sala (6 bytes) e o PSM do canal (2 bytes), como service data
 *   do [SERVICE]. Cabe nos 31 bytes de um anúncio legado.
 * - O convidado já sabe o código (digitado, QR ou NFC): faz scan filtrado por
 *   ele, lê o PSM e conecta no aparelho que anunciou.
 *
 * O endereço do anfitrião não pode ir no QR: desde o Android 6,
 * `BluetoothAdapter.getAddress()` devolve `02:00:00:00:00:00` para apps comuns.
 * Por isso a descoberta é pelo anúncio.
 *
 * O que trafega são linhas de texto (uma mensagem JSON por linha). O canal é um
 * stream: o `BluetoothSocket` junta e parte os pacotes L2CAP sozinho.
 *
 * Nada aqui liga rádio. Bluetooth desligado é pedido com
 * `ACTION_REQUEST_ENABLE`, que é o sistema perguntando ao jogador. O Wi-Fi não é
 * tocado: foi justamente o Nearby Connections ligando o Wi-Fi por conta própria
 * que tirou o modo sem internet anterior do app.
 *
 * Os sinais nascem em threads de leitura e de accept, e saem pela thread de
 * render da Godot, onde o GDScript roda.
 */
class GodotBlePlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        /** Identifica os anúncios deste app. Precisa ser o mesmo nos dois lados. */
        val SERVICE: ParcelUuid = ParcelUuid(UUID.fromString("c45ca991-7d2e-4f3b-9a4e-2b6f0e1d5a01"))
        private const val CODE_LENGTH = 6
        private const val REQ_PERMISSIONS = 0xB1E
        private const val REQ_ENABLE = 0xB1F

        private const val SIGNAL_OPENED = "link_opened"
        private const val SIGNAL_LINE = "line"
        private const val SIGNAL_CLOSED = "link_closed"
        private const val SIGNAL_ERROR = "ble_error"
        private const val SIGNAL_HOSTING = "hosting"
        private const val SIGNAL_PERMISSIONS = "permissions_result"
        private const val SIGNAL_ENABLE = "enable_result"
    }

    private val manager: BluetoothManager?
        get() = activity?.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
    private val adapter: BluetoothAdapter?
        get() = manager?.adapter

    private val main = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()
    private val links = ConcurrentHashMap<Int, BluetoothSocket>()
    private val nextId = AtomicInteger(1)

    private var server: BluetoothServerSocket? = null
    private var advertising: AdvertiseCallback? = null
    private var scanning: ScanCallback? = null
    private var scanTimeout: Runnable? = null

    @NonNull
    override fun getPluginName() = "GodotBle"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(SIGNAL_OPENED, Int::class.javaObjectType),
        SignalInfo(SIGNAL_LINE, Int::class.javaObjectType, String::class.java),
        SignalInfo(SIGNAL_CLOSED, Int::class.javaObjectType),
        SignalInfo(SIGNAL_ERROR, String::class.java),
        SignalInfo(SIGNAL_HOSTING),
        SignalInfo(SIGNAL_PERMISSIONS, Boolean::class.javaObjectType),
        SignalInfo(SIGNAL_ENABLE, Boolean::class.javaObjectType)
    )

    private fun emit(name: String, vararg args: Any) {
        runOnRenderThread { emitSignal(name, *args) }
    }

    // --- prontidão ------------------------------------------------------------

    /** L2CAP orientado a conexão só existe a partir do Android 10 (API 29). */
    @UsedByGodot
    fun isAvailable(): Boolean {
        val activity = activity ?: return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            adapter != null &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
    }

    @UsedByGodot
    fun isEnabled(): Boolean = adapter?.isEnabled == true

    private fun neededPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            // Android 10 e 11: scan BLE só com localização. O manifesto limita
            // esta permissão a `maxSdkVersion=30`.
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    @UsedByGodot
    fun hasPermissions(): Boolean {
        val activity = activity ?: return false
        return neededPermissions().all {
            activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    /** Um diálogo só: no Android 12+ as três são o grupo "Dispositivos próximos". */
    @UsedByGodot
    fun requestPermissions() {
        val activity = activity ?: return
        if (hasPermissions()) {
            emit(SIGNAL_PERMISSIONS, true)
            return
        }
        activity.requestPermissions(neededPermissions(), REQ_PERMISSIONS)
    }

    override fun onMainRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>?, grantResults: IntArray?
    ) {
        if (requestCode != REQ_PERMISSIONS) return
        emit(SIGNAL_PERMISSIONS, hasPermissions())
    }

    /** Pede ao sistema para ligar o Bluetooth. O jogador decide no diálogo. */
    @UsedByGodot
    fun requestEnable() {
        val activity = activity ?: return
        if (isEnabled()) {
            emit(SIGNAL_ENABLE, true)
            return
        }
        activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQ_ENABLE)
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ_ENABLE) return
        emit(SIGNAL_ENABLE, isEnabled())
    }

    /** No Android 10 e 11 o scan BLE volta vazio, em silêncio, com a localização desligada. */
    @UsedByGodot
    fun locationNeededAndOff(): Boolean {
        val sdk = Build.VERSION.SDK_INT
        if (sdk < Build.VERSION_CODES.Q || sdk >= Build.VERSION_CODES.S) return false
        val location = activity?.getSystemService(Context.LOCATION_SERVICE) as LocationManager?
            ?: return false
        return !location.isLocationEnabled
    }

    /** Erro por código curto; o texto para gente ler mora no GDScript. */
    private fun ready(): Boolean {
        val code = when {
            !isAvailable() -> "unsupported"
            !hasPermissions() -> "no_permission"
            !isEnabled() -> "disabled"
            else -> return true
        }
        emit(SIGNAL_ERROR, code)
        return false
    }

    // --- anfitrião --------------------------------------------------------------

    /**
     * Abre o canal, anuncia o código e aceita quem chegar até [stop]. Cada
     * conexão aceita vira um `link_opened(id)`.
     */
    @SuppressLint("MissingPermission", "NewApi")
    @UsedByGodot
    fun host(code: String) {
        stop()
        if (!ready()) return
        val advertiser = adapter?.bluetoothLeAdvertiser
        if (advertiser == null) {
            emit(SIGNAL_ERROR, "advertise_unsupported")
            return
        }
        val socket = try {
            adapter!!.listenUsingInsecureL2capChannel()
        } catch (error: IOException) {
            emit(SIGNAL_ERROR, "listen_failed")
            return
        }
        server = socket

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceData(SERVICE, serviceData(code, socket.psm))
            .build()
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                emit(SIGNAL_HOSTING)
            }

            override fun onStartFailure(errorCode: Int) {
                emit(SIGNAL_ERROR, "advertise_failed:$errorCode")
            }
        }
        advertising = callback
        advertiser.startAdvertising(settings, data, callback)

        Thread({ acceptLoop(socket) }, "GodotBle-accept").start()
    }

    private fun acceptLoop(socket: BluetoothServerSocket) {
        while (server === socket) {
            val client = try {
                socket.accept()
            } catch (error: IOException) {
                return // `stop()` fechou o servidor.
            }
            open(client)
        }
    }

    // --- convidado --------------------------------------------------------------

    /**
     * Procura o anúncio com [code] por até [timeoutMs] e conecta. Sem anúncio no
     * prazo, `ble_error("not_found")`.
     */
    @SuppressLint("MissingPermission", "NewApi")
    @UsedByGodot
    fun join(code: String, timeoutMs: Int) {
        stop()
        if (!ready()) return
        if (locationNeededAndOff()) {
            emit(SIGNAL_ERROR, "location_off")
            return
        }
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null) {
            emit(SIGNAL_ERROR, "disabled")
            return
        }
        // O filtro já compara o código, então só o anfitrião certo chega aqui.
        val mask = ByteArray(CODE_LENGTH + 2) { if (it < CODE_LENGTH) 0xFF.toByte() else 0 }
        val filter = ScanFilter.Builder()
            .setServiceData(SERVICE, serviceData(code, 0), mask)
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val bytes = result.scanRecord?.getServiceData(SERVICE) ?: return
                if (bytes.size < CODE_LENGTH + 2 || scanning !== this) return
                stopScan()
                val psm = ((bytes[CODE_LENGTH].toInt() and 0xFF) shl 8) or
                    (bytes[CODE_LENGTH + 1].toInt() and 0xFF)
                Thread({ connect(result, psm) }, "GodotBle-connect").start()
            }

            override fun onScanFailed(errorCode: Int) {
                stopScan()
                emit(SIGNAL_ERROR, "scan_failed:$errorCode")
            }
        }
        scanning = callback
        scanner.startScan(listOf(filter), settings, callback)
        val timeout = Runnable {
            if (scanning === callback) {
                stopScan()
                emit(SIGNAL_ERROR, "not_found")
            }
        }
        scanTimeout = timeout
        main.postDelayed(timeout, timeoutMs.toLong())
    }

    @SuppressLint("MissingPermission", "NewApi")
    private fun connect(result: ScanResult, psm: Int) {
        val socket = try {
            result.device.createInsecureL2capChannel(psm).also { it.connect() }
        } catch (error: IOException) {
            emit(SIGNAL_ERROR, "connect_failed")
            return
        }
        open(socket)
    }

    @SuppressLint("MissingPermission", "NewApi")
    private fun stopScan() {
        scanTimeout?.let { main.removeCallbacks(it) }
        scanTimeout = null
        val callback = scanning ?: return
        scanning = null
        try {
            adapter?.bluetoothLeScanner?.stopScan(callback)
        } catch (error: IllegalStateException) {
            // Bluetooth desligado no meio: o scan já parou sozinho.
        }
    }

    // --- links ------------------------------------------------------------------

    private fun open(socket: BluetoothSocket) {
        val id = nextId.getAndIncrement()
        links[id] = socket
        emit(SIGNAL_OPENED, id)
        Thread({ readLoop(id, socket) }, "GodotBle-read-$id").start()
    }

    private fun readLoop(id: Int, socket: BluetoothSocket) {
        try {
            val reader = socket.inputStream.bufferedReader(Charsets.UTF_8)
            while (true) {
                val line = reader.readLine() ?: break
                emit(SIGNAL_LINE, id, line)
            }
        } catch (error: IOException) {
            // Queda de rádio ou `close(id)`: o mesmo fim.
        }
        // Só avisa quem caiu sozinho. Quem fechou por `close`/`stop` já tirou o
        // link do mapa e sabe que fechou.
        if (links.remove(id) != null) {
            closeQuietly(socket)
            emit(SIGNAL_CLOSED, id)
        }
    }

    /** Uma linha, sem o `\n`. A escrita sai de uma thread só, na ordem de chegada. */
    @UsedByGodot
    fun send(id: Int, line: String) {
        val socket = links[id] ?: return
        val bytes = (line + "\n").toByteArray(Charsets.UTF_8)
        writer.execute {
            try {
                socket.outputStream.write(bytes)
                socket.outputStream.flush()
            } catch (error: IOException) {
                // A thread de leitura percebe a mesma queda e emite o `link_closed`.
                closeQuietly(socket)
            }
        }
    }

    /**
     * Pela fila de escrita, atrás do que já foi mandado: o mini relay manda o
     * motivo de uma recusa e fecha no mesmo fôlego, e fechar na hora jogaria o
     * motivo fora antes de ele sair.
     */
    @UsedByGodot
    fun close(id: Int) {
        writer.execute { links.remove(id)?.let { closeQuietly(it) } }
    }

    /** Para anúncio, scan e servidor, e fecha todos os links sem emitir nada. */
    @SuppressLint("MissingPermission", "NewApi")
    @UsedByGodot
    fun stop() {
        stopScan()
        advertising?.let { callback ->
            try {
                adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
            } catch (error: IllegalStateException) {
                // Bluetooth já desligado.
            }
        }
        advertising = null
        server?.let { closeQuietly(it) }
        server = null
        for (id in links.keys.toList()) close(id)
    }

    override fun onMainDestroy() {
        stop()
        writer.shutdown()
    }

    private fun serviceData(code: String, psm: Int): ByteArray {
        val bytes = ByteArray(CODE_LENGTH + 2)
        val ascii = code.uppercase().toByteArray(Charsets.US_ASCII)
        ascii.copyInto(bytes, 0, 0, minOf(ascii.size, CODE_LENGTH))
        bytes[CODE_LENGTH] = (psm shr 8).toByte()
        bytes[CODE_LENGTH + 1] = psm.toByte()
        return bytes
    }

    private fun closeQuietly(closeable: java.io.Closeable) {
        try {
            closeable.close()
        } catch (error: IOException) {
            // Já estava fechado.
        }
    }
}
