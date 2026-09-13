class_name BomberLockstep
extends RefCounted

## O acerto de passo entre os aparelhos de uma partida de Bomberman.
##
## Nos outros cinco jogos o que viaja é o **lance**, e a posição é reconstruída
## aplicando lances. Aqui não há lance: há trinta tiques por segundo, e o que cada
## aparelho precisa saber é o que os dedos dos outros estavam fazendo em cada um
## deles. Então o que viaja é o **comando** — um byte por jogador por tique — e a
## posição não viaja nunca.
##
## Isso só se sustenta porque [BomberRules] é determinística até a última unidade:
## mesmos comandos, mesmo resultado, em qualquer processador. Esta classe é a
## outra metade daquela promessa — ela garante que todo aparelho roda o tique `n`
## com **exatamente** o mesmo conjunto de comandos, ou não o roda.
##
## ## O atraso de entrada
##
## O comando que o dedo dá no tique `n` só vale no tique `n + `[constant DELAY].
## Não é um defeito a corrigir: é o que dá à rede tempo de entregar o byte antes
## de ele ser necessário. Sem o atraso, todo tique esperaria uma viagem de ida e
## volta e a partida andaria na velocidade do pior ping.
##
## Cento e sessenta e sete milissegundos é o preço, e ele é pago no lugar certo: o
## boneco demora um pouco a sair, mas **nunca** engasga. A alternativa — prever o
## que o outro vai fazer e corrigir depois — devolve o boneco do adversário para
## trás na tela quando a previsão erra, que é bem pior de olhar num jogo de grade.
##
## O número não é escolhido sozinho: o que a rede tem para entregar um byte é o
## atraso **menos** o tempo de juntar a mensagem ([constant FRAME]). Com seis
## tiques de atraso e três de quadro eram 200 − 66 = 134 ms de viagem; com cinco e
## dois são 167 − 33 = 134 ms — a mesma folga de rede, 33 ms a menos no polegar.
## Mexer num sem o outro é que muda o risco de engasgo.
##
## ## Quando falta um byte
##
## A simulação **para**. Não há previsão, não há repetir o último comando: as duas
## coisas fazem dois aparelhos discordarem sobre o passado, e uma discordância
## sobre o passado nesta simulação é um jogador vivo numa tela e morto na outra
## vinte segundos depois, sem nada apontando para a causa.
##
## Parar é honesto e converge sozinho: todo mundo para no mesmo tique, e todo
## mundo volta quando o byte chega.
##
## ## Os bots não viajam
##
## [BomberBot] não sorteia nada e não olha o relógio: alimentado com os mesmos
## estados na mesma ordem, ele decide a mesma coisa em todo aparelho. Então a
## cadeira de máquina é calculada **localmente** por cada um, e não ocupa rede
## nenhuma. É a vantagem escondida de um bot sem aleatoriedade, e vale dizer em voz
## alta: se algum dia ele ganhar um `randi()`, o comando dele passa a ter de viajar
## como o de gente.

## Tiques entre pedir e valer. Cinco a trinta por segundo são 167 ms — a folga que
## cobre um relay do outro lado do país sem o jogo parecer pesado no polegar.
const DELAY := 5

## Comandos por mensagem.
##
## Um por tique seriam trinta mensagens por segundo por aparelho, e isso não é só
## deselegante: o relay corta a sessão de quem passa de **quarenta mensagens por
## segundo** (`rateMaxMessages`, em `relay/src/server.ts`). A trinta, qualquer
## mensagem a mais — o anúncio de uma saída, um repasse — encosta no teto, e o
## castigo é a conexão morrer no meio da partida.
##
## A dois comandos por mensagem são quinze por segundo, com folga de sobra para o
## resto do protocolo. O atraso de juntar (um tique, 33 ms) já está pago dentro de
## [constant DELAY], e é a metade dele que este número devolve ao polegar: juntar
## de três em três custava 66 ms a **todo** comando, e o teto do relay estava a
## quatro vezes de distância.
const FRAME := 2

## Quantas mensagens antigas cada mensagem repete.
##
## Um byte perdido **para a partida de todo mundo** até ele voltar, então a
## retransmissão não é otimização: é o que transforma uma perda de pacote num
## soluço invisível. Quatro mensagens de folga são 333 ms de perda contínua
## absorvidos sem ninguém ver, e custam dez bytes por mensagem.
##
## O número acompanha [constant FRAME]: o que a janela cobre é `FRAME ×
## (REDUNDANCY + 1)` tiques, e mensagens menores precisam de mais repetições para
## cobrir o mesmo tempo de perda.
const REDUNDANCY := 4

## Teto de tiques num histórico de retomada. Dois minutos — o dobro da janela em
## que o relay ainda guarda a cadeira de quem sumiu. Ver [method _resume_from].
const RESUME_TICKS := 3600

## O que uma mensagem carrega. O primeiro número de `p` diz qual das duas é.
enum Op {
	## `[INPUT, primeiro_tique, comando, comando, …]` — os comandos de quem
	## mandou. O assento não vai dentro: o relay carimba o remetente, e é nele que
	## se confia.
	INPUT,
	## `[DROP, assento, tique]` — a cadeira sai da partida naquele tique exato.
	DROP,
	## `[RELAY, assento, primeiro_tique, comando, …]` — os comandos **de outro**,
	## repassados por quem anuncia a saída dele.
	##
	## Existe só para o caso da queda, e é o que impede a saída de virar um
	## impasse: quem anuncia diz "a cadeira sai no tique T" e, junto, entrega tudo
	## o que ela chegou a pedir antes de T. Sem isso, um aparelho que ficou sem os
	## últimos bytes dela esperaria por eles para sempre — a cadeira já não está
	## lá para reenviá-los.
	RELAY,
}

## Nunca dropado. Guardado como constante porque a comparação aparece em três
## lugares e `-1` solto num `if` não diz o que significa.
const NEVER := -1


## Os comandos de um assento, indexados pelo tique em que valem.
##
## Dois vetores e não um dicionário: a busca por tique acontece uma vez por
## assento por tique, e um dicionário com milhares de chaves inteiras custa mais
## que um vetor com buracos. `present` existe porque zero é um comando legítimo —
## "não estou pedindo nada" — e não dá para confundi-lo com "ainda não chegou".
class Track extends RefCounted:
	var commands := PackedByteArray()
	var present := PackedByteArray()
	## Maior tique já preenchido. O vetor cresce em blocos, então o tamanho dele
	## não responde isso — e mandar o bloco inteiro num histórico entregaria zeros
	## do futuro como se fossem comando, que é a pior coisa que esta classe pode
	## fazer: o outro lado rodaria o tique em vez de esperar por ele.
	var highest := -1

	## Cresce em blocos e não no tique exato: uma partida de dois minutos são 3600
	## tiques, e realocar o vetor a cada um deles é o único gasto desta classe que
	## chegaria a aparecer num perfil.
	func put(tick: int, command: int) -> void:
		if tick < 0:
			return
		if tick >= present.size():
			var room := tick + 256
			commands.resize(room)
			present.resize(room)
		commands[tick] = command & 0xFF
		present[tick] = 1
		highest = maxi(highest, tick)

	func has(tick: int) -> bool:
		return tick >= 0 and tick < present.size() and present[tick] == 1

	func at(tick: int) -> int:
		return commands[tick] if has(tick) else 0


## Assentos de gente em **outros** aparelhos. São exatamente estes que a
## simulação espera: o local se conhece, e as máquinas são calculadas por todos.
var remote_seats := PackedInt32Array()

## Tiques entre pedir e valer, nesta partida.
##
## É [constant DELAY] em rede e **zero** fora dela. Sem rede não há byte para
## esperar, e cobrar o atraso ali seria cobrar o preço de um problema que não
## existe: o boneco sairia 200 ms depois do polegar numa partida contra bots.
##
## O caminho é o mesmo nos dois casos — a cena grava e lê pela trilha sempre —, e
## é isso que faz o modo solo exercitar o mesmo código que a rede usa.
var delay := DELAY

var _tracks := {}
## Assento → tique a partir do qual ele deixou a partida. Ver [method drop_seat].
var _dropped := {}
## Comandos locais já produzidos e ainda dentro da janela de retransmissão.
var _window := PackedByteArray()
## Tique a que o primeiro byte da janela corresponde.
var _window_from := 0
## Quantos comandos novos entraram na janela desde a última mensagem.
var _fresh := 0


## A trilha de um assento, criada na primeira pergunta.
##
## Ela nasce com os [constant DELAY] primeiros tiques zerados, e sem isso a
## partida não sai do lugar: o primeiro comando que alguém dá vale no tique
## `DELAY`, então ninguém tem comando para o tique zero — e a simulação esperaria
## para sempre por um byte que, por construção, não existe. Aqueles tiques iniciais
## são de verdade "ninguém está pedindo nada", e é isso que fica escrito aqui.
func track_of(seat: int) -> Track:
	if not _tracks.has(seat):
		var track := Track.new()
		for tick in delay:
			track.put(tick, 0)
		_tracks[seat] = track
	return _tracks[seat]


## Guarda o que este aparelho está pedindo no tique `tick`. O comando vale em
## `tick + DELAY`, e é lá que ele é gravado — quem lê depois não precisa saber que
## existe um atraso.
func record_local(seat: int, tick: int, command: int) -> void:
	track_of(seat).put(tick + delay, command)
	_window.append(command & 0xFF)
	_fresh += 1
	# A janela guarda o que uma mensagem manda mais o que ela repete. O que sai
	# dela já foi mandado quatro vezes; se essas quatro se perderam, o problema não
	# é mais de pacote perdido e quem resolve é a reconexão.
	var keep := FRAME * (REDUNDANCY + 1)
	if _window.size() > keep:
		var extra := _window.size() - keep
		_window = _window.slice(extra)
		_window_from += extra


## A mensagem a mandar agora, ou vazia se ainda não juntou um quadro.
##
## O tique do primeiro byte vai dentro: sem ele o receptor teria de contar
## mensagens para saber onde encaixá-las, e uma mensagem perdida desalinharia
## todas as seguintes — que é o modo mais silencioso possível de dessincronizar
## esta partida.
func take_frame() -> PackedInt32Array:
	if _fresh < FRAME:
		return PackedInt32Array()
	_fresh = 0
	var message := PackedInt32Array([Op.INPUT, _window_from + delay])
	for command in _window:
		message.append(command)
	return message


## Tudo o que este aparelho já pediu, do começo da partida.
##
## Existe para a volta de uma queda: a janela de retransmissão cobre 300 ms, e
## quem passou meio minuto sem rede perdeu bem mais que isso. Como o receptor
## ignora o que já tem, mandar a partida inteira é a resposta mais simples que
## está certa — e são 30 bytes por segundo de partida.
func full_history(seat: int) -> PackedInt32Array:
	var from := _resume_from(seat)
	var message := PackedInt32Array([Op.INPUT, from])
	_append_tail(message, seat, from)
	return message


## O mesmo histórico, mas de outro assento e dito em nome dele. Ver [enum Op].
func relayed_history(seat: int) -> PackedInt32Array:
	var from := _resume_from(seat)
	var message := PackedInt32Array([Op.RELAY, seat, from])
	_append_tail(message, seat, from)
	return message


## De que tique a retomada começa.
##
## O relay recusa mensagem acima de 32 KB, e a partida inteira em JSON passa disso
## depois de uns seis minutos — o histórico completo é uma bomba-relógio que só
## estoura na partida longa, que é justamente a que ninguém testa.
##
## O teto não perde nada: enquanto alguém está fora, **todo mundo para** de
## simular esperando por ele, e quem está fora para de produzir comando. O buraco a
## tapar é o da ausência, e o relay derruba a sala antes dos 95 segundos
## (`Net.ABSENCE_LIMIT`) — bem dentro de [constant RESUME_TICKS].
func _resume_from(seat: int) -> int:
	return maxi(0, track_of(seat).highest + 1 - RESUME_TICKS)


func _append_tail(message: PackedInt32Array, seat: int, from: int) -> void:
	var track := track_of(seat)
	for tick in range(from, track.highest + 1):
		message.append(track.commands[tick])


## O tique em que uma cadeira que caiu deve sair: o primeiro para o qual ela não
## mandou nada.
##
## É o tique exato em que a partida travou esperando por ela, então aplicá-lo
## destrava na mesma hora. Anunciar mais à frente pareceria mais seguro e seria o
## contrário: os outros continuariam esperando bytes que ninguém vai mandar.
func first_missing(seat: int) -> int:
	return track_of(seat).highest + 1


## Encaixa os comandos de um assento. Repetido é descartado sem custo: a
## retransmissão manda de propósito o que já foi mandado.
func receive_inputs(seat: int, first_tick: int, commands: PackedInt32Array) -> void:
	var track := track_of(seat)
	for offset in commands.size():
		var tick := first_tick + offset
		if track.has(tick):
			continue
		track.put(tick, commands[offset])


## A cadeira saiu da mesa, e sai **num tique combinado**.
##
## O tique vem de quem anuncia, e não do relógio de cada um: o relay avisa cada
## aparelho da saída em instantes diferentes, e uma cadeira que vira máquina no
## tique 900 aqui e no 903 ali são duas partidas diferentes a partir dali. Um
## número dito em voz alta é a única forma de os quatro concordarem.
func drop_seat(seat: int, tick: int) -> void:
	if _dropped.has(seat) and int(_dropped[seat]) <= tick:
		return
	_dropped[seat] = tick


## Tique em que a cadeira saiu, ou [constant NEVER].
func dropped_at(seat: int) -> int:
	return int(_dropped.get(seat, NEVER))


## A cadeira ainda é jogada por gente do outro lado neste tique?
func is_remote_at(seat: int, tick: int) -> bool:
	var left := dropped_at(seat)
	return left == NEVER or tick < left


## Dá para rodar este tique?
##
## Só olha os assentos remotos: o local já gravou o próprio comando com
## [constant DELAY] tiques de antecedência, e as máquinas saem da simulação.
func ready_for(tick: int) -> bool:
	for seat in remote_seats:
		if is_remote_at(seat, tick) and not track_of(seat).has(tick):
			return false
	return true


## Por quem a partida está esperando. Para a tela poder dizer o nome em vez de
## "aguarde".
func waiting_seats(tick: int) -> PackedInt32Array:
	var late := PackedInt32Array()
	for seat in remote_seats:
		if is_remote_at(seat, tick) and not track_of(seat).has(tick):
			late.append(seat)
	return late


## O comando de um assento neste tique. Zero depois de a cadeira sair — o boneco
## dela para de andar, e o que acontece com ele daí em diante é decisão de quem
## chama (a cena entrega a cadeira a uma máquina).
func command_of(seat: int, tick: int) -> int:
	if not is_remote_at(seat, tick):
		return 0
	return track_of(seat).at(tick)
