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

const MENU_SCENE := "res://scenes/main_menu.tscn"
## Respiro depois de a mesa parar, antes de a vez seguinte começar.
const AFTER_SHOT := 0.35
## Quanto o bot "pensa" antes de tacar. Ele não pensa — escolhe entre candidatos
## simulados —, mas sem a pausa a vez dele acontece entre dois quadros.
const BOT_THINK := 0.7
## Largura da coluna dos jogadores, na base deitada de 768.
const COLUMN := 168.0

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
## As duas etiquetas da coluna, uma por assento, com a cor das bolas de cada um.
var _tags: Array[PlayerTag] = []
var _bar: MatchBar = null
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
	_bar.bind()
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
	add_child(safe)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 0)
	safe.add_child(shell)

	# A barra é montada aqui e ligada à partida depois de `begin_match()`: é ele
	# que decide se o relógio conta de agora ou da partida retomada.
	_bar = MatchBar.new()
	_bar.compact = true
	_bar.leave_confirmed.connect(_leave)
	shell.add_child(_bar)

	var pad := MarginContainer.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	pad.add_theme_constant_override("margin_top", 8)
	shell.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var column := VBoxContainer.new()
	column.custom_minimum_size.x = COLUMN
	column.add_theme_constant_override("separation", AppTheme.SPACE_S)
	row.add_child(column)

	for seat in 2:
		var tag := PlayerTag.new()
		tag.shape = PlayerTag.Shape.TAG
		_tags.append(tag)
		column.add_child(tag)

	# A instrução embaixo das etiquetas, e não num canto: ela responde "o que eu
	# faço agora", e é logo depois de saber de quem é a vez que se pergunta isso.
	_hint = Label.new()
	_hint.theme_type_variation = &"Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_hint)

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


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(AppTheme.BACKGROUND, 0.82)
	_overlay.add_child(dim)

	# Fim de partida em papel, como nos outros jogos.
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


func _on_shot_aimed(ball: int, direction: Vector2, power: float) -> void:
	if not _can_act():
		return
	_submit(PoolRules.shot(ball, direction, power))


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
	for seat in _tags.size():
		var tag := _tags[seat]
		# A bolacha na cor das bolas do assento: é a informação principal da tela no
		# mata-mata, e a etiqueta a carrega no avatar em vez de numa tarja.
		tag.seat_color = _seat_color(seat)
		tag.active = seat == turn
		tag.title = _seat_name(seat)
		tag.subtitle = _seat_detail(seat)


## A cor do assento: no mata-mata é a das bolas dele — e essa **é** a informação
## principal da tela, porque ela diz com quais bolas ele taca e quais ele tem de
## matar. Na brasileira os dois tacam com a mesma branca, então a cor volta a ser
## só o latão de "é a sua vez".
func _seat_color(seat: int) -> Color:
	if PoolRules.has_cue_ball(_state):
		return AppTheme.ACCENT
	return PoolRules.GROUP_COLORS[PoolRules.group_of(seat) % PoolRules.GROUP_COLORS.size()]


## O que falta **ao adversário**, e não a ele.
##
## No mata-mata a conta que decide a partida é quantas bolas do outro ainda estão
## na mesa: é isso que precisa chegar a zero. Mostrar as próprias seria mostrar
## quantos projéteis sobraram, que é outra pergunta — e a resposta errada para a
## que se está fazendo ao olhar o placar.
func _seat_detail(seat: int) -> String:
	if PoolRules.has_cue_ball(_state):
		return "%d pontos" % PoolRules.score_of(_state, seat)
	var hunting := PoolRules.group_of(1 - seat)
	return "faltam %d" % PoolRules.balls_left(_state, hunting)


func _seat_name(seat: int) -> String:
	if Game.mode == Game.Mode.ONLINE:
		# Vazio até o outro se apresentar — e quem volta depois de fechar o app só
		# reaprende os nomes no `resume`. Um cartão em branco parece defeito; um
		# numerado, só alguém que ainda não disse o nome.
		var theirs := Net.name_of(seat)
		if not theirs.is_empty():
			return theirs
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


## O gesto de voltar pergunta, como o botão da barra. Com o fim de partida na
## tela, sai direto: não há partida a proteger atrás do painel.
func go_back() -> void:
	if _overlay.visible:
		_leave()
		return
	_bar.leave.ask()


func _leave() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
