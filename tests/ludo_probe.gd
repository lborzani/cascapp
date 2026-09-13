extends Node

## Regras do Ludo, sem tela.
##
##   godot --headless --path . res://tests/ludo_probe.tscn
##
## O que está sendo verificado é a aritmética do percurso, que é onde este jogo
## erra em silêncio: uma trilha compartilhada por quatro cores, cada uma
## contando da própria saída, com captura que só existe na parte comum. Um erro
## de um na conversão progresso → casa não trava nada — só faz duas cores nunca
## se encontrarem, e ninguém repara jogando.

const RULES := preload("res://core/ludo_rules.gd")

var _failures := 0
var _rules: LudoRules = null


func _ready() -> void:
	_rules = RULES.new()
	_probe_geometry()
	_probe_opening()
	_probe_capture()
	_probe_home()
	_probe_replay()
	_probe_bot()
	await _probe_animation()
	await _probe_die()

	if _failures == 0:
		print("OK — regras do Ludo consistentes.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## As quatro saídas dividem a trilha em quatro braços iguais, e a volta fecha:
## o passo 51 de uma cor é a casa imediatamente anterior à saída dela.
func _probe_geometry() -> void:
	print("geometria da trilha")
	_equals(LudoRules.ring_square(0, 1), 0, "o primeiro passo cai na própria saída")
	_equals(LudoRules.ring_square(1, 1), 13, "e a segunda cor sai 13 casas adiante")
	_equals(LudoRules.ring_square(3, 1), 39, "a quarta, 39")
	# A volta **não** fecha, e é assim mesmo: no passo 51 a cor entra na própria
	# reta final, uma casa antes de pisar de novo na casa de onde saiu. A casa
	# imediatamente atrás da saída (índice 51 para a primeira cor) nunca é
	# visitada por ela — só pelas outras três, de passagem.
	_equals(
		LudoRules.ring_square(0, LudoRules.RING - 1), LudoRules.RING - 2,
		"o último passo da trilha para uma casa antes de fechar a volta"
	)
	_equals(
		LudoRules.ring_square(1, LudoRules.RING - 1), LudoRules.START_STEP - 2,
		"e a conta é a mesma para as outras cores"
	)
	_equals(LudoRules.ring_square(0, 0), -1, "peão na base não está em casa nenhuma")
	_equals(
		LudoRules.ring_square(0, LudoRules.RING), -1,
		"nem peão que já entrou na reta final"
	)

	# Duas cores em progressos diferentes na mesma casa é o encontro que a
	# captura precisa enxergar. A segunda cor sai 13 casas depois da primeira,
	# então o passo 14 da primeira é a saída da segunda.
	_equals(
		LudoRules.ring_square(0, 14), LudoRules.ring_square(1, 1),
		"progressos diferentes de cores diferentes caem na mesma casa"
	)
	_check(LudoRules.is_safe(0) and LudoRules.is_safe(13), "as saídas são casas seguras")
	_check(LudoRules.is_safe(8) and LudoRules.is_safe(21), "e as estrelas oito casas adiante")
	_check(not LudoRules.is_safe(5), "o resto da trilha não é")


## Com todo mundo na base, só o 6 abre a porta — e quem tira 6 joga de novo.
func _probe_opening() -> void:
	print("abertura")
	var state := _rules.initial_state()
	_equals(LudoRules.turn_of(state), 0, "a primeira cor começa")

	var three := _rules.moves_for(state, 3)
	_equals(three.size(), 1, "um dado que não é 6 tem um lance só")
	_equals(LudoRules.token_of(three[0]), LudoRules.PASS, "e esse lance é passar")

	var six := _rules.moves_for(state, 6)
	_equals(six.size(), LudoRules.TOKENS, "com 6, qualquer um dos quatro peões sai")

	_rules.apply_move(state, six[0])
	_equals(
		LudoRules.progress(state)[LudoRules.slot(0, 0)], 1,
		"sair põe o peão na casa de saída, não seis casas adiante"
	)
	_equals(LudoRules.turn_of(state), 0, "e o 6 devolve a vez a quem tirou")

	# Passar consome a vez: sem isso os dois aparelhos discordariam de quem joga.
	var passed := _rules.initial_state()
	_rules.apply_move(passed, _rules.moves_for(passed, 2)[0])
	_equals(LudoRules.turn_of(passed), 1, "passar entrega a vez à cor seguinte")


## Captura só na parte comum da trilha, e só fora das casas seguras.
func _probe_capture() -> void:
	print("captura")
	var state := _rules.initial_state()
	var prog := LudoRules.progress(state)
	# Primeira cor a três casas de uma casa comum; segunda cor parada nela.
	# A casa escolhida (passo 15 da primeira) não é saída nem estrela.
	prog[LudoRules.slot(0, 0)] = 12
	prog[LudoRules.slot(1, 0)] = 2
	state.meta[LudoRules.PROG] = prog
	_equals(
		LudoRules.ring_square(0, 15), LudoRules.ring_square(1, 2),
		"as duas cores disputam a mesma casa"
	)
	_check(not LudoRules.is_safe(LudoRules.ring_square(0, 15)), "que não é segura")

	_rules.apply_move(state, _move_for(state, 3, 0))
	_equals(
		LudoRules.progress(state)[LudoRules.slot(1, 0)], LudoRules.BASE,
		"quem estava lá volta para a base"
	)

	# Mesma colisão, agora numa saída: peão em casa segura não é capturado.
	var safe := _rules.initial_state()
	var safe_prog := LudoRules.progress(safe)
	safe_prog[LudoRules.slot(0, 0)] = 11
	safe_prog[LudoRules.slot(1, 0)] = 1
	safe.meta[LudoRules.PROG] = safe_prog
	_equals(
		LudoRules.ring_square(0, 14), LudoRules.ring_square(1, 1),
		"a colisão é na saída da segunda cor"
	)
	_rules.apply_move(safe, _move_for(safe, 3, 0))
	_equals(
		LudoRules.progress(safe)[LudoRules.slot(1, 0)], 1,
		"e lá o peão não é capturado"
	)

	# Dois peões da mesma cor dividem casa.
	#
	# Este teste já disse o contrário, e estava errado junto com a regra: a recusa
	# travava o Ludo no ponto mais visível dele, que é o segundo peão saindo da
	# base. Fica invertido, e com o caso da saída junto — que é o que o jogador
	# encontra primeiro.
	var stacked := _rules.initial_state()
	var stacked_prog := LudoRules.progress(stacked)
	stacked_prog[LudoRules.slot(0, 0)] = 5
	stacked_prog[LudoRules.slot(0, 1)] = 7
	stacked.meta[LudoRules.PROG] = stacked_prog
	_check(_move_for(stacked, 2, 0) != null, "dois peões da mesma cor dividem casa")

	# O caso que motivou a mudança: um peão na saída, um 6 na mão, três na base.
	var crowded := _rules.initial_state()
	var crowded_prog := LudoRules.progress(crowded)
	crowded_prog[LudoRules.slot(0, 0)] = 1
	crowded.meta[LudoRules.PROG] = crowded_prog
	_check(
		_move_for(crowded, LudoRules.EXIT_ROLL, 1) != null,
		"com um peão na saída, o 6 ainda tira outro da base"
	)
	# E por isso o 6 passa a **oferecer escolha** em vez de a tela jogar sozinha:
	# com um lance só na lista, `ludo_match.gd` joga sem perguntar, e era assim que
	# o 6 saía andando com o peão de fora sem ninguém ter escolhido.
	_check(
		_rules.moves_for(crowded, LudoRules.EXIT_ROLL).size() >= 2,
		"e o jogador escolhe entre sair e andar, em vez de a tela decidir"
	)


## A reta final é privada, e a chegada exige número exato.
func _probe_home() -> void:
	print("reta final e chegada")
	var state := _rules.initial_state()
	var prog := LudoRules.progress(state)
	prog[LudoRules.slot(0, 0)] = LudoRules.GOAL - 2
	state.meta[LudoRules.PROG] = prog

	_check(_move_for(state, 3, 0) == null, "estourar a chegada não é lance")
	_check(_move_for(state, 2, 0) != null, "o número exato é")

	_rules.apply_move(state, _move_for(state, 2, 0))
	_equals(LudoRules.progress(state)[LudoRules.slot(0, 0)], LudoRules.GOAL, "e leva o peão para casa")
	_equals(LudoRules.finished(state, 0), 1, "o placar conta um peão em casa")
	_equals(_rules.winner(state), -1, "um peão não ganha a partida")

	var done := _rules.initial_state()
	var done_prog := LudoRules.progress(done)
	for token in LudoRules.TOKENS:
		done_prog[LudoRules.slot(2, token)] = LudoRules.GOAL
	done.meta[LudoRules.PROG] = done_prog
	_equals(_rules.winner(done), 2, "os quatro peões em casa ganham")


## O histórico reproduz a partida: é o que a reconexão vai repetir quando o Ludo
## chegar à rede, e o que garante que o dado do outro aparelho é o mesmo daqui.
func _probe_replay() -> void:
	print("histórico")
	var played := _rules.initial_state()
	var script := [[6, 0], [3, 0], [5, LudoRules.PASS], [6, 0]]
	for entry in script:
		var move := _find(played, entry[0], entry[1])
		if move == null:
			_failures += 1
			printerr("  FAIL o roteiro do teste tem um lance ilegal: %s" % [entry])
			return
		_rules.apply_move(played, move)

	var replayed := _rules.initial_state()
	for data in played.history:
		_rules.apply_move(replayed, Move.from_dict(data))

	_equals(
		LudoRules.progress(replayed), LudoRules.progress(played),
		"repetir o histórico devolve a mesma posição"
	)
	_equals(
		LudoRules.turn_of(replayed), LudoRules.turn_of(played),
		"e a mesma vez"
	)
	_equals(played.history.size(), script.size(), "com um registro por rolagem")


## Quatro bots jogando uma partida inteira, com dado sorteado de verdade.
##
## O que está sendo verificado não é a qualidade do jogo — é que a partida
## **termina** e que a heurística sempre tem o que responder. Um bot que devolve
## `null` numa rolagem sem lance possível trava a vez para sempre, e é uma
## travada que só aparece depois de dezenas de jogadas, no aparelho, com quatro
## pessoas esperando.
##
## Semente fixa: uma partida que passa hoje e falha amanhã por sorte diferente
## não é um teste, é um sorteio.
func _probe_bot() -> void:
	print("bot")
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var state := _rules.initial_state()

	var plays := 0
	var limit := 6000
	while _rules.winner(state) < 0 and plays < limit:
		var die := rng.randi_range(1, 6)
		var moves := _rules.moves_for(state, die)
		if moves.is_empty():
			_failures += 1
			printerr("  FAIL nenhum lance para o dado %d — nem o de passar" % die)
			return
		var choice := _rules.best_move(state, moves)
		if choice == null:
			_failures += 1
			printerr("  FAIL a heurística não escolheu nada entre %d lances" % moves.size())
			return
		_rules.apply_move(state, choice)
		plays += 1

	_check(plays < limit, "a partida entre bots termina (%d rolagens)" % plays)
	_check(_rules.winner(state) >= 0, "e alguém vence")
	_equals(
		LudoRules.finished(state, _rules.winner(state)), LudoRules.TOKENS,
		"com os quatro peões em casa"
	)
	_equals(state.history.size(), plays, "e o histórico tem uma entrada por rolagem")

	# A partida jogada é reproduzível a partir da lista de lances — é o que a
	# reconexão faz, e o bot não pode ser uma exceção a isso.
	var replayed := _rules.initial_state()
	for data in state.history:
		var move := Move.from_dict(data)
		_rules.apply_move(replayed, move)
	_equals(
		LudoRules.progress(replayed), LudoRules.progress(state),
		"e repetir o histórico do bot devolve a mesma posição"
	)


## A caminhada do peão, com o relógio andando de verdade.
##
## O estado é sempre o final e quem se move é o desenho, então o que pode
## quebrar aqui não aparece em teste de regra nenhum: um peão que fica parado no
## destino (animação que nunca começa), um que nunca chega (sinal que não sai) e
## um que para no meio do caminho (a conta de progresso fracionário errada).
##
## O `travel_finished` é o que a cena espera antes de devolver a vez: sem ele o
## tabuleiro trava, com o dado apagado e ninguém para jogar.
func _probe_animation() -> void:
	print("animação")
	var view := LudoView.new()
	view.size = Vector2(600.0, 600.0)
	add_child(view)
	# A geometria é calculada no desenho, e sem servidor de vídeo o desenho pode
	# nunca acontecer — aí o tamanho da casa fica em zero e toda distância medida
	# aqui dá zero, que passa em qualquer comparação e não prova nada.
	view._layout()

	var state := _rules.initial_state()
	var prog := LudoRules.progress(state)
	# A posição **depois** do lance: o peão saiu de 3 e está em 9.
	prog[LudoRules.slot(0, 0)] = 9
	prog[LudoRules.slot(1, 0)] = LudoRules.BASE
	state.meta[LudoRules.PROG] = prog
	view.state = state

	var landed := [false]
	view.travel_finished.connect(func(): landed[0] = true)
	# Um capturado junto: ele volta para a base vindo de onde estava.
	view.travel(0, 0, 3, 9, [{"player": 1, "token": 0, "from": 5}])
	_check(view.is_travelling(), "a viagem começa ao ser pedida")

	var destination := view._center_at(0, 9, 0)
	await get_tree().create_timer(LudoView.STEP_SECONDS * 2.0).timeout
	var midway := view._token_center(0, 0)
	_check(
		midway.distance_to(destination) > view._cell * 0.5,
		"no meio do caminho o peão ainda não está no destino"
	)
	# A captura é no fim do caminho: enquanto quem anda não chega, o capturado
	# continua na casa dele. Mandá-lo embora antes seria mostrar o efeito antes
	# da causa.
	_equals(
		view._token_center(1, 0), view._center_at(1, 5, 0),
		"e o capturado ainda está parado na casa dele, esperando a batida"
	)

	await get_tree().create_timer(
		LudoView.STEP_SECONDS * 8.0 + LudoView.KNOCK_SECONDS + 0.2
	).timeout
	var yard := view._center_at(1, LudoRules.BASE, 0)
	_check(
		view._token_center(1, 0).distance_to(yard) < 0.5,
		"e no fim ele está na base"
	)
	_check(landed[0], "a viagem avisa quando termina")
	_check(not view.is_travelling(), "e o desenho volta a ser o estado puro")
	_check(
		view._token_center(0, 0).distance_to(destination) < 0.5,
		"com o peão exatamente onde o estado diz"
	)

	view.free()


## O dado: rola, passa por vários números e para num deles.
##
## O que se verifica é o contrato com a partida, que é curto e fácil de quebrar
## mexendo na animação: o aviso sai **uma vez**, com um número de 1 a 6, e a face
## que fica na tela é esse número. Um dado que anuncia um valor e mostra outro é
## uma partida em que ninguém confia.
##
## A rolagem em si também precisa acontecer: se o dado for direto ao resultado,
## o número lê como decidido pelo app em vez de sorteado.
func _probe_die() -> void:
	print("dado")
	var die := DieView.new()
	die.size = Vector2(100.0, 100.0)
	add_child(die)

	var results := []
	die.rolled.connect(func(face: int): results.append(face))
	die.roll()

	# Amostragem durante a rolagem: os números que passaram pela tela.
	var seen := {}
	var samples := 12
	for _i in samples:
		await get_tree().create_timer(DieView.SPIN / samples).timeout
		seen[die.value] = true

	await get_tree().create_timer(DieView.SETTLE + 0.2).timeout

	_equals(results.size(), 1, "a rolagem avisa uma vez só")
	if not results.is_empty():
		var face: int = results[0]
		_check(face >= 1 and face <= 6, "com um número de dado (obtido: %d)" % face)
		_equals(die.value, face, "e a face que fica é a anunciada")
	_check(seen.size() >= 3, "o dado passa por vários números antes de parar (%d)" % seen.size())

	# Trocar o número de fora também transiciona: é por aí que chega o dado de um
	# lance recebido pela rede, e ele não pode aparecer de um quadro para o outro
	# enquanto o do jogador local nasce e some.
	die.value = 1
	die.value = 6
	_check(die._morph < 1.0, "trocar a face de fora começa uma transição")
	_equals(die._previous, 1, "que sabe de qual número está saindo")

	die.free()


func _move_for(state: MatchState, die: int, token: int) -> Move:
	for move in _rules.moves_for(state, die):
		if LudoRules.token_of(move) == token:
			return move
	return null


func _find(state: MatchState, die: int, token: int) -> Move:
	return _move_for(state, die, token)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
