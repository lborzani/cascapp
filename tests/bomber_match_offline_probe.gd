extends Node

## A cena de partida offline, instanciada de verdade e rodada por alguns segundos.
##
##   godot --headless --path . res://tests/bomber_match_offline_probe.tscn
##
## Cena e não `--script`: o caminho offline usa autoloads ([Game], [Sound]), que
## não existem no modo `--script`.
##
## Não testa a rede — testa que a **reescrita do loop** não quebrou o caminho
## offline: a cena monta, o relógio anda, os bots jogam, e a simulação avança sem
## erro de runtime. É a rede de segurança da troca de lockstep por predição, que
## mexeu no `_process` que os dois modos compartilham.

var _failures := 0


func _ready() -> void:
	Game.mode = Game.Mode.SOLO
	Game.game_id = Game.BOMBERMAN

	await get_tree().process_frame
	var scene: Control = load("res://scenes/bomber_match.tscn").instantiate()
	get_tree().root.add_child(scene)

	var first := -1
	var last := -1
	for frame in 180:
		await get_tree().process_frame
		var state = scene._state
		if state != null:
			if first < 0:
				first = state.tick
			last = state.tick

	_check(first >= 0, "a cena montou um estado")
	_check(last > first, "o tique andou (%d → %d)" % [first, last])
	scene.queue_free()

	if _failures == 0:
		print("OK — partida offline de Bomberman roda.")
	else:
		printerr("%d verificação(ões) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
