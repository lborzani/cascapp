extends Node

## Autoload `Pairing`: fazer os dois aparelhos concordarem sobre **qual sala**,
## antes de qualquer lógica de jogo.
##
## O modelo é sala, não ligação direta: o anfitrião abre uma sala no relay e o
## código de 6 caracteres é o nome dela. Entrar é dizer o nome — de onde for,
## em qualquer rede.
##
## Por isso o que mora aqui é só a **entrega do código**. Ele viaja por três
## canais que produzem exatamente o mesmo resultado:
##
## - digitado à mão;
## - lido de um QR na tela do anfitrião;
## - encostando os aparelhos (NFC).
##
## Os três terminam em `payload_received` com o mesmo dicionário, e daí em
## diante o caminho é um só. Não há descoberta na rede local, endereço IP nem
## hotspot: isso existia quando a partida era uma ligação direta entre os dois
## aparelhos, e um endereço IP não é algo que o jogador queira ver.
##
## Nada aqui liga rádio nenhum por conta própria. O NFC só escuta quando o
## jogador toca em "Aproximar" e a câmera só abre em "Ler QR" — entrar numa tela
## nunca deve mexer no aparelho.

signal payload_received(info: Dictionary)
## Um QR foi decodificado ou uma tag lida, e não era nossa. Silêncio aqui é
## indistinguível de "o leitor está quebrado", então a tela é avisada.
signal payload_rejected(text: String)

const PAYLOAD_PREFIX := "XDM3"
## Sem 0/O/1/I: estes códigos são lidos de uma tela e digitados à mão.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6

var nfc: NfcBridge
var qr_scanner: QrScannerBridge
var relay: RelayBridge


func _ready() -> void:
	nfc = NfcBridge.new()
	nfc.name = "NfcBridge"
	add_child(nfc)
	qr_scanner = QrScannerBridge.new()
	qr_scanner.name = "QrScannerBridge"
	add_child(qr_scanner)
	relay = RelayBridge.new()
	relay.name = "RelayBridge"
	add_child(relay)

	nfc.payload_received.connect(_on_external_payload)
	qr_scanner.scanned.connect(_on_external_payload)


# --- payload -----------------------------------------------------------------


## Jogo e código, nada mais.
##
## A versão anterior carregava lista de endereços IP, porta, SSID e senha de
## hotspot — sete campos, porque a partida era uma ligação direta e o convidado
## precisava saber *onde* estava o anfitrião. Com sala, ele só precisa saber
## *qual*. O QR encolheu de versão 5 (37x37) para versão 1 (21x21), e um QR
## menos denso é um QR que a câmera trava de longe e com a tela suja.
static func build_payload(game_id: StringName, code: String) -> String:
	return "%s|%s|%s" % [PAYLOAD_PREFIX, game_id, code]


## Devolve {} para qualquer coisa que não seja um payload nosso, então uma tag
## NFC perdida ou um QR de outro app é simplesmente ignorado.
##
## Um payload do formato antigo tem sete campos e cai aqui como desconhecido,
## que é o comportamento certo: melhor recusar do que ler os campos trocados.
static func parse_payload(text: String) -> Dictionary:
	var parts := text.strip_edges().split("|")
	if parts.size() != 3 or parts[0] != PAYLOAD_PREFIX:
		return {}
	var code := parts[2].strip_edges().to_upper()
	if code.length() != CODE_LENGTH:
		return {}
	return {"game": StringName(parts[1]), "code": code}


static func generate_code() -> String:
	var code := ""
	for _i in CODE_LENGTH:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


func _on_external_payload(text: String) -> void:
	var info := parse_payload(text)
	if info.is_empty():
		push_warning("Payload de pareamento não reconhecido: %s" % text)
		payload_rejected.emit(text)
		return
	payload_received.emit(info)
