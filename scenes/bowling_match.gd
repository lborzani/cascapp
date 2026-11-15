extends Control

## Uma partida de boliche, em retrato: a cartela em cima e a pista embaixo.
##
## O lance é o que caiu: quem arremessa roda a física ([BowlingView], [BowlingLane])
## e a máscara dos pinos derrubados vira o `Move`, junto com os parâmetros do
## arremesso. As regras ([BowlingRules]) só contam. Ver o cabeçalho de
## `core/bowling_rules.gd` para o porquê.
##
## Solo é a mesa com um humano só: você é o assento 0 e as outras cadeiras são
## máquina, como em Metrópole. No mesmo aparelho, de 2 a 4 se revezam por frame.
##
## ## Em rede
##
## Quem arremessa roda a física e manda o lance (máscara e parâmetros) antes de
## aplicá-lo, como os outros jogos. Os outros aparelhos repetem o arremesso na
## própria pista para ver a jogada, e no fim **vale a máscara recebida**, não a
## que a física daqui deu: a Jolt não dá o mesmo resultado bit a bit em dois
## aparelhos. A máquina de pinos arma o que o estado manda, então a próxima bola
## começa igual em todo lado, mesmo que a repetição tenha divergido.
##
## Os lances de fora entram numa fila, um por vez, porque cada um leva o tempo da
## jogada inteira. Reconexão e entrada no meio refazem a cartela pelo histórico,
## sem física. Cadeira vazia é máquina, e só um aparelho (`Net.bot_driver`) joga
## por ela.

const MENU_SCENE := "res://scenes/main_menu.tscn"
## O tempo de ler "Strike!" com os pinos ainda caídos, antes de a máquina limpar.
const AFTER_THROW := 1.4
## Quanto o bot "pensa" antes de arremessar.
const BOT_THINK := 0.9
## Erro do bot no timing: desvio padrão, na escala de -1 a 1.
const BOT_TIMING_SPREAD := 0.35
## Uma cor de bola por cadeira.
const SEAT_COLORS: Array[Color] = [
	Color("4b7fb5"), Color("d98b3a"), Color("5f9e63"), Color("c9524d"),
]

var _rules := BowlingRules.new()
var _state: MatchState = null
var _busy := false
var _bot_pending := false
## Parâmetros do arremesso em curso, até a física dizer o que caiu.
var _pending := PackedFloat32Array()
var _bot_seats := PackedInt32Array()
var _link_down := false
var _abandoned := false
## Lances de outros aparelhos esperando a vez de serem repetidos na pista.
var _incoming: Array[Dictionary] = []
var _draining := false
var _again: Button = null

var _view: BowlingView = null
var _card: BowlingCard = null
var _banner: Banner = null
var _hint: Label = null
var _bar: MatchBar = null
var _overlay: Control = null
var _overlay_title: Label = null
var _result_header: ResultHeader = null


func _ready() -> void:
	theme = AppTheme.shared()
	var online := Game.mode == Game.Mode.ONLINE
	# Em rede, o tamanho da mesa é o da sala, que veio de quem a abriu.
	_rules.seats = maxi(2, Net.seats) if online else Game.players_of(Game.BOWLING)
	_state = _rules.initial_state()
	_build()

	Game.begin_match()
	_bar.bind()
	_bar.status.counts_rounds = false
	Game.local_seat = 0
	if Game.mode == Game.Mode.SOLO:
		for seat in range(1, BowlingRules.seats_of(_state)):
			_bot_seats.append(seat)
	if online:
		Game.local_seat = Net.local_seat
		_bot_seats = Net.bot_seats
		Net.move_received.connect(_on_remote_move)
		Net.opponent_left.connect(_on_opponent_left)
		Net.seat_left.connect(_on_seat_left)
		Net.seat_returned.connect(_on_seat_returned)
		Net.link_lost.connect(_on_link_lost)
		Net.link_restored.connect(_on_link_restored)
		Net.sync_received.connect(_apply_sync)
		Net.names_changed.connect(_refresh)
		Net.bots_changed.connect(_adopt_bot_seats)
		# Revanche é de dois; numa mesa de até quatro quem quer jogar de novo abre
		# outra sala, como no Uno.
		_again.visible = false

	_view.rack(BowlingRules.ALL_PINS)
	_refresh()
	# Quem entrou numa partida em curso recebeu o histórico antes desta cena
	# existir, e ele ficou guardado esperando.
	Net.claim_sync()


# --- montagem -----------------------------------------------------------------


func _build() -> void:
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = AppTheme.BACKGROUND
	add_child(background)

	var safe := SafeAreaMargin.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(safe)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 0)
	safe.add_child(shell)

	_bar = MatchBar.new()
	_bar.leave_confirmed.connect(_leave)
	shell.add_child(_bar)

	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	shell.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_S)
	pad.add_child(column)

	_card = BowlingCard.new()
	_card.state = _state
	column.add_child(_card)

	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint.add_theme_font_override("font", AppTheme.font(800))
	_hint.add_theme_font_size_override("font_size", 13)
	column.add_child(_hint)

	# A pista vai até a borda de baixo, sem margem: ela é o jogo.
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(stage)

	_view = BowlingView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.released.connect(_on_released)
	_view.settled.connect(_on_settled)
	stage.add_child(_view)

	_banner = Banner.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_bottom = 110.0
	stage.add_child(_banner)

	_build_overlay()


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(AppTheme.BACKGROUND, 0.82)
	_overlay.add_child(dim)

	var panel := PaperCard.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(320, 0)
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_M)
	margin.add_child(column)

	_overlay_title = Label.new()
	_overlay_title.theme_type_variation = &"Display"
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_overlay_title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", AppTheme.SPACE_S)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)

	var out := Button.new()
	out.text = "Sair"
	out.theme_type_variation = &"GhostButton"
	out.pressed.connect(_leave)
	buttons.add_child(out)

	_again = Button.new()
	_again.text = "Jogar de novo"
	_again.theme_type_variation = &"PrimaryButton"
	_again.pressed.connect(_restart)
	buttons.add_child(_again)


# --- a vez --------------------------------------------------------------------


func _can_act() -> bool:
	var turn := BowlingRules.turn_of(_state)
	return (
		not _busy and not _link_down and not _abandoned
		and not BowlingRules.game_over(_state) and not _is_bot(turn)
		and (Game.mode != Game.Mode.ONLINE or turn == Game.local_seat)
	)


func _is_bot(seat: int) -> bool:
	return _bot_seats.has(seat)


## Este aparelho joga pelas máquinas: no solo sempre; em rede só o
## `Net.bot_driver`, para a mesma vez não ganhar dois arremessos.
func _drives_bots() -> bool:
	return Game.mode != Game.Mode.ONLINE or Net.drives_bots()


## Quem pode mandar o lance desta cadeira: ela mesma, ou quem dirige as máquinas.
func _sender_for(seat: int) -> int:
	return Net.bot_driver() if _is_bot(seat) else seat


func _on_released(params: PackedFloat32Array) -> void:
	if not _can_act():
		return
	_busy = true
	_pending = params
	_view.enabled = false
	Sound.play(Sound.Cue.MOVE)
	_refresh()


## A física parou. Quem arremessou transforma o que caiu em lance — e o lance
## passa pela mesma porta de um lance de rede: `validate`.
func _on_settled(mask: int) -> void:
	if _pending.is_empty():
		return
	var move := _rules.validate(_state, BowlingRules.roll(mask, _pending).path)
	_pending = PackedFloat32Array()
	if move == null:
		# Não acontece com a pista armada pelo estado; se acontecer, a vez não trava.
		move = BowlingRules.roll(0)
	_play(move)


func _play(move: Move, from_network := false) -> void:
	var seat := BowlingRules.turn_of(_state)
	var before := BowlingRules.standing(_state)
	# Sai antes de ser aplicado: `ply` é o índice dele, e é o que o torna
	# idempotente do outro lado numa reconexão.
	if not from_network and Game.mode == Game.Mode.ONLINE:
		Net.send_move({"p": move.path, "pr": 0}, _state.ply)
	_rules.apply_move(_state, move)
	_card.state = _state
	_announce(seat, before, BowlingRules.mask_of(move))
	await get_tree().create_timer(AFTER_THROW).timeout
	if not is_inside_tree():
		return
	_busy = false
	_view.rack(BowlingRules.standing(_state))
	if BowlingRules.game_over(_state):
		_finish(BowlingRules.winner_of(_state))
		return
	_refresh()


func _announce(seat: int, before: int, mask: int) -> void:
	var knocked := BowlingRules.pin_count(mask)
	var who := _seat_name(seat)
	if mask == before and before == BowlingRules.ALL_PINS:
		Sound.play(Sound.Cue.WIN)
		_banner.show_message("Strike! %s derrubou todos." % who, Banner.Kind.INFO)
	elif mask == before:
		_banner.show_message("Spare! %s limpou a pista." % who, Banner.Kind.INFO)
	elif knocked == 0:
		_banner.show_message("Nenhum pino.", Banner.Kind.ALERT)
	else:
		_banner.show_message("%d pino%s." % [knocked, "" if knocked == 1 else "s"], Banner.Kind.INFO)


# --- bot ----------------------------------------------------------------------


func _run_bot() -> void:
	_bot_pending = true
	await get_tree().create_timer(BOT_THINK).timeout
	_bot_pending = false
	if (
		not is_inside_tree() or _busy or _link_down or _abandoned or not _drives_bots()
		or not _is_bot(BowlingRules.turn_of(_state)) or BowlingRules.game_over(_state)
	):
		return
	_busy = true
	_pending = bot_params()
	_view.throw(_pending)


## O arremesso do bot: sai da direita com um gancho leve para a esquerda, mira
## no bolso (entre o 1 e o 3), joga forte e erra o timing como gente erra.
static func bot_params() -> PackedFloat32Array:
	var spot := randf_range(0.2, 0.45)
	var spin := randf_range(-0.5, -0.1)
	var start := spot * (BowlingLane.LANE_W * 0.5 - BowlingLane.BALL_R)
	var pocket := 0.07 - start - spin * BowlingView.HOOK_PREVIEW
	var direction := rad_to_deg(atan2(pocket, BowlingLane.HEAD_PIN)) / BowlingLane.MAX_ANGLE
	return PackedFloat32Array([
		spot, clampf(direction, -1.0, 1.0), spin,
		clampf(randfn(0.0, BOT_TIMING_SPREAD), -1.0, 1.0),
		randf_range(0.75, 1.0),
	])


# --- rede ---------------------------------------------------------------------


func _on_remote_move(data: Dictionary) -> void:
	if _abandoned:
		return
	_incoming.append({
		"n": int(data.get("n", -1)),
		"p": PackedInt32Array(data.get("p", [])),
		"seat": int(data.get("seat", -1)),
	})
	_drain_incoming()


## Repete os lances de fora, um por vez: cada um é a jogada inteira na pista, e
## só depois dela o lance entra na cartela.
func _drain_incoming() -> void:
	if _draining or _busy or _abandoned or _incoming.is_empty():
		return
	_draining = true
	while not _incoming.is_empty() and not _abandoned and is_inside_tree():
		var entry: Dictionary = _incoming.pop_front()
		var index := int(entry["n"])
		if index >= 0 and index < _state.ply:
			continue
		if index > _state.ply:
			# Falta lance no meio: pedir o histórico é mais barato que adivinhar.
			Net.send_sync(_state.history, [])
			break
		var turn := BowlingRules.turn_of(_state)
		if int(entry["seat"]) != _sender_for(turn):
			push_warning("Arremesso do assento %d recusado: a vez é de %d." % [entry["seat"], turn])
			continue
		var move := _rules.validate(_state, entry["p"])
		if move == null:
			push_warning("Arremesso de rede recusado pelas regras: %s" % [entry["p"]])
			continue
		_busy = true
		_view.enabled = false
		_view.ball_color = _seat_color(turn)
		_view.throw(BowlingRules.params_of(move))
		await _view.settled
		# Um histórico pode ter chegado no meio da jogada e refeito a partida.
		if not is_inside_tree() or _abandoned or _state.ply != index:
			break
		await _play(move, true)
	_draining = false


## Reconexão: refaz a partida pelo histórico, sem física, e arma o que ficou em pé.
func _apply_sync(moves: Array, _clocks: Array) -> void:
	if moves.size() <= _state.ply:
		return
	var rebuilt := _rules.initial_state()
	for data in moves:
		var checked := _rules.validate(rebuilt, Move.from_dict(data).path)
		if checked == null:
			push_warning("Histórico recebido não bate com as regras; ignorado.")
			return
		_rules.apply_move(rebuilt, checked)
	_state = rebuilt
	_busy = false
	_pending = PackedFloat32Array()
	_incoming.clear()
	_view.rack(BowlingRules.standing(_state))
	if BowlingRules.game_over(_state):
		_finish(BowlingRules.winner_of(_state))
		return
	_refresh()


func _on_link_lost() -> void:
	_link_down = true
	_refresh()


func _on_link_restored() -> void:
	_link_down = false
	Net.send_sync(_state.history, [])
	_refresh()


func _on_opponent_left() -> void:
	_abandoned = true
	_view.enabled = false
	_banner.show_message("O outro jogador saiu.", Banner.Kind.ALERT, true)
	_refresh()


## Numa mesa de mais de dois, quem sai vira máquina e a partida continua.
func _on_seat_left(seat: int) -> void:
	if _abandoned:
		return
	var who := _seat_name(seat)
	_bot_seats = Net.bot_seats
	_banner.show_message("%s saiu. Uma máquina joga até a volta." % who, Banner.Kind.ALERT)
	_refresh()


func _on_seat_returned(seat: int) -> void:
	if _abandoned:
		return
	_bot_seats = Net.bot_seats
	_banner.show_message("%s assumiu o lugar da máquina." % _seat_name(seat), Banner.Kind.INFO)
	_refresh()


func _adopt_bot_seats() -> void:
	_bot_seats = Net.bot_seats
	_refresh()


# --- tela ---------------------------------------------------------------------


func _refresh() -> void:
	var turn := BowlingRules.turn_of(_state)
	_view.ball_color = _seat_color(turn)
	_view.enabled = _can_act()
	var names := PackedStringArray()
	var colors: Array[Color] = []
	for seat in BowlingRules.seats_of(_state):
		names.append(_seat_name(seat))
		colors.append(_seat_color(seat))
	_card.names = names
	_card.colors = colors
	_card.state = _state

	var lit := _can_act()
	var text := _rules.status_hint(_state).trim_suffix(".")
	if not BowlingRules.game_over(_state):
		text = "%s · %s" % [_seat_name(turn), text]
	_hint.text = text
	var pill := AppTheme.box(AppTheme.ACCENT if lit else AppTheme.SURFACE_HIGH, 13)
	pill.content_margin_left = 14
	pill.content_margin_right = 14
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	_hint.add_theme_stylebox_override("normal", pill)
	_hint.add_theme_color_override("font_color", AppTheme.ACCENT_INK if lit else AppTheme.TEXT_DIM)

	# Arremessos de fora que chegaram com a pista ocupada esperam a vez deles.
	_drain_incoming()
	if (
		_is_bot(turn) and _drives_bots() and not _bot_pending and not _busy
		and not _link_down and not _abandoned and not BowlingRules.game_over(_state)
	):
		_run_bot()


func _seat_color(seat: int) -> Color:
	return SEAT_COLORS[seat % SEAT_COLORS.size()]


func _seat_name(seat: int) -> String:
	if Game.mode == Game.Mode.ONLINE:
		if _is_bot(seat):
			return "Máquina %d" % (seat + 1)
		var theirs := Net.name_of(seat)
		if not theirs.is_empty():
			return theirs
	if Game.mode == Game.Mode.SOLO:
		if seat == 0:
			return Prefs.player_name()
		return "Máquina" if BowlingRules.seats_of(_state) == 2 else "Máquina %d" % seat
	return "Jogador %d" % (seat + 1)


func _finish(champion: int) -> void:
	Sound.play(Sound.Cue.WIN)
	_view.enabled = false
	_refresh()
	if champion == -2:
		_overlay_title.text = "Empate"
	else:
		_overlay_title.text = "%s venceu" % _seat_name(champion)
	if _result_header == null:
		_result_header = ResultHeader.attach(_overlay_title, _overlay_title, _overlay)
	_overlay.visible = true
	var mood := ResultHeader.Mood.DRAW
	if champion != -2:
		var mine := Game.mode == Game.Mode.HOTSEAT or champion == Game.local_seat
		mood = ResultHeader.Mood.WIN if mine else ResultHeader.Mood.LOSS
	var best := BowlingRules.score_of(_state, maxi(champion, 0))
	_result_header.celebrate(mood, [
		[ResultHeader.duration_since(Game.match_started_at), "duração"],
		[str(best), "pontos"],
	])


func _restart() -> void:
	Game.restart_match()
	_state = _rules.initial_state()
	_busy = false
	_bot_pending = false
	_pending = PackedFloat32Array()
	_overlay.visible = false
	_view.rack(BowlingRules.ALL_PINS)
	_refresh()


func go_back() -> void:
	if _overlay.visible:
		_leave()
		return
	_bar.leave.ask()


func _leave() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
