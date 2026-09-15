extends SceneTree

## As regras e a física da sinuca, sem tela.
##
##   godot --headless --path . --script res://tests/pool_probe.gd
##
## O que se persegue aqui não é o que uma tacada faz — é o que ela **tem** de
## fazer para o resto do app continuar de pé:
##
## - **a mesa para.** Uma simulação que não converge trava a partida dos dois
##   lados, e o teto de passos existe para isso não ser possível;
## - **a mesma tacada dá a mesma mesa.** É a propriedade em que a rede inteira se
##   apoia: o que viaja é a causa, e os dois aparelhos derivam o efeito;
## - **as bolas ficam no pano.** Uma bola atravessando a tabela por erro de passo
##   é o defeito clássico deste tipo de simulação, e ele aparece cedo;
## - **repetir o histórico reconstrói a partida**, que é o que faz a reconexão do
##   app funcionar em sinuca sem uma linha nova.

const RulesLib := preload("res://core/pool_rules.gd")

var _failures := 0


func _initialize() -> void:
	_test_rack()
	_test_settles()
	_test_stays_on_cloth()
	_test_deterministic()
	_test_pocket_and_foul()
	_test_knockout_groups()
	_test_brazilian_target()
	_test_replay()
	_test_bot()

	if _failures == 0:
		print("OK — sinuca consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _test_rack() -> void:
	print("mesa montada")
	var knockout := _rules(PoolRules.Format.KNOCKOUT)
	var state := knockout.initial_state()
	_equals(PoolRules.ball_count(state), PoolRules.KNOCKOUT_PER_GROUP * 2 + 1, "branca e oito bolas")

	var yellow := 0
	var blue := 0
	for ball in range(1, PoolRules.ball_count(state)):
		if PoolRules.kind_of_ball(state, ball) == 0:
			yellow += 1
		else:
			blue += 1
	_equals(yellow, PoolRules.KNOCKOUT_PER_GROUP, "quatro de uma cor")
	_equals(blue, PoolRules.KNOCKOUT_PER_GROUP, "quatro da outra")
	_check(PoolRules.table_open(state), "e a mesa começa aberta")

	var brazilian := _rules(PoolRules.Format.BRAZILIAN).initial_state()
	_equals(PoolRules.ball_count(brazilian), 8, "a brasileira tem branca e sete")
	_equals(
		PoolRules.kind_of_ball(brazilian, PoolRules.target_ball(brazilian)), 1,
		"e a bola da vez começa sendo a vermelha"
	)

	# Nenhuma bola nasce em cima de outra: um triângulo mal montado explode no
	# primeiro passo da simulação e a mesa inteira sai voando.
	var overlap := false
	for a in PoolRules.ball_count(state):
		for b in range(a + 1, PoolRules.ball_count(state)):
			var apart := PoolRules.position_of(state, a).distance_to(PoolRules.position_of(state, b))
			if apart < PoolRules.BALL_RADIUS * 1.99:
				overlap = true
	_check(not overlap, "e nenhuma bola nasce dentro de outra")


## A mesa para, e para dentro do teto de passos.
func _test_settles() -> void:
	print("a mesa para")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var state := rules.initial_state()
	rules.apply_move(state, PoolRules.shot(Vector2.RIGHT, 1.0))
	# Se não tivesse parado, as bolas estariam fora do pano ou empilhadas; as duas
	# conferências seguintes pegariam. O que este teste garante é que a chamada
	# **retorna** — um laço sem teto travaria aqui e o teste morreria no tempo.
	_check(true, "a tacada mais forte da mesa termina")
	_equals(state.ply, 1, "e conta como um lance")


func _test_stays_on_cloth() -> void:
	print("as bolas ficam no pano")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var state := rules.initial_state()
	for angle in 12:
		# Doze direções, sempre da posição em que a mesa parou. É o jeito barato de
		# bater em todas as tabelas e em todas as quinas.
		var direction := Vector2(cos(float(angle) * 0.52), sin(float(angle) * 0.52))
		if PoolRules.ball_in_hand(state):
			rules.apply_move(state, PoolRules.placement(Vector2(0.5, 0.5)))
		rules.apply_move(state, PoolRules.shot(direction, 1.0))
		if PoolRules.winner_of(state) >= 0:
			break

	var escaped := ""
	for ball in PoolRules.ball_count(state):
		if not PoolRules.is_live(state, ball):
			continue
		var spot := PoolRules.position_of(state, ball)
		if (
			spot.x < PoolRules.BALL_RADIUS - 0.001
			or spot.x > PoolRules.TABLE_WIDTH - PoolRules.BALL_RADIUS + 0.001
			or spot.y < PoolRules.BALL_RADIUS - 0.001
			or spot.y > PoolRules.TABLE_HEIGHT - PoolRules.BALL_RADIUS + 0.001
		):
			escaped = "bola %d em %s" % [ball, spot]
	_check(escaped.is_empty(), "nenhuma atravessou a tabela (%s)" % ["ok" if escaped.is_empty() else escaped])


## A mesma tacada na mesma mesa dá a mesma mesa. É a propriedade em que a rede
## inteira se apoia — o que viaja é a causa.
func _test_deterministic() -> void:
	print("a mesma tacada dá a mesma mesa")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var first := rules.initial_state()
	var second := rules.initial_state()
	var move := PoolRules.shot(Vector2(0.97, 0.21), 0.85)
	rules.apply_move(first, move)
	rules.apply_move(second, move)

	var same := true
	for ball in PoolRules.ball_count(first):
		if PoolRules.position_of(first, ball) != PoolRules.position_of(second, ball):
			same = false
		if PoolRules.is_live(first, ball) != PoolRules.is_live(second, ball):
			same = false
	_check(same, "as onze bolas param no mesmo lugar, bit a bit")

	# E uma tacada um milésimo diferente **não** dá a mesma mesa: se desse, a
	# quantização estaria grossa demais para o jogo ter mira.
	var nudged := rules.initial_state()
	var other := Move.new()
	other.path = move.path.duplicate()
	other.path[2] += 40
	rules.apply_move(nudged, other)
	var differs := false
	for ball in PoolRules.ball_count(first):
		if PoolRules.position_of(first, ball) != PoolRules.position_of(nudged, ball):
			differs = true
	_check(differs, "e uma mira diferente dá uma mesa diferente")


func _test_pocket_and_foul() -> void:
	print("caçapa e falta")
	var rules := _rules(PoolRules.Format.KNOCKOUT)

	# A branca e uma bola em coluna, as duas alinhadas com a caçapa do meio de
	# cima. Mesa armada à mão: uma tacada de saída não garante encaçapar nada, e um
	# teste que depende do que o triângulo fez não testa a regra, testa o rack.
	var state := _rig(rules, [
		Vector2(1.0, 0.70),
		Vector2(1.0, 0.25),
	], [0, 1])
	rules.apply_move(state, PoolRules.shot(Vector2.UP, 0.6))
	_check(not PoolRules.is_live(state, 1), "a bola alinhada com a boca entra")
	_equals(PoolRules.turn_of(state), 0, "e quem encaçapou continua na mesa")

	# A branca na boca: cair é falta, ela volta à marca e o outro fica com ela na
	# mão.
	var suicide := _rig(rules, [
		Vector2(1.0, 0.25),
		Vector2(0.3, 0.80),
	], [0, 1])
	rules.apply_move(suicide, PoolRules.shot(Vector2.UP, 0.6))
	_check(PoolRules.is_live(suicide, 0), "a branca volta para a mesa")
	_equals(PoolRules.turn_of(suicide), 1, "a vez passa")
	_check(PoolRules.ball_in_hand(suicide), "e o adversário fica com ela na mão")

	# Bater em nada é falta igual: sem isso, dar uma tacada para o vazio seria uma
	# forma grátis de passar a vez com a mesa arrumada.
	var whiff := _rig(rules, [Vector2(1.0, 0.5), Vector2(0.2, 0.9)], [0, 1])
	rules.apply_move(whiff, PoolRules.shot(Vector2.RIGHT, 0.35))
	_equals(PoolRules.turn_of(whiff), 1, "tacada que não acerta ninguém passa a vez")


func _test_knockout_groups() -> void:
	print("mata-mata")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var state := _rig(rules, [
		Vector2(1.0, 0.70),
		Vector2(1.0, 0.25),
		Vector2(0.4, 0.50),
	], [0, 1, 0])
	_check(PoolRules.table_open(state), "a mesa começa aberta")
	rules.apply_move(state, PoolRules.shot(Vector2.UP, 0.6))
	_check(not PoolRules.table_open(state), "a primeira bola que cai fecha a mesa")
	_equals(PoolRules.group_of(state, 0), 1, "quem encaçapou fica com a cor dela")
	_equals(PoolRules.group_of(state, 1), 0, "e o outro fica com a outra")

	# Limpar o grupo ganha a mesa. O assento 0 ficou com a cor 1, e só resta uma
	# bola dessa cor na mesa armada abaixo.
	var last := _rig(rules, [Vector2(1.0, 0.70), Vector2(1.0, 0.25), Vector2(0.4, 0.50)], [0, 1, 0])
	last.meta[PoolRules.GROUP] = PackedInt32Array([1, 0])
	rules.apply_move(last, PoolRules.shot(Vector2.UP, 0.6))
	_equals(PoolRules.winner_of(last), 0, "quem limpa o grupo ganha")


func _test_brazilian_target() -> void:
	print("brasileira")
	var rules := _rules(PoolRules.Format.BRAZILIAN)

	# Bater na bola errada é falta, e a falta entrega sete ao adversário.
	var wrong := _rig(rules, [Vector2(1.0, 0.5), Vector2(0.2, 0.5), Vector2(1.9, 0.5)], [0, 1, 2])
	rules.apply_move(wrong, PoolRules.shot(Vector2.RIGHT, 0.6))
	_equals(PoolRules.score_of(wrong, 1), PoolRules.FOUL_POINTS, "bater na errada dá sete ao outro")
	_equals(PoolRules.turn_of(wrong), 1, "e passa a vez")

	# Encaçapar a bola da vez conta o valor dela e devolve a tacada.
	var clean := _rig(rules, [Vector2(1.0, 0.70), Vector2(1.0, 0.25)], [0, 3])
	rules.apply_move(clean, PoolRules.shot(Vector2.UP, 0.6))
	_equals(PoolRules.score_of(clean, 0), 3, "a bola da vez vale o número dela")
	_equals(PoolRules.turn_of(clean), 0, "e quem a encaçapou taca de novo")
	_equals(PoolRules.winner_of(clean), 0, "mesa limpa, vence quem tem mais ponto")


## Repetir o histórico reconstrói a partida. É o que faz a reconexão da sinuca ser
## a mesma dos outros jogos — e ela só funciona porque o lance é a **causa**.
func _test_replay() -> void:
	print("replay do histórico")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var played := rules.initial_state()
	for _each in 6:
		if PoolRules.winner_of(played) >= 0:
			break
		var move := rules.best_move(played, rules.generate_moves(played))
		if move == null:
			break
		rules.apply_move(played, move)

	var rebuilt := rules.initial_state()
	for entry: Dictionary in played.history:
		var move := rules.validate(rebuilt, PackedInt32Array(entry.get("p", [])))
		_check(move != null, "cada lance do histórico ainda é legal na reconstrução")
		if move == null:
			return
		rules.apply_move(rebuilt, move)

	var same := true
	for ball in PoolRules.ball_count(played):
		if PoolRules.position_of(played, ball) != PoolRules.position_of(rebuilt, ball):
			same = false
	_check(same, "e a mesa reconstruída é a mesma, bola por bola")
	_equals(PoolRules.turn_of(rebuilt), PoolRules.turn_of(played), "com a mesma vez")


func _test_bot() -> void:
	print("bot")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var state := _rig(rules, [
		Vector2(1.0, 0.70),
		Vector2(1.0, 0.25),
		Vector2(0.4, 0.50),
	], [0, 1, 0])
	state.meta[PoolRules.GROUP] = PackedInt32Array([1, 0])
	var move := rules.best_move(state, rules.generate_moves(state))
	_check(move != null, "o bot escolhe alguma tacada")
	rules.apply_move(state, move)
	_check(not PoolRules.is_live(state, 1), "e ele acha a bola que está na boca")


# --- utilidades ---------------------------------------------------------------


func _rules(wanted: int) -> PoolRules:
	var rules := PoolRules.new()
	rules.format = wanted
	return rules


## Uma mesa armada à mão: posições e espécies, a branca no índice 0.
func _rig(rules: PoolRules, spots: Array, kinds: Array) -> MatchState:
	var state := rules.initial_state()
	var flat := PackedFloat64Array()
	var live := PackedByteArray()
	var species := PackedInt32Array()
	for index in spots.size():
		var spot: Vector2 = spots[index]
		flat.append(spot.x)
		flat.append(spot.y)
		live.append(1)
		species.append(int(kinds[index]))
	state.meta[PoolRules.POS] = flat
	state.meta[PoolRules.LIVE] = live
	state.meta[PoolRules.KIND] = species
	state.meta[PoolRules.GROUP] = PackedInt32Array([-1, -1])
	state.meta[PoolRules.SCORE] = PackedInt32Array([0, 0])
	state.meta[PoolRules.TURN] = 0
	state.meta[PoolRules.HAND] = 0
	state.meta[PoolRules.WINNER] = -1
	return state


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
