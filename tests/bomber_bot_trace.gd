extends SceneTree

## Onde a decisão do bot de Bomberman vai parar.
##
##   godot --headless --path . --script res://tests/bomber_bot_trace.gd
##
## Não é teste. É a mesma régua que `bot_bench.gd` é para o xadrez: conta em qual
## dos três ramos cada decisão caiu, para separar "ele não quer bombardear" de
## "ele quer e acha que não tem fuga".

const TICKS := 900


func _initialize() -> void:
	var rules := BomberRules.new()
	var bot := BomberBot.new()
	var state := rules.initial_state(4, 11)

	var fleeing := 0
	var bombing := 0
	var wants_bomb := 0
	var walking := 0
	var idle := 0
	var bombs_dropped := 0
	var free_ticks := 0
	var ready := 0
	var no_escape := 0

	for tick in TICKS:
		var inputs := PackedByteArray()
		inputs.resize(4)
		for seat in 4:
			var command := bot.decide(state, seat)
			inputs[seat] = command
			var player := state.players[seat]
			if not player.alive:
				continue
			var col := player.x / BomberState.CELL
			var row := player.y / BomberState.CELL
			var danger := bot._danger_map(state)
			if danger[BomberState.index_of(col, row)] > 0:
				fleeing += 1
				continue
			var has_capacity := bot._can_place(state, seat)
			var next_to_brick := bot._worth_bombing(state, seat, col, row)
			if has_capacity:
				free_ticks += 1
			if next_to_brick:
				wants_bomb += 1
			if has_capacity and next_to_brick:
				ready += 1
				if not bot._has_escape(state, col, row, player.flame):
					no_escape += 1
			if command & BomberRules.IN_BOMB:
				bombing += 1
			elif command != 0:
				walking += 1
			else:
				idle += 1
		var before := state.bombs.size()
		rules.step(state, inputs)
		bombs_dropped += maxi(0, state.bombs.size() - before)

	print("em %d tiques com 4 bots:" % TICKS)
	print("  fugindo        %d" % fleeing)
	print("  com bomba na mão %d" % free_ticks)
	print("  ao lado de caixa %d" % wants_bomb)
	print("  os dois          %d, dos quais sem fuga %d" % [ready, no_escape])
	print("  pediu bomba      %d" % bombing)
	print("  andando        %d" % walking)
	print("  parado         %d" % idle)
	print("  bombas postas  %d" % bombs_dropped)
	print("  vivos          %d" % state.alive_count())

	# O caminho de um bot só, casa a casa. Andar 22 segundos sem encostar numa
	# caixa num mapa de 13x11 cheio delas não é caminhada — é ida e volta.
	var fresh := rules.initial_state(4, 11)
	var trail := PackedStringArray()
	var last := ""
	for tick in 240:
		var inputs := PackedByteArray()
		inputs.resize(4)
		for seat in 4:
			inputs[seat] = bot.decide(fresh, seat)
		rules.step(fresh, inputs)
		var one := fresh.players[0]
		var here := "%d,%d" % [one.x / BomberState.CELL, one.y / BomberState.CELL]
		if here != last:
			trail.append(here)
			last = here
	print("caminho do assento 0: %s" % " ".join(trail))

	# Qual ramo, casa e alvo, tique a tique. É o que separa "ele está fugindo em
	# círculo" de "ele está caçando em círculo" — dois bugs diferentes com o mesmo
	# rastro.
	var lines := PackedStringArray()
	for tick in 40:
		var inputs := PackedByteArray()
		inputs.resize(4)
		for seat in 4:
			inputs[seat] = bot.decide(fresh, seat)
		var one := fresh.players[0]
		var col := one.x / BomberState.CELL
		var row := one.y / BomberState.CELL
		var danger := bot._danger_map(fresh)
		var branch := "anda"
		if not one.alive:
			branch = "morto"
		elif danger[BomberState.index_of(col, row)] > 0:
			branch = "FOGE"
		elif bot._can_place(fresh, 0) and bot._worth_bombing(fresh, 0, col, row):
			branch = "BOMBA"
		var goal: Dictionary = bot._targets.get(0, {})
		lines.append("%s@%d,%d->%s" % [branch, col, row, goal.get("cell", Vector2i(-1, -1))])
		rules.step(fresh, inputs)
	print("ramos: %s" % " ".join(lines))
	quit(0)
