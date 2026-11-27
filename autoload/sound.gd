extends Node

## Autoload `Sound`: o som e a vibração do app inteiro.
##
## Oito sinais, e não oito arquivos por jogo. Um toque de peça soa igual no
## xadrez, nas damas e no Ludo porque **é** a mesma coisa acontecendo, e um banco
## de sons por jogo seria cinco vocabulários que divergem no dia em que alguém
## trocar um deles.
##
## ## As ondas são geradas em código
##
## Nenhum arquivo de áudio no repositório. É a mesma decisão do tabuleiro
## desenhado, das peças em primitivas e do QR escrito à mão: o app inteiro é
## código, e um efeito de 0,2 segundo é um envelope exponencial sobre ruído ou
## sobre duas senóides — dez linhas de matemática contra um binário com licença
## a rastrear.
##
## **O limite disso é honesto e vale dito**: som sintetizado acerta o *clique*, o
## *baque* e o *chocalho*, que são ataque curto e decaimento rápido. Ele não faz
## timbre — uma moeda de verdade tem harmônicos que uma soma de senóides não
## reproduz sem virar um sintetizador. Se um dia o app quiser textura em vez de
## sinal, é aqui que um pacote de amostras entra, e só a tabela de `_bake` muda.
##
## ## Tudo curto, e nada em cima de nada
##
## Os oito cabem em meio segundo cada. Num jogo de tabuleiro o som é **pontuação**
## — ele diz que a coisa aconteceu e sai do caminho. Um efeito de dois segundos
## ainda está tocando quando o jogador faz a próxima escolha, e aí ele deixa de
## informar e passa a atrapalhar.
##
## Uma roda de tocadores em vez de um só: o dado e o passo do peão se sobrepõem
## por desenho, e um tocador único cortaria o primeiro no meio para começar o
## segundo.
##
## ## A vibração acompanha, e é mais curta ainda
##
## Só nos três sinais em que alguma coisa **encosta**: o toque, o baque e o dado.
## Vibrar a cada evento transforma o aparelho num alarme, e vibrar no fim da
## partida é comemorar com o bolso do jogador.

## O que aconteceu. É o vocabulário inteiro do app.
enum Cue {
	## Um toque que foi aceito — casa selecionada, botão do tabuleiro.
	TAP,
	## Uma peça pousou.
	MOVE,
	## Alguém foi derrubado: captura no xadrez e nas damas, peão à base no Ludo,
	## tiro certeiro na batalha naval.
	CAPTURE,
	## O dado parou.
	DICE,
	## Dinheiro mudou de mão.
	CASH,
	## Uma carta virou.
	CARD,
	## A partida acabou.
	WIN,
	## Não deu — lance recusado, aviso de perigo.
	ALERT,
	## Uma folha subiu: um sopro curto e abafado.
	SHEET,
	## Madeira contra madeira: um pino batendo (boliche). Quem toca dá o peso
	## pela velocidade (`gain_db`) e varia a altura (`pitch`).
	PIN,
	## A bola chegando aos pinos: o baque grave que abre o estrondo.
	KNOCK,
}

## Os sons que ficam tocando em laço, gerados numa thread na abertura (ver
## [method loop]).
enum Loop {
	## A música da tela inicial.
	MUSIC,
	## O salão do boliche: murmúrio de gente e pinos caindo em pistas distantes.
	HALL,
	## A bola rolando na madeira.
	ROLL,
	## A bola na canaleta: mais oco e mais grave.
	GUTTER,
}

## Os barramentos. Criados aqui em código, como o resto do som: o `Master` é do
## Godot, e cada um destes manda nele.
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"

## As cenas com música: as abas do cardápio (Jogos, Online, Loja, Você). Fora
## delas — partida, pareamento — a música desce e pausa, e volta de onde parou.
const MUSIC_SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/join.tscn",
	"res://scenes/shop.tscn",
	"res://scenes/settings.tscn",
]
## Volume da música, em dB. Baixa: ela é fundo do cardápio, não trilha de cinema.
const MUSIC_DB := -15.0
## Quanto o fade leva, em segundos.
const MUSIC_FADE := 0.8
const SILENT_DB := -60.0

## 22 kHz mono. É metade da taxa de CD e ninguém ouve a diferença num clique de
## 30 ms saindo de um alto-falante de celular; em compensação, os oito sinais
## inteiros cabem em menos de 100 KB de memória.
const RATE := 22050

## Quantos sons podem soar ao mesmo tempo. Quatro cobre o pior caso real — dois
## dados parando junto de um peão andando — com folga para um aviso por cima.
const VOICES := 10

## Volume de cada sinal, em decibéis relativos. Eles não nascem no mesmo peso: o
## chocalho do dado é ruído de banda larga e soa bem mais alto que uma senóide de
## mesma amplitude, e o passo do peão toca dez vezes seguidas num lance só.
const LEVELS := {
	Cue.TAP: -14.0,
	Cue.MOVE: -12.0,
	Cue.CAPTURE: -8.0,
	Cue.DICE: -11.0,
	Cue.CASH: -10.0,
	Cue.CARD: -13.0,
	Cue.WIN: -7.0,
	Cue.ALERT: -9.0,
	Cue.SHEET: -17.0,
	Cue.PIN: -6.0,
	Cue.KNOCK: -4.0,
}

## Duração da vibração, em milissegundos, nos sinais que a têm. Curtíssimas de
## propósito: o que se quer é a impressão de contato, e acima de uns 40 ms isso
## vira zumbido.
const BUZZ := {
	Cue.TAP: 12,
	Cue.MOVE: 16,
	Cue.CAPTURE: 34,
	Cue.DICE: 24,
}

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
## Quadro em que cada sinal tocou por último (ver [method play]).
var _played := {}
## Laços prontos, `Loop -> AudioStreamWAV`. Preenchido pela thread.
var _loops := {}
var _baker: Thread = null
var _music: AudioStreamPlayer = null
var _music_tween: Tween = null


func _ready() -> void:
	# Continua tocando com a árvore pausada: o autoload sobrevive a trocas de cena
	# e não deve emudecer numa transição.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add_bus(MUSIC_BUS)
	_add_bus(SFX_BUS)
	for index in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voices.append(voice)
	for cue in Cue.values():
		_streams[cue] = _bake(cue)
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	_music.volume_db = SILENT_DB
	add_child(_music)
	get_tree().scene_changed.connect(_follow_scene)
	refresh()
	# Os laços somam ~30 s de áudio: amostra a amostra em GDScript, isso é
	# perceptível na abertura. Na thread o app abre na hora, e a música entra
	# quando fica pronta.
	_baker = Thread.new()
	_baker.start(_bake_loops)


func _exit_tree() -> void:
	if _baker != null and _baker.is_started():
		_baker.wait_to_finish()


func _add_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, &"Master")


## Aplica os interruptores: "Som" cala tudo, "Música" só a música. Quem muda um
## deles chama isto.
func refresh() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SFX_BUS), not Prefs.sound_on())
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MUSIC_BUS), not music_allowed())
	_follow_scene()


func music_allowed() -> bool:
	return Prefs.sound_on() and Prefs.music_on()


## Toca um sinal. Silencioso e sem custo quando o jogador desligou o som — a
## checagem mora aqui e não em cada chamador, senão cada tela nova teria de
## lembrar de perguntar.
##
## O mesmo sinal duas vezes no mesmo quadro toca uma vez: todo botão já faz o
## clique sozinho (`Nav`), e as telas que chamavam `play(TAP)` no próprio botão
## não precisam saber disso.
func play(cue: int, gain_db := 0.0, pitch := 1.0) -> void:
	if not Prefs.sound_on():
		return
	# Só o toque puro: as batidas dos pinos (com peso e altura) soam juntas.
	var frame := Engine.get_process_frames()
	if gain_db == 0.0 and pitch == 1.0:
		if _played.get(cue, -1) == frame:
			return
		_played[cue] = frame
	var stream: AudioStream = _streams.get(cue, null)
	if stream == null:
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = float(LEVELS.get(cue, -12.0)) + gain_db
	voice.pitch_scale = pitch
	voice.play()
	_buzz(cue)


## O laço pronto, ou `null` enquanto a thread ainda o gera.
func loop(which: int) -> AudioStreamWAV:
	return _loops.get(which, null)


## A música segue a cena: sobe nas do cardápio, desce e pausa nas outras. Pausa
## e não para, para voltar de onde estava.
func _follow_scene() -> void:
	if _music == null or not is_inside_tree():
		return
	var scene := get_tree().current_scene
	var wanted := music_allowed() and scene != null and scene.scene_file_path in MUSIC_SCENES
	if _music.stream == null:
		_music.stream = loop(Loop.MUSIC)
		if _music.stream == null:
			return
	var fading_out := not wanted and _music.playing and not _music.stream_paused
	if not wanted and not fading_out:
		return
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	if wanted:
		if not _music.playing:
			_music.play()
		_music.stream_paused = false
		_music_tween.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_FADE)
	else:
		_music_tween.tween_property(_music, "volume_db", SILENT_DB, MUSIC_FADE)
		_music_tween.tween_callback(func() -> void: _music.stream_paused = true)


## A música no ar (tocando e não pausada). Para as sondas.
func music_playing() -> bool:
	return _music != null and _music.playing and not _music.stream_paused


## Vibração curta, só nos sinais de contato e só onde o aparelho tem o motor.
## `vibrate_handheld` não faz nada no desktop, então não há o que testar antes.
func _buzz(cue: int) -> void:
	if not Prefs.haptics_on() or not BUZZ.has(cue):
		return
	Input.vibrate_handheld(int(BUZZ[cue]))


# --- síntese ------------------------------------------------------------------


## A onda de cada sinal.
##
## Todas seguem a mesma forma: uma fonte (ruído ou senóides) multiplicada por um
## envelope que cai. O que distingue um clique de um baque é **quanto tempo leva
## para cair**, e não a nota — por isso os números que importam aqui são os
## decaimentos, e não as frequências.
func _bake(cue: int) -> AudioStreamWAV:
	match cue:
		Cue.TAP:
			# Um "toc" abafado: senóide grave curta com um pouco de ruído passado
			# por um passa-baixa. Ruído cru (o clique antigo) era todo agudo e,
			# tocando em todo botão, cansava.
			var low := [0.0]
			return _wave(0.05, func(t: float, _n: float) -> float:
				low[0] += 0.18 * (_noise(t) - low[0])
				return (
					sin(TAU * 340.0 * t) * 0.55 * _fall(t, 0.05, 22.0)
					+ low[0] * 1.4 * _fall(t, 0.05, 40.0)
				)
			)
		Cue.MOVE:
			# Madeira: uma fundamental grave com um estalo de ruído por cima. Só a
			# senóide soa a apito; só o ruído soa a estática.
			return _wave(0.11, func(t: float, _n: float) -> float:
				return (
					sin(TAU * 210.0 * t) * 0.7 * _fall(t, 0.11, 20.0)
					+ _noise(t) * 0.5 * _fall(t, 0.11, 60.0)
				)
			)
		Cue.CAPTURE:
			# O mesmo baque uma oitava abaixo e mais demorado. Mais grave e mais
			# longo é o que o ouvido lê como "maior", e captura é o lance que pesa.
			return _wave(0.20, func(t: float, _n: float) -> float:
				return (
					sin(TAU * 120.0 * t) * 0.8 * _fall(t, 0.20, 12.0)
					+ _noise(t) * 0.6 * _fall(t, 0.20, 26.0)
				)
			)
		Cue.DICE:
			# Chocalho: ruído recortado por uma modulação rápida, que é o que
			# separa "dado quicando" de "chiado". A queda é lenta no começo e
			# rápida no fim, como um objeto que perde energia a cada quique.
			return _wave(0.26, func(t: float, _n: float) -> float:
				var clatter := 0.5 + 0.5 * sin(TAU * 38.0 * t)
				return _noise(t) * clatter * _fall(t, 0.26, 9.0)
			)
		Cue.CASH:
			# Duas notas subindo, curtas e limpas. Subir é o sinal universal de
			# "entrou"; a tela é quem diz se entrou para você ou para o outro.
			return _wave(0.26, func(t: float, _n: float) -> float:
				var note := 784.0 if t > 0.09 else 587.0
				return sin(TAU * note * t) * 0.7 * _fall(t, 0.26, 11.0)
			)
		Cue.CARD:
			# Papel: ruído com o brilho caindo — abre num sopro e fecha seco.
			return _wave(0.18, func(t: float, _n: float) -> float:
				var swell := sin(PI * clampf(t / 0.18, 0.0, 1.0))
				return _noise(t) * 0.8 * swell * swell
			)
		Cue.WIN:
			# Três notas de um acorde maior, uma a cada terço. O único sinal longo
			# do conjunto, e ele só toca quando não há mais nada a fazer.
			return _wave(0.62, func(t: float, _n: float) -> float:
				var step := mini(2, int(t / 0.16))
				var note: float = [523.25, 659.25, 783.99][step]
				var since := t - step * 0.16
				return sin(TAU * note * t) * 0.6 * _fall(since, 0.30, 7.0)
			)
		Cue.ALERT:
			# Duas notas descendo. Descer é o oposto exato do dinheiro entrando, e
			# usar o mesmo eixo para as duas notícias é o que as torna
			# reconhecíveis sem se confundirem.
			return _wave(0.24, func(t: float, _n: float) -> float:
				var note := 311.13 if t > 0.10 else 415.30
				return sin(TAU * note * t) * 0.7 * _fall(t, 0.24, 10.0)
			)
		Cue.SHEET:
			# Ar: ruído abafado (passa-baixa) que incha e some. Mais grave e mais
			# baixo que a carta, para não competir com o clique do botão.
			var low := [0.0]
			return _wave(0.16, func(t: float, _n: float) -> float:
				low[0] += 0.12 * (_noise(t) - low[0])
				var swell := sin(PI * clampf(t / 0.16, 0.0, 1.0))
				return low[0] * 3.0 * swell * swell
			)
		Cue.PIN:
			# Madeira dura e oca: duas parciais altas que somem rápido, mais um
			# estalo. A altura alta é o que separa o pino da bola.
			return _wave(0.16, func(t: float, _n: float) -> float:
				return (
					sin(TAU * 820.0 * t) * 0.5 * _fall(t, 0.16, 26.0)
					+ sin(TAU * 1930.0 * t) * 0.3 * _fall(t, 0.16, 40.0)
					+ _noise(t) * 0.6 * _fall(t, 0.16, 80.0)
				)
			)
		Cue.KNOCK:
			# A bola de 7 kg entrando no triângulo: grave e longo.
			var low := [0.0]
			return _wave(0.32, func(t: float, _n: float) -> float:
				low[0] += 0.2 * (_noise(t) - low[0])
				return (
					sin(TAU * 95.0 * t) * 0.6 * _fall(t, 0.32, 10.0)
					+ low[0] * 1.6 * _fall(t, 0.32, 14.0)
				)
			)
	return _wave(0.02, func(_t: float, _n: float) -> float: return 0.0)


# --- laços ----------------------------------------------------------------------


## Roda na thread: gera os quatro laços e entrega ao nó no quadro seguinte.
func _bake_loops() -> void:
	var baked := {
		Loop.MUSIC: _music_loop(),
		Loop.HALL: _hall_loop(),
		Loop.ROLL: _roll_loop(),
		Loop.GUTTER: _gutter_loop(),
	}
	_loops_ready.call_deferred(baked)


func _loops_ready(baked: Dictionary) -> void:
	_loops = baked
	_follow_scene()


## Lo-fi de cardápio: quatro acordes de 4 s (Dó7M, Lám7, Fá7M, Sol6) num pad que
## respira com cada acorde, e um arpejo dedilhado em colcheias de meio segundo.
## Uma oitava acima do natural: alto-falante de celular não reproduz grave, e o
## que ele não toca vira só barulho.
func _music_loop() -> AudioStreamWAV:
	const CHORD := 4.0
	const STEP := 0.5
	var chords := [
		[261.63, 329.63, 392.0, 493.88],
		[220.0, 261.63, 329.63, 392.0],
		[174.61, 220.0, 261.63, 329.63],
		[196.0, 246.94, 293.66, 329.63],
	]
	var order := [0, 1, 2, 3, 2, 1, 2, 3]
	var length := CHORD * chords.size()
	var steps := int(length / STEP)
	var count := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for index in count:
		var t := float(index) / RATE
		var chord: Array = chords[int(t / CHORD)]
		var inside := fmod(t, CHORD)
		var breath := smoothstep(0.0, 0.7, inside) * smoothstep(CHORD, CHORD - 0.7, inside)
		var pad := 0.0
		for note: float in chord:
			pad += sin(TAU * note * t) + 0.25 * sin(TAU * note * 2.0 * t)
		pad *= breath * 0.09 * (0.85 + 0.15 * sin(TAU * 0.25 * t))
		# As duas notas do arpejo que ainda soam: a de agora e a anterior, que
		# no início do laço é a última dele (o laço fecha sem emenda).
		var pluck := 0.0
		var at := int(t / STEP)
		for back in 2:
			var which := (at - back + steps) % steps
			var since := t - float(at - back) * STEP
			var root: Array = chords[int(which * STEP / CHORD)]
			var note: float = root[order[which % order.size()]] * 2.0
			var envelope := minf(1.0, since / 0.006) * exp(-since * 5.0)
			pluck += (sin(TAU * note * since) + 0.3 * sin(TAU * note * 2.0 * since)) * envelope
		out[index] = pad + pluck * 0.22
	return _pcm(_normalized(out, 0.7), true)


## Salão de boliche: murmúrio (ruído na faixa da voz, com a intensidade
## variando devagar, como conversa) e dois estrondos de pinos em pistas longe.
func _hall_loop() -> AudioStreamWAV:
	const LENGTH := 8.0
	var crashes := [1.9, 5.6]
	var out := _seamless(LENGTH, func(t: float, state: Array) -> float:
		var noise := _noise(t)
		state[0] += 0.16 * (noise - state[0])
		state[1] += 0.02 * (noise - state[1])
		var babble := 0.65 + 0.35 * sin(TAU * 1.3 * t) * sin(TAU * 0.37 * t + 1.0)
		var value: float = (state[0] - state[1]) * babble
		state[2] += 0.3 * (noise - state[2])
		for at: float in crashes:
			var since := t - at
			if since >= 0.0 and since < 1.0:
				var clatter := 0.4 + 0.6 * absf(sin(TAU * 23.0 * since))
				value += state[2] * 0.5 * clatter * exp(-since * 4.5) * minf(1.0, since / 0.01)
		return value
	)
	return _pcm(_normalized(out, 0.6), true)


## A bola rolando: ronco grave de madeira com um balanço leve, que é a bola
## girando. Quem toca muda volume e altura pela velocidade.
func _roll_loop() -> AudioStreamWAV:
	var out := _seamless(1.5, func(t: float, state: Array) -> float:
		var noise := _noise(t)
		state[0] += 0.03 * (noise - state[0])
		state[1] += 0.12 * (noise - state[1])
		var wobble := 0.8 + 0.2 * sin(TAU * 3.0 * t)
		return (state[0] * 1.0 + state[1] * 0.25 + sin(TAU * 62.0 * t) * 0.04) * wobble
	)
	return _pcm(_normalized(out, 0.8), true)


## A canaleta: o mesmo ronco passando por um ressoador em ~180 Hz, que é o tubo
## de metal oco em volta da bola.
func _gutter_loop() -> AudioStreamWAV:
	var w := TAU * 180.0 / RATE
	var r := 0.996
	var out := _seamless(1.5, func(t: float, state: Array) -> float:
		var noise := _noise(t)
		state[0] += 0.05 * (noise - state[0])
		var ring: float = 2.0 * r * cos(w) * state[1] - r * r * state[2] + state[0] * 0.02
		state[2] = state[1]
		state[1] = ring
		return ring + state[0] * 0.5
	)
	return _pcm(_normalized(out, 0.8), true)


## Gera `seconds` de som que emenda sem estalo quando repete: gera um pouco
## além do fim e funde essa sobra no começo. `shape(t, estado)` recebe um
## `Array` de estado (filtros) que persiste entre as amostras.
func _seamless(seconds: float, shape: Callable) -> PackedFloat32Array:
	var count := int(seconds * RATE)
	var blend := int(0.25 * RATE)
	var state := [0.0, 0.0, 0.0, 0.0]
	var raw := PackedFloat32Array()
	raw.resize(count + blend)
	for index in raw.size():
		raw[index] = float(shape.call(float(index) / RATE, state))
	var out := raw.slice(0, count)
	for index in blend:
		var weight := float(index) / blend
		out[index] = raw[index] * weight + raw[count + index] * (1.0 - weight)
	return out


static func _normalized(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0001
	for value in samples:
		top = maxf(top, absf(value))
	var scale := peak / top
	for index in samples.size():
		samples[index] *= scale
	return samples


## Margem, em amostras, em volta de um laço. O resampler do Godot lê amostras
## vizinhas além de `loop_end` (e antes de `loop_begin`): com o laço colado nas
## pontas do buffer ele lia fora da memória e o app fechava na primeira volta da
## música (SIGSEGV na thread de áudio, 1.84). A margem repete o outro lado do
## laço, então a interpolação continua sem emenda.
const LOOP_PAD := 16


static func _pcm(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var count := samples.size()
	if looped:
		samples = samples.slice(count - LOOP_PAD) + samples + samples.slice(0, LOOP_PAD)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size():
		bytes.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = LOOP_PAD
		stream.loop_end = LOOP_PAD + count
	return stream


## Monta o `AudioStreamWAV` chamando `shape(t, progresso)` amostra a amostra.
##
## 16 bits com sinal, mono, sem laço: é o formato que o Godot toca sem
## importação, e é o que permite estes sons existirem sem um arquivo no
## repositório.
func _wave(seconds: float, shape: Callable) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for index in count:
		var t := float(index) / RATE
		var value := clampf(float(shape.call(t, float(index) / count)), -1.0, 1.0)
		bytes.encode_s16(index * 2, int(value * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## Envelope que cai. `strength` é quantas vezes ele se divide ao longo de
## `seconds` — 34 é um estalo, 7 é uma nota que sustenta.
static func _fall(t: float, seconds: float, strength: float) -> float:
	if t < 0.0:
		return 0.0
	return exp(-strength * t / maxf(0.0001, seconds))


## Ruído determinístico a partir do tempo.
##
## Uma função de dispersão e não `randf()`: assim as oito ondas saem **idênticas
## em toda execução**, e um som que muda a cada abertura do app é um som que
## ninguém consegue julgar nem corrigir.
static func _noise(t: float) -> float:
	var seed_value := int(t * RATE) * 1103515245 + 12345
	seed_value = (seed_value ^ (seed_value >> 16)) * 2654435761
	return float(seed_value & 0xFFFF) / 32768.0 - 1.0
