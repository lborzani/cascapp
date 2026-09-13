extends SceneTree

## A predição e a reconciliação do cliente de Bomberman, sem tela e sem rede.
##
##   godot --headless --path . --script res://tests/bomber_predict_probe.gd
##
## É o teste mais importante da rede nova. A predição só é honesta se, depois de
## receber os comandos verdadeiros, o cliente chegar **exatamente** ao mesmo estado
## que o servidor — bit a bit, não "perto". Um erro de uma unidade no quinto
## segundo vira um boneco vivo de um lado e morto do outro, sem nada apontando pra
## causa. Por isso o teste central compara o estado inteiro contra uma simulação de
## referência rodada direta.

var _failures := 0
var _rules := BomberRules.new()


func _initialize() -> void:
	_test_convergence()
	_test_own_drift_zero()
	_test_remote_bomb_not_predicted()
	_test_snapshot_ahead_adopts()

	if _failures == 0:
		print("OK — predição de Bomberman consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


## O coração: prever N tiques só com o próprio dedo, receber os comandos
## verdadeiros dos outros, reconciliar, e bater bit a bit com a referência.
func _test_convergence() -> void:
	print("convergência exata")
	const N := 40
	var truth := _rules.initial_state(4, 314159)
	var rows := _script_rows(N)
	var history: Array[BomberState] = [truth.clone()]
	for t in range(1, N + 1):
		_rules.step(truth, rows[t])
		history.append(truth.clone())

	# O cliente é o assento 0. Adota o estado inicial e prevê até N só com o próprio
	# comando; os outros ele chuta (repete movimento, sem bomba).
	var client := BomberPredictor.new(_rules, 0)
	client.note_seats(PackedStringArray(["Ana", "Beto", "Cid", "Dan"]))
	client.adopt(history[0])
	for t in range(1, N + 1):
		client.advance(rows[t][0])
	_equals(client.tick, N, "o cliente previu até o tique N")

	# Agora chegam os comandos verdadeiros de todo mundo e um snapshot antigo. A
	# reconciliação refaz o caminho com a verdade.
	client.note(1, rows.slice(1, N + 1))
	var replayed := client.reconcile(history[0])
	_check(replayed == N, "reexecutou os N tiques (foram %d)" % replayed)
	_check(_same(client.state, history[N], "convergência"), "o estado bate bit a bit com a referência")


## O próprio boneco nunca é corrigido quando nada remoto o afeta: só o assento 0
## se move, os outros ficam parados e ninguém solta bomba. `drift` tem de ser zero.
func _test_own_drift_zero() -> void:
	print("o próprio dedo não é chute")
	const N := 30
	var truth := _rules.initial_state(4, 271828)
	var rows: Array = []
	rows.append(PackedByteArray([0, 0, 0, 0]))
	for t in range(1, N + 1):
		# Assento 0 anda pra direita e pra baixo alternado; os outros, parados.
		var move := BomberRules.IN_RIGHT if t % 2 == 0 else BomberRules.IN_DOWN
		rows.append(PackedByteArray([move, 0, 0, 0]))
	var history: Array[BomberState] = [truth.clone()]
	for t in range(1, N + 1):
		_rules.step(truth, rows[t])
		history.append(truth.clone())

	var client := BomberPredictor.new(_rules, 0)
	client.note_seats(PackedStringArray(["Ana", "Beto", "Cid", "Dan"]))
	client.adopt(history[0])
	for t in range(1, N + 1):
		client.advance(rows[t][0])

	client.note(1, rows.slice(1, N + 1))
	client.reconcile(history[0])
	_equals(client.drift, 0, "o assento local não escorregou")
	_check(_same(client.state, history[N], "isolado"), "e ainda bate com a referência")


## Bomba de remoto não entra na predição até o servidor confirmar. Antes de
## `note`/`reconcile`, o estado previsto não tem a bomba do assento 1; depois, tem.
func _test_remote_bomb_not_predicted() -> void:
	print("bomba de outro só quando confirmada")
	const N := 6
	var truth := _rules.initial_state(4, 42)
	# O assento 1 solta bomba no tique 1 e fica parado; o resto, parado.
	var rows: Array = [PackedByteArray([0, 0, 0, 0])]
	for t in range(1, N + 1):
		var one := BomberRules.IN_BOMB if t == 1 else 0
		rows.append(PackedByteArray([0, one, 0, 0]))
	var history: Array[BomberState] = [truth.clone()]
	for t in range(1, N + 1):
		_rules.step(truth, rows[t])
		history.append(truth.clone())
	_check(_bombs_of(history[N], 1) > 0, "a referência tem a bomba do assento 1")

	var client := BomberPredictor.new(_rules, 0)
	client.note_seats(PackedStringArray(["Ana", "Beto", "Cid", "Dan"]))
	client.adopt(history[0])
	for t in range(1, N + 1):
		client.advance(rows[t][0])  # o cliente é o 0, não sabe o comando do 1
	_equals(_bombs_of(client.state, 1), 0, "sem confirmação, nenhuma bomba-fantasma do 1")

	client.note(1, rows.slice(1, N + 1))
	client.reconcile(history[0])
	_check(_bombs_of(client.state, 1) > 0, "confirmada, a bomba do assento 1 aparece")


## Snapshot mais novo que o cliente: não há o que reexecutar, adota e segue.
func _test_snapshot_ahead_adopts() -> void:
	print("snapshot à frente é adotado")
	var client := BomberPredictor.new(_rules, 0)
	client.note_seats(PackedStringArray(["Ana", "Beto", "Cid", "Dan"]))
	var early := _rules.initial_state(4, 5)
	client.adopt(early)
	client.advance(BomberRules.IN_UP)  # tique 1

	var ahead := early.clone()
	for t in 10:
		_rules.step(ahead, PackedByteArray([0, 0, 0, 0]))  # servidor no tique 10
	var replayed := client.reconcile(ahead)
	_equals(replayed, 0, "nada a reexecutar")
	_equals(client.tick, ahead.tick, "o cliente saltou pro tique do servidor")


# --- utilidades --------------------------------------------------------------


## Uma sequência de comandos determinística e movimentada: todos andam e soltam
## bomba de vez em quando, pra a reconciliação ter bombas e fogo pra reproduzir.
func _script_rows(n: int) -> Array:
	var rows: Array = [PackedByteArray([0, 0, 0, 0])]
	var dirs := [BomberRules.IN_UP, BomberRules.IN_DOWN, BomberRules.IN_LEFT, BomberRules.IN_RIGHT]
	for t in range(1, n + 1):
		var row := PackedByteArray()
		row.resize(4)
		for seat in 4:
			var command: int = dirs[(t + seat) % 4]
			if (t + seat) % 7 == 0:
				command |= BomberRules.IN_BOMB
			row[seat] = command
		rows.append(row)
	return rows


func _bombs_of(state: BomberState, owner: int) -> int:
	var count := 0
	for bomb in state.bombs:
		if bomb.owner == owner:
			count += 1
	return count


## Igualdade bit a bit entre dois estados. Imprime o primeiro campo que diverge.
func _same(a: BomberState, b: BomberState, label: String) -> bool:
	if a.tick != b.tick or a.seed_state != b.seed_state:
		printerr("  [%s] tique/semente divergem" % label)
		return false
	if a.tiles != b.tiles or a.prizes != b.prizes or a.flames != b.flames:
		printerr("  [%s] mapa/prêmios/fogo divergem" % label)
		return false
	if a.players.size() != b.players.size() or a.bombs.size() != b.bombs.size():
		printerr("  [%s] contagem de jogadores/bombas diverge" % label)
		return false
	for seat in a.players.size():
		var one := a.players[seat]
		var two := b.players[seat]
		if (one.x != two.x or one.y != two.y or one.facing != two.facing
			or one.alive != two.alive or one.died_at != two.died_at
			or one.bombs != two.bombs or one.flame != two.flame or one.speed != two.speed):
			printerr("  [%s] jogador %d diverge (pos %d,%d vs %d,%d)" % [label, seat, one.x, one.y, two.x, two.y])
			return false
	for index in a.bombs.size():
		var one := a.bombs[index]
		var two := b.bombs[index]
		if (one.col != two.col or one.row != two.row or one.owner != two.owner
			or one.fuse != two.fuse or one.flame != two.flame or one.pass_seats != two.pass_seats):
			printerr("  [%s] bomba %d diverge" % [label, index])
			return false
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
