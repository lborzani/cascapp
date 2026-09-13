class_name WaitingPanel
extends Control

## O que está acontecendo enquanto a sala não abre.
##
## Antes isto era uma linha de texto embaixo da lista: "Na sala: 4 de 4
## jogadores." Ela diz o número e não diz **em que partida** você entrou — e é
## justamente essa a dúvida de quem digitou um código de seis letras que alguém
## mandou por mensagem. Xadrez ou Ludo? Com relógio? Já começou?
##
## A espera também é o único momento do app em que não há o que tocar, e uma tela
## sem resposta com uma linha de texto pequena lê como travada. Um painel que
## ocupa a tela responde "estou esperando, e é isto que estou esperando".
##
## ## Ele sai por um botão, e o botão desiste de verdade
##
## Sair daqui não é voltar de tela: é largar a cadeira que o servidor já reservou.
## Sem isso a cadeira fica ocupada até a carência do relay expirar, e quem tentar
## entrar no lugar recebe "sala cheia" de uma sala que tem gente de menos.

## Desistiu de entrar. Quem escuta larga a sala.
signal cancelled

const PANEL_WIDTH := 320

var _title: Label = null
var _detail: Label = null
var _count: Label = null
var _hint: Label = null


## As âncoras são escritas por quem monta, antes do `add_child` — mesma armadilha
## do painel de fim de Metrópole e do de boas-vindas.
func _ready() -> void:
	visible = false

	var shade := ColorRect.new()
	shade.color = Color(AppTheme.BACKGROUND, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_title = Label.new()
	_title.theme_type_variation = &"Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_detail = Label.new()
	_detail.theme_type_variation = &"Subtitle"
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail)

	# A lotação é o número grande: é o que muda enquanto se espera, e é a única
	# coisa da tela que responde "falta muito?".
	_count = Label.new()
	_count.theme_type_variation = &"Display"
	_count.add_theme_font_size_override("font_size", 34)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_count)

	_hint = Label.new()
	_hint.theme_type_variation = &"Caption"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)

	var cancel := Button.new()
	cancel.text = "Desistir"
	cancel.theme_type_variation = &"GhostButton"
	cancel.custom_minimum_size.y = 44
	cancel.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(cancel)


## Mostra a espera. `taken` e `capacity` vêm do relay, que os conhece assim que a
## cadeira é dada — antes de o anfitrião ter dito qualquer coisa.
##
## `capacity` zero é a sala de dois, onde o relay não conta: ali a pergunta não é
## "quantos faltam" e sim "o anfitrião ainda está aí".
func show_room(game_id: StringName, code: String, taken: int, capacity: int) -> void:
	var title := Game.game_title(game_id)
	_title.text = title if not title.is_empty() else "Partida"
	_detail.text = "Sala %s" % code
	if capacity > 2:
		_count.text = "%d de %d" % [taken, capacity]
		_hint.text = (
			"Esperando a mesa encher." if taken < capacity
			else "Mesa cheia. Entrando na partida…"
		)
	else:
		_count.text = ""
		_hint.text = "Esperando o anfitrião abrir a partida."
	visible = true


func hide_room() -> void:
	visible = false
