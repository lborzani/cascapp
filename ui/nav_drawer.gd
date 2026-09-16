class_name NavDrawer
extends Control

## A gaveta de navegação: a marca no topo e os destinos do app embaixo.
##
## Ela existe porque o app passou a ter três lugares para estar — a coleção de
## jogos, o multiplayer e os ajustes — e nenhum deles é filho do outro. Numa
## pilha de telas, ir dos ajustes para o multiplayer é voltar e entrar de novo;
## com a gaveta, é um toque de qualquer lugar.
##
## Modal, e não uma coluna fixa: a tela do celular tem 432 px de largura, e uma
## coluna permanente de 280 comeria dois terços dela. Em tablet valeria a coluna,
## e é a mesma lista que ela mostraria.
##
## O véu fecha ao toque, o gesto de voltar fecha, e a tela de onde ela saiu
## continua viva por baixo: abrir a gaveta não é navegar, é perguntar para onde.
##
## Quem navega é a tela. A gaveta emite a rota e sai do caminho — é o que permite
## a mesma gaveta servir a tela inicial, que já está em `Home` e não deve se
## recarregar, e as outras, que trocam de cena.

signal picked(route: StringName)

const HOME := &"home"
const MULTIPLAYER := &"multiplayer"
const SETTINGS := &"settings"

const APP_NAME := "Cascapp"
const WIDTH := 284.0
const SLIDE := 0.18
## Diâmetro do disco da marca no topo. É o mesmo ícone do app, e o círculo é o
## que o Android desenha na gaveta dele desde sempre.
const LOGO := 72.0
const LOGO_PATH := "res://assets/icon/role.png"

const ITEMS := [
	{"route": HOME, "label": "Início"},
	{"route": MULTIPLAYER, "label": "Multiplayer"},
	{"route": SETTINGS, "label": "Configurações"},
]

## Qual linha aparece marcada. A tela diz onde está ao abrir a gaveta — uma
## gaveta que não mostra onde o jogador está é uma lista de links.
var current: StringName = HOME

var _panel: PanelContainer = null
var _scrim: ColorRect = null
var _closing := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_scrim = ColorRect.new()
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.color = AppTheme.SCRIM
	_scrim.modulate.a = 0.0
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	_panel = PanelContainer.new()
	# Ancorado na borda esquerda e movido pelos **offsets**, não por `position`: o
	# pai é um `Control` ancorado, e ele reescreve a posição dos filhos no primeiro
	# layout. A gaveta chegava 44 px à esquerda de onde devia e cortava a primeira
	# letra de cada linha — sem erro nenhum, porque nada tinha falhado.
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH
	_panel.offset_right = 0.0
	# Superfície do topo da pilha: ela está por cima de uma tela que já tem
	# cartões, e um mesmo tom faria a gaveta parecer parte do que está atrás.
	var style := AppTheme.box(AppTheme.SURFACE_TOP, 0)
	style.content_margin_left = AppTheme.SPACE_M
	style.content_margin_right = AppTheme.SPACE_M
	style.content_margin_top = AppTheme.SPACE_XL
	style.content_margin_bottom = AppTheme.SPACE_L
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_panel.add_child(_build_body())


func _build_body() -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", AppTheme.SPACE_S)

	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(LOGO, LOGO)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(LOGO_PATH):
		logo.texture = load(LOGO_PATH)
	body.add_child(logo)

	var name_label := Label.new()
	# Escrito, e não lido de `application/config/name`: aquele é o nome do pacote,
	# em caixa baixa, e a gaveta mostrava "cascapp" com um logo em cima.
	name_label.text = APP_NAME
	name_label.theme_type_variation = &"Title"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(name_label)

	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 1.0
	rule.color = Color(1.0, 1.0, 1.0, 0.07)
	body.add_child(_spacer(AppTheme.SPACE_S))
	body.add_child(rule)
	body.add_child(_spacer(AppTheme.SPACE_S))

	for item in ITEMS:
		var route: StringName = item["route"]
		var entry := Button.new()
		entry.text = str(item["label"])
		entry.custom_minimum_size.y = AppTheme.NAV_HEIGHT
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.focus_mode = Control.FOCUS_NONE
		entry.theme_type_variation = (
			&"NavItemSelected" if route == current else &"NavItem"
		)
		# Sem servidor de partidas não há sala para procurar. A linha continua na
		# gaveta, apagada: um destino que some parece um destino que foi removido,
		# e a nota embaixo diz por que ele não responde.
		entry.disabled = route == MULTIPLAYER and not Net.relay_available()
		entry.pressed.connect(_pick.bind(route))
		body.add_child(entry)

	if not Net.relay_available():
		body.add_child(_spacer(AppTheme.SPACE_S))
		var note := Label.new()
		note.text = "Este build não tem servidor de partidas."
		note.theme_type_variation = &"Caption"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(note)
	return body


func _spacer(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = float(height)
	return gap


## Abre com o painel deslizando e o véu escurecendo junto. Os dois no mesmo
## tempo: um véu que escurece antes do painel chegar parece a tela apagando.
func open() -> void:
	_slide(0.0, 1.0)


func close() -> void:
	if _closing:
		return
	_closing = true
	await _slide(-WIDTH, 0.0).finished
	queue_free()


## Os dois offsets andam juntos porque são as duas bordas do mesmo painel: mover
## só o esquerdo o estica em vez de deslizá-lo.
func _slide(left: float, veil: float) -> Tween:
	var slide := create_tween().set_parallel()
	slide.tween_property(_panel, "offset_left", left, SLIDE).set_trans(Tween.TRANS_CUBIC)
	slide.tween_property(_panel, "offset_right", left + WIDTH, SLIDE).set_trans(Tween.TRANS_CUBIC)
	slide.tween_property(_scrim, "modulate:a", veil, SLIDE)
	return slide


## A rota sai **antes** de a gaveta fechar, e a tela é quem decide o que fazer com
## ela: trocar de cena descarta esta gaveta junto, e esperar a animação para
## depois navegar seria adiar a resposta ao toque por 180 ms sem ganhar nada.
func _pick(route: StringName) -> void:
	Sound.play(Sound.Cue.TAP)
	picked.emit(route)
	close()


func _on_scrim_input(event: InputEvent) -> void:
	# Por [Tap]: um clique chega duas vezes, e fechar duas vezes é inofensivo — mas
	# a gaveta usa a mesma porta que o resto do app, e uma porta só é uma porta.
	if Tap.began(event):
		close()
