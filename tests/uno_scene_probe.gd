extends Node

## A cena do Uno, com autoloads e nós de verdade.
##
##   godot --headless --path . res://tests/uno_scene_probe.tscn
##
## As regras já são cobertas por `uno_probe.gd`. O que se verifica aqui é a
## camada que o teste de regra não alcança, e que é onde a partida trava sem nada
## falhar:
##
## - **a mão acende o que a regra aceita**, e não o que `is_playable` acha. As
##   duas listas discordam depois de uma compra, e é exatamente ali que a tela
##   ofereceria um toque que a regra recusaria;
## - **o toque acha a carta certa** num leque em que elas se cobrem. Um erro de
##   índice aqui tira da mão uma carta que o jogador não tocou;
## - **a segunda pergunta aparece só quando existe** — a cor do curinga e o alvo
##   do 7 —, e a mesa de dois não pergunta com quem trocar;
## - **a vez da máquina anda sozinha**, e anda uma vez só.

const MATCH_SCENE := preload("res://scenes/uno_match.tscn")
const RULES := preload("res://core/uno_rules.gd")

var _failures := 0


func _ready() -> void:
	Game.start_solo(Game.UNO)
	Game.table_size = 4
	Game.uno_sevens = true

	await _probe_opening()
	await _probe_table_seats()
	await _probe_hand_hit()
	await _probe_playing()
	await _probe_draw_then_pass()
	await _probe_wild()
	await _probe_seven()
	await _probe_action_buttons()
	await _probe_bot_turn()
	await _probe_finish()
	await _probe_late_names()

	if _failures == 0:
		print("OK — cena do Uno consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Uma cena montada e pronta para receber toque.
func _open() -> Node:
	var scene := MATCH_SCENE.instantiate()
	add_child(scene)
	await get_tree().process_frame
	return scene


## Substitui a partida por uma posição escrita à mão e redesenha.
##
## Mexer no estado por dentro é o que permite testar o 7 e o curinga sem esperar
## que o baralho sorteie um — e o sorteio é determinístico, mas amarrar o teste a
## uma semente faz dele um teste da semente.
func _rig(scene: Node, hands: Array, top: int, seats := 4) -> void:
	var state := MatchState.new()
	state.meta[UnoRules.SEATS] = seats
	state.meta[UnoRules.SEVENS] = 1
	state.meta[UnoRules.RNG] = 12345
	state.meta[UnoRules.TURN] = 0
	state.meta[UnoRules.DIR] = 1
	state.meta[UnoRules.DREW] = 0
	state.meta[UnoRules.PEND] = 0
	state.meta[UnoRules.PKIND] = -1
	state.meta[UnoRules.FOURBY] = -1
	state.meta[UnoRules.FOURBAD] = 0
	state.meta[UnoRules.LAST] = -1
	state.meta[UnoRules.SAID] = 0
	state.meta[UnoRules.PILE] = PackedInt32Array([top])
	state.meta[UnoRules.COLOR] = UnoRules.color_of_card(top)
	var deck := PackedInt32Array()
	for _each in 20:
		deck.append(UnoRules.card(UnoRules.CardColor.YELLOW, 8))
	state.meta[UnoRules.DECK] = deck
	for seat in seats:
		var hand := PackedInt32Array()
		if seat < hands.size():
			for card in hands[seat]:
				hand.append(int(card))
		if hand.is_empty():
			hand.append(UnoRules.card(UnoRules.CardColor.YELLOW, 8))
		state.meta[UnoRules.hand_key(seat)] = hand

	scene._rules.seats = seats
	scene._rules.sevens = true
	scene._state = state
	scene._busy = false
	scene._bot_pending = false
	scene._refresh()
	await get_tree().process_frame


func _probe_opening() -> void:
	print("abertura")
	var scene := await _open()
	_equals(scene._hand.cards.size(), UnoRules.HAND_SIZE, "a mão local começa com 7 cartas")
	_equals(UnoRules.turn_of(scene._state), 0, "e é a vez do jogador local")
	_check(scene._hand.enabled, "a mão aceita toque")
	_check(not scene.get_node("%Overlay").visible, "sem painel de fim de partida")
	_check(not scene.get_node("%ChoiceLayer").visible, "e sem pergunta aberta")
	_check(not scene.get_node("%PassButton").visible, "passar não é lance antes de comprar")

	# A mesa sabe quem é o dono do aparelho e como cada assento se chama. É o que
	# põe o local embaixo e os outros na ordem de jogo a partir dele.
	var table: UnoView = scene._table
	_equals(table.local_seat, 0, "a mesa sabe qual assento é o nosso")
	_equals(table.names.size(), 4, "e o nome de cada um")
	_equals(table.names[0], "Você", "com o local se chamando Você")
	scene.free()


## Os assentos ficam em volta, na **ordem de jogo** a partir do local — e não na
## ordem de índice.
##
## É o que faz a seta do sentido significar a mesma coisa nas quatro telas de uma
## partida em rede: lá o `local_seat` de cada aparelho é diferente, e uma mesa
## desenhada por índice mostraria a mesma partida girada de um jeito para cada um.
func _probe_table_seats() -> void:
	print("assentos em volta da mesa")
	var table := UnoView.new()
	table.size = Vector2(560.0, 250.0)
	add_child(table)
	var rules := RULES.new()
	rules.seats = 4
	rules.match_seed = 99
	table.state = rules.initial_state()
	await get_tree().process_frame

	table.local_seat = 0
	table._layout()
	var bottom := table._seat_center(0)
	_check(
		bottom.y > table.size.y * 0.5,
		"o assento local fica embaixo"
	)
	var across := table._seat_center(2)
	_check(across.y < table.size.y * 0.5, "e o oposto fica em cima")

	# O mesmo estado visto por outro aparelho: quem está embaixo muda, e a ordem
	# em volta continua sendo a de jogo.
	table.local_seat = 2
	var moved := table._seat_center(2)
	_check(
		moved.y > table.size.y * 0.5,
		"trocando de dono, quem fica embaixo é o novo local"
	)
	# Quem vai para o topo é quem está a **meia mesa** do novo local — numa mesa de
	# quatro, dois lugares adiante. É o assento 0, e não o 3: o 3 é o vizinho
	# imediato e vai para o lado.
	_check(
		table._seat_center(0).distance_to(across) < 1.0,
		"e o oposto do novo local ocupa o lugar de cima"
	)
	_check(
		absf(table._seat_center(3).y - table.size.y * 0.52) < table.size.y * 0.05,
		"com o vizinho imediato no lado, à meia altura"
	)
	table.free()


## O toque num leque em que as cartas se cobrem tem de achar a de cima.
##
## A vista é montada **solta**, fora da cena da partida. Ligada nela, o primeiro
## toque jogaria a carta e a mão mudaria no meio do laço — o teste passaria a
## medir o efeito do toque anterior em vez do acerto do seguinte. Foi assim que
## este teste falhou da primeira vez, e o leque estava certo.
func _probe_hand_hit() -> void:
	print("toque no leque")
	var hand := UnoHand.new()
	hand.size = Vector2(408.0, 150.0)
	add_child(hand)
	await get_tree().process_frame

	var cards := PackedInt32Array()
	for value in range(1, 9):
		cards.append(UnoRules.card(UnoRules.CardColor.RED, value))
	hand.cards = cards
	hand.playable = cards
	hand.enabled = true
	hand._layout()
	_equals(hand._spots.size(), cards.size(), "o leque posiciona uma carta por lugar")

	# Uma mão de oito numa tela de celular: o passo já encolheu, e é onde o acerto
	# fica apertado. O centro de cada carta continua pertencendo a ela e só a ela.
	var taken := []
	hand.card_tapped.connect(func(card: int): taken.append(card))
	for index in cards.size():
		taken.clear()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = hand._spots[index].origin
		hand._gui_input(press)
		_equals(
			taken, [cards[index]],
			"o toque no centro da carta %d entrega ela mesma" % index
		)

	# A carta apagada não emite nada, e **não** deixa o toque cair na de baixo:
	# o jogador veria sair da mão uma carta que ele não tocou.
	hand.playable = PackedInt32Array([cards[cards.size() - 1]])
	hand._layout()
	taken.clear()
	var blocked := InputEventMouseButton.new()
	blocked.button_index = MOUSE_BUTTON_LEFT
	blocked.pressed = true
	blocked.position = hand._spots[0].origin
	hand._gui_input(blocked)
	_equals(taken, [], "tocar numa carta apagada não joga nada")

	# O leque inteiro cabe na largura: a última carta não pode sair da tela numa
	# mão grande, que é o que uma fila não garante sem um gesto a mais.
	var last: Vector2 = hand._spots[hand._spots.size() - 1].origin
	_check(last.x < hand.size.x, "e a última carta continua dentro da tela")

	hand.free()


func _probe_playing() -> void:
	print("jogar uma carta")
	var scene := await _open()
	var three := UnoRules.card(UnoRules.CardColor.RED, 3)
	var stranger := UnoRules.card(UnoRules.CardColor.BLUE, 9)
	await _rig(scene, [[three, stranger]], UnoRules.card(UnoRules.CardColor.RED, 5))

	_equals(scene._hand.playable, PackedInt32Array([three]), "só a carta que serve acende")
	_check(scene.get_node("%Table").can_draw, "e o monte acende junto, porque comprar é legal")

	scene._on_card_tapped(three)
	await get_tree().create_timer(0.6).timeout
	_equals(
		UnoRules.top_card(scene._state), three, "a carta jogada vai para o descarte"
	)
	_equals(
		UnoRules.hand_of(scene._state, 0), PackedInt32Array([stranger]),
		"e sai da mão"
	)
	_check(not scene._hand.enabled, "a mão fecha quando a vez não é mais nossa")
	scene.free()


## Comprar não encerra a vez quando a carta comprada serve — e a tela precisa
## contar isso, senão o jogador acha que travou.
func _probe_draw_then_pass() -> void:
	print("comprar e passar")
	var scene := await _open()
	await _rig(scene, [[UnoRules.card(UnoRules.CardColor.BLUE, 9)]],
		UnoRules.card(UnoRules.CardColor.RED, 5))
	# Monte com uma carta que serve no topo (o topo é o fim do vetor).
	scene._state.meta[UnoRules.DECK] = PackedInt32Array([
		UnoRules.card(UnoRules.CardColor.RED, 2)
	])
	scene._refresh()
	_check(scene._hand.playable.is_empty(), "nada serve antes de comprar")

	scene._on_deck_tapped()
	await get_tree().create_timer(0.6).timeout
	_equals(UnoRules.turn_of(scene._state), 0, "comprar carta que serve não passa a vez")
	_check(scene.get_node("%PassButton").visible, "e o botão de passar aparece")
	_equals(
		scene._hand.playable, PackedInt32Array([UnoRules.card(UnoRules.CardColor.RED, 2)]),
		"só a carta comprada acende, e não a mão inteira"
	)

	scene._on_pass()
	await get_tree().create_timer(0.6).timeout
	_equals(UnoRules.turn_of(scene._state), 1, "passar entrega a vez")
	_check(not scene.get_node("%PassButton").visible, "e o botão some")
	scene.free()


func _probe_wild() -> void:
	print("curinga")
	var scene := await _open()
	var wild := UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD)
	await _rig(scene, [[wild, UnoRules.card(UnoRules.CardColor.BLUE, 9)]],
		UnoRules.card(UnoRules.CardColor.RED, 5))

	scene._on_card_tapped(wild)
	await get_tree().process_frame
	_check(scene.get_node("%ChoiceLayer").visible, "o curinga abre a pergunta da cor")
	var row: Node = scene.get_node("%ChoiceRow")
	_equals(row.get_child_count(), UnoRules.COLOR_COUNT, "com um botão por cor")

	# O terceiro botão é o verde, na ordem do enum.
	var green: Button = row.get_child(UnoRules.CardColor.GREEN)
	green.pressed.emit()
	await get_tree().create_timer(0.6).timeout
	_check(not scene.get_node("%ChoiceLayer").visible, "escolher fecha a pergunta")
	_equals(
		UnoRules.active_color(scene._state), UnoRules.CardColor.GREEN,
		"e a cor escolhida passa a valer"
	)
	_check(
		UnoRules.is_wild(UnoRules.top_card(scene._state)),
		"o curinga continua curinga no descarte"
	)
	scene.free()


## O 7 pergunta com quem trocar — e numa mesa de dois não pergunta, porque a
## resposta é uma só.
func _probe_seven() -> void:
	print("o 7 da regra da casa")
	var scene := await _open()
	var seven := UnoRules.card(UnoRules.CardColor.RED, 7)
	await _rig(scene, [
		[seven, UnoRules.card(UnoRules.CardColor.BLUE, 9)],
		[UnoRules.card(UnoRules.CardColor.GREEN, 2)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))

	# Grita antes de jogar: a mão vai ficar com uma carta, e sem o grito o bot do
	# assento 1 pega — que é o certo, e aqui atrapalharia a conta da troca.
	scene._on_action(UnoRules.CALL)
	await get_tree().create_timer(0.7).timeout

	scene._on_card_tapped(seven)
	await get_tree().process_frame
	_check(scene.get_node("%ChoiceLayer").visible, "o 7 abre a pergunta do alvo")
	var row: Node = scene.get_node("%ChoiceRow")
	_equals(row.get_child_count(), 3, "com um botão por adversário")
	# O rótulo carrega o tamanho da mão: é a informação inteira da escolha.
	var first: Button = row.get_child(0)
	_check(first.text.contains("(1)"), "e o botão diz quantas cartas o alvo tem")

	first.pressed.emit()
	await get_tree().create_timer(1.2).timeout
	_equals(
		UnoRules.hand_of(scene._state, 0),
		PackedInt32Array([UnoRules.card(UnoRules.CardColor.GREEN, 2)]),
		"trocar entrega a mão do alvo a quem jogou"
	)
	scene.free()

	# Mesa de dois: um alvo possível, e nenhuma pergunta.
	var duel := await _open()
	await _rig(duel, [
		[seven, UnoRules.card(UnoRules.CardColor.BLUE, 9)],
		[UnoRules.card(UnoRules.CardColor.GREEN, 2)],
	], UnoRules.card(UnoRules.CardColor.RED, 5), 2)
	duel._on_card_tapped(seven)
	await get_tree().process_frame
	_check(
		not duel.get_node("%ChoiceLayer").visible,
		"numa mesa de dois o 7 não pergunta com quem trocar"
	)
	duel.free()


## Os botões da coluna da direita: um por lance que não é carta.
##
## O que se verifica é que eles aparecem **só quando o lance existe** e que o
## rótulo carrega o número da decisão — "Comprar 6" e "Comprar 2" são escolhas
## diferentes, e um botão escrito "Comprar" não diz qual delas está na mesa.
func _probe_action_buttons() -> void:
	print("botões de ação")
	var scene := await _open()
	var two := UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO)
	await _rig(scene, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 3), UnoRules.card(UnoRules.CardColor.BLUE, 4)],
		[two],
	], UnoRules.card(UnoRules.CardColor.RED, 5))

	# Duas cartas na mão: gritar é lance, e nenhum dos outros é.
	_check(_action(scene, UnoRules.CALL).visible, "com duas cartas, o botão de gritar aparece")
	_equals(_action(scene, UnoRules.CALL).text, "UNO!", "com o rótulo curto")
	_check(not _action(scene, UnoRules.TAKE).visible, "e nenhum botão de pilha")
	_check(not _action(scene, UnoRules.CHALLENGE).visible, "nem o de duvidar")

	# Pilha de seis na mesa, esperando resposta de quem olha.
	scene._state.meta[UnoRules.PEND] = 6
	scene._state.meta[UnoRules.PKIND] = UnoRules.DRAW_TWO
	scene._refresh()
	await get_tree().process_frame
	_check(_action(scene, UnoRules.TAKE).visible, "com a pilha no ar, engolir é botão")
	_equals(_action(scene, UnoRules.TAKE).text, "Comprar 6", "e ele diz quantas")
	_check(
		not _action(scene, UnoRules.CHALLENGE).visible,
		"e não se duvida de uma pilha de +2"
	)

	# A mesma pilha, mas de +4 e com autor: agora duvidar existe.
	scene._state.meta[UnoRules.PKIND] = UnoRules.WILD_FOUR
	scene._state.meta[UnoRules.FOURBY] = 1
	scene._state.meta[UnoRules.hand_key(0)] = PackedInt32Array(
		[UnoRules.card(UnoRules.CardColor.BLUE, 3)]
	)
	scene._refresh()
	await get_tree().process_frame
	_check(_action(scene, UnoRules.CHALLENGE).visible, "numa pilha de +4, duvidar é botão")
	_equals(_action(scene, UnoRules.CHALLENGE).text, "Duvidar", "com o rótulo dele")

	scene.free()


## O botão de uma espécie de lance.
func _action(scene: Node, kind: int) -> Button:
	return scene._actions[kind]


## A vez da máquina anda sozinha, e anda **uma vez só**.
func _probe_bot_turn() -> void:
	print("vez da máquina")
	var scene := await _open()
	await _rig(scene, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 9)],
		[UnoRules.card(UnoRules.CardColor.RED, 1), UnoRules.card(UnoRules.CardColor.RED, 2)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	# Entrega a vez ao assento 1, que é máquina no solo.
	scene._state.meta[UnoRules.TURN] = 1
	scene._refresh()
	_check(not scene._hand.enabled, "a mão fecha na vez da máquina")

	var before := UnoRules.hand_size(scene._state, 1)
	await get_tree().create_timer(2.0).timeout
	_check(
		UnoRules.hand_size(scene._state, 1) < before,
		"a máquina joga sem ninguém tocar em nada"
	)
	# Uma jogada, não várias: `_bot_pending` existe para isso, e sem ele cada
	# `_refresh` durante a vez dela marcaria outra.
	_check(
		UnoRules.hand_size(scene._state, 1) == before - 1,
		"e joga uma carta só por vez"
	)
	scene.free()


func _probe_finish() -> void:
	print("fim de partida")
	var scene := await _open()
	var last := UnoRules.card(UnoRules.CardColor.RED, 3)
	await _rig(scene, [[last]], UnoRules.card(UnoRules.CardColor.RED, 5))

	scene._on_card_tapped(last)
	await get_tree().create_timer(0.8).timeout
	_equals(scene._rules.winner(scene._state), 0, "quem esvaziou a mão venceu")
	_check(scene.get_node("%Overlay").visible, "e o painel de fim de partida abre")
	_equals(scene.get_node("%OverlayTitle").text, "Você venceu", "dizendo quem venceu")
	_check(not scene._hand.enabled, "com a mão fechada")

	scene.get_node("%AgainButton").pressed.emit()
	await get_tree().process_frame
	_check(not scene.get_node("%Overlay").visible, "a revanche fecha o painel")
	_equals(
		scene._hand.cards.size(), UnoRules.HAND_SIZE, "e reparte sete cartas"
	)
	scene.free()


## O nome que chega **depois** da tela.
##
## Numa mesa de quatro, quem entra aprende o nome do anfitrião no `welcome`, e o
## dos outros convidados só quando o `ready` deles chega — o que costuma ser
## depois de a cena já ter montado a coluna de jogadores. A coluna escrevia o
## nome uma vez, ao nascer, e o aviso `names_changed` só redesenhava a mesa: em
## algumas partidas os nomes apareciam, em outras ficava "Jogador 2", conforme
## quem ganhava a corrida.
func _probe_late_names() -> void:
	print("nomes que chegam depois da tela")
	Game.mode = Game.Mode.ONLINE
	Net.seats = 4
	Net.local_seat = 2
	Net.bot_seats = PackedInt32Array()
	Net.player_names = {0: "Ana"}
	var scene := await _open()

	var label := func(seat: int) -> String:
		var row: HBoxContainer = scene._chips[seat].get_child(0)
		return (row.get_child(1) as Label).text

	_equals(label.call(0), "Ana", "o nome que já tinha chegado aparece")
	_equals(label.call(1), "Jogador 2", "e quem ainda não se apresentou é numerado")
	_equals(label.call(2), "Você", "e o local é você")

	Net._remember_name(1, "Bia")
	Net._remember_name(3, "Duda")
	await get_tree().process_frame
	_equals(label.call(1), "Bia", "o nome que chega depois entra na coluna")
	_equals(label.call(3), "Duda", "o de todos os que chegarem")

	Net.bot_seats = PackedInt32Array([3])
	Net.bots_changed.emit()
	await get_tree().process_frame
	_equals(label.call(3), "Jogador 4 (bot)", "e a cadeira que vira máquina diz isso")

	scene.free()
	Net.leave()
	Game.start_solo(Game.UNO)


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
