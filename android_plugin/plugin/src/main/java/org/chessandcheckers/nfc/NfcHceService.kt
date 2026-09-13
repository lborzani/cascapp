package org.chessandcheckers.nfc

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/**
 * Host Card Emulation service: while a match is being advertised, this phone
 * behaves like a contactless card that hands out the pairing payload.
 *
 * Registered in the manifest with `apduservice.xml`; Android routes any SELECT
 * for our AID here, even with the screen on and the app in the foreground.
 */
class NfcHceService : HostApduService() {

    companion object {
        /** Set by [GodotNfcPlugin.startBroadcast]; null means "not hosting". */
        @Volatile
        var payload: String? = null

        private val STATUS_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val STATUS_UNKNOWN = byteArrayOf(0x6F.toByte(), 0x00)
        private val STATUS_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())

        /** Strips the trailing status word and returns the payload, or null. */
        fun decodeResponse(response: ByteArray?): String? {
            if (response == null || response.size <= STATUS_OK.size) return null
            val last = response.size
            val statusOk = response[last - 2] == STATUS_OK[0] && response[last - 1] == STATUS_OK[1]
            if (!statusOk) return null
            return String(response.copyOfRange(0, last - 2), Charsets.UTF_8)
        }

        /**
         * Por que a leitura não deu payload, em português, para a tela mostrar.
         *
         * Existe porque "não aconteceu nada" depois de um toque que vibrou é o
         * pior relato possível: o rádio funcionou, e a causa está numa das
         * quatro respostas abaixo. Sem distingui-las não há o que investigar.
         */
        fun describeFailure(response: ByteArray?): String {
            if (response == null) return "O outro aparelho não respondeu ao toque."
            if (response.size < 2) return "Resposta NFC truncada (${response.size} bytes)."
            val sw1 = response[response.size - 2]
            val sw2 = response[response.size - 1]
            return when {
                sw1 == STATUS_NOT_FOUND[0] && sw2 == STATUS_NOT_FOUND[1] ->
                    "O outro aparelho tem o app aberto, mas não está anunciando uma partida. Abra \"Criar partida\" nele."
                sw1 == STATUS_UNKNOWN[0] && sw2 == STATUS_UNKNOWN[1] ->
                    "O outro aparelho recusou o comando NFC."
                else ->
                    "Resposta NFC inesperada (status %02X%02X).".format(sw1, sw2)
            }
        }
    }

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
        if (commandApdu == null || !isSelectAid(commandApdu)) return STATUS_UNKNOWN
        val current = payload ?: return STATUS_NOT_FOUND
        return current.toByteArray(Charsets.UTF_8) + STATUS_OK
    }

    override fun onDeactivated(reason: Int) {
        // Nothing to clean up: the payload is cleared by the Godot side.
    }

    private fun isSelectAid(apdu: ByteArray): Boolean {
        // 00 A4 04 00 <len> <aid...>
        if (apdu.size < 5 + GodotNfcPlugin.AID.size) return false
        if (apdu[0] != 0x00.toByte() || apdu[1] != 0xA4.toByte()) return false
        if (apdu[2] != 0x04.toByte() || apdu[3] != 0x00.toByte()) return false
        val aid = apdu.copyOfRange(5, 5 + GodotNfcPlugin.AID.size)
        return aid.contentEquals(GodotNfcPlugin.AID)
    }
}
