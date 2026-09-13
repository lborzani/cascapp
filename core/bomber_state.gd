class_name BomberState
extends RefCounted

## A partida de Bomberman inteira, num objeto que se copia.
##
## É o primeiro jogo do app que **não** é por turnos, e por isso não usa
## `MatchState`. Aquele guarda um tabuleiro, um lado da vez e uma lista de lances;
## aqui não existe vez, e o que existe é um instante — posições, pavios acesos e
## fogo no ar — que anda sozinho trinta vezes por segundo.
##
## ## Tudo inteiro, nada float
##
## Posição, velocidade e tempo são **inteiros**, e isso não é preciosismo: a
## partida roda em paralelo em cada aparelho e os dois têm de chegar ao mesmo
## instante a partir dos mesmos comandos. Um `float` some de formas ligeiramente
## diferentes em processadores diferentes, e uma diferença de um milésimo no
## quinto segundo vira um jogador vivo de um lado e morto do outro.
##
## A casa vale [constant CELL] unidades. Meia casa é 128, e um jogador está "na
## casa" quando o centro dele cai dentro dela — não há arredondamento a decidir.
##
## ## O sorteio também é estado
##
## O mapa e o que sai de cada caixa quebrada vêm de um gerador guardado **aqui
## dentro**, e não de `randi()`. Duas partidas com a mesma semente são a mesma
## partida, e é isso que permite a um aparelho que caiu refazer o que perdeu a
## partir da lista de comandos.

## Lado da casa em unidades internas. Potência de dois porque metade e quarto de
## casa aparecem em toda conta de colisão, e deslocamento de bit é exato.
const CELL := 256

## Tamanho clássico: ímpar nos dois eixos, para os pilares fixos caírem num
## xadrez perfeito e sobrar corredor entre eles.
const COLS := 13
const ROWS := 11

## O que ocupa uma casa.
enum Tile {
	FLOOR,
	## Pilar de concreto. Nunca sai, e é ele que dá o desenho de xadrez ao mapa.
	SOLID,
	## Caixa. Some no fogo, às vezes deixando um prêmio.
	BRICK,
}

## Prêmios que saem das caixas. `NONE` é a caixa que não deixa nada, e é a
## maioria — um mapa em que toda caixa dá prêmio vira uma corrida de coleta, não
## um jogo de posição.
enum Prize { NONE, BOMB, FLAME, SPEED }

## Um jogador. Guardado como classe e não como dicionário porque cada campo é
## lido dezenas de vezes por tique, e o acesso por chave de dicionário em GDScript
## custa mais que o campo.
class Bomber extends RefCounted:
	## Centro do boneco, em unidades. Não é a casa: ele anda entre casas.
	var x := 0
	var y := 0
	## Última direção pedida, para o boneco continuar olhando para onde andou.
	var facing := 2
	var alive := true
	## Tique em que ele morreu, para a tela poder mostrar a explosão antes de
	## tirá-lo do mapa.
	var died_at := -1
	## Quantas bombas ele consegue ter acesas ao mesmo tempo, e quantas casas o
	## fogo dele alcança em cada braço.
	var bombs := 1
	var flame := 1
	## Velocidade em unidades por tique.
	var speed := 32

	func clone() -> Bomber:
		var copy := Bomber.new()
		copy.x = x
		copy.y = y
		copy.facing = facing
		copy.alive = alive
		copy.died_at = died_at
		copy.bombs = bombs
		copy.flame = flame
		copy.speed = speed
		return copy


## Uma bomba acesa.
class Bomb extends RefCounted:
	var col := 0
	var row := 0
	var owner := 0
	## Tiques que faltam. Zero é a explosão deste tique.
	var fuse := 0
	var flame := 1
	## Máscara dos assentos que ainda podem atravessar esta bomba, um bit por
	## assento. Zero é "parede para todos".
	##
	## É uma máscara e não um assento só porque não é apenas o dono que pode estar
	## em cima dela: o corpo tem 81% da casa, então dois bonecos dividem casa o
	## tempo todo, e quem solta uma bomba solta debaixo do pé do outro. Com a
	## permissão de um assento só, o outro ficava **imóvel** — todas as quatro
	## posições candidatas dele encostavam na casa da bomba, o empurrão de quina
	## também, e ele esperava o pavio sem poder andar.
	##
	## A permissão é **grudenta e de mão única**: vale até o corpo daquele assento
	## deixar a casa, e depois disso não volta. Sem isso, o dono entra e sai da
	## própria bomba à vontade e ela vira um abrigo em vez de uma ameaça.
	var pass_seats := 0

	func clone() -> Bomb:
		var copy := Bomb.new()
		copy.col = col
		copy.row = row
		copy.owner = owner
		copy.fuse = fuse
		copy.flame = flame
		copy.pass_seats = pass_seats
		return copy


var tick := 0
var seats := 4
var players: Array[Bomber] = []
var bombs: Array[Bomb] = []
## Mapa em ordem de linha, `row * COLS + col`, com valores de [enum Tile].
var tiles := PackedByteArray()
## Prêmio escondido em cada casa, com valores de [enum Prize]. Só significa
## alguma coisa onde há caixa — ou onde o fogo acabou de derrubar uma.
var prizes := PackedByteArray()
## Tiques que faltam de fogo em cada casa. Zero é casa sem fogo.
var flames := PackedByteArray()
## Estado do gerador determinístico. Ver [method BomberRules.next_random].
var seed_state := 1


func clone() -> BomberState:
	var copy := BomberState.new()
	copy.tick = tick
	copy.seats = seats
	copy.seed_state = seed_state
	# `duplicate()` nos empacotados: eles são cópia-na-escrita, e escrever pelo
	# caminho (`tiles[i] = x`) mexeria no vetor do original. É a mesma armadilha
	# que `MatchState.clone()` já registrou.
	copy.tiles = tiles.duplicate()
	copy.prizes = prizes.duplicate()
	copy.flames = flames.duplicate()
	for player in players:
		copy.players.append(player.clone())
	for bomb in bombs:
		copy.bombs.append(bomb.clone())
	return copy


## Casas do mapa. Os três vetores de terreno — [member tiles], [member prizes] e
## [member flames] — têm exatamente este tamanho.
const CELLS := COLS * ROWS

## Bytes fixos do cabeçalho de um snapshot: tique, assentos, semente, e as duas
## contagens (jogadores e bombas). O resto do tamanho é variável.
const _SNAP_HEAD := 4 + 1 + 4 + 1 + 1
## Bytes de um jogador no fio. Todos os campos de [class Bomber] cabem: as faixas
## de bombas, fogo e velocidade são limitadas por [BomberRules] a menos de 256.
const _SNAP_PLAYER := 4 + 4 + 1 + 1 + 4 + 1 + 1 + 1
## Bytes de uma bomba no fio. `fuse` chega a [constant BomberRules.FUSE] (90) e
## cabe num byte; `pass_seats` é uma máscara de quatro bits.
const _SNAP_BOMB := 1 + 1 + 1 + 1 + 1 + 1


## O estado inteiro em bytes, pro servidor mandar e o cliente aceitar.
##
## ## Tamanho variável, ao contrário do volei
##
## Um snapshot de volei tem sempre quatro atletas e nada mais, então cabe num
## tamanho fixo. Aqui a partida tem de dois a quatro bonecos e um número de bombas
## que muda a cada tique, mais três mapas de [constant CELLS] casas. Por isso as
## contagens vão no cabeçalho e o leitor reconstrói as listas a partir delas.
##
## São ~500 bytes numa partida cheia (quatro jogadores, várias bombas). A
## [constant BomberProtocol.SNAPSHOT_HZ] snapshots por segundo é o orçamento de
## download do jogo, e cabe com folga num pacote ENet.
##
## ## O que **não** viaja
##
## Nada de `float`: a partida é toda inteira de propósito (ver o topo do arquivo),
## e é o que deixa o cliente reexecutar o passado e chegar ao mesmo bit que o
## servidor. A semente viaja porque o replay depende dela.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(_SNAP_HEAD + 3 * CELLS + players.size() * _SNAP_PLAYER + bombs.size() * _SNAP_BOMB)
	var at := 0

	out.encode_s32(at, tick); at += 4
	out.encode_u8(at, seats); at += 1
	out.encode_u32(at, seed_state & 0xFFFFFFFF); at += 4
	out.encode_u8(at, players.size()); at += 1
	out.encode_u8(at, bombs.size()); at += 1

	# Os três mapas em bloco. `duplicate` não: escrever byte a byte num destino já
	# dimensionado é mais barato e não realoca.
	for cell in CELLS:
		out.encode_u8(at + cell, tiles[cell] if cell < tiles.size() else 0)
	at += CELLS
	for cell in CELLS:
		out.encode_u8(at + cell, prizes[cell] if cell < prizes.size() else 0)
	at += CELLS
	for cell in CELLS:
		out.encode_u8(at + cell, flames[cell] if cell < flames.size() else 0)
	at += CELLS

	for player in players:
		out.encode_s32(at, player.x); at += 4
		out.encode_s32(at, player.y); at += 4
		out.encode_u8(at, player.facing); at += 1
		out.encode_u8(at, 1 if player.alive else 0); at += 1
		out.encode_s32(at, player.died_at); at += 4
		out.encode_u8(at, player.bombs); at += 1
		out.encode_u8(at, player.flame); at += 1
		out.encode_u8(at, player.speed); at += 1

	for bomb in bombs:
		out.encode_u8(at, bomb.col); at += 1
		out.encode_u8(at, bomb.row); at += 1
		out.encode_u8(at, bomb.owner); at += 1
		out.encode_u8(at, bomb.fuse); at += 1
		out.encode_u8(at, bomb.flame); at += 1
		out.encode_u8(at, bomb.pass_seats); at += 1

	return out


## Reconstrói o estado a partir dos bytes. Devolve `false` se a mensagem não bate
## com o que o cabeçalho promete — um pacote curto é lixo, e aceitar lixo aqui
## vira uma partida que diverge sem explicação.
##
## Reconstrói as listas em vez de preencher as existentes (como o volei faz): o
## número de bonecos e de bombas é justamente o que muda, então não há lista de
## tamanho certo pra reaproveitar.
func from_bytes(raw: PackedByteArray) -> bool:
	if raw.size() < _SNAP_HEAD + 3 * CELLS:
		return false
	var at := 0

	tick = raw.decode_s32(at); at += 4
	seats = raw.decode_u8(at); at += 1
	seed_state = raw.decode_u32(at); at += 4
	var player_count := raw.decode_u8(at); at += 1
	var bomb_count := raw.decode_u8(at); at += 1

	if raw.size() < _SNAP_HEAD + 3 * CELLS + player_count * _SNAP_PLAYER + bomb_count * _SNAP_BOMB:
		return false

	tiles = raw.slice(at, at + CELLS); at += CELLS
	prizes = raw.slice(at, at + CELLS); at += CELLS
	flames = raw.slice(at, at + CELLS); at += CELLS

	players = []
	for index in player_count:
		var player := Bomber.new()
		player.x = raw.decode_s32(at); at += 4
		player.y = raw.decode_s32(at); at += 4
		player.facing = raw.decode_u8(at); at += 1
		player.alive = raw.decode_u8(at) == 1; at += 1
		player.died_at = raw.decode_s32(at); at += 4
		player.bombs = raw.decode_u8(at); at += 1
		player.flame = raw.decode_u8(at); at += 1
		player.speed = raw.decode_u8(at); at += 1
		players.append(player)

	bombs = []
	for index in bomb_count:
		var bomb := Bomb.new()
		bomb.col = raw.decode_u8(at); at += 1
		bomb.row = raw.decode_u8(at); at += 1
		bomb.owner = raw.decode_u8(at); at += 1
		bomb.fuse = raw.decode_u8(at); at += 1
		bomb.flame = raw.decode_u8(at); at += 1
		bomb.pass_seats = raw.decode_u8(at); at += 1
		bombs.append(bomb)

	return true


static func index_of(col: int, row: int) -> int:
	return row * COLS + col


func tile_at(col: int, row: int) -> int:
	if col < 0 or col >= COLS or row < 0 or row >= ROWS:
		return Tile.SOLID
	return tiles[index_of(col, row)]


func bomb_at(col: int, row: int) -> Bomb:
	for bomb in bombs:
		if bomb.col == col and bomb.row == row:
			return bomb
	return null


## Quantos ainda estão de pé. É por isto que a partida acaba.
func alive_count() -> int:
	var total := 0
	for player in players:
		if player.alive:
			total += 1
	return total
