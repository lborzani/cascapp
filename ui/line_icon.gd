class_name LineIcon
extends RefCounted

## Ícones em traço, desenhados no `_draw` de quem chama: as abas da base e os
## atalhos da aba Você. Traço e não glifo pelo mesmo motivo do `IconButton` — a
## fonte do aparelho não decide se o ícone existe. Acrescentar um é acrescentar
## um `match` aqui.

const STROKE := 2.0

const DICE := &"dice"
const GLOBE := &"globe"
const BAG := &"bag"
const PERSON := &"person"
const CLOCK := &"clock"
const TARGET := &"target"
const FLAG := &"flag"
const GIFT := &"gift"
const BOOK := &"book"
const SHIELD := &"shield"


## `kind` num quadrado de lado `side` centrado em `at`.
static func draw(canvas: CanvasItem, kind: StringName, at: Vector2, side: float, ink: Color) -> void:
	var r := side * 0.5
	var w := STROKE * side / 16.0
	match kind:
		DICE:
			_rounded(canvas, Rect2(at - Vector2(r, r), Vector2(side, side)), r * 0.5, ink, w)
			for step in [-1, 0, 1]:
				canvas.draw_circle(at + Vector2(step, step) * r * 0.45, r * 0.2, ink)
		GLOBE:
			canvas.draw_arc(at, r - w * 0.5, 0.0, TAU, 32, ink, w, true)
			canvas.draw_line(at + Vector2(-r, 0.0), at + Vector2(r, 0.0), ink, w * 0.75, true)
			var meridian := PackedVector2Array()
			for index in 25:
				var angle := TAU * index / 24.0
				meridian.append(at + Vector2(cos(angle) * r * 0.42, sin(angle) * (r - w * 0.5)))
			canvas.draw_polyline(meridian, ink, w * 0.75, true)
		BAG:
			canvas.draw_polyline(PackedVector2Array([
				at + Vector2(-r * 0.88, -r * 0.3), at + Vector2(r * 0.88, -r * 0.3),
				at + Vector2(r * 0.75, r), at + Vector2(-r * 0.75, r), at + Vector2(-r * 0.88, -r * 0.3),
			]), ink, w, true)
			canvas.draw_arc(at + Vector2(0.0, -r * 0.3), r * 0.42, PI, TAU, 12, ink, w, true)
		PERSON:
			canvas.draw_arc(at + Vector2(0.0, -r * 0.42), r * 0.42, 0.0, TAU, 20, ink, w, true)
			canvas.draw_arc(at + Vector2(0.0, r * 1.05), r * 0.9, PI * 1.12, PI * 1.88, 16, ink, w, true)
		CLOCK:
			canvas.draw_arc(at, r - w * 0.5, 0.0, TAU, 32, ink, w, true)
			canvas.draw_polyline(PackedVector2Array([
				at + Vector2(0.0, -r * 0.55), at, at + Vector2(r * 0.4, r * 0.25),
			]), ink, w, true)
		TARGET:
			canvas.draw_arc(at, r - w * 0.5, 0.0, TAU, 32, ink, w, true)
			canvas.draw_arc(at, r * 0.5, 0.0, TAU, 24, ink, w, true)
			canvas.draw_circle(at, r * 0.16, ink)
		FLAG:
			var pole := at + Vector2(-r * 0.6, 0.0)
			canvas.draw_line(pole + Vector2(0.0, -r), pole + Vector2(0.0, r), ink, w, true)
			canvas.draw_polyline(PackedVector2Array([
				pole + Vector2(0.0, -r * 0.9), pole + Vector2(r * 1.5, -r * 0.55),
				pole + Vector2(0.0, -r * 0.1),
			]), ink, w, true)
		GIFT:
			var box := Rect2(at + Vector2(-r * 0.85, -r * 0.25), Vector2(r * 1.7, r * 1.2))
			canvas.draw_rect(box, ink, false, w)
			canvas.draw_line(at + Vector2(-r, -r * 0.25), at + Vector2(r, -r * 0.25), ink, w, true)
			canvas.draw_line(at + Vector2(0.0, -r * 0.25), at + Vector2(0.0, r * 0.95), ink, w, true)
			canvas.draw_arc(at + Vector2(-r * 0.3, -r * 0.55), r * 0.3, 0.0, TAU, 12, ink, w, true)
			canvas.draw_arc(at + Vector2(r * 0.3, -r * 0.55), r * 0.3, 0.0, TAU, 12, ink, w, true)
		BOOK:
			# Aberto: duas páginas que se encontram na lombada.
			canvas.draw_polyline(PackedVector2Array([
				at + Vector2(0.0, -r * 0.55), at + Vector2(-r, -r * 0.75), at + Vector2(-r, r * 0.65),
				at + Vector2(0.0, r * 0.85), at + Vector2(r, r * 0.65), at + Vector2(r, -r * 0.75),
				at + Vector2(0.0, -r * 0.55), at + Vector2(0.0, r * 0.85),
			]), ink, w, true)
		SHIELD:
			var outline := PackedVector2Array()
			outline.append(at + Vector2(0.0, -r))
			outline.append(at + Vector2(r * 0.85, -r * 0.6))
			outline.append(at + Vector2(r * 0.75, r * 0.2))
			outline.append(at + Vector2(0.0, r))
			outline.append(at + Vector2(-r * 0.75, r * 0.2))
			outline.append(at + Vector2(-r * 0.85, -r * 0.6))
			outline.append(at + Vector2(0.0, -r))
			canvas.draw_polyline(outline, ink, w, true)
			canvas.draw_polyline(PackedVector2Array([
				at + Vector2(-r * 0.35, 0.0), at + Vector2(-r * 0.05, r * 0.3), at + Vector2(r * 0.4, -r * 0.3),
			]), ink, w, true)


static func _rounded(canvas: CanvasItem, rect: Rect2, radius: float, ink: Color, width: float) -> void:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(maxi(1, roundi(width)))
	box.border_color = ink
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	canvas.draw_style_box(box, rect)
