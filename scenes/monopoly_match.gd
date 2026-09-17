extends Control

## Uma partida de Metrópole. Tela deitada, tabuleiro 3D e duas superfícies de
## texto em cima dele.
##
## O arranjo é o do esboço, e cada peça responde uma pergunta:
##
## - **coluna da esquerda** — "como está a partida": um jogador por faixa, o
##   caixa e quantas escrituras. Sempre visível, porque comparar seis jogadores é
##   o que se faz o tempo todo;
## - **tabuleiro no meio** — onde os peões estão;
## - **painel flutuante à direita** — "onde eu caí" e "o que eu tenho": a
##   escritura da casa em foco, e a lista das suas propriedades, de onde se
##   constrói e se hipoteca.
##
## O painel flutua sobre o tabuleiro em vez de ocupar uma terceira coluna. O
## tabuleiro é quadrado e a tela é deitada: uma coluna própria o encolheria para
## caber num espaço que fica vazio a maior parte do tempo, enquanto o canto de
## cima à direita do tabuleiro em perspectiva é a área menos usada da tela.
##
## ## O layout é montado em código
##
## Como o placar do Ludo, e pelo mesmo motivo: o número de faixas da coluna vem
## da mesa (2 a 6), e seis cópias no `.tscn` é onde a terceira acaba com o nome da
## segunda. O que está no `.tscn` é a raiz e mais nada.
##
## ## O tabuleiro fica numa janela 3D
##
## `SubViewportContainer` → `SubViewport` → [monopoly_board_3d.gd]. É o que
## permite o resto do app continuar sendo `Control`: tema, botões, aviso e área
## segura funcionam por cima sem saber que há 3D embaixo.
##
## ## Em rede
##
## Cada aparelho é um assento (`Game.local_seat`), e só quem tem a decisão do
## momento vê botão. Quem decide é `MonopolyRules.actor_of()` — o jogador da vez
## em tudo, menos com uma proposta de troca na mesa, quando é o destinatário.
## Esta tela nunca pergunta `turn_of` para saber se pode agir; se perguntasse, o
## aparelho errado mandaria a resposta da troca.
##
## O que viaja é o lance, como em todos os outros jogos, e os dois acasos — os
## dados e a carta — vão dentro dele. Repetir `history` reconstrói a partida, que
## é o que faz a reconexão ser a mesma de sempre.
##
## Dois cuidados que só existem aqui, e os dois são sobre **acaso duplicado**:
##
## - a carta é sorteada por um aparelho só, o de quem está na fase de tirar. Se
##   os quatro sorteassem ao receber o lance de quem pisou na casa de Sorte, cada
##   um veria uma carta diferente;
## - os bots são jogados pelo assento 0, sempre. Dois aparelhos rolando o dado do
##   mesmo bot dariam dois lances para a mesma vez.
##
## ## O fim
##
## `MonopolyResult` cobre a tela com o vencedor e o **patrimônio final de todo
## mundo**. No formato por rodadas o vencedor é o maior patrimônio, e esse número
## não aparece em lugar nenhum durante a partida — a coluna da esquerda mostra o
## caixa, que é outra coisa.

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Largura da coluna da esquerda, na base deitada de 768. Larga o bastante para
## "M 1500" e um nome curto; estreita o bastante para o tabuleiro continuar sendo
## o assunto da tela.
const RAIL_WIDTH := 136
## Folga do painel flutuante em relação ao canto.
const PANEL_MARGIN := 10
## Largura do painel de escritura.
##
## Vem do próprio painel, e não de um número escrito aqui. Eram dois: 168 nesta
## cena e 150 lá dentro. Um `Control` nunca desenha menor que o mínimo que o
## conteúdo pede, então quem mandava não era nenhum dos dois — era a frase mais
## comprida da casa aberta, e numa casa de evento ela passava dos 168 e o painel
## esticava por cima do tabuleiro. O porquê e a correção estão em [MonopolyPanel].
const PANEL_WIDTH := MonopolyPanel.WIDTH
## Largura da barra de ação, e ela é **mais estreita** que o painel.
##
## Os dois blocos são a mesma coluna flutuante e ficam alinhados pela direita, mas
## respondem coisas de tamanhos diferentes: o painel carrega texto — nome, cidade,
## tabela de aluguel, a frase de uma casa de evento — e a barra carrega dois dados
## e um botão. Amarrar as duas ao mesmo número obrigava a escolher entre um painel
## apertado e uma barra larga à toa, e as duas escolhas custam tabuleiro.
const BAR_WIDTH := 168
## Altura da barra de ação, embaixo do painel. O painel ocupa o que sobra: assim
## os dois nunca se atropelam numa tela mais baixa, e não há dois números a somar
## certo à mão.
const BAR_HEIGHT := 112
## Largura do botão de recentrar, no canto de baixo à esquerda do palco.
const RECENTER_WIDTH := 92

## Pausa entre o dado parar e o peão sair andando. Tempo de **ler** o número —
## sem ela o tabuleiro já está se mexendo quando o olho ainda está no dado.
const READ_DICE := 0.5
## Pausa antes de a carta virar. A casa de Sorte acabou de ser pisada; virar a
## carta no mesmo quadro faz as duas coisas parecerem uma só.
const DRAW_DELAY := 0.45
## Espera antes de cada lance do bot. Ele não pensa, mas precisa **parecer** que
## decidiu: sem a pausa a vez dele acontece entre dois quadros, e o jogador vê o
## tabuleiro diferente sem ter visto nada acontecer. Mesmo motivo do Ludo.
##
## Mais curta que a do Ludo (1,1s) porque aqui um turno são vários lances: uma
## pausa longa em cada um faria a vez de um bot durar dez segundos.
const BOT_THINK := 0.55

## Os dois dados pararam. Sinal local porque são dois: esperar `rolled` de um e
## depois do outro trava quando o segundo pousa primeiro — os dois giram pelo
## mesmo tempo e param no mesmo quadro, em ordem que não se controla.
signal _dice_settled

var _rules := MonopolyRules.new()
var _state: MatchState
var _board: MonopolyBoard3D = null
## A janela 3D e o palco em que ela mora. Guardados porque o tamanho de uma sai do
## tamanho do outro toda vez que a tela muda. Ver [method _fit_window].
var _window: SubViewportContainer = null
var _stage: Control = null
## A carta virada, por cima de tudo.
var _card: MonopolyCardPopup = null
var _panel: MonopolyPanel = null
var _rail: VBoxContainer = null
var _cards: Array[MonopolyPlayerCard] = []
var _banner: Banner = null
var _bar: PanelContainer = null
var _status: Label = null
var _buttons: VBoxContainer = null
var _dice: Array[DieView] = []
var _dice_left := 0
var _trade: MonopolyTrade = null
## Fundo escuro atrás da mesa de troca. Separado do widget porque ele é um painel
## centrado, e escurecer a tela é da camada, não do painel.
var _trade_layer: Control = null
var _match_status: MatchStatus = null
var _trade_button: Button = null
var _recenter: Button = null
var _result: MonopolyResult = null
## Um lance está sendo resolvido — dado girando, peão andando. Enquanto isso a
## tela não aceita outro.
var _busy := false
## O que a barra diz enquanto o lance resolve. Sem isto ela fica muda por dois
## segundos — dado girando, peão andando — e o jogador não sabe se tocou.
var _busy_text := ""
## Cadeiras jogadas por máquina. Vem do modo: no solo são as que sobram depois da
## sua; no mesmo aparelho, nenhuma.
var _bot_seats := PackedInt32Array()
## Uma vez de bot já foi agendada. Sem isto, cada `_refresh` durante a vez dele
## marcaria outro lance e ele jogaria várias vezes de uma vez.
var _bot_pending := false
## Alguém saiu para valer, ou o link caiu. Nos dois casos a tela para de aceitar
## toque — a diferença é que o segundo pode voltar.
var _abandoned := false
var _link_down := false
## Lances que chegaram da rede e ainda não foram aplicados. Ver `_drain_incoming`.
var _incoming: Array[Dictionary] = []
var _draining := false


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	# Este é o único jogo do app que joga deitado, e quem gira é a cena. Quem
	# desgira é `Game.reset_to_menu()`, por onde toda saída passa.
	Orientation.to_landscape(get_tree())

	var online := Game.mode == Game.Mode.ONLINE
	if online:
		# O tamanho da mesa e o formato vêm de quem abriu a sala, não das escolhas
		# guardadas neste aparelho: duas mesas com limites diferentes não seriam a
		# mesma partida.
		Game.round_limit = Net.option
		_rules.seats = maxi(MonopolyRules.MIN_SEATS, Net.seats)
	else:
		_rules.seats = maxi(MonopolyRules.MIN_SEATS, Game.players_of(Game.MONOPOLY))
	_rules.round_limit = Game.round_limit
	_state = _rules.initial_state()

	if Game.mode == Game.Mode.SOLO:
		# Solo é a mesa cheia com um humano só: você é o assento 0 e o resto é
		# máquina. É o mesmo caminho de uma sala que não encheu, sem a sala.
		Game.local_seat = 0
		for seat in range(1, MonopolyRules.seats_of(_state)):
			_bot_seats.append(seat)
	if online:
		Game.local_seat = Net.local_seat
		_bot_seats = Net.bot_seats
		Net.move_received.connect(_on_remote_move)
		Net.opponent_left.connect(_on_opponent_left)
		Net.seat_left.connect(_on_seat_left)
		Net.seat_returned.connect(_on_seat_returned)
		Net.link_lost.connect(_on_link_lost)
		Net.link_restored.connect(_on_link_restored)
		Net.sync_received.connect(_apply_sync)
		# Os nomes chegam **depois** da tela: quem entra se apresenta no `ready` e
		# quem volta no `resumed`, e os dois caem no meio de uma partida já
		# desenhada. Sem isto o cartão só se corrigia no lance seguinte.
		Net.names_changed.connect(_refresh)
		# A cópia local da lista de máquinas envelhece: ela é lida a cada decisão
		# de vez, e uma cadeira pode deixar de ser de máquina no meio da partida
		# quando alguém senta nela.
		Net.bots_changed.connect(_adopt_bot_seats)

	_build_layout()
	_refresh()
	# Depois de montar a partida: quem entrou numa que já estava em curso recebeu o
	# histórico antes desta cena existir, e ele ficou guardado esperando.
	Net.claim_sync()


func _exit_tree() -> void:
	Orientation.reset(get_tree())


# --- montagem -----------------------------------------------------------------


func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var safe := SafeAreaMargin.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 8)
	add_child(safe)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	safe.add_child(row)

	_rail = VBoxContainer.new()
	_rail.custom_minimum_size.x = RAIL_WIDTH
	_rail.add_theme_constant_override("separation", 6)
	row.add_child(_rail)

	# No topo da coluna, acima dos cartões. Ela é a coluna do estado da partida, e
	# tempo, rodadas e sala são estado da partida — a barra embaixo é sobre a
	# **vez**, e some e volta a cada rolagem.
	#
	# Os cartões absorvem a altura que ela custa: são `SIZE_EXPAND_FILL` e o pé é
	# fixo, então a mesa de seis aperta uns pixels em cada faixa em vez de empurrar
	# o botão de sair para fora da tela — que foi o que já aconteceu uma vez aqui.
	Game.begin_match()
	_match_status = MatchStatus.create()
	_rail.add_child(_match_status)

	# O tabuleiro fica numa moldura própria: é ela que recorta a janela 3D e é
	# nela que o painel flutuante se ancora, para o painel acompanhar o tabuleiro
	# e não a tela inteira.
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	row.add_child(stage)

	# Sem âncoras: o tamanho e a escala deste contêiner são escritos por
	# `_fit_window`, e um preset os reescreveria a cada layout. Ver lá o porquê.
	var window := SubViewportContainer.new()
	window.stretch = true
	stage.add_child(window)

	var viewport := SubViewport.new()
	# O toque tem de chegar ao `_unhandled_input` do nó 3D para virar casa. Sem
	# isto o `SubViewport` entrega tudo ao 2D que ele não tem e o tabuleiro fica
	# mudo.
	viewport.handle_input_locally = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	window.add_child(viewport)
	_wire_window(stage, window)

	_board = MonopolyBoard3D.new()
	viewport.add_child(_board)
	_board.tile_tapped.connect(_on_tile_tapped)
	_board.camera_freed.connect(_update_recenter)

	# "Recentrar" no canto de baixo à esquerda do palco, e só enquanto a câmera
	# está na mão do jogador.
	#
	# Ele não cabe na barra nem na coluna, e não deveria: as duas são sobre a
	# **partida**, e este é sobre a vista. Aparecendo só quando a câmera saiu do
	# automático, ele também é a única coisa na tela que diz que ela saiu — sem
	# ele, uma mesa girada é indistinguível de uma mesa quebrada.
	_recenter = Button.new()
	_recenter.text = "Recentrar"
	MonopolyPanel.compact(_recenter)
	_recenter.visible = false
	_recenter.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_recenter.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_recenter.offset_left = PANEL_MARGIN
	# A largura é escrita, e não deixada ao conteúdo: com âncoras nos dois cantos
	# esquerdos, o retângulo sai de `offset_right - offset_left`, e o zero que um
	# preset deixa ali dá **largura negativa**. O botão nasceu como uma lasca de
	# três pixels no canto da tela.
	_recenter.offset_right = PANEL_MARGIN + RECENTER_WIDTH
	_recenter.offset_top = -(PANEL_MARGIN + 28)
	_recenter.offset_bottom = -PANEL_MARGIN
	_recenter.pressed.connect(func() -> void: _board.recenter())
	stage.add_child(_recenter)

	_panel = MonopolyPanel.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -(PANEL_MARGIN + PANEL_WIDTH)
	_panel.offset_top = PANEL_MARGIN
	_panel.offset_right = -PANEL_MARGIN
	_panel.offset_bottom = -(PANEL_MARGIN * 2 + BAR_HEIGHT)
	_panel.naming(_player_label)
	_panel.tile_chosen.connect(_on_tile_tapped)
	_panel.action_requested.connect(_on_action)
	stage.add_child(_panel)

	_build_bar(stage)

	_banner = Banner.new()
	# O aviso daqui é notícia, e não confirmação de um toque: ele conta o que
	# aconteceu com o dinheiro de outra pessoa, com nomes e uma casa no meio, e
	# quase sempre enquanto o olho está no tabuleiro. Uma frase dessas some antes
	# de ser lida no tempo que basta para "Lance inválido".
	_banner.linger = 1.7
	# Largura inteira do palco: o aviso se desenha centrado dentro do que recebe,
	# e ancorado só pelo centro ele nasce com largura zero e o texto some.
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = PANEL_MARGIN
	_banner.offset_right = -(PANEL_MARGIN * 2 + PANEL_WIDTH)
	stage.add_child(_banner)

	# Cinco cadeiras ou mais e os cartões apertam. Quem sabe de quantos é a mesa é
	# esta cena; o cartão desenha um jogador e não conhece os outros.
	var seats := MonopolyRules.seats_of(_state)
	for player in seats:
		var card := MonopolyPlayerCard.new()
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.chosen.connect(_on_player_chosen)
		_rail.add_child(card)
		# Depois de entrar na árvore: os rótulos que ele aperta só existem a partir
		# do `_ready` dele.
		card.dense(seats >= 5)
		_cards.append(card)

	# Trocar mora na coluna, e não na barra de ações.
	#
	# A barra responde "o que esta fase pede de você", e some e reaparece a cada
	# rolagem. Propor uma troca não é o que a fase pede — é uma coisa que se pode
	# fazer em quase qualquer ponto do próprio turno, e que abre outra tela em vez
	# de jogar um lance. Na barra ela também não caberia: a fase da cadeia já
	# oferece três botões nos 112 de altura.
	#
	# Lado a lado com "Sair", e não empilhado: seis faixas de jogador mais dois
	# botões em coluna não cabem nos 416 de altura da base deitada, e o que sobra
	# de fora é o último — que era justamente a saída da partida.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	_rail.add_child(foot)

	_trade_button = Button.new()
	_trade_button.text = "Trocar"
	MonopolyPanel.compact(_trade_button)
	_trade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade_button.pressed.connect(_open_trade)
	foot.add_child(_trade_button)

	# O mesmo componente dos outros jogos: ícone quadrado, vermelho de aviso, com
	# a pergunta de confirmação dentro dele. Aqui ele divide o rodapé com o botão
	# de troca, e por isso não se estica — quem ocupa a linha é a ação de jogar.
	var leave := LeaveButton.new()
	leave.confirmed.connect(_leave)
	foot.add_child(leave)

	_build_trade_layer()

	# A carta fica **acima** da mesa de troca e abaixo do resultado: enquanto ela
	# está na frente, o turno está parado esperando o efeito dela, e nada atrás
	# aceita toque.
	_card = MonopolyCardPopup.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_card)

	# Fora da área segura e por cima de tudo: a partida acabou, e o que estava
	# atrás não aceita mais toque.
	_result = MonopolyResult.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.again_pressed.connect(_restart)
	_result.leave_pressed.connect(_leave)
	add_child(_result)


## Faz o tabuleiro ser desenhado nos pixels que a tela tem de verdade.
##
## O app roda em `canvas_items` sobre uma base de 432×768: tudo é medido nessa
## base e o esticamento da janela amplia o resultado até a resolução do aparelho.
## Para o 2D isso é de graça — o tema desenha vetorial no tamanho final, e é por
## isso que o texto da tela nunca esteve borrado. Para o `SubViewport` do
## tabuleiro não é: ele é uma **imagem**. O contêiner escreve nele o tamanho que
## tem, em unidades da base, então num celular 1080p deitado o tabuleiro inteiro é
## desenhado em 768×432 e depois esticado para 2400×1080. É essa ampliação que se
## vê como serrilha nas quinas e como nome de casa borrado.
##
## `scaling_3d_scale` **não** resolve isto, e foi a primeira tentativa: ele
## multiplica a resolução em que a cena 3D é desenhada *dentro* do viewport, mas o
## alvo final continua do tamanho do contêiner. Limpa a imagem pequena; não a
## aumenta. No aparelho não mudou nada, e não tinha como mudar.
##
## O que resolve é o viewport ser **maior**. Como `stretch` cola o tamanho dele no
## do contêiner, quem cresce é o contêiner — e a escala do `Control` o devolve ao
## tamanho na tela:
##
##     contêiner: tamanho = palco × f,  escala = 1/f
##
## O resultado ocupa exatamente o mesmo retângulo de antes, com f vezes mais
## pixels. O toque continua chegando ao nó 3D porque `SubViewportContainer`
## converte o evento pela transformação do próprio `Control`, e a projeção do
## toque no tampo mede o viewport, que cresceu junto.
##
## Teto de 2. O fator de um celular denso passa de 2,5, e a diferença entre 2× e
## 3× num tabuleiro visto de longe não paga desenhar o dobro de pixels com sombra
## e MSAA num aparelho de bateria.
const MAX_PIXEL_SCALE := 2.0


## Liga o tamanho da janela 3D ao do palco, e refaz a conta quando ele muda.
##
## O palco muda de tamanho mais vezes do que parece: ao deitar a tela (que esta
## cena pede no `_ready`, e que só vale no quadro seguinte), ao girar o aparelho, e
## no primeiro quadro, quando as âncoras ainda não foram resolvidas.
func _wire_window(stage: Control, window: SubViewportContainer) -> void:
	_window = window
	_stage = stage
	stage.resized.connect(_fit_window)
	_fit_window()


func _fit_window() -> void:
	if _window == null or _stage == null:
		return
	var stage_size := _stage.size
	if stage_size.x < 1.0 or stage_size.y < 1.0:
		return
	# O fator de esticamento da janela, tirado da própria transformação que o
	# motor aplica. Perguntar o tamanho da janela e dividir pelo do viewport dá o
	# mesmo número quando dá certo, e dá 1 quando a API responde em pixels em vez
	# de unidades de base — que é silencioso e foi o que escondeu este problema.
	var stretch := get_viewport().get_final_transform().get_scale().x
	var factor := clampf(stretch, 1.0, MAX_PIXEL_SCALE)
	_window.size = stage_size * factor
	_window.scale = Vector2.ONE / factor


## A mesa de troca, escondida até alguém abrir.
##
## Ela cobre a tela inteira porque é a jogada mais cara de montar do jogo — duas
## listas de escrituras e um valor — e o painel flutuante tem 168 de largura.
func _build_trade_layer() -> void:
	_trade_layer = Control.new()
	_trade_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_trade_layer.visible = false
	add_child(_trade_layer)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.66)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_trade_layer.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_trade_layer.add_child(center)

	_trade = MonopolyTrade.new()
	_trade.naming(_player_label)
	_trade.proposed.connect(_on_trade_proposed)
	_trade.answered.connect(_on_trade_answered)
	_trade.dismissed.connect(_close_trade)
	center.add_child(_trade)


## Os dois dados e o botão do momento, embaixo do painel.
##
## Uma **barra por fase**, e não uma fileira fixa de botões: em Metrópole quase
## todo momento tem uma ação só que faz sentido, e as outras nem existem. Uma
## fileira fixa exigiria acinzentar cinco botões para acender um, o que ensina a
## ignorar a fileira inteira.
func _build_bar(stage: Control) -> void:
	_bar = PanelContainer.new()
	var bar := _bar
	bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_left = -(PANEL_MARGIN + BAR_WIDTH)
	bar.offset_right = -PANEL_MARGIN
	bar.offset_top = -(PANEL_MARGIN + BAR_HEIGHT)
	bar.offset_bottom = -PANEL_MARGIN
	var style := AppTheme.box(
		Color(AppTheme.SURFACE, 0.96), AppTheme.RADIUS_LARGE, AppTheme.BORDER, 1
	)
	# As folgas do tema saem, como no cartão de jogador e pelo mesmo motivo:
	# `AppTheme.box` embute 14 em cima e 14 embaixo, feitas para painel de menu.
	# Aqui elas somavam 28 à altura mínima de uma barra que tem 112, e o
	# `MarginContainer` de dentro já dá a folga que ela precisa.
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	bar.add_theme_stylebox_override("panel", style)
	stage.add_child(bar)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	bar.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.add_theme_constant_override("separation", 8)
	column.add_child(pair)
	for _index in 2:
		var die := DieView.new()
		die.rolled.connect(_on_die_settled)
		pair.add_child(die)
		# Os dois **depois** de entrar na árvore: o `_ready` do dado escreve o
		# tamanho mínimo dele (76, feito para ser o único alvo da tela do Ludo) e
		# apagaria estes se viessem antes.
		#
		# O dado não aceita toque: são **dois**, e cada um sorteando por conta
		# produziria dois lances que não existem. Quem rola é o botão, que decide
		# os dois valores e manda cada dado parar no seu. Isto já estava escrito
		# antes do `add_child` e era desfeito lá dentro — o dado girava ao toque,
		# parava num número que a partida ignorava, e ainda gastava um dos dois
		# avisos de "dado parou".
		die.mouse_filter = Control.MOUSE_FILTER_IGNORE
		die.custom_minimum_size = Vector2(40, 40)
		_dice.append(die)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 4)
	column.add_child(_buttons)


# --- ciclo da vez -------------------------------------------------------------


## Qual botão a barra oferece agora. Sai direto da fase, que é o que as regras
## consultam para dizer o que é legal — a tela não tem uma segunda ideia sobre em
## que ponto do turno a partida está.
func _update_bar() -> void:
	_paint_bar()
	# Depois de a barra ter os botões da fase, e não antes: é a contagem deles que
	# decide a altura dela, e é a altura dela que decide onde o painel termina.
	_fit_panel()


func _paint_bar() -> void:
	for child in _buttons.get_children():
		# Fora da árvore **antes** de liberar: `queue_free` é adiado, e um botão
		# em vias de morrer ainda conta na altura mínima da barra — que é
		# exatamente o número que `_fit_panel` vai ler daqui a algumas linhas.
		_buttons.remove_child(child)
		child.queue_free()
	# `actor_of` e não `turn_of`: com uma proposta na mesa quem decide é o
	# destinatário, e a barra tem de falar com ele.
	var actor := MonopolyRules.actor_of(_state)
	var color: Color = MonopolyFace.PLAYER_COLORS[actor % MonopolyFace.PLAYER_COLORS.size()]
	for die in _dice:
		die.tint = color

	if _rules.winner(_state) >= 0:
		_status.text = "%s venceu." % _player_label(_rules.winner(_state))
		return
	if _abandoned:
		_status.text = "A partida acabou."
		return
	if _link_down:
		_status.text = "Conexão instável; tentando voltar…"
		return
	if _busy:
		_status.text = _busy_text
		return
	if not _my_turn():
		# Nem a máquina nem o jogador do outro aparelho recebem botões. O que a
		# barra faz é dizer de quem é a vez, para quem está olhando não achar que
		# travou.
		_status.text = "Vez de %s." % _player_label(actor)
		if _is_bot(actor):
			_status.text += " (bot)"
		return

	match MonopolyRules.phase_of(_state) as int:
		MonopolyRules.Phase.ROLL:
			_status.text = "Vez de %s." % _player_label(actor)
			_bar_button("Rolar", _roll, true)
		MonopolyRules.Phase.JAILED:
			_status.text = "%s está na cadeia." % _player_label(actor)
			_bar_button("Rolar (dupla solta)", _roll, true)
			if MonopolyRules.jail_cards_of(_state, actor) > 0:
				_bar_button("Usar saída livre", func() -> void: _try(MonopolyRules.Act.USE_CARD))
			if MonopolyRules.cash_of(_state, actor) >= MonopolyBoard.BAIL:
				_bar_button(
					"Pagar fiança %d" % MonopolyBoard.BAIL,
					func() -> void: _try(MonopolyRules.Act.BAIL)
				)
		MonopolyRules.Phase.BUY:
			var tile := MonopolyRules.position_of(_state, actor)
			_status.text = "%s está à venda." % MonopolyBoard.display_name(tile)
			if MonopolyRules.cash_of(_state, actor) >= MonopolyBoard.price_of(tile):
				_bar_button(
					"Comprar por %d" % MonopolyBoard.price_of(tile),
					func() -> void: _try(MonopolyRules.Act.BUY), true
				)
			_bar_button("Deixar passar", func() -> void: _try(MonopolyRules.Act.DECLINE))
		MonopolyRules.Phase.DRAW:
			_status.text = "Tirando a carta…"
		MonopolyRules.Phase.MANAGE:
			# Tirou dupla: o turno volta para o mesmo jogador depois de encerrar.
			_status.text = (
				"Dupla — você joga de novo."
				if int(_state.meta[MonopolyRules.DOUBLES]) > 0
				else "Construa, hipoteque, ou encerre."
			)
			_bar_button("Encerrar turno", func() -> void: _try(MonopolyRules.Act.END), true)
		MonopolyRules.Phase.RAISE:
			_status.text = "Deve %d. Venda ou hipoteque pelo painel." % MonopolyRules.debt_of(_state)
			_bar_button("Declarar falência", func() -> void: _try(MonopolyRules.Act.BANKRUPT))
		MonopolyRules.Phase.TRADE:
			# Os botões de verdade estão na mesa de troca, que `_refresh` abre
			# sozinha. A barra só diz por que a partida parou, para o caso de a
			# mesa ter sido fechada sem resposta.
			_status.text = "%s propôs uma troca." % _player_label(
				MonopolyRules.turn_of(_state)
			)
			_bar_button("Ver a proposta", _open_trade, true)


## Um botão da barra. `primary` é o que a fase **pede** — rolar, encerrar, comprar
## —, e sai em latão pulsando; o resto é alternativa, e fica na cor da superfície.
##
## Um por barra, no máximo. Dois latões pulsando lado a lado não destacam nenhum
## dos dois e ainda desmentem a regra do tema, que reserva o cheio para a ação da
## tela.
func _bar_button(label: String, action: Callable, primary := false) -> void:
	var button := Button.new()
	button.text = label
	MonopolyPanel.compact(button)
	button.pressed.connect(action)
	_buttons.add_child(button)
	# Depois de entrar na árvore: o pulso é um `Tween`, e um nó de fora da árvore
	# não tem de onde tirar um.
	if primary:
		MonopolyPanel.highlight(button)


## Encosta o rodapé do painel no topo da barra, seja qual for a altura dela.
##
## A barra tem altura **variável**: uma fase oferece um botão e a da cadeia
## oferece três, e o aviso de status quebra em duas linhas quando o nome do
## jogador é comprido. Ela cresce para cima (`GROW_DIRECTION_BEGIN`), então tudo
## o que passa dos 112 nominais entrava por dentro do painel de escritura — que é
## o que se via como um bloco em cima do outro.
##
## O painel cede, e não a barra: a barra é onde se toca, e o painel já rola por
## dentro. Perder três linhas de tabela de aluguel é barato; perder o botão de
## rolar não é.
##
## A altura sai do tamanho **desenhado**, um quadro depois, e não de
## `get_combined_minimum_size()`. Aquele número mente aqui: o rótulo de status
## quebra linha sozinho, e um `Label` com quebra automática reporta a altura que
## ele teria na largura que ainda não recebeu — que é estreitíssima, e portanto
## muitas linhas. Pela conta do mínimo a barra pedia uns 250 e desenhava 160, e o
## painel encolhia noventa pixels à toa.
func _fit_panel() -> void:
	if _bar == null or _panel == null:
		return
	await get_tree().process_frame
	if not is_inside_tree() or _bar == null or _panel == null:
		return
	_panel.offset_bottom = -(PANEL_MARGIN * 2 + maxf(float(BAR_HEIGHT), _bar.size.y))


## Rola os dois dados e joga o lance que eles formam.
##
## Os dois valores são decididos **antes** da animação, e juntos: em Metrópole o
## lance é `[ROLL, d1, d2]`, uma coisa só. A animação só atrasa a notícia — o que
## a partida registra não depende de quantos quadros a tela conseguiu desenhar.
func _roll() -> void:
	if _busy:
		return
	_busy = true
	_update_bar()
	var first := randi_range(1, 6)
	var second := randi_range(1, 6)
	await _spin_dice(first, second)
	if not is_inside_tree():
		return
	_busy = false
	await _play(PackedInt32Array([MonopolyRules.Act.ROLL, first, second]))


## Gira os dois dados até os valores dados e espera a leitura.
##
## Um só caminho para os dois casos: a rolagem local, que sorteia e depois anima,
## e a que chegou de outro aparelho, que já vem com os valores. Escrito duas
## vezes, o segundo caso é o que ficaria de fora — foi o que aconteceu: quem não
## rolava nunca via o número, só a consequência dele.
## `quick` mostra os números sem a rolagem, e é o caso de quem **assiste**.
##
## O giro de quase um segundo é suspense, e suspense é de quem rolou. Para os
## outros três da mesa ele é espera pura: multiplicado por três adversários, era
## um minuto por partida de gente olhando dado girar com o resultado já decidido
## — e da cadeira deles isso parece o servidor ter ficado lento.
##
## O que o espectador precisa é do **número**, e ele aparece na hora: escrever em
## `value` já transiciona a face, então a informação chega animada sem a espera.
func _spin_dice(first: int, second: int, quick := false) -> void:
	_busy_text = "Rolando…"
	_update_bar()
	if quick:
		_dice[0].value = first
		_dice[1].value = second
	else:
		_dice_left = 2
		_dice[0].roll_to(first)
		_dice[1].roll_to(second)
		await _dice_settled
	if not is_inside_tree():
		return
	_busy_text = "Tirou %d." % (first + second)
	if first == second:
		_busy_text += " Dupla!"
	_update_bar()
	await get_tree().create_timer(READ_DICE).timeout


func _is_bot(player: int) -> bool:
	return _bot_seats.has(player)


## Uma cadeira mudou de dono entre máquina e gente. Relê a lista e redesenha.
##
## Redesenhar junto não é enfeite: o cartão diz "(bot)" e a barra diz de quem é a
## vez, e as duas leem esta lista. Deixar a atualização para o lance seguinte
## mostraria uma pessoa jogando com "(bot)" escrito ao lado do nome dela.
func _adopt_bot_seats() -> void:
	_bot_seats = Net.bot_seats
	_refresh()


## Vez em que **este humano** decide. No mesmo aparelho é toda vez que não seja de
## máquina — quem segura o celular joga as seis cadeiras. Em rede, só a do próprio
## assento.
##
## Quem decide sai de `actor_of`, e não da vez: com uma proposta na mesa é o
## destinatário que responde, e é o aparelho **dele** que precisa dos botões.
func _my_turn() -> bool:
	var actor := MonopolyRules.actor_of(_state)
	return not _is_bot(actor) and _drives(actor)


## Este aparelho responde por este jogador.
func _drives(player: int) -> bool:
	if _is_bot(player):
		return _drives_bots()
	if Game.mode != Game.Mode.ONLINE:
		return true
	return player == Game.local_seat


## Este aparelho é o que joga pelos bots. No solo não há outro; em rede é sempre o
## assento 0, e os lances dele saem pela mesma mensagem de um lance humano.
##
## Dois aparelhos rolando o dado do mesmo bot dariam dois lances para a mesma vez,
## e as partidas divergiriam no primeiro deles — o oposto do que a lista de lances
## promete.
func _drives_bots() -> bool:
	return Game.mode != Game.Mode.ONLINE or Net.drives_bots()


## A vez de uma máquina, jogada como a de um humano: um lance por vez, pelo mesmo
## `_play`, com a mesma animação.
##
## Um lance por chamada, e não o turno inteiro de uma vez: assim o bot constrói
## três casas em três lances visíveis, e quem assiste consegue acompanhar o que
## ele fez. Também é o que faz a heurística não precisar saber quantas construções
## cabem num turno — ela responde "e agora?" e é perguntada de novo.
##
## Rolar é tratado à parte porque **não é uma escolha**: a heurística devolveria
## um lance de rolagem com dois valores já sorteados, e a tela precisa dos dados
## girando. `_roll()` sorteia os seus e anima; dá no mesmo, e o dado aparece.
func _run_bot() -> void:
	_bot_pending = true
	await get_tree().create_timer(BOT_THINK).timeout
	if not is_inside_tree():
		return
	_bot_pending = false
	var actor := MonopolyRules.actor_of(_state)
	if _busy or _abandoned or _link_down or not _is_bot(actor) or not _drives_bots():
		return
	if _rules.winner(_state) >= 0:
		return
	# A carta quem tira é `_after_move`, que já mostra o texto dela no aviso. A
	# heurística também sabe tirar uma — ela responde por qualquer fase, e é isso
	# que o teste headless usa —, e deixar os dois caminhos vivos aqui seria dois
	# sorteios disputando a mesma carta.
	if MonopolyRules.phase_of(_state) == MonopolyRules.Phase.DRAW:
		return

	var choice := _rules.best_move(_state, _rules.generate_moves(_state))
	if choice == null:
		return
	if MonopolyRules.act_of(choice) == MonopolyRules.Act.ROLL:
		await _roll()
		return
	await _play(choice.path)


## Um som para os **dois** dados, no último a parar. Dois chocalhos no mesmo
## quadro somam em amplitude e viram um estouro.
func _on_die_settled(_value: int) -> void:
	_dice_left -= 1
	if _dice_left <= 0:
		Sound.play(Sound.Cue.DICE)
		_dice_settled.emit()


## Um lance qualquer, montado à mão, conferido contra as regras e animado.
##
## Tudo passa por aqui: o botão da barra, o botão do painel, a mesa de troca, o
## bot e a rede. É o único lugar que aplica um lance, então é o único que precisa
## saber esperar o peão andar — e o único que precisa lembrar de mandá-lo.
##
## Quem confere é `MonopolyRules.validate()`, e não uma varredura de
## `generate_moves` daqui: a proposta de troca não é enumerável, e uma tela que
## conferisse por pertencer à lista simplesmente não conseguiria jogar uma.
func _play(path: PackedInt32Array, from_network := false) -> bool:
	if _busy or _abandoned:
		return false
	var move := _rules.validate(_state, path)
	if move == null:
		return false

	# O lance sai **antes** de ser aplicado: `_state.ply` é o índice dele, e depois
	# de aplicar já é o do próximo. É esse `n` que torna o lance idempotente do
	# outro lado, e é o que impede uma reconexão de aplicar duas vezes o que já
	# tinha chegado.
	if not from_network and Game.mode == Game.Mode.ONLINE:
		Net.send_move({"p": move.path, "pr": 0}, _state.ply)

	_busy = true
	await _resolve(move, from_network)
	_busy = false
	_busy_text = ""
	_refresh()
	_after_move()
	return true


func _try(action: int, tile := -1) -> void:
	var path := (
		PackedInt32Array([action]) if tile < 0 else PackedInt32Array([action, tile])
	)
	if not await _play(path):
		_banner.show_message("As regras não permitem isso agora.", Banner.Kind.ALERT)


## Aplica e mostra o que aconteceu.
##
## A leitura é feita **antes** de aplicar: depois do `apply_move` o peão já está
## no destino e o dinheiro já mudou de mãos, e não há como saber de onde nenhum
## dos dois saiu.
func _resolve(move: Move, from_network := false) -> void:
	# Os dados de quem rolou **em outro aparelho** giram aqui também.
	#
	# O lance viaja como `[ROLL, d1, d2]` e era aplicado direto: o peão saía
	# andando e os dados desta tela continuavam mostrando o número da vez
	# anterior. Quem não rolou nunca via o que foi tirado — a informação mais
	# básica do turno chegava só como consequência.
	#
	# Só quando veio de fora: a rolagem local já foi animada por `_roll()` antes
	# de virar lance, e animar de novo giraria os dados duas vezes.
	if from_network and MonopolyRules.act_of(move) == MonopolyRules.Act.ROLL:
		await _spin_dice(move.path[1], move.path[2], true)
		if not is_inside_tree():
			return

	# A carta tirada em outro aparelho é virada aqui também, pelo mesmo motivo dos
	# dados: quem não tirou via só o efeito. Ela vem pronta dentro do lance —
	# `[DRAW, baralho, índice]` —, então não há sorteio nenhum a repetir.
	#
	# Só quando veio de fora: quem tirou já a viu em `_after_move`, antes de o
	# lance existir, e mostrá-la de novo aqui seria a mesma carta duas vezes.
	if from_network and MonopolyRules.act_of(move) == MonopolyRules.Act.DRAW:
		await _reveal_card(move.path[1], move.path[2])
		if not is_inside_tree():
			return

	var actor := MonopolyRules.turn_of(_state)
	var from := MonopolyRules.position_of(_state, actor)
	var was_jailed := MonopolyRules.in_jail(_state, actor)
	# O caixa de **todo mundo**, e não só o de quem joga.
	#
	# É o que permite o aviso dizer para quem o dinheiro foi. As regras não contam
	# transações — elas mexem no bolso e seguem —, então a única forma de saber que
	# um aluguel foi pago a alguém é reparar que esse alguém ficou mais rico no
	# mesmo lance. Ler todos custa uma volta num vetor de até seis.
	var purses := _purses()
	# Lido antes por outro motivo: aceitar ou recusar **apaga** a proposta, e
	# depois não há como saber com quem ela era.
	var partner := MonopolyRules.offer_to(_state)

	_rules.apply_move(_state, move)

	if _announce_trade(move, actor, partner):
		return

	var to := MonopolyRules.position_of(_state, actor)
	var jailed := MonopolyRules.in_jail(_state, actor) and not was_jailed
	if to != from and not jailed:
		# O tabuleiro precisa do estado novo para saber quem está onde, e da casa
		# antiga para saber de onde o peão sai. O estado já é o final; quem anda
		# é o desenho.
		_board.state = _state
		_board.walk(actor, from, MonopolyBoard.steps_between(from, to, _walks_backward(move)))
		await _board.walk_finished
	elif jailed:
		# Ir para a cadeia não é andar: o peão **é posto** lá, sem passar pelas
		# vinte casas do caminho — e passar por elas seria dizer que ele passou
		# pela Partida, que é exatamente o que a regra nega.
		_board.state = _state

	_report(actor, purses, move, from, to)
	if to != from:
		# O foco segue o peão: depois de andar, a pergunta é sempre "onde eu caí",
		# e obrigar a tocar na casa para descobrir seria pedir um toque cuja
		# resposta a tela já sabe.
		_on_tile_tapped(to)


## Conta o que aconteceu com a proposta, e devolve verdadeiro quando o lance era
## sobre ela.
##
## Troca não move peão nem cabe no relato de caixa: aceitar mexe no bolso de dois
## jogadores ao mesmo tempo, e `_report` só sabe falar da diferença de um. Sai
## antes, com o nome dos dois.
func _announce_trade(move: Move, actor: int, partner: int) -> bool:
	match MonopolyRules.act_of(move):
		MonopolyRules.Act.OFFER:
			_banner.show_message("%s propôs uma troca a %s." % [
				_player_label(actor), _player_label(move.path[1])
			])
		MonopolyRules.Act.ACCEPT:
			_banner.show_message("%s aceitou a troca." % _player_label(partner))
		MonopolyRules.Act.REJECT:
			_banner.show_message(
				"%s recusou a troca." % _player_label(partner), Banner.Kind.ALERT
			)
		_:
			return false
	return true


## Este lance anda de ré. Só uma carta faz isso; todo o resto vai para a frente.
static func _walks_backward(move: Move) -> bool:
	if MonopolyRules.act_of(move) != MonopolyRules.Act.DRAW:
		return false
	return MonopolyBoard.card_walks_backward(move.path[1], move.path[2])


## O caixa de todos os assentos, agora.
func _purses() -> PackedInt32Array:
	var purses := PackedInt32Array()
	for seat in MonopolyRules.seats_of(_state):
		purses.append(MonopolyRules.cash_of(_state, seat))
	return purses


## O que aconteceu, em uma linha — com nome, valor, motivo e destinatário.
##
## Ele dizia só "Fulano recebeu 150", e esse aviso respondia a pergunta menos
## interessante das três que o momento levanta. Quem paga já sabe que pagou; o que
## ele não sabe é **por quê** e **a quem** — e quem está assistindo não sabe nem
## que houve cobrança. Num jogo em que o dinheiro dos outros é a informação que
## decide a próxima troca, isso é a partida inteira acontecendo em silêncio.
##
## Os valores saem da **diferença de caixa**, e não de refazer a conta do aluguel:
## a regra já cobrou, e recalcular aqui seria uma segunda resposta para a mesma
## pergunta — que é como as duas passam a discordar. O que a diferença não sabe é
## o motivo, e esse sai do lance: comprar, construir, hipotecar e a fiança se
## anunciam sozinhos; o resto é aluguel, banco, ou acerto com a mesa toda.
func _report(actor: int, before: PackedInt32Array, move: Move, from: int, to: int) -> void:
	var now := _purses()
	var moved := now[actor] - before[actor]
	# Quem mais mexeu no bolso neste lance. Em aluguel é um; numa carta de "pague a
	# cada jogador" são todos; em imposto não é ninguém, e o dinheiro foi ao banco.
	var others := PackedInt32Array()
	var others_total := 0
	for seat in now.size():
		if seat != actor and now[seat] != before[seat]:
			others.append(seat)
			others_total += absi(now[seat] - before[seat])

	var line := _reason(actor, move, moved, others, others_total)
	if line.is_empty():
		return
	# Passar pela Partida vem junto, e não no lugar: quem anda 12 casas pode cruzar
	# a Partida **e** cair num aluguel, e o caixa mostra só o saldo dos dois. Sem
	# esta frase, o jogador vê "recebeu 165" e não entende de onde saiu o número.
	# Andou para a frente e chegou num índice **menor**: deu a volta no anel, e
	# quem dá a volta passa pela Partida. Cair nela também conta, e cai neste mesmo
	# teste. De ré nunca conta, que é exatamente o que a regra da carta diz.
	if to < from and not _walks_backward(move):
		line = "Passou pela Partida. " + line
	if moved < 0:
		Sound.play(Sound.Cue.ALERT)
		_banner.show_message(line, Banner.Kind.ALERT)
	else:
		Sound.play(Sound.Cue.CASH)
		_banner.show_message(line)


## A frase, escolhida pelo lance. Vazia quando não há nada que valha um aviso.
func _reason(
	actor: int, move: Move, moved: int, others: PackedInt32Array, others_total: int
) -> String:
	var who := _player_label(actor)
	var act := MonopolyRules.act_of(move)
	var target := move.path[1] if move.path.size() > 1 else -1

	match act:
		MonopolyRules.Act.BUY:
			var bought := MonopolyRules.position_of(_state, actor)
			return "%s comprou %s por %d." % [who, MonopolyBoard.display_name(bought), -moved]
		MonopolyRules.Act.BUILD:
			return "%s construiu em %s por %d." % [
				who, MonopolyBoard.display_name(target), -moved
			]
		MonopolyRules.Act.SELL:
			return "%s vendeu uma construção em %s e recebeu %d." % [
				who, MonopolyBoard.display_name(target), moved
			]
		MonopolyRules.Act.MORTGAGE:
			return "%s hipotecou %s por %d." % [who, MonopolyBoard.display_name(target), moved]
		MonopolyRules.Act.UNMORTGAGE:
			return "%s resgatou %s por %d." % [who, MonopolyBoard.display_name(target), -moved]
		MonopolyRules.Act.BAIL:
			return "%s pagou %d de fiança e saiu da cadeia." % [who, -moved]
		MonopolyRules.Act.USE_CARD:
			return "%s usou a carta de saída livre." % who

	if moved == 0 and others.is_empty():
		return ""

	# Sobrou o dinheiro que muda de mão sem um botão: aluguel, imposto, carta.
	if others.size() == 1:
		var other := _player_label(others[0])
		if moved < 0:
			# O valor vem do bolso de **quem recebeu**, e não do de quem pagou: quem
			# pagou pode ter cruzado a Partida no mesmo lance, e aí o saldo dele é a
			# soma de duas coisas. O do dono mexeu por um motivo só.
			var landed := MonopolyRules.position_of(_state, actor)
			if MonopolyBoard.is_deed(landed) and MonopolyRules.owner_of(_state, landed) == others[0]:
				return "%s pagou %d de aluguel a %s por %s." % [
					who, others_total, other, MonopolyBoard.display_name(landed)
				]
			return "%s pagou %d a %s." % [who, others_total, other]
		return "%s recebeu %d de %s." % [who, others_total, other]

	if others.size() > 1:
		if moved < 0:
			return "%s pagou %d a cada jogador — %d ao todo." % [
				who, others_total / others.size(), others_total
			]
		return "%s recebeu %d de cada jogador — %d ao todo." % [
			who, others_total / others.size(), others_total
		]

	# Ninguém do outro lado: o banco.
	if moved < 0:
		var standing := MonopolyRules.position_of(_state, actor)
		if MonopolyBoard.kind_of(standing) == MonopolyBoard.Tile.TAX:
			# O nome da casa **é** o imposto ("Imposto de Renda"), então dizer "de
			# imposto em Imposto de Renda" é dizer duas vezes.
			return "%s pagou %d de %s." % [who, -moved, MonopolyBoard.display_name(standing)]
		return "%s pagou %d ao banco." % [who, -moved]
	return "%s recebeu %d do banco." % [who, moved]


## O que a fase seguinte faz sozinha.
##
## A carta é tirada sem botão: o jogador não escolhe qual carta sai, e apresentar
## isso como escolha é pedir um toque cuja única resposta possível é "ok". É a
## mesma decisão da rolagem sem lance possível no Ludo.
## Em rede, quem tira a carta é **um aparelho só**: o de quem está na fase de
## tirar. Se cada um sorteasse ao receber o lance de quem pisou na casa de Sorte,
## os quatro veriam cartas diferentes — e a carta é o segundo acaso do jogo,
## exatamente como o dado.
func _after_move() -> void:
	if MonopolyRules.phase_of(_state) != MonopolyRules.Phase.DRAW:
		return
	if not _drives(MonopolyRules.actor_of(_state)):
		return
	await get_tree().create_timer(DRAW_DELAY).timeout
	if not is_inside_tree():
		return
	var which := MonopolyBoard.CHEST if MonopolyBoard.kind_of(
		MonopolyRules.position_of(_state, MonopolyRules.turn_of(_state))
	) == MonopolyBoard.Tile.CHEST else MonopolyBoard.CHANCE
	# Entre as cartas que **podem** sair: a de saída livre some do baralho
	# enquanto está na mão de alguém, e sortear um índice cru pescaria uma carta
	# que as regras vão recusar.
	var choices: Array[Move] = _rules.generate_moves(_state)
	if choices.is_empty():
		return
	var pick: Move = choices[randi() % choices.size()]
	await _reveal_card(which, pick.path[2])
	if not is_inside_tree():
		return
	await _play(pick.path)


## Vira a carta na frente do jogador e espera **o toque** que a fecha.
##
## A espera não é enfeite, e não dá para tirá-la: `_play` aplica o efeito e
## `_report` escreve "fulano pagou 200" no aviso do topo. Sem a carta na frente e
## sem a pausa, o jogador vê só a consequência — a causa passou entre dois
## quadros. Foi por isso que a carta deixou de ser uma linha no mesmo aviso: um
## canal só para as duas coisas é um apagando o outro.
##
## Sem relógio: a partida espera o tempo que o jogador levar para ler. Ver
## [monopoly_card.gd] para o que isso custa numa mesa em rede.
func _reveal_card(which: int, index: int) -> void:
	Sound.play(Sound.Cue.CARD)
	_card.show_card(which, index)
	await _card.dismissed


# --- estado -------------------------------------------------------------------


func _refresh() -> void:
	if _match_status != null:
		_match_status.rounds = _rules.rounds_played(_state)
	var turn := MonopolyRules.turn_of(_state)
	var actor := MonopolyRules.actor_of(_state)
	var champion := _rules.winner(_state)
	var live := champion < 0 and not _abandoned
	_board.state = _state
	# A câmera segue o peão **da vez**, e não o de quem decide: numa proposta de
	# troca quem responde é o outro, e a câmera saltando para o peão dele contaria
	# uma caminhada que não aconteceu.
	_board.follow = turn
	if _board.focused < 0:
		_board.focused = MonopolyRules.position_of(_state, turn)

	_panel.state = _state
	# Em rede o painel é **seu**, sempre: é dele que se constrói e se hipoteca, e
	# um painel que mostrasse as propriedades de quem está jogando ofereceria
	# botões que este aparelho não pode apertar.
	_panel.viewer = Game.local_seat if Game.mode == Game.Mode.ONLINE else turn
	_panel.acting = live and _my_turn() and not _busy
	if _panel.tile < 0:
		_panel.tile = _board.focused
	_panel.refresh()

	for player in _cards.size():
		_cards[player].show_player(_state, player, player == turn, _player_label(player))
	if _buttons != null:
		_update_bar()
	if _trade_button != null:
		_trade_button.visible = (
			live and _my_turn() and not _busy
			and MonopolyRules.can_offer(_state, actor)
		)

	if champion >= 0:
		_finish(champion)
		return

	# A proposta na mesa abre a tela sozinha para quem tem de responder. Esperar um
	# toque num botão seria esperar por um toque cuja única função é revelar uma
	# pergunta que já foi feita.
	if MonopolyRules.phase_of(_state) == MonopolyRules.Phase.TRADE:
		if _my_turn() and not _busy and not _trade_layer.visible:
			_open_trade()
	elif _trade_layer.visible and _trade.is_reviewing():
		# A proposta saiu da mesa sem ser por aqui — o outro aparelho respondeu, ou
		# uma reconexão trouxe a partida adiante.
		_close_trade()

	_drain_incoming()

	# A vez da máquina começa sozinha, e só depois de a tela já estar mostrando de
	# quem ela é.
	if (
		_is_bot(actor) and _drives_bots() and not _bot_pending
		and not _busy and not _link_down and not _abandoned
	):
		_run_bot()


## Como o jogador é chamado na coluna. O nome guardado no aparelho para quem
## está com ele na mão; os outros pelo número do assento, que é o que se sabe
## deles antes de a rede trazer nome.
##
## Sem `has_name()`: `Prefs.player_name()` já devolve o nome padrão para quem
## nunca escolheu um, e é isso que o xadrez e a batalha naval mostram. Perguntar
## antes fazia o mesmo jogador aparecer como "Guidon" numa tela e "Jogador 1" na
## outra, no mesmo aparelho.
func _player_label(player: int) -> String:
	if _is_bot(player):
		return "Bot %d" % (player + 1)
	if player == Game.local_seat:
		return Prefs.player_name()
	# Em rede o nome do outro veio no aperto de mão. Faltando — versão antiga do
	# outro lado, ou reconexão que caiu antes de apresentá-lo —, o número do
	# assento continua respondendo.
	var theirs := Net.name_of(player) if Game.mode == Game.Mode.ONLINE else ""
	return theirs if not theirs.is_empty() else "Jogador %d" % (player + 1)


func _update_recenter() -> void:
	if _recenter != null:
		_recenter.visible = _board.free


func _on_tile_tapped(tile: int) -> void:
	if tile != _board.focused:
		Sound.play(Sound.Cue.TAP)
	_board.focused = tile
	_panel.tile = tile
	_panel.listing = false
	_panel.listing_of = -1
	_panel.refresh()


## Uma faixa da coluna foi tocada: o painel abre as propriedades daquele jogador.
##
## Vale para **qualquer** assento, inclusive os bots e o próprio. "O que o outro
## tem" é a pergunta que decide se uma troca vale a pena, e até aqui a resposta era
## um número de escrituras na coluna — que não diz se são um grupo fechado ou três
## casas soltas de cidades diferentes.
##
## Tocar de novo na mesma faixa fecha, porque o gesto que abriu é o que se tenta
## para desfazer.
func _on_player_chosen(player: int) -> void:
	Sound.play(Sound.Cue.TAP)
	if _panel.listing and _panel.listing_of == player:
		_panel.listing = false
		_panel.listing_of = -1
	else:
		_panel.listing = true
		_panel.listing_of = player
	_panel.refresh()


## Constrói, vende, hipoteca ou resgata — se as regras disserem que dá.
##
## O painel **pede**, e quem decide é a lista de lances legais: assim a
## uniformidade de construção, a hipoteca com o grupo em obras e o caixa curto
## são conferidos num lugar só, o mesmo que a rede e o bot consultam. O botão da
## tela não repete nenhuma dessas regras.
func _on_action(action: int, tile: int) -> void:
	_try(action, tile)


# --- troca --------------------------------------------------------------------


## Abre a mesa de troca no modo que a fase pede: montar, ou responder.
func _open_trade() -> void:
	if _busy or _abandoned or not _my_turn():
		return
	var actor := MonopolyRules.actor_of(_state)
	if MonopolyRules.phase_of(_state) == MonopolyRules.Phase.TRADE:
		_trade.review(_state)
	elif MonopolyRules.can_offer(_state, actor):
		_trade.compose(_state, actor)
	else:
		return
	_trade_layer.visible = true


func _close_trade() -> void:
	if _trade_layer != null:
		_trade_layer.visible = false


func _on_trade_proposed(path: PackedInt32Array) -> void:
	_close_trade()
	if not await _play(path):
		_banner.show_message("As regras não permitem essa troca.", Banner.Kind.ALERT)


func _on_trade_answered(accepted: bool) -> void:
	_close_trade()
	await _play(PackedInt32Array([
		MonopolyRules.Act.ACCEPT if accepted else MonopolyRules.Act.REJECT
	]))


# --- rede ---------------------------------------------------------------------


## Lance de outro aparelho, enfileirado antes de ser aplicado.
##
## A fila existe porque um turno aqui dura segundos de animação — dado girando,
## peão andando — e nesse tempo o aparelho de quem joga em seguida já pode ter
## mandado o dele. Aplicar direto o descartaria, e um lance descartado é uma
## partida que diverge em silêncio, que é o pior fim possível para isto.
func _on_remote_move(data: Dictionary) -> void:
	if _abandoned:
		return
	_incoming.append({
		"n": int(data.get("n", -1)),
		"p": PackedInt32Array(data.get("p", [])),
		"seat": int(data.get("seat", -1)),
	})
	_drain_incoming()


## Quem tem o direito de mandar o lance deste jogador.
##
## Ele mesmo, se for humano; o aparelho que joga pelas máquinas, se não for. A
## legalidade do lance **não** responde isso: um lance legal para o jogador da vez
## é legal olhando só o tabuleiro, venha ele de quem vier — e sem esta conferência
## qualquer assento da mesa joga a vez de qualquer outro.
##
## Em Metrópole ela vale dobrado por causa da troca: com uma proposta na mesa
## quem decide é o destinatário, e sem conferir o remetente quem propôs manda o
## próprio "aceito".
func _sender_for(player: int) -> int:
	return Net.bot_driver() if _is_bot(player) else player


## Esvazia a fila, um lance por vez, esperando cada animação terminar.
func _drain_incoming() -> void:
	if _draining or _busy or _abandoned or _incoming.is_empty():
		return
	_draining = true
	while not _incoming.is_empty() and not _abandoned and is_inside_tree():
		var entry: Dictionary = _incoming.pop_front()
		# Conferido na hora de aplicar, e não na de receber: uma reconexão reenvia
		# o que o outro lado não sabe que chegou, e a fila pode ter andado desde
		# então.
		var index := int(entry["n"])
		if index >= 0 and index < _state.ply:
			continue
		# O remetente é conferido **na hora de aplicar**, e não na de receber: a
		# fila pode ter andado desde então, e quem tinha o direito de jogar mudou
		# junto com a vez.
		var sender := int(entry["seat"])
		var allowed := _sender_for(MonopolyRules.actor_of(_state))
		if sender != allowed:
			push_warning(
				"Lance do assento %d recusado: a vez é de quem o assento %d joga."
				% [sender, allowed]
			)
			continue
		var path: PackedInt32Array = entry["p"]
		# Os dados e a carta vêm dentro do lance e são aceitos — são acaso, não há
		# como conferir. Todo o resto passa pelo mesmo `validate` dos lances daqui.
		if not await _play(path, true):
			push_warning("Lance de rede recusado pelas regras locais: %s" % [path])
	_draining = false


## Reconexão: os dois lados trocam o histórico e quem estiver atrás repete a
## diferença. Como os dois acasos viajam dentro do lance, repetir a lista devolve
## exatamente a mesma posição — sem isso, nenhuma partida de dado sobreviveria a
## uma queda.
func _apply_sync(moves: Array, _clocks: Array) -> void:
	if moves.size() <= _state.ply:
		return
	var rebuilt := _rules.initial_state()
	for data in moves:
		var move := Move.from_dict(data)
		var checked := _rules.validate(rebuilt, move.path)
		if checked == null:
			push_warning("Histórico recebido não bate com as regras; ignorado.")
			return
		_rules.apply_move(rebuilt, checked)

	_state = rebuilt
	_busy = false
	_busy_text = ""
	_incoming.clear()
	_close_trade()
	# A carta na frente é de uma partida que avançou sem ela; o efeito dela já está
	# no histórico que acabou de chegar.
	_card.close()
	# O foco é refeito do zero: a casa que estava aberta era de uma partida que
	# avançou vários lances desde então.
	_board.focused = -1
	_panel.tile = -1
	_panel.listing = false
	_refresh()


func _on_link_lost() -> void:
	_link_down = true
	_close_trade()
	_refresh()


func _on_link_restored() -> void:
	_link_down = false
	Net.send_sync(_state.history, [])
	_refresh()


func _on_opponent_left() -> void:
	_abandoned = true
	_close_trade()
	_result.show_abandoned("Um dos jogadores saiu da mesa.")
	_refresh()


## Um jogador saiu de uma mesa de mais de dois: a cadeira dele vira máquina e a
## partida continua.
##
## Encerrar seria o que `_on_opponent_left` faz, e numa mesa de seis isso é o 4G
## de uma pessoa acabando o jogo das outras cinco. A cadeira já tem um jogador
## pronto — é o mesmo bot da sala que não enche.
##
## O link volta junto: a ausência tinha congelado a mesa esperando uma volta que
## não veio.
func _on_seat_left(seat: int) -> void:
	if _abandoned:
		return
	# O nome sai **antes** da lista de bots ser atualizada: depois dela o assento
	# já é máquina, e o aviso diria "Bot 3 saiu".
	var who := _player_label(seat)
	_bot_seats = Net.bot_seats
	_link_down = false
	_close_trade()
	_banner.show_message("%s saiu. Um bot joga até a volta." % who, Banner.Kind.ALERT)
	_refresh()


## A cadeira deixou de ser máquina: quem tinha caído voltou, ou alguém sentou numa
## cadeira que a mesa começou sem. A lista já chegou atualizada, então o rótulo
## lido aqui é o de gente, e não "Bot".
func _on_seat_returned(seat: int) -> void:
	if _abandoned:
		return
	_bot_seats = Net.bot_seats
	_banner.show_message("%s assumiu o lugar do bot." % _player_label(seat), Banner.Kind.INFO)
	_refresh()


# --- fim ----------------------------------------------------------------------


func _finish(champion: int) -> void:
	if _result.visible:
		return
	Sound.play(Sound.Cue.WIN)
	_close_trade()
	# Revanche é conversa de dois, e aqui a mesa tem até seis: quem quer jogar de
	# novo em rede abre outra sala. O botão sai em vez de prometer o que não há —
	# mesma decisão do Ludo.
	_result.show_winner(
		_state, champion, _player_label, Game.mode != Game.Mode.ONLINE
	)


func _restart() -> void:
	Game.restart_match()
	_match_status.started_at = Game.match_started_at
	_state = _rules.initial_state()
	_busy = false
	_busy_text = ""
	_bot_pending = false
	_incoming.clear()
	_result.visible = false
	_close_trade()
	_card.close()
	_board.focused = -1
	_panel.tile = -1
	_panel.listing = false
	_refresh()


## A mesa de troca é a única camada do app que o gesto de voltar **não** fecha
## sempre, e a diferença é de quem está esperando.
##
## Montando uma proposta, o gesto é o "Cancelar": nada saiu, ninguém espera, e
## desistir não muda a partida de ninguém.
##
## Respondendo a uma, não. Enquanto a proposta está na mesa a partida inteira
## está parada esperando a resposta deste aparelho — é a única fase em que
## `actor_of` não é `turn_of` —, e fechar a tela por gesto tiraria da frente os
## dois únicos botões que destravam os outros jogadores. O gesto não faz nada, e
## é a resposta certa: a saída daqui é "Aceitar" ou "Recusar".
func go_back() -> void:
	if _trade_layer != null and _trade_layer.visible:
		if not _trade.is_reviewing():
			_close_trade()
		return
	_leave()


func _leave() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
