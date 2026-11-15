extends Node

## Um print da partida de Uno, para julgar a tela sem jogar.
##
##   godot --path . res://tests/uno_shot.tscn -- --seats=6 --size=432x768
##
## Salva em user://uno_screen_<assentos>_<largura>x<altura>.png. A posição é
## escrita à mão e não sorteada: o que se quer ver é a mão grande, o curinga, o +4 e a carta apagada convivendo — e um
## baralho sorteado dá isso uma vez em muitas.

const Stage := preload("res://tests/shot_stage.gd")


func _ready() -> void:
	Game.start_solo(Game.UNO)
	# `-- --seats=N` troca a mesa, para julgar o anel de dois a seis.
	Game.table_size = 6
	# `-- --size=LxA` troca o palco: deitado (padrão) ou em pé.
	var physical := Vector2i(768, 432)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seats="):
			Game.table_size = int(arg.trim_prefix("--seats="))
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			physical = Vector2i(int(parts[0]), int(parts[1]))
	Game.uno_sevens = true
	var stage := Stage.make(self, physical)
	var scene := preload("res://scenes/uno_match.tscn").instantiate()
	stage.add_child(scene)
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
	var shot := "user://uno_screen_%d_%dx%d.png" % [
		Game.table_size, physical.x, physical.y
	]
	Stage.save(stage, shot)
	print("ok — %s" % shot)
	get_tree().quit()
