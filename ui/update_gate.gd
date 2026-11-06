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
## Dois caminhos. Com pacote OTA (`offer.pck`), ele baixa aqui dentro, é
## conferido pelo sha256 que a release anunciou, e espera em `user://ota/` a
## próxima abertura (`Patcher`) — o Android não deixa o app se reiniciar, então a
## tela pede para fechar e abrir. Sem pacote, ou se ele falhar, o APK baixa pelo
## navegador e instala por cima. Nos dois, a próxima abertura já é a versão nova,
## e o menu não mostra mais esta tela.

## `{version, url, changes}` e às vezes `pck`, de `UpdateCheck.offer`.
var offer := {}

var _download: Button = null
var _hint: Label = null
## O pacote não baixou ou não conferiu: daqui em diante, o APK.
var _pck_failed := false


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
	scroll.add_child(ChangelogPanel.notes(offer.get("changes", [])))

	_download = Button.new()
	_download.name = "Download"
	_download.theme_type_variation = &"PrimaryButton"
	_download.custom_minimum_size = Vector2(0, 52)
	# Não some depois do toque: download cancelado ou falho no navegador deixa o
	# botão à mão.
	_download.pressed.connect(_on_download)
	column.add_child(_download)
	_hint = _label("", &"Hint", "Hint")
	column.add_child(_hint)
	_refresh()


## O pacote, quando ele serve: não é o que já falhou ao abrir (`Patcher.failed`)
## nem o que acabou de falhar aqui.
func _pck() -> Dictionary:
	var pck = offer.get("pck", {})
	if _pck_failed or not pck is Dictionary or offer.get("version") == Patcher.failed \
			or not str(pck.get("url", "")).begins_with(UpdateCheck.DOWNLOADS):
		return {}
	return pck


func _pck_path() -> String:
	return Patcher.DIR + "%s.pck" % offer.get("version", "")


## Baixado numa vez anterior, só falta reabrir.
func _downloaded() -> bool:
	return not _pck().is_empty() and FileAccess.file_exists(_pck_path())


func _refresh() -> void:
	var version := str(offer.get("version", ""))
	var pck := _pck()
	if _downloaded():
		_download.text = "Fechar o app"
		_hint.text = "A versão %s já está baixada. Feche e abra o app de novo para usar." % version
	elif not pck.is_empty():
		_download.text = "Atualizar para a %s (%s MB)" % [
			version, ("%.1f" % (int(pck.get("size", 0)) / 1048576.0)).replace(".", ",")
		]
		_hint.text = "Baixa aqui mesmo. Depois é só fechar e abrir o app."
	else:
		_download.text = "Baixar a versão %s" % version
		_hint.text = "O APK baixa pelo navegador; abra o arquivo para instalar por cima."
		if _pck_failed:
			_hint.text = "Não deu para atualizar por aqui. " + _hint.text


func _on_download() -> void:
	Sound.play(Sound.Cue.TAP)
	if _downloaded():
		get_tree().quit()
	elif not _pck().is_empty():
		_fetch_pck()
	else:
		var url := str(offer.get("url", ""))
		if url.begins_with(UpdateCheck.DOWNLOADS):
			OS.shell_open(url)


## Baixa para `.part` e só renomeia depois de conferir: o `Patcher` nunca vê um
## pacote pela metade.
func _fetch_pck() -> void:
	var pck := _pck()
	var part := _pck_path() + ".part"
	DirAccess.make_dir_recursive_absolute(Patcher.DIR)
	var http := HTTPRequest.new()
	http.download_file = part
	http.timeout = 120.0
	add_child(http)
	_download.disabled = true
	_download.text = "Baixando…"
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			http.queue_free()
			_download.disabled = false
			if result == HTTPRequest.RESULT_SUCCESS and code == 200 and UpdateCheck.verify(part, pck):
				DirAccess.rename_absolute(part, _pck_path())
			else:
				DirAccess.remove_absolute(part)
				_pck_failed = true
			_refresh()
	)
	if http.request(str(pck.get("url", ""))) != OK:
		http.queue_free()
		_download.disabled = false
		_pck_failed = true
		_refresh()


func _label(text: String, variation: StringName, node_name: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		label.theme_type_variation = variation
	if not node_name.is_empty():
		label.name = node_name
	return label
