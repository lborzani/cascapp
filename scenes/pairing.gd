extends Control

## A sala aberta, esperando alguém: o código de 6 caracteres, o QR e o cartão
## NFC emulado.
##
## Só do lado de **quem abre**. A metade "convidado" desta tela virou
## `ui/join_panel.tscn` e mora na tela inicial, porque entrar numa partida não é
## uma decisão sobre um jogo — e aqui ela obrigava a escolher um antes de ver a
## lista de salas. O que sobrou é simétrico ao que aquele painel faz: um lado
## anuncia a sala, o outro procura.
##
## Não há lista de partidas na rede, endereço IP nem hotspot. Aquilo existia
## quando a partida era uma ligação direta entre os dois aparelhos, e cobrava por
## isso: o convidado esperava tentativas de conexão a endereços que o Wi-Fi
## doméstico costuma bloquear, e a tela mostrava IPs — que não é o que alguém
## quer ler para entrar numa sala.

const MENU_SCENE := "res://scenes/main_menu.tscn"

var _code := ""
## A sala desta tela é pelo Bluetooth, sem internet. Ver [method _toggle_bluetooth].
var _bluetooth := false
var _bluetooth_button: Button = null


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	# Entrada curta: troca de tela sem corte seco.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)
	Net.opponent_joined.connect(_on_opponent_joined)
	# Mesa de mais de dois: a partida começa quando **enche**, não quando o
	# primeiro chega. Os dois sinais existem porque respondem coisas diferentes.
	Net.table_ready.connect(_on_table_ready)
	Net.relay_unavailable.connect(_on_relay_unavailable)
	Pairing.relay.state_changed.connect(_on_relay_state_changed)
	# Entre o segundo e o quarto jogador o estado da sala não muda — continua
	# `WAITING` —, então quem atualiza o contador é a chegada de cada um.
	Pairing.relay.peer_present.connect(func(_seat: int): _on_relay_state_changed(Pairing.relay.state()))
	Pairing.relay.peer_gone.connect(func(_seat: int): _on_relay_state_changed(Pairing.relay.state()))
	Pairing.nfc.failed.connect(_show_error)
	%BotsButton.pressed.connect(_start_with_bots)
	%CopyButton.pressed.connect(_copy_code)
	%QrButton.pressed.connect(_toggle_qr)
	# Só onde há rádio para isso: num aparelho sem Bluetooth LE o botão prometeria
	# uma partida que não acontece.
	if Pairing.ble.is_available():
		_bluetooth_button = Button.new()
		_bluetooth_button.name = "BluetoothButton"
		_bluetooth_button.theme_type_variation = &"GhostButton"
		_bluetooth_button.pressed.connect(_toggle_bluetooth)
		%HostHint.add_sibling(_bluetooth_button)

	# O título da barra é o que a tela **é**; a linha abaixo dela é o que esta
	# partida em particular tem — o jogo e o ritmo. Estavam juntos numa frase só,
	# e era a frase que crescia: "Xadrez • Criar partida • 3 + 2" não cabe numa
	# barra sem reticências, e o que sumia no corte era justamente o ritmo.
	%AppBar.title = "Criar partida"
	%AppBar.leading = IconButton.Kind.BACK
	%AppBar.leading_pressed.connect(_back_to_menu)

	%Title.text = Game.game_title()
	if Game.has_clock():
		%Title.text = "%s • %s" % [%Title.text, Game.clock_label()]
	elif Game.supports_rounds():
		%Title.text = "%s • %s" % [%Title.text, Game.round_limit_label()]
	%Seats.capacity = Game.players_of()
	%Seats.local_seat = 0
	_setup_host()
	_refresh_seats()


## Tudo o que esta tela acendeu é apagado aqui. Um link já estabelecido
## sobrevive — o socket do relay em particular *é* a partida, e pertence a `Net`.
func _exit_tree() -> void:
	Pairing.nfc.stop()
	Friends.pending_invite = ""


func _setup_host() -> void:
	_code = Pairing.generate_code()
	# Quem hospeda decide o ritmo e o formato; os dois viajam no `welcome` para
	# quem entrar. O que vai no `option` depende do jogo — limite de rodadas em
	# Metrópole, semente do baralho no Uno —, e quem sabe disso é o catálogo.
	Net.time_control = Game.time_control
	Net.option = Game.host_option()

	%CodeLabel.text = _code
	_open_room()


## Abre a sala no relay ou, com [member _bluetooth], neste próprio aparelho.
func _open_room() -> void:
	var payload := Pairing.build_payload(Game.game_id, _code, _bluetooth)
	%QrCode.payload = payload
	%HostHint.text = _host_hint()
	%StatusLabel.text = "Abrindo a sala…"
	if _bluetooth_button != null:
		_bluetooth_button.text = "Voltar para a internet" if _bluetooth else "Sem internet? Jogar por Bluetooth"

	if not _bluetooth and not Net.relay_available():
		_show_error("Este build não tem servidor de partidas configurado, então não dá para abrir uma sala.")
		%StatusLabel.text = "Sem servidor de partidas neste build."
		return

	# A capacidade da mesa vem do catálogo: dois para xadrez, damas e batalha
	# naval, quatro para o Ludo. A sala nasce do tamanho do jogo.
	#
	# Quem joga de brancas sai na moeda nos jogos que pedem (`coin_toss` no
	# catálogo). Antes era sempre quem abria a sala.
	var white := randi() % 2 if Game.entry_of(Game.game_id).get("coin_toss", false) else 0
	Pairing.relay.via_bluetooth = _bluetooth
	# Sala pública não existe sem internet: a lista mora no servidor.
	Net.host_relay(Game.game_id, _code, Game.listed_room and not _bluetooth, Game.players_of(), white)
	# O anfitrião também emula o cartão NFC. Um erro aqui era silencioso antes:
	# o outro aparelho encostava, vibrava e não recebia nada, sem ninguém saber.
	if Pairing.nfc.is_available():
		Pairing.nfc.broadcast(payload)


## Troca a sala entre a internet e o Bluetooth, com o mesmo código.
##
## A tela abre pela internet, que é o caminho de sempre, e o botão é a saída para
## quando ela falta: dois celulares lado a lado, sem rede. O código não muda, para
## o que já foi dito em voz alta continuar valendo — só o QR e o NFC ganham o
## marcador que manda o convidado pelo Bluetooth.
func _toggle_bluetooth() -> void:
	if not _bluetooth:
		var problem: String = await Pairing.ble.prepare()
		if not is_inside_tree():
			return
		if not problem.is_empty():
			_show_error(problem)
			return
	_bluetooth = not _bluetooth
	Net.leave()
	_open_room()


func _host_hint() -> String:
	if _bluetooth:
		var how := "No outro celular: na aba Online, digite %s e toque em Bluetooth, ou aponte a câmera para o QR." % _code
		if Pairing.nfc.is_available():
			how = "No outro celular: digite %s e toque em Bluetooth, aponte a câmera para o QR, ou encoste os dois (NFC)." % _code
		return "%s Sem internet: os dois precisam estar perto, com o Bluetooth ligado." % how
	if Game.listed_room:
		return "Esta sala aparece na aba Online do outro aparelho. Quem tiver o código %s também entra direto." % _code
	# "Na aba Online", e não "em Multiplayer" nem "na tela inicial": o campo do
	# código mudou de lugar duas vezes (gaveta, depois aba), e uma instrução que
	# aponta para onde a coisa **estava** é pior que instrução nenhuma.
	var channels := "No outro aparelho: na aba Online, digite %s no campo do código, ou aponte a câmera para o QR." % _code
	if Pairing.nfc.is_available():
		channels = "No outro aparelho: digite %s, aponte a câmera para o QR, ou encoste os dois (NFC)." % _code
	return "%s Funciona de qualquer lugar com internet — não precisa ser a mesma rede." % channels


## A sala **é** o produto: sem ela o código na tela não leva a lugar nenhum, e o
## convidado recebe "nenhuma partida com esse código" — que parece erro de
## digitação dele. Quem tem de saber que a sala não abriu é quem a abriu.
func _on_relay_unavailable(reason: String) -> void:
	%StatusLabel.text = "A sala não abriu."
	if _bluetooth:
		# O motivo já vem em texto de gente: rádio desligado, anúncio recusado.
		_show_error(reason)
		return
	var message := "Não consegui abrir a sala. Confira a internet deste aparelho — sem sala, o código não leva o outro jogador a lugar nenhum."
	if _bluetooth_button != null:
		message += " Sem internet, toque em \"Jogar por Bluetooth\"."
	_show_error(message)


func _on_relay_state_changed(state: RelayBridge.State) -> void:
	_refresh_seats()
	if Net.connected:
		return
	match state:
		RelayBridge.State.CONNECTING:
			%StatusLabel.text = "Abrindo a sala pelo Bluetooth…" if _bluetooth else "Falando com o servidor…"
		RelayBridge.State.WAITING:
			%StatusLabel.text = "Sala %s aberta. %s" % [_code, _waiting_text()]
			if _bluetooth:
				return  # Convite de amigo vai pela internet.
			# A sala existe no relay agora: o amigo chamado pela gaveta já acha ela.
			var invited := Friends.send_pending_invite(Game.game_id, _code)
			if not invited.is_empty():
				%Toast.show_message("Chamei %s para esta sala." % invited, Banner.Kind.INFO)
		RelayBridge.State.RECONNECTING:
			%StatusLabel.text = "Conexão instável; tentando de novo…"
		_:
			pass


## O código na área de transferência: quem abre a sala manda ele por mensagem, e
## copiar à mão um código de seis letras lidas da tela é onde nasce o "nenhuma
## partida com esse código" que parece erro de digitação — e é.
func _copy_code() -> void:
	DisplayServer.clipboard_set(_code)
	Sound.play(Sound.Cue.TAP)
	%Toast.show_message("Código %s copiado." % _code, Banner.Kind.INFO)


## O QR começa escondido. Ele ocupa meia tela e serve a um caminho só — o outro
## aparelho apontando a câmera —, enquanto o código serve a todos.
func _toggle_qr() -> void:
	%QrCard.visible = not %QrCard.visible
	%QrButton.text = "Esconder QR" if %QrCard.visible else "Mostrar QR"


## As cadeiras da mesa, como o relay as conhece. O anfitrião é sempre a de baixo.
func _refresh_seats() -> void:
	var present := PackedInt32Array([0])
	for seat in Pairing.relay.present_seats():
		if not present.has(seat):
			present.append(seat)
	%Seats.capacity = maxi(Game.players_of(), 2)
	%Seats.present = present
	%Seats.refresh()
	var players := Game.players_of()
	%SeatsCount.text = (
		"%d de %d" % [present.size(), players] if players > 2 else "2 lugares"
	)


## Quantos já estão na mesa, quando isso é uma pergunta. Numa sala de dois,
## "aguardando o outro jogador" já diz tudo — contar "1 de 2" seria informar uma
## fração que só tem um valor possível.
func _waiting_text() -> String:
	_refresh_bots_button()
	var players := Game.players_of()
	if players <= 2:
		return "Aguardando o outro jogador…"
	return "Aguardando: %d de %d jogadores." % [Pairing.relay.seats_taken(), players]


## "Começar com bots" só aparece quando ele é a saída para um problema real: a
## mesa não enche. Antes de alguém chegar, o botão diria "jogue sozinho contra
## três máquinas numa sala on-line", que é o modo solo com passos a mais — e
## esse já está no menu.
##
## Some assim que a mesa enche, porque aí não falta ninguém para substituir.
func _refresh_bots_button() -> void:
	var taken := Pairing.relay.seats_taken()
	%BotsButton.visible = (
		Game.mode_available(Game.Mode.SOLO)
		and Game.players_of() > 2
		and taken >= 2
		and taken < Game.players_of()
	)
	%BotsButton.text = "Começar com %d bot(s)" % (Game.players_of() - taken)


## As cadeiras vazias viram máquina, e a partida começa. Quem as joga é este
## aparelho — o assento 0 —, porque dois aparelhos rolando o dado do mesmo bot
## produziriam dois lances para a mesma vez.
func _start_with_bots() -> void:
	var empty := PackedInt32Array()
	var present := Pairing.relay.present_seats()
	for seat_index in Game.players_of():
		if not present.has(seat_index):
			empty.append(seat_index)
	if empty.is_empty():
		return
	%BotsButton.disabled = true
	%StatusLabel.text = "Começando com %d bot(s)…" % empty.size()
	Net.start_with_bots(empty)


func _on_opponent_joined(_remote_side: int) -> void:
	Game.local_side = Net.local_side
	Pairing.nfc.stop()
	get_tree().change_scene_to_file(Game.match_scene())


func _on_table_ready(_seats: int) -> void:
	Game.local_seat = Net.local_seat
	Pairing.nfc.stop()
	get_tree().change_scene_to_file(Game.match_scene())


## Toast no topo, e não a linha de status do rodapé. A distinção entre os dois é
## o que acontece *sozinho* e o que **muda o que o jogador deve fazer** — e o
## rodapé é onde um texto morre sem ninguém ver, entre uma mensagem de progresso
## e outra.
func _show_error(message: String) -> void:
	%Toast.show_message(message, Banner.Kind.DANGER)


## Sair daqui pelo gesto fecha a sala, como o botão "Voltar" — `reset_to_menu()`
## desliga o link, o NFC e a câmera. Uma sala que continuasse aberta depois de o
## anfitrião ter saído da tela apareceria na lista pública sem ninguém dentro.
func go_back() -> void:
	_back_to_menu()


## Voltar daqui é desfazer a escolha "quero abrir uma sala", e não largar o jogo:
## a tela inicial reabre a folha dele, que é a tela de onde se veio.
func _back_to_menu() -> void:
	Game.pending_sheet = Game.game_id
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
