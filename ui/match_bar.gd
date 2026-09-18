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
## O que fala com `Game` e `Net` é só o `bind()`, e o resto da barra não conhece
## autoload nenhum: é o que deixa a tela montá-la no `.tscn` como qualquer nó.

## O jogador confirmou que quer sair. Vem do `LeaveButton`, que faz a pergunta —
## ligar em `pressed` sairia sem perguntar.
signal leave_confirmed

const HEIGHT := 52.0
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

var _title: Label = null


func _init() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", AppTheme.SPACE_M)
	add_child(row)

	leave = LeaveButton.new()
	# No topo à esquerda, e não no canto de baixo: aqui ele está na moldura, longe
	# da mão que joga, e é o mesmo canto em que todo aplicativo põe "voltar".
	leave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.custom_minimum_size = Vector2(38, 38)
	leave.confirmed.connect(_on_leave_confirmed)
	row.add_child(leave)

	_title = Label.new()
	_title.theme_type_variation = &"SectionHeader"
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.text = title
	row.add_child(_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	status = MatchStatus.new()
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)
	# À direita depois de entrar na árvore: o `_ready` dele centraliza, que é o
	# certo quando a faixa é a linha inteira de uma coluna, e errado quando ela
	# divide a linha com um título.
	status.alignment = FlowContainer.ALIGNMENT_END

	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", AppTheme.SPACE_S)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)

	_apply_size()
	_apply_skin()


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


## A mesma barra, montada por código, para a tela que não a declara no `.tscn`.
static func create(bar_title := "") -> MatchBar:
	var bar := MatchBar.new()
	bar.bind(bar_title)
	return bar


func _apply_size() -> void:
	custom_minimum_size = Vector2(0, HEIGHT_COMPACT if compact else HEIGHT)
	if _title != null:
		_title.add_theme_font_size_override(
			"font_size", AppTheme.SIZE_DISPLAY_M - (2 if compact else 0)
		)


## Fundo e um fio embaixo: a barra precisa se separar do que vem depois sem virar
## um bloco. O fio é a beirada do balcão.
func _apply_skin() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(AppTheme.BACKGROUND, 0.72) if translucent else AppTheme.SURFACE
	style.border_width_bottom = 1
	style.border_color = AppTheme.LINE_SOFT
	style.content_margin_left = AppTheme.SPACE_M
	style.content_margin_right = AppTheme.SPACE_M
	style.content_margin_top = AppTheme.SPACE_XS
	style.content_margin_bottom = AppTheme.SPACE_XS
	add_theme_stylebox_override("panel", style)
