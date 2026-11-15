extends Node

## A cena do boliche, com autoloads e nós de verdade.
##
##   godot --headless --fixed-fps 60 --path . res://tests/bowling_scene_probe.tscn
##
## As regras são do `bowling_probe` e a física do `bowling_physics_probe`. Aqui se
## confere a camada do meio, onde uma partida trava sem nada falhar:
##
## - **o gesto vira mira:** arrastar a bola muda a posição, arrastar o trilho muda
##   o efeito;
## - **o balanço:** o botão começa, o segundo toque solta, e o timing sai do
##   ângulo em que a bola estava;
## - **a física vira lance:** a jogada para, a cartela anda, a máquina arma o que
##   ficou em pé e a vez passa;
## - **a partida acaba** com o vencedor na tela, e o bot joga sozinho no solo.

const MATCH_SCENE := preload("res://scenes/bowling_match.tscn")
const DEADLINE := 240.0

var _failures := 0
var _done := false


func _ready() -> void:
	_watchdog()
	await _probe_opening()
	await _probe_aim()
	await _probe_swing_and_throw()
	await _probe_full_game()
	await _probe_bot()

	_done = true
	if _failures == 0:
		print("OK — cena do boliche consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _watchdog() -> void:
	await get_tree().create_timer(DEADLINE).timeout
	if _done or not is_inside_tree():
		return
	printerr("A sonda passou de %.0fs sem terminar." % DEADLINE)
	get_tree().quit(1)


func _probe_opening() -> void:
	print("abertura")
	Game.start_hotseat(Game.BOWLING)
	Game.table_size = 3
	var scene := await _open()
	_equals(BowlingRules.seats_of(scene._state), 3, "a mesa tem o tamanho escolhido no menu")
	_check(scene._view.enabled, "e a pista aceita mira")
	_check(scene._view._button.visible and scene._view._button.text == "Segure para jogar", "com o botão de jogar à vista")
	_check(scene._card.custom_minimum_size.y > BowlingCard.ROW * 2.5, "a cartela tem uma linha por jogador")
	_check(scene._hint.text.begins_with("Jogador 1"), "a dica diz de quem é a vez (%s)" % scene._hint.text)
	var standing := 0
	for body in scene._view.lane.pins:
		standing += 1 if body != null else 0
	_equals(standing, 10, "dez pinos armados")
	_check(Game.category_of(Game.BOWLING) == Game.CAT_SPORT and Game.category_of(Game.POOL) == Game.CAT_SPORT,
		"boliche e sinuca em Esporte")
	_check(Game.piece_of(Game.BOWLING) != 0, "o boliche tem ícone no catálogo")
	Game.table_size = 0
	scene.free()


func _probe_aim() -> void:
	print("mira")
	Game.start_hotseat(Game.BOWLING)
	var scene := await _open()
	var view: BowlingView = scene._view
	var track := view._track_rect()
	_tap(view, Vector2(track.end.x, track.get_center().y))
	_check(view.aim_spin > 0.9, "tocar no fim do trilho dá gancho cheio para a direita (%.2f)" % view.aim_spin)
	_tap(view, Vector2(track.position.x, track.get_center().y))
	_check(view.aim_spin < -0.9, "e no começo, para a esquerda")
	_check(view.spin_name().contains("esquerda"), "e o nome diz isso (%s)" % view.spin_name())

	var ball := view._to_screen(view._preview.position)
	_press(view, ball)
	_move(view, ball + Vector2(60.0, 0.0))
	_release(view, ball + Vector2(60.0, 0.0))
	_check(view.aim_position > 0.1, "arrastar a bola para a direita muda a posição (%.2f)" % view.aim_position)

	var start := view._to_screen(view._preview.position)
	var far := view._to_screen(Vector3(-0.5, 0.0, -12.0))
	_tap(view, far)
	_check(view.aim_direction < -0.1, "tocar na pista à esquerda gira a mira para a esquerda (%.2f)" % view.aim_direction)
	_check(far.y < start.y, "(o toque foi acima da bola)")
	scene.free()


func _probe_swing_and_throw() -> void:
	print("balanço e arremesso")
	Game.start_hotseat(Game.BOWLING)
	var scene := await _open()
	var view: BowlingView = scene._view
	var got := []
	var missed := []
	view.released.connect(func(p: PackedFloat32Array) -> void: got.append(p))
	view.swing_missed.connect(func() -> void: missed.append(true))

	# Sem o toque a bola não sai (na 1.47 ela saía sozinha no fim da volta).
	view._button.button_down.emit()
	await _frames(12)
	view._button.button_up.emit()
	var frames := 0
	while view._phase != BowlingView.Phase.AIM and frames < 200:
		await get_tree().process_frame
		frames += 1
	_check(got.is_empty() and BowlingRules.rolls_of(scene._state, 0).is_empty(), "sem o toque no verde a bola não sai")
	_equals(missed.size(), 1, "e o balanço avisa que voltou")
	_check(view.enabled and not scene._busy and view._button.text == "Segure para jogar", "com a mira de volta")

	# Segurar meio segundo dá meia força.
	view._button.button_down.emit()
	_check(view._phase == BowlingView.Phase.HOLD and view._button.text == "Solte o dedo", "segurar o botão junta força")
	await _frames(30)
	_check(absf(view._power - 0.5) < 0.06, "meio segundo segurando é meia força (%.2f)" % view._power)
	_check(view._angle > BowlingView.MIN_BACKSWING, "e a bola recua (%.0f°)" % view._angle)
	view._button.button_up.emit()
	_check(view._phase == BowlingView.Phase.FORWARD and view._button.text == "Toque no verde!", "soltar o dedo começa a volta")
	frames = 0
	while not (view._phase == BowlingView.Phase.FORWARD and view._angle < 3.0) and frames < 300:
		await get_tree().process_frame
		frames += 1
	# O toque na pista, longe do botão, também solta.
	_tap(view, Vector2(view.size.x * 0.5, view.size.y * 0.3))
	_equals(got.size(), 1, "o toque solta a bola")
	if got.is_empty():
		scene.free()
		return
	var timing: float = got[0][3]
	_check(absf(timing) < 0.35, "soltar perto do fundo dá timing perto de zero (%.2f)" % timing)
	_check(absf(got[0][4] - 0.5) < 0.06, "e a força vai no lance (%.2f)" % got[0][4])
	_check(not view.enabled and scene._busy, "com a bola rolando ninguém mexe")

	# A bola só sobe na tela enquanto rola: a câmera não pode fazê-la descer e
	# voltar (o "pulinho" da 1.47).
	var highest := INF
	var dip := 0.0
	frames = 0
	while BowlingRules.rolls_of(scene._state, 0).is_empty() and frames < 900:
		await get_tree().process_frame
		frames += 1
		var ball := view.lane.ball
		if ball != null and ball.global_position.z > -(BowlingLane.HEAD_PIN - 0.6) and frames > 20:
			var y := view._to_screen(ball.global_position).y
			highest = minf(highest, y)
			dip = maxf(dip, y - highest)
	_check(dip < 2.0, "a bola não volta para baixo na tela (desceu %.1f px)" % dip)
	var rolls := BowlingRules.rolls_of(scene._state, 0)
	_equals(rolls.size(), 1, "a jogada vira a primeira bola na cartela")
	while scene._busy and frames < 1200:
		await get_tree().process_frame
		frames += 1
	var standing := BowlingRules.standing(scene._state)
	var armed := 0
	for pin in BowlingRules.PINS:
		if scene._view.lane.pins[pin] != null:
			armed |= 1 << pin
	_equals(armed, standing, "a máquina arma só o que ficou em pé")
	var strike := rolls.size() > 0 and rolls[0] == 10
	_equals(BowlingRules.turn_of(scene._state), 1 if strike else 0, "a vez segue a regra (strike passa, senão é a segunda bola)")
	_check(scene._view.enabled, "e a pista volta a aceitar mira")
	scene.free()


func _probe_full_game() -> void:
	print("partida inteira")
	Game.start_hotseat(Game.BOWLING)
	var scene := await _open()
	# Arremessos forçados: jogador 1 faz 9 e erra, jogador 2 faz spares.
	var guard := 0
	while not BowlingRules.game_over(scene._state) and guard < 60:
		guard += 1
		var seat := BowlingRules.turn_of(scene._state)
		var standing := BowlingRules.standing(scene._state)
		var fresh := standing == BowlingRules.ALL_PINS
		var mask := (standing & ~1) if (seat == 0 and fresh) else (0 if seat == 0 else (standing & ~1 if fresh else standing))
		scene._busy = true
		await scene._play(BowlingRules.roll(mask))
	_check(BowlingRules.game_over(scene._state), "a partida acaba")
	_equals(BowlingRules.score_of(scene._state, 0), 90, "jogador 1 com 90")
	_equals(BowlingRules.score_of(scene._state, 1), 190, "jogador 2 com 190")
	_check(scene._overlay.visible, "o fim aparece na tela")
	_equals(scene._overlay_title.text, "Jogador 2 venceu", "com o vencedor")
	_check(not scene._view.enabled, "e a pista não aceita mais mira")
	scene._restart()
	_check(not scene._overlay.visible and BowlingRules.rolls_of(scene._state, 0).is_empty(), "jogar de novo zera a cartela")
	scene.free()


func _probe_bot() -> void:
	print("bot")
	Game.start_solo(Game.BOWLING)
	var scene := await _open()
	_equals(scene._bot_seats, PackedInt32Array([1]), "no solo a outra cadeira é máquina")
	# Primeiro frame do humano à força, depois a máquina joga sozinha.
	scene._busy = true
	await scene._play(BowlingRules.roll(BowlingRules.ALL_PINS))
	_equals(BowlingRules.turn_of(scene._state), 1, "strike passa a vez para a máquina")
	_check(not scene._view.enabled, "e a pista não aceita mira na vez dela")
	var frames := 0
	while BowlingRules.turn_of(scene._state) == 1 and frames < 2400:
		await get_tree().process_frame
		frames += 1
	var bot := BowlingRules.rolls_of(scene._state, 1)
	_check(not bot.is_empty(), "a máquina arremessa sozinha (%s)" % [bot])
	print("  bot derrubou %s" % [bot])
	_equals(BowlingRules.turn_of(scene._state), 0, "e devolve a vez")
	scene.free()


# --- apoio --------------------------------------------------------------------


func _open() -> Node:
	var scene := MATCH_SCENE.instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _tap(view: Control, at: Vector2) -> void:
	_press(view, at)
	_release(view, at)


func _press(view: Control, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	view._gui_input(event)


func _move(view: Control, at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	view._gui_input(event)


func _release(view: Control, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	view._gui_input(event)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
