class_name SeatList
extends VBoxContainer

## Os lugares de uma sala, um por linha: quem já sentou e quem ainda falta.
##
## A sala de espera desenhava as cadeiras em volta de uma mesa redonda
## (`SeatTable`). Bonito, e gastava meia tela para dizer duas palavras por
## cadeira. Em linhas cabe o nome de quem chegou, o papel dele e — na linha
## vazia, que pulsa — o que ainda se espera, na mesma altura de um cartão de sala.
##
## A interface é a da `SeatTable` de propósito (`capacity`, `local_seat`,
## `present`, `refresh`): quem monta a espera troca uma pela outra sem mudar o que
## pergunta ao relay.

## A cor de cada lugar. É só para distinguir as linhas entre si: dentro da
## partida cada jogo pinta o assento do jeito dele.
const SEAT_COLORS: Array[Color] = [
	Color("ff4d7d"), Color("59d36b"), Color("39c6ff"),
	Color("ffc229"), Color("9b7bff"), Color("ff8a3d"),
]
const ROW_HEIGHT := 60.0

var capacity := 2
var local_seat := 0
## Quem abriu a sala. No relay é sempre o assento 0.
var host_seat := 0
## Assentos ocupados agora, como o relay os conhece.
var present := PackedInt32Array()


func _init() -> void:
	add_theme_constant_override("separation", AppTheme.SPACE_S)


func is_taken(seat: int) -> bool:
	return seat == local_seat or present.has(seat)


func title_of(seat: int) -> String:
	if seat == local_seat:
		return "Você"
	return "Jogador %d" % (seat + 1) if is_taken(seat) else "Esperando alguém"


func detail_of(seat: int) -> String:
	if not is_taken(seat):
		return ""
	if seat == host_seat:
		return "Abriu a sala"
	return "Chegou"


## Refaz as linhas. Chamado quando a lotação muda ou quando alguém senta.
func refresh() -> void:
	# `remove_child` antes do `queue_free`: o segundo só apaga no fim do quadro, e
	# até lá a lista teria as linhas velhas embaixo das novas.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for seat in capacity:
		var row := Row.new()
		row.color = SEAT_COLORS[seat % SEAT_COLORS.size()]
		row.taken = is_taken(seat)
		row.mine = seat == local_seat
		row.number = seat + 1
		row.title = title_of(seat)
		row.detail = detail_of(seat)
		add_child(row)


class Row:
	extends Control

	var color := Color.WHITE
	var taken := false
	var mine := false
	var number := 1
	var title := ""
	var detail := ""

	func _init() -> void:
		custom_minimum_size.y = SeatList.ROW_HEIGHT
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		if taken:
			return
		# O lugar vazio pulsa: é o que a tela inteira está esperando.
		var pulse := create_tween().set_loops()
		pulse.tween_property(self, "modulate:a", 0.45, 0.8)
		pulse.tween_property(self, "modulate:a", 1.0, 0.8)

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		if taken:
			draw_style_box(AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_LARGE), box)
		else:
			draw_style_box(
				AppTheme.framed(Color(0, 0, 0, 0), AppTheme.SURFACE_TOP, AppTheme.RADIUS_LARGE), box
			)
		var center := Vector2(12.0 + 20.0, size.y * 0.5)
		draw_circle(center, 20.0, color if taken else Color(color, 0.45))
		if taken:
			draw_string(
				AppTheme.display(700), Vector2(center.x - 20.0, center.y + 6.0), str(number),
				HORIZONTAL_ALIGNMENT_CENTER, 40.0, 17, AppTheme.ACCENT_INK
			)
		var text_x := center.x + 20.0 + 12.0
		var text_width := size.x - text_x - 12.0
		if detail.is_empty():
			draw_string(
				AppTheme.font(700), Vector2(text_x, size.y * 0.5 + 5.0), title,
				HORIZONTAL_ALIGNMENT_LEFT, text_width, 15, AppTheme.TEXT_DIM
			)
			return
		draw_string(
			AppTheme.display(600), Vector2(text_x, size.y * 0.5 - 2.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, text_width, 17, AppTheme.TEXT
		)
		draw_string(
			AppTheme.font(700), Vector2(text_x, size.y * 0.5 + 16.0), detail,
			HORIZONTAL_ALIGNMENT_LEFT, text_width, 12, AppTheme.ACCENT if mine else AppTheme.TEXT_DIM
		)
