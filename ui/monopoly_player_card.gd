class_name MonopolyPlayerCard
extends PanelContainer

## Uma faixa da coluna da esquerda: um jogador, o dinheiro dele e o que ele tem.
##
## A coluna é a resposta para "como está a partida". Ela fica **sempre visível**,
## e é por isso que a informação dela é curta: nome, caixa, quantas escrituras.
## Detalhe de propriedade é pergunta de painel, não de coluna — quem olha para cá
## quer comparar seis jogadores de relance, e seis blocos de seis linhas não se
## comparam de relance.
##
## A cor é a mesma que tinge o peão no tabuleiro ([monopoly_face.gd]), e é o único
## elo entre a coluna e o que se vê em cima do tampo: sem ela, achar o próprio
## peão exigiria contar assentos.

## A faixa foi tocada: quem olha quer ver as propriedades deste jogador.
##
## O cartão não sabe o que fazer com isso — quem abre o painel é a cena. Ele só
## diz que foi escolhido, como o cartão de jogo do menu.
signal chosen(player: int)

## Faixa vertical de cor na borda esquerda. Vertical e não um ponto: ela precisa
## sobreviver ao cartão inteiro ficando esmaecido quando não é a vez.
const STRIPE := 5

## Corpos e folgas nos dois tamanhos: mesa curta e mesa cheia.
##
## Seis faixas não cabem nos 416 de altura da base deitada no tamanho normal —
## cada cartão pede uns 55 pixels de conteúdo, e seis mais os botões do rodapé
## passam de 400. Encolher os corpos e as margens resolve sem tirar informação de
## ninguém, que é o que uma rolagem faria: a coluna existe justamente para os
## jogadores serem **comparados de relance**, e o que sai da tela não se compara.
const SIZES := {
	false: {"name": 12, "cash": 15, "detail": 10, "pad": 5},
	true: {"name": 11, "cash": 13, "detail": 9, "pad": 2},
}

var _stripe: ColorRect = null
var _name: Label = null
var _cash: Label = null
var _detail: Label = null
var _margin: MarginContainer = null
## Assento que este cartão desenha. Guardado porque o toque precisa dizer **de
## quem** ele foi, e o cartão só descobre isso quando é preenchido.
var _player := -1


func _ready() -> void:
	# O cartão inteiro é o alvo, e por isso os containers de dentro deixam o toque
	# passar: um `MarginContainer` com o filtro padrão recebe o evento antes desta
	# faixa e o engole sem deixar rastro.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_margin = MarginContainer.new()
	_margin.add_theme_constant_override("margin_left", 7)
	_margin.add_theme_constant_override("margin_right", 7)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	var margin := _margin

	# A faixa vive **dentro** do layout, como primeira coluna de um `HBox`.
	#
	# A primeira versão a deixava solta e ancorada à esquerda, e ela cobriu o
	# cartão inteiro: `PanelContainer` estica todos os filhos para preencher, e
	# ignora âncora. Um filho solto ali não é um filho posicionado — é um filho
	# em cima de todos os outros.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)

	_stripe = ColorRect.new()
	_stripe.custom_minimum_size.x = STRIPE
	_stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_stripe)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(column)

	_name = Label.new()
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_name)

	_cash = Label.new()
	# Em mono, e amarelo: é o placar desta partida, e os algarismos precisam
	# alinhar entre as seis faixas para "quem tem mais" ser respondido de relance.
	_cash.add_theme_font_override("font", AppTheme.mono(600))
	column.add_child(_cash)

	_detail = Label.new()
	_detail.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	column.add_child(_detail)

	dense(false)


func _gui_input(event: InputEvent) -> void:
	# Por [Tap]: ver o cabeçalho dele. Um clique chega duas vezes.
	if Tap.began(event) and _player >= 0:
		accept_event()
		chosen.emit(_player)


## Aperta o cartão para caber numa mesa cheia.
##
## Chamado pela cena, que é quem sabe de quantos é a mesa — o cartão desenha um
## jogador e não conhece os outros. Escrito depois de `add_child` como tudo o mais
## aqui: os rótulos só existem a partir do `_ready`.
func dense(value: bool) -> void:
	var step: Dictionary = SIZES[value]
	_name.add_theme_font_size_override("font_size", int(step["name"]))
	_cash.add_theme_font_size_override("font_size", int(step["cash"]))
	_detail.add_theme_font_size_override("font_size", int(step["detail"]))
	_margin.add_theme_constant_override("margin_top", int(step["pad"]))
	_margin.add_theme_constant_override("margin_bottom", int(step["pad"]))


## Preenche a faixa a partir do estado. Recebe tudo pronto em vez de guardar uma
## referência ao `MatchState`: o cartão não sabe as regras do jogo, só desenha o
## que lhe dizem, e é o que permite a mesma faixa servir a um bot, a um humano e
## a quem já quebrou.
func show_player(
	state: MatchState, player: int, is_turn: bool, label: String
) -> void:
	_player = player
	var color: Color = MonopolyFace.PLAYER_COLORS[player % MonopolyFace.PLAYER_COLORS.size()]
	var out := MonopolyRules.is_out(state, player)

	_stripe.color = Color(color, 0.35 if out else 1.0)
	# Fundo preenchido só na vez. Seis cartões acesos competiriam entre si, e a
	# pergunta que a coluna responde primeiro é "de quem é a vez".
	var style: StyleBox = AppTheme.box(Color(color, 0.20), AppTheme.RADIUS, Color(color, 0.9), 2)
	if not is_turn:
		# Quem espera fica em contorno de giz, como as etiquetas dos outros jogos.
		style = AppTheme.dashed(Color(AppTheme.SURFACE, 0.72), AppTheme.LINE_SOFT)
	# As folgas do tema saem.
	#
	# `AppTheme.box` embute 18 de lado e 14 em cima e embaixo, e está certo: ela
	# foi escrita para painel de menu, onde o ar em volta do conteúdo é o que faz
	# a tela respirar. Numa faixa de coluna esses 28 verticais são mais altura que
	# o próprio conteúdo — seis faixas passavam dos 416 da base deitada e a última
	# saía da tela junto com os botões do rodapé. Os 36 horizontais eram o motivo
	# de a coluna nascer mais larga que os 136 que ela pede.
	#
	# Quem dá a folga aqui é o `MarginContainer` de dentro, que é o que o modo
	# apertado ajusta.
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)

	_name.text = label
	_name.add_theme_color_override(
		"font_color", AppTheme.TEXT_DIM if out else AppTheme.TEXT
	)

	if out:
		_cash.text = "quebrou"
		_cash.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		_detail.text = ""
		return

	_cash.text = "M %d" % MonopolyRules.cash_of(state, player)
	_cash.add_theme_color_override(
		"font_color", AppTheme.ACCENT if is_turn else Color(AppTheme.ACCENT, 0.7)
	)

	var deeds := MonopolyRules.deeds_of(state, player).size()
	var parts := PackedStringArray([
		"%d escritura%s" % [deeds, "" if deeds == 1 else "s"]
	])
	if MonopolyRules.in_jail(state, player):
		parts.append("na cadeia")
	# A carta de saída livre é a única coisa que se **guarda** neste jogo, e até
	# aqui ela não aparecia em lugar nenhum: o jogador tirava a carta, via o texto
	# dela uma vez, e depois tinha de lembrar que a tinha. Pior, o botão "Usar
	# saída livre" só existe na fase da cadeia — então a única prova de que ela
	# estava na mão aparecia depois de já ser tarde para contar com ela.
	var kept := MonopolyRules.jail_cards_of(state, player)
	if kept > 0:
		parts.append("%d saída livre" % kept if kept == 1 else "%d saídas livres" % kept)
	_detail.text = " · ".join(parts)
