extends Control

## O lobby do Bomberman: criar uma sala no servidor autoritativo, ou entrar numa
## pelo código.
##
## É próprio do Bomberman, e não a tela de emparelhamento compartilhada
## ([scenes/pairing.gd]): os outros cinco jogos abrem sala no relay, e o Bomberman
## abre no servidor de tempo real ([BomberNet]). O QR/NFC é o **mesmo** — o payload
## já era só `XDM3|jogo|código` ([Pairing]), e o endereço do servidor é fixo. O que
## muda é pra onde o código conecta.
##
## ## Anfitrião e convidado numa cena só
##
## Quem chega aqui com [member BomberNet.pending_code] vazio **cria** a sala e vira
## anfitrião: vê o código, o QR e o botão de começar. Quem chega com um código
## **entra** e espera o anfitrião começar. A partida começa quando o anfitrião
## manda — as cadeiras vazias já são máquina, então não é preciso encher a mesa,
## mas a mesa de grade precisa esperar os amigos lerem o QR antes de começar.

const MENU_SCENE := "res://scenes/game_menu.tscn"
const MATCH_SCENE := "res://scenes/bomber_match.tscn"

var _is_host := false
var _left := false


func _ready() -> void:
	theme = AppTheme.shared()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	%AppBar.leading = IconButton.Kind.BACK
	%AppBar.leading_pressed.connect(_back_to_menu)
	%StartButton.pressed.connect(_on_start_pressed)
	BomberNet.joined.connect(_on_joined)
	BomberNet.denied.connect(_on_denied)
	BomberNet.seats_changed.connect(_on_seats)
	BomberNet.started.connect(_on_started)
	BomberNet.dropped.connect(_on_dropped)

	var wanted := BomberNet.pending_code
	_is_host = wanted == ""
	%HostPanel.visible = _is_host
	%StartButton.visible = false
	# Na barra o que a tela é; na linha de baixo, de que jogo é esta sala.
	%AppBar.title = "Criar partida" if _is_host else "Entrar"
	%Title.text = "Bomberman"
	%StatusLabel.text = "Conectando ao servidor…"

	var problem := BomberNet.connect_to()
	if problem != OK:
		_fail("Não consegui falar com o servidor de partidas. Confira a internet deste aparelho.")
		return
	if not await _wait_connected():
		_fail("O servidor de partidas não respondeu.")
		return

	BomberNet.ask_room(wanted, Game.players_of(Game.BOMBERMAN), Prefs.player_name())


func _exit_tree() -> void:
	Pairing.nfc.stop()


## Espera o aperto de mão do ENet fechar antes de pedir a sala: `connect_to` volta
## antes de a conexão existir, e um RPC mandado cedo demais some sem erro.
func _wait_connected() -> bool:
	for frame in 600:
		var peer := multiplayer.multiplayer_peer
		if peer != null:
			var status := peer.get_connection_status()
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				return true
			if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
				return false
		await get_tree().process_frame
	return false


func _on_joined(_seat: int, host: bool) -> void:
	_is_host = host
	%HostPanel.visible = host
	if host:
		var payload := Pairing.build_payload(Game.BOMBERMAN, BomberNet.code)
		%CodeLabel.text = BomberNet.code
		%QrCode.payload = payload
		%HostHint.text = _host_hint()
		%StartButton.visible = true
		%StatusLabel.text = "Sala %s aberta. Comece quando quiser." % BomberNet.code
		if Pairing.nfc.is_available():
			Pairing.nfc.broadcast(payload)
	else:
		%StatusLabel.text = "Na sala %s. Aguardando o anfitrião começar…" % BomberNet.code


func _host_hint() -> String:
	var channels := "No outro aparelho: digite %s, ou aponte a câmera para o QR." % BomberNet.code
	if Pairing.nfc.is_available():
		channels = "No outro aparelho: digite %s, aponte a câmera para o QR, ou encoste os dois (NFC)." % BomberNet.code
	return "%s Funciona de qualquer lugar com internet." % channels


## Quem está na sala, pelos nomes que o servidor anunciou. Assento de máquina tem
## nome vazio e não entra na conta — o servidor os preenche com bots ao começar.
func _on_seats(names: PackedStringArray) -> void:
	if not _is_host:
		return
	var here := PackedStringArray()
	for name in names:
		if name != "":
			here.append(name)
	if here.size() <= 1:
		%StatusLabel.text = "Sala %s aberta. Comece quando quiser." % BomberNet.code
	else:
		%StatusLabel.text = "Na sala: %s. Comece quando quiser." % ", ".join(here)


func _on_start_pressed() -> void:
	if not _is_host:
		return
	%StartButton.disabled = true
	%StatusLabel.text = "Começando…"
	BomberNet.start_match()


func _on_started() -> void:
	Pairing.nfc.stop()
	Game.local_seat = BomberNet.seat
	get_tree().change_scene_to_file(MATCH_SCENE)


func _on_denied(reason: int) -> void:
	_fail(_deny_text(reason))


func _deny_text(reason: int) -> String:
	match reason:
		BomberProtocol.Deny.NO_ROOM:
			return "Nenhuma sala com esse código. Confira os seis caracteres."
		BomberProtocol.Deny.ROOM_FULL:
			return "Essa sala está cheia ou a partida já começou."
		BomberProtocol.Deny.BAD_CODE:
			return "Código inválido."
		BomberProtocol.Deny.TOO_MANY_ROOMS:
			return "O servidor está cheio de salas agora. Tente de novo em instantes."
		BomberProtocol.Deny.ALREADY_SEATED:
			return "Este aparelho já está numa sala."
		_:
			return "Não consegui entrar na sala."


func _on_dropped() -> void:
	_fail("Conexão com o servidor perdida.")


func _fail(message: String) -> void:
	%StatusLabel.text = message
	%Toast.show_message(message, Banner.Kind.DANGER)


func go_back() -> void:
	_back_to_menu()


func _back_to_menu() -> void:
	if _left:
		return
	_left = true
	Pairing.nfc.stop()
	BomberNet.leave()
	BomberNet.pending_code = ""
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
