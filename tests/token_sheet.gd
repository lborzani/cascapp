extends Node

## As peças do Metrópole da loja de perto, lado a lado, na amostra da loja
## (`ShopPanel.TokenSample`). Salva em `user://shots/20m_pecas_loja.png`:
##
##   godot --path . res://tests/token_sheet.tscn

const Stage := preload("res://tests/shot_stage.gd")

var _stage: SubViewport = null
var _frames := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	_stage = Stage.make(self, Vector2i(720, 300))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(20, 10)
	_stage.add_child(grid)
	for id in [""] + Array(Cosmetics.of_slot(Cosmetics.TOKEN)):
		var cell := VBoxContainer.new()
		var sample := ShopPanel.TokenSample.new(Cosmetics.token_of({Cosmetics.TOKEN: id}))
		sample.custom_minimum_size = Vector2(160, 110)
		cell.add_child(sample)
		var label := Label.new()
		label.text = "Padrão" if id.is_empty() else str(Cosmetics.ITEMS[id]["name"])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(label)
		grid.add_child(cell)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 20:
		Stage.save(_stage, "user://shots/20m_pecas_loja.png")
		print("shot 20m_pecas_loja")
		get_tree().quit()
