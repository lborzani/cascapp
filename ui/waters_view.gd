class_name WatersView
extends GridView

## Um dos dois mares da batalha naval: o seu, ou o do adversário.
##
## O mesmo nó serve aos dois porque a diferença é de **visibilidade**, não de
## desenho — `own` decide se os navios inteiros aparecem. Ter duas classes para
## isso significaria dois desenhos de casco que um dia divergem, e o jogador
## comparando dois mares lado a lado é justamente quem mais nota a diferença.
##
## O modelo conhece as duas frotas; é aqui que o segredo é guardado. Parece
## frágil e é a troca deliberada de `BattleshipRules`: esconder no modelo
## quebraria a reconstrução da partida pela lista de lances, que é o que faz a
## reconexão funcionar.
##
## As casas não são xadrezadas de verdade. No xadrez a cor da casa é regra — o
## bispo de casas claras nunca sai delas; num mar todas as casas valem o mesmo, e
## um xadrezado forte anunciaria uma diferença que não existe. Sobra só o
## contraste mínimo que deixa contar as casas com o olho.

## Frota deste mar, casa a casa (espécie ou 0). Vazia enquanto o adversário não
## mandou a dele.
var fleet := PackedInt32Array():
	set(value):
		fleet = value
		queue_redraw()

## Tiros dados **neste** mar, em códigos de `BattleshipRules.Shot`.
var shots := PackedInt32Array():
	set(value):
		shots = value
		queue_redraw()

## Este mar é o do jogador local. Falso esconde todo navio que ainda não afundou.
var own := false:
	set(value):
		own = value
		queue_redraw()

## Casa mirada, destacada em latão. É o retorno do toque antes do tiro sair.
var aim := Board.NO_SQUARE:
	set(value):
		aim = value
		queue_redraw()

## Coordenadas na moldura. Saem no mar pequeno: com a casa em ~13px a letra fica
## menor que o traço dela, e uma coordenada ilegível é ruído com aparência de
## informação.
var labels := true:
	set(value):
		labels = value
		queue_redraw()


func _draw() -> void:
	layout()
	draw_frame()

	var sunk := _sunk_kinds()
	for square in Board.SQUARE_COUNT:
		var rect := rect_of(square)
		var dark := (Board.file_of(square) + Board.rank_of(square)) % 2 == 0
		draw_rect(rect, AppTheme.WATER if dark else AppTheme.WATER_ALT)

	for square in Board.SQUARE_COUNT:
		var kind := _kind_at(square)
		if kind != 0 and (own or sunk.has(kind)):
			_draw_hull(square, kind, sunk.has(kind))

	for square in Board.SQUARE_COUNT:
		match _shot_at(square):
			BattleshipRules.Shot.MISS:
				_draw_splash(rect_of(square))
			BattleshipRules.Shot.HIT:
				_draw_hit(rect_of(square))

	if aim != Board.NO_SQUARE:
		var rect := rect_of(aim)
		draw_rect(rect, Color(AppTheme.ACCENT, 0.22))
		draw_rect(rect.grow(-2.0), Color(AppTheme.ACCENT, 0.9), false, maxf(2.0, _cell * 0.06))

	if labels:
		draw_coordinates()


func _kind_at(square: int) -> int:
	return fleet[square] if square < fleet.size() else 0


func _shot_at(square: int) -> int:
	return shots[square] if square < shots.size() else BattleshipRules.Shot.NONE


## Calculado uma vez por desenho, e não por casa: `is_sunk` varre as 64 casas, e
## perguntar dentro do laço faria 4096 voltas a cada quadro.
func _sunk_kinds() -> PackedInt32Array:
	var kinds := PackedInt32Array()
	if fleet.is_empty() or shots.is_empty():
		return kinds
	for ship in BattleshipRules.SHIPS:
		var kind := int(ship["kind"])
		if BattleshipRules.is_sunk(fleet, shots, kind):
			kinds.append(kind)
	return kinds


## Um segmento de casco por casa, escolhido pelos vizinhos: sem vizinho adiante é
## proa, sem vizinho atrás é popa, entre os dois é meio. A corrente que eles
## formam lê como um navio inteiro sem nenhuma casa precisar saber o comprimento
## dele.
##
## Vizinho "do mesmo navio" é vizinho da **mesma espécie**, e isso só funciona
## porque cada navio tem a sua: dois cascos encostados nunca se fundem num só por
## engano, e nenhuma casa precisa carregar um identificador de casco.
##
## O afundado é o mesmo desenho tingido de vermelho. Redesenhar um casco
## destruído seria um quinto e um sexto arquivo para dizer o que a cor já diz.
func _draw_hull(square: int, kind: int, is_sunk: bool) -> void:
	var rect := rect_of(square)
	var horizontal := _same_ship(square, 1, 0, kind) or _same_ship(square, -1, 0, kind)
	var ahead := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
	var part := "mid"
	if not _same_ship(square, ahead.x, ahead.y, kind):
		part = "bow"
	elif not _same_ship(square, -ahead.x, -ahead.y, kind):
		part = "stern"

	var texture := _hull_texture(part)
	var tint := Color(1.0, 0.55, 0.5) if is_sunk else Color.WHITE
	if texture == null:
		# Rede de segurança: sem o asset, um bloco chapado ainda diz onde o navio
		# está. Um casco que some do mar seria bem pior que um casco feio.
		draw_rect(rect.grow(-_cell * 0.11), AppTheme.HULL * tint)
		return

	# A proa do desenho aponta para +x. Na vertical ela precisa apontar para o
	# topo da tela, que é para onde a fileira **cresce** quando o tabuleiro não
	# está girado — daí o quarto de volta negativo. Girar o tabuleiro é meia volta
	# em tudo (`rect_of` espelha os dois eixos), então soma PI.
	var angle := 0.0 if horizontal else -PI * 0.5
	if flipped:
		angle += PI
	draw_set_transform(rect.get_center(), angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-rect.size * 0.5, rect.size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _same_ship(square: int, df: int, dr: int, kind: int) -> bool:
	var file := Board.file_of(square) + df
	var rank := Board.rank_of(square) + dr
	if not Board.in_bounds(file, rank):
		return false
	return _kind_at(Board.square(file, rank)) == kind


## Carregado uma vez por segmento e guardado na classe: são três texturas para o
## app inteiro, e `load` a cada casa desenhada seria 64 chamadas por quadro.
static var _hull_cache := {}


static func _hull_texture(part: String) -> Texture2D:
	if not _hull_cache.has(part):
		_hull_cache[part] = load("res://assets/pieces/ship_%s.svg" % part) as Texture2D
	return _hull_cache[part]


## Tiro n'água: um ponto apagado. Pequeno de propósito — ele só precisa dizer
## "já tentei aqui", e um marcador forte em 40 casas gastas cobriria o mar.
func _draw_splash(rect: Rect2) -> void:
	draw_circle(rect.get_center(), _cell * 0.16, Color(AppTheme.SPLASH, 0.85))


## Acerto: cruz vermelha cheia. É o único evento do jogo que muda alguma coisa, e
## precisa ser encontrado de relance num mar cheio de pontos apagados.
func _draw_hit(rect: Rect2) -> void:
	var inset := rect.grow(-_cell * 0.26)
	var width := _cell * 0.13
	draw_line(inset.position, inset.position + inset.size, AppTheme.DANGER, width)
	draw_line(
		inset.position + Vector2(inset.size.x, 0),
		inset.position + Vector2(0, inset.size.y),
		AppTheme.DANGER,
		width
	)
