class_name JoinPanel
extends VBoxContainer

## Entrar numa partida que já existe: a lista de salas abertas, o código de 6
## caracteres, o QR e o NFC — os quatro caminhos, num nó só.
##
## Era a metade "convidado" da tela de pareamento, e morava atrás da escolha do
## jogo: para chegar aqui era preciso dizer "xadrez" ou "damas" antes. Ordem
## errada — quem entra joga o que o anfitrião abriu, e o jogador descobria isso
## ao chegar numa lista onde a única sala aberta era do outro jogo. Agora a
## pergunta some: cada sala já diz de que jogo é, e o aperto de mão traz o jogo
## junto com o ritmo.
##
## Componente e não tela: `scenes/join.tscn` o mostra inteiro, e ele não sabe o
## que tem em volta. O que ele **não** faz é trocar de cena — quando o anfitrião
## responde, quem navega é a tela, que é quem sabe de onde o jogador veio.
##
## O **NFC fica ligado o tempo todo** em que a tela está aberta, quando o
## aparelho tem. Era um botão "Encostar (NFC)": o jogador tocava nele e só então
## encostava os aparelhos — dois passos para uma tecnologia cujo gesto inteiro é
## encostar, e um botão que não fazia nada visível, o que fazia metade das
## pessoas tocar de novo achando que não tinha pegado. No lugar dele ficou uma
## frase dizendo que já está ligado, que é a única coisa que o botão realmente
## comunicava.
##
## A câmera continua atrás de um toque, e a diferença não é de gosto: ler NFC não
## acende nada nem pede permissão em tempo de execução, e a câmera faz as duas
## coisas. Rádio que custa é rádio que se liga quando pedem.
##
## O campo do código vem **antes** da lista, e não depois: quem chega aqui com um
## código na mão sabe exatamente o que quer, e é o caminho que funciona mesmo com
## a sala privada — a lista só mostra as públicas.

## Erro que muda o que o jogador deve fazer: código errado, sala cheia, leitura
## de outro app. Vai para o toast da tela, e não para a linha de status daqui —
## o rodapé é onde uma mensagem morre sem ninguém ver.
signal failed(message: String)

## Tocou numa bolacha de "Criar sala". A tela abre a folha daquele jogo em Online —
## o painel não navega, como nenhum componente do app.
signal create_requested(game_id: StringName)

## Uma sala aberta é uma pessoa esperando; a lista tem de acompanhar isso sem
## que ninguém precise puxar para atualizar. Curto o bastante para parecer vivo,
## longo o bastante para não virar uma requisição por segundo.
const ROOM_REFRESH := 6.0
const BOMBER_LOBBY_SCENE := "res://scenes/bomber_lobby.tscn"
## Jogos que já sabem receber espectador: os que usam `match.gd`. Os outros
## recebem quem assiste no relay, mas nenhuma tela deles mostraria a partida.
const WATCHABLE: Array[StringName] = [Game.CHESS, Game.CHECKERS]

## Trava contra dois toques seguidos em "Entrar", ou um QR lido no meio de uma
## tentativa que ainda não respondeu.
var _joining := false
var _rooms_timer := 0.0
## A última resposta do servidor, como veio. O filtro por jogo redesenha a partir
## daqui.
var _rooms: Array = []
var _live: Array = []
## Código da sala para onde se está **voltando** com a chave guardada, ou vazio. É o
## que transforma um "nenhuma partida com esse código" genérico em "essa partida já
## acabou" — e o que diz que a cadeira guardada pode ser esquecida.
var _rejoining := ""
var _resume_card: ResumeCard = null


func _ready() -> void:
	# Sem servidor de partidas o painel inteiro sai. Uma lista permanentemente
	# vazia com um campo de código que não leva a lugar nenhum lê como app
	# quebrado; o rodapé da tela já diz `On-line: não` uma vez.
	visible = Net.relay_available()
	if not visible:
		set_process(false)
		return

	Net.join_failed.connect(_on_join_failed)
	Pairing.payload_received.connect(join_payload)
	Pairing.payload_rejected.connect(_on_payload_rejected)
	Pairing.relay.state_changed.connect(_on_relay_state_changed)
	Pairing.relay.peer_present.connect(func(_seat: int): _show_waiting())
	Pairing.relay.peer_gone.connect(func(_seat: int): _show_waiting())
	Pairing.relay.watching.connect(_on_watching)
	Pairing.nfc.failed.connect(_fail)
	Pairing.qr_scanner.failed.connect(_fail)

	%RefreshButton.pressed.connect(_fetch_rooms)
	%RoomsRequest.request_completed.connect(_on_rooms_fetched)
	%JoinButton.pressed.connect(_join_by_code)
	%WatchButton.pressed.connect(_watch_by_code)
	%LiveRequest.request_completed.connect(_on_live_fetched)
	# A sexta casa vale o mesmo que tocar em "Entrar": quem acabou de digitar o
	# código inteiro não deveria ter de procurar um botão.
	%CodeInput.completed.connect(func(_code: String) -> void: _join_by_code())
	%ScanButton.pressed.connect(_start_scan)
	_fill_create_row()
	%ScanButton.visible = Pairing.qr_scanner.is_available()

	# O filtro é por **jogo**, e não por categoria como na tela inicial: quem
	# procura sala procura a partida de um jogo. Ele não vai ao servidor — a
	# resposta traz todas as salas abertas, que são poucas por natureza, e
	# refiltrar no aparelho responde no toque em vez de numa ida à rede.
	%GameFilter.setup(ChipBar.online_game_items())
	%GameFilter.selected.connect(func(_id: StringName) -> void:
		_render_rooms()
		_render_live())
	_set_hint()
	_clear_status()

	# O NFC escuta desde já: o gesto dele é encostar, e um botão antes disso é um
	# passo que não faz nada visível.
	%NfcHint.visible = Pairing.nfc.is_available()
	if Pairing.nfc.is_available():
		Pairing.nfc.listen()

	_offer_rejoin()
	_fetch_rooms()


## O mesmo cartão da tela inicial, no topo do painel. Quem caiu e vem direto para
## "Multiplayer" procurar a partida é exatamente quem precisa dele.
func _offer_rejoin() -> void:
	var pending := Prefs.pending_rejoin(int(Time.get_unix_time_from_system()))
	if pending.is_empty():
		return
	_resume_card = ResumeCard.new()
	_resume_card.game_id = pending["game"]
	_resume_card.code = pending["code"]
	_resume_card.saved_at = pending["at"]
	_resume_card.resume_pressed.connect(func(id: StringName, code: String) -> void:
		_enter_room(id, code)
	)
	_resume_card.dismissed.connect(_drop_rejoin)
	add_child(_resume_card)
	move_child(_resume_card, 0)


func _drop_rejoin() -> void:
	Prefs.forget_rejoin()
	if _resume_card != null:
		_resume_card.queue_free()
		_resume_card = null


## Tudo o que este painel acendeu é apagado aqui. Um link já estabelecido
## sobrevive — o socket do relay em particular *é* a partida, e pertence a `Net`.
func _exit_tree() -> void:
	Pairing.nfc.stop()
	Pairing.qr_scanner.stop()


# --- lista de salas abertas ---------------------------------------------------


func _process(delta: float) -> void:
	_rooms_timer -= delta
	if _rooms_timer <= 0.0:
		_fetch_rooms()


## Só salas que pediram para aparecer, e só enquanto esperam alguém — o servidor
## já filtra as cheias e as órfãs, então o que chega aqui é sempre entrável.
func _fetch_rooms() -> void:
	_rooms_timer = ROOM_REFRESH
	if _joining:
		return
	var address := Net.rooms_url()
	if address.is_empty():
		return
	# Uma requisição por vez: a anterior é abandonada em vez de enfileirada, e o
	# resultado velho não interessa mais.
	%RoomsRequest.cancel_request()
	%RoomsRequest.request(address)
	%LiveRequest.cancel_request()
	%LiveRequest.request(Net.live_url())


func _on_rooms_fetched(
	_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if code != 200:
		_set_rooms_placeholder("Não consegui falar com o servidor de partidas.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is not Dictionary:
		_set_rooms_placeholder("Resposta inesperada do servidor.")
		return
	show_rooms(Array(parsed.get("rooms", [])))


## Pública porque é o que a folha de prints planta para fotografar a lista cheia
## sem depender de haver partidas abertas de verdade no relay.
##
## A resposta fica guardada porque a tela a redesenha sem perguntar de novo: o
## filtro por jogo é uma pergunta sobre a lista que já chegou, e ir à rede a cada
## toque num chip seria uma requisição para não descobrir nada novo.
func show_rooms(rooms: Array) -> void:
	_rooms = rooms
	_render_rooms()


func _render_rooms() -> void:
	_clear_rooms()
	var wanted: StringName = %GameFilter.current
	var rooms := _rooms.filter(func(entry: Variant) -> bool:
		if entry is not Dictionary:
			return false
		if wanted == ChipBar.ALL:
			return true
		return StringName(str(entry.get("game", Game.CHESS))) == wanted
	)
	if rooms.is_empty():
		# Curto de propósito. A versão longa ensinava o que fazer em vez disso
		# ("use o código, ou volte e crie a sua"), mas as duas saídas estão na
		# tela — o campo logo acima e a gaveta logo ali —, e um parágrafo entre
		# elas só empurra as duas para longe.
		#
		# Com filtro ligado a frase diz **de que jogo** não há sala: "nenhuma sala
		# aberta" sob um chip de Ludo aceso faria o jogador concluir que o app
		# inteiro está vazio.
		if wanted == ChipBar.ALL:
			_set_rooms_placeholder("Nenhuma sala aberta agora.")
		else:
			_set_rooms_placeholder("Nenhuma sala de %s agora." % Game.game_title(wanted))
		return

	%RoomsEmpty.visible = false
	for entry in rooms:
		if entry is not Dictionary:
			continue
		var card := RoomCard.new()
		card.code = str(entry.get("code", ""))
		card.game_id = StringName(str(entry.get("game", Game.CHESS)))
		card.clock_label = Game.clock_label_for(int(entry.get("tc", 0)))
		# Um relay antigo não conta quem abriu, e o cartão volta a ser só o jogo.
		card.host_name = str(entry.get("host", ""))
		card.age_seconds = int(entry.get("age", 0))
		# Um relay antigo não conta assentos; dois é o que ele quis dizer.
		card.seats = int(entry.get("seats", 2))
		card.taken = int(entry.get("taken", 1))
		card.pressed.connect(_enter_room.bind(card.game_id, card.code))
		%RoomRows.add_child(card)


## Partidas públicas em andamento. Um relay antigo responde 404 em `/live`, e aí
## a seção simplesmente não aparece — ela não é o caminho principal desta tela.
func _on_live_fetched(
	_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if code == 200 else null
	show_live(Array(parsed.get("rooms", [])) if parsed is Dictionary else [])


## Pública pelo mesmo motivo de [method show_rooms]: dá para plantar a lista.
func show_live(rooms: Array) -> void:
	_live = rooms
	_render_live()


func _render_live() -> void:
	for child in %LiveRows.get_children():
		child.queue_free()
	var wanted: StringName = %GameFilter.current
	var shown := 0
	for entry in _live:
		if entry is not Dictionary:
			continue
		var id := StringName(str(entry.get("game", "")))
		if not WATCHABLE.has(id) or (wanted != ChipBar.ALL and id != wanted):
			continue
		var card := RoomCard.new()
		card.code = str(entry.get("code", ""))
		card.game_id = id
		card.clock_label = Game.clock_label_for(int(entry.get("tc", 0)))
		card.host_name = str(entry.get("host", ""))
		card.watchers = int(entry.get("watchers", 0))
		card.pressed.connect(_watch_room.bind(card.code))
		%LiveRows.add_child(card)
		shown += 1
	%LiveCaption.visible = shown > 0


func _clear_rooms() -> void:
	for child in %RoomRows.get_children():
		if child is RoomCard:
			child.queue_free()


func _set_rooms_placeholder(message: String) -> void:
	_clear_rooms()
	%RoomsEmpty.text = message
	%RoomsEmpty.visible = true


# --- os quatro caminhos -------------------------------------------------------


func _join_by_code() -> void:
	var code: String = %CodeInput.code
	if code.length() != Pairing.CODE_LENGTH:
		_fail("O código tem %d caracteres." % Pairing.CODE_LENGTH)
		return
	# Sem jogo junto: quem digita um código não sabe — nem precisa saber — o que o
	# anfitrião abriu, e o aperto de mão é quem responde isso.
	_enter_room(Game.game_id, code)


func _watch_by_code() -> void:
	var code: String = %CodeInput.code
	if code.length() != Pairing.CODE_LENGTH:
		_fail("O código tem %d caracteres." % Pairing.CODE_LENGTH)
		return
	_watch_room(code)


## Assistir. A tela troca de cena no `Net.watch_started`; recusa (sala que não
## existe, espectadores demais) volta pelo `join_failed`, como a de entrar.
func _watch_room(code: String) -> void:
	if _joining:
		_fail("Já estou tentando entrar numa sala. Espere terminar para tentar outra.")
		return
	_joining = true
	Game.mode = Game.Mode.ONLINE
	_set_status("Entrando para assistir a sala %s…" % code)
	Net.watch_relay(code)


## O relay confirmou a sala. Jogo que ainda não tem tela de espectador é recusado
## aqui, antes de esperar por uma partida que nunca seria desenhada.
func _on_watching(game_id: String, _capacity: int) -> void:
	if not _joining or WATCHABLE.has(StringName(game_id)):
		return
	Net.leave()
	_on_join_failed("Assistir ainda não está disponível para %s." % Game.game_title(StringName(game_id)))


## As bolachas de "Criar sala": um jogo por bolacha, só os que têm Online.
##
## Criar partida morava na outra aba, atrás de escolher o jogo. Mas quem abre o
## app para jogar com alguém já está aqui — e mandar essa pessoa para a coleção de
## jogos só para voltar é um desvio que não decide nada. A fileira é o mesmo
## catálogo, curto, do que dá para abrir daqui.
func _fill_create_row() -> void:
	for child in %CreateRow.get_children():
		%CreateRow.remove_child(child)
		child.queue_free()
	for id in Game.games_in():
		if not Game.mode_available(Game.Mode.ONLINE, id):
			continue
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		var button := Button.new()
		button.theme_type_variation = &"IconButton"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(56, 56)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void: create_requested.emit(id))
		var coaster := Coaster.new()
		coaster.set_anchors_preset(Control.PRESET_FULL_RECT)
		coaster.piece = Game.piece_of(id)
		button.add_child(coaster)
		column.add_child(button)
		var label := Label.new()
		label.text = Game.game_title(id)
		label.theme_type_variation = &"Caption"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		%CreateRow.add_child(column)


func _start_scan() -> void:
	_set_status("Abrindo a câmera…")
	Pairing.qr_scanner.start()


## Um QR lido ou uma tag NFC. O payload traz o jogo junto com o código, então
## quem leu um QR de xadrez segue o anfitrião mesmo tendo aberto o app pensando
## em damas.
##
## Público porque a tela também chama: um QR lido antes de o Android recolher o
## app sobrevive no plugin, e o pareamento continua por aqui.
func join_payload(info: Dictionary) -> void:
	_enter_room(StringName(str(info.get("game", Game.game_id))), str(info.get("code", "")))


func _enter_room(id: StringName, code: String) -> void:
	if code.is_empty():
		return
	if _joining:
		_fail("Já estou tentando entrar numa sala. Espere terminar para tentar outra.")
		return
	_joining = true
	Game.mode = Game.Mode.ONLINE
	Game.role = Game.Role.GUEST
	Game.game_id = id
	# O Bomberman entra pelo servidor autoritativo, e não pelo relay: manda o código
	# pro lobby próprio dele, que conecta e pede a sala. Os outros cinco seguem no
	# relay.
	if id == Game.BOMBERMAN:
		BomberNet.pending_code = code.strip_edges().to_upper()
		get_tree().change_scene_to_file(BOMBER_LOBBY_SCENE)
		return
	_set_status("Procurando a sala %s…" % code)
	# Qualquer caminho até a sala leva a chave, se este aparelho tiver uma para ela:
	# o cartão de voltar, o código digitado, a sala tocada na lista ou o QR. Quem
	# caiu não precisa saber qual deles devolve a cadeira certa.
	var key := Prefs.rejoin_key(code)
	_rejoining = code.to_upper() if not key.is_empty() else ""
	Net.join_relay(code, id, key)


# --- retorno ------------------------------------------------------------------


func _on_relay_state_changed(state: RelayBridge.State) -> void:
	if Net.connected or not _joining:
		return
	match state:
		RelayBridge.State.CONNECTING:
			_set_status("Falando com o servidor…")
		RelayBridge.State.WAITING:
			_show_waiting()
		RelayBridge.State.RECONNECTING:
			_set_status("Conexão instável; tentando de novo…")
		_:
			pass


## Quem já está na sala, enquanto ela não enche.
##
## Numa mesa de quatro, "aguardando" sem número é uma espera sem fim aparente:
## quem entrou não sabe se falta um ou três. Numa de dois o número não diz nada
## que a frase já não diga.
##
## Chamado também quando alguém chega ou sai, e não só na troca de estado: entre
## o segundo e o quarto jogador o estado continua sendo `WAITING`, e sem isso o
## contador ficava congelado em "1 de 4".
## A espera saiu da linha de status e virou painel, e o painel é da **cena**.
##
## A linha dizia o número e não dizia em que partida se entrou — que é a dúvida de
## quem digitou um código que alguém mandou por mensagem. E ela é pequena no meio
## de uma tela que, durante a espera, não tem mais nada para tocar: lia como app
## travado.
##
## Quem desenha é a cena porque o painel cobre a tela inteira, e este nó é uma
## faixa dentro dela. O sinal leva o que o relay já sabe assim que dá a cadeira —
## jogo, código e lotação —, tudo antes de o anfitrião ter dito qualquer coisa.
signal waiting(game_id: StringName, code: String, present: PackedInt32Array, capacity: int, local_seat: int)
signal waiting_ended


func _show_waiting() -> void:
	if not _joining:
		return
	# Quem assiste não tem cadeira na mesa que enche: só espera ela começar.
	if Net.is_spectator:
		_set_status("Na sala. A partida começa quando os jogadores chegarem…")
		return
	var capacity := Pairing.relay.capacity()
	waiting.emit(
		Game.game_id, Pairing.relay.room_code(), Pairing.relay.present_seats(),
		capacity, Pairing.relay.seat()
	)
	if capacity > 2:
		_set_status("Na sala: %d de %d jogadores." % [Pairing.relay.seats_taken(), capacity])
	else:
		_set_status("Entrou na sala. Aguardando o anfitrião…")


func _on_join_failed(reason: String) -> void:
	_joining = false
	waiting_ended.emit()
	_clear_status()
	if not _rejoining.is_empty():
		_rejoining = ""
		# Recusa que não muda tentando de novo: a sala acabou, ou a cadeira foi de
		# outra pessoa e a mesa encheu. A partida guardada deixa de ser oferecida —
		# um cartão que sempre leva ao mesmo erro é pior que cartão nenhum.
		match Pairing.relay.refusal():
			"room_not_found":
				_drop_rejoin()
				reason = "Essa partida já acabou — a sala foi fechada."
			"room_full":
				_drop_rejoin()
				reason = "Sua cadeira foi ocupada e a mesa está cheia."
	_fail(reason)


## Desistiu da espera. Larga a cadeira em vez de só fechar o painel: o servidor a
## reservou, e uma cadeira ocupada por ninguém deixa a sala "cheia" com gente de
## menos até a carência expirar.
func give_up() -> void:
	_joining = false
	%CodeInput.clear()
	waiting_ended.emit()
	_clear_status()
	Net.leave()


## A linha de status só existe **enquanto algo acontece**. Parada, ela dizia
## "escolha uma sala ou digite o código" embaixo de uma lista de salas e de um
## campo de código — instrução para quem já está olhando para os dois, e uma
## terceira linha de texto numa região que já tinha duas.
##
## Sumir e não esvaziar: uma linha vazia continua ocupando altura, e o espaço
## abre e fecha sozinho a cada mensagem.
func _clear_status() -> void:
	%Status.text = ""
	%Status.visible = false


func _set_status(message: String) -> void:
	%Status.text = message
	%Status.visible = true


## Algo foi decodificado, só não era nosso — um QR qualquer, ou um anfitrião
## rodando um build antigo. Dizer isso é melhor que parecer um leitor morto.
func _on_payload_rejected(text: String) -> void:
	var preview := text.substr(0, 40)
	if text.length() > 40:
		preview += "…"
	_fail("Código lido, mas não é de uma partida deste jogo: \"%s\"" % preview)


func _fail(message: String) -> void:
	failed.emit(message)


## Caminho que some sem explicação lê como app quebrado — então a ausência é dita
## uma vez, numa linha, e só quando existe.
##
## Some, e não fica apagado: um botão desabilitado ocupa o mesmo espaço de um que
## funciona e ainda convida ao toque.
##
## O texto encolheu de três linhas para uma. A versão longa explicava plugin
## Android, dizia que o código tem 6 caracteres e prometia que ele funciona de
## qualquer rede — três coisas que ninguém lê empilhadas embaixo de uma lista, e
## que o campo logo acima já responde por existir.
func _set_hint() -> void:
	var missing := PackedStringArray()
	if not Pairing.qr_scanner.is_available():
		missing.append("QR")
	if not Pairing.nfc.is_available():
		missing.append("NFC")
	%Hint.visible = not missing.is_empty()
	%Hint.text = "Sem %s neste aparelho — use o código." % " nem ".join(missing)
