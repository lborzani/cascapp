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
	await _probe_skins()
	await _probe_aim()
	await _probe_swing_and_throw()
	await _probe_full_game()
	await _probe_bot()
	await _probe_online()

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
	view.released.connect(func(p: PackedFloat32Array) -> void: got.append(p))

	# A força vai e volta enquanto o dedo está no botão (na 1.48 travava em 100%).
	view._button.button_down.emit()
	_check(view._phase == BowlingView.Phase.HOLD and view._button.text == "Solte na força certa", "segurar o botão junta força")
	await _frames(48)
	_check(view._power > 0.95, "em 0,8 s a força chega ao máximo (%.2f)" % view._power)
	_check(view._angle > BowlingView.MIN_BACKSWING, "e a bola recua (%.0f°)" % view._angle)
	await _frames(24)
	_check(absf(view._power - 0.5) < 0.06, "e volta em vez de travar: meia força em 1,2 s (%.2f)" % view._power)
	view._button.button_up.emit()
	_check(view._phase == BowlingView.Phase.SWING and view._button.text == "Toque no verde!", "soltar o dedo começa o balanço")

	# O balanço vai e volta até o toque: nem solta sozinho, nem desiste.
	await _frames(300)
	_check(got.is_empty() and view._phase == BowlingView.Phase.SWING, "cinco segundos depois a bola ainda balança, sem sair")
	var frames := 0
	while not (view._phase == BowlingView.Phase.SWING and absf(view._angle) < 3.0) and frames < 300:
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


## Em rede, pelos sinais do `Net` (sem relay: o caminho do relay é do
## `bowling_net_smoke`). Este aparelho é o assento 1 de uma mesa de dois.
## A bola de cada assento: a textura da loja do visual dele, ou o mármore na cor.
func _probe_skins() -> void:
	print("bola da loja")
	var galaxy := Cosmetics.ball_texture({"ball": "ball_galaxy"})
	var flames := Cosmetics.ball_texture({"ball": "ball_flames"})
	var look_before := Account.look
	Account.look = {"ball": "ball_galaxy"}
	Game.start_hotseat(Game.BOWLING)
	var scene := await _open()
	_equals(_ball_paint(scene._view._preview), galaxy, "no aparelho, a bola do dono usa a textura dele")
	_equals(scene._view.lane.ball_skin, galaxy, "e a pista arma a bola com ela")
	scene._dress_ball(1)
	_check(_ball_paint(scene._view._preview) != galaxy, "o segundo jogador do mesmo aparelho fica com a bola padrão")
	_equals(_ball_tint(scene._view._preview), scene._seat_color(1), "na cor do assento dele")
	scene.free()

	Game.start_hotseat(Game.BOWLING)
	Game.mode = Game.Mode.ONLINE
	Net.local_seat = 1
	Net.seats = 2
	Net.looks = {0: {"ball": "ball_flames"}, 1: {"ball": "ball_galaxy"}}
	scene = await _open()
	scene._dress_ball(0)
	_equals(_ball_paint(scene._view._preview), flames, "em rede, a bola de cada um é a que ele mandou")
	scene._dress_ball(1)
	_equals(_ball_paint(scene._view._preview), galaxy, "inclusive a deste aparelho")
	Net.looks = {0: {"ball": "ball_que_nao_existe"}}
	scene._dress_ball(0)
	_equals(_ball_tint(scene._view._preview), scene._seat_color(0), "item que este app não conhece cai na bola padrão")
	scene.free()
	Net.looks = {}
	Account.look = look_before
	Game.mode = Game.Mode.HOTSEAT


## A textura que a bola desenha agora (a do material pintado, ou a do mármore).
func _ball_paint(node: Node) -> Texture2D:
	var material := _ball_material(node)
	return material.albedo_texture if material != null else null


func _ball_tint(node: Node) -> Color:
	var material := _ball_material(node)
	return material.albedo_color if material != null else Color.WHITE


func _ball_material(node: Node) -> StandardMaterial3D:
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (found as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and source.resource_name == "ball":
				var painted := (found as MeshInstance3D).get_surface_override_material(surface) as StandardMaterial3D
				return painted if painted != null else source
	return null


func _probe_online() -> void:
	print("em rede")
	Game.start_hotseat(Game.BOWLING)
	Game.mode = Game.Mode.ONLINE
	Net.connected = true
	Net.local_seat = 1
	Net.seats = 2
	Net.bot_seats = PackedInt32Array()
	Net.player_names = {0: "Ana", 1: "Bia"}
	var scene := await _open()
	_equals(BowlingRules.seats_of(scene._state), 2, "a mesa tem o tamanho da sala")
	_check(not scene._view.enabled, "na vez do outro a pista não aceita mira")
	_check(scene._hint.text.begins_with("Ana"), "e a dica diz de quem é a vez (%s)" % scene._hint.text)
	_check(not scene._again.visible, "em rede não há jogar de novo")

	# O arremesso da Ana chega: a pista o repete e vale a máscara recebida (9 pinos),
	# não o que a física daqui der.
	var params := PackedFloat32Array([0.3, 0.0, 0.0, 0.0, 1.0])
	Net.move_received.emit({"p": BowlingRules.roll(0b0111111111, params).path, "n": 0, "seat": 0})
	_check(scene._busy and scene._view._phase == BowlingView.Phase.ROLLING, "o arremesso de fora é repetido na pista")
	var frames := 0
	while scene._busy and frames < 1200:
		await get_tree().process_frame
		frames += 1
	_equals(BowlingRules.rolls_of(scene._state, 0), PackedInt32Array([9]), "e entra na cartela com o que veio pela rede")
	var armed := 0
	for pin in BowlingRules.PINS:
		if scene._view.lane.pins[pin] != null:
			armed |= 1 << pin
	_equals(armed, 0b1000000000, "a máquina arma o que o estado manda (só o 10)")

	# Fora da vez, ou de quem não tem a vez, não entra.
	Net.move_received.emit({"p": BowlingRules.roll(0b1000000000).path, "n": 1, "seat": 1})
	await _frames(3)
	_equals(scene._state.ply, 1, "arremesso de quem não tem a vez é recusado")

	# A segunda bola da Ana chega em quadros, enquanto ela joga: a pista segue o
	# que ela manda, sem física, e o lance só entra depois do último quadro.
	for step in range(0, 61, 4):
		var down := 0b1000000000 if step == 60 else 0
		Net.frame_received.emit({"n": 1, "k": step, "x": _poses(-step / 8.0, down, 0b1000000000), "seat": 0})
	_check(scene._shown == 1 and scene._view.lane.following, "os quadros da Ana vão direto para a pista")
	_check(scene._view._phase == BowlingView.Phase.ROLLING and not scene._view.enabled, "com a bola rolando e sem mira")
	_check(scene._view.lane.pins[9].freeze, "e sem física daqui")
	var wrong: int = scene._view.lane._frames.size()
	Net.frame_received.emit({"n": 1, "k": 64, "x": _poses(-8.0, 0, 0b1000000000), "seat": 1})
	_equals(scene._view.lane._frames.size(), wrong, "quadro de quem não tem a vez é ignorado")
	Net.move_received.emit({"p": BowlingRules.roll(0b1000000000).path, "n": 1, "seat": 0})
	await _frames(2)
	_equals(scene._state.ply, 1, "o lance espera a pista mostrar o último quadro")
	frames = 0
	while scene._state.ply < 2 and frames < 600:
		await get_tree().process_frame
		frames += 1
	_check(BowlingLane.is_down(scene._view.lane.pins[9].global_transform), "no fim, o 10 está no chão como na pista da Ana")
	_equals(BowlingRules.rolls_of(scene._state, 0), PackedInt32Array([9, 1]), "e o spare entra na cartela")
	frames = 0
	while scene._busy and frames < 1200:
		await get_tree().process_frame
		frames += 1
	_equals(BowlingRules.turn_of(scene._state), 1, "o frame da Ana fechou e a vez é daqui")
	_check(scene._view.enabled, "e a pista aceita mira")

	# Reconexão: o histórico chega e a cartela é refeita sem física.
	var history: Array[Dictionary] = []
	var rules: BowlingRules = scene._rules
	var rebuilt := rules.initial_state()
	for mask: int in [0b0111111111, 0, 0b1111111111, 0b0000000111]:
		var move := BowlingRules.roll(mask)
		var checked := rules.validate(rebuilt, move.path)
		rules.apply_move(rebuilt, checked)
		history.append(checked.to_dict())
	Net.sync_received.emit(history, [])
	_equals(scene._state.ply, 4, "o histórico refaz a partida")
	_equals(BowlingRules.rolls_of(scene._state, 1), PackedInt32Array([10]), "com o strike daqui")
	_equals(BowlingRules.standing(scene._state), 0b1111111000, "e os pinos em pé do frame da Ana")
	_check(not scene._view.enabled, "a vez voltou para a Ana")

	Net.opponent_left.emit()
	_check(scene._abandoned and not scene._view.enabled, "o outro saiu: a partida para")

	Net.connected = false
	Net.local_seat = 0
	Net.player_names = {}
	scene.free()


# --- apoio --------------------------------------------------------------------


## Um quadro de jogada como o que vem pela rede (`BowlingLane.snapshot`): a bola
## em `ball_z` no meio da pista, os pinos de `racked` no lugar e os de `fallen`
## deitados.
func _poses(ball_z: float, fallen: int, racked: int) -> PackedInt32Array:
	var poses := PackedInt32Array()
	poses.resize(BowlingLane.BODIES * BowlingLane.POSE_INTS)
	_put(poses, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, BowlingLane.BALL_R, ball_z)))
	for pin in BowlingRules.PINS:
		if racked & (1 << pin):
			var lying := Basis(Vector3.RIGHT, PI / 2.0) if fallen & (1 << pin) else Basis.IDENTITY
			_put(poses, pin + 1, Transform3D(lying, BowlingLane.pin_spot(pin)))
	return poses


func _put(poses: PackedInt32Array, index: int, pose: Transform3D) -> void:
	var at := pose.origin * BowlingLane.POSE_MM
	var turn := pose.basis.get_rotation_quaternion() * BowlingLane.POSE_QUAT
	var values := [at.x, at.y, at.z, turn.x, turn.y, turn.z, turn.w]
	for slot in BowlingLane.POSE_INTS:
		poses[index * BowlingLane.POSE_INTS + slot] = roundi(values[slot])


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
