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
## Quem arremessa roda a física e, enquanto a bola rola, manda a pose da bola e
## dos pinos 15 vezes por segundo (`Net.send_frame`). Os outros aparelhos não
## rodam física: a pista deles segue esses quadros, com uns 0,2 s de folga, e
## termina com os mesmos pinos no chão. Repetir o arremesso na física daqui, como
## na 1.50, mostrava outra jogada (a Jolt não dá o mesmo resultado bit a bit em
## dois aparelhos) e chegava uma jogada inteira atrasado.
##
## Quando a bola para, sai o lance (máscara e parâmetros), e é ele que vale na
## cartela. Ele só entra depois de a pista daqui mostrar o último quadro. Sem
## quadros (quem jogou numa versão antiga), a pista repete o arremesso na física
## daqui, como antes. A máquina de pinos arma o que o estado manda, então a
## próxima bola começa igual em todo lado.
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
## Passos de física entre dois quadros mandados aos outros aparelhos: a 60 Hz,
## 15 quadros por segundo. O relay aceita 40 mensagens por segundo de cada um.
const FRAME_EVERY := 4
## Teto de quadros guardados por lance: a jogada mais longa (12 s) tem 181.
const MAX_FRAMES := 400
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
## Passos de física da jogada que este aparelho transmite (`_physics_process`);
## -1 quando ele não transmite nada.
var _step := -1
## Quadros recebidos, por lance: `n -> [[passo, poses, assento], ...]`. Esperam
## aqui até a pista estar livre para mostrá-los.
var _frames := {}
## O lance cuja jogada a pista mostra pelos quadros (-1 sem nenhum), e de qual
## assento eles vêm.
var _shown := -1
var _shown_from := -1
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
		Net.frame_received.connect(_on_remote_frame)
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

	# Na barra, e não sobre a pista: no alto da pista ficam os pinos.
	_banner = _bar.notice

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
	_start_streaming()
	Sound.play(Sound.Cue.MOVE)
	_refresh()


## Em rede, quem roda a física manda a jogada em quadros enquanto ela acontece.
func _start_streaming() -> void:
	if Game.mode == Game.Mode.ONLINE:
		_step = 0
		Net.send_frame(_state.ply, _step, _view.lane.snapshot())


func _physics_process(_delta: float) -> void:
	if _step < 0 or not _view.lane.rolling:
		return
	_step += 1
	if _step % FRAME_EVERY == 0:
		Net.send_frame(_state.ply, _step, _view.lane.snapshot())


## A física parou. Quem arremessou transforma o que caiu em lance — e o lance
## passa pela mesma porta de um lance de rede: `validate`.
func _on_settled(mask: int) -> void:
	if _pending.is_empty():
		return
	if _step >= 0:
		# O último quadro é a pose exata de onde saiu a máscara: a pista dos outros
		# termina igual à daqui.
		Net.send_frame(_state.ply, _step + 1, _view.lane.snapshot())
		_step = -1
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
	_shown = -1
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
	_start_streaming()


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


## Um quadro da jogada de outro aparelho. O do lance da vez, de quem tem a vez,
## vai direto para a pista; os de um lance adiante (a pista daqui ainda mostra o
## anterior) esperam guardados.
func _on_remote_frame(data: Dictionary) -> void:
	var index := int(data.get("n", -1))
	var poses: PackedInt32Array = data.get("x", PackedInt32Array())
	if (
		_abandoned or index < _state.ply or index > _state.ply + 2
		or poses.size() != BowlingLane.BODIES * BowlingLane.POSE_INTS
	):
		return
	var seat := int(data.get("seat", -1))
	if index == _state.ply and seat != _sender_for(BowlingRules.turn_of(_state)):
		return
	var list: Array = _frames.get_or_add(index, [])
	if list.size() < MAX_FRAMES:
		list.append([int(data.get("k", 0)), poses, seat])
	_show_frames()


## A pista livre começa a mostrar os quadros do lance da vez, e a que já mostra
## recebe os novos.
func _show_frames() -> void:
	if _abandoned or (_busy and _shown != _state.ply):
		return
	var list: Array = _frames.get(_state.ply, [])
	var sender := _sender_for(BowlingRules.turn_of(_state))
	if _shown != _state.ply:
		# Guardados antes de se saber de quem era a vez: os de outro assento saem.
		list = list.filter(func(frame: Array) -> bool: return frame[2] == sender)
		if list.is_empty():
			return
		_busy = true
		_shown = _state.ply
		_shown_from = sender
		_view.enabled = false
		_dress_ball(BowlingRules.turn_of(_state))
	for frame: Array in list:
		_view.follow(frame[0], frame[1])
	_frames[_state.ply] = []


## A jogada que a pista mostrava pelos quadros não vai acabar (quem jogava saiu):
## a pista volta ao que o estado manda, e a vez segue como se ela não existisse.
func _drop_shown() -> void:
	if _shown < 0:
		return
	_frames.erase(_shown)
	_shown = -1
	_busy = false
	_view.rack(BowlingRules.standing(_state))


## Os lances de fora, um por vez, e só depois da jogada na pista: a mostrada
## pelos quadros, até o último; sem quadros, repetida na física daqui.
func _drain_incoming() -> void:
	if _draining or _abandoned or _incoming.is_empty():
		return
	_show_frames()
	if _busy and _shown != _state.ply:
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
		if _shown == index:
			while not _view.lane.caught_up() and is_inside_tree() and not _abandoned and _shown == index:
				await get_tree().process_frame
		else:
			_busy = true
			_view.enabled = false
			_dress_ball(turn)
			_view.throw(BowlingRules.params_of(move))
			await _view.settled
		# Um histórico pode ter chegado no meio da jogada e refeito a partida.
		if not is_inside_tree() or _abandoned or _state.ply != index:
			break
		_frames.erase(index)
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
	_step = -1
	_frames.clear()
	_shown = -1
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
	# Saiu no meio do arremesso que a pista mostra: o lance dele não vem mais, e
	# a vez é jogada de novo (pela máquina, ou por quem dirige as máquinas agora).
	if _shown == _state.ply and _shown_from == seat:
		_drop_shown()
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
	_dress_ball(turn)
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

	# Jogadas e arremessos de fora que chegaram com a pista ocupada esperam a vez
	# deles.
	_show_frames()
	_drain_incoming()
	if (
		_is_bot(turn) and _drives_bots() and not _bot_pending and not _busy
		and not _link_down and not _abandoned and not BowlingRules.game_over(_state)
	):
		_run_bot()


func _seat_color(seat: int) -> Color:
	return SEAT_COLORS[seat % SEAT_COLORS.size()]


## A bola de quem joga: a textura da loja do assento, ou o mármore na cor dele.
func _dress_ball(seat: int) -> void:
	_view.ball_skin = Cosmetics.ball_texture(seat_look(seat))
	_view.ball_color = _seat_color(seat)


## O visual (`Cosmetics`) de um assento. Online, o que cada aparelho disse no
## aperto de mão; aqui, o do dono do aparelho no assento 0 (no mesmo aparelho ele
## é o dono, contra o bot é quem joga). Máquinas e convidados ficam no padrão.
func seat_look(seat: int) -> Dictionary:
	if Game.mode == Game.Mode.ONLINE:
		return Net.look_of(seat)
	return Account.look if seat == 0 else {}


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
	var stats := [
		[ResultHeader.duration_since(Game.match_started_at), "duração"],
		[str(best), "pontos"],
	]
	_result_header.celebrate(mood, stats)
	Game.record_result(mood, stats)


func _restart() -> void:
	Game.restart_match()
	_state = _rules.initial_state()
	_busy = false
	_bot_pending = false
	_pending = PackedFloat32Array()
	_step = -1
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


## Onde a reação do chat de `seat` aparece (ver `ChatButton`): o nome dele na
## cartela. A cartela é desenhada, e não feita de nós, então a linha sai da conta
## do próprio `BowlingCard`.
func chat_spot(seat: int) -> Rect2:
	if _card == null or not _card.is_visible_in_tree() or seat < 0:
		return Rect2()
	var top := _card.get_global_rect().position + Vector2(0.0, seat * (BowlingCard.ROW + BowlingCard.GAP))
	return Rect2(top, Vector2(BowlingCard.NAME_WIDTH, BowlingCard.ROW))
