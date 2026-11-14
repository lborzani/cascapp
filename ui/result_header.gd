class_name ResultHeader
extends VBoxContainer

## O topo do cartão de fim de partida: o selo do resultado e uma fileira de
## números.
##
## O fim de partida dizia o resultado numa linha de texto. O selo diz antes de
## ler — troféu limão em quem venceu, apagado em quem perdeu, "=" no empate —, e
## os números respondem "como foi" sem abrir a revisão: duração, lances, Elo.
##
## Componente e não cena: os jogos montam o próprio cartão de fim, e cada um
## sabe que números tem. Quem chama passa o humor e os blocos; o selo balança
## devagar enquanto o cartão está aberto.

enum Mood { WIN, DRAW, LOSS }

const BADGE := 92.0
const EDGE := 6.0

var mood := Mood.WIN:
	set(value):
		mood = value
		if _badge != null:
			_badge.queue_redraw()

var _badge: Control = null
var _stats: HBoxContainer = null
var _wobble: Tween = null


func _init() -> void:
	add_theme_constant_override("separation", AppTheme.SPACE_L)
	_badge = Control.new()
	_badge.custom_minimum_size = Vector2(BADGE, BADGE + EDGE)
	_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(_draw_badge)
	add_child(_badge)
	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", AppTheme.SPACE_S)
	_stats.visible = false
	visibility_changed.connect(_sync_wobble)


## Mostra o resultado. `stats` é uma lista de `[valor, legenda, destaque]`; o
## destaque pinta a legenda de limão (o Elo que subiu). Vazia, a fileira some.
func show_result(new_mood: Mood, stats: Array) -> void:
	mood = new_mood
	set_stats(stats)
	_sync_wobble()


func set_stats(stats: Array) -> void:
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for entry: Array in stats:
		_stats.add_child(_tile(str(entry[0]), str(entry[1]), entry.size() > 2 and bool(entry[2])))
	_stats.visible = not stats.is_empty()


## A fileira de números, para o cartão pôr onde couber (embaixo do texto).
func stats_row() -> HBoxContainer:
	return _stats


func _tile(value: String, caption: String, lit: bool) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := AppTheme.box(AppTheme.SURFACE_HIGH, AppTheme.RADIUS_LARGE)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	tile.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -2)
	tile.add_child(column)
	var number := Label.new()
	number.text = value
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", AppTheme.display(700))
	number.add_theme_font_size_override("font_size", 22)
	number.add_theme_color_override("font_color", AppTheme.TEXT)
	column.add_child(number)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", AppTheme.font(800))
	label.add_theme_font_size_override("font_size", AppTheme.SIZE_CAPTION)
	label.add_theme_color_override("font_color", AppTheme.ACCENT if lit else AppTheme.TEXT_DIM)
	column.add_child(label)
	return tile


## O selo balança só enquanto aparece, e só quando há o que comemorar.
func _sync_wobble() -> void:
	if _wobble != null:
		_wobble.kill()
		_wobble = null
	_badge.rotation = 0.0
	if mood != Mood.WIN or not is_visible_in_tree():
		return
	_badge.pivot_offset = _badge.custom_minimum_size * 0.5
	_wobble = _badge.create_tween().set_loops()
	_wobble.tween_property(_badge, "rotation", 0.1, 0.9).set_trans(Tween.TRANS_SINE)
	_wobble.tween_property(_badge, "rotation", -0.1, 0.9).set_trans(Tween.TRANS_SINE)


func _draw_badge() -> void:
	var center := Vector2(BADGE * 0.5, BADGE * 0.5)
	var radius := BADGE * 0.5
	var fill := AppTheme.ACCENT if mood == Mood.WIN else AppTheme.SURFACE_TOP
	var edge := AppTheme.ACCENT_EDGE if mood == Mood.WIN else AppTheme.SURFACE_HIGH
	var ink := AppTheme.ACCENT_INK if mood == Mood.WIN else AppTheme.TEXT_DIM
	_badge.draw_circle(center + Vector2(0.0, EDGE), radius, edge)
	_badge.draw_circle(center, radius, fill)
	if mood == Mood.DRAW:
		for dy: float in [-7.0, 7.0]:
			_badge.draw_line(center + Vector2(-16.0, dy), center + Vector2(16.0, dy), ink, 6.0, true)
		return
	# A taça: copo, duas alças, haste e base. Em traço, como os ícones do app.
	var s := radius / 46.0
	var cup := PackedVector2Array([
		center + Vector2(-15, -18) * s, center + Vector2(15, -18) * s,
		center + Vector2(15, -6) * s, center + Vector2(9, 4) * s,
		center + Vector2(0, 7) * s, center + Vector2(-9, 4) * s,
		center + Vector2(-15, -6) * s, center + Vector2(-15, -18) * s,
	])
	_badge.draw_polyline(cup, ink, 4.0 * s, true)
	_badge.draw_arc(center + Vector2(-15, -10) * s, 7.0 * s, PI * 0.5, PI * 1.5, 12, ink, 3.5 * s, true)
	_badge.draw_arc(center + Vector2(15, -10) * s, 7.0 * s, -PI * 0.5, PI * 0.5, 12, ink, 3.5 * s, true)
	_badge.draw_line(center + Vector2(0, 7) * s, center + Vector2(0, 15) * s, ink, 4.0 * s, true)
	_badge.draw_line(center + Vector2(-10, 18) * s, center + Vector2(10, 18) * s, ink, 4.5 * s, true)
