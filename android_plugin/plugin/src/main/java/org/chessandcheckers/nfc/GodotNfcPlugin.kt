package org.chessandcheckers.nfc

import android.app.Activity
import android.content.ComponentName
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.nfc.tech.IsoDep
import androidx.annotation.NonNull
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Android side of `net/nfc_bridge.gd`.
 *
 * Android Beam (peer-to-peer NDEF push) was removed from the platform, so the
 * two roles are asymmetric:
 *
 *  - the host runs Host Card Emulation ([NfcHceService]) and answers a SELECT
 *    APDU with the pairing payload;
 *  - the guest runs NFC reader mode, sends that SELECT and reads the answer.
 *
 * Both phones only need NFC enabled — no pairing, no Bluetooth, no internet.
 *
 * Build with the Godot Android plugin template (Godot 4.x), drop the resulting
 * .aar plus the .gdap next to `android/plugins/`, and export with "Use Gradle
 * Build" enabled. See README.md in this folder.
 */
class GodotNfcPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        /** Proprietary AID: 0xF0 + "CHESS". Must match `apduservice.xml`. */
        val AID = byteArrayOf(0xF0.toByte(), 0x43, 0x48, 0x45, 0x53, 0x53)
        /** O mesmo AID em hexadecimal, que é a forma que `CardEmulation` aceita. */
        const val AID_HEX = "F04348455353"
        private val SELECT_APDU = byteArrayOf(
            0x00, 0xA4.toByte(), 0x04, 0x00, AID.size.toByte(),
            *AID,
            0x00
        )
        private const val SIGNAL_PAYLOAD = "payload_received"
        private const val SIGNAL_ERROR = "nfc_error"
    }

    private val adapter: NfcAdapter?
        get() = NfcAdapter.getDefaultAdapter(activity)

    @NonNull
    override fun getPluginName() = "GodotNfc"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(SIGNAL_PAYLOAD, String::class.java),
        SignalInfo(SIGNAL_ERROR, String::class.java)
    )

    @UsedByGodot
    fun isAvailable(): Boolean = adapter != null

    @UsedByGodot
    fun isEnabled(): Boolean = adapter?.isEnabled == true

    /** Host role: keep answering with [payload] until [stop] is called. */
    @UsedByGodot
    fun startBroadcast(payload: String) {
        if (!requireNfc()) return
        NfcHceService.payload = payload

        // Declarar o AID no manifesto não garante que o sistema roteie o SELECT
        // para cá: outro app pode declarar o mesmo AID, e alguns fabricantes
        // exigem que o serviço seja habilitado nas configurações de NFC. Sem
        // esta checagem, o convidado encosta, o aparelho vibra, e o comando vai
        // parar em outro lugar — falha silenciosa nos dois lados.
        val currentActivity: Activity = activity ?: return
        val emulation = runCatching { CardEmulation.getInstance(adapter) }.getOrNull() ?: return
        val service = ComponentName(currentActivity, NfcHceService::class.java)
        val routed = runCatching {
            emulation.isDefaultServiceForAid(service, AID_HEX)
        }.getOrDefault(true)
        if (!routed) {
            emitSignal(
                SIGNAL_ERROR,
                "O sistema não está encaminhando o toque NFC para este jogo. " +
                    "Verifique em Configurações > Conexões > NFC qual app responde por padrão."
            )
        }
    }

    /** Guest role: read the first tag that speaks our AID. */
    @UsedByGodot
    fun startReader() {
        val currentActivity: Activity = activity ?: return
        if (!requireNfc()) return
        adapter?.enableReaderMode(
            currentActivity,
            { tag ->
                val isoDep = IsoDep.get(tag)
                if (isoDep == null) {
                    emitSignal(SIGNAL_ERROR, "Tag NFC incompatível.")
                    return@enableReaderMode
                }
                try {
                    isoDep.connect()
                    val response = isoDep.transceive(SELECT_APDU)
                    val payload = NfcHceService.decodeResponse(response)
                    if (payload == null) {
                        emitSignal(SIGNAL_ERROR, NfcHceService.describeFailure(response))
                    } else {
                        emitSignal(SIGNAL_PAYLOAD, payload)
                    }
                } catch (error: Exception) {
                    emitSignal(SIGNAL_ERROR, error.message ?: "Falha na leitura NFC.")
                } finally {
                    runCatching { isoDep.close() }
                }
            },
            // NFC-B junto com NFC-A: a emulação de cartão do Android é NFC-A na
            // maioria dos aparelhos, mas não em todos, e pedir só A faz o leitor
            // ignorar em silêncio o anfitrião que se apresenta como B.
            NfcAdapter.FLAG_READER_NFC_A
                or NfcAdapter.FLAG_READER_NFC_B
                or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
            null
        )
    }

    @UsedByGodot
    fun stop() {
        NfcHceService.payload = null
        activity?.let { adapter?.disableReaderMode(it) }
    }

    private fun requireNfc(): Boolean {
        val nfc = adapter
        if (nfc == null) {
            emitSignal(SIGNAL_ERROR, "Este aparelho não tem NFC.")
            return false
        }
        if (!nfc.isEnabled) {
            emitSignal(SIGNAL_ERROR, "NFC desligado nas configurações do sistema.")
            return false
        }
        return true
    }
}
