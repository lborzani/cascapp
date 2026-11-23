class_name Openings
extends RefCounted

## O guia de aberturas: as linhas principais que todo jogador encontra, cada uma
## com o lado que a escolhe (`side`) e a ideia em uma frase.
##
## Lances em UCI, como o treino guarda (`Training`): o projeto não lê PGN, e
## refazer lances é o que as regras já fazem. Toda linha é conferida no
## `test_runner` — uma linha ilegal quebraria o treino no meio.
##
## Lista e não árvore: o treino segue **uma** linha escolhida, e o nome na
## partida é o da linha mais longa que ela já percorreu.

const LINES := [
	{
		"name": "Italiana", "side": Board.Side.WHITE,
		"moves": "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 c2c3 g8f6 d2d3",
		"idea": "O bispo em c4 mira f7, o ponto fraco das pretas. Desenvolver rápido, rocar e preparar d4.",
	},
	{
		"name": "Espanhola (Ruy López)", "side": Board.Side.WHITE,
		"moves": "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7",
		"idea": "O bispo pressiona o cavalo que defende e5. Pressão lenta e duradoura no centro.",
	},
	{
		"name": "Escocesa", "side": Board.Side.WHITE,
		"moves": "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4 f3d4",
		"idea": "Abre o centro logo no terceiro lance: jogo aberto, peças ativas e menos teoria.",
	},
	{
		"name": "Gambito do Rei", "side": Board.Side.WHITE,
		"moves": "e2e4 e7e5 f2f4 e5f4 g1f3",
		"idea": "Entrega um peão para abrir a coluna f e tomar o centro. Ataque cedo, ao estilo romântico.",
	},
	{
		"name": "Gambito da Dama", "side": Board.Side.WHITE,
		"moves": "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5",
		"idea": "Oferece o peão de c4 para desviar o peão de d5 e dominar o centro.",
	},
	{
		"name": "Sistema Londres", "side": Board.Side.WHITE,
		"moves": "d2d4 d7d5 c1f4 g8f6 e2e3 e7e6 g1f3 c7c5 c2c3",
		"idea": "Mesmo esquema contra quase tudo: bispo em f4, pirâmide de peões e3-d4-c3, rei seguro.",
	},
	{
		"name": "Inglesa", "side": Board.Side.WHITE,
		"moves": "c2c4 e7e5 b1c3 g8f6 g2g3 d7d5 c4d5 f6d5 f1g2",
		"idea": "Controla d5 pelo flanco e o bispo em g2 varre a diagonal longa.",
	},
	{
		"name": "Siciliana (Najdorf)", "side": Board.Side.BLACK,
		"moves": "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6",
		"idea": "Troca o peão c pelo peão d das brancas: posição desequilibrada, jogo pela coluna c.",
	},
	{
		"name": "Francesa", "side": Board.Side.BLACK,
		"moves": "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6 c1g5 f8e7",
		"idea": "Cadeia de peões sólida e contra-ataque com c5 na base do centro branco.",
	},
	{
		"name": "Caro-Kann", "side": Board.Side.BLACK,
		"moves": "e2e4 c7c6 d2d4 d7d5 b1c3 d5e4 c3e4 c8f5",
		"idea": "Como a Francesa, mas o bispo das casas brancas sai antes de e6. Sólida e segura.",
	},
	{
		"name": "Escandinava", "side": Board.Side.BLACK,
		"moves": "e2e4 d7d5 e4d5 d8d5 b1c3 d5a5",
		"idea": "Ataca e4 na hora. A dama sai cedo, mas a posição fica simples e fácil de jogar.",
	},
	{
		"name": "Petrov", "side": Board.Side.BLACK,
		"moves": "e2e4 e7e5 g1f3 g8f6 f3e5 d7d6 e5f3 f6e4",
		"idea": "Contra-ataca e4 em vez de defender e5. Simétrica e muito difícil de furar.",
	},
	{
		"name": "Dois Cavalos", "side": Board.Side.BLACK,
		"moves": "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6",
		"idea": "Contra a Italiana, ataca e4 em vez de espelhar o bispo. Jogo tático cedo.",
	},
	{
		"name": "Eslava", "side": Board.Side.BLACK,
		"moves": "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 d5c4",
		"idea": "Segura d5 com c6 sem prender o bispo de c8 atrás de e6.",
	},
	{
		"name": "Nimzo-Índia", "side": Board.Side.BLACK,
		"moves": "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4",
		"idea": "Crava o cavalo de c3 e luta por e4 com as peças, não com os peões.",
	},
	{
		"name": "Índia do Rei", "side": Board.Side.BLACK,
		"moves": "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 g1f3 e8g8",
		"idea": "Deixa as brancas tomarem o centro e depois o ataca com e5 ou c5, rei já rocado.",
	},
]


static func moves_of(line: Dictionary) -> PackedStringArray:
	return str(line["moves"]).split(" ", false)


## O nome da abertura em que a partida está: a linha que ela acompanhou mais
## longe, se nenhuma outra acompanhou tanto. Empate (1.e4 e5 2.Cf3 Cc6 serve a
## quatro) só se resolve por uma linha percorrida inteira — a mais longa delas.
static func name_for(played: PackedStringArray) -> String:
	var best := 0
	var leaders := []
	var finished := ""
	var finished_size := 0
	for line: Dictionary in LINES:
		var moves := moves_of(line)
		var shared := 0
		while shared < mini(moves.size(), played.size()) and moves[shared] == played[shared]:
			shared += 1
		if shared == moves.size() and shared > finished_size:
			finished = str(line["name"])
			finished_size = shared
		if shared > best:
			best = shared
			leaders = [line["name"]]
		elif shared == best and shared > 0:
			leaders.append(line["name"])
	if best >= 2 and leaders.size() == 1:
		return str(leaders[0])
	return finished


## O próximo lance da linha depois de `played`, ou vazio se a partida saiu dela
## ou ela acabou.
static func next_in(line: PackedStringArray, played: PackedStringArray) -> String:
	if played.size() >= line.size() or line.slice(0, played.size()) != played:
		return ""
	return line[played.size()]


## "1.e4 e5 2.Cf3 Cc6", na notação das regras.
static func san(line: PackedStringArray) -> String:
	var rules := ChessRules.new()
	var state := rules.initial_state()
	var out := PackedStringArray()
	for i in line.size():
		var move := rules.move_from_uci(state, line[i])
		if move == null:
			break
		var text := rules.notation(state, move)
		out.append(("%d.%s" % [i / 2 + 1, text]) if i % 2 == 0 else text)
		rules.apply_move(state, move)
	return " ".join(out)
