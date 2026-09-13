class_name Board
extends RefCounted

## Square/piece encoding shared by both rulesets.
##
## A square index is `rank * 8 + file`, with rank 0 = White's back rank and
## file 0 = the "a" file. A piece is packed in a single int: the low nibble is
## the kind, bit 4 is the side. 0 means "empty square".

enum Side { WHITE = 0, BLACK = 1 }

enum Kind {
	EMPTY = 0,
	# chess
	PAWN,
	KNIGHT,
	BISHOP,
	ROOK,
	QUEEN,
	KING,
	# checkers
	MAN,
	DAME,
	# batalha naval
	BATTLESHIP,
	CRUISER,
	SUBMARINE,
	DESTROYER,
	# ludo: o dado, que é o ícone do jogo. Os peões do Ludo não passam por aqui —
	# eles são quatro cores, e este encoding tem um bit de lado, não dois.
	DIE,
	# metrópole: a casinha. Ela não é peça de tabuleiro nenhum — é o ícone do
	# jogo, e existe porque o dado já era o do Ludo: com os dois na mesma lista,
	# as duas linhas do menu ficavam iguais de relance, que é exatamente o
	# contrário do que um ícone de jogo serve para fazer.
	#
	# Casinha e não uma das seis peças de jogador: aquelas são seis, e eleger uma
	# como o rosto do jogo é privilegiar quem calhar de jogar com ela. A casa é o
	# que **todo mundo** constrói.
	HOUSE,
	# bomberman: a bomba com o pavio aceso. Como a casinha, ela não é peça de
	# tabuleiro nenhum — este jogo não tem tabuleiro de peças, tem um mapa e
	# quatro bonecos. Ela existe só como o rosto do jogo na lista do menu.
	BOMB,
	# uno: uma carta de baralho vista de frente, em leque. Como a casinha e a
	# bomba, só o rosto do jogo no menu — o Uno não tem peça nenhuma, tem 108
	# cartas, e nenhuma delas representa o jogo melhor que a forma de carta.
	CARD,
}

const SIZE := 8
const SQUARE_COUNT := 64
const NO_SQUARE := -1

## Cinco bits de espécie, e o lado logo acima.
##
## Eram quatro, e quatro deixaram de bastar: com `BOMB` em 15 o nibble estava
## cheio, e a espécie seguinte — a carta do Uno — virou 16, que `kind_of()`
## mascarava de volta para `EMPTY`. O sintoma foi o ícone do jogo simplesmente não
## aparecer, sem erro nenhum: a peça não era zero, então `draw_piece` seguia em
## frente e desenhava a espécie 0, que não tem desenho.
##
## O deslocamento sai do próprio `SIDE_BIT` e não de um `4` escrito à mão em duas
## funções, que é como estava. Aquilo tornava as constantes decorativas — alargar
## a máscara sem mexer nos dois literais teria dado uma peça de lado errado, que é
## um bug bem pior que um ícone faltando.
const KIND_BITS := 5
const SIDE_BIT := 1 << KIND_BITS
const KIND_MASK := SIDE_BIT - 1


static func piece(side: int, kind: int) -> int:
	return kind | (side << KIND_BITS)


static func kind_of(p: int) -> int:
	return p & KIND_MASK


static func side_of(p: int) -> int:
	return (p >> KIND_BITS) & 1


static func is_empty(p: int) -> bool:
	return p == 0


static func opponent(side: int) -> int:
	return 1 - side


static func square(file: int, rank: int) -> int:
	return rank * SIZE + file


static func file_of(sq: int) -> int:
	return sq % SIZE


static func rank_of(sq: int) -> int:
	return sq / SIZE


static func in_bounds(file: int, rank: int) -> bool:
	return file >= 0 and file < SIZE and rank >= 0 and rank < SIZE


static func empty_squares() -> PackedInt32Array:
	var squares := PackedInt32Array()
	squares.resize(SQUARE_COUNT)
	squares.fill(0)
	return squares


## "e4" style coordinate, handy for logs and debugging.
static func square_name(sq: int) -> String:
	if sq < 0 or sq >= SQUARE_COUNT:
		return "--"
	return "%s%d" % [char("a".unicode_at(0) + file_of(sq)), rank_of(sq) + 1]
