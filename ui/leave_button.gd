class_name LeaveButton
extends Button

## O botão de sair da partida: quadrado, com um ícone, em vermelho de aviso.
##
## ## Por que ele encolheu
##
## "Sair da partida" é uma linha inteira de texto num rodapé, e ela custava uma
## faixa de tela em todos os jogos — numa tela deitada de celular, essa faixa vem
## da mesa ou da mão, que é onde a partida acontece. E o texto pagava por uma ação
## que ninguém procura: sair é o toque menos frequente de qualquer partida.
##
## Um quadrado de 44 px continua sendo alvo confortável de polegar (é o mínimo
## recomendado, e o mesmo que os botões antigos já tinham de altura) e devolve a
## largura inteira para o resto.
##
## ## O que se perde, e o que compensa
##
## Um ícone sem rótulo é sempre uma adivinhação a mais que uma palavra. Duas
## coisas seguram o significado aqui:
##
## - **o desenho é uma porta com uma seta saindo**, que é o ícone de sair mais
##   difundido que existe. Não é uma metáfora inventada para este app;
## - **a cor é o vermelho de perigo do tema**, que no resto do app já quer dizer
##   "isto custa caro" — desistir, desfazer, sair.
##
## E o rótulo não some de verdade: ele vira `tooltip_text`, que é o que um leitor
## de tela anuncia. Um ícone mudo seria um botão que só existe para quem enxerga.
##
## Vazado e não preenchido: preenchido, o vermelho vira a coisa mais forte de uma
## tela cuja ação principal é jogar uma carta ou mover uma peça. O contorno diz
## "está aqui se você precisar" em vez de "faça isto".

## O jogador confirmou que quer sair. **Este** é o sinal a escutar, e não
## `pressed`: o toque no botão abre a pergunta, e quem sai é a resposta.
##
## Ligar em `pressed` continua compilando e sai da partida sem perguntar nada, que
## é justamente o bug que este componente existe para não ter. Vale conferir a
## ligação ao trocar um botão antigo por este.
signal confirmed

const SIDE := 44.0
## Fração do lado ocupada pelo desenho.
const GLYPH := 0.46


func _init() -> void:
	custom_minimum_size = Vector2(SIDE, SIDE)
	# Canto de baixo à esquerda: é onde o polegar da mão que **não** joga alcança
	# num aparelho deitado, e é o canto mais longe da mão de cartas — que é onde
	# todo o resto do toque acontece. Sair não pode ser vizinho de jogar.
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_END
	text = ""
	tooltip_text = "Sair da partida"
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	add_theme_stylebox_override("normal", _box(0.0))
	add_theme_stylebox_override("hover", _box(0.10))
	add_theme_stylebox_override("pressed", _box(0.20))
	add_theme_stylebox_override("focus", _box(0.0))
	pressed.connect(ask)


static func _box(fill: float) -> StyleBoxFlat:
	return AppTheme.box(Color(AppTheme.DANGER, fill), AppTheme.RADIUS, AppTheme.DANGER, 1)


# --- a confirmação ------------------------------------------------------------


## Pergunta antes de sair. Público porque o **gesto de voltar** do sistema entra
## por aqui também: sair pelo gesto e sair pelo botão são a mesma decisão, e uma
## delas passar sem pergunta é a pergunta não existir.
##
## Sair de uma partida é o toque mais caro da tela e o menos frequente — a
## combinação exata que pede confirmação. Errar o alvo custa a partida inteira, e
## não há como desfazer: a mesa não fica esperando.
func ask() -> void:
	if _layer != null:
		return
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Acima de tudo: o painel de fim de partida e a escolha de cor do curinga são
	# camadas irmãs, e uma pergunta que aparece atrás de outra não é uma pergunta.
	_layer.z_index = 100
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.78)
	# Para o toque e **cancela**: tocar fora de um diálogo é a saída conhecida de
	# quem abriu por engano, que é a maioria de quem abre este aqui.
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_on_shade_input)
	_layer.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := Label.new()
	title.theme_type_variation = &"Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Sair da partida?"
	column.add_child(title)

	var note := Label.new()
	note.theme_type_variation = &"Subtitle"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Você volta ao menu e deixa esta partida."
	column.add_child(note)

	# **Ficar** é a ação preenchida, e sair é a discreta.
	#
	# É o inverso do que um diálogo de confirmação costuma fazer, e de propósito: o
	# botão cheio é onde o dedo vai sem ler, e o caminho sem volta não pode ser o
	# padrão de quem não leu. Quem realmente quer sair lê duas palavras a mais.
	var stay := Button.new()
	stay.theme_type_variation = &"PrimaryButton"
	stay.custom_minimum_size = Vector2(240, 48)
	stay.text = "Continuar jogando"
	stay.pressed.connect(_dismiss)
	column.add_child(stay)

	var leave := Button.new()
	leave.theme_type_variation = &"DangerButton"
	leave.custom_minimum_size = Vector2(0, 44)
	leave.text = "Sair"
	leave.pressed.connect(_accept)
	column.add_child(leave)

	_host().add_child(_layer)


## O `Control` mais alto acima deste botão.
##
## Subir a árvore em vez de usar `get_tree().current_scene`: o mesmo componente
## roda dentro da cena da partida no app e dentro de um nó de teste no probe, e no
## segundo a cena corrente é outra — o diálogo apareceria fora da tela montada.
func _host() -> Node:
	var node: Node = self
	var best: Node = self
	while node != null:
		if node is Control:
			best = node
		node = node.get_parent()
	return best


func _on_shade_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
		_dismiss()


func _dismiss() -> void:
	if _layer == null:
		return
	_layer.queue_free()
	_layer = null


func _accept() -> void:
	_dismiss()
	confirmed.emit()


var _layer: Control = null


## Porta com seta saindo, desenhada por código como o resto do app.
##
## Três traços e um triângulo: o batente em U aberto para a direita, a haste da
## seta e a ponta. Em 20 px de desenho, qualquer detalhe a mais vira borrão — o
## que precisa sobreviver é a leitura "alguma coisa saindo de alguma coisa".
func _draw() -> void:
	var span := minf(size.x, size.y) * GLYPH
	var center := size * 0.5
	var ink := AppTheme.DANGER
	var thick := maxf(span * 0.13, 1.5)

	# O batente ocupa a metade esquerda, aberto para o lado por onde se sai.
	var half := span * 0.5
	var left := center.x - half
	var mid := center.x - half * 0.05
	draw_polyline(PackedVector2Array([
		Vector2(mid, center.y - half),
		Vector2(left, center.y - half),
		Vector2(left, center.y + half),
		Vector2(mid, center.y + half),
	]), ink, thick, true)

	# A seta atravessa a abertura, e a ponta passa da borda do batente: é o que
	# faz o desenho dizer "saindo" em vez de "entrando".
	var tip := Vector2(center.x + half * 0.95, center.y)
	draw_line(Vector2(center.x - half * 0.35, center.y), tip - Vector2(thick, 0.0), ink, thick, true)
	var head := span * 0.30
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + Vector2(-head, -head * 0.62),
		tip + Vector2(-head, head * 0.62),
	]), ink)
