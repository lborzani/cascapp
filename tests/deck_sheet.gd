extends Node

## Os baralhos do Uno da loja de perto: o verso e cartas das quatro cores e um
## curinga, em cada baralho. Salva em `user://shots/21_baralhos.png`:
##
##   godot --path . res://tests/deck_sheet.tscn

const Stage := preload("res://tests/shot_stage.gd")
const HEIGHT := 96.0

var _stage: SubViewport = null
var _frames := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	# O dos testadores logo depois do padrão: é o que mais pede conferência.
	var ids: Array = ["", "deck_pioneer"] + Array(Cosmetics.of_slot(Cosmetics.DECK)).filter(func(id: String) -> bool: return id != "deck_pioneer")
	_stage = Stage.make(self, Vector2i(600, int(ids.size() * (HEIGHT + 22.0)) + 20))
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(func() -> void:
		var cards := [
			UnoRules.card(UnoRules.CardColor.RED, 7), UnoRules.card(UnoRules.CardColor.YELLOW, UnoRules.SKIP),
			UnoRules.card(UnoRules.CardColor.GREEN, UnoRules.DRAW_TWO), UnoRules.card(UnoRules.CardColor.BLUE, 4),
			UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR),
		]
		for row in ids.size():
			var skin := Cosmetics.deck_of({Cosmetics.DECK: ids[row]})
			var y := 10.0 + row * (HEIGHT + 22.0) + HEIGHT * 0.5
			var label := "Padrão" if str(ids[row]).is_empty() else str(Cosmetics.ITEMS[ids[row]]["name"])
			canvas.draw_string(AppTheme.font(700), Vector2(8, y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, 90, 13, AppTheme.TEXT)
			UnoCardArt.draw_back(canvas, Vector2(130, y), HEIGHT, 0.0, 1.0, Color(0, 0, 0, 0), skin)
			for i in cards.size():
				UnoCardArt.draw_card(canvas, cards[i], Vector2(210 + i * 72, y), HEIGHT, 0.0, false, 1.0, Color(0, 0, 0, 0), skin)
	)
	_stage.add_child(canvas)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		Stage.save(_stage, "user://shots/21_baralhos.png")
		print("shot 21_baralhos")
		get_tree().quit()
