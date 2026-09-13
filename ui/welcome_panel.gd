class_name WelcomePanel
extends Control

## A primeira tela que o app mostra na primeira vez: quem somos, e como você quer
## ser chamado.
##
## ## Por que uma pergunta, e só uma
##
## O nome já tinha um lugar — a engrenagem na tela inicial — e quase ninguém
## chegava lá. O resultado era uma lista de salas públicas abertas por "Guidon",
## "Guidon" e "Guidon", e cartões de jogador com o mesmo nome dos dois lados do
## tabuleiro. O padrão existe para o app funcionar sem a pergunta; ele não existe
## para ser a resposta de todo mundo.
##
## Perguntar na abertura funciona porque a resposta é **usada logo**: o primeiro
## lugar em que o nome aparece é a sala que este jogador vai abrir ou entrar. Uma
## abertura que perguntasse três coisas — nome, som, tema — seria um formulário
## antes do jogo, e o preço de cada pergunta a mais é pago por todas as outras.
##
## ## Ela não prende
##
## "Bora jogar" segue com o que estiver no campo, inclusive vazio: quem não quer
## escolher agora fica com o padrão e troca depois nos ajustes. Um modal sem
## saída transforma a primeira impressão do app numa exigência, e o nome não vale
## isso — ele é um apelido de tabuleiro, não um cadastro.
##
## ## Ela não volta
##
## Quem passou por aqui não vê de novo, mesmo tendo ficado com o padrão. É por
## isso que a marca é `Prefs.welcomed()` e não `Prefs.has_name()`: guardado pelo
## nome, quem decidiu ficar com o padrão receberia a mesma boas-vindas em toda
## abertura, e uma boas-vindas que reaparece vira cobrança.

## O jogador seguiu. O nome já foi gravado quando este sinal sai — quem escuta só
## precisa continuar o que estava fazendo.
signal finished

const SHADE := 0.82
const PANEL_WIDTH := 320


var _edit: LineEdit = null


## Deve ser mostrado agora? Uma pergunta só, num lugar só: a tela inicial não
## refaz a conta, e o dia em que a condição mudar ela muda aqui.
static func pending() -> bool:
	return not Prefs.welcomed()


## As âncoras são escritas por quem monta, **antes** do `add_child` — mesma
## armadilha do painel de fim de Metrópole: escritas aqui dentro, o nó já entrou
## na árvore e o layout não volta para recalcular.
func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(AppTheme.BACKGROUND, SHADE)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Pára o toque: a lista de jogos está viva atrás disto, e um toque que
	# atravessasse abriria uma partida por baixo da tela de boas-vindas.
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE, AppTheme.RADIUS_LARGE, AppTheme.BORDER, 1
	))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Oi! Como te chamamos?"
	title.theme_type_variation = &"Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	# Uma linha, e ela diz **onde** o nome aparece — não "escolha um nome".
	#
	# A diferença é entre um campo a preencher e uma decisão com consequência
	# visível, e ela cabe em oito palavras. A primeira versão gastava um parágrafo
	# apresentando o app antes de perguntar: quem abriu já sabe o que baixou, e o
	# texto virava uma coisa a atravessar para chegar ao campo.
	var blurb := Label.new()
	blurb.text = "É assim que os outros jogadores vão te ver."
	blurb.theme_type_variation = &"Subtitle"
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(blurb)

	_edit = LineEdit.new()
	_edit.max_length = Prefs.NAME_LIMIT
	# Vazio com o padrão só no placeholder, como na tela de ajustes: um "Guidon"
	# dentro do campo parece nome digitado, e ninguém troca o que já parece
	# escolhido.
	_edit.placeholder_text = Prefs.DEFAULT_NAME
	_edit.text_submitted.connect(func(_text: String): finish())
	column.add_child(_edit)

	var start := Button.new()
	start.text = "Bora jogar"
	start.theme_type_variation = &"PrimaryButton"
	start.custom_minimum_size.y = 48
	start.pressed.connect(finish)
	column.add_child(start)


## O foco vai para o campo, mas só depois de o painel estar desenhado: pedir foco
## a um `LineEdit` que ainda não tem retângulo não abre o teclado do Android.
func open() -> void:
	await get_tree().process_frame
	if is_inside_tree():
		_edit.grab_focus()


## Grava o que estiver no campo e sai. Pública porque o botão de voltar do
## sistema entra por aqui — e ele tem de fazer exatamente o mesmo que o botão,
## e não um segundo caminho de saída que esqueça de gravar alguma coisa.
func finish() -> void:
	# Vazio é uma resposta: `set_player_name("")` apaga a chave e devolve o
	# padrão, que é exatamente o que "não quero escolher agora" significa.
	Prefs.set_player_name(_edit.text)
	Prefs.set_welcomed()
	Sound.play(Sound.Cue.TAP)
	finished.emit()
	queue_free()
