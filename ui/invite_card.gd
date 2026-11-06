class_name InviteCard
extends MarginContainer

## O aviso de convite: "Bia te chamou para Xadrez", com Entrar e Agora não.
##
## Desce no topo da tela, por cima do que estiver aberto, e não tapa o resto: quem
## não quer entrar segue mexendo no app sem precisar responder. Quem o põe na tela
## e decide o que cada botão faz é o `Friends`.

signal accepted
signal declined

const PHOTO := 44.0

var friend_name := ""
var game_title := ""
var photo: Texture2D = null


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	# A margem em volta do cartão não pega toque: ali embaixo ainda é a tela.
	mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		add_theme_constant_override("margin_" + side, AppTheme.SPACE_M)
	add_theme_constant_override("margin_top", AppTheme.SPACE_M + int(_safe_top()))
	theme = AppTheme.shared()

	var card := PanelContainer.new()
	var style := AppTheme.box(AppTheme.SURFACE_TOP, AppTheme.RADIUS, AppTheme.ACCENT, 2)
	style.content_margin_left = AppTheme.SPACE_M
	style.content_margin_right = AppTheme.SPACE_M
	style.content_margin_top = AppTheme.SPACE_M
	style.content_margin_bottom = AppTheme.SPACE_M
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	card.add_theme_stylebox_override("panel", style)
	add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_M)
	card.add_child(column)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", AppTheme.SPACE_M)
	column.add_child(line)
	var coaster := Coaster.new()
	coaster.custom_minimum_size = Vector2(PHOTO, PHOTO)
	coaster.size_flags_vertical = SIZE_SHRINK_CENTER
	coaster.player_name = friend_name
	coaster.photo = photo
	line.add_child(coaster)
	var message := Label.new()
	message.name = "Message"
	message.text = "%s te chamou para %s" % [friend_name, game_title if not game_title.is_empty() else "jogar"]
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_horizontal = SIZE_EXPAND_FILL
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_override("font", AppTheme.font(800))
	message.add_theme_font_size_override("font_size", AppTheme.SIZE_BODY)
	line.add_child(message)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", AppTheme.SPACE_S)
	column.add_child(buttons)
	var later := _button("Agora não", &"GhostButton")
	later.pressed.connect(func() -> void: declined.emit())
	buttons.add_child(later)
	var enter := _button("Entrar", &"PrimaryButton")
	enter.pressed.connect(func() -> void: accepted.emit())
	buttons.add_child(enter)

	modulate.a = 0.0
	position.y = -24.0
	var drop := create_tween().set_parallel()
	drop.tween_property(self, "modulate:a", 1.0, 0.18)
	drop.tween_property(self, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _button(text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.name = text.replace(" ", "")
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	return button


## O recorte da câmera, em pixels da tela base: o aviso não pode nascer embaixo dele.
func _safe_top() -> float:
	var screen := DisplayServer.screen_get_size()
	if screen.y <= 0:
		return 0.0
	return DisplayServer.get_display_safe_area().position.y * get_viewport_rect().size.y / screen.y
