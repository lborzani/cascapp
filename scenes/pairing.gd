extends Control

## A sala aberta, esperando alguém: o código de 6 caracteres, o QR e o cartão
## NFC emulado.
##
## O topo é uma faixa na cor do jogo, com o código bem grande — é o que se dita
## em voz alta para a mesa — e os três jeitos de passá-lo adiante: copiar, QR e
## convidar um amigo que esteja online. Embaixo, um lugar por linha, com os
## vazios pulsando, e no rodapé o botão de começar.
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
## A lista de amigos online para chamar, enquanto está na tela.
var _invite_card: PanelContainer = null


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
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
	# O nome e o visual da conta de quem sentou chegam depois da chegada.
	Net.names_changed.connect(_refresh_seats)
	Pairing.nfc.failed.connect(_show_error)
	%BotsButton.pressed.connect(_start_with_bots)
	%InviteButton.pressed.connect(_invite)
	%BackButton.pressed.connect(_back_to_menu)
	_dress_band()
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

	# O título diz que sala é esta; o ritmo (ou o limite de rodadas) vai ao lado da
	# lotação, em `_refresh_seats`.
	%Title.text = "Sala de %s" % Game.game_title()
	%Seats.capacity = Game.players_of()
	%Seats.game_id = Game.game_id
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
	# Uma linha só: o código já está enorme logo acima, e repeti-lo aqui com três
	# canais empilhados era o parágrafo que ninguém lia.
	if Game.listed_room:
		return "Sala pública: aparece na aba Online de quem abrir o app. Com o código também se entra."
	if Pairing.nfc.is_available():
		return "Quem entra digita o código na aba Online, lê o QR ou encosta os aparelhos."
	return "Quem entra digita o código na aba Online, ou lê o QR."


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
	var parts := PackedStringArray()
	if Game.has_clock():
		parts.append(Game.clock_label())
	elif Game.supports_rounds():
		parts.append(Game.round_limit_label())
	parts.append("%d de %d" % [present.size(), maxi(players, 2)])
	%SeatsCount.text = " · ".join(parts)


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
	var players := Game.players_of()
	var can_start := (
		Game.mode_available(Game.Mode.SOLO) and players > 2 and taken >= 2 and taken < players
	)
	# O botão do rodapé está sempre lá: apagado, diz o que falta; aceso, é a saída
	# para a mesa que não enche.
	%BotsButton.disabled = not can_start
	if can_start:
		%BotsButton.text = "Começar com %d bot(s)" % (players - taken)
	else:
		%BotsButton.text = "Esperando o outro jogador" if players <= 2 else "Esperando jogadores"


## A faixa do topo na cor do jogo, e os botões escuros sobre ela.
func _dress_band() -> void:
	var color: Color = AppTheme.GAME_COLORS.get(String(Game.game_id), AppTheme.SURFACE_HIGH)
	var band := AppTheme.box(color, 0)
	band.corner_radius_bottom_left = 32
	band.corner_radius_bottom_right = 32
	band.border_width_bottom = 6
	band.border_color = color.darkened(0.3)
	band.content_margin_left = AppTheme.SCREEN_PAD
	band.content_margin_right = AppTheme.SCREEN_PAD
	band.content_margin_top = AppTheme.SPACE_L
	band.content_margin_bottom = AppTheme.SPACE_XL
	%Band.add_theme_stylebox_override("panel", band)
	var ink := AppTheme.ACCENT_INK
	for label: Label in [%Title, %SeatsCount, %CodeCaption, %CodeLabel]:
		label.add_theme_color_override("font_color", ink)
	%Title.add_theme_font_override("font", AppTheme.display(700))
	%Title.add_theme_font_size_override("font_size", 22)
	for label: Label in [%SeatsCount, %CodeCaption]:
		label.add_theme_font_override("font", AppTheme.font(800))
		label.add_theme_font_size_override("font_size", AppTheme.SIZE_CAPTION + 1)
	%CodeLabel.add_theme_font_override("font", AppTheme.display(700))
	%CodeLabel.add_theme_font_size_override("font_size", 56)
	for button: Button in [%BackButton, %CopyButton, %QrButton, %InviteButton]:
		button.add_theme_font_override("font", AppTheme.font(800))
		button.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY_S)
		for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, AppTheme.TEXT)
		var dark := AppTheme.box(AppTheme.BACKGROUND, AppTheme.RADIUS)
		dark.content_margin_left = 8
		dark.content_margin_right = 8
		for state: String in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, dark)
	# A seta das outras telas, desenhada, e não o caractere "<": a mesma forma do
	# voltar das partidas.
	%BackButton.text = ""
	%BackButton.custom_minimum_size = Vector2(44, 44)
	%BackButton.draw.connect(func() -> void:
		var center: Vector2 = %BackButton.size * 0.5
		var reach := 7.0
		%BackButton.draw_polyline(PackedVector2Array([
			center + Vector2(reach * 0.6, -reach),
			center + Vector2(-reach * 0.6, 0.0),
			center + Vector2(reach * 0.6, reach),
		]), AppTheme.TEXT, 3.0, true)
	)


## Chama um amigo que está online para esta sala. Sem ninguém online (ou sem
## conta), o caminho é o código por mensagem — e o aviso diz isso.
func _invite() -> void:
	var online := _invitable()
	if online.is_empty():
		%Toast.show_message("Nenhum amigo online agora. Copie o código e mande por mensagem.", Banner.Kind.INFO)
		return
	if _invite_card != null:
		_invite_card.queue_free()
	_invite_card = PanelContainer.new()
	_invite_card.theme_type_variation = &"Card"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", AppTheme.SPACE_S)
	_invite_card.add_child(list)
	var title := Label.new()
	title.theme_type_variation = &"SectionHeader"
	title.text = "Chamar para esta sala"
	list.add_child(title)
	for friend: Dictionary in online:
		var id := str(friend.get("id", ""))
		var call := Button.new()
		call.theme_type_variation = &"GhostButton"
		call.alignment = HORIZONTAL_ALIGNMENT_LEFT
		call.text = Friends.name_of(id)
		call.pressed.connect(func() -> void:
			Friends.invite(id, Game.game_id, _code)
			%Toast.show_message("Chamei %s para esta sala." % Friends.name_of(id), Banner.Kind.INFO)
			call.disabled = true
		)
		list.add_child(call)
	%HostHint.add_sibling(_invite_card)


## Os amigos online que dá para chamar: fora quem já está sentado nesta sala, pela
## conta confirmada do assento ou pela presença dele apontando para este código.
func _invitable() -> Array:
	var seated := {}
	for seat: int in Net.verified_seats:
		seated[str(Net.profile_of(seat).get("user", ""))] = true
	return Friends.sorted().filter(func(friend: Dictionary) -> bool:
		var id := str(friend.get("id", ""))
		var status: Variant = Friends.online.get(id)
		if status == null or seated.has(id):
			return false
		return not (status is Dictionary and str(status.get("room", "")) == _code)
	)


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
