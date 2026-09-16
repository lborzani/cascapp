class_name MonopolyCardPopup
extends Control

## A carta de Sorte ou Cofre, virada na frente do jogador.
##
## Ela existe porque o aviso do topo não dava conta do segundo acaso do jogo. O
## dado tem dois cubos girando no meio da tela; a carta tinha uma linha de texto
## no mesmo lugar onde a tela escreve "fulano pagou 200" — o mesmo canal para a
## causa e para a consequência, e um substituindo o outro em dois segundos. O
## jogador via o prejuízo sem nunca ver o motivo.
##
## Aqui a carta tem **forma de carta**: sobe de baixo, cobre o resto, e tem três
## alturas de leitura — o nome, o que ela faz, e uma frase de por que aconteceu.
## As duas primeiras vêm das regras; a terceira não vale nada para a partida e é
## a única razão de alguém lembrar de uma carta específica depois.
##
## ## Ela sobe, e não aparece
##
## Um painel que surge no lugar é indistinguível de um erro de desenho. Vindo de
## baixo, o movimento **conta que uma carta foi tirada do baralho** — e é a mesma
## direção do gesto de virar uma carta na mesa. Duzentos e poucos milissegundos:
## curto o bastante para não atrasar o turno, longo o bastante para o olho seguir.
##
## ## Quem a fecha é o dedo, e só ele
##
## Não há relógio. A carta fica na frente até alguém tocar, e isso vale também
## para a carta que um bot tirou — quem está olhando decide quando já leu.
##
## Houve um fechamento por tempo aqui, e ele estava errado pelo motivo de sempre:
## o tempo de leitura de outra pessoa não é um número que este arquivo saiba. Dois
## segundos é uma eternidade para quem já conhece as 32 cartas e é pouco para quem
## está lendo "Reforma geral" pela primeira vez com o preço na ponta. Um toque
## responde a pergunta certa — "você terminou?" — em vez de adivinhá-la.
##
## O preço está anotado: enquanto a carta estiver aberta, **a partida inteira
## espera**. Numa mesa em rede é o aparelho de quem tirou que segura os outros, e
## na vez de um bot é este aparelho que precisa de um toque para a partida seguir.

## A carta saiu da frente — por toque ou por tempo. Quem mostrou espera por isto
## antes de aplicar o efeito.
signal dismissed

const SHADE := 0.62
## Subida e descida. A descida é mais curta: a carta já foi lida, e a espera aqui
## é espera pura.
const RISE := 0.24
const FALL := 0.16
## De quanto abaixo do lugar ela começa. Mais que a altura da carta, para ela
## entrar de fora da tela e não crescer do meio dela.
const RISE_DISTANCE := 260.0

## Largura da carta. Fixa, e estreita: proporção de carta de baralho em pé é o
## que faz o objeto ser lido como carta antes de o texto ser lido como texto.
const CARD_WIDTH := 300

var _slide: Control = null
var _shade: ColorRect = null
var _panel: PanelContainer = null
var _band: ColorRect = null
var _deck: Label = null
var _title: Label = null
var _effect: Label = null
var _flavor: Label = null
var _hint: Label = null
## A carta terminou de subir. Antes disso o toque não fecha: um dedo que já
## estava descendo quando ela apareceu fecharia a carta sem ninguém a ter visto.
var _settled := false
## A saída já começou. Sem isto, um toque durante a descida dispara um segundo
## `dismissed` — e quem espera por ele aplica o efeito da carta duas vezes.
var _closing := false


## Como a camada de resultado: o `PRESET_FULL_RECT` é escrito por quem monta,
## antes do `add_child`. Escrito aqui dentro o nó já está na árvore e escondido, e
## o layout não volta para recalcular.
func _ready() -> void:
	visible = false

	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, SHADE)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Pára o toque, e é ele que também fecha a carta: o tabuleiro atrás continua
	# vivo, e um toque atravessando daqui giraria a câmera de uma partida parada.
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.gui_input.connect(_on_shade_input)
	add_child(_shade)

	# O que desliza é esta camada, e não a carta.
	#
	# A carta está dentro de um `CenterContainer`, e um container **escreve** a
	# posição dos filhos a cada quadro — animar a posição dela seria uma disputa
	# com o layout, que ganha. A camada é filha direta de um `Control` comum, onde
	# a posição é de quem a escreveu.
	_slide = Control.new()
	_slide.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slide)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slide.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_deck = Label.new()
	_deck.add_theme_font_size_override("font_size", 11)
	_deck.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_deck)

	_title = Label.new()
	_title.add_theme_font_override("font", AppTheme.font(700))
	_title.add_theme_font_size_override("font_size", 21)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)

	# A faixa da cor do baralho, entre o nome e a regra. É o que dá à carta a
	# silhueta impressa do tampo — a mesma faixa que separa o topo de cada casa.
	_band = ColorRect.new()
	_band.custom_minimum_size.y = 3
	column.add_child(_band)

	_effect = Label.new()
	_effect.add_theme_font_size_override("font_size", 14)
	_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_effect)

	_flavor = Label.new()
	_flavor.add_theme_font_size_override("font_size", 12)
	_flavor.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_flavor)

	# A única saída daqui, e por isso ele não é tão apagado quanto uma legenda
	# comum: enquanto a carta estiver na frente a partida está parada, e um jogador
	# que não perceba que o toque é com ele fica esperando a tela se resolver
	# sozinha — que era o que acontecia quando havia relógio.
	_hint = Label.new()
	_hint.text = "Toque para continuar"
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)

	# A carta inteira deixa o toque passar.
	#
	# Quem fecha é o fundo escuro, e enquanto isto não existia o toque **na carta**
	# não fazia nada: só o de fora dela. O `PanelContainer` já estava marcado para
	# ignorar, mas os containers de dentro não — e um `MarginContainer` engolindo o
	# evento é a coisa mais silenciosa possível. Do ponto de vista de quem joga, a
	# carta é o alvo óbvio; o fundo é que é o "fora".
	_let_touch_through(_slide)


## Vira a carta na frente de quem está olhando.
##
## `which` é `MonopolyBoard.CHANCE` ou `MonopolyBoard.CHEST`; `index` é a posição
## dela no baralho, que é o mesmo número que viaja dentro do lance.
##
## Quem chama espera por [signal dismissed], e não por esta chamada: ela termina
## quando a carta acaba de **subir**, e o efeito só pode valer quando ela sai da
## frente.
func show_card(which: int, index: int) -> void:
	var card := MonopolyBoard.card(which, index)
	# Latão para Sorte, verde para Cofre: são as duas cores que o tampo já usa
	# nessas casas, e a carta chegando na cor da casa em que o peão parou é o que
	# liga uma coisa à outra sem precisar dizer.
	var tint := AppTheme.ACCENT if which == MonopolyBoard.CHANCE else AppTheme.SUCCESS
	_deck.text = "SORTE" if which == MonopolyBoard.CHANCE else "COFRE"
	_deck.add_theme_color_override("font_color", tint)
	_band.color = tint
	_title.text = str(card.get("title", ""))
	_effect.text = str(card.get("text", ""))
	_flavor.text = str(card.get("flavor", ""))
	_panel.add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE, AppTheme.RADIUS_LARGE, tint, 2
	))

	_settled = false
	_closing = false
	visible = true
	_shade.modulate.a = 0.0
	_slide.position.y = RISE_DISTANCE
	var rise := create_tween()
	rise.set_parallel(true)
	rise.tween_property(_shade, "modulate:a", 1.0, RISE)
	rise.tween_property(_slide, "position:y", 0.0, RISE).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	await rise.finished
	if not is_inside_tree():
		return
	_settled = true


## Fecha a carta e avisa.
##
## Chamar duas vezes não faz nada na segunda. O dedo não é a única porta daqui —
## uma reconexão e uma partida nova também fecham a carta —, e dois `dismissed`
## para a mesma carta aplicariam o efeito dela duas vezes.
func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_settled = false
	var fall := create_tween()
	fall.set_parallel(true)
	fall.tween_property(_shade, "modulate:a", 0.0, FALL)
	fall.tween_property(_slide, "position:y", RISE_DISTANCE, FALL).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN)
	await fall.finished
	visible = false
	dismissed.emit()


## Marca a subárvore inteira para ignorar o toque.
##
## Recursivo, e não uma lista de nós escrita à mão: a carta tem sete controles
## hoje e vai ter outros, e o que for acrescentado sem a marca volta a abrir um
## buraco onde o toque morre.
static func _let_touch_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_let_touch_through(child)


func _on_shade_input(event: InputEvent) -> void:
	if not _settled:
		return
	# Por [Tap]: ver o cabeçalho dele.
	if Tap.began(event):
		close()
