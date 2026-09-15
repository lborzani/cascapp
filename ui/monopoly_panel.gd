class_name MonopolyPanel
extends PanelContainer

## O painel flutuante da direita: a escritura da casa em foco, e a porta para as
## suas propriedades.
##
## Ele responde **duas** perguntas com a mesma superfície, e isso é de propósito:
##
## - "onde eu caí?" — a casa em que o peão da vez está, com o aluguel inteiro,
##   preço de construção e valor de hipoteca. É a pergunta do momento seguinte a
##   uma rolagem, e é o que o tampo não tem espaço para dizer;
## - "o que eu tenho?" — a lista das suas escrituras, de onde se abre qualquer
##   uma para construir ou hipotecar.
##
## Duas superfícies separadas custariam duas navegações num celular deitado, e as
## duas mostram a mesma coisa: uma escritura. O que muda é como se chegou nela.
##
## Ele **flutua** sobre o tabuleiro em vez de ocupar uma coluna própria. O
## tabuleiro é quadrado e a tela é deitada: reservar uma terceira coluna
## encolheria o tabuleiro para caber num espaço que fica vazio a maior parte do
## tempo, enquanto o canto de cima à direita do tabuleiro em perspectiva é a área
## menos usada da tela.

## A casa a mostrar mudou porque alguém escolheu na lista.
signal tile_chosen(tile: int)
## Construir, vender, hipotecar ou resgatar. A tela decide se o lance é legal —
## o painel só pede.
signal action_requested(action: int, tile: int)

const ROW_HEIGHT := 14
## Largura reservada à barra de rolagem do corpo. Ver a canaleta em [method
## _ready].
const SCROLL_GUTTER := 10
## Largura do painel, e ela é **fixa**.
##
## Duzentos, e não os 168 da barra de baixo. Ele é o bloco que carrega **texto** —
## nome de casa, cidade, uma tabela de aluguel de seis degraus e, nas casas de
## evento, uma frase inteira —, e a 168 quase tudo isso quebrava em duas ou três
## linhas. A barra não precisa da mesma largura: ela tem dois dados e um botão, e
## alargá-la junto só tiraria tabuleiro à toa.
##
## O teto é o tabuleiro. O palco tem uns 608 de largura na base deitada, então 200
## é um terço dele — e como o painel flutua sobre o canto de cima à direita, que é
## a área menos usada de um tabuleiro em perspectiva, o que ele cobre a mais são
## trinta e dois pixels de uma região que já estava vazia. Acima disso ele começa a
## comer a fileira do fundo, e aí a conta se inverte.
##
## Fixa e não "o que o conteúdo pedir": o conteúdo muda a cada casa — de uma
## frase inteira num "Descanso" a onze linhas numa propriedade com a tabela toda —
## e um painel que muda de largura ao trocar de casa arrasta o olho para o lado a
## cada rolagem de dado.
##
## Mora aqui e não na cena porque manter o número em dois lugares é o que fazia a
## cena reservar 168 enquanto o painel pedia 150: o maior dos dois ganhava, e
## qual era o maior dependia do texto da casa aberta.
##
## Escrever a largura, porém, **não basta** — e foi assim que ela escapou. Um
## `Control` nunca desenha menor que o mínimo que o conteúdo dele pede, e o
## `ScrollContainer` de dentro repassa a largura mínima do filho porque a rolagem
## horizontal está desligada. Bastava uma linha de texto sem quebra para o painel
## inteiro esticar. Quem segura isso são os rótulos: os de frase quebram, os de
## tabela cortam com reticências. Ver [method _line].
const WIDTH := 200
## Meia respiração do botão em destaque. Ida e volta dão pouco mais de um segundo
## e meio — mais rápido que isso lê como alerta, e alerta é o que o vermelho faz.
const PULSE_SECONDS := 0.8
## Alcance do halo, em pixels, e o quanto ele chega a acender.
##
## Seis, e não mais: a barra dá 8 de folga em volta dos botões, e um halo maior
## que isso encosta na borda arredondada dela. Entre dois botões empilhados a folga
## é de 4 — o halo passa por trás do vizinho, que é opaco e o esconde, e o que
## sobra visível é o brilho no vão. É o efeito certo pelo caminho mais barato.
const HALO_SIZE := 6
const HALO_ALPHA := 0.55

var state: MatchState = null
## Quem está olhando. Decide de quem é a lista de propriedades e quais ações
## aparecem — em rede é o assento local, no mesmo aparelho é o jogador da vez.
var viewer := 0
## Casa mostrada agora.
var tile := -1
## A lista de propriedades está aberta no lugar da escritura.
var listing := false
## De quem é a lista aberta, ou -1 para a de quem está olhando.
##
## Existe porque "o que o outro tem" é a pergunta que decide se vale a pena
## propor uma troca, e ela não tinha resposta: a coluna da esquerda diz **quantas**
## escrituras cada um tem, e o número sozinho não diz se são de um grupo fechado
## ou três casas soltas de cidades diferentes — que é a diferença entre um
## adversário perigoso e um jogador com dinheiro parado.
##
## A lista de outro é só de leitura, e isso sai de graça: os botões de construir e
## hipotecar já dependem de a escritura aberta ser de quem olha.
var listing_of := -1
## Quem está olhando pode agir agora.
##
## No mesmo aparelho isto é sempre verdade quando é a vez de quem olha — e quem
## olha **é** quem joga. Em rede não: o painel mostra as suas escrituras o tempo
## todo, inclusive enquanto outro joga, e sem isto ele ofereceria "Construir"
## para um lance que as regras vão recusar. Um botão que existe e não funciona é
## pior que a ausência dele, que é a regra do resto desta tela.
var acting := true

## Como cada jogador é chamado. Vem de fora: quem sabe o nome guardado no
## aparelho, o que chegou pela rede e quais cadeiras são máquina é a cena da
## partida — a mesma resposta que a coluna da esquerda e a mesa de troca já usam.
##
## O padrão responde pelo número do assento, e era o que a escritura mostrava
## sempre: "Jogador 4" ao lado de uma barra da cor dele, com a barra de baixo
## dizendo "Vez de Cascão." na mesma tela. Duas respostas para "quem é o jogador
## 4" é uma delas estar errada.
var _labeler: Callable = func(player: int) -> String: return "Jogador %d" % (player + 1)

var _title: Label = null
var _city: Label = null
var _band: ColorRect = null
var _body: VBoxContainer = null
var _actions: VBoxContainer = null
var _toggle: Button = null


func _ready() -> void:
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel", AppTheme.box(
		Color(AppTheme.SURFACE, 0.96), AppTheme.RADIUS_LARGE, AppTheme.BORDER, 1
	))

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	# O cabeçalho **quebra**, e não corta.
	#
	# A primeira correção da largura cortava com reticências, e "Imposto de Ren…"
	# é o nome da casa pela metade — justamente o dado que o painel existe para
	# responder. Quebrar em duas linhas custa uns pixels de altura, e a altura o
	# painel tem de sobra: o corpo dele rola.
	#
	# Notar que só as reticências não bastariam: o comportamento de transbordo
	# decide o que **desenhar** quando falta espaço, e não faz o rótulo parar de
	# pedir a largura da frase inteira. Quem tira o pedido é a quebra.
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 14)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)

	_city = Label.new()
	_city.add_theme_font_size_override("font_size", 11)
	_city.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_city.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_city)

	_band = ColorRect.new()
	_band.custom_minimum_size.y = 4
	column.add_child(_band)

	# O corpo rola; o cabeçalho e os botões não.
	#
	# O conteúdo varia de uma linha ("Descanso: não acontece nada") a onze (uma
	# propriedade com a tabela inteira), e o painel tem altura fixa. Sem a rolagem
	# a escritura mais longa empurrava os botões para fora da tela — e são eles
	# que fazem a coisa acontecer.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	# Uma canaleta para a barra de rolagem, sempre reservada.
	#
	# O `ScrollContainer` desenha a barra **por cima** do conteúdo quando a largura
	# mínima do filho já ocupa a faixa toda, e a coluna de valores da direita é
	# exatamente o que fica embaixo: numa propriedade com a tabela inteira, o "200"
	# do preço saía com a barra atravessada no último algarismo. Ler um aluguel
	# errado por causa de um pixel de barra é o pior tipo de defeito de tela —
	# silencioso e plausível.
	#
	# Reservada **sempre**, e não só quando a barra aparece: uma canaleta que nasce
	# e some faz a coluna de números pular para o lado a cada troca de casa, e o
	# olho segue o pulo em vez de ler o número.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", SCROLL_GUTTER)
	scroll.add_child(gutter)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 2)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(_body)

	# Empilhados, e não lado a lado. O painel tem 168 de largura e o par
	# "Construir | Vender" dividido em dois cortava os dois rótulos no meio — um
	# botão escrito "Co" não é um botão. Em coluna cada um recebe a largura
	# inteira, que é o que o texto precisa.
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	column.add_child(_actions)

	_toggle = Button.new()
	compact(_toggle)
	_toggle.pressed.connect(_on_toggle)
	column.add_child(_toggle)


## Como chamar cada jogador. Ver [member _labeler].
func naming(labeler: Callable) -> void:
	_labeler = labeler


func refresh() -> void:
	if state == null or not is_node_ready():
		return
	for child in _body.get_children():
		child.queue_free()
	for child in _actions.get_children():
		child.queue_free()

	if listing:
		_show_holdings()
	else:
		_show_deed()

	var owned := MonopolyRules.deeds_of(state, viewer).size()
	_toggle.text = "Ver a casa" if listing else "Propriedades"
	_toggle.disabled = owned == 0 and not listing


## Assento cuja lista está aberta. O de quem olha, a menos que alguém tenha
## tocado numa faixa da coluna.
func _listed() -> int:
	return listing_of if listing_of >= 0 else viewer


func _on_toggle() -> void:
	listing = not listing
	# Sair da lista desfaz a visita: reabri-la depois tem de voltar às **suas**
	# propriedades, que é o que o botão promete. Sem isto o painel guardava o
	# último jogador espiado e o botão "Propriedades" abria a lista de outro.
	if not listing:
		listing_of = -1
	refresh()


# --- a escritura --------------------------------------------------------------


func _show_deed() -> void:
	if tile < 0:
		_title.text = "Nenhuma casa"
		_city.text = ""
		_band.color = Color(0, 0, 0, 0)
		return

	_title.text = MonopolyBoard.display_name(tile)
	var city := MonopolyBoard.city_of(tile)
	_city.text = city if not city.is_empty() else _kind_label(tile)
	var group := MonopolyBoard.group_of(tile)
	_band.color = (
		MonopolyBoard.GROUP_COLORS[group]
		if group != MonopolyBoard.Group.NONE
		else Color(AppTheme.BORDER, 0.8)
	)

	if not MonopolyBoard.is_deed(tile):
		_line(_event_text(tile), AppTheme.TEXT_DIM)
		return

	_line("Preço", AppTheme.TEXT_DIM, str(MonopolyBoard.price_of(tile)))
	_owner_line()
	_rent_rows()

	if MonopolyBoard.can_build_on(tile):
		_line("Casa / hotel", AppTheme.TEXT_DIM, str(MonopolyBoard.house_cost(tile)))
	_line("Hipoteca", AppTheme.TEXT_DIM, str(MonopolyBoard.mortgage_value(tile)))
	_build_actions()


## A tabela de aluguel inteira, e não só o valor de agora.
##
## O valor de agora responde "quanto eu pago", que a tela já vai cobrar sozinha.
## A tabela responde "vale a pena construir aqui", que é a única decisão de
## verdade que este jogo oferece, e não dá para tomá-la de cabeça.
func _rent_rows() -> void:
	match MonopolyBoard.kind_of(tile):
		MonopolyBoard.Tile.PROPERTY:
			var table: Array = MonopolyBoard.tile(tile)["rent"]
			var built := MonopolyRules.houses_on(state, tile)
			for step in table.size():
				var label := "Aluguel"
				if step == MonopolyBoard.HOTEL:
					label = "Hotel"
				elif step > 0:
					label = "%d casa%s" % [step, "" if step == 1 else "s"]
				# O degrau em que a casa está agora fica aceso; os outros são
				# projeção. Sem isso a tabela é uma lista de números sem presente.
				_line(label, AppTheme.TEXT if step == built else AppTheme.TEXT_DIM, str(table[step]))
		MonopolyBoard.Tile.AIRPORT:
			for count in MonopolyBoard.AIRPORT_RENT.size():
				_line(
					"%d aeroporto%s" % [count + 1, "" if count == 0 else "s"],
					AppTheme.TEXT_DIM, str(MonopolyBoard.AIRPORT_RENT[count])
				)
		MonopolyBoard.Tile.UTILITY:
			for count in MonopolyBoard.UTILITY_MULTIPLIER.size():
				_line(
					"%d companhia%s" % [count + 1, "" if count == 0 else "s"],
					AppTheme.TEXT_DIM, "%dx o dado" % MonopolyBoard.UTILITY_MULTIPLIER[count]
				)


func _owner_line() -> void:
	var landlord := MonopolyRules.owner_of(state, tile)
	if landlord == MonopolyRules.NO_OWNER:
		_line("Sem dono", AppTheme.SUCCESS)
		return
	var color: Color = MonopolyFace.PLAYER_COLORS[landlord % MonopolyFace.PLAYER_COLORS.size()]
	var text: String = _labeler.call(landlord)
	if landlord == viewer:
		text = "Sua"
	if MonopolyRules.is_mortgaged(state, tile):
		text += " · hipotecada"
	_line(text, color)


## Os botões só existem quando o lance existe. Um botão cinza que nunca acende
## ensina a ignorar a fileira inteira; a ausência dele já diz por que não dá.
func _build_actions() -> void:
	if not acting or MonopolyRules.owner_of(state, tile) != viewer:
		return
	if MonopolyRules.is_mortgaged(state, tile):
		_action("Resgatar %d" % MonopolyBoard.unmortgage_cost(tile), MonopolyRules.Act.UNMORTGAGE)
		return
	if MonopolyBoard.can_build_on(tile):
		_action("Construir", MonopolyRules.Act.BUILD)
		if MonopolyRules.houses_on(state, tile) > 0:
			_action("Vender", MonopolyRules.Act.SELL)
	if MonopolyRules.houses_on(state, tile) == 0:
		_action("Hipotecar", MonopolyRules.Act.MORTGAGE)


func _action(label: String, act: int) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compact(button)
	var chosen := tile
	button.pressed.connect(func() -> void: action_requested.emit(act, chosen))
	_actions.add_child(button)


# --- a lista ------------------------------------------------------------------


## As suas escrituras, na ordem do tabuleiro. Na ordem do tabuleiro e não por
## valor: é assim que elas estão na cabeça de quem jogou a partida, e é assim que
## as três de uma cidade aparecem juntas — que é a informação que interessa,
## porque grupo fechado é o que constrói.
func _show_holdings() -> void:
	var seat := _listed()
	var mine := seat == viewer
	_title.text = "Suas propriedades" if mine else _labeler.call(seat)
	_city.text = "M %d em caixa" % MonopolyRules.cash_of(state, seat)
	# O caixa de outro jogador é informação aberta: a coluna da esquerda já o
	# mostra o tempo todo, e esconder aqui o que está visível ali seria só
	# incoerência.
	var kept := MonopolyRules.jail_cards_of(state, seat)
	if kept > 0:
		_city.text += "  ·  %d saída livre" % kept if kept == 1 else "  ·  %d saídas livres" % kept
	_band.color = MonopolyFace.PLAYER_COLORS[seat % MonopolyFace.PLAYER_COLORS.size()]

	var owned := MonopolyRules.deeds_of(state, seat)
	if owned.is_empty():
		_line(
			"Você ainda não comprou nada." if mine else "Ainda não comprou nada.",
			AppTheme.TEXT_DIM
		)
		return
	for owned_tile in owned:
		_holding_row(owned_tile)


func _holding_row(owned_tile: int) -> void:
	var row := Button.new()
	compact(row)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = MonopolyBoard.short_name(owned_tile)
	# O estado da propriedade cabe num sufixo curto: construções ou hipoteca.
	# Uma segunda linha por escritura faria a lista de vinte itens não caber.
	var built := MonopolyRules.houses_on(state, owned_tile)
	if MonopolyRules.is_mortgaged(state, owned_tile):
		row.text += "  ·  hip."
	elif built >= MonopolyBoard.HOTEL:
		row.text += "  ·  hotel"
	elif built > 0:
		row.text += "  ·  %d" % built
	var group := MonopolyBoard.group_of(owned_tile)
	if group != MonopolyBoard.Group.NONE:
		row.add_theme_color_override("font_color", MonopolyBoard.GROUP_COLORS[group])
	row.pressed.connect(func() -> void:
		listing = false
		listing_of = -1
		tile_chosen.emit(owned_tile)
	)
	_body.add_child(row)


# --- utilidades ---------------------------------------------------------------


## Encolhe um botão para o passo deste painel.
##
## O tema do app foi escrito para botões de tela cheia — a folga vertical dele é
## generosa de propósito, para o dedo achar o alvo num menu. Aqui, três botões
## com essa folga comem metade dos 296 de altura e não sobra nada para a tabela
## de aluguel, que é o conteúdo. A altura mínima continua sendo tocável; o que
## sai é o ar em volta do texto.
static func compact(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 12)
	button.clip_text = true
	button.custom_minimum_size.y = 26
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var fill := Color(AppTheme.SURFACE_HIGH, 0.55 if state_name == "disabled" else 1.0)
		if state_name == "hover" or state_name == "pressed":
			fill = Color(AppTheme.ACCENT, 0.22)
		var style := AppTheme.box(fill, AppTheme.RADIUS, Color(AppTheme.BORDER, 0.9), 1)
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		style.content_margin_left = 8
		style.content_margin_right = 8
		button.add_theme_stylebox_override(state_name, style)


## Marca o botão que **é** a ação da fase: latão cheio, e pulsando.
##
## Os botões da barra saem todos de `compact()`, que os deixa da cor da superfície
## — e numa fase de três ("Rolar", "Usar saída livre", "Pagar fiança") isso são
## três retângulos cinzas iguais, sem nada dizendo por onde se sai do normal. O
## latão cheio é o que o tema já reserva para "a ação da tela", e existe **um** por
## barra, que é o mesmo limite da regra escrita em [app_theme.gd].
##
## O pulso é para o outro caso: a barra tem 112 de altura no canto de baixo à
## direita de uma tela deitada, e o olho de quem acabou de ver o peão andar está no
## meio do tabuleiro. Cor parada não traz o olho de volta; movimento traz.
##
## O movimento é um **halo**: um brilho da cor do latão que acende e apaga em volta
## do botão, sem que o botão saia do lugar. A primeira versão respirava em brilho e
## em escala, e a escala era o defeito — um alvo de toque que muda de tamanho
## sozinho é um alvo que escapa do dedo, e numa fileira de três botões o vizinho
## parecia empurrado a cada respiração. O halo cresce para **fora**, onde não há
## nada para deslocar.
##
## O `Tween` nasce do próprio botão, então ele morre junto: a barra é refeita a
## cada mudança de fase, e um pulso órfão continuaria animando um nó liberado.
static func highlight(button: Button) -> void:
	var resting: StyleBoxFlat = null
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var fill := AppTheme.ACCENT
		if state_name == "hover":
			fill = AppTheme.ACCENT.lightened(0.12)
		elif state_name == "pressed":
			fill = AppTheme.ACCENT.darkened(0.15)
		elif state_name == "disabled":
			fill = Color(AppTheme.ACCENT, 0.4)
		var style := AppTheme.box(fill, AppTheme.RADIUS)
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		style.content_margin_left = 8
		style.content_margin_right = 8
		if state_name == "normal":
			resting = style
		button.add_theme_stylebox_override(state_name, style)
	# Texto escuro sobre o latão: o claro do tema some no preenchimento.
	for slot in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(slot, AppTheme.BACKGROUND)

	# O halo é a sombra do próprio `StyleBoxFlat`, sem deslocamento: ela cresce
	# para os quatro lados a partir da borda, que é exatamente a forma de um halo.
	# Desenhá-lo à mão pediria um nó a mais e um `_draw` só para isso.
	#
	# `tween_method` e não `tween_property`, e o `queue_redraw` é escrito na mão:
	# quem muda aqui é um recurso, não o nó, e depender do aviso de mudança dele
	# chegar ao `Control` é depender de um encadeamento que falha em silêncio — o
	# halo ficaria parado no valor inicial sem nada acusar.
	var halo := func(amount: float) -> void:
		if not is_instance_valid(button):
			return
		resting.shadow_size = int(roundf(HALO_SIZE * amount))
		resting.shadow_color = Color(AppTheme.ACCENT, HALO_ALPHA * amount)
		button.queue_redraw()

	# Um `Tween` só, com os dois passos em sequência — que é o padrão, e por isso
	# funciona. A versão anterior tentou juntar duas propriedades com
	# `set_parallel()` e separar ida de volta com `chain()`: `chain()` vale para o
	# tweener seguinte e o `set_parallel(true)` logo depois o desfazia, então os
	# quatro passos rodavam juntos e o efeito se anulava.
	var pulse := button.create_tween().set_loops()
	pulse.tween_method(halo, 0.0, 1.0, PULSE_SECONDS).set_trans(Tween.TRANS_SINE)
	pulse.tween_method(halo, 1.0, 0.0, PULSE_SECONDS).set_trans(Tween.TRANS_SINE)


## Uma linha do corpo: um rótulo à esquerda e, às vezes, um número à direita.
##
## As duas formas seguram a largura do painel de jeitos diferentes, e é por isso
## que a distinção é feita aqui e não deixada para quem chama:
##
## - **sem número** é uma frase — "Não acontece nada. É o único lugar do tabuleiro
##   assim." Ela **quebra**. Cortar uma explicação com reticências seria esconder
##   metade do que ela existe para dizer;
## - **com número** é linha de tabela, e o número é o que importa. O rótulo
##   **corta**: "Aluguel" cabe, e um rótulo longo que quebrasse desalinharia a
##   coluna de valores, que é o que se lê de cima a baixo.
##
## Sem uma das duas, o rótulo pede a largura do texto inteiro, o `ScrollContainer`
## repassa esse mínimo, e o painel estica — que foi exatamente o que aconteceu.
func _line(label: String, color: Color, value := "") -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var left := Label.new()
	left.text = label
	left.add_theme_font_size_override("font_size", 12)
	left.add_theme_color_override("font_color", color)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if value.is_empty():
		left.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		left.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		left.clip_text = true
	row.add_child(left)
	if not value.is_empty():
		var right := Label.new()
		right.text = value
		right.add_theme_font_size_override("font_size", 12)
		right.add_theme_color_override("font_color", color)
		row.add_child(right)
	_body.add_child(row)


func _kind_label(index: int) -> String:
	match MonopolyBoard.kind_of(index):
		MonopolyBoard.Tile.AIRPORT:
			return "Aeroporto"
		MonopolyBoard.Tile.UTILITY:
			return "Companhia"
		MonopolyBoard.Tile.CHANCE:
			return "Sorte"
		MonopolyBoard.Tile.CHEST:
			return "Cofre"
		MonopolyBoard.Tile.TAX:
			return "Imposto"
		_:
			return ""


func _event_text(index: int) -> String:
	match MonopolyBoard.kind_of(index):
		MonopolyBoard.Tile.GO:
			return "Passar por aqui paga %d." % MonopolyBoard.GO_SALARY
		MonopolyBoard.Tile.JAIL:
			return "Só de visita, a menos que você tenha sido mandado para cá."
		MonopolyBoard.Tile.PARKING:
			return "Não acontece nada. É o único lugar do tabuleiro assim."
		MonopolyBoard.Tile.GOTO_JAIL:
			return "Vá para a cadeia sem passar pela Partida."
		MonopolyBoard.Tile.TAX:
			return "Pague %d ao banco." % int(MonopolyBoard.tile(index).get("amount", 0))
		MonopolyBoard.Tile.CHANCE, MonopolyBoard.Tile.CHEST:
			return "Tire uma carta e faça o que ela mandar."
		_:
			return ""
