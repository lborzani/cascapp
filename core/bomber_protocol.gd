class_name BomberProtocol
extends RefCounted

## O que trafega entre o cliente de Bomberman e o servidor autoritativo, e em que
## ritmo.
##
## Números e formato num lugar só porque os dois lados têm de concordar — e a
## forma mais barata de discordarem é cada um ter a sua cópia do número. É o mesmo
## papel do `protocol.gd` do streetVolley, adaptado a este jogo: aqui o comando de
## um tique é **um byte** ([BomberRules] já o define assim), então não há um
## objeto de comando pra empacotar.
##
## ## Servidor dedicado, e não o relay
##
## Os outros cinco jogos deste app são por turno e falam pelo relay WebSocket. O
## Bomberman é o único em tempo real, e o lockstep P2P que ele usava paga um atraso
## de entrada fixo e trava quando qualquer aparelho engasga. Este protocolo é a
## outra metade da troca por um servidor autoritativo com predição no cliente — o
## modelo que o streetVolley já roda.

## Onde o servidor do Bomberman está. Nome e não IP, pelo mesmo motivo do volei:
## endereço residencial rotaciona e o provedor usa CGNAT. Trocar aqui exige build
## novo — o cliente não pergunta o endereço a ninguém.
##
## É um app do Fly separado do relay: o relay serve os jogos por turno e não roda
## simulação; este roda uma partida a [constant BomberRules.TICK_HZ] por sala.
const SERVER_HOST := "bomber.fly.dev"

const PORT := 27016

## A versão do protocolo. Sobe **sempre** que muda o formato de uma mensagem, o
## conjunto de RPCs, ou o significado de um campo. É um rótulo impresso nas duas
## pontas, não uma validação: o Godot numera RPC por posição, e um método novo no
## meio desloca os índices seguintes sem erro nenhum. A regra que ela documenta é
## **cliente e servidor sobem juntos**.
const VERSION := 1

## Snapshots por segundo. O estado inteiro do Bomberman é mais pesado que o do
## volei (três mapas de [constant BomberState.CELLS] casas mais as bombas), mas
## ainda cabe: ~500 bytes a 20 Hz são ~10 kB/s por cliente.
const SNAPSHOT_HZ := 20

## Comandos por mensagem de entrada. Um por tique seriam 30 mensagens por segundo
## por cliente; a dois são 15, e o atraso de juntar é um tique (33 ms).
const FRAME := 2

## Quantos comandos antigos cada mensagem de entrada repete.
##
## O comando é a única coisa que o servidor não reconstrói sozinho: um byte
## perdido é um tique em que ele não sabe o que o dedo pediu. Repetir os quatro
## anteriores custa quatro bytes e transforma uma perda de até 133 ms num soluço
## que ninguém vê. Ao contrário do lockstep, o servidor **não para** esperando o
## byte: segue com o último comando conhecido e corrige quando ele chega.
const HISTORY := 4

## Tiques que o servidor aceita de atraso num comando antes de desistir dele. Um
## comando que chega tarde demais é passado — aplicá-lo reescreveria uma jogada
## que já aconteceu na tela de todo mundo.
const INPUT_GRACE := 12

## Tiques de **adiantamento** que o servidor aceita num comando, e é o outro lado
## de [constant INPUT_GRACE].
##
## O atraso tinha teto e o adiantamento não tinha, e a falta era um vazamento de
## memória com endereço na internet. O tique do comando é um `s32` que vem do
## cliente; um cliente adulterado carimbava dois bilhões e a sala guardava aquilo
## na caixa de entrada do assento **para sempre** — `_forget_before` só apaga o
## que ficou para trás do tique atual, e o que está adiante dele nunca fica.
## Nenhum desses comandos chega a ser usado: a sala procura pelo tique do passo
## seguinte, que jamais alcança o número. Seis bytes por mensagem, dezenas de
## mensagens por segundo, sessenta e quatro peers — e a máquina de 512 MB cai sem
## que nenhuma regra do jogo tenha sido quebrada.
##
## Doze e não três: o cliente carimba o comando para [constant
## bomber_match.SEND_LEAD] tiques à frente do último snapshot e o relógio dele
## escorrega de propósito para manter essa folga. O teto tem de caber a folga
## legítima mais a oscilação da rede, e não a folga exata — o custo de ser
## generoso aqui é uma caixa de entrada com doze entradas a mais, e o custo de ser
## apertado é descartar o comando de quem está com a rede ruim.
const INPUT_LEAD := 12

## Teto de salas simultâneas. Numa porta aberta pra internet, criar sala é a única
## coisa que um estranho pede sem nada em troca, e cada sala custa uma simulação a
## 30 Hz. Sem teto, um laço de pedidos derruba a máquina.
const MAX_ROOMS := 100

enum Deny { UNKNOWN, NO_ROOM, ROOM_FULL, BAD_CODE, TOO_MANY_ROOMS, ALREADY_SEATED }

## Código de sala. Seis caracteres de um alfabeto sem os que se confundem ao ler em
## voz alta ou digitar. Mesmo esquema do volei.
const CODE_LENGTH := 6
const CODE_ALPHABET := "ACDEFGHJKLMNPQRTUVWXY479"


## `[tique do primeiro comando][quantos][comando, comando, …]`, um byte por
## comando.
##
## O tique vai junto porque UDP não promete ordem: sem ele, uma mensagem atrasada
## seria aplicada como se fosse a mais nova, e o boneco andaria pra trás.
static func write_inputs(first_tick: int, commands: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(5 + commands.size())
	out.encode_s32(0, first_tick)
	out.encode_u8(4, commands.size())
	for index in commands.size():
		out.encode_u8(5 + index, commands[index])
	return out


## Devolve `{"tick": int, "commands": PackedByteArray}`, ou vazio se a mensagem não
## faz sentido. Pacote malformado é lixo, e num servidor exposto à internet lixo é
## o caso normal, não a exceção.
static func read_inputs(raw: PackedByteArray) -> Dictionary:
	if raw.size() < 5:
		return {}
	var count := raw.decode_u8(4)
	if count <= 0 or count > FRAME + HISTORY:
		return {}
	if raw.size() < 5 + count:
		return {}
	return {"tick": raw.decode_s32(0), "commands": raw.slice(5, 5 + count)}


## `[tique da primeira linha][quantas][assentos][linha…]`, cada linha com um byte
## de comando por assento — o que o servidor **de fato usou** naquele tique.
##
## O número de assentos vai no cabeçalho porque a mesa do Bomberman é de dois a
## quatro, e sem ele o leitor não sabe o tamanho de cada linha. (No volei a mesa é
## sempre de quatro, então lá não precisa.)
##
## Sem estas linhas o cliente prevê os outros chutando, e chute erra em cima do que
## importa: um boneco cuja posição foi adivinhada solta bomba num lugar que o
## servidor vai desmentir. Com elas, o cliente reexecuta o passado com os comandos
## verdadeiros e o erro fica confinado aos poucos tiques que ainda não chegaram.
static func write_frame(first_tick: int, seats: int, rows: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(6 + rows.size() * seats)
	out.encode_s32(0, first_tick)
	out.encode_u8(4, rows.size())
	out.encode_u8(5, seats)
	var at := 6
	for row in rows:
		for seat in seats:
			out.encode_u8(at, row[seat] if seat < row.size() else 0)
			at += 1
	return out


## Devolve `{"tick": int, "seats": int, "rows": Array}` — cada linha é uma
## `PackedByteArray` de um comando por assento. Vazio se a mensagem não faz
## sentido.
static func read_frame(raw: PackedByteArray) -> Dictionary:
	if raw.size() < 6:
		return {}
	var count := raw.decode_u8(4)
	var seats := raw.decode_u8(5)
	if count <= 0 or count > FRAME + HISTORY:
		return {}
	if seats <= 0 or seats > 4:
		return {}
	if raw.size() < 6 + count * seats:
		return {}

	var rows: Array = []
	var at := 6
	for index in count:
		rows.append(raw.slice(at, at + seats))
		at += seats
	return {"tick": raw.decode_s32(0), "seats": seats, "rows": rows}


## Código novo, do relógio e de um contador. Não é sorteio criptográfico e não
## precisa ser: o código protege contra entrar na sala errada por engano, não
## contra alguém querendo entrar.
static func make_code(salt: int) -> String:
	var value := (Time.get_ticks_usec() + salt * 7919) & 0x7FFFFFFF
	var code := ""
	for index in CODE_LENGTH:
		code += CODE_ALPHABET[value % CODE_ALPHABET.length()]
		value /= CODE_ALPHABET.length()
	return code


static func valid_code(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false
	for letter in code:
		if not CODE_ALPHABET.contains(letter):
			return false
	return true
