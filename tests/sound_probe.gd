extends Node

## O som sem ouvido: barramentos, música só no cardápio e o boliche batendo.
##
##   godot --headless --fixed-fps 60 --path . res://tests/sound_probe.tscn
##
## O que se confere é o estado dos tocadores, não o som: que a música está no ar
## nas abas do cardápio e pausada fora delas (e volta de onde parou), e que uma
## bola no meio da pista faz o baque, as batidas dos pinos e o rolar.

var _failures := 0


func _ready() -> void:
	# A sonda troca de cena: sai da cena atual para não ser liberada junto.
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	_check(AudioServer.get_bus_index(Sound.MUSIC_BUS) != -1, "barramento Music existe")
	_check(AudioServer.get_bus_index(Sound.SFX_BUS) != -1, "barramento SFX existe")
	var started := Time.get_ticks_msec()
	var waited := 0.0
	while Sound.loop(Sound.Loop.MUSIC) == null and waited < 60.0:
		await tree.process_frame
		waited = (Time.get_ticks_msec() - started) / 1000.0
	_check(Sound.loop(Sound.Loop.HALL) != null, "laços prontos (%.1f s)" % waited)
	# Laço colado nas pontas do buffer derrubava o app no Android (1.84).
	for which: int in Sound.Loop.values():
		var wav := Sound.loop(which)
		var frames := wav.data.size() / 2
		_check(wav.loop_begin >= Sound.LOOP_PAD and wav.loop_end <= frames - Sound.LOOP_PAD, "laço %d tem margem no buffer" % which)
	await _probe_music(tree)
	await _probe_bowling(tree)
	print("sound_probe: %s" % ("OK" if _failures == 0 else "%d falhas" % _failures))
	tree.quit(0 if _failures == 0 else 1)


func _probe_music(tree: SceneTree) -> void:
	var was_sound := Prefs.sound_on()
	var was_music := Prefs.music_on()
	Prefs.set_sound(true)
	Prefs.set_music(true)
	Sound.refresh()
	tree.change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(tree, 1.2)
	_check(Sound.music_playing(), "música toca na inicial")
	tree.change_scene_to_file("res://scenes/pairing.tscn")
	await _wait(tree, 1.2)
	_check(not Sound.music_playing(), "música pausa fora do cardápio")
	tree.change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(tree, 0.3)
	_check(Sound.music_playing(), "música volta ao voltar")
	Prefs.set_music(false)
	Sound.refresh()
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(Sound.MUSIC_BUS)), "Música desligada cala o barramento")
	Prefs.set_sound(was_sound)
	Prefs.set_music(was_music)
	Sound.refresh()


func _probe_bowling(tree: SceneTree) -> void:
	var lane := BowlingLane.new()
	add_child(lane)
	var audio := BowlingAudio.new(lane)
	add_child(audio)
	lane.rack(BowlingRules.ALL_PINS)
	await tree.physics_frame
	lane.throw(PackedFloat32Array([0, 0, 0, 0]))
	var heard := {}
	var rolled := false
	var pin: AudioStream = Sound._streams[Sound.Cue.PIN]
	var knock: AudioStream = Sound._streams[Sound.Cue.KNOCK]
	var frames := 0
	while lane.rolling and frames < 900:
		await tree.physics_frame
		frames += 1
		rolled = rolled or audio._roll.volume_db > BowlingAudio.ROLL_DB - 10.0
		for voice: AudioStreamPlayer in Sound._voices:
			if voice.playing and (voice.stream == pin or voice.stream == knock):
				heard[voice.stream] = int(heard.get(voice.stream, 0)) + 1
	_check(rolled, "bola rolando sobe o laço do rolar")
	_check(heard.has(knock), "bola nos pinos faz o baque")
	_check(heard.has(pin), "pinos batendo soam")
	lane.queue_free()
	audio.queue_free()


func _wait(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds).timeout


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FALHA ", what)
