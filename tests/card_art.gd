extends Node

## Gera a arte de fundo das linhas de jogo do menu, em `assets/cards/`.
##
##   godot --path . res://tests/card_art.tscn
##
## Não roda com `--headless`: sem servidor de vídeo o viewport volta preto, e o
## PNG sai vazio sem nenhum erro.
##
## O fundo de cada linha é o **próprio jogo** — o mesmo `BoardView`, o mesmo
## `WatersView` e o mesmo `MonopolyFace` que desenham a partida, com a posição
## inicial em cima. Nada aqui é desenho novo: se a peça, a cor da casa ou a
## moldura mudarem, esta ferramenta roda de novo e a arte acompanha. Uma imagem
## pintada à mão divergiria do jogo na primeira mudança de paleta, e ninguém
## repararia.
##
## Depois de rodar, o Godot precisa **importar** os PNGs novos — eles nascem em
## `assets/` sem o `.import` que o motor gera, e sem ele o cartão desenha a linha
## lisa sem nenhum erro:
##
##   godot --headless --path . --editor --quit
##
## Por que assar num PNG em vez de desenhar o tabuleiro ao vivo dentro do cartão:
## o desfoque. Um tabuleiro nítido atrás do nome do jogo briga com ele; desfocado
## e a 8% ele vira textura. Desfocar ao vivo custaria shader e um viewport por
## linha, todo quadro, para um resultado que nunca muda.
##
## O recorte, o desfoque, os cantos arredondados e o degradê que apaga a arte do
## lado do texto ficam **assados na imagem**. O cartão só desenha o PNG esticado:
## nenhum shader, nenhum nó a mais, nenhuma conta por quadro.

const OUT_DIR := "res://assets/cards"
## Tamanho da linha na tela, em pixels de UI: largura útil de um celular estreito
## menos as margens, pela altura de `GameChoice.ROW_HEIGHT`.
const ROW := Vector2i(392, 76)
## Quantas vezes a arte é maior que a linha. Três porque é o fator de tela dos
## celulares densos: abaixo disso o aparelho estica a imagem e devolve o borrão
## que o desfoque não pediu.
const SCALE := 3
const SIZE := Vector2i(ROW.x * SCALE, ROW.y * SCALE)
## Tamanho do cartão da **grade** da tela inicial, em pixels de UI: a coluna que
## sobra de `main_menu.COLUMNS` pela altura de `TILE_HEIGHT`.
##
## Ele existe porque a faixa não serve: a arte é um recorte largo e baixo, e
## esticada num cartão quase quadrado ela sai deformada — um tabuleiro de casas
## retangulares atrás do nome do jogo chama mais atenção do que o nome. Por isso
## a grade ficou **sem** arte desde que a tela inicial virou grade, e por isso
## esta ferramenta passou a assar os dois recortes.
const TILE := Vector2i(124, 118)
const TILE_SIZE := Vector2i(TILE.x * SCALE, TILE.y * SCALE)

## Onde a janela cai sobre o tabuleiro, em fração da altura do nó. No xadrez e
## nas damas, encostada na borda de baixo do tabuleiro: é onde estão as peças que
## dizem o jogo — os peões são iguais em todo lugar —, e descer um fio a mais
## traria a faixa de coordenadas da moldura, que desfocada vira sujeira com cara
## de texto. No mar, no meio, onde a frota está.
const CROP := {
	Game.CHESS: 0.869,
	Game.CHECKERS: 0.869,
	Game.BATTLESHIP: 0.50,
	# O Ludo é o tabuleiro inteiro numa cruz: a faixa cai no meio, onde estão os
	# quatro braços e o centro colorido, que é o que identifica o jogo de longe.
	Game.LUDO: 0.50,
	# Metrópole é um anel: o meio é bege e não diz nada. A faixa cai na fileira de
	# baixo, onde estão as faixas de cor dos grupos — que é a única coisa deste
	# tabuleiro que se reconhece desfocada a 13%.
	#
	# A fileira mede 0,12 do tabuleiro e a janela 0,19: ela não tem como preencher
	# a faixa, e sobra por cima **ou** por baixo. Sobra por baixo, onde a
	# transparência some no fundo escuro do cartão; por cima seria um bloco de
	# bege ocupando o terço superior da linha.
	Game.MONOPOLY: 0.92,
	# Bomberman é o único mapa mais largo que alto, e o único em que a faixa cabe
	# quase inteira dentro dele: são 2,5 fileiras de 11. Cai no **meio**, onde o
	# xadrez de pilares está cercado de caixas — a borda de concreto de cima e de
	# baixo é uma tira cinza lisa que não diz nada desfocada.
	Game.BOMBERMAN: 0.50,
	# O Uno nao tem tabuleiro: a arte e um leque de cartas, e ele ja e uma faixa
	# larga e baixa do tamanho da linha. A janela cai no meio dele.
	Game.UNO: 0.50,
	# A sinuca é uma mesa deitada, e o que a identifica desfocada é o pano verde
	# com as bolas coloridas encostadas nas tabelas. A janela cai no meio: nos
	# cantos só há caçapa preta, que é um buraco em qualquer jogo.
	Game.POOL: 0.50,
}
## Quanto a imagem encolhe antes de voltar ao tamanho cheio. É o desfoque: o que
## se perde no caminho de ida não volta na volta.
##
## Igual a `SCALE` de propósito: a ida para em exatamente um pixel de tela por
## pixel de imagem. Joga fora o que a linha não teria como mostrar, e nada além
## disso — com o dobro disso as peças viravam manchas, que foi o que apareceu na
## primeira rodada.
const BLUR_DIVISOR := SCALE
## Canto do cartão (`AppTheme.RADIUS_LARGE`), na escala desta imagem.
const RADIUS := float(AppTheme.RADIUS_LARGE * SCALE)
## A arte só existe do meio para a direita. À esquerda estão a peça-ícone e o
## nome, e textura atrás de texto é o que transforma um cartão bonito num cartão
## ilegível.
const FADE_FROM := 0.30
const FADE_TO := 0.95
## O mesmo, no cartão da grade — e na **vertical**.
##
## Ali o nome mora embaixo e o ícone no meio, então o que precisa ficar limpo é a
## metade de baixo. A arte entra forte no topo e some antes de chegar ao texto,
## que é a mesma decisão da faixa girada noventa graus.
const TILE_FADE_FROM := 0.30
const TILE_FADE_TO := 0.80


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Dois recortes por jogo: a faixa da lista e o ladrilho da grade. Um só não
	# serve para os dois — ver [constant TILE].
	for entry in Game.GAMES:
		var id := StringName(entry["id"])
		await _render(id, SIZE, "%s/%s.png" % [OUT_DIR, id], true)
		await _render(id, TILE_SIZE, "%s/%s_tile.png" % [OUT_DIR, id], false)
	print("PRONTO ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _render(id: StringName, size: Vector2i, path: String, wide: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var board := _board_for(id)
	board.size = _cover(id, size)
	# A janela é a faixa da linha sobre o tabuleiro inteiro; puxar o nó é o mesmo
	# que rolar a imagem por baixo dela. Em x o deslocamento joga a moldura para
	# fora dos dois lados; em y ele escolhe a fileira.
	board.position = Vector2(
		-(board.size.x - float(size.x)) * 0.5,
		-(board.size.y * float(CROP[id]) - float(size.y) * 0.5)
	)
	viewport.add_child(board)

	# Dois quadros: o primeiro instancia e mede, o segundo desenha já medido.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()

	_blur(image, size)
	_mask(image, size, wide)
	image.save_png(path)


## Tamanho do nó do tabuleiro: a proporção natural dele, ampliada até **cobrir** a
## janela nos dois eixos.
##
## O cover não é zelo. A faixa é larga e baixa, então nela a largura sempre mandou
## e a altura sobrava de graça; o ladrilho é quase quadrado, e ali um nó dimensionado
## só pela largura deixa faixas transparentes em cima e embaixo. Foi o que
## aconteceu com a sinuca, cuja mesa é duas por uma: o ladrilho dela saiu quase
## vazio, com um fio de pano no meio de um retângulo transparente.
##
## O acréscimo da moldura vale só para quem desenha por `GridView`: ele reserva
## `FRAME` de casa de cada lado e centraliza o resto, então o nó precisa ser maior
## que a janela para as oito casas atravessarem — com ele do tamanho da imagem,
## sobrava a moldura como uma tira escura vazia em cada ponta.
func _cover(id: StringName, size: Vector2i) -> Vector2:
	var ratio := _board_ratio(id)
	var scale := maxf(float(size.x) / ratio.x, float(size.y) / ratio.y)
	if _framed(id):
		scale *= (Board.SIZE + GridView.FRAME * 2.0) / Board.SIZE
	return ratio * scale


## A proporção de cada tabuleiro, em unidades quaisquer.
func _board_ratio(id: StringName) -> Vector2:
	if id == Game.BOMBERMAN:
		# Treze por onze: [BomberView] escolhe a casa pelo lado mais apertado, e num
		# nó quadrado sobrariam duas casas de vazio que a janela recorta.
		return Vector2(float(BomberState.COLS), float(BomberState.ROWS))
	if id == Game.POOL:
		return Vector2(2.0, 1.0)
	if id == Game.UNO:
		# O "tabuleiro" do Uno é um leque de cartas, largo e baixo por natureza. Num
		# nó quadrado as cartas sairiam do tamanho de meio cartão.
		return Vector2(1.0, 0.26)
	return Vector2.ONE


## Desenha por `GridView`, e portanto reserva moldura. Xadrez, damas e o mar são
## grades de oito casas; o resto desenha até a borda do nó.
const FRAMED := [Game.CHESS, Game.CHECKERS, Game.BATTLESHIP]


func _framed(id: StringName) -> bool:
	return FRAMED.has(id)


func _board_for(id: StringName) -> Control:
	if id == Game.MONOPOLY:
		# O mesmo `MonopolyFace` que vira a textura do tampo 3D, desenhado em 2D.
		# É literalmente o tabuleiro do jogo, e não uma ilustração dele — se uma
		# cor de grupo mudar, esta ferramenta roda de novo e a arte acompanha.
		var face := MonopolyFace.new()
		var monopoly := MonopolyRules.new()
		var position := monopoly.initial_state()
		# Donos espalhados pela fileira de baixo: sem eles a moldura externa fica
		# vazia, e a barra colorida do dono é metade do que identifica este
		# tabuleiro. Os índices são a fileira que a janela vê.
		for entry in [[1, 0], [3, 1], [6, 2], [8, 0], [9, 3]]:
			position.meta[MonopolyRules.OWNER][entry[0]] = entry[1]
		face.state = position
		return face
	if id == Game.LUDO:
		var ludo := LudoView.new()
		var rules := LudoRules.new()
		var state := rules.initial_state()
		# Peões espalhados pelos quatro braços: o tabuleiro vazio do Ludo é só
		# geometria colorida, e o que diz "jogo de peões" são os discos nela.
		var progress := LudoRules.progress(state)
		for entry in [[0, 0, 7], [0, 1, 20], [1, 0, 3], [1, 1, 16], [2, 0, 9], [3, 0, 5]]:
			progress[LudoRules.slot(entry[0], entry[1])] = entry[2]
		state.meta[LudoRules.PROG] = progress
		ludo.state = state
		return ludo
	if id == Game.BOMBERMAN:
		return _bomber_map()
	if id == Game.UNO:
		return _uno_fan()
	if id == Game.POOL:
		return _pool_table()
	if id == Game.BATTLESHIP:
		var waters := WatersView.new()
		waters.own = true
		waters.labels = false
		waters.fleet = _fleet()
		waters.shots = _shots()
		return waters
	var view := BoardView.new()
	view.ruleset = Game.make_ruleset(id)
	view.state = view.ruleset.initial_state()
	return view


## O mapa de Bomberman armado à mão, na faixa que a janela vê.
##
## A posição inicial não serve aqui, e é o mesmo problema do mar e do Ludo: os
## quatro bonecos nascem nos **cantos**, e a janela olha o meio. A arte sairia um
## labirinto vazio — que é geometria bonita e não diz qual jogo é.
##
## O que identifica este tabuleiro desfocado a 13% são três coisas, e as três
## estão postas de propósito nas fileiras 4 a 6: o xadrez de pilares cinzas, as
## caixas cor de tijolo em volta, e uma bomba com o fogo aberto em cruz. Os
## bonecos entram pela cor — as mesmas quatro do Ludo —, que é o que sobra de um
## disco de 20 pixels depois do desfoque.
##
## Tudo isso mora da **coluna 7 para a direita**, e essa é a parte que não é
## óbvia: o degradê de [constant FADE_FROM] apaga a arte até 30% da largura e só a
## entrega inteira aos 95%, porque à esquerda estão o ícone e o nome do jogo. A
## primeira versão desta função pôs a bomba na coluna 5 — no meio do mapa, e no
## meio do apagamento. Ela estava lá, e ninguém ia ver.
func _bomber_map() -> Control:
	var view := BomberView.new()
	var rules := BomberRules.new()
	var state := rules.initial_state(4, 4242)

	# Chão embaixo do que vai ser posto: um boneco desenhado por cima de uma caixa
	# lê como erro de desenho, e o fogo atravessando concreto contradiz a regra que
	# a própria arte deveria estar anunciando.
	for cell: Vector2i in [
		Vector2i(7, 5), Vector2i(11, 5), Vector2i(7, 6),
		Vector2i(9, 5), Vector2i(8, 5), Vector2i(10, 5), Vector2i(9, 4), Vector2i(9, 6),
	]:
		var index := BomberState.index_of(cell.x, cell.y)
		state.tiles[index] = BomberState.Tile.FLOOR
		state.prizes[index] = BomberState.Prize.NONE

	for entry: Array in [[0, Vector2i(7, 5)], [1, Vector2i(11, 5)], [2, Vector2i(7, 6)]]:
		var player: BomberState.Bomber = state.players[int(entry[0])]
		var cell: Vector2i = entry[1]
		player.x = cell.x * BomberState.CELL + BomberRules.HALF
		player.y = cell.y * BomberState.CELL + BomberRules.HALF

	var bomb := BomberState.Bomb.new()
	bomb.col = 9
	bomb.row = 5
	bomb.flame = 1
	# Pavio pela metade: o desenho da bomba pulsa com ele, e no fim do pavio ela
	# aparece no tamanho errado para o que a linha quer mostrar.
	bomb.fuse = BomberRules.FUSE / 2
	state.bombs.append(bomb)

	# O fogo em cruz de um braço só. Dois braços encostariam nos bonecos, e um
	# boneco dentro do fogo é uma cena que a regra resolve matando — a arte estaria
	# mostrando o instante que não existe.
	for cell: Vector2i in [Vector2i(8, 5), Vector2i(10, 5), Vector2i(9, 4), Vector2i(9, 6)]:
		state.flames[BomberState.index_of(cell.x, cell.y)] = BomberRules.FLAME_TICKS

	view.state = state
	return view


## Frota posta à mão, e não sorteada: a janela da linha vê duas fileiras, e um
## sorteio espalha os quatro navios pelas oito — a arte saía um mar vazio, que é
## o oposto do que ela tem de dizer. Aqui os cascos estão onde a janela cai.
func _fleet() -> PackedInt32Array:
	var fleet := BattleshipRules.empty_grid()
	fleet = BattleshipRules.place(fleet, Board.Kind.BATTLESHIP, Board.square(1, 4), true)
	fleet = BattleshipRules.place(fleet, Board.Kind.CRUISER, Board.square(4, 3), true)
	fleet = BattleshipRules.place(fleet, Board.Kind.DESTROYER, Board.square(6, 4), true)
	fleet = BattleshipRules.place(fleet, Board.Kind.SUBMARINE, Board.square(0, 2), false)
	return fleet


## Um acerto e um erro: sem eles o mar é só casco em água parada, e o que a
## batalha naval tem de próprio — a marca do que já foi tentado — não aparece.
func _shots() -> PackedInt32Array:
	var shots := BattleshipRules.empty_grid()
	shots[Board.square(2, 4)] = BattleshipRules.Shot.HIT
	shots[Board.square(3, 3)] = BattleshipRules.Shot.MISS
	return shots


## Desfoque por ida e volta: encolher joga fora o detalhe, e voltar ao tamanho
## cheio interpola o que sobrou. Um gaussiano de verdade custaria um shader e um
## segundo viewport para um resultado que, a 8% de opacidade, ninguém distingue.
func _blur(image: Image, size: Vector2i) -> void:
	var small := Vector2i(maxi(1, size.x / BLUR_DIVISOR), maxi(1, size.y / BLUR_DIVISOR))
	image.resize(small.x, small.y, Image.INTERPOLATE_LANCZOS)
	image.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)


## Cantos arredondados e degradê, assados no alfa.
##
## Os cantos são obrigatórios, não enfeite: o cartão é arredondado, e uma imagem
## retangular por baixo dele acende quatro triângulos claros fora da borda — que
## a 8% de opacidade ainda aparecem no fundo escuro.
func _mask(image: Image, size: Vector2i, wide: bool) -> void:
	var half := Vector2(size) * 0.5
	var inner := half - Vector2(RADIUS, RADIUS)
	for y in size.y:
		for x in size.x:
			var color := image.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			var offset := (Vector2(x + 0.5, y + 0.5) - half).abs() - inner
			var distance := (
				Vector2(maxf(offset.x, 0.0), maxf(offset.y, 0.0)).length()
				+ minf(maxf(offset.x, offset.y), 0.0)
				- RADIUS
			)
			var corner := 1.0 - smoothstep(-1.5, 1.5, distance)
			# Na faixa o degradê é horizontal — o ícone e o nome ficam à esquerda. No
			# ladrilho ele é vertical e invertido: ali o nome mora embaixo, e a arte
			# entra pelo topo e some antes de chegar nele.
			var fade := (
				smoothstep(FADE_FROM, FADE_TO, float(x) / float(size.x)) if wide
				else 1.0 - smoothstep(TILE_FADE_FROM, TILE_FADE_TO, float(y) / float(size.y))
			)
			color.a *= corner * fade
			image.set_pixel(x, y, color)


## A mesa de sinuca, com as dez bolas no arranjo de saída.
##
## A mesma `PoolView` que a partida desenha, e o arranjo que a regra monta: se as
## cores dos grupos ou o pano mudarem, esta ferramenta roda de novo e a arte
## acompanha.
##
## Desligada para mira: a mesa em repouso é o que identifica o jogo. Um taco e
## uma linha de mira congelados na arte de fundo seriam um gesto parado no meio,
## que lê como captura de tela e não como textura.
##
## A mesa **não** é a do arranjo inicial, e é o mesmo problema do mar, do Ludo e
## do Bomberman: ali as dez bolas nascem encostadas nas tabelas, e a janela olha o
## meio. A arte saía um retângulo de pano vazio — tecnicamente uma mesa de
## sinuca, e visualmente nada.
##
## Uma tacada de abertura resolve e não inventa: ela é a mesma simulação que a
## partida roda, com uma direção escrita à mão. Determinística, então a arte sai
## igual toda vez que a ferramenta rodar.
func _pool_table() -> Control:
	var table := PoolView.new()
	var rules := PoolRules.new()
	rules.format = PoolRules.Format.KNOCKOUT
	var state := rules.initial_state()
	for entry: Array in [[0, Vector2(0.94, 0.34)], [6, Vector2(-0.86, 0.5)]]:
		rules.apply_move(state, PoolRules.shot(int(entry[0]), entry[1], 1.0))
	table.state = state
	table.enabled = false
	return table


## O leque do Uno: a mão do jogador, aberta, com as cores todas.
##
## O mesmo `UnoHand` que a partida desenha, e não uma ilustração dele — se a
## paleta da carta ou a forma do leque mudarem, esta ferramenta roda de novo e a
## arte acompanha.
##
## A mão é escolhida à mão, e é o único ponto em que esta arte "encena": um
## sorteio dá cinco cartas da mesma cor uma vez em muitas, e o que identifica o
## Uno desfocado a 13% são **as quatro cores juntas** mais o preto do curinga.
## Uma mão monocromática seria um leque genérico de cartas.
##
## Todas jogáveis e a mão ligada, porque o apagado é informação de partida: aqui
## não há vez de ninguém, e meia mão escura leria como uma imagem malfeita.
func _uno_fan() -> Control:
	var hand := UnoHand.new()
	var cards := PackedInt32Array([
		UnoRules.card(UnoRules.CardColor.RED, 7),
		UnoRules.card(UnoRules.CardColor.YELLOW, UnoRules.SKIP),
		UnoRules.card(UnoRules.CardColor.GREEN, 3),
		UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR),
		UnoRules.card(UnoRules.CardColor.BLUE, UnoRules.REVERSE),
		UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO),
		UnoRules.card(UnoRules.CardColor.YELLOW, 5),
		UnoRules.card(UnoRules.CardColor.GREEN, UnoRules.SKIP),
		UnoRules.card(UnoRules.CardColor.BLUE, 9),
	])
	hand.cards = cards
	hand.playable = cards
	hand.enabled = true
	return hand
