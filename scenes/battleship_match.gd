extends Control

## Partida de batalha naval. Só em rede — sem mesa e sem bot, porque os dois
## jogadores não podem ver o mar um do outro e num aparelho só isso exigiria uma
## cortina entre cada tiro.
##
## Cena própria, e não o `match.tscn`: aquele é inteiro sobre selecionar uma peça
## e movê-la, com relógio, pré-movimentação e animação de trajeto. Aqui não há
## peça que ande — há duas grades, uma fase de posicionamento antes do primeiro
## lance e metade da informação escondida. Sobrava a moldura, e ela já mora no
## `GridView`.
##
## **Dois mares ao mesmo tempo, e não um alternando.** O de cima é onde se age, o
## de baixo é o que se perde. Trocar um pelo outro conforme a vez pareceu mais
## limpo no papel e é desorientador na mão: a tela muda sozinha entre o toque e a
## resposta, e o jogador deixa de saber onde está olhando.

const MENU_SCENE := "res://scenes/game_menu.tscn"

## Posicionar → esperar o outro → atirar → acabou.
enum Phase { PLACING, WAITING, FIRING, OVER }

var _rules := BattleshipRules.new()
var _match_status: MatchStatus = null
var _state: MatchState
var _phase := Phase.PLACING
var _outcome := Ruleset.Outcome.ONGOING
var _abandoned := false
var _disconnected := false

## Frota em montagem, antes de virar oficial. Separada do estado de propósito: o
## jogador pode limpar e recomeçar, e enquanto ele mexe a partida não existe.
var _draft := PackedInt32Array()
var _next_ship := 0
var _horizontal := true
var _confirmed := false

## A frota do adversário pode chegar antes de o jogador terminar a dele. Guardar
## em vez de aplicar direto é o que evita perder a mensagem — ela vem uma vez.
var _enemy_fleet := PackedInt32Array()

## Casa mirada. O tiro sai no **segundo** toque na mesma casa: no celular um
## toque perdido custaria a vez inteira, e não há como desfazer um tiro.
var _aim := Board.NO_SQUARE

var _rematch_offered := false
var _rematch_incoming := false
var _rematch_refused := false

@onready var _enemy: WatersView = %EnemyWaters
@onready var _own: WatersView = %OwnWaters
@onready var _place: WatersView = %PlaceWaters
@onready var _banner: Banner = %Banner


func _ready() -> void:
	theme = AppTheme.shared()
	_state = _rules.initial_state()
	_draft = BattleshipRules.empty_grid()

	_own.own = true
	_own.labels = false
	_own.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place.own = true
	_enemy.square_tapped.connect(_on_enemy_tapped)
	_place.square_tapped.connect(_on_place_tapped)

	%RotateButton.pressed.connect(_rotate)
	%ShuffleButton.pressed.connect(_shuffle)
	%ClearButton.pressed.connect(_clear)
	%ConfirmButton.pressed.connect(_confirm_fleet)
	%ExitButton.confirmed.connect(_exit)
	%LeaveButton.pressed.connect(_exit)
	%RematchButton.pressed.connect(_on_rematch_button)
	%RematchDeclineButton.pressed.connect(_decline_rematch)

	Net.move_received.connect(_on_remote_move)
	Net.fleet_received.connect(_on_enemy_fleet)
	Net.opponent_left.connect(_on_opponent_left)
	Net.link_lost.connect(_on_link_lost)
	Net.link_restored.connect(_on_link_restored)
	Net.sync_received.connect(_on_sync)
	# Os nomes chegam **depois** da tela: quem entra se apresenta no `ready` e
	# quem volta no `resumed`, e os dois caem no meio de uma partida já desenhada.
	# Sem isto o cartão só se corrigia no lance seguinte.
	Net.names_changed.connect(_refresh)
	Net.rematch_requested.connect(_on_rematch_requested)
	Net.rematch_accepted.connect(_start_rematch)
	Net.rematch_declined.connect(_on_rematch_declined)

	%OverlayLayer.visible = false

	# Acima de "Sair", que é o rodapé desta tela. A faixa é contexto e o botão é
	# saída: ficam juntos porque nenhum dos dois é sobre o mar.
	Game.begin_match()
	_match_status = MatchStatus.create()
	var column := %ExitButton.get_parent()
	column.add_child(_match_status)
	column.move_child(_match_status, %ExitButton.get_index())

	_refresh()
	# Depois de montar a partida: quem entrou numa que já estava em curso recebeu o
	# histórico antes desta cena existir, e ele ficou guardado esperando.
	Net.claim_sync()


# --- posicionamento ----------------------------------------------------------


## Toque numa casa pousa o próximo navio com a proa ali. Inválido não faz nada e
## não avisa: o rastro que não cabe simplesmente não aparece, e insistir com um
## erro a cada toque errado seria ruído numa tela em que errar não custa nada.
func _on_place_tapped(square: int) -> void:
	if _phase != Phase.PLACING or _next_ship >= BattleshipRules.SHIPS.size():
		return
	var ship: Dictionary = BattleshipRules.SHIPS[_next_ship]
	if not BattleshipRules.can_place(_draft, square, int(ship["size"]), _horizontal):
		return
	_draft = BattleshipRules.place(_draft, int(ship["kind"]), square, _horizontal)
	_next_ship += 1
	_refresh()


func _rotate() -> void:
	_horizontal = not _horizontal
	_refresh()


func _shuffle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_draft = BattleshipRules.random_fleet(rng)
	_next_ship = BattleshipRules.SHIPS.size()
	_refresh()


func _clear() -> void:
	_draft = BattleshipRules.empty_grid()
	_next_ship = 0
	_refresh()


func _fleet_complete() -> bool:
	return _next_ship >= BattleshipRules.SHIPS.size()


func _draft_is_empty() -> bool:
	for square in Board.SQUARE_COUNT:
		if _draft[square] != 0:
			return false
	return true


## A frota vira oficial e viaja. A partir daqui ela não muda mais — e é por isso
## que o botão só aparece com os quatro navios pousados: metade de uma frota
## enviada seria uma partida impossível de vencer, sem jeito de voltar atrás.
func _confirm_fleet() -> void:
	if not _fleet_complete() or _confirmed:
		return
	_confirmed = true
	BattleshipRules.set_fleet(_state, Game.local_side, _draft)
	if Game.mode == Game.Mode.ONLINE:
		Net.send_fleet(_draft)
	_adopt_enemy_fleet()
	_refresh()


## Aplica a frota do adversário se ela já chegou, e começa a partida quando as
## duas estão no lugar.
func _adopt_enemy_fleet() -> void:
	if not _enemy_fleet.is_empty():
		BattleshipRules.set_fleet(_state, Board.opponent(Game.local_side), _enemy_fleet)
	_phase = Phase.FIRING if BattleshipRules.ready(_state) else Phase.WAITING


func _on_enemy_fleet(cells: PackedInt32Array) -> void:
	_enemy_fleet = cells
	if not _confirmed:
		return
	_adopt_enemy_fleet()
	_refresh()


# --- tiro --------------------------------------------------------------------


func _on_enemy_tapped(square: int) -> void:
	if _phase != Phase.FIRING or not _my_turn():
		return
	if BattleshipRules.shots_of(_state, Game.local_side)[square] != BattleshipRules.Shot.NONE:
		return
	# Primeiro toque mira, segundo na mesma casa atira. Uma casa diferente move a
	# mira em vez de disparar — mudar de ideia não pode custar o tiro.
	if _aim != square:
		_aim = square
		_refresh()
		return
	var chosen := _legal_shot(square)
	if chosen == null:
		return
	_aim = Board.NO_SQUARE
	_play(chosen, true)


func _legal_shot(square: int) -> Move:
	for move in _rules.generate_moves(_state):
		if move.to_square() == square:
			return move
	return null


func _play(move: Move, broadcast: bool) -> void:
	var index := _state.ply
	var note := _rules.notation(_state, move)
	var mine := _state.side_to_move == Game.local_side
	_rules.apply_move(_state, move)
	if broadcast and Game.mode == Game.Mode.ONLINE:
		Net.send_move(move.to_dict(), index)
	_announce(note, mine)
	_refresh()


## O texto do lance já diz tudo — a notação carrega "×" no acerto e o nome do
## navio no afundamento. Só a cor muda conforme de quem foi a sorte.
func _announce(note: String, mine: bool) -> void:
	var hit := note.contains("×") or note.contains("afundou")
	var kind := Banner.Kind.INFO
	if hit:
		kind = Banner.Kind.ALERT if mine else Banner.Kind.DANGER
	# Acerto e água soam diferente porque essa **é** a única informação de um tiro,
	# e ela chega antes de o texto ser lido.
	Sound.play(Sound.Cue.CAPTURE if hit else Sound.Cue.TAP)
	_banner.show_message("%s %s" % ["Você:" if mine else "Oponente:", note], kind)


func _my_turn() -> bool:
	return _state.side_to_move == Game.local_side


# --- rede --------------------------------------------------------------------


## Todo lance recebido é revalidado contra a própria geração de lances. O índice
## torna a mensagem idempotente: uma reconexão que reentregue um tiro já aplicado
## é descartada em vez de gastar a vez de novo.
func _on_remote_move(data: Dictionary) -> void:
	if _phase == Phase.OVER:
		return
	var index := int(data.get("n", -1))
	if index >= 0 and index < _state.ply:
		# Tiro que já temos: uma reconexão reenvia o que estava em voo.
		return
	if index > _state.ply:
		# Falta tiro no meio. Pedir o histórico é mais barato que adivinhar —
		# descartar em silêncio, que era o que acontecia aqui, deixa os dois mares
		# permanentemente diferentes sem ninguém perceber.
		Net.send_sync(_state.history)
		return
	# Quem mandou tem de ser quem tinha a vez: sem isto o oponente pode atirar
	# **pelo nosso lado**, que é um tiro legal olhando só o tabuleiro.
	var sender := int(data.get("seat", -1))
	if sender != (0 if _state.side_to_move == Net.HOST_SIDE else 1):
		push_warning("Tiro do assento %d recusado: não é a vez dele." % sender)
		return
	var incoming := Move.from_dict(data)
	for move in _rules.generate_moves(_state):
		if move.same_as(incoming):
			_play(move, false)
			return


func _on_link_lost() -> void:
	_disconnected = true
	_banner.show_message("Sem conexão. Tentando voltar…", Banner.Kind.DANGER, true)
	_refresh()


## A frota volta junto com a lista de lances: ela não é um lance, então o replay
## do `sync` sozinho reconstruiria uma partida sem navios.
func _on_link_restored() -> void:
	_disconnected = false
	_banner.hide_message()
	if _confirmed:
		Net.send_fleet(_draft)
	Net.send_sync(_state.history)
	_refresh()


func _on_sync(moves: Array, _clocks: Array) -> void:
	if moves.size() <= _state.ply:
		return
	if not BattleshipRules.ready(_state):
		return
	var rebuilt := _rules.initial_state()
	BattleshipRules.set_fleet(rebuilt, Game.local_side, _draft)
	BattleshipRules.set_fleet(rebuilt, Board.opponent(Game.local_side), _enemy_fleet)
	for entry in moves:
		var incoming := Move.from_dict(entry)
		var found: Move = null
		for move in _rules.generate_moves(rebuilt):
			if move.same_as(incoming):
				found = move
				break
		if found == null:
			_banner.show_message("Partidas fora de sincronia.", Banner.Kind.DANGER, true)
			return
		_rules.apply_move(rebuilt, found)
	_state = rebuilt
	_aim = Board.NO_SQUARE
	_refresh()


func _on_opponent_left() -> void:
	if _phase == Phase.OVER:
		return
	_abandoned = true
	_phase = Phase.OVER
	_show_result("O oponente saiu", "A partida acabou aqui.", false)


## Um só tratador, que decide pelo estado. A primeira versão trocava o tratador
## com `disconnect`/`connect` conforme o convite chegasse ou saísse, e isso quebra
## de duas formas: um segundo convite do oponente tenta desconectar o que já não
## está conectado (erro em tempo de execução), e depois de uma revanche aceita o
## botão fica preso no tratador de "aceitar" para a partida seguinte.
func _on_rematch_button() -> void:
	if _rematch_incoming:
		Net.send_rematch_accept()
		_start_rematch()
		return
	if _rematch_offered:
		return
	_rematch_offered = true
	Net.send_rematch()
	_refresh_rematch()


## Aceitar é um toque; o convite chega como oferta e não como ordem.
func _on_rematch_requested() -> void:
	_rematch_incoming = true
	_refresh_rematch()


## Recusar também é um toque.
##
## Esta tela tratava `rematch_declined` e não tinha como **enviar** um — e como o
## outro lado também é batalha naval, aquele tratador era inalcançável. Na
## prática, quem não queria revanche aqui não tinha botão: aceitava ou saía, e
## quem convidou ficava esperando uma resposta que não vinha. O xadrez e as damas
## têm o botão desde sempre.
func _decline_rematch() -> void:
	if not _rematch_incoming:
		return
	_rematch_incoming = false
	_rematch_refused = true
	Net.send_rematch_decline()
	_refresh_rematch()


func _on_rematch_declined() -> void:
	_rematch_incoming = false
	_rematch_offered = false
	_rematch_refused = true
	_refresh_rematch()


func _refresh_rematch() -> void:
	# "Recusar" só existe com um convite na mesa. Fora disso não há o que recusar,
	# e um botão que não faz nada ensina a ignorar a fileira inteira.
	%RematchDeclineButton.visible = _rematch_incoming
	var button: Button = %RematchButton
	if _rematch_incoming:
		button.disabled = false
		button.text = "Aceitar revanche"
	elif _rematch_refused:
		button.disabled = true
		button.text = "Revanche recusada"
	elif _rematch_offered:
		button.disabled = true
		button.text = "Convite enviado…"
	else:
		button.disabled = false
		button.text = "Revanche"


## Volta ao posicionamento, e não a um tabuleiro pronto: numa revanche a graça é
## justamente esconder a frota num lugar diferente.
func _start_rematch() -> void:
	Game.restart_match()
	_match_status.started_at = Game.match_started_at
	_state = _rules.initial_state()
	_draft = BattleshipRules.empty_grid()
	_enemy_fleet = PackedInt32Array()
	_next_ship = 0
	_confirmed = false
	_rematch_offered = false
	_rematch_incoming = false
	_rematch_refused = false
	_outcome = Ruleset.Outcome.ONGOING
	_abandoned = false
	_aim = Board.NO_SQUARE
	_phase = Phase.PLACING
	%OverlayLayer.visible = false
	_banner.hide_message()
	# O rótulo do botão não sai do `_refresh()` geral: ele responde ao estado da
	# negociação, não ao da partida, e sem esta linha a revanche seguinte abria
	# com "Aceitar revanche" escrito antes de existir convite nenhum.
	_refresh_rematch()
	_refresh()


# --- tela --------------------------------------------------------------------


func _refresh() -> void:
	if _match_status != null:
		_match_status.rounds = _rules.rounds_played(_state)
	var placing := _phase == Phase.PLACING or _phase == Phase.WAITING
	%PlaceLayer.visible = placing
	if placing:
		_refresh_placing()
	else:
		_refresh_firing()
	_refresh_cards()


func _refresh_placing() -> void:
	_place.fleet = _draft
	_place.shots = BattleshipRules.empty_grid()

	var waiting := _phase == Phase.WAITING
	%RotateButton.disabled = waiting
	%ShuffleButton.disabled = waiting
	%ClearButton.disabled = waiting
	%ConfirmButton.visible = not waiting
	%ConfirmButton.disabled = not _fleet_complete()
	%RotateButton.text = "Deitado" if _horizontal else "Em pé"

	if waiting:
		%FleetLabel.text = "Frota confirmada"
		%PlaceHint.text = "Esperando o oponente posicionar a frota dele."
		return

	if _fleet_complete():
		%FleetLabel.text = "Frota completa"
		%PlaceHint.text = "Confirme para começar. Depois disso ela não muda mais."
		return

	var ship: Dictionary = BattleshipRules.SHIPS[_next_ship]
	%FleetLabel.text = "%s — %d casas" % [ship["name"], int(ship["size"])]
	%PlaceHint.text = "Toque na casa onde ele começa. Faltam %d navios." % (
		BattleshipRules.SHIPS.size() - _next_ship
	)


func _refresh_firing() -> void:
	var me := Game.local_side
	var them := Board.opponent(me)
	_enemy.fleet = BattleshipRules.fleet_of(_state, them)
	_enemy.shots = BattleshipRules.shots_of(_state, me)
	_enemy.aim = _aim
	_own.fleet = BattleshipRules.fleet_of(_state, me)
	_own.shots = BattleshipRules.shots_of(_state, them)

	if _phase == Phase.OVER:
		return
	_outcome = _rules.outcome(_state)
	if _outcome != Ruleset.Outcome.ONGOING:
		_phase = Phase.OVER
		var won := (_outcome == Ruleset.Outcome.WHITE_WINS) == (me == Board.Side.WHITE)
		_show_result(
			"Você venceu" if won else "Você perdeu",
			_rules.outcome_text(_outcome),
			Game.mode == Game.Mode.ONLINE
		)


func _refresh_cards() -> void:
	var me := Game.local_side
	var them := Board.opponent(me)
	var over := _phase == Phase.OVER
	var playing := _phase == Phase.FIRING and not _disconnected
	for card in [[%TopCard, them], [%BottomCard, me]]:
		var view: PlayerCard = card[0]
		var side: int = card[1]
		view.side = side
		# O nome dos ajustes de cada lado: o local sai do `Prefs`, o do outro veio
		# no aperto de mão. "Oponente" continua sendo a resposta enquanto ele não
		# se apresentou — é melhor dizer que não se sabe do que inventar um nome.
		var theirs := Net.name_of(0 if them == Net.HOST_SIDE else 1)
		view.title = (
			Prefs.player_name() if side == me
			else (theirs if not theirs.is_empty() else "Oponente")
		)
		view.active = playing and not over and _state.side_to_move == side
		view.subtitle = _fleet_status(side)


## Quantos navios daquele lado ainda flutuam. É informação pública — afundar é
## anunciado pelas regras — e é o placar da partida inteira num número.
func _fleet_status(side: int) -> String:
	if not BattleshipRules.ready(_state):
		return ""
	var afloat := BattleshipRules.ships_afloat(_state, side)
	return "1 navio" if afloat == 1 else "%d navios" % afloat


func _show_result(title: String, detail: String, allow_rematch: bool) -> void:
	%ResultTitle.text = title
	%ResultDetail.text = detail
	%RematchButton.visible = allow_rematch and not _abandoned
	_refresh_rematch()
	%OverlayLayer.visible = true


func go_back() -> void:
	_exit()


func _exit() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
