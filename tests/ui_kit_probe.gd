extends SceneTree

## Os componentes base do tema Boteco, sem autoload e sem GPU.
##
##   godot --headless --path . --script res://tests/ui_kit_probe.gd
##
## O que se verifica aqui é o que dá para verificar sem enxergar pixel: que as
## fontes são as embarcadas e têm os acentos do português, que as cores de texto
## passam no contraste, que o tema entrega as variações que as telas pedem, e a
## geometria e o comportamento de cada componente. O que só a imagem prova — que
## peças e cartas não mudaram — é conferido por `tests/image_diff.gd`.

var _failures := 0


func _initialize() -> void:
	_run()


## Um quadro antes dos testes: os que montam nós precisam da árvore pronta, e
## dentro de `_initialize` ela ainda não resolve tema — um rótulo devolvia a cor
## padrão da engine, e uma asserção de "diferente de" passava por acaso.
func _run() -> void:
	await process_frame
	_probe_fonts()
	_probe_dashed()
	_probe_palette()
	_probe_theme()
	_probe_coaster()
	_probe_paper()
	_probe_segments()
	_probe_scene_palette()
	_probe_tabs()
	_probe_seats()
	_probe_code_input()
	_probe_player_tag()
	await _probe_banner()
	_probe_rules_docs()
	_probe_table_rules()
	await _probe_rules_page()
	if _failures == 0:
		print("OK — kit de interface consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _probe_fonts() -> void:
	print("fontes")
	var body := AppTheme.font(400)
	var bold := AppTheme.font(700)
	var display := AppTheme.display()
	var mono := AppTheme.mono()
	_check(
		body is FontFile and body.resource_path.ends_with("AtkinsonHyperlegible-Regular.ttf"),
		"corpo é a Atkinson Hyperlegible"
	)
	_check(
		bold is FontFile and bold.resource_path.ends_with("AtkinsonHyperlegible-Bold.ttf"),
		"e o negrito é o arquivo negrito"
	)
	_check(display is FontVariation, "display é uma variação da Big Shoulders")
	if display is FontVariation:
		var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
		_equals(int((display as FontVariation).variation_opentype.get(tag, 0)), 900, "no peso 900")
	_check(
		mono is FontFile and mono.resource_path.ends_with("IBMPlexMono-SemiBold.ttf"),
		"mono é a IBM Plex Mono"
	)
	_check(AppTheme.legacy_font(700) is SystemFont, "a fonte antiga continua disponível para o que é protegido")
	_check(AppTheme.font(700) == AppTheme.font(700), "fontes em cache: a mesma instância a cada chamada")
	for letter: String in ["ç", "ã", "é", "ô", "Ú"]:
		var code := letter.unicode_at(0)
		_check(
			body.has_char(code) and display.has_char(code) and mono.has_char(code),
			"as três famílias têm '%s'" % letter
		)


func _probe_palette() -> void:
	print("paleta")
	_equals(AppTheme.BACKGROUND, Color("17211c"), "fundo é a lousa")
	_equals(AppTheme.ACCENT, Color("f2c029"), "destaque é o amarelo de cadeira")
	_equals(AppTheme.BOARD_LIGHT, Color("e9d8b8"), "casa clara do tabuleiro não mudou")
	_equals(AppTheme.BOARD_DARK, Color("8a5b3c"), "casa escura não mudou")
	_equals(AppTheme.BOARD_FRAME, Color("241d18"), "moldura do tabuleiro ainda não mudou")
	_equals(AppTheme.WATER, Color("223a4d"), "o mar não mudou")
	_equals(AppTheme.LAST_MOVE, Color("6fbf73"), "o último lance não mudou")
	_equals(AppTheme.PREMOVE, Color("6f9fd8"), "o lance planejado não mudou")
	var text_pairs := [
		["TEXT", AppTheme.TEXT, "BACKGROUND", AppTheme.BACKGROUND],
		["TEXT_DIM", AppTheme.TEXT_DIM, "BACKGROUND", AppTheme.BACKGROUND],
		["TEXT_DIM", AppTheme.TEXT_DIM, "SURFACE", AppTheme.SURFACE],
		["ACCENT_INK", AppTheme.ACCENT_INK, "ACCENT", AppTheme.ACCENT],
		["ACCENT", AppTheme.ACCENT, "BACKGROUND", AppTheme.BACKGROUND],
		["DANGER", AppTheme.DANGER, "BACKGROUND", AppTheme.BACKGROUND],
		["PAPER_INK", AppTheme.PAPER_INK, "PAPER", AppTheme.PAPER],
	]
	for pair: Array in text_pairs:
		var ratio := AppTheme.contrast(pair[1], pair[3])
		_check(ratio >= 4.5, "%s sobre %s legível como texto (%.1f:1)" % [pair[0], pair[2], ratio])
	var line := AppTheme.contrast(AppTheme.BACKGROUND.blend(AppTheme.LINE), AppTheme.BACKGROUND)
	_check(line >= 3.0, "LINE contorna coisa tocável (%.1f:1)" % line)


func _probe_theme() -> void:
	print("tema")
	var theme := AppTheme.build()
	for variation: String in ["PrimaryButton", "ChipButton", "ChipSelected", "AccentButton",
			"SuccessSolidButton", "DangerButton", "NavItem", "IconButton",
			"GhostButton", "Segment", "SegmentSelected"]:
		_equals(String(theme.get_type_variation_base(variation)), "Button", "%s é variação de botão" % variation)
	for variation: String in ["Display", "Title", "Subtitle", "Greeting", "SectionHeader", "Caption", "PairingCode", "Mono"]:
		_equals(String(theme.get_type_variation_base(variation)), "Label", "%s é variação de rótulo" % variation)
	for variation: String in ["Card", "QuietCard"]:
		_equals(String(theme.get_type_variation_base(variation)), "PanelContainer", "%s é variação de painel" % variation)
	_check(theme.get_font("font", "Button") == AppTheme.display(900), "botão fala com a voz do letreiro")
	_equals(theme.get_color("font_color", "PrimaryButton"), AppTheme.ACCENT_INK, "placa amarela com tinta escura")
	var plate := theme.get_stylebox("normal", "PrimaryButton") as StyleBoxFlat
	_check(plate != null and plate.border_width_bottom == AppTheme.PLATE_EDGE, "a placa tem a borda de baixo")
	var pressed := theme.get_stylebox("pressed", "PrimaryButton") as StyleBoxFlat
	_check(pressed != null and pressed.border_width_bottom == 0, "e afunda quando pressionada")
	_check(theme.get_stylebox("normal", "GhostButton") is StyleBoxDashed, "botão secundário é tracejado")
	_check(theme.get_stylebox("panel", "QuietCard") is StyleBoxDashed, "painel quieto também")
	_check(theme.get_font("font", "PairingCode") == AppTheme.mono(600), "código da sala em mono")
	_equals(theme.get_color("font_color", "SegmentSelected"), AppTheme.ACCENT_INK, "segmento marcado com tinta escura")
	_equals(theme.default_font_size, AppTheme.SIZE_BODY, "corpo em 16")


func _probe_coaster() -> void:
	print("bolacha")
	_equals(Coaster.initial_of("Casqueta"), "C", "inicial do nome")
	_equals(Coaster.initial_of("k'rec@"), "K", "maiúscula, mesmo com símbolo no nome")
	_equals(Coaster.initial_of("  bia"), "B", "espaço antes não conta")
	_equals(Coaster.initial_of("érica"), "É", "acento vira maiúsculo")
	_equals(Coaster.initial_of("@@"), "?", "sem letra, interrogação")
	_equals(Coaster.initial_of("7 Belo"), "7", "número vale")
	_equals(Coaster.ink_for(AppTheme.COASTER), AppTheme.TEXT, "tinta clara sobre a bolacha escura")
	_equals(Coaster.ink_for(AppTheme.PAPER), AppTheme.PAPER_INK, "tinta escura sobre papel")
	_equals(Coaster.ink_for(AppTheme.ACCENT), AppTheme.PAPER_INK, "e sobre o amarelo")
	var coaster := Coaster.new()
	_equals(coaster.fill, AppTheme.COASTER, "bolacha escura por padrão")
	_equals(coaster.ring, AppTheme.GOLD, "com anel de chopp")
	_check(coaster.custom_minimum_size.x >= 40.0, "e no mínimo 40 de largura")
	_equals(coaster.mouse_filter, Control.MOUSE_FILTER_IGNORE, "não rouba o toque de quem a contém")
	coaster.free()


func _probe_paper() -> void:
	print("papel")
	var host := Control.new()
	host.theme = AppTheme.shared()
	root.add_child(host)
	var paper := PaperCard.new()
	host.add_child(paper)
	var plain := Label.new()
	var caption := Label.new()
	caption.theme_type_variation = &"Caption"
	var title := Label.new()
	title.theme_type_variation = &"Title"
	paper.add_child(plain)
	paper.add_child(caption)
	paper.add_child(title)
	var box := paper.get_theme_stylebox("panel") as StyleBoxFlat
	_check(box != null and box.bg_color == AppTheme.PAPER, "fundo de papel")
	_equals(plain.get_theme_color("font_color"), AppTheme.PAPER_INK, "texto sobre papel em tinta escura")
	_equals(caption.get_theme_color("font_color"), Color(AppTheme.PAPER_INK, 0.72), "a legenda não herda o cinza da lousa")
	_equals(title.get_theme_color("font_color"), AppTheme.PAPER_INK, "nem o título, o giz")
	_check(title.get_theme_font("font") == AppTheme.display(900), "mas continua com a voz de letreiro do tema")
	paper.size = Vector2(200, 100)
	paper.tilt_degrees = -1.2
	_check(paper.pivot_offset.is_equal_approx(Vector2(100, 50)), "gira em torno do próprio centro")
	_check(is_equal_approx(paper.rotation, deg_to_rad(-1.2)), "no ângulo pedido")
	host.free()


func _probe_segments() -> void:
	print("segmentos")
	var control := SegmentedControl.new()
	root.add_child(control)
	var heard: Array[int] = []
	control.selected.connect(func(index: int) -> void: heard.append(index))
	control.setup(PackedStringArray(["Online", "Neste aparelho", "Contra bot"]), 0)
	_equals(control.segment_count(), 3, "um segmento por opção")
	_equals(control.current, 0, "começa no pedido")
	_equals(control._buttons[0].text, "ONLINE", "rótulo em maiúsculas, voz de letreiro")
	_equals(control._buttons[0].theme_type_variation, &"SegmentSelected", "o marcado é o preenchido")
	_equals(control._buttons[1].theme_type_variation, &"Segment", "e os outros não")
	control._buttons[2].pressed.emit()
	_equals(control.current, 2, "tocar troca")
	_equals(heard, [2] as Array[int], "e avisa uma vez")
	control._buttons[2].pressed.emit()
	_equals(heard.size(), 1, "tocar no marcado não avisa de novo")
	control.set_current(1)
	_equals(control.current, 1, "trocar por código funciona")
	_equals(heard.size(), 1, "sem avisar — quem trocou já sabe")
	control.setup(PackedStringArray(["Mata-mata", "Brasileira"]), 1)
	_equals(control.segment_count(), 2, "refazer troca os segmentos")
	_equals(control._row.get_child_count(), 2, "sem deixar os velhos na fileira")
	_equals(control.current, 1, "e marca o pedido")
	control.free()


## Cor de tema escrita à mão numa cena não acompanha a paleta.
##
## Os fundos das telas eram um `ColorRect` com o marrom antigo gravado no `.tscn`,
## e a troca de tokens deixou metade do app no fundo velho sem nada falhar. Este
## teste procura, nas cenas e na configuração do projeto, as cores da paleta que
## saiu.
func _probe_scene_palette() -> void:
	print("cores antigas gravadas em cena")
	var retired := {
		"fundo antigo": "0.0745098, 0.0627451, 0.054902",
		"fundo antigo (projeto)": "0.07450981, 0.0627451, 0.05490196",
		"latão antigo": "0.85098, 0.643137, 0.254902",
	}
	var files: Array[String] = ["res://project.godot"]
	for folder: String in ["res://scenes", "res://ui"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".tscn"):
				files.append("%s/%s" % [folder, file])
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for label: String in retired:
			_check(not text.contains(retired[label]), "%s sem %s" % [path.get_file(), label])


func _probe_tabs() -> void:
	print("abas")
	var tabs := AppTabs.new()
	tabs.size = Vector2(432, 64)
	tabs.current = AppTabs.GAMES
	root.add_child(tabs)
	var heard: Array[StringName] = []
	tabs.picked.connect(func(route: StringName) -> void: heard.append(route))
	_equals(tabs.route_at(Vector2(30, 30)), AppTabs.GAMES, "a esquerda é Jogos")
	_equals(tabs.route_at(Vector2(216, 30)), AppTabs.ONLINE, "o meio é Online")
	_equals(tabs.route_at(Vector2(400, 30)), AppTabs.YOU, "a direita é Você")
	tabs.pick(AppTabs.GAMES)
	_equals(heard.size(), 0, "tocar na aba em que se está não navega")
	tabs.disabled = [AppTabs.ONLINE] as Array[StringName]
	tabs.pick(AppTabs.ONLINE)
	_equals(heard.size(), 0, "nem na desabilitada")
	tabs.pick(AppTabs.YOU)
	_equals(heard, [AppTabs.YOU] as Array[StringName], "a outra avisa")
	tabs.free()
	var bar := AppBar.new()
	root.add_child(bar)
	bar.greet("Casqueta")
	_check(bar.find_children("*", "Coaster", true, false).size() == 1, "o cabeçalho de casa tem a bolacha do jogador")
	bar.leading = -1
	_check(not bar._leading_button.visible, "e as abas não têm botão de voltar")
	bar.free()
	var theme := AppTheme.build()
	_equals(String(theme.get_type_variation_base("Hint")), "Label", "Hint é variação de rótulo")
	_equals(theme.get_font_size("font_size", "Hint"), AppTheme.SIZE_BODY_S, "a dica em 14, legível")
	_equals(theme.get_color("font_color", "Hint"), AppTheme.TEXT_DIM, "e em giz apagado")


func _probe_seats() -> void:
	print("mesa de espera")
	_check(is_equal_approx(SeatTable.seat_angle(0, 4, 0), PI * 0.5), "o lugar de quem olha é embaixo")
	_check(is_equal_approx(SeatTable.seat_angle(2, 4, 2), PI * 0.5), "mesmo quando ele é o assento 2")
	_check(is_equal_approx(SeatTable.seat_angle(3, 4, 2), PI), "o seguinte fica à esquerda")
	_check(is_equal_approx(SeatTable.seat_angle(0, 4, 2), PI * 1.5), "o de frente fica em cima")
	_check(is_equal_approx(SeatTable.seat_angle(1, 4, 2), 0.0), "e o último à direita")
	var table := SeatTable.new()
	table.size = Vector2(300, 240)
	root.add_child(table)
	table.capacity = 4
	table.local_seat = 0
	table.present = PackedInt32Array([0, 1])
	table.refresh()
	_equals(table.find_children("*", "Coaster", true, false).size(), 4, "uma bolacha por cadeira")
	_equals(table.label_of(0), "Você", "a sua cadeira diz você")
	_equals(table.label_of(1), "Chegou", "a de quem já sentou diz que chegou")
	_equals(table.label_of(3), "Esperando", "e a vazia continua esperando")
	table.capacity = 6
	table.refresh()
	_equals(table.find_children("*", "Coaster", true, false).size(), 6, "trocar a lotação refaz a mesa")
	table.free()


func _probe_code_input() -> void:
	print("código em seis casas")
	_equals(CodeInput.clean("ab-12cd9"), "AB12CD", "colar limpa e corta no tamanho do código")
	_equals(CodeInput.clean("  d k 4 "), "DK4", "espaço não conta")
	var field := CodeInput.new()
	root.add_child(field)
	var heard: Array[String] = []
	field.completed.connect(func(code: String) -> void: heard.append(code))
	field.set_code("dk4")
	_equals(field.code, "DK4", "o que se digita vira maiúscula")
	_equals(heard.size(), 0, "e com menos de seis não avisa")
	field.set_code("dk4p2q")
	_equals(field.code, "DK4P2Q", "seis casas cheias")
	_equals(heard, ["DK4P2Q"] as Array[String], "avisa uma vez")
	field.set_code("dk4p2q")
	_equals(heard.size(), 1, "e não avisa de novo pelo mesmo código")
	field.clear()
	_equals(field.code, "", "limpar esvazia")
	field.free()


func _probe_player_tag() -> void:
	print("etiqueta de jogador")
	_equals(PlayerTag.material([Board.piece(Board.Side.WHITE, Board.Kind.QUEEN)]), 9, "a dama vale nove")
	_equals(
		PlayerTag.material([
			Board.piece(Board.Side.BLACK, Board.Kind.PAWN),
			Board.piece(Board.Side.BLACK, Board.Kind.ROOK),
		]), 6, "peão e torre somam seis"
	)

	var tag := PlayerTag.new()
	root.add_child(tag)
	tag.size = Vector2(320, PlayerTag.HEIGHT)
	tag.title = "Lucas"
	var coasters := tag.find_children("*", "Coaster", true, false)
	_equals(coasters.size(), 1, "a etiqueta tem uma bolacha")
	var coaster: Coaster = coasters[0]
	_equals(coaster.player_name, "Lucas", "que leva o nome de quem é")
	_check(not coaster.turn, "e começa sem o anel de vez")
	tag.active = true
	_check(coaster.turn, "a vez acende o anel")
	tag.piece = Board.piece(Board.Side.WHITE, Board.Kind.KING)
	_equals(coaster.piece, Board.piece(Board.Side.WHITE, Board.Kind.KING), "a peça entra na bolacha")

	_equals(tag.custom_minimum_size.y, PlayerTag.HEIGHT, "a faixa é a alta")
	tag.shape = PlayerTag.Shape.TAG
	_equals(tag.custom_minimum_size.y, PlayerTag.HEIGHT_TAG, "a etiqueta ancorada é a baixa")

	# Modo mesa: quem joga do outro lado do aparelho lê a própria faixa de lá.
	tag.upside_down = true
	_check(is_equal_approx(tag.rotation, PI), "o lado de cima vira de ponta-cabeça")
	tag.free()


## O aviso é posicionado pela cena, por âncora e offset — a Metrópole o desce
## para baixo da barra translúcida. A animação de entrada reescrevia `position`, e
## depois do primeiro aviso ele morava em y = 0, embaixo da barra.
func _probe_banner() -> void:
	print("aviso")
	var stage := Control.new()
	stage.size = Vector2(432, 400)
	root.add_child(stage)
	var banner := Banner.new()
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 50.0
	banner.offset_bottom = 110.0
	stage.add_child(banner)
	banner.show_message("Fulano pagou M 20 a Beltrano.")
	await create_timer(0.4).timeout
	_equals(banner.offset_top, 50.0, "o aviso continua onde a cena o pôs")
	stage.free()


## Os oito jogos do catálogo, na ordem dele. Escritos à mão, e não lidos do
## `Game`: o kit roda sem autoload — e uma lista à mão também é o que pega o jogo
## novo que entrar no catálogo sem regras.
const RULED_GAMES: Array[StringName] = [
	&"chess", &"checkers", &"battleship", &"ludo",
	&"monopoly", &"uno", &"pool", &"bomberman",
]


func _probe_rules_docs() -> void:
	print("como jogar")
	for id in RULED_GAMES:
		var doc := GameRulesDoc.load_for(id)
		_check(doc != null, "%s tem regras" % id)
		if doc == null:
			continue
		_check(not doc.title.is_empty() and not doc.objective.is_empty(), "%s tem título e objetivo" % id)
		if doc.formats.is_empty():
			_check(doc.steps.size() >= 3, "%s tem passos" % id)
			continue
		for block in doc.formats:
			_check(
				not block.objective.is_empty() and block.steps.size() >= 3,
				"%s, %s, tem objetivo e passos" % [id, block.title]
			)
	var pool := GameRulesDoc.load_for(&"pool")
	_equals(pool.formats.size(), 2, "a sinuca tem os dois formatos")
	_check(GameRulesDoc.load_for(&"nao-existe") == null, "jogo sem regras devolve nada, e não erro")


func _probe_table_rules() -> void:
	print("regras desta mesa")
	var state_of := func(rows: Array[Dictionary], label: String) -> String:
		for row in rows:
			if row["label"] == label:
				return str(row["state"])
		return ""

	var uno_on := TableRules.for_game(&"uno", {"sevens": true})
	var uno_off := TableRules.for_game(&"uno", {"sevens": false})
	_equals(state_of.call(uno_on, "0 e 7"), "ligada", "o 0 e o 7 da mesa ligado")
	_equals(state_of.call(uno_off, "0 e 7"), "desligada", "e desligado")
	# O número sai da constante da regra: mudar a multa em `core/` muda o texto.
	_equals(
		state_of.call(uno_on, "Esquecer o UNO"), "+%d cartas" % UnoRules.CATCH_PENALTY,
		"a multa do grito vem da regra"
	)
	var brazilian := TableRules.for_game(&"pool", {"format": PoolRules.Format.BRAZILIAN})
	_equals(state_of.call(brazilian, "Formato"), "brasileira", "a sinuca reflete o formato")
	_check(
		state_of.call(brazilian, "Falta").begins_with(str(PoolRules.FOUL_POINTS)),
		"a falta da brasileira vale os pontos da regra"
	)
	var knockout := TableRules.for_game(&"pool", {"format": PoolRules.Format.KNOCKOUT})
	_equals(state_of.call(knockout, "Falta"), "passa a vez", "no mata-mata a falta passa a vez")
	_equals(
		state_of.call(TableRules.for_game(&"monopoly", {"round_limit": 20}), "Fim"),
		"20 rodadas, maior patrimônio", "Metrópole mostra o limite de rodadas"
	)
	for id in RULED_GAMES:
		_check(not TableRules.for_game(id, {}).is_empty(), "%s tem regras da mesa" % id)


func _probe_rules_page() -> void:
	print("página de regras")
	var stage := Control.new()
	stage.size = Vector2(432, 768)
	root.add_child(stage)

	var page := RulesPage.open(stage, &"pool", 1)
	await process_frame
	_check(page.is_in_group(&"back_layer"), "a página entra na fila do gesto de voltar")
	_check(page._segments.visible, "a sinuca abre com as abas de formato")
	_equals(page.format, 1, "no formato pedido")
	var brazilian_goal: String = (page._content.get_child(0) as Label).text
	page._on_format(0)
	await process_frame
	var knockout_goal: String = (page._content.get_child(0) as Label).text
	_equals(knockout_goal, page.doc.formats[0].objective, "trocar de formato mostra o objetivo do outro")
	_check(knockout_goal != brazilian_goal, "e os dois formatos não dizem a mesma coisa")
	page.dismiss()
	await process_frame
	_check(not is_instance_valid(page), "fechar tira a página da árvore")

	var chess := RulesPage.open(stage, &"chess")
	await process_frame
	_check(not chess._segments.visible, "jogo de um formato só não tem abas")
	chess.dismiss()

	var drawer := TableRulesDrawer.open(
		stage, &"uno", TableRules.for_game(&"uno", {"sevens": true})
	)
	await process_frame
	_equals(drawer._list.get_child_count(), 4, "a gaveta tem uma linha por regra da mesa")
	var full := drawer.open_full()
	await process_frame
	_check(not is_instance_valid(drawer), "a página completa substitui a gaveta")
	_equals(full.doc.title, "Uno", "e abre as regras do mesmo jogo")
	full.dismiss()
	await process_frame
	stage.free()


func _probe_dashed() -> void:
	print("tracejado")
	var rounded := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 40), 10.0)
	_equals(rounded.size(), 4 * (StyleBoxDashed.CORNER_STEPS + 1), "um arco de pontos por canto")
	_check(rounded[0].is_equal_approx(Vector2(90, 0)), "o contorno começa no fim da aresta de cima")
	var inside := true
	for point in rounded:
		inside = inside and Rect2(0, 0, 100, 40).grow(0.001).has_point(point)
	_check(inside, "e nenhum ponto sai do retângulo")
	var clamped := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 40), 50.0)
	_check(clamped[0].is_equal_approx(Vector2(80, 0)), "raio maior que meia altura é limitado a ela")
	var square := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 100), 0.0)
	_equals(square.size(), 4, "sem raio, um ponto por canto")
	var dashes := StyleBoxDashed.dash_segments(square, 10.0, 10.0)
	_equals(dashes.size() % 2, 0, "os traços vêm em pares")
	_check(absf(_drawn(dashes) - 200.0) < 0.01, "metade do perímetro desenhada com traço e vão iguais (obtido %.2f)" % _drawn(dashes))
	var longest := 0.0
	for i in range(0, dashes.size(), 2):
		longest = maxf(longest, dashes[i].distance_to(dashes[i + 1]))
	_check(longest <= 10.0001, "nenhum traço maior que o pedido")
	var solid := StyleBoxDashed.dash_segments(square, 10.0, 0.0)
	_check(absf(_drawn(solid) - 400.0) < 0.01, "sem vão, o contorno inteiro")


static func _drawn(segments: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(0, segments.size(), 2):
		total += segments[i].distance_to(segments[i + 1])
	return total


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
