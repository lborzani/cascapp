extends Node

## A cena da sinuca, com autoloads e nós de verdade.
##
##   godot --headless --path . res://tests/pool_scene_probe.tscn
##
## As regras e a física são cobertas por `pool_probe.gd`. O que se verifica aqui
## é a camada que o teste de regra não alcança, e que é onde uma partida trava
## sem nada falhar:
##
## - **o gesto vira lance.** O arrasto é convertido em direção e força pela tela,
##   e o lance sai daí — se a conversão estiver invertida, a bola vai para o lado
##   contrário do dedo e nenhum teste de regra percebe;
## - **a tela só aceita toque quando é a vez**, e nunca enquanto a mesa anda;
## - **a fita da tacada existe**, que é o que separa a bola vista entrando de um
##   ponto que aparece do nada no placar;
## - **a branca na mão recusa lugar ocupado**, que é a única validação de posição
##   do jogo.

const MATCH_SCENE := preload("res://scenes/pool_match.tscn")

## Teto de tempo da suíte inteira.
##
## Não é paciência, é **modo de falhar**. Uma sonda de cena que espera animação
## pendura o processo quando alguma coisa não acontece — e um processo pendurado
## não é um teste que falhou, é um teste que ninguém sabe que existe: sai sem
## mensagem, sem código de erro, e morre no tempo limite da esteira meia hora
## depois. Com o relógio, a mesma situação vira uma linha dizendo onde parou.
const DEADLINE := 90.0

var _failures := 0
var _done := false


func _ready() -> void:
	_watchdog()
	Game.start_hotseat(Game.POOL)
	Game.pool_format = PoolRules.Format.KNOCKOUT

	await _probe_opening()
	await _probe_shot()
	await _probe_hand()

	_done = true
	if _failures == 0:
		print("OK — cena da sinuca consistente.")
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
	var scene := await _open()
	_check(scene._state != null, "a partida nasce montada")
	_equals(
		PoolRules.ball_count(scene._state), PoolRules.KNOCKOUT_PER_GROUP * 2 + 1,
		"com a branca e as oito"
	)
	_check(scene._view.enabled, "e a mesa aceita mira")
	_equals(scene._rules.trace_every, PoolRules.TRACE_EVERY, "com a fita da tacada ligada")
	scene.free()


## O arrasto vira tacada, e a direção é **do dedo para a bola**.
##
## É o teste que pega a inversão do gesto: puxar o taco para a direita manda a
## branca para a esquerda, e os dois testes de regra do mundo não notariam.
func _probe_shot() -> void:
	print("o arrasto vira tacada")
	var scene := await _open()
	var sent := []
	scene._view.shot_aimed.connect(func(direction: Vector2, power: float) -> void:
		sent.append([direction, power])
	)

	var view: PoolView = scene._view
	# Lido **antes** do arrasto: `_play` aplica o lance no mesmo quadro em que o
	# gesto termina, e só depois começa a esperar a animação. Ler a posição entre as
	# duas coisas é ler a mesa já resolvida e concluir que nada se mexeu.
	var before := PoolRules.position_of(scene._state, 0)

	var cue := view._cue_screen()
	view._begin(cue + Vector2(120.0, 0.0))
	view._end(cue + Vector2(120.0, 0.0))
	_equals(sent.size(), 1, "soltar o arrasto pede uma tacada")
	if sent.is_empty():
		scene.free()
		return
	var direction: Vector2 = sent[0][0]
	_check(direction.x < -0.9, "puxando para a direita, a branca vai para a esquerda")
	_check(PoolRules.position_of(scene._state, 0) != before, "e a branca sai do lugar")
	_equals(scene._state.ply, 1, "com a tacada virando um lance no histórico")

	_check(not view.enabled, "com a mesa andando, a mira fecha")
	_check(not scene._rules.trace_spots.is_empty(), "e a fita da tacada tem quadros")
	# Segunda tacada no meio da primeira: recusada, e é o que impede uma mesa que
	# ainda anda de receber outro lance por cima.
	scene._on_shot_aimed(Vector2.RIGHT, 1.0)
	_equals(scene._state.ply, 1, "e uma segunda tacada no meio da primeira é recusada")

	await get_tree().create_timer(view.remaining_animation() + 0.6).timeout
	_check(view.remaining_animation() == 0.0, "a mesa para sozinha")
	scene.free()


## A branca na mão recusa lugar ocupado. É a única validação de posição do jogo, e
## sem ela dá para largar a branca dentro de outra bola — as duas explodem no
## primeiro passo da simulação.
func _probe_hand() -> void:
	print("branca na mão")
	var scene := await _open()
	scene._state.meta[PoolRules.HAND] = 1
	scene._refresh()

	var occupied := PoolRules.position_of(scene._state, 1)
	_check(
		scene._rules.validate(scene._state, PoolRules.placement(occupied).path) == null,
		"em cima de outra bola, não"
	)
	var free_spot := Vector2(PoolRules.TABLE_WIDTH * 0.2, PoolRules.TABLE_HEIGHT * 0.5)
	_check(
		scene._rules.validate(scene._state, PoolRules.placement(free_spot).path) != null,
		"no pano vazio, sim"
	)
	# E tacar enquanto a branca está na mão não é lance: a ordem é pôr e depois
	# tacar, e a tela que oferecesse as duas deixaria a bola em dois lugares.
	_check(
		scene._rules.validate(scene._state, PoolRules.shot(Vector2.RIGHT, 1.0).path) == null,
		"e tacar antes de pôr, não"
	)
	scene.free()


# --- utilidades ---------------------------------------------------------------


func _open() -> Node:
	var scene := MATCH_SCENE.instantiate()
	add_child(scene)
	await get_tree().process_frame
	# Um quadro não basta: a mesa é desenhada depois do primeiro `_layout`, e o
	# gesto depende da escala que ele calcula.
	await get_tree().process_frame
	return scene


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
