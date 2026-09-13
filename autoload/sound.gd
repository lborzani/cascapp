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
}

## 22 kHz mono. É metade da taxa de CD e ninguém ouve a diferença num clique de
## 30 ms saindo de um alto-falante de celular; em compensação, os oito sinais
## inteiros cabem em menos de 100 KB de memória.
const RATE := 22050

## Quantos sons podem soar ao mesmo tempo. Quatro cobre o pior caso real — dois
## dados parando junto de um peão andando — com folga para um aviso por cima.
const VOICES := 4

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


func _ready() -> void:
	# Continua tocando com a árvore pausada: o autoload sobrevive a trocas de cena
	# e não deve emudecer numa transição.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	for cue in Cue.values():
		_streams[cue] = _bake(cue)


## Toca um sinal. Silencioso e sem custo quando o jogador desligou o som — a
## checagem mora aqui e não em cada chamador, senão cada tela nova teria de
## lembrar de perguntar.
func play(cue: int) -> void:
	if not Prefs.sound_on():
		return
	var stream: AudioStream = _streams.get(cue, null)
	if stream == null:
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = float(LEVELS.get(cue, -12.0))
	voice.play()
	_buzz(cue)


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
			# Ruído curtíssimo: o ouvido lê ataque rápido sem altura definida como
			# "encostou em alguma coisa dura".
			return _wave(0.035, func(t: float, _n: float) -> float:
				return _noise(t) * _fall(t, 0.035, 34.0)
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
	return _wave(0.02, func(_t: float, _n: float) -> float: return 0.0)


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
