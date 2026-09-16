extends Node

## A cena da sinuca, com autoloads e nós de verdade.
##
##   godot --headless --path . res://tests/pool_scene_probe.tscn
##
## As regras e a física são cobertas por `pool_probe.gd`. O que se verifica aqui
## é a camada que o teste de regra não alcança, e que é onde uma partida trava
## sem nada falhar:
##
## - **a escolha da bola.** Sem tacadeira, com qual bola se taca é metade da
##   jogada, e quem a escolhe é o dedo. Se o toque pegar a bola errada — ou a do
##   adversário — o lance sai inteiro e a regra não tem como saber que não era
##   aquele que o jogador queria;
## - **o gesto vira lance.** O arrasto é convertido em direção e força pela tela;
##   se a conversão estiver invertida, a bola vai para o lado contrário do dedo e
##   nenhum teste de regra percebe;
## - **o ponto de contato**, que é a conta de que a mira inteira depende;
## - **a tela só aceita toque quando é a vez**, e nunca enquanto a mesa anda;
## - **a branca na mão recusa lugar ocupado** — a única validação de posição do
##   jogo, e só na brasileira.

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

	await _probe_opening()
	await _probe_pick()
	await _probe_shot()
	await _probe_aim()
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
	var scene := await _open(PoolRules.Format.KNOCKOUT)
	_check(scene._state != null, "a partida nasce montada")
	_equals(
		PoolRules.ball_count(scene._state), PoolRules.KNOCKOUT_PER_GROUP * 2,
		"cinco contra cinco, e sem branca"
	)
	_check(scene._view.enabled, "e a mesa aceita mira")
	_equals(scene._rules.trace_every, PoolRules.TRACE_EVERY, "com a fita da tacada ligada")
	scene.free()


## O dedo escolhe com qual bola se taca, e só entre as próprias.
##
## É o que o mata-mata trouxe de novo. Um toque que pegasse a bola do adversário
## montaria um lance que a regra recusa — e o jogador veria a tela não responder
## sem saber por quê.
func _probe_pick() -> void:
	print("escolha da bola")
	var scene := await _open(PoolRules.Format.KNOCKOUT)
	var view: PoolView = scene._view

	var mine := PoolRules.shootable(scene._state)
	_equals(mine.size(), PoolRules.KNOCKOUT_PER_GROUP, "há cinco bolas para escolher")
	_check(view._shooter_ball() in mine, "e a tela começa com uma delas")

	# Tocar numa bola própria troca a escolha.
	var wanted: int = mine[3]
	view._begin(view._to_screen(PoolRules.position_of(scene._state, wanted)))
	_equals(view._shooter_ball(), wanted, "tocar numa bola minha passa a tacada para ela")
	_check(not view._aiming, "e não começa a mirar no mesmo toque")

	# Tocar numa do adversário não escolhe nada: ela não é tacável.
	var theirs := PoolRules.KNOCKOUT_PER_GROUP
	view._begin(view._to_screen(PoolRules.position_of(scene._state, theirs)))
	_equals(view._shooter_ball(), wanted, "tocar numa do adversário não troca a escolha")

	# A escolhida que cai deixa de valer: a tela não pode apontar o taco para um
	# buraco na vez seguinte.
	var live := PackedByteArray(scene._state.meta[PoolRules.LIVE])
	live[wanted] = 0
	scene._state.meta[PoolRules.LIVE] = live
	_check(view._shooter_ball() != wanted, "a bola que caiu deixa de ser a escolhida")
	_check(view._shooter_ball() in mine, "e a tela cai numa que ainda está na mesa")
	scene.free()


## O arrasto vira tacada, e a direção é **do dedo para a bola**.
##
## É o teste que pega a inversão do gesto: puxar o taco para a direita manda a
## bola para a esquerda, e os dois testes de regra do mundo não notariam.
func _probe_shot() -> void:
	print("o arrasto vira tacada")
	var scene := await _open(PoolRules.Format.KNOCKOUT)
	var view: PoolView = scene._view
	var sent := []
	view.shot_aimed.connect(func(ball: int, direction: Vector2, power: float) -> void:
		sent.append([ball, direction, power])
	)

	# Lido **antes** do arrasto: `_play` aplica o lance no mesmo quadro em que o
	# gesto termina, e só depois começa a esperar a animação. Ler a posição entre
	# as duas coisas é ler a mesa já resolvida e concluir que nada se mexeu.
	var shooter := view._shooter_ball()
	var before := PoolRules.position_of(scene._state, shooter)

	var cue := view._cue_screen()
	view._begin(cue + Vector2(120.0, 0.0))
	view._end(cue + Vector2(120.0, 0.0))
	_equals(sent.size(), 1, "soltar o arrasto pede uma tacada")
	if sent.is_empty():
		scene.free()
		return
	_equals(sent[0][0], shooter, "e ela diz com qual bola")
	var direction: Vector2 = sent[0][1]
	_check(direction.x < -0.9, "puxando para a direita, a bola vai para a esquerda")
	_check(
		PoolRules.position_of(scene._state, shooter) != before,
		"e a bola escolhida sai do lugar"
	)
	_equals(scene._state.ply, 1, "com a tacada virando um lance no histórico")

	_check(not view.enabled, "com a mesa andando, a mira fecha")
	_check(not scene._rules.trace_spots.is_empty(), "e a fita da tacada tem quadros")
	# Segunda tacada no meio da primeira: recusada, e é o que impede uma mesa que
	# ainda anda de receber outro lance por cima.
	scene._on_shot_aimed(shooter, Vector2.RIGHT, 1.0)
	_equals(scene._state.ply, 1, "e uma segunda tacada no meio da primeira é recusada")

	await get_tree().create_timer(view.remaining_animation() + 0.6).timeout
	_check(view.remaining_animation() == 0.0, "a mesa para sozinha")
	scene.free()


## O ponto de contato, que é a conta de que a mira inteira depende.
##
## A bola que taca **não** para a dois raios medidos ao longo da mira: ela para
## quando os dois centros ficam a duas bolas de distância, e no triângulo formado
## pela linha de mira, pela perpendicular e pela linha dos centros isso é
## Pitágoras. Na batida frontal os dois números coincidem — é de raspão que eles
## se separam, e é de raspão que a seta da bola atingida muda de lado.
func _probe_aim() -> void:
	print("ponto de contato")
	var scene := await _open(PoolRules.Format.KNOCKOUT)
	var view: PoolView = scene._view
	var radius := PoolRules.BALL_RADIUS
	var touch := radius * 2.0

	# Frontal: a do adversário um pouco à direita da nossa, na mesma altura.
	_place(scene, Vector2(0.4, 0.5), Vector2(1.0, 0.5))
	var head := view._impact(Vector2.RIGHT)
	_equals(head["ball"], 1, "a bola em frente é a atingida")
	_near(head["stop"], 0.6 - touch, "e na batida frontal ela para a duas bolas")

	# De raspão: a bola deslocada de um raio para o lado. O cateto que falta é
	# sqrt((2r)² - r²) = r·sqrt(3), e não 2r — a diferença é de meio raio.
	_place(scene, Vector2(0.4, 0.5), Vector2(1.0, 0.5 + radius))
	var clip := view._impact(Vector2.RIGHT)
	_equals(clip["ball"], 1, "de raspão ela continua sendo a atingida")
	_near(clip["stop"], 0.6 - radius * sqrt(3.0), "e a tacadeira para mais tarde que a dois raios")
	_check(float(clip["stop"]) > 0.6 - touch, "que é depois de onde a conta ingênua a punha")

	# Fora do corredor: passa raspando por fora e não conta como batida.
	_place(scene, Vector2(0.4, 0.5), Vector2(1.0, 0.5 + touch * 1.05))
	_equals(view._impact(Vector2.RIGHT)["ball"], -1, "e o que passa por fora não é batida")

	scene.free()


## A branca na mão recusa lugar ocupado. É a única validação de posição do jogo, e
## sem ela dá para largar a branca dentro de outra bola — as duas explodem no
## primeiro passo da simulação.
##
## Só na brasileira: sem tacadeira não há o que pôr de volta.
func _probe_hand() -> void:
	print("branca na mão")
	var knockout := await _open(PoolRules.Format.KNOCKOUT)
	knockout._state.meta[PoolRules.HAND] = 1
	_check(
		not PoolRules.ball_in_hand(knockout._state),
		"no mata-mata não existe branca na mão, nem marcada à força"
	)
	knockout.free()

	var scene := await _open(PoolRules.Format.BRAZILIAN)
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
		scene._rules.validate(scene._state, PoolRules.shot(0, Vector2.RIGHT, 1.0).path) == null,
		"e tacar antes de pôr, não"
	)
	scene.free()


# --- utilidades ---------------------------------------------------------------


func _open(wanted: int) -> Node:
	Game.pool_format = wanted
	var scene := MATCH_SCENE.instantiate()
	add_child(scene)
	await get_tree().process_frame
	# Um quadro não basta: a mesa é desenhada depois do primeiro `_layout`, e o
	# gesto depende da escala que ele calcula.
	await get_tree().process_frame
	return scene


## Uma mesa de duas bolas, posta à mão: a primeira é nossa e a segunda do
## adversário. As sondas de mira não querem o arranjo inicial — elas querem uma
## geometria que dê para conferir com uma conta de papel.
func _place(scene: Node, mine: Vector2, theirs: Vector2) -> void:
	scene._state.meta[PoolRules.POS] = PackedFloat64Array([
		mine.x, mine.y, theirs.x, theirs.y
	])
	scene._state.meta[PoolRules.LIVE] = PackedByteArray([1, 1])
	scene._state.meta[PoolRules.KIND] = PackedInt32Array([0, 1])
	scene._view._shooter = 0
	scene._view.state = scene._state


func _near(actual: float, expected: float, label: String) -> void:
	_check(
		absf(actual - expected) < 0.0005,
		"%s (esperado %.4f, obtido %.4f)" % [label, expected, actual]
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
