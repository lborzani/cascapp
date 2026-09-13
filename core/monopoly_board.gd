class_name MonopolyBoard
extends RefCounted

## As 40 casas e os dois baralhos de **Metrópole**. Só dado: nenhuma regra mora
## aqui, e nada daqui entra em `MatchState.meta`.
##
## A separação importa por causa do `clone()` raso ([match_state.gd]): `meta` só
## pode guardar inteiro e `PackedInt32Array`, então o que é dicionário — nome,
## preço, tabela de aluguel — tem de ser **constante**, lida por índice de casa.
## O estado guarda quem é o dono da casa 19; o que a casa 19 *é* está aqui e
## nunca muda.
##
## ## Por que não "Monopoly"
##
## O nome, os nomes das ruas e o traçado do tabuleiro original são marca e
## trade dress de terceiros — a mecânica não é. Então a mecânica é a clássica e
## o conteúdo é próprio: oito cidades brasileiras, uma por grupo de cor, do
## grupo mais barato ao mais caro. Um jogador reconhece o jogo pelo ritmo, não
## pelos nomes, e os nomes daqui são os únicos que o app pode publicar.
##
## Ferrovia virou **aeroporto**: no Brasil, quatro ferrovias de passageiro não
## dizem nada a ninguém, e quatro aeroportos dizem exatamente a mesma coisa que
## as quatro ferrovias diziam — pontos de passagem espalhados pelo tabuleiro,
## que valem mais quanto mais você tem.

## O que uma casa é. Só isso decide o que acontece ao parar nela.
enum Tile {
	GO,
	PROPERTY,
	AIRPORT,
	UTILITY,
	TAX,
	CHANCE,
	CHEST,
	JAIL,
	PARKING,
	GOTO_JAIL,
}

## Grupos que se completam. Os oito de cor valem por permitirem construir; os
## dois últimos valem por escala — aluguel de aeroporto e de companhia depende
## de quantos do grupo o dono tem, e não de casas.
enum Group {
	NONE = -1,
	BROWN = 0,
	LIGHT_BLUE,
	PINK,
	ORANGE,
	RED,
	YELLOW,
	GREEN,
	BLUE,
	AIRPORTS,
	UTILITIES,
}

const SIZE := 40
const GO_TILE := 0
const JAIL_TILE := 10
const GOTO_JAIL_TILE := 30

## Salário por completar a volta. Passar pela Partida paga; parar nela paga a
## mesma coisa — a regra de "dobro na Partida" é caseira e infla a partida.
const GO_SALARY := 200

## Fiança. Também é o que se paga na terceira tentativa fracassada de tirar
## dupla: sair da cadeia é caro, mas nunca é impossível.
const BAIL := 50

## Dinheiro inicial de cada jogador.
const START_CASH := 1500

## Quantas casas cabem numa propriedade antes do hotel. `houses[tile] == 5` é o
## hotel — um número só para as duas coisas, porque hotel é o sexto degrau da
## mesma escada de aluguel e guardá-lo à parte seria guardar duas verdades sobre
## a mesma casa.
const HOTEL := 5

## Casas e hotéis que o banco tem. Escassez é regra do jogo original e é o que
## impede dois jogadores ricos de hotelarem tudo ao mesmo tempo — mas ela só
## morde em partida longa de seis, e custa dois contadores no estado. Fica para
## quando houver evidência de que faz falta.
const HOUSE_SUPPLY := -1

## Aluguel de aeroporto por quantidade que o dono tem: 1, 2, 3 ou 4.
const AIRPORT_RENT := [25, 50, 100, 200]

## Companhia cobra a **rolagem** vezes isto — 4 com uma, 10 com as duas. É o
## único aluguel do jogo que depende do dado, e por isso `meta["roll"]` existe.
const UTILITY_MULTIPLIER := [4, 10]

## Cor de cada grupo, para quem desenha. Mora junto do tabuleiro porque a cor
## **é** a identidade do grupo: dois lugares definindo "o que é o laranja" é um
## lugar a mais do que precisa existir.
const GROUP_COLORS := {
	Group.BROWN: Color("8d6748"),
	Group.LIGHT_BLUE: Color("7fc6e8"),
	Group.PINK: Color("d96fa8"),
	Group.ORANGE: Color("e8913f"),
	Group.RED: Color("d94f4f"),
	Group.YELLOW: Color("e8cf4f"),
	Group.GREEN: Color("4fa36b"),
	Group.BLUE: Color("4f6fd9"),
	Group.AIRPORTS: Color("9aa4b2"),
	Group.UTILITIES: Color("9aa4b2"),
}

## As 40 casas, na ordem em que se anda.
##
## `rent` tem seis degraus — sem casa, 1, 2, 3, 4, hotel — e o índice é o número
## de construções. Aeroporto e companhia não constroem e têm a tabela própria
## acima.
##
## `short` existe porque o tabuleiro é desenhado num celular em pé: "Jardim
## Europa" não cabe numa casa de 40 pixels, e cortar no meio na hora de desenhar
## produz "Jardim Eu…" em vez de um nome escolhido para caber.
const TILES := [
	{"name": "Partida", "short": "Partida", "kind": Tile.GO},
	{
		"name": "Guamá", "short": "Guamá", "city": "Belém",
		"kind": Tile.PROPERTY, "group": Group.BROWN, "price": 60, "house": 50,
		"rent": [2, 10, 30, 90, 160, 250],
	},
	{"name": "Cofre", "short": "Cofre", "kind": Tile.CHEST},
	{
		"name": "Icoaraci", "short": "Icoaraci", "city": "Belém",
		"kind": Tile.PROPERTY, "group": Group.BROWN, "price": 60, "house": 50,
		"rent": [4, 20, 60, 180, 320, 450],
	},
	{"name": "Imposto de Renda", "short": "Imposto", "kind": Tile.TAX, "amount": 200},
	{
		"name": "Aeroporto de Congonhas", "short": "Congonh.",
		"kind": Tile.AIRPORT, "group": Group.AIRPORTS, "price": 200,
	},
	{
		"name": "Cidade Nova", "short": "C. Nova", "city": "Manaus",
		"kind": Tile.PROPERTY, "group": Group.LIGHT_BLUE, "price": 100, "house": 50,
		"rent": [6, 30, 90, 270, 400, 550],
	},
	{"name": "Sorte", "short": "Sorte", "kind": Tile.CHANCE},
	{
		"name": "Adrianópolis", "short": "Adrian.", "city": "Manaus",
		"kind": Tile.PROPERTY, "group": Group.LIGHT_BLUE, "price": 100, "house": 50,
		"rent": [6, 30, 90, 270, 400, 550],
	},
	{
		"name": "Ponta Negra", "short": "P. Negra", "city": "Manaus",
		"kind": Tile.PROPERTY, "group": Group.LIGHT_BLUE, "price": 120, "house": 50,
		"rent": [8, 40, 100, 300, 450, 600],
	},
	{"name": "Cadeia", "short": "Cadeia", "kind": Tile.JAIL},
	{
		"name": "Benfica", "short": "Benfica", "city": "Fortaleza",
		"kind": Tile.PROPERTY, "group": Group.PINK, "price": 140, "house": 100,
		"rent": [10, 50, 150, 450, 625, 750],
	},
	{
		"name": "Companhia de Energia", "short": "Energia",
		"kind": Tile.UTILITY, "group": Group.UTILITIES, "price": 150,
	},
	{
		"name": "Aldeota", "short": "Aldeota", "city": "Fortaleza",
		"kind": Tile.PROPERTY, "group": Group.PINK, "price": 140, "house": 100,
		"rent": [10, 50, 150, 450, 625, 750],
	},
	{
		"name": "Meireles", "short": "Meireles", "city": "Fortaleza",
		"kind": Tile.PROPERTY, "group": Group.PINK, "price": 160, "house": 100,
		"rent": [12, 60, 180, 500, 700, 900],
	},
	{
		"name": "Aeroporto de Confins", "short": "Confins",
		"kind": Tile.AIRPORT, "group": Group.AIRPORTS, "price": 200,
	},
	{
		"name": "Espinheiro", "short": "Espinh.", "city": "Recife",
		"kind": Tile.PROPERTY, "group": Group.ORANGE, "price": 180, "house": 100,
		"rent": [14, 70, 200, 550, 750, 950],
	},
	{"name": "Cofre", "short": "Cofre", "kind": Tile.CHEST},
	{
		"name": "Casa Forte", "short": "C. Forte", "city": "Recife",
		"kind": Tile.PROPERTY, "group": Group.ORANGE, "price": 180, "house": 100,
		"rent": [14, 70, 200, 550, 750, 950],
	},
	{
		"name": "Boa Viagem", "short": "Boa Viag.", "city": "Recife",
		"kind": Tile.PROPERTY, "group": Group.ORANGE, "price": 200, "house": 100,
		"rent": [16, 80, 220, 600, 800, 1000],
	},
	{"name": "Descanso", "short": "Descanso", "kind": Tile.PARKING},
	{
		"name": "Rio Vermelho", "short": "R. Verm.", "city": "Salvador",
		"kind": Tile.PROPERTY, "group": Group.RED, "price": 220, "house": 150,
		"rent": [18, 90, 250, 700, 875, 1050],
	},
	{"name": "Sorte", "short": "Sorte", "kind": Tile.CHANCE},
	{
		"name": "Graça", "short": "Graça", "city": "Salvador",
		"kind": Tile.PROPERTY, "group": Group.RED, "price": 220, "house": 150,
		"rent": [18, 90, 250, 700, 875, 1050],
	},
	{
		"name": "Barra", "short": "Barra", "city": "Salvador",
		"kind": Tile.PROPERTY, "group": Group.RED, "price": 240, "house": 150,
		"rent": [20, 100, 300, 750, 925, 1100],
	},
	{
		"name": "Aeroporto Salgado Filho", "short": "S. Filho",
		"kind": Tile.AIRPORT, "group": Group.AIRPORTS, "price": 200,
	},
	{
		"name": "Água Verde", "short": "Á. Verde", "city": "Curitiba",
		"kind": Tile.PROPERTY, "group": Group.YELLOW, "price": 260, "house": 150,
		"rent": [22, 110, 330, 800, 975, 1150],
	},
	{
		"name": "Batel", "short": "Batel", "city": "Curitiba",
		"kind": Tile.PROPERTY, "group": Group.YELLOW, "price": 260, "house": 150,
		"rent": [22, 110, 330, 800, 975, 1150],
	},
	{
		"name": "Companhia de Águas", "short": "Águas",
		"kind": Tile.UTILITY, "group": Group.UTILITIES, "price": 150,
	},
	{
		"name": "Ecoville", "short": "Ecoville", "city": "Curitiba",
		"kind": Tile.PROPERTY, "group": Group.YELLOW, "price": 280, "house": 150,
		"rent": [24, 120, 360, 850, 1025, 1200],
	},
	{"name": "Vá para a Cadeia", "short": "Cadeia!", "kind": Tile.GOTO_JAIL},
	{
		"name": "Savassi", "short": "Savassi", "city": "Belo Horizonte",
		"kind": Tile.PROPERTY, "group": Group.GREEN, "price": 300, "house": 200,
		"rent": [26, 130, 390, 900, 1100, 1275],
	},
	{
		"name": "Lourdes", "short": "Lourdes", "city": "Belo Horizonte",
		"kind": Tile.PROPERTY, "group": Group.GREEN, "price": 300, "house": 200,
		"rent": [26, 130, 390, 900, 1100, 1275],
	},
	{"name": "Cofre", "short": "Cofre", "kind": Tile.CHEST},
	{
		"name": "Belvedere", "short": "Belved.", "city": "Belo Horizonte",
		"kind": Tile.PROPERTY, "group": Group.GREEN, "price": 320, "house": 200,
		"rent": [28, 150, 450, 1000, 1200, 1400],
	},
	{
		"name": "Aeroporto do Galeão", "short": "Galeão",
		"kind": Tile.AIRPORT, "group": Group.AIRPORTS, "price": 200,
	},
	{"name": "Sorte", "short": "Sorte", "kind": Tile.CHANCE},
	{
		"name": "Leblon", "short": "Leblon", "city": "Rio de Janeiro",
		"kind": Tile.PROPERTY, "group": Group.BLUE, "price": 350, "house": 200,
		"rent": [35, 175, 500, 1100, 1300, 1500],
	},
	{"name": "Taxa de Luxo", "short": "Luxo", "kind": Tile.TAX, "amount": 100},
	{
		"name": "Jardim Europa", "short": "Jd. Europa", "city": "São Paulo",
		"kind": Tile.PROPERTY, "group": Group.BLUE, "price": 400, "house": 200,
		"rent": [50, 200, 600, 1400, 1700, 2000],
	},
]


# --- baralhos -----------------------------------------------------------------


## O que uma carta faz. Seis efeitos cobrem as 32 cartas — as do jogo original
## que precisariam de um sétimo ("vá ao aeroporto mais próximo") foram trocadas
## por um destino fixo, que é a mesma carta sem o caso especial.
enum Effect {
	MONEY,
	## Vá para uma casa. Passar pela Partida no caminho paga o salário.
	MOVE_TO,
	## Ande N casas para trás. Nunca cruza a Partida, então nunca paga.
	MOVE_BY,
	GOTO_JAIL,
	## Guarda a carta de saída livre. Ela sai do baralho enquanto está na mão.
	JAIL_CARD,
	## Paga por construção: `house` por casa e `hotel` por hotel.
	PER_BUILDING,
	## Acerta contas com cada jogador em jogo. Positivo recebe, negativo paga.
	EACH_PLAYER,
}

const CHANCE := 0
const CHEST := 1

## Cada carta fala **três** vezes, e cada voz tem um lugar.
##
## - `title` — o nome da carta, duas ou três palavras. É o que fica na memória de
##   quem já jogou ("de novo a reforma geral"), e é o que a carta mostra grande;
## - `text` — o que a carta **faz**, na linguagem das regras. É a única das três
##   que o aviso da tela usa, e a única que precisa ser exata;
## - `flavor` — por que aconteceu, em uma frase. Não vale nada para a partida, e é
##   ela que faz uma carta ser lembrada como cena em vez de como valor.
##
## Estão juntas na mesma entrada de propósito: separadas em três tabelas paralelas
## indexadas pela mesma posição, a carta acrescentada no fim de uma só é a que
## mostra o texto errado.
const CHANCE_CARDS := [
	{
		"title": "Volta triunfal", "text": "Avance até a Partida.",
		"flavor": "Você atravessa a cidade inteira e ainda passa no caixa. Ninguém pergunta como.",
		"effect": Effect.MOVE_TO, "value": 0,
	},
	{
		"title": "Convite para o Leblon", "text": "Avance até o Leblon.",
		"flavor": "Alguém te chamou para um café à beira-mar. Você vai — e paga o que a casa cobrar.",
		"effect": Effect.MOVE_TO, "value": 37,
	},
	{
		"title": "Fim de semana em Boa Viagem", "text": "Avance até Boa Viagem.",
		"flavor": "Mala pronta, sem discussão. Se a casa tiver dono, o aluguel entra na conta da viagem.",
		"effect": Effect.MOVE_TO, "value": 19,
	},
	{
		"title": "Voo remarcado", "text": "Avance até o Aeroporto de Congonhas.",
		"flavor": "Corra para o portão. Se o aeroporto tiver dono, a passagem sai bem mais cara.",
		"effect": Effect.MOVE_TO, "value": 5,
	},
	{
		"title": "Chamado da elétrica", "text": "Avance até a Companhia de Energia.",
		"flavor": "Faltou luz no quarteirão e você foi junto. Aqui a conta é o dado que decide.",
		"effect": Effect.MOVE_TO, "value": 12,
	},
	{
		"title": "Dividendos", "text": "O banco paga dividendos de 50.",
		"flavor": "Aquelas ações esquecidas na gaveta resolveram render.",
		"effect": Effect.MONEY, "value": 50,
	},
	{
		"title": "Saída livre", "text": "Saída livre da cadeia. Guarde esta carta.",
		"flavor": "Um contato bem colocado. Guarde: um dia essa porta vai precisar abrir.",
		"effect": Effect.JAIL_CARD, "value": 0,
	},
	{
		"title": "Passo em falso", "text": "Volte três casas.",
		"flavor": "Você esqueceu alguma coisa três casas atrás. E vai ter que assumir o que encontrar lá.",
		"effect": Effect.MOVE_BY, "value": -3,
	},
	{
		"title": "Direto para a cadeia", "text": "Vá para a cadeia. Não passe pela Partida.",
		"flavor": "Sem escala, sem salário, sem discussão. A Partida que espere.",
		"effect": Effect.GOTO_JAIL, "value": 0,
	},
	{
		"title": "Reforma geral", "text": "Reforma geral: pague 25 por casa e 100 por hotel.",
		"flavor": "O fiscal apareceu e nada está no padrão. Quanto mais você construiu, mais dói.",
		"effect": Effect.PER_BUILDING, "house": 25, "hotel": 100, "value": 0,
	},
	{
		"title": "Excesso de velocidade", "text": "Multa por excesso de velocidade: pague 15.",
		"flavor": "O radar não perdoa nem em jogo de tabuleiro.",
		"effect": Effect.MONEY, "value": -15,
	},
	{
		"title": "Aplicação rendeu", "text": "Sua aplicação rendeu. Receba 150.",
		"flavor": "Você nem lembrava desse investimento. Ele lembrou de você.",
		"effect": Effect.MONEY, "value": 150,
	},
	{
		"title": "Presidente do conselho",
		"text": "Você foi eleito presidente do conselho. Pague 50 a cada jogador.",
		"flavor": "Parabéns pelo cargo. O brinde da posse é por sua conta.",
		"effect": Effect.EACH_PLAYER, "value": -50,
	},
	{
		"title": "Noite na Savassi", "text": "Avance até a Savassi.",
		"flavor": "O rumo mudou no meio do caminho. O que acontecer lá é problema seu.",
		"effect": Effect.MOVE_TO, "value": 31,
	},
	{
		"title": "Manutenção do escritório", "text": "Pague a manutenção do escritório: 100.",
		"flavor": "Ar-condicionado, café e aquele cano que ninguém consertou.",
		"effect": Effect.MONEY, "value": -100,
	},
	{
		"title": "Cliente antigo", "text": "Receba 100 de um cliente antigo.",
		"flavor": "Um trabalho velho voltou — e voltou pago.",
		"effect": Effect.MONEY, "value": 100,
	},
]

const CHEST_CARDS := [
	{
		"title": "De volta ao começo", "text": "Avance até a Partida.",
		"flavor": "O caminho mais curto era dar a volta toda. Pelo menos o salário vem junto.",
		"effect": Effect.MOVE_TO, "value": 0,
	},
	{
		"title": "Erro do banco", "text": "Erro do banco a seu favor. Receba 200.",
		"flavor": "A seu favor, dessa vez. Pegue o dinheiro e não faça perguntas.",
		"effect": Effect.MONEY, "value": 200,
	},
	{
		"title": "Consulta médica", "text": "Consulta médica: pague 50.",
		"flavor": "Nada grave. Só caro.",
		"effect": Effect.MONEY, "value": -50,
	},
	{
		"title": "Venda de ações", "text": "Venda de ações: receba 50.",
		"flavor": "Você vendeu na hora certa. Por acidente, mas vendeu.",
		"effect": Effect.MONEY, "value": 50,
	},
	{
		"title": "Saída livre", "text": "Saída livre da cadeia. Guarde esta carta.",
		"flavor": "Um papel pequeno que vale muito. Guarde para o dia em que a cela chamar.",
		"effect": Effect.JAIL_CARD, "value": 0,
	},
	{
		"title": "Direto para a cadeia", "text": "Vá para a cadeia. Não passe pela Partida.",
		"flavor": "A caminhada acabou aqui. E nada de passar no caixa no caminho.",
		"effect": Effect.GOTO_JAIL, "value": 0,
	},
	{
		"title": "É seu aniversário", "text": "É seu aniversário. Receba 10 de cada jogador.",
		"flavor": "Todo mundo à mesa canta — e paga. Barato, mas é de todos.",
		"effect": Effect.EACH_PLAYER, "value": 10,
	},
	{
		"title": "Restituição do imposto", "text": "Restituição do imposto: receba 20.",
		"flavor": "O leão devolveu uma migalha. Aceite mesmo assim.",
		"effect": Effect.MONEY, "value": 20,
	},
	{
		"title": "Prêmio do seguro", "text": "Prêmio do seguro: receba 100.",
		"flavor": "A apólice finalmente serviu para alguma coisa.",
		"effect": Effect.MONEY, "value": 100,
	},
	{
		"title": "Conta do hospital", "text": "Conta do hospital: pague 100.",
		"flavor": "O atendimento foi rápido. A fatura, não.",
		"effect": Effect.MONEY, "value": -100,
	},
	{
		"title": "Mensalidade da escola", "text": "Mensalidade da escola: pague 50.",
		"flavor": "Chegou o boleto de todo mês. Ele sempre chega.",
		"effect": Effect.MONEY, "value": -50,
	},
	{
		"title": "Serviço de consultoria", "text": "Serviço de consultoria: receba 25.",
		"flavor": "Você deu um palpite de trinta segundos e cobraram por ele.",
		"effect": Effect.MONEY, "value": 25,
	},
	{
		"title": "Obra na rua", "text": "Obra na rua: pague 40 por casa e 115 por hotel.",
		"flavor": "Abriram o asfalto bem na sua porta. Cada construção entra no rateio.",
		"effect": Effect.PER_BUILDING, "house": 40, "hotel": 115, "value": 0,
	},
	{
		"title": "Segundo lugar no concurso", "text": "Segundo lugar no concurso: receba 10.",
		"flavor": "Quase. Fique com os 10 e com a lembrança.",
		"effect": Effect.MONEY, "value": 10,
	},
	{
		"title": "Herança", "text": "Herança: receba 100.",
		"flavor": "Um parente distante lembrou de você no fim. Que gentileza.",
		"effect": Effect.MONEY, "value": 100,
	},
	{
		"title": "Honorários atrasados", "text": "Honorários atrasados: receba 25.",
		"flavor": "Aquele trabalho de meses atrás enfim caiu na conta.",
		"effect": Effect.MONEY, "value": 25,
	},
]


static func deck(which: int) -> Array:
	return CHEST_CARDS if which == CHEST else CHANCE_CARDS


static func card(which: int, index: int) -> Dictionary:
	var cards := deck(which)
	return cards[index % cards.size()]


# --- leitura do tabuleiro -----------------------------------------------------


static func tile(index: int) -> Dictionary:
	return TILES[index % SIZE]


static func kind_of(index: int) -> int:
	return int(tile(index)["kind"])


static func group_of(index: int) -> int:
	return int(tile(index).get("group", Group.NONE))


static func price_of(index: int) -> int:
	return int(tile(index).get("price", 0))


static func house_cost(index: int) -> int:
	return int(tile(index).get("house", 0))


## Vale dinheiro e tem dono: propriedade, aeroporto ou companhia. É a pergunta
## que separa as 28 casas que se compram das 12 que só acontecem.
static func is_deed(index: int) -> bool:
	match kind_of(index):
		Tile.PROPERTY, Tile.AIRPORT, Tile.UTILITY:
			return true
		_:
			return false


## Só propriedade de cor constrói. Aeroporto e companhia sobem de aluguel por
## quantidade, e é por isso que eles não têm tabela de casas.
static func can_build_on(index: int) -> bool:
	return kind_of(index) == Tile.PROPERTY


## Metade do preço, que é quanto o banco empresta pela hipoteca. Levantar a
## hipoteca custa isso mais 10% de juros — a diferença é o preço de ter
## precisado do dinheiro.
static func mortgage_value(index: int) -> int:
	return price_of(index) / 2


static func unmortgage_cost(index: int) -> int:
	return int(round(mortgage_value(index) * 1.1))


## As outras casas do mesmo grupo, esta inclusive. Usado para saber se alguém
## fechou a cor — o que libera construir e dobra o aluguel do terreno vazio.
static func group_tiles(group: int) -> PackedInt32Array:
	var tiles := PackedInt32Array()
	if group == Group.NONE:
		return tiles
	for index in SIZE:
		if group_of(index) == group:
			tiles.append(index)
	return tiles


## As casas entre uma e outra, sem contar a de partida e incluindo a de chegada.
##
## Mora aqui e não na tela porque é topologia do anel, não desenho: quem anda
## para a frente cruza a Partida, e é esse cruzamento que paga o salário. Uma
## segunda ideia de "qual é o caminho" na cena divergiria da regra no dia em que
## alguém precisasse dela — e a tela contaria uma volta que as regras negam.
##
## Para a frente por padrão. É assim que se anda em Metrópole, inclusive numa
## carta de "avance até", que atravessa o tabuleiro em vez de pular.
static func steps_between(from: int, to: int, backward := false) -> PackedInt32Array:
	var path := PackedInt32Array()
	var at := posmod(from, SIZE)
	var target := posmod(to, SIZE)
	var step := -1 if backward else 1
	# O teto é a guarda: sem ele, um destino inalcançável — que só existe se
	# alguém quebrar a aritmética — roda para sempre.
	while at != target and path.size() < SIZE:
		at = posmod(at + step, SIZE)
		path.append(at)
	return path


## A carta manda andar para trás. Só uma faz isso, e ela nunca dá a volta — por
## isso o caminho de volta não paga salário nenhum.
static func card_walks_backward(which: int, index: int) -> bool:
	var chosen := card(which, index)
	return int(chosen["effect"]) == Effect.MOVE_BY and int(chosen["value"]) < 0


static func display_name(index: int) -> String:
	return str(tile(index)["name"])


static func short_name(index: int) -> String:
	return str(tile(index).get("short", tile(index)["name"]))


## Cidade a que a propriedade pertence, ou vazio nas casas que não são de cor.
## A tela mostra ao lado do nome: "Batel" sozinho não diz nada a quem não é de
## Curitiba, e é a cidade que agrupa as três na cabeça do jogador.
static func city_of(index: int) -> String:
	return str(tile(index).get("city", ""))
