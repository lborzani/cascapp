extends Control

## A partida de Bomberman: o relógio de passo fixo, os controles e a tela.
##
## ## O laço é diferente de todas as outras telas do app
##
## Nas outras, a partida só anda quando alguém joga: um toque vira lance, o lance
## vira estado novo, a tela redesenha. Aqui a partida anda **sozinha**, trinta
## vezes por segundo, e o toque só decide o que os bonecos estão tentando fazer
## quando cada um desses passos acontece.
##
## O passo é fixo e o quadro não. O `_process` recebe um `delta` que varia com o
## aparelho; se a simulação andasse por `delta`, dois celulares veriam partidas
## diferentes. Então o tempo entra num acumulador e sai em pedaços iguais de
## [constant BomberRules.TICK_HZ]. O resto do quadro vira [member BomberView.blend]:
## a tela desenha entre o último passo e o próximo.
##
## ## Em rede: servidor autoritativo, e não mais lockstep
##
## O modelo antigo era lockstep — cada aparelho rodava a simulação e esperava o
## comando dos outros pra andar, com um atraso de entrada fixo de 167 ms e uma
## travada sempre que alguém engasgava. Agora quem tem razão sobre a partida é o
## servidor ([BomberNet], [BomberRoom]), e este aparelho **prevê** com o
## [BomberPredictor]: aplica o próprio comando na hora e se corrige quando o
## snapshot do servidor discorda. O boneco local responde no mesmo tique, e um
## engasgo de um jogador não para os outros.
##
## O que a rede resolve mora no [BomberPredictor] e no [BomberRoom]; aqui só mora o
## relógio — quantos tiques dar neste quadro, e quando mandar o que o dedo pediu.

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Segundos de um passo.
const STEP := 1.0 / float(BomberRules.TICK_HZ)
## Passos que um quadro pode recuperar. Acima disso o tempo é perdido de propósito
## em vez de rodar de uma vez e travar a tela.
const MAX_CATCH_UP := 8

## Tiques à frente do último snapshot em que o comando é carimbado.
##
## O servidor está adiantado em relação ao que o cliente vê: o snapshot levou meio
## ping pra chegar e o comando vai levar outro meio. Carimbar pro tique do snapshot
## seria mandar sempre pro passado. Três tiques são 100 ms de folga; enquanto isso
## [constant BomberProtocol.INPUT_GRACE] cobre o erro. Ajuste automático pelo ping
## fica pra depois.
const SEND_LEAD := 3

## O relógio escorrega pra manter a folga em vez de travar. Adiantado, o tique dura
## um tiquinho mais; atrasado, um tiquinho menos. Os limites são imperceptíveis e
## ainda assim fecham vários tiques de erro em segundos. Mesmo princípio da
## absorção de correção da tela.
const PACE_LIMIT := 0.05
const PACE_GAIN := 0.01

## Altura da faixa de controles, na base deitada de 432.
const PAD_SIZE := 128.0
const PAD_MARGIN := 12.0
const BOMB_SIZE := 96.0

var _rules := BomberRules.new()
var _bot := BomberBot.new()
var _state: BomberState = null
var _accumulator := 0.0
## Posição de cada boneco no passo anterior, para a tela interpolar.
var _previous := PackedInt32Array()
var _over := false
## A partida acabou porque a mesa esvaziou, e não porque alguém venceu.
var _abandoned := false

## A partida é em rede.
var _online := false
var _seat := 0
var _names := PackedStringArray()

## A previsão do cliente. Nula fora da rede — offline a simulação é direta.
var _predictor: BomberPredictor = null
var _server_tick := -1
var _net_time := 0.0
## Comandos locais recentes, pra cada mensagem repetir os anteriores.
var _outbox := PackedByteArray()

var _view: BomberView = null
var _pad: BomberPad = null
var _bomb: BombButton = null
var _status: Label = null
var _result: Control = null
var _result_title: Label = null
var _again: Button = null


func _ready() -> void:
	theme = AppTheme.shared()
	Orientation.to_landscape(get_tree())
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	_online = Game.mode == Game.Mode.ONLINE
	Game.begin_match()
	_build()
	_new_match()
	set_process(true)


func _new_match() -> void:
	_over = false
	_abandoned = false
	_accumulator = 0.0
	_net_time = 0.0
	_server_tick = -1
	_outbox = PackedByteArray()
	_previous = PackedInt32Array()

	if _online:
		_seat = BomberNet.seat
		_predictor = BomberPredictor.new(_rules, _seat)
		_state = null
		BomberNet.snapshot_arrived.connect(_on_snapshot)
		BomberNet.frame_arrived.connect(_on_frame)
		BomberNet.seats_changed.connect(_on_seats)
		BomberNet.dropped.connect(_on_dropped)
		_on_seats(BomberNet.names)
	else:
		# Offline: o assento local é o 0, o resto é máquina, e a simulação é direta —
		# não há snapshot pra prever nem servidor pra reconciliar.
		var seats := Game.players_of(Game.BOMBERMAN)
		Game.local_seat = 0
		_seat = 0
		_state = _rules.initial_state(seats, _match_seed())
		_previous = _snapshot_positions(_state)

	_result.visible = false
	_pad.release()
	_refresh_status()


## A semente da partida offline. Em rede ela não existe: o mapa inteiro vem dentro
## do primeiro snapshot do servidor.
func _match_seed() -> int:
	return int(Time.get_unix_time_from_system()) & 0x7FFFFFFF


func _process(delta: float) -> void:
	if _online:
		_online_frame(delta)
		return

	if _state == null:
		return
	if not _over:
		_accumulator += delta
		var steps := 0
		while _accumulator >= STEP and steps < MAX_CATCH_UP:
			_previous = _snapshot_positions(_state)
			_rules.step(_state, _offline_commands())
			_accumulator -= STEP
			steps += 1
			if _check_finish():
				break
		if _accumulator >= STEP * MAX_CATCH_UP:
			_accumulator = 0.0

	_view.state = _state
	_view.previous = _previous
	_view.blend = clampf(_accumulator / STEP, 0.0, 1.0)
	_view.refresh()


# --- online ------------------------------------------------------------------


## O cliente simula na frente do servidor; o [BomberPredictor] cuida de estar
## certo. Aqui só o relógio: quantos tiques dar, e quando mandar o comando.
func _online_frame(delta: float) -> void:
	if _predictor == null or _predictor.state == null:
		return

	if not _over:
		_net_time += delta
		var step := _paced_step()
		var made := 0
		while _net_time >= step and made < MAX_CATCH_UP:
			_net_time -= step
			made += 1
			_advance_online()
			if _check_finish():
				break
		if _net_time > step * MAX_CATCH_UP:
			_net_time = 0.0

	_view.state = _predictor.state
	_view.previous = _snapshot_positions(_predictor.previous)
	_view.blend = clampf(_net_time / _paced_step(), 0.0, 1.0)
	_view.refresh()


## Quanto dura um tique agora — 1/30 s, esticado ou encolhido um pouco pra a folga
## de [constant SEND_LEAD] voltar ao lugar. Escorregar em vez de travar: parar de
## simular quando adiantado trava o fator de interpolação e vira tremor no próprio
## boneco, o único que a previsão acerta em cheio.
func _paced_step() -> float:
	if _server_tick < 0:
		return STEP
	var slack := float(_predictor.tick - _server_tick - SEND_LEAD)
	return STEP * (1.0 + clampf(slack * PACE_GAIN, -PACE_LIMIT, PACE_LIMIT))


func _advance_online() -> void:
	var command := _local_input()
	_predictor.advance(command)

	_outbox.append(command)
	while _outbox.size() > BomberProtocol.FRAME + BomberProtocol.HISTORY:
		_outbox = _outbox.slice(1)
	# A repetição substitui retransmissão: o comando é a única coisa que o servidor
	# não reconstrói sozinho, e repeti-lo custa um byte enquanto pedir de novo
	# custaria uma viagem inteira.
	if _predictor.tick % BomberProtocol.FRAME == 0:
		BomberNet.send_inputs(_predictor.tick - _outbox.size() + 1, _outbox)


func _on_snapshot(raw: PackedByteArray) -> void:
	if _predictor == null:
		return
	var fresh := BomberState.new()
	if not fresh.from_bytes(raw):
		return
	# UDP não promete ordem: um snapshot mais velho que o último descreve um passado
	# que a tela já deixou.
	if fresh.tick <= _server_tick:
		return
	_server_tick = fresh.tick

	if _predictor.state == null:
		# O primeiro snapshot não tem o que reconciliar, e o cliente ainda tem que
		# ganhar a folga: adota e corre os tiques de vantagem de uma vez, com o dedo
		# parado.
		_predictor.adopt(fresh)
		for extra in SEND_LEAD:
			_predictor.advance(0)
		return

	_predictor.reconcile(fresh)


func _on_frame(raw: PackedByteArray) -> void:
	if _predictor == null:
		return
	var parsed := BomberProtocol.read_frame(raw)
	if parsed.is_empty():
		return
	# Antes do snapshot que vai usá-los: a reconciliação reexecuta com o que já está
	# na mão, e um comando que chega depois do snapshot chegou tarde.
	_predictor.note(parsed["tick"], parsed["rows"])


func _on_seats(names: PackedStringArray) -> void:
	_names = names
	if _predictor != null:
		_predictor.note_seats(names)
	_refresh_status()


## O servidor sumiu. Não há partida a continuar sem quem tenha razão sobre ela.
func _on_dropped() -> void:
	if _over:
		return
	_abandoned = true
	_over = true
	_pad.release()
	_result_title.text = "Conexão perdida"
	_result.visible = true
	_refresh_status()


# --- simulação e tela --------------------------------------------------------


## As posições de todos os bonecos, pra a tela interpolar entre dois passos.
func _snapshot_positions(state: BomberState) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(state.players.size() * 2)
	for seat in state.players.size():
		out[seat * 2] = state.players[seat].x
		out[seat * 2 + 1] = state.players[seat].y
	return out


## Os comandos de todos os assentos offline: o local do dedo, o resto das máquinas.
func _offline_commands() -> PackedByteArray:
	var inputs := PackedByteArray()
	inputs.resize(_state.players.size())
	for seat in _state.players.size():
		inputs[seat] = _local_input() if seat == _seat else _bot.decide(_state, seat)
	return inputs


func _check_finish() -> bool:
	var shown := _predictor.state if _online else _state
	var champion := _rules.winner(shown)
	if champion != -1:
		_finish(champion)
		return true
	return false


## O que este aparelho está pedindo. Direcional mais teclado: as setas existem para
## a partida ser jogável no desktop, onde ela é conferida.
func _local_input() -> int:
	var command := _pad.direction()
	if Input.is_action_pressed("ui_up"):
		command |= BomberRules.IN_UP
	elif Input.is_action_pressed("ui_down"):
		command |= BomberRules.IN_DOWN
	elif Input.is_action_pressed("ui_left"):
		command |= BomberRules.IN_LEFT
	elif Input.is_action_pressed("ui_right"):
		command |= BomberRules.IN_RIGHT
	if _pad.take_bomb() or Input.is_action_just_pressed("ui_accept"):
		command |= BomberRules.IN_BOMB
	return command


func _finish(champion: int) -> void:
	if _over:
		return
	_over = true
	_pad.release()
	if champion == _seat:
		_result_title.text = "Você venceu"
	elif champion < 0:
		_result_title.text = "Empate"
	else:
		_result_title.text = "%s venceu" % _seat_label(champion)
	Sound.play(Sound.Cue.WIN)
	_result.visible = true
	_refresh_status()


## Como o jogador é chamado. O nome guardado no aparelho para quem está com ele na
## mão, o que a sala anunciou para os outros, e o número do assento para quem ainda
## não se apresentou.
func _seat_label(seat: int) -> String:
	if _online:
		if seat == _seat:
			return Prefs.player_name()
		if seat < _names.size() and _names[seat] != "":
			return _names[seat]
	return "Jogador %d" % (seat + 1)


func _refresh_status() -> void:
	if _over:
		_status.text = ""
		return
	var shown := _predictor.state if (_online and _predictor != null) else _state
	if shown == null:
		_status.text = "Conectando…"
		return
	_status.text = "%d de pé" % shown.alive_count()


# --- construção da tela ------------------------------------------------------


func _build() -> void:
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var safe := SafeAreaMargin.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 8)
	add_child(safe)

	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe.add_child(stage)

	_view = BomberView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_view)

	# Os controles ficam **por cima** do mapa, nos cantos de baixo: numa tela deitada
	# de 432 de altura, uma faixa própria roubaria um terço do mapa.
	_pad = BomberPad.new()
	_pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_pad.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_pad.offset_left = PAD_MARGIN
	_pad.offset_right = PAD_MARGIN + PAD_SIZE
	_pad.offset_top = -(PAD_MARGIN + PAD_SIZE)
	_pad.offset_bottom = -PAD_MARGIN
	stage.add_child(_pad)

	_bomb = BombButton.new()
	_bomb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bomb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bomb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bomb.offset_left = -(PAD_MARGIN + BOMB_SIZE)
	_bomb.offset_right = -PAD_MARGIN
	_bomb.offset_top = -(PAD_MARGIN + BOMB_SIZE)
	_bomb.offset_bottom = -PAD_MARGIN
	# No encostar, e não no soltar: o segundo só dispara quando o dedo **sai** do
	# botão, e num jogo de reação isso é meio segundo entre querer a bomba e ela cair.
	_bomb.pressed_down.connect(_pad.press_bomb)
	stage.add_child(_bomb)

	_status = Label.new()
	_status.theme_type_variation = &"Caption"
	_status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.offset_top = 2
	# Contorno, e não uma faixa atrás.
	#
	# O mapa ocupa a tela inteira e este rótulo cai **em cima** dele: sobre a
	# parede de concreto, que é um cinza médio, o texto apagado do tema ficava
	# cinza sobre cinza. Uma faixa escura atrás resolveria o contraste e tiraria
	# duas casas do mapa; o contorno resolve o mesmo sem ocupar pixel nenhum, e
	# continua funcionando quando o fogo passa por baixo dele.
	_status.add_theme_color_override("font_color", AppTheme.TEXT)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color(AppTheme.BACKGROUND, 0.85))
	stage.add_child(_status)

	var leave := LeaveButton.new()
	leave.set_anchors_preset(Control.PRESET_TOP_LEFT)
	leave.offset_left = 6
	leave.offset_top = 6
	leave.confirmed.connect(_leave)
	stage.add_child(leave)

	_build_result()


func _build_result() -> void:
	_result = Control.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.visible = false
	add_child(_result)

	var shade := ColorRect.new()
	shade.color = Color(AppTheme.BACKGROUND, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE, AppTheme.RADIUS_LARGE, AppTheme.BORDER, 1
	))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_result_title = Label.new()
	_result_title.theme_type_variation = &"Title"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	# "Jogar de novo" não existe em rede: a partida é do servidor, e recomeçá-la é
	# decisão de todo mundo, não de quem apertar primeiro. Revanche em rede é abrir
	# outra sala.
	_again = Button.new()
	_again.text = "Jogar de novo"
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.visible = not _online
	_again.pressed.connect(_restart)
	buttons.add_child(_again)

	var out := Button.new()
	out.text = "Sair"
	out.theme_type_variation = &"GhostButton"
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.pressed.connect(_leave)
	buttons.add_child(out)


func _restart() -> void:
	Game.restart_match()
	_new_match()


func go_back() -> void:
	_leave()


func _leave() -> void:
	if _online:
		BomberNet.leave()
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
