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
## O cartão inteiro é o toque de voltar, como o `RoomCard` — de quem ele copia o
## desenho de propósito: é uma sala, e a lista de salas já ensinou como ela se
## parece. O que muda é a borda na cor de destaque, porque esta não é uma sala
## qualquer, e o `X` à direita no lugar da seta: quem não quer voltar precisa de um
## jeito de dizer isso que não seja esperar quatro horas o cartão sumir sozinho.

signal resume_pressed(game_id: StringName, code: String)
signal dismissed

const HEIGHT := 72.0

var game_id := &"chess"
var code := ""
## Quando a cadeira foi gravada, em tempo Unix.
var saved_at := 0

var _close: IconButton = null


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	theme_type_variation = &"PrimaryButton"
	text = ""
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func() -> void: resume_pressed.emit(game_id, code))

	# Filho do botão, e não um irmão ao lado dele: o cartão continua sendo uma
	# linha só na lista, e o toque no `X` fica com o `X` — um `Control` filho que
	# para o toque não o repassa ao pai.
	_close = IconButton.new()
	_close.kind = IconButton.Kind.CLOSE
	# Tinta escura: o X mora na placa amarela, e o cinza do tema sumiria nela.
	_close.tint = Color(AppTheme.ACCENT_INK, 0.75)
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
	var pad := 16.0
	var piece_size := size.y * 0.58
	PieceRenderer.draw_piece(
		self, Game.piece_of(game_id), Vector2(pad + piece_size * 0.5, size.y * 0.5), piece_size
	)

	var text_x := pad + piece_size + 14.0
	var text_width := maxf(40.0, size.x - text_x - IconButton.SIZE - 20.0)
	draw_string(
		AppTheme.display(900), Vector2(text_x, size.y * 0.5 - 2.0), _title().to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 20, AppTheme.ACCENT_INK
	)
	draw_string(
		AppTheme.font(400), Vector2(text_x, size.y * 0.5 + 18.0), _detail(),
		HORIZONTAL_ALIGNMENT_LEFT, text_width, 13, Color(AppTheme.ACCENT_INK, 0.75)
	)


func _title() -> String:
	return "Voltar para %s" % str(Game.entry_of(game_id).get("title", "a partida"))


## O código vai junto porque é o que os outros jogadores veem na tela deles: quem
## volta e diz "entrei no DK4P2Q" está falando a mesma língua da mesa.
func _detail() -> String:
	return "Partida em andamento • sala %s" % code
