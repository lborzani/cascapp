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
	await _probe_spin()
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
	view._press(view._to_screen(PoolRules.position_of(scene._state, wanted)))
	_equals(view._shooter_ball(), wanted, "tocar numa bola minha passa a tacada para ela")
	_check(not view._steering, "e não começa a mirar no mesmo toque")
	_check(view._cue.visible, "e o taco já está atrás dela")

	# Tocar numa do adversário não escolhe nada: ela não é tacável.
	var theirs := PoolRules.KNOCKOUT_PER_GROUP
	view._press(view._to_screen(PoolRules.position_of(scene._state, theirs)))
	view._release(view._to_screen(PoolRules.position_of(scene._state, theirs)))
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
	view.shot_aimed.connect(func(ball: int, direction: Vector2, power: float, spin: Vector2) -> void:
		sent.append([ball, direction, power, spin])
	)

	# Lido **antes** do arrasto: `_play` aplica o lance no mesmo quadro em que o
	# gesto termina, e só depois começa a esperar a animação. Ler a posição entre
	# as duas coisas é ler a mesa já resolvida e concluir que nada se mexeu.
	var shooter := view._shooter_ball()
	var before := PoolRules.position_of(scene._state, shooter)

	var cue := view._cue_screen()
	_check(view._cue.visible, "na vez, o taco aparece sem ninguém tocar")
	# Mirar: tocar na mesa à direita da bola aponta o taco para lá, e não taca. (À
	# esquerda não: a bola nasce encostada na tabela, e ali ao lado está a barra.)
	view._press(cue + Vector2(120.0, 0.0))
	view._release(cue + Vector2(120.0, 0.0))
	_equals(sent.size(), 0, "mirar sozinho não taca")
	_check(view._aim.x > 0.9, "e o taco aponta para o dedo")
	# Força: puxar a barra até embaixo e soltar.
	var bar := view._bar_rect()
	view._press(bar.position + Vector2(bar.size.x * 0.5, 2.0))
	view._drag(bar.end - Vector2(bar.size.x * 0.5, 0.0))
	_check(view._power > 0.95, "puxar a barra até embaixo é força cheia")
	view._release(bar.end - Vector2(bar.size.x * 0.5, 0.0))
	_equals(sent.size(), 1, "soltar a barra pede uma tacada")
	if sent.is_empty():
		scene.free()
		return
	_equals(sent[0][0], shooter, "e ela diz com qual bola")
	var direction: Vector2 = sent[0][1]
	_check(direction.x > 0.9, "na direção que o taco apontava (%s)" % direction)
	_check(float(sent[0][2]) > 0.95, "com a força da barra")
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

	# A mesa 3D termina onde a regra terminou: cada bola na posição do estado, e
	# as que caíram fora da mesa. É a fita que move as bolas, e uma fita mal
	# reproduzida deixaria o desenho num lugar e a partida noutro.
	var apart := ""
	for ball in PoolRules.ball_count(scene._state):
		var node: MeshInstance3D = view._balls[ball]
		var spot := PoolRules.position_of(scene._state, ball)
		if node.visible != PoolRules.is_live(scene._state, ball):
			apart = "bola %d visível=%s" % [ball, node.visible]
		elif node.visible and node.position.distance_to(Vector3(spot.x, PoolRules.BALL_RADIUS, spot.y)) > 0.0001:
			apart = "bola %d em %s" % [ball, node.position]
	_check(apart.is_empty(), "a mesa 3D termina na mesa da regra (%s)" % [
		"ok" if apart.is_empty() else apart
	])
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


## O seletor de efeito: a bolinha abre a bola grande, o toque nela escolhe o
## ponto, tocar fora fecha, e o ponto escolhido viaja no lance.
func _probe_spin() -> void:
	print("efeito")
	var scene := await _open(PoolRules.Format.KNOCKOUT)
	var view: PoolView = scene._view
	var sent := []
	view.shot_aimed.connect(func(_ball: int, _direction: Vector2, _power: float, spin: Vector2) -> void:
		sent.append(spin)
	)

	_check(not view._spin_open, "a bola grande começa fechada")
	view._press(view._spin_icon_center())
	view._release(view._spin_icon_center())
	_check(view._spin_open, "tocar na bolinha abre a bola grande")

	# Embaixo do centro é draw: altura negativa.
	var low := view._spin_center() + Vector2(0.0, view._spin_radius() * 0.8)
	view._press(low)
	view._release(low)
	_check(view._spin.distance_to(Vector2(0.0, -0.8)) < 0.01, "tocar embaixo do centro é draw (%s)" % view._spin)
	_check(view._spin_open, "e a bola grande continua aberta para corrigir")

	# Fora do círculo o ponto para na borda.
	view._press(view._spin_center() + Vector2(view._spin_radius() * 1.1, 0.0))
	view._release(view._spin_center() + Vector2(view._spin_radius() * 1.1, 0.0))
	_check(view._spin.length() <= PoolView.SPIN_EDGE + 0.0001, "o ponto nunca sai da bola")
	_check(view._spin.x > 0.99, "e arrastar para fora deixa o ponto na borda, à direita")

	view._press(Vector2(4.0, 4.0))
	view._release(Vector2(4.0, 4.0))
	_check(not view._spin_open, "tocar fora fecha a bola grande")
	_check(view._spin.x > 0.99, "e o efeito escolhido fica")

	var bar := view._bar_rect()
	view._press(bar.position + Vector2(bar.size.x * 0.5, 2.0))
	view._release(bar.end - Vector2(bar.size.x * 0.5, bar.size.y * 0.4))
	_equals(sent.size(), 1, "soltar a barra taca")
	if not sent.is_empty():
		_check((sent[0] as Vector2).x > 0.99, "com o efeito escolhido")
	var path := PackedInt32Array(scene._state.history[-1].get("p", []))
	_check(path.size() == PoolRules.PATH_SIZE and path[PoolRules.SIDE_AT] > 990, "e o lance leva o efeito (%s)" % path)
	_equals(view._spin, Vector2.ZERO, "e o efeito volta a zero para a próxima tacada")
	await get_tree().create_timer(view.remaining_animation() + 0.6).timeout
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
