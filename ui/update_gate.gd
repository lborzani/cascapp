class_name UpdateGate
extends Control

## A tela da versão nova obrigatória: o que muda e o botão de baixar, por cima de
## tudo e sem saída.
##
## Sem "Agora não" de propósito. Duas versões convivendo são duas regras de jogo e
## dois protocolos falando com o mesmo relay, e quem fica para trás descobre isso
## no meio de uma partida com um amigo. O gesto de voltar fecha o app (é a tela
## inicial que a hospeda), que é a única saída honesta.
##
## O APK baixa pelo navegador e instala por cima; a próxima abertura já é a versão
## nova, e o menu não mostra mais esta tela.

## `{version, url, changes}` de `UpdateCheck.offer`.
var offer := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# O tema da tela que a hospeda nem sempre desce até aqui (ver `AppTheme`).
	theme = AppTheme.shared()
	# Nada atrás desta tela recebe toque.
	mouse_filter = MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)

	var safe := SafeAreaMargin.new()
	for side in ["left", "right"]:
		safe.add_theme_constant_override("margin_" + side, AppTheme.SCREEN_PAD)
	for side in ["top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, AppTheme.SPACE_XL)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_M)
	safe.add_child(column)

	column.add_child(_label("Versão %s" % offer.get("version", ""), &"Title", "Title"))
	column.add_child(_label(
		"Você está na %s. Para continuar jogando, instale a versão nova." % AppVersion.text(), &"Subtitle", ""
	))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(scroll)
	var notes := VBoxContainer.new()
	notes.name = "Notes"
	notes.size_flags_horizontal = SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", AppTheme.SPACE_S)
	scroll.add_child(notes)
	var changes: Array = offer.get("changes", [])
	if changes.is_empty():
		notes.add_child(_label("Melhorias e correções.", &"", ""))
	for change: Dictionary in changes:
		notes.add_child(_label("Novidades da %s" % change["version"], &"SectionHeader", ""))
		for item in change["items"]:
			notes.add_child(_label("•  %s" % item, &"", ""))

	var download := Button.new()
	download.name = "Download"
	download.text = "Baixar a versão %s" % offer.get("version", "")
	download.theme_type_variation = &"PrimaryButton"
	download.custom_minimum_size = Vector2(0, 52)
	# Não some depois do toque: download cancelado ou falho no navegador deixa o
	# botão à mão.
	download.pressed.connect(func() -> void:
		Sound.play(Sound.Cue.TAP)
		var url := str(offer.get("url", ""))
		if url.begins_with(UpdateCheck.DOWNLOADS):
			OS.shell_open(url)
	)
	column.add_child(download)
	column.add_child(_label("O APK baixa pelo navegador; abra o arquivo para instalar por cima.", &"Hint", ""))


func _label(text: String, variation: StringName, node_name: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	if not node_name.is_empty():
		label.name = node_name
	return label
