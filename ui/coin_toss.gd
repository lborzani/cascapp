class_name CoinToss
extends Control

## A moeda que decidiu quem joga de brancas numa partida em rede.
##
## A cor já foi sorteada antes de a partida abrir (`pairing.gd`); isto só mostra
## o sorteio. Sem ela, quem criou a sala e saiu de pretas acharia que a regra
## mudou ou que o app errou — a moeda girando diz que foi sorte.
##
## A moeda é uma bolacha (`Coaster`) com uma peça de cada cor nas faces. O giro
## é a escala horizontal seguindo o cosseno do ângulo: em zero ela fica de perfil
## e a face troca. O ângulo desacelera até parar na face sorteada, como o dado do
## Ludo, para o resultado parecer o fim de um movimento.
##
## Não segura o toque: quem saiu de brancas pode jogar enquanto ela some.

## Duração do giro, do resultado na tela e da saída.
const SPIN := 1.4
const HOLD := 1.2
const FADE := 0.3
## Meias voltas até parar, partindo da face branca. Uma a mais quando o resultado
## é pretas, para a última face ser a certa.
const HALF_TURNS := 8
## Diâmetro em relação ao lado menor da tela, e a altura do arco do lançamento
## em relação ao diâmetro.
const COIN_SHARE := 0.32
const TOSS_HEIGHT := 0.6

var side := Board.Side.WHITE
var kind := Board.Kind.PAWN

var _coin := Coaster.new()
var _caption := Label.new()
var _progress := 0.0


## Lança a moeda por cima de `parent`. `player_side` é a cor de quem está vendo.
static func play(parent: Control, player_side: int, piece_kind: int) -> CoinToss:
	var toss := CoinToss.new()
	toss.side = player_side
	toss.kind = piece_kind
	parent.add_child(toss)
	return toss


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin.ring = AppTheme.GOLD
	add_child(_coin)
	_caption.text = "Você joga de %s" % ("brancas" if side == Board.Side.WHITE else "pretas")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", AppTheme.display(800))
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_color", AppTheme.TEXT)
	_caption.modulate.a = 0.0
	add_child(_caption)
	resized.connect(_layout)
	_layout()

	var tween := create_tween()
	tween.tween_method(_spin, 0.0, 1.0, SPIN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_caption, "modulate:a", 1.0, 0.2)
	tween.tween_interval(HOLD)
	tween.tween_property(self, "modulate:a", 0.0, FADE)
	tween.tween_callback(queue_free)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), AppTheme.SCRIM)


## A face que está para cima num ângulo dado. Começa na branca e troca a cada
## meia volta, no instante em que a moeda passa de perfil.
static func face_at(angle: float) -> int:
	var half := int(floor((angle + PI * 0.5) / PI))
	return Board.Side.WHITE if half % 2 == 0 else Board.Side.BLACK


func _turns() -> int:
	return HALF_TURNS + (0 if side == Board.Side.WHITE else 1)


func _spin(progress: float) -> void:
	_progress = progress
	var angle := progress * _turns() * PI
	var face := face_at(angle)
	_coin.fill = AppTheme.PAPER if face == Board.Side.WHITE else AppTheme.COASTER
	_coin.piece = Board.piece(face, kind)
	# Nunca zero: uma escala nula some com o nó e o perfil da moeda pisca.
	var lift := sin(progress * PI)
	_coin.scale = Vector2(maxf(absf(cos(angle)), 0.04), 1.0) * (1.0 + 0.25 * lift)
	_layout()


func _layout() -> void:
	var diameter := minf(size.x, size.y) * COIN_SHARE
	var lift := sin(_progress * PI) * diameter * TOSS_HEIGHT
	var center := Vector2(size.x * 0.5, size.y * 0.42 - lift)
	_coin.size = Vector2(diameter, diameter)
	_coin.pivot_offset = _coin.size * 0.5
	_coin.position = center - _coin.size * 0.5
	_caption.size = Vector2(size.x, 0.0)
	_caption.position = Vector2(0.0, size.y * 0.42 + diameter * 0.5 + 24.0)
