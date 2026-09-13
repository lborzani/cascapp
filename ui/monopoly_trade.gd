class_name MonopolyTrade
extends PanelContainer

## A mesa de troca: quem, o quê, e por quanto.
##
## É a única superfície do jogo que ocupa a tela inteira, e é de propósito. Uma
## troca é a jogada mais cara de montar em Metrópole — duas listas de escrituras e
## um valor —, e o painel flutuante da partida tem 168 de largura. Tentar montá-la
## ali seria rolar duas listas dentro de uma coluna.
##
## ## As duas metades são a mesma tela
##
## Quem propõe monta; quem recebe lê e responde. As duas coisas mostram
## exatamente o mesmo: o que sai, o que entra, e o dinheiro. O que muda é se as
## linhas aceitam toque e o que os botões do rodapé dizem.
##
## Duas telas separadas custariam duas montagens e uma delas ficaria para trás na
## primeira mudança de regra — e a pergunta "estou vendo a mesma proposta que ele
## montou?" é justamente a que quem responde precisa poder confiar.
##
## ## As colunas são sempre do ponto de vista de quem propõe
##
## "Sai" é o que sai das mãos de quem propôs, mesmo na tela de quem responde. É a
## mesma direção do lance `[OFFER, …]`, e inverter a leitura para o destinatário
## faria a tela e o histórico contarem a mesma troca ao contrário.
## O rótulo diz o nome de cada um, então não sobra ambiguidade sobre de quem é a
## coluna.

## O jogador montou uma proposta e quer mandá-la. O caminho já vem no formato de
## `Act.OFFER`; quem decide se é legal são as regras, não esta tela.
signal proposed(path: PackedInt32Array)
## A resposta de quem recebeu.
signal answered(accepted: bool)
## Fechou sem propor nada.
signal dismissed

## Passos do dinheiro. Dois tamanhos porque as duas escalas existem: acertar um
## troco de 20 e cobrir a diferença de uma cor de 500.
const CASH_STEPS := [-100, -10, 10, 100]

var _state: MatchState = null
var _proposer := 0
var _partner := -1
var _cash := 0
var _give := PackedInt32Array()
var _get := PackedInt32Array()
var _reviewing := false

var _title: Label = null
var _subtitle: Label = null
var _partners: HBoxContainer = null
var _give_head: Label = null
var _get_head: Label = null
var _give_list: VBoxContainer = null
var _get_list: VBoxContainer = null
var _cash_label: Label = null
var _cash_row: HBoxContainer = null
var _footer: HBoxContainer = null
## Como cada jogador é chamado. Vem de fora: quem sabe o nome guardado no
## aparelho e quais cadeiras são máquina é a cena da partida.
var _labeler: Callable = func(player: int) -> String: return "Jogador %d" % (player + 1)


func _ready() -> void:
	custom_minimum_size = Vector2(560, 340)
	add_theme_stylebox_override("panel", AppTheme.box(
		AppTheme.SURFACE, AppTheme.RADIUS_LARGE, AppTheme.BORDER, 1
	))

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subtitle)

	_partners = HBoxContainer.new()
	_partners.add_theme_constant_override("separation", 6)
	column.add_child(_partners)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	column.add_child(columns)

	_give_head = Label.new()
	_give_list = VBoxContainer.new()
	columns.add_child(_side_column(_give_head, _give_list))

	_get_head = Label.new()
	_get_list = VBoxContainer.new()
	columns.add_child(_side_column(_get_head, _get_list))

	_cash_label = Label.new()
	_cash_label.add_theme_font_size_override("font_size", 13)
	_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_cash_label)

	_cash_row = HBoxContainer.new()
	_cash_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cash_row.add_theme_constant_override("separation", 6)
	column.add_child(_cash_row)
	for step in CASH_STEPS:
		var button := Button.new()
		button.text = "%+d" % step
		MonopolyPanel.compact(button)
		button.custom_minimum_size.x = 62
		button.pressed.connect(_bump_cash.bind(step))
		_cash_row.add_child(button)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	column.add_child(_footer)


## Uma coluna de escrituras com o seu cabeçalho, rolável.
##
## Rolável porque a lista cresce sem teto — no fim de uma partida um jogador pode
## ter vinte escrituras — e a altura da mesa é a da tela deitada, que é o que ela
## é.
func _side_column(head: Label, list: VBoxContainer) -> Control:
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 4)

	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	holder.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(scroll)

	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return holder


## Como chamar cada jogador. A cena da partida já responde isso para a coluna da
## esquerda, e duas respostas para "quem é o jogador 2" é onde uma delas vira
## "Bot 2" e a outra "Jogador 2" na mesma tela.
func naming(labeler: Callable) -> void:
	_labeler = labeler


# --- montar -------------------------------------------------------------------


## Abre em branco para o jogador da vez montar uma proposta.
func compose(state: MatchState, proposer: int) -> void:
	_state = state
	_proposer = proposer
	_reviewing = false
	_cash = 0
	_give = PackedInt32Array()
	_get = PackedInt32Array()
	_partner = -1
	for other in MonopolyRules.alive_players(state):
		if other != proposer:
			_partner = other
			break
	_rebuild()


## Abre a proposta que está na mesa, para quem recebeu responder.
func review(state: MatchState) -> void:
	_state = state
	_proposer = MonopolyRules.turn_of(state)
	_partner = MonopolyRules.offer_to(state)
	_reviewing = true
	_cash = MonopolyRules.offer_cash(state)
	_give = MonopolyRules.offer_give(state)
	_get = MonopolyRules.offer_get(state)
	_rebuild()


## Está mostrando uma proposta alheia, e não montando uma.
##
## A cena precisa distinguir os dois para saber quando fechar sozinha: uma
## revisão morre quando a proposta sai da mesa; uma montagem em curso não deve
## fechar porque a fase mudou por baixo dela.
func is_reviewing() -> bool:
	return _reviewing


func _rebuild() -> void:
	if _state == null or not is_node_ready():
		return
	_title.text = "Proposta de troca" if _reviewing else "Propor troca"
	_subtitle.text = (
		"%s quer negociar com você." % _labeler.call(_proposer)
		if _reviewing
		else "Escolha com quem, o que sai, o que entra e a diferença em dinheiro."
	)

	_build_partners()
	_give_head.text = "Sai de %s" % _labeler.call(_proposer)
	_get_head.text = (
		"Sai de %s" % _labeler.call(_partner) if _partner >= 0 else "Sai do outro"
	)
	_build_side(_give_list, _proposer, _give)
	_build_side(_get_list, _partner, _get)
	_update_cash()
	_build_footer()


## Com quem trocar. Só aparece na montagem: quem responde já sabe de quem é a
## proposta, e um seletor ali seria um controle que não controla nada.
##
## Não aparece com dois jogadores na mesa, porque aí a resposta é uma só.
func _build_partners() -> void:
	for child in _partners.get_children():
		child.queue_free()
	var others := PackedInt32Array()
	for player in MonopolyRules.alive_players(_state):
		if player != _proposer:
			others.append(player)
	_partners.visible = not _reviewing and others.size() > 1
	if not _partners.visible:
		return
	for player in others:
		var chip := Button.new()
		chip.text = _labeler.call(player)
		MonopolyPanel.compact(chip)
		chip.toggle_mode = true
		chip.button_pressed = player == _partner
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.pressed.connect(_choose_partner.bind(player))
		_partners.add_child(chip)


## Trocar de destinatário zera o que já estava marcado do lado dele. As
## escrituras marcadas eram **daquele** jogador, e mantê-las marcadas montaria uma
## proposta que pede de um o que é do outro.
func _choose_partner(player: int) -> void:
	if player == _partner:
		_rebuild()
		return
	_partner = player
	_get = PackedInt32Array()
	_cash = clampi(_cash, -_cash_floor(), _cash_ceiling())
	_rebuild()


## Uma linha por escritura. Na montagem elas ligam e desligam; na revisão, só as
## que estão na proposta aparecem, e não recebem toque.
func _build_side(list: VBoxContainer, owner: int, chosen: PackedInt32Array) -> void:
	for child in list.get_children():
		child.queue_free()
	if owner < 0:
		return

	var offered := (
		chosen if _reviewing else MonopolyRules.tradable_deeds(_state, owner)
	)
	if offered.is_empty():
		var empty := Label.new()
		empty.text = "Nada." if _reviewing else "Nada que possa entrar numa troca."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(empty)
		return

	for tile in offered:
		var row := Button.new()
		MonopolyPanel.compact(row)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = MonopolyBoard.short_name(tile)
		if MonopolyRules.is_mortgaged(_state, tile):
			row.text += "  ·  hip."
		var group := MonopolyBoard.group_of(tile)
		if group != MonopolyBoard.Group.NONE:
			row.add_theme_color_override("font_color", MonopolyBoard.GROUP_COLORS[group])
		if _reviewing:
			row.disabled = true
		else:
			row.toggle_mode = true
			row.button_pressed = chosen.has(tile)
			row.pressed.connect(_toggle_tile.bind(owner, tile))
		list.add_child(row)


func _toggle_tile(owner: int, tile: int) -> void:
	var chosen := _give if owner == _proposer else _get
	var at := chosen.find(tile)
	if at >= 0:
		chosen.remove_at(at)
	else:
		chosen.append(tile)
	if owner == _proposer:
		_give = chosen
	else:
		_get = chosen
	_rebuild()


# --- dinheiro -----------------------------------------------------------------


## Positivo é quem propõe pagando; negativo é cobrando. Um número com sinal, e não
## dois campos: a diferença é uma só, e dois campos permitiriam preencher os dois
## e criar dinheiro que ninguém tem.
func _bump_cash(step: int) -> void:
	_cash = clampi(_cash + step, -_cash_floor(), _cash_ceiling())
	_update_cash()
	# O rodapé também: uma proposta só de dinheiro sai de vazia para válida aqui, e
	# o botão de propor precisa acender junto.
	_build_footer()


## Os limites são os dois caixas: ninguém pode oferecer nem cobrar dinheiro que
## não existe. É a mesma conta que `validate` faz, e aqui ela existe para o
## jogador não conseguir **montar** uma proposta que seria recusada depois de
## pronta.
func _cash_ceiling() -> int:
	return MonopolyRules.cash_of(_state, _proposer)


func _cash_floor() -> int:
	return MonopolyRules.cash_of(_state, _partner) if _partner >= 0 else 0


func _update_cash() -> void:
	_cash_row.visible = not _reviewing and _partner >= 0
	if _cash == 0:
		_cash_label.text = "Sem dinheiro na troca."
		_cash_label.add_theme_color_override("font_color", AppTheme.TEXT_DIM)
		return
	var payer := _proposer if _cash > 0 else _partner
	var payee := _partner if _cash > 0 else _proposer
	var who := str(_labeler.call(payer))
	var to_whom := str(_labeler.call(payee))
	_cash_label.text = "%s paga M %d a %s." % [who, absi(_cash), to_whom]
	_cash_label.add_theme_color_override("font_color", AppTheme.TEXT)


# --- rodapé -------------------------------------------------------------------


func _build_footer() -> void:
	for child in _footer.get_children():
		child.queue_free()
	if _reviewing:
		_footer_button("Recusar", func() -> void: answered.emit(false))
		_footer_button("Aceitar", func() -> void: answered.emit(true), true)
		return
	_footer_button("Cancelar", func() -> void: dismissed.emit())
	# O botão de propor **existe sempre** e fica cinza quando a proposta está
	# vazia. É o oposto da barra da partida, onde o botão ausente é a resposta:
	# aqui o jogador está montando alguma coisa, e um botão que some enquanto ele
	# monta parece a tela quebrando.
	var send := _footer_button(
		"Propor",
		func() -> void: proposed.emit(
			MonopolyRules.offer_path(_partner, _cash, _give, _get)
		),
		true
	)
	send.disabled = _partner < 0 or (_give.is_empty() and _get.is_empty() and _cash == 0)


## O botão forte fica com o estilo do tema; os outros passam pelo `compact`.
##
## Os dois caminhos não se misturam: `compact()` escreve os quatro styleboxes do
## botão, e um override de stylebox ganha da variação do tema — chamar os dois
## deixaria um "PrimaryButton" indistinguível dos vizinhos, que é exatamente o
## contrário do que a variação existe para fazer.
func _footer_button(label: String, action: Callable, strong := false) -> Button:
	var button := Button.new()
	button.text = label
	if strong:
		button.theme_type_variation = &"PrimaryButton"
		button.add_theme_font_size_override("font_size", 13)
	else:
		MonopolyPanel.compact(button)
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	_footer.add_child(button)
	return button
