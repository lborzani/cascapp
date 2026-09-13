class_name SafeAreaMargin
extends MarginContainer

## Afasta o conteúdo do notch da câmera e da barra de navegação.
##
## O export está em modo *edge to edge*, ou seja, o app desenha por baixo das
## barras do sistema. Isso é bom para o fundo — a tela inteira fica escura em vez
## de emoldurada — e péssimo para o conteúdo, que some atrás do recorte da câmera
## e dos botões de navegação. A correção é manter o fundo até a borda e recuar
## apenas o que precisa ser lido e tocado, que é exatamente o que este container
## faz com os filhos.
##
## Em desktop `get_display_safe_area()` devolve a tela inteira e as margens ficam
## sendo só as do projeto, sem caso especial.

var _base := {}


func _ready() -> void:
	for side in ["left", "top", "right", "bottom"]:
		_base[side] = get_theme_constant("margin_" + side)
	_apply()
	get_window().size_changed.connect(_apply)


func _apply() -> void:
	var insets := _safe_area_insets()
	add_theme_constant_override("margin_left", int(_base["left"] + insets.position.x))
	add_theme_constant_override("margin_top", int(_base["top"] + insets.position.y))
	add_theme_constant_override("margin_right", int(_base["right"] + insets.size.x))
	add_theme_constant_override("margin_bottom", int(_base["bottom"] + insets.size.y))


## Devolve as sobras em coordenadas do viewport: `position` é o recuo em cima e à
## esquerda, `size` o recuo embaixo e à direita. A conversão importa porque o
## projeto usa `stretch/canvas_items`, então pixel de tela não é pixel de UI.
func _safe_area_insets() -> Rect2:
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return Rect2()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Rect2()

	var viewport := get_viewport_rect().size
	var scale := Vector2(viewport.x / float(window.x), viewport.y / float(window.y))
	return Rect2(
		Vector2(maxf(0.0, safe.position.x), maxf(0.0, safe.position.y)) * scale,
		Vector2(
			maxf(0.0, window.x - safe.end.x),
			maxf(0.0, window.y - safe.end.y)
		) * scale
	)
