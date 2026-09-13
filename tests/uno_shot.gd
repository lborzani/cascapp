extends Node

## Um print da partida de Uno, para julgar a tela sem jogar.
##
##   godot --path . --resolution 768x432 res://tests/uno_shot.tscn
##
## Salva em user://uno_screen.png. A posição é escrita à mão e não sorteada: o que
## se quer ver é a mão grande, o curinga, o +4 e a carta apagada convivendo — e um
## baralho sorteado dá isso uma vez em muitas.

func _ready() -> void:
	Game.start_solo(Game.UNO)
	Game.table_size = 6
	Game.uno_sevens = true
	var scene := preload("res://scenes/uno_match.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame

	var state: MatchState = scene._state
	state.meta[UnoRules.hand_key(0)] = PackedInt32Array([
		UnoRules.card(UnoRules.CardColor.RED, 7),
		UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO),
		UnoRules.card(UnoRules.CardColor.YELLOW, 0),
		UnoRules.card(UnoRules.CardColor.GREEN, UnoRules.SKIP),
		UnoRules.card(UnoRules.CardColor.BLUE, 9),
		UnoRules.card(UnoRules.CardColor.BLUE, UnoRules.REVERSE),
		UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR),
	])
	# Uma mão de uma carta na mesa: é o alarme vermelho do assento.
	state.meta[UnoRules.hand_key(2)] = PackedInt32Array([
		UnoRules.card(UnoRules.CardColor.GREEN, 4)
	])
	# E uma mão grande, para o teto do leque de costas aparecer: acima de sete
	# versos quem conta é o número.
	var big := PackedInt32Array()
	for _each in 14:
		big.append(UnoRules.card(UnoRules.CardColor.GREEN, 4))
	state.meta[UnoRules.hand_key(4)] = big
	state.meta[UnoRules.PILE] = PackedInt32Array([UnoRules.card(UnoRules.CardColor.RED, 5)])
	state.meta[UnoRules.COLOR] = UnoRules.CardColor.RED
	state.meta[UnoRules.TURN] = 0
	scene._refresh()

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://uno_screen.png")
	print("ok — user://uno_screen.png")
	get_tree().quit()
