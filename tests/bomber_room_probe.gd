extends SceneTree

## A sala autoritativa de Bomberman, sem socket.
##
##   godot --headless --path . --script res://tests/bomber_room_probe.gd
##
## A sala é o coração do modelo novo: é ela que tem razão sobre a partida, nunca
## para esperando um byte, e joga por quem não está sentado. O teste alimenta
## comandos direto (sem rede) e confere que ela anda, aplica no tique certo,
## descarta o que chega tarde, repete movimento sem repetir bomba, e encerra
## quando alguém vence.

var _failures := 0


func _initialize() -> void:
	_test_advances()
	_test_grace()
	_test_name_is_cleaned()
	_test_repeat_masks_bomb()
	_test_known_keeps_bomb()
	_test_empty_seat_is_bot()
	_test_winner_ends()
	_test_empty_table_ends()

	if _failures == 0:
		print("OK — sala de Bomberman consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


## Rodando, o tique anda um por passo. É a prova de que a sala **simula**, e não
## só guarda um estado parado.
func _test_advances() -> void:
	print("a sala anda")
	var room := _room()
	room.running = true
	for i in 30:
		room.step()
	_equals(room.state.tick, 30, "trinta passos = tique 30")

	# Parada, não anda. A partida só corre depois do começo.
	var idle := _room()
	idle.step()
	_equals(idle.state.tick, 0, "sala parada não anda")


## Comando dentro da janela é aplicado; velho demais é passado. Reescrever um tique
## que já foi mudaria uma jogada que todo mundo já viu.
func _test_grace() -> void:
	print("janela de aceite")
	var room := _room()
	room.running = true
	room.seat_for(100, "Ana")
	for i in 40:
		room.step()

	# Um tique bem no passado, além da graça.
	room.receive(100, 0, PackedByteArray([BomberRules.IN_UP]))
	_check(not room._inbox[0].has(0), "comando velho é descartado")

	# Um tique logo à frente é guardado.
	var soon := room.state.tick + 1
	room.receive(100, soon, PackedByteArray([BomberRules.IN_LEFT]))
	_check(room._inbox[0].has(soon), "comando fresco é guardado")

	# E o outro lado da janela, que é o que faltava: um tique absurdamente
	# adiantado não entra. O tique vem num `s32` do cliente, e sem este teto ele
	# ficava guardado para sempre — `_forget_before` só apaga o que ficou para
	# trás, e nada que esteja à frente do tique atual fica. Era memória que só
	# crescia, num servidor com a porta aberta para a internet.
	var absurd := 2_000_000_000
	room.receive(100, absurd, PackedByteArray([BomberRules.IN_DOWN]))
	_check(not room._inbox[0].has(absurd), "comando adiantado demais é descartado")

	# O limite exato continua servindo: quem está com a rede ruim manda o comando
	# com folga, e essa folga é legítima.
	var edge := room.state.tick + BomberProtocol.INPUT_LEAD
	room.receive(100, edge, PackedByteArray([BomberRules.IN_RIGHT]))
	_check(room._inbox[0].has(edge), "a folga inteira ainda é aceita")


## O nome vem do teclado de uma pessoa e vai desenhado para a tela das outras.
## Um peer adulterado é a hipótese normal, então a sala corta o que não se desenha
## em vez de confiar no cliente.
func _test_name_is_cleaned() -> void:
	print("nome de assento higienizado")
	var room := _room()
	room.seat_for(100, "An\na\tBeta")
	_check(not room.names[0].contains("\n"), "quebra de linha não entra no nome")
	_check(not room.names[0].contains("\t"), "nem tabulação")

	room.seat_for(101, "                                        ")
	_equals(room.names[1], "Jogador 2", "só espaço é o mesmo que nome vazio")

	room.seat_for(102, "Um nome absurdamente comprido para um cartão")
	_equals(room.names[2].length(), BomberRoom.NAME_LIMIT, "e o comprido é cortado no limite")


## Byte faltante repete o movimento, nunca a bomba. Repetir a última tecla
## plantaria uma bomba nova a cada tique perdido.
func _test_repeat_masks_bomb() -> void:
	print("repeat mascara a bomba")
	var room := _room()
	room.seat_for(100, "Ana")
	room._last[0] = BomberRules.IN_UP | BomberRules.IN_BOMB

	var got := room._command_for(0, 9999)  # tique sem comando conhecido
	_check(got & BomberRules.IN_BOMB == 0, "o bit de bomba some no repeat")
	_check(got & BomberRules.IN_UP != 0, "o movimento fica no repeat")


## Quando o byte **chegou**, o comando vale inteiro — inclusive a bomba. O
## descarte é só do repeat, não do comando verdadeiro.
func _test_known_keeps_bomb() -> void:
	print("comando conhecido mantém a bomba")
	var room := _room()
	room.seat_for(100, "Ana")
	room._inbox[0][5] = BomberRules.IN_RIGHT | BomberRules.IN_BOMB

	var got := room._command_for(0, 5)
	_check(got & BomberRules.IN_BOMB != 0, "a bomba do comando verdadeiro fica")
	_equals(room._last[0], got, "e vira o último conhecido")


## Assento vazio é jogado pela máquina, e o comando dela é um byte válido.
func _test_empty_seat_is_bot() -> void:
	print("assento vazio é bot")
	var room := _room()  # ninguém sentado: os quatro são bots
	var command := room._command_for(0, 1)
	_check(command >= 0 and command <= 31, "o bot devolve um comando válido")

	# Uma sala só de bots anda sem travar.
	room.running = true
	for i in 20:
		room.step()
	_equals(room.state.tick, 20, "sala só de bots simula")


## Alguém vence e a sala encerra: para de simular e marca o vencedor.
func _test_winner_ends() -> void:
	print("vitória encerra a partida")
	var room := BomberRoom.new("DUO001", 2, 555)
	room.running = true
	room.seat_for(100, "Ana")
	room.seat_for(101, "Beto")
	# Mata o assento 1 direto no estado; o próximo passo vê um só de pé.
	room.state.players[1].alive = false
	room.step()

	_check(room.finished, "a partida terminou")
	_check(not room.running, "e parou de simular")
	_equals(room.winner, 0, "o assento 0 venceu")


## A mesa esvaziou de gente no meio da partida. Não há Bomberman de humano nenhum
## contra bots num servidor: quem sobrar recebe o fim.
func _test_empty_table_ends() -> void:
	print("mesa vazia encerra")
	var room := BomberRoom.new("DUO002", 2, 7)
	room.running = true
	room.seat_for(100, "Ana")
	room.step()
	_check(not room.finished, "com gente, segue")
	room.release(100)
	_check(room.finished, "sem gente, encerra")


# --- utilidades --------------------------------------------------------------


func _room() -> BomberRoom:
	return BomberRoom.new("TEST01", 4, 12345)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])
