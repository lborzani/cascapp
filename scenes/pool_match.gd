extends Control

## Uma partida de sinuca: a mesa, a mira, e a tacada acontecendo.
##
## É a tela mais simples do app depois do menu, e é de propósito. Em sinuca a
## interface inteira é **um gesto** — puxar o taco — e tudo o que não é a mesa
## rouba espaço de onde se mira. Então não há barra de ações: o que muda de uma
## vez para a outra é o texto de uma linha e de quem é a faixa acesa.
##
## ## O que viaja é a tacada, não a mesa
##
## Como em todos os outros jogos, o que sai pela rede é o `Move` — aqui, a
## velocidade inicial da branca em dois inteiros. Os dois aparelhos rodam a mesma
## simulação de [PoolRules] e chegam à mesma mesa, e repetir o histórico
## reconstrói a partida. Mandar as posições finais seria mais curto e pediria
## confiar no resultado que o outro lado calculou, que é uma porta que este app
## não abre em jogo nenhum.
##
## ## A tacada é assistida antes de ser resolvida
##
## `apply_move` já devolve a mesa parada, mas a tela reproduz os retratos que a
## própria simulação gravou antes de contar o que aconteceu. Uma bola que entra
## sem ser vista entrando é um ponto que aparece do nada no placar.

const MENU_SCENE := "res://scenes/game_menu.tscn"
## Respiro depois de a mesa parar, antes de a vez seguinte começar.
const AFTER_SHOT := 0.35
## Quanto o bot "pensa" antes de tacar. Ele não pensa — escolhe entre candidatos
## simulados —, mas sem a pausa a vez dele acontece entre dois quadros.
const BOT_THINK := 0.7
## Largura da coluna dos jogadores, na base deitada de 768.
const COLUMN := 150.0

var _rules := PoolRules.new()
var _state: MatchState = null
var _busy := false
var _bot_pending := false
var _abandoned := false
var _link_down := false
## Assentos jogados por máquina. No solo, o 1.
var _bot_seats := PackedInt32Array()

var _view: PoolView = null
var _banner: Banner = null
var _hint: Label = null
var _cards: Array[PanelContainer] = []
var _overlay: Control = null
var _overlay_title: Label = null
var _again: Button = null


func _ready() -> void:
	theme = AppTheme.shared()
	# Deitada como Ludo, Uno, Metrópole e Bomberman, e aqui pelo motivo mais
	# literal de todos: a mesa é duas vezes mais larga que alta. Em retrato ela
	# ocuparia um terço da tela com faixa preta em cima e embaixo.
	Orientation.to_landscape(get_tree())
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	_adopt_rules()
	_state = _rules.initial_state()
	_build()

	Game.begin_match()
	if Game.mode == Game.Mode.SOLO:
		Game.local_seat = 0
		_bot_seats = PackedInt32Array([1])
	if Game.mode == Game.Mode.ONLINE:
		Game.local_seat = Net.local_seat
		_bot_seats = Net.bot_seats
		Net.move_received.connect(_on_remote_move)
		Net.opponent_left.connect(_on_opponent_left)
		Net.link_lost.connect(_on_link_lost)
		Net.link_restored.connect(_on_link_restored)
		Net.sync_received.connect(_apply_sync)
		Net.names_changed.connect(_refresh)
		Net.bots_changed.connect(func() -> void: _bot_seats = Net.bot_seats)

	_refresh()
	Net.claim_sync()


func _exit_tree() -> void:
	Orientation.reset(get_tree())


## O formato vem do menu e, em rede, do `welcome` — um número por jogo, como o
## limite de rodadas de Metrópole e a regra da casa do Uno. Duas mesas com
## formatos diferentes não seriam a mesma partida, e o erro só apareceria na
## primeira bola encaçapada.
func _adopt_rules() -> void:
	_rules.format = Game.pool_format
	if Game.mode == Game.Mode.ONLINE and Net.option >= 0:
		_rules.format = Net.option
		Game.pool_format = _rules.format
	# A fita dos retratos só existe aqui: é a tela que assiste à tacada.
	_rules.trace_every = PoolRules.TRACE_EVERY


# --- montagem -----------------------------------------------------------------


func _build() -> void:
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = AppTheme.BACKGROUND
	add_child(background)

	var safe := SafeAreaMargin.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 12)
	add_child(safe)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	safe.add_child(row)

	var column := VBoxContainer.new()
	column.custom_minimum_size.x = COLUMN
	column.add_theme_constant_override("separation", AppTheme.SPACE_S)
	row.add_child(column)

	var status := MatchStatus.create()
	column.add_child(status)
	for seat in 2:
		var card := _build_card(seat)
		_cards.append(card)
		column.add_child(card)

	_hint = Label.new()
	_hint.theme_type_variation = &"Caption"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_hint)

	var leave := LeaveButton.new()
	leave.confirmed.connect(_leave)
	column.add_child(leave)

	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(stage)

	_view = PoolView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.state = _state
	_view.shot_aimed.connect(_on_shot_aimed)
	_view.ball_placed.connect(_on_ball_placed)
	stage.add_child(_view)

	_banner = Banner.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_bottom = 110.0
	stage.add_child(_banner)

	_build_overlay()


func _build_card(seat: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.y = 62
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	margin.add_child(lines)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.add_theme_font_size_override("font_size", 14)
	lines.add_child(name_label)

	var detail := Label.new()
	detail.name = "Detail"
	detail.theme_type_variation = &"Caption"
	lines.add_child(detail)
	return card


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(AppTheme.BACKGROUND, 0.82)
	_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(320, 0)
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_M)
	margin.add_child(column)

	_overlay_title = Label.new()
	_overlay_title.theme_type_variation = &"Title"
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_overlay_title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", AppTheme.SPACE_S)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)

	var out := Button.new()
	out.text = "Sair"
	out.pressed.connect(_leave)
	buttons.add_child(out)

	_again = Button.new()
	_again.text = "Jogar de novo"
	_again.theme_type_variation = &"PrimaryButton"
	_again.pressed.connect(_restart)
	# Revanche é conversa de dois no mesmo aparelho. Em rede, quem quer jogar de
	# novo abre outra sala — mesma decisão do Ludo e de Metrópole.
	_again.visible = Game.mode != Game.Mode.ONLINE
	buttons.add_child(_again)


# --- a vez --------------------------------------------------------------------


func _my_turn() -> bool:
	if Game.mode == Game.Mode.HOTSEAT:
		return true
	return PoolRules.turn_of(_state) == Game.local_seat


func _can_act() -> bool:
	return (
		_my_turn() and not _busy and not _link_down and not _abandoned
		and PoolRules.winner_of(_state) < 0
		and not _is_bot(PoolRules.turn_of(_state))
	)


func _is_bot(seat: int) -> bool:
	return _bot_seats.has(seat)


## Quem dirige as máquinas: no solo este aparelho, em rede o assento 0 — a mesma
## regra do Ludo, e pelo mesmo motivo. Dois aparelhos tacando pelo mesmo bot
## dariam duas tacadas para a mesma vez.
func _drives_bots() -> bool:
	return Game.mode != Game.Mode.ONLINE or Game.local_seat == 0


func _on_shot_aimed(direction: Vector2, power: float) -> void:
	if not _can_act():
		return
	_submit(PoolRules.shot(direction, power))


func _on_ball_placed(spot: Vector2) -> void:
	if not _can_act():
		return
	_submit(PoolRules.placement(spot))


## Todo lance local passa por aqui, e passa pela **mesma porta** que um lance de
## rede: `validate`. Um lance montado pela tela não é mais confiável que um que
## chegou pelo fio — ele só foi montado mais perto.
func _submit(move: Move) -> void:
	var checked := _rules.validate(_state, move.path)
	if checked == null:
		return
	if Game.mode == Game.Mode.ONLINE:
		Net.send_move({"p": checked.path, "pr": 0}, _state.ply)
	_play(checked)


func _play(move: Move) -> void:
	_busy = true
	_view.enabled = false
	var seat := PoolRules.turn_of(_state)
	var before := PoolRules.score_of(_state, seat)
	var kind := PoolRules.kind_of(move)

	_rules.apply_move(_state, move)
	if kind == PoolRules.SHOOT:
		Sound.play(Sound.Cue.MOVE)
		_view.play(_rules.trace_spots, _rules.trace_live)
		await get_tree().create_timer(_view.remaining_animation()).timeout
	else:
		Sound.play(Sound.Cue.TAP)
	if not is_inside_tree():
		return

	_view.state = _state
	_announce(seat, before)
	await get_tree().create_timer(AFTER_SHOT).timeout
	if not is_inside_tree():
		return

	_busy = false
	var champion := PoolRules.winner_of(_state)
	if champion != -1:
		_finish(champion)
		return
	_refresh()


## O que a tacada causou, e só quando ele não está à vista.
##
## Uma bola que entra é vista entrando; a falta não é vista nunca — a mesa
## simplesmente para e a vez troca. Sem o aviso, quem levou a falta descobre pelo
## placar, e quem a cometeu não descobre.
func _announce(seat: int, before: int) -> void:
	if PoolRules.ball_in_hand(_state):
		_banner.show_message(
			"Falta de %s. A branca fica na mão." % _seat_name(seat), Banner.Kind.ALERT
		)
		return
	var gained := PoolRules.score_of(_state, seat) - before
	if gained > 0:
		_banner.show_message("%s fez %d." % [_seat_name(seat), gained], Banner.Kind.INFO)


# --- bot ----------------------------------------------------------------------


func _run_bot() -> void:
	_bot_pending = true
	await get_tree().create_timer(BOT_THINK).timeout
	if not is_inside_tree() or _busy:
		_bot_pending = false
		return
	var seat := PoolRules.turn_of(_state)
	if not _is_bot(seat) or not _drives_bots() or PoolRules.winner_of(_state) >= 0:
		_bot_pending = false
		return
	var choice := _rules.best_move(_state, _rules.generate_moves(_state))
	_bot_pending = false
	if choice == null:
		return
	if Game.mode == Game.Mode.ONLINE:
		Net.send_move({"p": choice.path, "pr": 0}, _state.ply)
	_play(choice)


# --- rede ---------------------------------------------------------------------


func _on_remote_move(data: Dictionary) -> void:
	if _abandoned:
		return
	var index := int(data.get("n", -1))
	if index >= 0 and index < _state.ply:
		return
	if index > _state.ply:
		Net.send_sync(_state.history, [])
		return
	# Quem mandou tem de ser quem tinha a vez. A legalidade responde "esta tacada
	# existe", não "esta tacada é sua".
	var sender := int(data.get("seat", -1))
	var allowed := PoolRules.turn_of(_state)
	if sender != allowed:
		push_warning("Tacada do assento %d recusada: a vez é do %d." % [sender, allowed])
		return
	var move := _rules.validate(_state, PackedInt32Array(data.get("p", [])))
	if move == null:
		_banner.show_message("Tacada inválida recebida", Banner.Kind.DANGER)
		return
	_play(move)


func _apply_sync(moves: Array, _clocks: Array) -> void:
	var rebuilt := _rules.initial_state()
	for entry in moves:
		var path := PackedInt32Array((entry as Dictionary).get("p", []))
		var move := _rules.validate(rebuilt, path)
		if move == null:
			_banner.show_message("Histórico recusado: a mesa não bate.", Banner.Kind.DANGER)
			return
		_rules.apply_move(rebuilt, move)
	_state = rebuilt
	_view.state = _state
	_busy = false
	_refresh()


func _on_link_lost() -> void:
	_link_down = true
	_refresh()


func _on_link_restored() -> void:
	_link_down = false
	_refresh()


func _on_opponent_left() -> void:
	_abandoned = true
	_view.enabled = false
	_banner.show_message("O outro jogador saiu.", Banner.Kind.ALERT)


# --- tela ---------------------------------------------------------------------


func _refresh() -> void:
	_view.state = _state
	_view.enabled = _can_act()
	_hint.text = _rules.status_hint(_state)
	_refresh_cards()

	if (
		_is_bot(PoolRules.turn_of(_state)) and _drives_bots() and not _bot_pending
		and not _busy and not _link_down and not _abandoned
		and PoolRules.winner_of(_state) < 0
	):
		_run_bot()


func _refresh_cards() -> void:
	var turn := PoolRules.turn_of(_state)
	for seat in _cards.size():
		var card := _cards[seat]
		var tint := _seat_color(seat)
		card.add_theme_stylebox_override("panel", AppTheme.box(
			Color(tint, 0.20) if seat == turn else AppTheme.SURFACE,
			AppTheme.RADIUS,
			tint if seat == turn else AppTheme.BORDER,
			2 if seat == turn else 1
		))
		var name_label: Label = card.find_child("Name", true, false)
		var detail: Label = card.find_child("Detail", true, false)
		name_label.text = _seat_name(seat)
		detail.text = _seat_detail(seat)


## A cor do assento: no mata-mata é a do grupo dele — e essa **é** a informação
## principal da tela, porque ela diz em que bola se pode bater. Enquanto a mesa
## está aberta, ninguém tem cor, e a faixa usa o latão de "é a sua vez".
func _seat_color(seat: int) -> Color:
	if PoolRules.format_of(_state) == PoolRules.Format.BRAZILIAN:
		return AppTheme.ACCENT
	var group := PoolRules.group_of(_state, seat)
	if group < 0:
		return AppTheme.ACCENT
	return PoolRules.GROUP_COLORS[group]


func _seat_detail(seat: int) -> String:
	if PoolRules.format_of(_state) == PoolRules.Format.BRAZILIAN:
		return "%d pontos" % PoolRules.score_of(_state, seat)
	var group := PoolRules.group_of(_state, seat)
	if group < 0:
		return "mesa aberta"
	var left := 0
	for ball in range(1, PoolRules.ball_count(_state)):
		if PoolRules.is_live(_state, ball) and PoolRules.kind_of_ball(_state, ball) == group:
			left += 1
	return "%d na mesa" % left


func _seat_name(seat: int) -> String:
	if Game.mode == Game.Mode.ONLINE:
		return Net.name_of(seat)
	if Game.mode == Game.Mode.SOLO:
		return Prefs.player_name() if seat == 0 else "Máquina"
	return "Jogador %d" % (seat + 1)


func _finish(champion: int) -> void:
	Sound.play(Sound.Cue.WIN)
	_view.enabled = false
	if champion == -2:
		_overlay_title.text = "Empate"
	else:
		_overlay_title.text = "%s venceu" % _seat_name(champion)
	_overlay.visible = true


func _restart() -> void:
	Game.restart_match()
	_state = _rules.initial_state()
	_busy = false
	_bot_pending = false
	_view.play([], [])
	_overlay.visible = false
	_refresh()


func go_back() -> void:
	_leave()


func _leave() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
