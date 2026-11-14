class_name MatchBar
extends PanelContainer

## A barra de uma partida: sair · nome do jogo · o que está acontecendo fora do
## tabuleiro · ações da tela.
##
## Antes cada jogo montava a própria beirada: o xadrez tinha um botão de sair no
## rodapé e a faixa de estado no meio da coluna, o Uno tinha o botão num canto da
## tela deitada, a Metrópole noutro. Eram cinco arranjos para as mesmas três
## coisas, e o jogador que sabia sair de um não sabia sair do outro.
##
## Aqui elas moram juntas, no topo, na mesma ordem em todos os jogos. O que muda
## de jogo para jogo é o que entra em `actions` — e a altura, porque uma tela
## deitada não pode gastar 52 px de mesa com a moldura.
##
## O que fala com `Game` e `Net` é o `bind()` e o `open_rules()`; o resto da barra
## não conhece autoload nenhum, e é o que deixa a tela montá-la no `.tscn` como
## qualquer nó.

## O jogador confirmou que quer sair. Vem do `LeaveButton`, que faz a pergunta —
## ligar em `pressed` sairia sem perguntar.
signal leave_confirmed

const HEIGHT := 56.0
const HEIGHT_COMPACT := 42.0

## Barra de tela deitada: mais baixa, com o título menor. O tabuleiro de uma tela
## deitada é a tela inteira, e cada pixel de moldura sai dele.
@export var compact := false:
	set(value):
		compact = value
		_apply_size()

## Sobre o jogo, e não acima dele: a Metrópole desenha o tabuleiro em 3D até a
## borda de cima, e uma barra opaca cortaria a mesa em duas.
@export var translucent := false:
	set(value):
		translucent = value
		_apply_skin()

@export var title := "":
	set(value):
		title = value
		if _title != null:
			_title.text = value

## Onde cada jogo pendura o que é dele: o `?` de como jogar, o botão de rolar, o
## de trocar. Fica à direita porque é o único lugar da barra que varia.
var actions: HBoxContainer = null
## Tempo, rodadas e código da sala.
var status: MatchStatus = null
var leave: LeaveButton = null
## O `?`: as regras desta mesa, sem sair da partida.
var help: Button = null

var _title: Label = null
## O título e, embaixo dele, a faixa de contexto. Deitada, os dois ficam lado a
## lado: a barra não tem altura para duas linhas.
var _words: BoxContainer = null


func _init() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", AppTheme.SPACE_M)
	add_child(row)

	leave = LeaveButton.new()
	# No topo à esquerda, e não no canto de baixo: aqui ele está na moldura, longe
	# da mão que joga, e é o mesmo canto em que todo aplicativo põe "voltar".
	leave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.custom_minimum_size = Vector2(44, 44)
	leave.confirmed.connect(_on_leave_confirmed)
	row.add_child(leave)

	_words = BoxContainer.new()
	_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_words)

	_title = Label.new()
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.add_theme_font_override("font", AppTheme.display(600))
	_title.text = title
	_words.add_child(_title)

	status = MatchStatus.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_words.add_child(status)

	# O `?` antes das ações do jogo, e sempre no mesmo lugar: é a porta das regras
	# em todas as partidas, e quem aprendeu onde ela fica num jogo acha no outro.
	help = Button.new()
	help.text = "?"
	help.tooltip_text = "Regras desta mesa"
	help.focus_mode = Control.FOCUS_NONE
	help.custom_minimum_size = Vector2(44, 44)
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.add_theme_font_override("font", AppTheme.display(700))
	help.add_theme_font_size_override("font_size", AppTheme.SIZE_DISPLAY_M + 2)
	# Neutro como o de sair: os dois são moldura, e a cor da tela é do jogo.
	for state_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		help.add_theme_color_override(state_name, AppTheme.TEXT_DIM)
	for state_name: String in ["normal", "hover", "pressed", "focus"]:
		var square := AppTheme.box(
			AppTheme.SURFACE_TOP if state_name == "pressed" else AppTheme.SURFACE_HIGH, AppTheme.RADIUS
		)
		square.content_margin_left = 0
		square.content_margin_right = 0
		square.content_margin_top = 0
		square.content_margin_bottom = 0
		help.add_theme_stylebox_override(state_name, square)
	help.pressed.connect(func() -> void: open_rules())
	row.add_child(help)

	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", AppTheme.SPACE_S)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)

	_apply_size()
	_apply_skin()


## Aqui e não no `_init`: o `_ready` do `MatchStatus` centraliza — o certo quando a
## faixa é a linha inteira de uma coluna, o errado dentro da barra — e ele roda
## depois, quando a barra entra na árvore.
func _ready() -> void:
	_apply_size()


## O `LeaveButton` já fez a pergunta; a barra só repassa a resposta, para a tela
## escutar um sinal só e não precisar conhecer o botão de dentro dela.
func _on_leave_confirmed() -> void:
	leave_confirmed.emit()


## Liga a barra à partida em curso: nome do jogo, quando ela começou e — só em
## rede — o código da sala. Quem chama já passou pelo `Game.begin_match()`, que é
## quem decide se o relógio conta de agora ou da partida retomada.
##
## Método e não construtor porque as cenas de partida trazem a barra no `.tscn`,
## como qualquer outro nó: o que não pode estar lá é a conversa com os autoloads.
func bind(bar_title := "") -> void:
	title = bar_title if not bar_title.is_empty() else Game.game_title()
	status.started_at = Game.match_started_at
	status.code = Net.room_code() if Game.mode == Game.Mode.ONLINE else ""


## Abre a gaveta com as regras **desta** mesa: as opções da partida em curso, lidas
## agora, e não no `bind()` — o formato e a regra da casa chegam em rede depois de
## a barra existir.
func open_rules() -> TableRulesDrawer:
	var options := MatchOptions.current()
	var chosen := int(options.get("format", 0)) if Game.game_id == Game.POOL else 0
	return TableRulesDrawer.open(
		RulesPage.host_of(self), Game.game_id,
		TableRules.for_game(Game.game_id, options), chosen
	)


## A mesma barra, montada por código, para a tela que não a declara no `.tscn`.
static func create(bar_title := "") -> MatchBar:
	var bar := MatchBar.new()
	bar.bind(bar_title)
	return bar


func _apply_size() -> void:
	custom_minimum_size = Vector2(0, HEIGHT_COMPACT if compact else HEIGHT)
	if _title == null:
		return
	_title.add_theme_font_size_override(
		"font_size", AppTheme.SIZE_DISPLAY_M + (0 if compact else 2)
	)
	# Em pé, a faixa de contexto vai embaixo do título, à esquerda. Deitada, ao
	# lado dele, encostada à direita.
	_words.vertical = not compact
	_words.add_theme_constant_override("separation", AppTheme.SPACE_M if compact else -3)
	status.alignment = FlowContainer.ALIGNMENT_END if compact else FlowContainer.ALIGNMENT_BEGIN


## Sem fundo próprio e sem fio: a barra é a parte de cima da tela, e quem a
## separa do jogo é o espaço. Só fica translúcida sobre o tabuleiro 3D.
func _apply_skin() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(AppTheme.BACKGROUND, 0.72 if translucent else 1.0)
	style.content_margin_left = AppTheme.SPACE_L
	style.content_margin_right = AppTheme.SPACE_L
	style.content_margin_top = AppTheme.SPACE_XS
	style.content_margin_bottom = AppTheme.SPACE_XS
	add_theme_stylebox_override("panel", style)
