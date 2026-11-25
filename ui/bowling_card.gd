class_name BowlingCard
extends Control

## A cartela do boliche: uma linha por jogador, dez frames e o total.
##
## Só desenha. As marcas (`X`, `/`, `-`) e o acumulado saem de [BowlingRules], e a
## linha de quem joga e o frame da vez ficam acesos.

const ROW := 30.0
const NAME_WIDTH := 84.0
const TOTAL_WIDTH := 40.0
const GAP := 4.0

var state: MatchState = null:
	set(value):
		state = value
		_fit()
		queue_redraw()
var names := PackedStringArray():
	set(value):
		names = value
		queue_redraw()
## O visual da loja de cada assento: o nome sai na cor dele.
var looks: Array = []:
	set(value):
		looks = value
		queue_redraw()
var colors: Array[Color] = []:
	set(value):
		colors = value
		queue_redraw()


func _fit() -> void:
	var rows := BowlingRules.seats_of(state) if state != null else 1
	custom_minimum_size.y = rows * ROW + (rows - 1) * GAP


func _draw() -> void:
	if state == null:
		return
	var turn := BowlingRules.turn_of(state)
	var over := BowlingRules.game_over(state)
	var frame_w := (size.x - NAME_WIDTH - TOTAL_WIDTH) / BowlingRules.FRAMES
	var bold := AppTheme.font(800)
	var body := AppTheme.font(600)
	for seat in BowlingRules.seats_of(state):
		var top := seat * (ROW + GAP)
		var active := seat == turn and not over
		var row := Rect2(0.0, top, size.x, ROW)
		draw_style_box(AppTheme.box(AppTheme.SURFACE_HIGH if active else AppTheme.SURFACE, 8,
			AppTheme.ACCENT if active else Color(0, 0, 0, 0), 2 if active else 0), row)

		var tint: Color = colors[seat] if seat < colors.size() else AppTheme.TEXT
		draw_circle(Vector2(10.0, top + ROW * 0.5), 5.0, tint)
		var label := names[seat] if seat < names.size() else "Jogador %d" % (seat + 1)
		ProfileStyle.draw_name(self, bold, Vector2(19.0, top + ROW * 0.5 + 5.0), label,
			NAME_WIDTH - 22.0, 12, AppTheme.ACCENT if active else AppTheme.TEXT,
			looks[seat] if seat < looks.size() else {})

		var rolls := BowlingRules.rolls_of(state, seat)
		var marks := BowlingRules.marks(rolls)
		var totals := BowlingRules.totals(rolls)
		var current := int(BowlingRules.position(rolls)["frame"])
		for frame in BowlingRules.FRAMES:
			var cell := Rect2(NAME_WIDTH + frame * frame_w, top, frame_w, ROW)
			if active and frame == current:
				draw_rect(cell.grow(-2.0), AppTheme.ACCENT_SOFT)
			draw_line(cell.position + Vector2(0.0, 5.0), cell.position + Vector2(0.0, ROW - 5.0), AppTheme.LINE_SOFT, 1.0)
			var cells: PackedStringArray = marks[frame]
			var mark_text := " ".join(cells)
			_centered(body, mark_text, Vector2(cell.get_center().x, top + 12.0), 10, AppTheme.TEXT_DIM)
			if totals[frame] >= 0 and not cells.is_empty():
				_centered(bold, str(totals[frame]), Vector2(cell.get_center().x, top + ROW - 5.0), 12, AppTheme.TEXT)
		var score := BowlingRules.score_of(state, seat)
		_centered(AppTheme.display(800), str(score), Vector2(size.x - TOTAL_WIDTH * 0.5, top + ROW * 0.5 + 7.0), 18,
			AppTheme.ACCENT if active else AppTheme.TEXT)


func _centered(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(at.x - wide * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
