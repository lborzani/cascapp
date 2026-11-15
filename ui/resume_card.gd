class_name ResumeCard
extends Button

## A partida de onde este aparelho caiu, com o caminho de volta.
##
## Existe porque o caminho de volta não existia. Quem tinha o app fechado no meio
## de uma partida reabria na tela inicial, e o único gesto à mão era **criar** uma
## partida: sala nova, código novo, e a antiga seguindo sem ele, com uma máquina
## jogando no seu lugar. Voltar exigia lembrar o código de seis letras que só
## apareceu na tela de quem abriu.
##
## O cartão inteiro é o toque de voltar. Fica no topo da tela inicial, com o
## ladrilho na cor do jogo e uma linha em limão dizendo que a partida segue — é a
## única coisa da tela que tem prazo. O `X` à direita existe porque quem não quer
## voltar precisa de um jeito de dizer isso que não seja esperar quatro horas o
## cartão sumir sozinho.
##
## Não diz de quem é a vez: isso só a mesa sabe, e o cartão é montado sem rede.
## O que ele sabe de verdade é o jogo, a sala e há quanto tempo a cadeira ficou.

signal resume_pressed(game_id: StringName, code: String)
signal dismissed

const HEIGHT := 84.0
const PAD := 12.0
const ICON := 60.0

var game_id := &"chess"
var code := ""
## Quando a cadeira foi gravada, em tempo Unix.
var saved_at := 0

var _close: IconButton = null


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	# Sem caixa do tema: o cartão desenha a própria superfície.
	theme_type_variation = &"IconButton"
	text = ""
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func() -> void: resume_pressed.emit(game_id, code))

	# Filho do botão, e não um irmão ao lado dele: o cartão continua sendo uma
	# linha só na lista, e o toque no `X` fica com o `X` — um `Control` filho que
	# para o toque não o repassa ao pai.
	_close = IconButton.new()
	_close.kind = IconButton.Kind.CLOSE
	_close.tint = AppTheme.TEXT_DIM
	_close.mouse_filter = Control.MOUSE_FILTER_STOP
	_close.pressed.connect(func() -> void: dismissed.emit())
	add_child(_close)
	resized.connect(_place_close)
	_place_close()


func _place_close() -> void:
	if _close == null:
		return
	var side := IconButton.SIZE
	_close.size = Vector2(side, side)
	_close.position = Vector2(size.x - side - 10.0, (size.y - side) * 0.5)


func _draw() -> void:
	draw_style_box(AppTheme.box(AppTheme.SURFACE, AppTheme.RADIUS_LARGE), Rect2(Vector2.ZERO, size))
	# O mesmo ladrilho dos blocos da grade: o cartão é da família deles, deitado.
	var tile := Rect2(PAD, (size.y - ICON) * 0.5 - 2.0, ICON, ICON)
	GameTile.draw_badge(self, game_id, tile)

	var text_x := tile.end.x + PAD
	var text_width := maxf(40.0, size.x - text_x - IconButton.SIZE - 20.0)
	var middle := size.y * 0.5
	draw_string(
		AppTheme.font(700), Vector2(text_x, middle - 16.0), _status(),
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 12, AppTheme.ACCENT
	)
	draw_string(
		AppTheme.display(600), Vector2(text_x, middle + 6.0), _title(),
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 19, AppTheme.TEXT
	)
	draw_string(
		AppTheme.font(500), Vector2(text_x, middle + 25.0), _detail(),
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 13, AppTheme.TEXT_DIM
	)


func _title() -> String:
	return "Voltar para %s" % str(Game.entry_of(game_id).get("title", "a partida"))


## O código vai junto porque é o que os outros jogadores veem na tela deles: quem
## volta e diz "entrei no DK4P2Q" está falando a mesma língua da mesa.
func _status() -> String:
	return "EM ANDAMENTO · SALA %s" % code


func _detail() -> String:
	return "Você saiu %s" % ago(int(Time.get_unix_time_from_system()) - saved_at)


## Há quanto tempo, em palavras: o cartão some sozinho em algumas horas, e
## "há 3 h" diz ao jogador se ainda vale a pena voltar.
static func ago(seconds: int) -> String:
	if seconds < 90:
		return "agora há pouco"
	if seconds < 3600:
		return "há %d min" % int(round(seconds / 60.0))
	return "há %d h" % int(round(seconds / 3600.0))
