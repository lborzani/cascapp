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
##
## E os dois formatos discordam no que é uma tacadeira, então quase todo teste
## aqui existe em duas versões: com branca e sem.

const RulesLib := preload("res://core/pool_rules.gd")

var _failures := 0


func _initialize() -> void:
	_test_rack()
	_test_settles()
	_test_stays_on_cloth()
	_test_deterministic()
	_test_pocket()
	_test_knockout()
	_test_brazilian()
	_test_replay()
	_test_bot()

	if _failures == 0:
		print("OK — sinuca consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _test_rack() -> void:
	print("mesa montada")
	var knockout := _rules(PoolRules.Format.KNOCKOUT).initial_state()
	_equals(
		PoolRules.ball_count(knockout), PoolRules.KNOCKOUT_PER_GROUP * 2,
		"o mata-mata é cinco contra cinco, e mais nada"
	)
	_check(not PoolRules.has_cue_ball(knockout), "sem tacadeira")
	_equals(PoolRules.cue_ball(knockout), -1, "e sem branca nenhuma")
	_equals(PoolRules.balls_left(knockout, 0), 5, "cinco de uma cor")
	_equals(PoolRules.balls_left(knockout, 1), 5, "cinco da outra")
	_equals(PoolRules.group_of(0), 0, "o assento 0 joga com as primeiras")
	_equals(PoolRules.group_of(1), 1, "e o assento 1 com as outras")

	# Quem taca escolhe entre as **próprias**, e são cinco desde a primeira vez.
	_equals(PoolRules.shootable(knockout).size(), 5, "e ele escolhe entre cinco")
	_check(
		PoolRules.can_shoot_with(knockout, 0, 0) and not PoolRules.can_shoot_with(knockout, 0, 5),
		"nunca com uma do adversário"
	)

	var brazilian := _rules(PoolRules.Format.BRAZILIAN).initial_state()
	_equals(PoolRules.ball_count(brazilian), 8, "a brasileira tem branca e sete")
	_check(PoolRules.has_cue_ball(brazilian), "com tacadeira")
	_equals(PoolRules.shootable(brazilian), PackedInt32Array([0]), "e só ela taca")
	_equals(
		PoolRules.kind_of_ball(brazilian, PoolRules.target_ball(brazilian)), 1,
		"a bola da vez começa sendo a vermelha"
	)

	# Nenhuma bola nasce em cima de outra nem dentro de uma caçapa: as duas coisas
	# explodem no primeiro passo da simulação.
	for wanted in [knockout, brazilian]:
		var bad := ""
		for a in PoolRules.ball_count(wanted):
			for b in range(a + 1, PoolRules.ball_count(wanted)):
				var apart := PoolRules.position_of(wanted, a).distance_to(
					PoolRules.position_of(wanted, b)
				)
				if apart < PoolRules.BALL_RADIUS * 1.99:
					bad = "bolas %d e %d a %.3f" % [a, b, apart]
			for pocket: Vector2 in PoolRules.POCKETS:
				if PoolRules.position_of(wanted, a).distance_to(pocket) < PoolRules.POCKET_RADIUS:
					bad = "bola %d nasce dentro de uma caçapa" % a
		_check(bad.is_empty(), "nenhuma bola nasce em cima de outra nem no buraco (%s)" % [
			"ok" if bad.is_empty() else bad
		])


## A mesa para, e para dentro do teto de passos.
func _test_settles() -> void:
	print("a mesa para")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var state := rules.initial_state()
	rules.apply_move(state, PoolRules.shot(0, Vector2.RIGHT, 1.0))
	_check(true, "a tacada mais forte da mesa termina")
	_equals(state.ply, 1, "e conta como um lance")


func _test_stays_on_cloth() -> void:
	print("as bolas ficam no pano")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var state := rules.initial_state()
	for angle in 14:
		if PoolRules.winner_of(state) >= 0:
			break
		var mine := PoolRules.shootable(state)
		if mine.is_empty():
			break
		var direction := Vector2(cos(float(angle) * 0.52), sin(float(angle) * 0.52))
		rules.apply_move(state, PoolRules.shot(mine[angle % mine.size()], direction, 1.0))

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
	_check(escaped.is_empty(), "nenhuma atravessou a tabela (%s)" % [
		"ok" if escaped.is_empty() else escaped
	])


## A mesma tacada na mesma mesa dá a mesma mesa. É a propriedade em que a rede
## inteira se apoia — o que viaja é a causa.
func _test_deterministic() -> void:
	print("a mesma tacada dá a mesma mesa")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var first := rules.initial_state()
	var second := rules.initial_state()
	var move := PoolRules.shot(1, Vector2(0.97, 0.21), 0.85)
	rules.apply_move(first, move)
	rules.apply_move(second, move)

	var same := true
	for ball in PoolRules.ball_count(first):
		if PoolRules.position_of(first, ball) != PoolRules.position_of(second, ball):
			same = false
		if PoolRules.is_live(first, ball) != PoolRules.is_live(second, ball):
			same = false
	_check(same, "as dez bolas param no mesmo lugar, bit a bit")

	# E uma tacada um milésimo diferente **não** dá a mesma mesa: se desse, a
	# quantização estaria grossa demais para o jogo ter mira.
	var nudged := rules.initial_state()
	var other := Move.new()
	other.path = move.path.duplicate()
	other.path[3] += 40
	rules.apply_move(nudged, other)
	var differs := false
	for ball in PoolRules.ball_count(first):
		if PoolRules.position_of(first, ball) != PoolRules.position_of(nudged, ball):
			differs = true
	_check(differs, "e uma mira diferente dá uma mesa diferente")


func _test_pocket() -> void:
	print("caçapa")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	# A bola do adversário alinhada com a caçapa do meio de cima, e uma nossa em
	# coluna com ela. Mesa armada à mão: uma tacada de saída não garante nada.
	var state := _rig(rules, [Vector2(1.0, 0.70), Vector2(1.0, 0.25)], [0, 1])
	rules.apply_move(state, PoolRules.shot(0, Vector2.UP, 0.6))
	_check(not PoolRules.is_live(state, 1), "a bola alinhada com a boca entra")
	_equals(PoolRules.winner_of(state), 0, "e limpar o grupo do outro ganha a partida")

	# Bater em nada é falta: sem isso, tacar para o vazio seria uma forma grátis de
	# passar a vez com a mesa arrumada.
	var whiff := _rig(rules, [Vector2(1.0, 0.5), Vector2(0.2, 0.9)], [0, 1])
	rules.apply_move(whiff, PoolRules.shot(0, Vector2.RIGHT, 0.35))
	_equals(PoolRules.turn_of(whiff), 1, "tacada que não acerta ninguém passa a vez")


func _test_knockout() -> void:
	print("mata-mata")
	var rules := _rules(PoolRules.Format.KNOCKOUT)

	# Bater primeiro numa bola **sua** é falta: sem isso, empurrar as próprias para
	# perto das caçapas seria uma tacada grátis.
	var wrong := _rig(
		rules,
		[Vector2(0.3, 0.5), Vector2(0.9, 0.5), Vector2(1.6, 0.5)],
		[0, 0, 1]
	)
	rules.apply_move(wrong, PoolRules.shot(0, Vector2.RIGHT, 0.7))
	_equals(PoolRules.turn_of(wrong), 1, "bater primeiro na própria cor passa a vez")

	# Encaçapar uma bola **sua** é um tiro no pé: ela sai do jogo e aproxima o
	# adversário do fim. A regra não precisa dizer nada além disso.
	var own := _rig(rules, [Vector2(1.0, 0.25), Vector2(0.4, 0.5)], [0, 1])
	rules.apply_move(own, PoolRules.shot(0, Vector2.UP, 0.6))
	_check(not PoolRules.is_live(own, 0), "a bola própria encaçapada sai do jogo")
	_equals(PoolRules.winner_of(own), 1, "e ficar sem bolas é perder")

	# Continua tacando quem matou uma do adversário.
	var again := _rig(
		rules, [Vector2(1.0, 0.70), Vector2(1.0, 0.25), Vector2(0.3, 0.8)], [0, 1, 1]
	)
	rules.apply_move(again, PoolRules.shot(0, Vector2.UP, 0.6))
	_check(not PoolRules.is_live(again, 1), "a do adversário entrou")
	_equals(PoolRules.turn_of(again), 0, "e quem matou taca de novo")
	_equals(PoolRules.winner_of(again), -1, "com a partida ainda de pé")


func _test_brazilian() -> void:
	print("brasileira")
	var rules := _rules(PoolRules.Format.BRAZILIAN)

	# Bater na bola errada é falta, e a falta entrega sete ao adversário.
	var wrong := _rig(
		rules, [Vector2(1.0, 0.5), Vector2(0.2, 0.5), Vector2(1.9, 0.5)], [0, 1, 2]
	)
	rules.apply_move(wrong, PoolRules.shot(0, Vector2.RIGHT, 0.6))
	_equals(PoolRules.score_of(wrong, 1), PoolRules.FOUL_POINTS, "bater na errada dá sete ao outro")
	_equals(PoolRules.turn_of(wrong), 1, "e passa a vez")
	_check(PoolRules.ball_in_hand(wrong), "com a branca na mão do adversário")

	# Encaçapar a bola da vez conta o valor dela e devolve a tacada.
	var clean := _rig(rules, [Vector2(1.0, 0.70), Vector2(1.0, 0.25)], [0, 3])
	rules.apply_move(clean, PoolRules.shot(0, Vector2.UP, 0.6))
	_equals(PoolRules.score_of(clean, 0), 3, "a bola da vez vale o número dela")
	_equals(PoolRules.turn_of(clean), 0, "e quem a encaçapou taca de novo")
	_equals(PoolRules.winner_of(clean), 0, "mesa limpa, vence quem tem mais ponto")

	# A branca sempre volta: ela é o taco, não um alvo.
	var suicide := _rig(rules, [Vector2(1.0, 0.25), Vector2(0.3, 0.80)], [0, 1])
	rules.apply_move(suicide, PoolRules.shot(0, Vector2.UP, 0.6))
	_check(PoolRules.is_live(suicide, 0), "a branca volta para a mesa")
	_equals(PoolRules.turn_of(suicide), 1, "a vez passa")
	_check(PoolRules.ball_in_hand(suicide), "e o adversário fica com ela na mão")


## Repetir o histórico reconstrói a partida. É o que faz a reconexão da sinuca ser
## a mesma dos outros jogos — e ela só funciona porque o lance é a **causa**.
func _test_replay() -> void:
	print("replay do histórico")
	for wanted: int in [PoolRules.Format.KNOCKOUT, PoolRules.Format.BRAZILIAN]:
		var rules := _rules(wanted)
		var played := rules.initial_state()
		for _each in 6:
			if PoolRules.winner_of(played) >= 0:
				break
			var move := rules.best_move(played, rules.generate_moves(played))
			if move == null:
				break
			rules.apply_move(played, move)

		var rebuilt := rules.initial_state()
		var ok := true
		for entry: Dictionary in played.history:
			var move := rules.validate(rebuilt, PackedInt32Array(entry.get("p", [])))
			if move == null:
				ok = false
				break
			rules.apply_move(rebuilt, move)
		_check(ok, "cada lance do histórico ainda é legal na reconstrução")
		if not ok:
			continue

		var same := true
		for ball in PoolRules.ball_count(played):
			if PoolRules.position_of(played, ball) != PoolRules.position_of(rebuilt, ball):
				same = false
		_check(same, "e a mesa reconstruída é a mesma, bola por bola")
		_equals(PoolRules.turn_of(rebuilt), PoolRules.turn_of(played), "com a mesma vez")


func _test_bot() -> void:
	print("bot")
	var rules := _rules(PoolRules.Format.KNOCKOUT)
	var state := _rig(
		rules, [Vector2(1.0, 0.70), Vector2(1.0, 0.25), Vector2(0.3, 0.8)], [0, 1, 1]
	)
	var move := rules.best_move(state, rules.generate_moves(state))
	_check(move != null, "o bot escolhe alguma tacada")
	if move == null:
		return
	_check(
		PoolRules.can_shoot_with(state, 0, PoolRules.ball_of(move)),
		"e ele taca com uma bola dele"
	)
	rules.apply_move(state, move)
	_check(not PoolRules.is_live(state, 1), "e acha a do adversário que está na boca")


# --- utilidades ---------------------------------------------------------------


func _rules(wanted: int) -> PoolRules:
	var rules := PoolRules.new()
	rules.format = wanted
	return rules


## Uma mesa armada à mão: posições e espécies. Na brasileira o índice 0 é a
## branca, no mata-mata ele é uma bola de jogador como qualquer outra.
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
