extends Node

## Autoload `Game`: the handful of choices made in the menu that the pairing and
## match scenes need to read. Adding a third board game means adding one entry
## to `make_ruleset` and one button in the menu.

enum Mode { HOTSEAT, ONLINE, SOLO }
enum Role { HOST, GUEST }

const CHESS := &"chess"
const CHECKERS := &"checkers"
const BATTLESHIP := &"battleship"
const LUDO := &"ludo"
const MONOPOLY := &"monopoly"
const BOMBERMAN := &"bomberman"
const UNO := &"uno"

## Categorias do catálogo, na ordem em que a tela inicial as oferece.
##
## Existem porque a lista passou de dois jogos para sete, e sete linhas numa tela
## de 768 px é uma lista que se rola — e uma lista que se rola é uma lista onde o
## último jogo não é visto. O filtro não encurta o catálogo, encurta a **procura**.
##
## Quatro e não sete: uma categoria por jogo seria o mesmo que categoria nenhuma.
## O corte é pelo que o jogador reconhece de fora — peça num tabuleiro, dado que
## anda, carta na mão, boneco que corre —, e não pela família de regras. Quem
## abre o app não sabe que batalha naval e xadrez são jogos de informação
## diferente; sabe que nos dois se olha para uma grade.
const CAT_BOARD := &"tabuleiro"
const CAT_DICE := &"dados"
const CAT_CARDS := &"cartas"
const CAT_ACTION := &"acao"

const CATEGORIES := [
	{"id": CAT_BOARD, "label": "Tabuleiro"},
	{"id": CAT_DICE, "label": "Dados"},
	{"id": CAT_CARDS, "label": "Cartas"},
	{"id": CAT_ACTION, "label": "Ação"},
]

## Catálogo: o que a tela de escolha mostra, na ordem em que mostra.
##
## Mora aqui e não na tela porque duas telas leem — a grade da escolha e o
## cabeçalho da tela seguinte — e duas cópias da mesma lista é duas listas que
## podem discordar sobre o que é cada jogo. Acrescentar um jogo é acrescentar uma
## entrada, mais a regra em `make_ruleset`.
##
## Uma peça por jogo, desenhada pelo mesmo renderizador que o tabuleiro usa. Ela
## responde "que jogo é este" antes de o nome ser lido, e é a mesma peça que a
## lista de salas já mostrava — um cavalo é xadrez e uma dama é damas em todos os
## lugares do app.
##
## Era um pedaço de tabuleiro 4x4 por jogo, com quatro peças posicionadas à mão.
## Dizia a mesma coisa e custava uma lista de quatro triplas por entrada, mais 16
## casas desenhadas por cartão.
## O catálogo guarda a **espécie** da peça, não a peça pronta: `Board.piece()` é
## uma função, e uma chamada de função não cabe num `const`. Guardar a espécie
## também é mais honesto — de que lado ela é desenhada é decisão de quem desenha,
## e todo mundo desenha de brancas por contraste com o fundo escuro.
## Cada jogo declara **onde ele roda** (`scene`), **como pode ser jogado**
## (`modes`) e **se tem relógio** (`clock`). Antes essas três coisas estavam
## espalhadas: a cena era uma constante única no `game_menu`, os modos eram os
## quatro botões fixos da tela, e o relógio era um `game_id != CHECKERS` solto.
## Espalhadas, cada tela nova tinha de lembrar de perguntar — e a que esquecesse
## ofereceria um modo que não existe. Aqui não tem como esquecer.
##
## Batalha naval é só em rede, e por enquanto sem bot. Os dois jogadores não podem
## ver o mar um do outro, e num aparelho só isso exigiria uma cortina de "passe o
## celular" entre cada tiro — um modo que atrapalha mais do que serve.
const GAMES := [
	{
		"id": CHESS,
		"title": "Xadrez",
		"category": CAT_BOARD,
		"icon": Board.Kind.KNIGHT,
		"scene": "res://scenes/match.tscn",
		"modes": [Mode.ONLINE, Mode.HOTSEAT, Mode.SOLO],
		"clock": true,
		"visible": true,
	},
	{
		"id": CHECKERS,
		"title": "Damas",
		"category": CAT_BOARD,
		"icon": Board.Kind.DAME,
		"scene": "res://scenes/match.tscn",
		"modes": [Mode.ONLINE, Mode.HOTSEAT, Mode.SOLO],
		"clock": false,
		"visible": true,
	},
	{
		"id": BATTLESHIP,
		"title": "Batalha Naval",
		"category": CAT_BOARD,
		"icon": Board.Kind.BATTLESHIP,
		"scene": "res://scenes/battleship_match.tscn",
		"modes": [Mode.ONLINE],
		"clock": false,
		"visible": true,
	},
	# Quatro jogadores, na sala e no sofá — e as cadeiras que sobrarem viram
	# máquina. `players` diz de que tamanho a sala nasce; o que falta para
	# fechá-la, em qualquer modo, é preenchido por bot.
	#
	# `bot_levels` falso: o adversário do Ludo é `LudoRules.best_move()`, quatro
	# regras de bolso sem profundidade de busca para regular. Oferecer "fácil,
	# médio, difícil" seria oferecer três nomes para o mesmo jogador.
	{
		"id": LUDO,
		"title": "Ludo",
		"category": CAT_DICE,
		"icon": Board.Kind.DIE,
		"scene": "res://scenes/ludo_match.tscn",
		"modes": [Mode.ONLINE, Mode.HOTSEAT, Mode.SOLO],
		"clock": false,
		"players": 4,
		"bot_levels": false,
		# Deitado como Metrópole, e por um motivo diferente do dela.
		#
		# Lá o tabuleiro é um anel cercado de painéis de texto, e em retrato ele
		# ficava com metade da largura. Aqui o tabuleiro é quadrado e já ocupava a
		# largura toda — deitado ele **não cresce**, e isso foi medido: 404 px em
		# retrato contra 402 deitado.
		#
		# O que muda é o resto da tela. Em retrato sobravam mais de cem pixels de
		# nada entre o dado e o botão de sair, com o placar espremido numa faixa;
		# deitado, placar e dado ficam ao lado do tabuleiro, cada um com a coluna
		# inteira — e o arranjo passa a ser o mesmo de Metrópole, que é o que faz
		# os dois jogos de mesa do app se parecerem entre si.
		"landscape": true,
		"visible": true,
	},
	# `landscape` é o único do app: o tabuleiro é um anel quadrado cercado de
	# painéis de texto, e em retrato ele fica com metade da largura da tela.
	#
	# `rounds` também: é o único jogo que pode acabar por tempo de mesa em vez de
	# por posição, e a escolha entre os dois formatos é do menu.
	{
		"id": MONOPOLY,
		"title": "Metrópole",
		"category": CAT_DICE,
		# A casinha, e não o dado: o dado já é o do Ludo, e com os dois iguais as
		# duas linhas do menu ficavam indistinguíveis de relance — o oposto do que
		# um ícone de jogo serve para fazer.
		"icon": Board.Kind.HOUSE,
		"scene": "res://scenes/monopoly_match.tscn",
		"modes": [Mode.ONLINE, Mode.HOTSEAT, Mode.SOLO],
		"clock": false,
		"players": 4,
		# O único jogo do catálogo em que a mesa **é uma escolha**. Ludo são quatro
		# porque são quatro cantos; aqui a regra vale para dois a seis, e a
		# diferença entre uma mesa de dois e uma de seis é a partida inteira — com
		# dois, metade do tabuleiro fica sem dono a partida toda.
		#
		# `players` continua sendo o padrão de quem não escolheu.
		"players_range": [MonopolyRules.MIN_SEATS, MonopolyRules.MAX_SEATS],
		"bot_levels": false,
		"landscape": true,
		"rounds": true,
		"visible": true,
	},
	# O primeiro jogo do catálogo que **não** é por turnos.
	#
	# Ele não tem `Ruleset`: não há lance legal para gerar nem vez de quem jogar.
	# O que existe é uma simulação que anda trinta vezes por segundo com o que cada
	# jogador está segurando (`core/bomber_rules.gd`), e é por isso que
	# `game_title()` passou a ler o nome daqui em vez de instanciar a regra.
	#
	# `bot_levels` falso pelo mesmo motivo do Ludo, com uma razão a mais: o bot
	# daqui não é busca nenhuma — é fugir do raio das bombas e empurrar o outro
	# contra uma. Não há profundidade para regular.
	{
		"id": BOMBERMAN,
		"title": "Bomberman",
		"category": CAT_ACTION,
		"icon": Board.Kind.BOMB,
		"scene": "res://scenes/bomber_match.tscn",
		# Sem "mesmo aparelho", e pelo mesmo motivo da batalha naval: o modo não
		# existe de verdade. Os quatro jogam **ao mesmo tempo**, e um celular tem
		# um direcional — dois polegares num aparelho deitado dariam dois
		# jogadores, com os dois botões de bomba disputando o meio da tela. É um
		# modo a projetar, não a oferecer de véspera.
		"modes": [Mode.ONLINE, Mode.SOLO],
		"clock": false,
		"players": 4,
		"players_range": [2, 4],
		"bot_levels": false,
		# O mapa tem 13 casas de largura por 11 de altura. Em retrato ele ficaria
		# com uma casa do tamanho de um dedão inteiro ou com metade da tela vazia.
		"landscape": true,
		"visible": true,
	},
	# O primeiro jogo do catálogo com **mão oculta**.
	#
	# Sem "mesmo aparelho", e pelo mesmo motivo da batalha naval: seis mãos
	# escondidas num aparelho só exigiriam uma cortina de "passe o celular" a cada
	# turno. O modo existiria na lista sem existir de verdade.
	#
	# `bot_levels` falso como no Ludo e em Metrópole: o adversário é a heurística
	# de `UnoRules.best_move()`, meia dúzia de regras de bolso sem profundidade de
	# busca para regular. Uma busca honesta aqui precisaria de esperança
	# matemática sobre um baralho que ninguém vê.
	#
	# Deitado, como Ludo e Metrópole, e por um motivo que só o desenho da mesa
	# revelou: a partida é um anel de até seis jogadores em volta do monte.
	#
	# Houve uma versão em retrato, com os adversários numa fileira de cartões no
	# topo, e ela quebrava exatamente onde a mesa cresce: seis cartões numa faixa
	# de 432 px dão 72 px cada, que é um nome cortado ao lado de um número. E o
	# tamanho da mão alheia continuava sendo um algarismo a ler, quando sete versos
	# empilhados dizem "muita carta" sem que ninguém leia nada.
	#
	{
		"id": UNO,
		"title": "Uno",
		"category": CAT_CARDS,
		"icon": Board.Kind.CARD,
		"scene": "res://scenes/uno_match.tscn",
		# Sem "mesmo aparelho": mão oculta num aparelho só exigiria uma cortina de
		# "passe o celular" a cada turno — o mesmo motivo da batalha naval. Sala e
		# solo, como Bomberman.
		"modes": [Mode.ONLINE, Mode.SOLO],
		"clock": false,
		"players": 4,
		"players_range": [UnoRules.MIN_SEATS, UnoRules.MAX_SEATS],
		"bot_levels": false,
		"landscape": true,
		"visible": true,
	},
]

## Formatos de Metrópole. O primeiro é jogar até sobrar um, e é o padrão: é o
## jogo como ele é. Os outros existem porque "até sobrar um" pode levar horas, e
## um jogo de tabuleiro num celular precisa de uma versão que cabe num intervalo.
##
## Fechado o número de voltas, vence o maior patrimônio — que é uma partida
## diferente de verdade, não a mesma partida abreviada: quem está com dinheiro
## parado no fim da décima rodada perde para quem gastou tudo em casas.
const ROUND_LIMITS := [
	{"label": "Até a falência", "rounds": 0},
	{"label": "10 rodadas", "rounds": 10},
	{"label": "20 rodadas", "rounds": 20},
	{"label": "30 rodadas", "rounds": 30},
]

## Rodadas até o fim em Metrópole, ou 0 para jogar até sobrar um. Escolhido no
## menu, como o ritmo do xadrez — e guardado aqui pelo mesmo motivo: quem
## hospeda decide, e duas mesas com limites diferentes não seriam uma partida.
##
## Em rede ele viaja no `welcome` como `Net.option`, e quem entra recebe o do
## anfitrião por cima do que tiver escolhido aqui.
var round_limit := 0
## Tamanho de mesa escolhido no menu, ou 0 para o padrão do catálogo. Como o
## limite de rodadas, quem hospeda decide — e quem entra recebe o dele pela
## capacidade da sala, sem passar por aqui.
var table_size := 0

## A regra da casa do Uno: um 7 troca a mão com alguém, um 0 roda as mãos da mesa.
##
## Como o limite de rodadas de Metrópole, quem hospeda decide e quem entra recebe
## a dele — duas mesas que discordassem disto não seriam a mesma partida, e a
## divergência seria a mais grave que este app comporta, porque ela reescreve as
## mãos inteiras.
##
## Nasce do disco (`Prefs`) e não de um padrão escrito aqui: é a única escolha de
## partida do app que sobrevive ao fechamento, e sobrevive porque regra de casa é
## de quem joga, não da sessão.
var uno_sevens := Prefs.sevens_on()

## Bit alto de [method host_option], acima da semente do baralho do Uno.
##
## Empacotado em vez de um campo novo no `welcome` porque `net_link.gd` não é
## canal de configuração — uma segunda coisa a sincronizar é uma segunda coisa que
## pode chegar errada. E os dois **têm** de chegar juntos: um baralho certo sob
## uma regra errada é a mesma partida discordando de si mesma.
const UNO_SEVENS_BIT := 1 << 30


## O jogo acaba por número de rodadas, e o menu deve perguntar qual. Ausente é
## não — que é todo o resto do catálogo.
func supports_rounds(id: StringName = game_id) -> bool:
	return bool(entry_of(id).get("rounds", false))


## Rótulo do formato escolhido, para as telas que anunciam a partida.
func round_limit_label() -> String:
	for entry in ROUND_LIMITS:
		if int(entry["rounds"]) == round_limit:
			return str(entry["label"])
	return "%d rodadas" % round_limit

## O número que quem abre a sala decide e que viaja no `welcome` (`Net.option`).
##
## Um campo só no protocolo, e dois significados — porque são dois jogos que
## precisam dizer alguma coisa ao entrar, e nunca o mesmo jogo dizendo as duas:
##
## - **Metrópole**: o limite de rodadas, escolhido no menu. Duas mesas com
##   limites diferentes não seriam a mesma partida;
## - **Bomberman**: a semente do mapa. Ali é mais grave que uma discordância de
##   formato — o mapa **sai** da semente, e dois mapas diferentes aparecem como um
##   jogador atravessando uma parede que só existe na tela do outro.
## - **Uno**: a semente do baralho nos 30 bits de baixo, e a regra da casa do 0 e
##   do 7 no bit 30. É o único que usa o campo para **duas** respostas, e elas
##   viajam juntas de propósito — separá-las em dois campos seria admitir um
##   estado em que o baralho chegou e a regra não.
##
## A semente é sorteada aqui, e não na cena da partida: quando a cena abre, quem
## entrou já precisa tê-la recebido, e o `welcome` sai desta tela.
func host_option(id: StringName = game_id) -> int:
	if id == BOMBERMAN:
		# Nunca zero: `BomberRules.initial_state` trata o zero como "não me
		# disseram nada" e inventa o próprio — o que daria dois mapas.
		return (randi() & 0x7FFFFFFF) | 1
	if id == UNO:
		# Trinta bits de semente para sobrar o de cima, e nunca zero pelo mesmo
		# motivo do Bomberman: o xorshift tem o zero como ponto fixo, e um baralho
		# semeado em zero é as 108 cartas na ordem de fábrica.
		var packed := (randi() & 0x3FFFFFFF) | 1
		return packed | UNO_SEVENS_BIT if uno_sevens else packed
	if supports_rounds(id):
		return round_limit
	return 0


## As duas metades de `option` no Uno.
##
## `static` porque quem lê é a cena da partida **e** o teste de regras, e o teste
## roda sem autoload. Pelo mesmo motivo elas não consultam nada deste arquivo.
static func uno_seed_of(option: int) -> int:
	return (option & 0x3FFFFFFF) | 1


static func uno_sevens_of(option: int) -> bool:
	return (option & UNO_SEVENS_BIT) != 0


## Quantos jogadores esta partida tem. Ausente é dois, que é o caso de três dos
## cinco jogos — e do app inteiro, que nasceu binário.
##
## Existe porque o menu precisa dizer "quatro jogadores, um aparelho" no Ludo e
## "dois" nos outros, e um `if id == LUDO` na tela seria a regra do jogo morando
## fora do catálogo — que é exatamente o que este dicionário existe para evitar.
##
## Nos jogos com `players_range` a resposta é o que foi escolhido no menu, quando
## houve escolha. O padrão do catálogo continua respondendo por quem entrou
## direto — e por quem **entra numa sala**, onde quem manda é o tamanho que veio
## do anfitrião pelo `welcome`, não o que este aparelho escolheu.
func players_of(id: StringName = game_id) -> int:
	var entry := entry_of(id)
	var span: Array = entry.get("players_range", [])
	if not span.is_empty() and table_size > 0:
		return clampi(table_size, int(span[0]), int(span[1]))
	return int(entry.get("players", 2))


## Tamanhos de mesa que o jogo aceita, ou vazio quando ele tem um só. O menu só
## pergunta onde há o que responder.
func players_range(id: StringName = game_id) -> Array:
	return entry_of(id).get("players_range", [])


## O bot deste jogo tem níveis para escolher. Falso onde ele é uma heurística
## fixa, e aí a tela de ajustes não oferece uma escolha que não existe.
func bot_levels(id: StringName = game_id) -> bool:
	return bool(entry_of(id).get("bot_levels", true))


## O jogo pede o aparelho deitado. Ausente é retrato, que é o app inteiro.
##
## Mora no catálogo pelo mesmo motivo do relógio: quem gira a tela é a cena da
## partida, mas quem **desgira** é `reset_to_menu()`, e as duas precisam
## concordar sobre quais jogos giram. Um `if game_id == X` em cada uma seria
## duas listas — e a que ficasse desatualizada devolveria o menu deitado.
func landscape(id: StringName = game_id) -> bool:
	return bool(entry_of(id).get("landscape", false))


## Peça que representa o jogo, ou 0 se ele não estiver no catálogo. Ponto único:
## a grade de escolha, o cabeçalho da tela seguinte e a lista de salas pedem a
## mesma coisa, e três respostas separadas viravam três desenhos que podiam
## divergir.
func piece_of(id: StringName) -> int:
	var entry := entry_of(id)
	if entry.is_empty():
		return 0
	return Board.piece(Board.Side.WHITE, int(entry["icon"]))


## A categoria de um jogo, ou vazio para quem não declarou uma. Vazio não é erro:
## um jogo sem categoria continua aparecendo em "Todos", e é só o filtro dele que
## não existe — um jogo que some da tela porque esqueceram uma chave é pior que um
## jogo sem filtro.
func category_of(id: StringName) -> StringName:
	return entry_of(id).get("category", &"")


## Os jogos que a tela inicial mostra, já filtrados.
##
## `category` vazio é "todos". A lista respeita `visible` — quem não tem cena não
## entra em filtro nenhum — e devolve os ids na ordem do catálogo, que é a ordem
## em que o app quer ser descoberto.
##
## Mora aqui e não na tela porque é uma pergunta sobre o catálogo, e o catálogo é
## daqui. A tela que filtrasse sozinha teria de conhecer `visible` e `category`,
## que são detalhes desta lista.
func games_in(category: StringName = &"") -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in GAMES:
		if not entry.get("visible", true):
			continue
		if not category.is_empty() and entry.get("category", &"") != category:
			continue
		ids.append(entry["id"])
	return ids


## Os favoritos que ainda existem no catálogo, na ordem do catálogo.
##
## Na ordem do catálogo e não na de quem favoritou: a lista de favoritos aparece
## acima da lista inteira, e duas ordens diferentes para os mesmos jogos fazem o
## olho procurar duas vezes.
##
## O filtro por existência é o que protege de um favorito gravado por um build
## anterior — um jogo removido do catálogo sai dos favoritos sozinho, sem precisar
## de migração no disco.
func favorite_games() -> Array[StringName]:
	var saved := Prefs.favorites()
	var ids: Array[StringName] = []
	for id in games_in():
		if saved.has(String(id)):
			ids.append(id)
	return ids


func entry_of(id: StringName) -> Dictionary:
	for entry in GAMES:
		if entry["id"] == id:
			return entry
	return {}


## Cena de partida do jogo. Cada um tem a sua: batalha naval não seleciona nem
## move peça, não tem relógio nem pré-movimentação, e nada do `match.tscn` — que
## é inteiro sobre essas coisas — sobreviveria à adaptação.
func match_scene(id: StringName = game_id) -> String:
	return str(entry_of(id).get("scene", "res://scenes/match.tscn"))


func supports_mode(mode: int, id: StringName = game_id) -> bool:
	var modes: Array = entry_of(id).get("modes", [])
	return modes.has(mode)


## Um modo que o jogo aceita **e** que este aparelho consegue executar. Sala
## precisa de servidor configurado; os outros dois só precisam da tela.
func mode_available(mode: int, id: StringName = game_id) -> bool:
	if not supports_mode(mode, id):
		return false
	return Net.relay_available() if mode == Mode.ONLINE else true


## Falso quando nenhum modo do jogo funciona neste build — hoje só acontece com
## um jogo exclusivo de rede num build sem servidor. A tela de escolha apaga o
## cartão em vez de escondê-lo: um jogo que some da grade parece um jogo que
## deixou de existir, e o jogador fica procurando o que ele fez de errado.
func playable(id: StringName = game_id) -> bool:
	for mode in entry_of(id).get("modes", []):
		if mode_available(mode, id):
			return true
	return false

## Ritmos oferecidos no menu. O primeiro é a ausência de relógio, e é o padrão:
## quem quer jogo rápido escolhe, quem não quer nem precisa saber que existe.
##
## O incremento em `3 + 2` é o que torna partida curta jogável num celular —
## sem ele os últimos lances viram corrida de toque, não de xadrez.
const TIME_CONTROLS := [
	{"label": "Sem relógio", "initial": 0.0, "increment": 0.0},
	{"label": "1:30", "initial": 90.0, "increment": 0.0},
	{"label": "3 + 2", "initial": 180.0, "increment": 2.0},
	{"label": "5 min", "initial": 300.0, "increment": 0.0},
	{"label": "10 min", "initial": 600.0, "increment": 0.0},
]

var mode := Mode.HOTSEAT
var role := Role.HOST
var game_id := CHESS
var local_side := Board.Side.WHITE
## Nosso lugar na mesa, nos jogos de mais de dois. No Ludo é a cor que se joga —
## assento 0 é o vermelho. Nos jogos de dois `local_side` continua respondendo, e
## isto fica em zero sem significar nada.
var local_seat := 0
## Índice em `TIME_CONTROLS`. Em rede quem hospeda decide, e o convidado recebe
## o índice no handshake — dois relógios diferentes não seriam uma partida.
var time_control := 0
## A sala aparece na lista pública de partidas esperando alguém.
##
## Padrão **falso**, e isso é a escolha de privacidade do app: o código de 6
## caracteres é um segredo, e quem abre uma partida para um amigo não deve
## receber um estranho por não ter percebido uma opção.
var listed_room := false
## Payload de um QR lido antes de o processo morrer, passado da tela inicial
## para a de entrar. Só isso: quem lê um QR com o app aberto recebe o sinal do
## `Pairing` na hora e não precisa de estado guardado em lugar nenhum.
var join_info := {}
## Índice em `Bot.LEVELS`. Começa no médio: o fácil erra de propósito e o difícil
## pensa alguns segundos por lance, e nenhum dos dois é a primeira impressão que
## se quer dar de um adversário.
var bot_level := 1
## Cor do bot. O jogador escolhe a dele no painel de ajustes, e a revanche troca
## as duas — pelo mesmo motivo da revanche em rede: começar sempre de brancas é
## meia vantagem repetida.
var bot_side := Board.Side.BLACK


## Só o xadrez usa relógio. A regra mora no catálogo, e não na tela que oferece a
## escolha: assim nenhum caminho — sala pela lista, QR, NFC, revanche — consegue
## ligar um cronômetro num jogo que não o tem. Uma tela a mais que esquecesse de
## perguntar seria um bug; uma coluna no catálogo não tem como ser esquecida.
func supports_clock(id: StringName = game_id) -> bool:
	return bool(entry_of(id).get("clock", false))


func has_clock() -> bool:
	return supports_clock() and clock_initial() > 0.0


func clock_initial() -> float:
	return float(_time_control()["initial"])


func clock_increment() -> float:
	return float(_time_control()["increment"])


func clock_label() -> String:
	return clock_label_for(time_control)


## Rótulo de um ritmo qualquer, não só o escolhido. A lista de salas recebe o
## índice do servidor e precisa traduzir o ritmo de partidas alheias.
func clock_label_for(index: int) -> String:
	return str(TIME_CONTROLS[clampi(index, 0, TIME_CONTROLS.size() - 1)]["label"])


func _time_control() -> Dictionary:
	return TIME_CONTROLS[clampi(time_control, 0, TIME_CONTROLS.size() - 1)]




func make_ruleset(id: StringName = game_id) -> Ruleset:
	match id:
		CHECKERS:
			return CheckersRules.new()
		BATTLESHIP:
			return BattleshipRules.new()
		LUDO:
			return LudoRules.new()
		UNO:
			# A semente **não** entra aqui: ela vem do `welcome` em rede e de um
			# sorteio local no solo, e nenhum dos dois é resposta que este autoload
			# tenha. Quem a preenche é `uno_match.gd`, como `bomber_match.gd` faz
			# com a do mapa. O que sai daqui é a mesa e a regra da casa.
			var uno := UnoRules.new()
			uno.seats = players_of(UNO)
			uno.sevens = uno_sevens
			return uno
		MONOPOLY:
			var monopoly := MonopolyRules.new()
			monopoly.seats = players_of(MONOPOLY)
			monopoly.round_limit = round_limit
			return monopoly
		_:
			return ChessRules.new()


## O nome do jogo sai do **catálogo**, e não de `make_ruleset(id).display_name()`.
##
## Aquele caminho instanciava a regra inteira para ler uma string, e parou de
## funcionar no primeiro jogo que não tem `Ruleset`: Bomberman é tempo real, não
## tem lance legal para gerar nem vez de quem jogar, e não implementa a interface.
## O catálogo já sabia o nome — as duas telas de menu leem `title` de lá desde
## sempre —, e era esta a única resposta que vinha por outro caminho.
func game_title(id: StringName = game_id) -> String:
	return str(entry_of(id).get("title", ""))


func start_hotseat(id: StringName) -> void:
	mode = Mode.HOTSEAT
	game_id = id
	local_side = Board.Side.WHITE


func start_solo(id: StringName) -> void:
	mode = Mode.SOLO
	game_id = id
	local_side = Board.opponent(bot_side)


## Verdadeiro quando o lado da vez é o do bot. Uma pergunta só, num lugar só: a
## tela, o relógio e o tabuleiro consultam isto em vez de cada um refazer a conta
## com `mode` e `bot_side` — que é como um deles acaba discordando dos outros.
func bot_turn(side_to_move: int) -> bool:
	return mode == Mode.SOLO and side_to_move == bot_side


## Quando esta partida começou, em tempo Unix. Zero fora de partida.
##
## Aqui e não em cada cena porque a resposta atravessa a troca de tela: numa
## reconexão o app volta pela tela de entrar e monta a cena da partida de novo, e
## a pergunta "há quanto tempo isto está acontecendo" não pode recomeçar do zero
## só porque um nó foi recriado.
var match_started_at := 0


## Marca o começo da partida, ou recupera o de uma que já estava em curso.
##
## Chamado pelas cinco cenas de partida ao abrir. Numa sala em rede, a resposta
## vem do disco quando o código é o mesmo de antes: é o caminho de quem caiu e
## voltou. Sem sala — mesmo aparelho, contra o bot — o começo é agora, porque uma
## partida local que o processo perdeu não tem como ser retomada.
func begin_match() -> void:
	var now := int(Time.get_unix_time_from_system())
	var code := Net.room_code()
	match_started_at = Prefs.match_start(code, now) if not code.is_empty() else now


## Zera o relógio. É a revanche: a sala é a mesma e a partida é outra, e sem isto
## o `begin_match()` devolveria o começo da anterior.
func restart_match() -> void:
	var now := int(Time.get_unix_time_from_system())
	var code := Net.room_code()
	match_started_at = Prefs.restart_match(code, now) if not code.is_empty() else now


func reset_to_menu() -> void:
	Net.leave()
	Pairing.nfc.stop()
	Pairing.qr_scanner.stop()
	# Incondicional de propósito: desgirar só quando `landscape()` é verdadeiro
	# dependeria de `game_id` ainda ser o do jogo que girou, e ele já pode ter
	# sido trocado por quem chamou. Voltar ao retrato quando já se está nele não
	# custa nada — `Orientation` compara antes de escrever.
	Orientation.reset(get_tree())
	mode = Mode.HOTSEAT
	join_info = {}
	# Fora de partida não há relógio a contar. O que ficou gravado no disco não é
	# apagado aqui de propósito: é justamente o que faz a volta pela mesma sala
	# reencontrar o começo certo, e sair para o menu é o caminho normal de quem vai
	# tentar entrar de novo.
	match_started_at = 0
