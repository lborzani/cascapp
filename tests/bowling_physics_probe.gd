extends SceneTree

## A física do boliche, sem tela de jogo.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/bowling_physics_probe.gd
##
## `--fixed-fps` faz cada quadro andar 1/60 s sem esperar o relógio: a física roda
## tão rápido quanto a máquina deixa, e o resultado não depende da carga dela.
##
## O que se persegue aqui é o que o jogo precisa da física para fazer sentido:
## bola no bolso derruba quase tudo, bola na canaleta não derruba nada, efeito
## curva para o lado certo e só no seco, a jogada acaba sozinha, e a máquina
## repõe os pinos no lugar exato.

const DEADLINE := 120.0
const FPS := 60

var _failures := 0
var _started := 0


func _initialize() -> void:
	_started = Time.get_ticks_msec()
	_run()


func _run() -> void:
	# Nó posto na raiz durante `_initialize` só fica pronto no primeiro quadro.
	await process_frame
	_test_launch()
	_test_spots()
	await _test_pocket()
	await _test_gutter()
	await _test_hook()
	await _test_settles_and_rack()
	await _test_same_twice()

	if _failures == 0:
		print("OK — física do boliche consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _test_launch() -> void:
	print("arremesso a partir dos parâmetros")
	var centre := BowlingLane.launch(PackedFloat32Array([0, 0, 0, 0]))
	_check(is_zero_approx(centre["position"].x), "posição 0 é o meio da pista")
	_check(centre["velocity"].z < 0.0 and is_zero_approx(centre["velocity"].x), "e a bola vai reto para os pinos")
	_check(is_equal_approx(centre["velocity"].length(), BowlingLane.FULL_SPEED), "com a força cheia no ponto certo")

	var right := BowlingLane.launch(PackedFloat32Array([1, 0, 0, 0]))
	_check(right["position"].x > 0.4, "posição +1 é a direita da linha")
	_check(BowlingLane.launch(PackedFloat32Array([0, 1, 0, 0]))["velocity"].x > 0.0, "direção +1 aponta para a direita")

	var early := BowlingLane.launch(PackedFloat32Array([0, 0, 0, -1]))
	var late := BowlingLane.launch(PackedFloat32Array([0, 0, 0, 1]))
	_check(early["velocity"].x < 0.0 and late["velocity"].x > 0.0, "cedo puxa para a esquerda, tarde empurra para a direita")
	_check(early["velocity"].length() < BowlingLane.FULL_SPEED, "e errar o timing tira força")


func _test_spots() -> void:
	print("lugar dos pinos")
	_check(BowlingLane.pin_spot(0).is_equal_approx(Vector3(0, 0, -BowlingLane.HEAD_PIN)), "pino 1 na cabeça")
	_check(BowlingLane.pin_spot(1).x < 0.0 and BowlingLane.pin_spot(2).x > 0.0, "2 à esquerda, 3 à direita")
	_check(BowlingLane.pin_spot(6).x < BowlingLane.pin_spot(9).x, "7 à esquerda do 10")
	_check(is_equal_approx(BowlingLane.pin_spot(9).x - BowlingLane.pin_spot(6).x, BowlingLane.PIN_SPACING * 3), "fileira de trás com 3 vãos")


func _test_pocket() -> void:
	print("bola no bolso")
	# Reto, entre o 1 e o 3, com pequenas variações de onde entra.
	var good := 0
	var counts := []
	for offset: float in [0.04, 0.055, 0.07, 0.085, 0.10]:
		var p := offset / (BowlingLane.LANE_W * 0.5 - BowlingLane.BALL_R)
		var run := await _throw(PackedFloat32Array([p, 0, 0, 0]))
		var down := BowlingRules.pin_count(run["mask"])
		counts.append("%d em %.1f s" % [down, float(run["frames"]) / FPS])
		if down >= 8:
			good += 1
	_check(good >= 3, "8 pinos ou mais na maioria das bolas no bolso (%s)" % [counts])


func _test_gutter() -> void:
	print("canaleta")
	for side: float in [-1.0, 1.0]:
		var run := await _throw(PackedFloat32Array([side, side, 0, 0]))
		_equals(run["mask"], 0, "bola na canaleta %s não derruba pino" % ("esquerda" if side < 0 else "direita"))


func _test_hook() -> void:
	print("efeito")
	var left := await _throw(PackedFloat32Array([0, 0, -1, 0]))
	var right := await _throw(PackedFloat32Array([0, 0, 1, 0]))
	var straight := await _throw(PackedFloat32Array([0, 0, 0, 0]))
	print("  x no fim do óleo: %.3f / %.3f / %.3f; nos pinos: %.3f / %.3f / %.3f" % [
		left["oil_x"], straight["oil_x"], right["oil_x"], left["pins_x"], straight["pins_x"], right["pins_x"]])
	_check(left["pins_x"] < -0.05 and right["pins_x"] > 0.05, "efeito curva para lados opostos")
	_check(absf(straight["pins_x"]) < 0.01, "sem efeito vai reto")
	var late_curve := absf(right["pins_x"] - right["oil_x"])
	_check(late_curve > absf(right["oil_x"]) * 2.0, "a curva aparece depois do óleo")


func _test_settles_and_rack() -> void:
	print("fim da jogada e máquina de pinos")
	var lane := BowlingLane.new()
	root.add_child(lane)
	lane.rack(BowlingRules.ALL_PINS)
	lane.throw(PackedFloat32Array([0.3, 0, 0, 0]))
	var frames := await _wait(lane)
	_check(frames > 0 and frames < BowlingLane.MAX_TIME * FPS, "a jogada termina sozinha (%.1f s)" % (float(frames) / FPS))
	var left := BowlingRules.ALL_PINS & ~lane.knocked()
	print("  ficaram em pé: %s" % String.num_int64(left, 2))
	lane.rack(left)
	var exact := true
	for pin in BowlingRules.PINS:
		var body := lane.pins[pin]
		if (left & (1 << pin)) != 0:
			exact = exact and body != null and body.position.is_equal_approx(BowlingLane.pin_spot(pin))
			exact = exact and body.basis.is_equal_approx(Basis.IDENTITY)
		else:
			exact = exact and body == null
	_check(exact, "os que ficaram voltam ao lugar exato, e só eles")
	_check(lane.ball == null and lane.knocked() == 0, "sem bola e nenhum caído depois de armar")
	lane.free()


func _test_same_twice() -> void:
	print("mesma jogada duas vezes")
	var params := PackedFloat32Array([0.4, -0.15, -0.6, 0.1])
	var first := await _throw(params)
	var second := await _throw(params)
	_check(first["mask"] != 0, "a jogada de teste derruba alguma coisa (%d pinos)" % BowlingRules.pin_count(first["mask"]))
	_equals(second["mask"], first["mask"], "dá a mesma máscara no mesmo aparelho")


# --- apoio --------------------------------------------------------------------


## Uma jogada numa pista nova, com todos os pinos. Devolve a máscara e por onde a
## bola passou no fim do óleo e na chegada aos pinos.
func _throw(params: PackedFloat32Array) -> Dictionary:
	var lane := BowlingLane.new()
	root.add_child(lane)
	lane.rack(BowlingRules.ALL_PINS)
	lane.throw(params)
	var track := {"oil_x": NAN, "pins_x": NAN}
	var frames := 0
	while lane.rolling and _alive():
		await physics_frame
		frames += 1
		var at := lane.ball.global_position
		if is_nan(track["oil_x"]) and at.z <= -BowlingLane.OIL_LEN:
			track["oil_x"] = at.x
		if is_nan(track["pins_x"]) and at.z <= -(BowlingLane.HEAD_PIN - 0.3):
			track["pins_x"] = at.x
	await physics_frame
	track["mask"] = lane.knocked()
	track["frames"] = frames
	lane.free()
	return track


func _wait(lane: BowlingLane) -> int:
	var frames := 0
	while lane.rolling and _alive():
		await physics_frame
		frames += 1
	return frames


func _alive() -> bool:
	if (Time.get_ticks_msec() - _started) / 1000.0 < DEADLINE:
		return true
	_check(false, "teto de %d s estourado" % DEADLINE)
	quit(1)
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
