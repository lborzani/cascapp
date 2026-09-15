class_name MonopolyBoard3D
extends Node3D

## O tabuleiro de Metrópole em três dimensões: o tampo, os peões, as construções,
## a luz e a câmera que gira para quem está jogando.
##
## É o único nó 3D do app. Ele vive dentro de um `SubViewport` numa tela que
## continua sendo `Control`, então tudo o que o app já tem — tema, botões, aviso,
## área segura — segue funcionando por cima sem saber que há 3D embaixo.
##
## ## A divisão: o que é plano é textura, o que tem altura é volume
##
## O tampo inteiro — casas, faixas de cor, barras de dono, nomes, preços, ícones
## e o miolo — é desenhado por [monopoly_face.gd] num `SubViewport` de 1536² e
## colado como textura. Peças, construções e os dois baralhos são malhas de
## verdade, de pé, com sombra.
##
## A divisão não é estética, é de custo. Texto em 3D custa 80 `Label3D` que
## precisam ser reorientados a cada giro de câmera; sombra pintada numa textura
## custa brigar com a sombra real que a luz projeta. Cada coisa fica do lado em
## que ela é barata.
##
## ## O que faz a cena parecer um brinquedo numa mesa
##
## Quatro coisas, e nenhuma é modelagem:
##
## - **a mesa.** Um plano grande e fosco embaixo de tudo. Sem ele a caixa flutua
##   num vazio da cor do fundo do app e a única sombra da cena é a das peças no
##   próprio tampo — o tabuleiro inteiro fica sem peso;
## - **o lábio.** O corpo da caixa é mais estreito que o tampo, então a superfície
##   impressa sobra por cima dele. Com os dois do mesmo tamanho a peça lia como
##   uma placa maciça;
## - **a curva filmica e um empurrão de saturação.** É o que separa "cores de
##   plástico" de "cores de material padrão" sem tocar em cor nenhuma uma a uma;
## - **a sombra macia.** Sombra dura de sol pontual em peça de dois centímetros
##   desenha um recorte de papel ao lado de cada uma.
##
## ## Cada jogador tem a sua peça
##
## Chapéu, carro, avião, bola, barco e bota, de [monopoly_token.gd] — e a cor
## continua sendo a do jogador. As duas coisas juntas: a cor liga a peça à faixa
## da coluna da esquerda, a forma é o que se reconhece de relance num anel com
## seis peças espalhadas.
##
## Elas apontam para **onde se anda**. `tile_along` é a direção em que os índices
## crescem, e é a mesma conta que gira a câmera — o carro anda de frente, e o
## anel passa a ter sentido em vez de ser uma coleção de objetos parados.
##
## ## A câmera anda atrás do peão da vez
##
## É o que o 3D compra. Ela fica perto, **atrás** de quem está jogando, e olha no
## sentido em que ele anda — o peão caminha para dentro da tela em vez de
## atravessá-la de lado. Como o eixo do giro é a direção da caminhada, ela vira
## sozinha a cada canto do anel.
##
## O preço é a legibilidade do tampo: a fileira em que o peão está passa a ser
## vista de enfiada, com o texto correndo para longe. É aceitável porque é
## exatamente isso que o painel da direita mostra em letra grande — o tabuleiro
## não precisa ser lido de relance quando há uma escritura aberta ao lado.
##
## `follow = -1` volta para o enquadramento do tabuleiro inteiro, que gira por
## assento (`(assento % 4) * 90°`) e enquadra tudo. Ninguém usa hoje; fica porque
## é o que uma tela de fim de partida vai querer.
##
## Projeção **perspectiva**, e a ortogonal foi tentada primeiro. O argumento dela
## era bom — duas casas do mesmo tamanho pareciam do mesmo tamanho — e o resultado
## lia como o desenho 2D inclinado. Sem convergência não há profundidade, e sem
## profundidade não há motivo para o jogo ser 3D.

## Casa tocada, do toque projetado no tampo.
signal tile_tapped(tile: int)
## O peão chegou. A cena espera por isto antes de resolver o que a casa manda.
signal walk_finished
## A câmera saiu ou voltou ao automático. A tela usa para mostrar "recentrar"
## exatamente enquanto ele serve para alguma coisa.
signal camera_freed

## Uma casa de borda mede uma unidade de mundo. Todas as outras medidas saem
## disso, então mudar a escala do tabuleiro é mudar `Face.EDGE` e mais nada.
const Face := preload("res://ui/monopoly_face.gd")
const BOARD_SPAN := Face.SPAN
const BOARD_THICKNESS := 0.34

## Lado da textura do tampo, em pixels. 1536 dá ~127 pixels por casa de borda.
##
## Chegou a ser 2048 quando a nitidez foi atacada pelo lado errado. O que faltava
## não era resolução de textura: era a janela 3D ser desenhada nos pixels do
## aparelho (`_fit_window`, em [monopoly_match.gd]) e o tampo ter **mipmap**. Com
## os dois no lugar, 1536 não é mais o limite de nada — e cada passo para cima
## custa o dobro na leitura de volta que a assadura do mipmap faz.
const FACE_PIXELS := 1536

## Tempo por casa andada. Mais rápido que o passo do Ludo (0,15s) porque aqui se
## anda até 12 casas de uma vez: no mesmo passo, uma rolagem de 11 levaria quase
## dois segundos antes de qualquer coisa acontecer.
const STEP_SECONDS := 0.085
const HOP_HEIGHT := 0.42

## Quanto a câmera leva para trocar de lado. Um quarto de volta é muito para ser
## instantâneo — sem a animação, o jogador perde a referência de onde estava
## olhando e procura o próprio peão de novo a cada vez.
const TURN_SECONDS := 0.55
## Altura da câmera, em graus acima do tampo. Baixo demais e as construções tapam
## as casas de trás; alto demais e o jogo vira o desenho 2D com sombra — que foi
## exatamente o que 52° e depois 45° produziram, mesmo com a sombra rasante.
const PITCH_DEGREES := 42.0
## Abertura da lente. Estreita: a perspectiva tem de dar profundidade sem torcer
## as casas dos cantos, e acima de uns 50° a fileira da frente começa a abrir em
## leque.
const FOV_DEGREES := 38.0
## Folga sobre a distância mínima que faz o tabuleiro caber. Um é o tabuleiro
## encostando nas quatro bordas da janela; acima de um sobra respiro, e é o
## respiro que impede uma peça alta na fileira do fundo de encostar no topo.
##
## Só vale no enquadramento de tabuleiro inteiro — seguindo um peão, quem manda é
## `FOLLOW_DISTANCE`.
const DISTANCE_FACTOR := 1.62

## Distância da câmera ao peão que ela segue, em casas de borda. Cerca de sete
## casas de largura no quadro: o bastante para ver de onde o peão veio e para
## onde vai, e perto o bastante para as construções terem volume em vez de serem
## pontinhos.
const FOLLOW_DISTANCE := 10.8
## Quanto a câmera olha **à frente** do peão, na direção da caminhada. Mirar nele
## o põe no meio do quadro sem se ver aonde ele vai; mirando adiante, ele desce e
## o que se vê é o caminho.
const FOLLOW_AHEAD := 2.6
## Quanto a mira desce **abaixo** do tampo, seguindo o peão.
##
## Mirar no tampo põe o horizonte no meio da tela: metade do quadro vira mesa
## vazia, e o tabuleiro — a única coisa que se está olhando — fica espremido na
## metade de baixo. Baixar a mira inclina a câmera mais para o chão, o horizonte
## sobe para fora do quadro e o tampo sobe junto.
##
## É a mesma ideia de [constant LOOK_HEIGHT], que já fazia isto no enquadramento
## de tabuleiro inteiro; o acompanhamento simplesmente não tinha o equivalente.
const FOLLOW_LOOK_DROP := 1.7
## Quanto a mira é puxada para o meio do tabuleiro. Zero é olhar só à frente do
## peão, e sai do tampo nos cantos; um é olhar sempre para o centro, e o
## acompanhamento deixa de existir.
##
## Era 0,55, que é mais da metade do caminho até o centro — e somado ao avanço
## punha a mira a quase quatro unidades do peão, num quadro cuja meia-largura é
## cinco. O peão vivia encostado na borda esquerda e, perto dos cantos, saía.
const FOLLOW_CENTER_PULL := 0.35
## Distância máxima entre a mira e o peão, em casas de borda.
##
## É a **garantia** que o puxão para o centro não dá: aquele é uma preferência —
## "olhe mais para dentro do tabuleiro quando der" — e uma preferência não impede
## o caso ruim, ela só o torna menos frequente. Com a coleira, seja qual for a
## combinação de avanço e puxão, o peão está sempre dentro deste raio da mira, e
## portanto sempre no quadro.
const FOLLOW_LEASH := 2.4
## Suavidade do acompanhamento, por segundo. Alto demais e a câmera cola no peão,
## que pula — e o tabuleiro inteiro passa a pular junto.
const FOLLOW_LERP := 3.4
## Para onde a câmera olha, acima do tampo. Mirar no tampo põe o horizonte no meio
## da tela e joga metade do quadro no fundo vazio; mirando um pouco acima, o
## tabuleiro sobe e ocupa o que sobrava.
const LOOK_HEIGHT := -0.9

## Mesa sob o tabuleiro, em cor e em tamanho.
##
## Ela existe para o tabuleiro **ter sombra em alguma coisa**. Sem ela a caixa
## flutua num vazio da cor do fundo do app, e a única sombra da cena é a das
## peças no próprio tampo — o tabuleiro inteiro fica sem peso. Um plano grande e
## fosco recebendo a sombra da caixa resolve isso com um nó.
##
## Escura, mas **acima** do fundo do app: com os dois quase iguais a sombra que a
## caixa projeta não tem onde aparecer, e a mesa deixa de servir para a única
## coisa que ela faz.
const TABLE_COLOR := Color("2a2119")
## Nove vezes o tabuleiro, e não três.
##
## Três acabava **dentro do quadro**: seguindo o peão, a câmera olha para o tampo,
## então o horizonte cai no meio da tela e a metade de cima era a borda da mesa e,
## depois dela, o vazio chapado da cor do fundo do app. Um terço da tela do jogo
## mais caro do catálogo era um retângulo preto.
##
## O plano custa dois triângulos, então o tamanho é de graça; o que não é de graça
## é a borda aparecer. Quem a esconde não é o tamanho sozinho — é [constant
## TABLE_FADE_AT], que apaga a mesa **para a própria cor do fundo** antes de ela
## terminar. Com os dois, não existe distância nem inclinação de câmera livre em
## que se veja onde a mesa acaba.
const TABLE_SPAN := Face.SPAN * 9.0
## Onde a mesa começa e termina de apagar, em fração do raio da textura.
##
## O tabuleiro ocupa pouco mais de 1/9 do raio, então a poça de luz vai até aí e o
## resto é a sala escura em volta. Terminar exatamente em `AppTheme.BACKGROUND` é
## o truque inteiro: a mesa e o fundo viram a mesma cor antes da geometria acabar.
const TABLE_LIT_AT := 0.10
const TABLE_FADE_AT := 0.42
## Quanto o tampo avança sobre o corpo da caixa, de cada lado. Um lábio: o tampo
## é a tampa impressa e o corpo é a caixa embaixo dela, que é como uma caixa de
## jogo é de verdade.
const BOARD_LIP := 0.11

## O baralho empilhado no miolo. Não é enfeite: até aqui a carta aparecia no
## aviso vinda de lugar nenhum, e a pilha é o que dá origem a ela.
const DECK_THICKNESS := 0.09

## Medidas das peças, em unidades de mundo — lembrando que uma casa de borda mede
## **uma**.
##
## Quatro casas têm de caber ao longo de uma casa de borda sem encostar: as vagas
## ficam a 0,25 uma da outra, então a largura tem de ser menor que isso.
const HOUSE_WIDTH := 0.22
const HOTEL_WIDTH := 0.62
const BUILDING_WALLS := 0.20
const BUILDING_ROOF := 0.14
## Menos que a faixa de cor (0,30), para a construção pousar **dentro** dela.
const BUILDING_DEPTH := 0.24

## Quanto o dedo anda antes de o toque virar arrasto, em pixels.
##
## Existe para separar **tocar numa casa** de **girar a câmera**, que são o mesmo
## gesto até o dedo se mexer. Doze é maior que o tremor de um toque firme e menor
## que qualquer arrasto intencional; abaixo disso, tocar numa casa girava a mesa
## um grau e a casa não abria.
const DRAG_SLOP := 12.0
## Radianos por pixel arrastado. Meia tela de lado dá cerca de meia volta, que é
## o que faz o giro parecer que a mesa está sendo empurrada com o dedo.
const ORBIT_PER_PIXEL := 0.0062
## Unidades de distância por pixel de pinça.
const ZOOM_PER_PIXEL := 0.022
## Passo da roda do mouse. Só existe para quem roda no desktop — o teste de
## desenho e o editor.
const ZOOM_PER_NOTCH := 1.4

## Limites da câmera livre.
##
## A inclinação é o que mais precisa de trava: abaixo de uns 20° as construções
## da fileira da frente tapam o tabuleiro inteiro, e acima de uns 75° a
## perspectiva some e a mesa vira o desenho 2D — que é justamente o que o 3D veio
## resolver.
const FREE_PITCH_MIN := 20.0
const FREE_PITCH_MAX := 74.0
## Perto o bastante para ler uma casa, longe o bastante para o anel inteiro caber.
const FREE_DISTANCE_MIN := 5.5
const FREE_DISTANCE_MAX := 26.0

var state: MatchState = null:
	set(value):
		state = value
		_dirty_face = true
		_dirty_pieces = true

## Casa em destaque — a que o painel está mostrando. -1 é nenhuma.
var focused := -1:
	set(value):
		focused = value
		_dirty_pieces = true

## De que lado a câmera olha quando ela **não** está seguindo ninguém.
var facing := 0:
	set(value):
		facing = value
		if follow < 0:
			_target_yaw = -deg_to_rad(90.0 * (value % 4))

## Peão que a câmera acompanha, ou -1 para enquadrar o tabuleiro inteiro.
##
## Seguindo, ela chega perto e se põe **atrás** dele, olhando no sentido da
## caminhada: vista de terceira pessoa, com o peão andando para dentro da tela.
var follow := -1:
	set(value):
		follow = value
		if value < 0:
			_target_yaw = -deg_to_rad(90.0 * (facing % 4))

## A câmera está na mão do jogador, e o acompanhamento automático está suspenso.
##
## Só de leitura para quem usa: quem a liga é o arrasto, e o único que a desliga
## é `recenter()`. Nada na partida a desfaz — uma vista que se desmonta sozinha a
## cada peão que anda não é uma vista que se possa usar.
var free := false

var _face: MonopolyFace = null
var _face_viewport: SubViewport = null
## Material do tampo, e a textura com mipmap que ele passa a usar. Ver
## [method _bake_face].
var _top_material: StandardMaterial3D = null
var _face_texture: ImageTexture = null
var _camera: Camera3D = null
var _pivot: Node3D = null
var _pieces: Node3D = null
var _highlight: MeshInstance3D = null
var _pawns: Array[Node3D] = []

var _target_yaw := 0.0
var _yaw := 0.0
## Ponto que a câmera mira quando está seguindo alguém, já amortecido.
var _focus := Vector3.ZERO
## A mira já foi posta no lugar uma vez. Sem isto, o primeiro quadro de um
## acompanhamento faz a câmera varrer do centro do tabuleiro até o peão.
var _focus_ready := false
var _dirty_face := true
var _dirty_pieces := true
## Quadros ainda a renderizar do tampo. Ver `_process` para o porquê de dois.
var _face_frames := 0
var _walk := {}

## Inclinação e distância da câmera livre. Semeadas do enquadramento em curso no
## instante em que o jogador pega a câmera, para não haver salto.
var _free_pitch := PITCH_DEGREES
var _free_distance := FOLLOW_DISTANCE
## Dedos encostados agora: índice → posição. Um é órbita, dois é pinça.
var _touches := {}
## Onde o gesto começou, para a folga ser medida contra ele.
var _press_at := Vector2.ZERO
## O dedo já passou da folga e virou arrasto. Enquanto for falso, soltar é toque.
var _dragging := false
## O aparelho tem tela sensível, então os eventos de mouse sintetizados a partir
## dela são ignorados. Sem isto, cada dedo gira a câmera duas vezes no Android,
## onde `emulate_mouse_from_touch` vem ligado de fábrica.
var _touch_device := false


func _ready() -> void:
	_build_environment()
	_build_face()
	_build_board()
	_pieces = Node3D.new()
	add_child(_pieces)
	_build_highlight()
	_yaw = _target_yaw
	set_process(true)


# --- montagem -----------------------------------------------------------------


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = AppTheme.BACKGROUND
	# Luz ambiente por cor, e não por céu: um céu procedural pinta o tampo de azul
	# nas partes em sombra, e o tabuleiro deixa de ser bege.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cfd6de")
	# Ambiente e sol somando pouco mais de 1: o tampo já é um bege claro, e com a
	# soma acima de 1 ele estourava para branco e o texto perdia contraste.
	environment.ambient_light_energy = 0.42
	# Curva filmica em vez de linear. A linear satura os claros de forma abrupta —
	# o tampo bege sob o sol chegava ao branco de chapa e o texto perdia o
	# contraste ali. A filmica dobra o topo da curva e devolve o degradê do tampo.
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.35
	# Um empurrão pequeno de contraste e de saturação. É o que separa "cores de
	# plástico" de "cores de material padrão" sem tocar em nenhuma cor uma a uma —
	# e é onde a estética de brinquedo é mais barata de obter.
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.12
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	# De cima e de lado, mas não de cima do jogador: a sombra tem de cair **para
	# dentro** do tabuleiro para dar volume às peças. Vinda de frente, cada peça
	# esconde a própria sombra e tudo volta a parecer plano.
	# Rasante, e não de cima. Sol a pino projeta a sombra debaixo da peça, onde ela
	# não é vista, e o tabuleiro volta a parecer o desenho 2D com um degradê. A
	# sombra comprida é o que diz que a peça **tem altura** numa projeção
	# ortogonal, que por definição não dá essa pista sozinha.
	sun.rotation_degrees = Vector3(-38.0, -50.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	# Sombra suave e curta: é um brinquedo em cima de uma mesa, não uma paisagem.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = BOARD_SPAN * 2.0
	# Borda macia. A sombra dura de um sol pontual em peças de dois centímetros
	# desenha um recorte de papel ao lado de cada uma; um pouco de borrão devolve
	# a escala de brinquedo em cima de uma mesa.
	sun.shadow_blur = 1.6
	add_child(sun)

	_pivot = Node3D.new()
	add_child(_pivot)
	_camera = Camera3D.new()
	# Perspectiva, e não ortogonal.
	#
	# A ortogonal era defensável — duas casas do mesmo tamanho pareciam do mesmo
	# tamanho — e produzia um tabuleiro que **lia como o desenho 2D inclinado**.
	# Sem convergência não há profundidade, e sem profundidade não há motivo para
	# o jogo ser 3D. A comparação "quanto ele construiu" se resolve no painel da
	# esquerda, onde os números estão escritos, e não medindo casinhas na tela.
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = FOV_DEGREES
	_camera.near = 0.1
	_camera.far = BOARD_SPAN * 4.0
	_pivot.add_child(_camera)
	_place_camera()


## O tampo desenhado, num alvo de render próprio.
##
## `UPDATE_ONCE` e não `UPDATE_ALWAYS`: são 1536² pixels e o tampo fica idêntico
## por dezenas de segundos: ele só muda quando alguém compra, hipoteca ou quebra.
## Redesenhá-lo a cada quadro é o gasto mais fácil de fazer sem perceber neste
## arranjo.
func _build_face() -> void:
	_face_viewport = SubViewport.new()
	_face_viewport.size = Vector2i(FACE_PIXELS, FACE_PIXELS)
	_face_viewport.transparent_bg = false
	_face_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Sem 2D próprio a textura sai preta; e sem desativar o 3D dele, o
	# `SubViewport` tenta renderizar um mundo que não existe.
	_face_viewport.own_world_3d = true
	_face_viewport.disable_3d = true
	add_child(_face_viewport)

	_face = MonopolyFace.new()
	# Tamanho fixo, sem âncora. `PRESET_FULL_RECT` põe as âncoras opostas em 0 e 1,
	# e aí o `size` que se escreve **soma** ao que a âncora já dá: o tampo era
	# desenhado com o dobro do lado e o alvo de render captava só o quadrante de
	# cima à esquerda, ampliado. Com âncora zerada o `Control` mede o que se
	# manda, e a única fonte do tamanho é `FACE_PIXELS`.
	_face.size = Vector2(FACE_PIXELS, FACE_PIXELS)
	_face_viewport.add_child(_face)


## A mesa: uma poça de luz sob o tabuleiro que se apaga para o fundo do app.
##
## É um degradê radial gerado em código, não um arquivo. Três paradas: o miolo
## claro onde a caixa pousa, a queda, e o fim exatamente em `AppTheme.BACKGROUND`
## — que é a cor do `background_color` do ambiente. A partir dali a mesa é
## indistinguível do vazio, então a borda dela não existe para o olho, por mais
## que a câmera livre se afaste ou se abaixe.
##
## Sem textura o mesmo plano era um cinza chapado até a borda, e a borda **era**
## vista: uma linha reta atravessando o fundo da tela no enquadramento que segue o
## peão. Com ela, o tabuleiro passa a estar numa sala escura em vez de num vazio.
##
## Material próprio e não `MonopolyToken.plastic()`: aquele devolve recursos de um
## cache compartilhado, e escrever uma textura num deles pintaria de degradê todo
## objeto que dividisse a mesma cor.
func _table_material() -> StandardMaterial3D:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, TABLE_LIT_AT, TABLE_FADE_AT, 1.0])
	ramp.colors = PackedColorArray([
		TABLE_COLOR.lightened(0.10),
		TABLE_COLOR,
		TABLE_COLOR.lerp(AppTheme.BACKGROUND, 0.75),
		AppTheme.BACKGROUND,
	])

	var glow := GradientTexture2D.new()
	glow.gradient = ramp
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	# 256 basta: é um degradê sem detalhe nenhum, esticado por 109 unidades de
	# mundo. O que contaria como banda a esta escala é a profundidade de cor, e
	# não a resolução.
	glow.width = 256
	glow.height = 256

	var felt := StandardMaterial3D.new()
	felt.albedo_texture = glow
	felt.roughness = 0.98
	felt.metallic = 0.0
	# Sem realce especular: a mesa é feltro, e um ponto de brilho nela chamaria
	# atenção para o único objeto da cena que não deve ser olhado.
	felt.metallic_specular = 0.0
	return felt


func _build_board() -> void:
	# A mesa primeiro: é ela que recebe a sombra de tudo o que vem depois.
	var table := MeshInstance3D.new()
	var surface := PlaneMesh.new()
	surface.size = Vector2(TABLE_SPAN, TABLE_SPAN)
	table.mesh = surface
	table.set_surface_override_material(0, _table_material())
	table.position.y = -0.002
	table.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(table)

	var top := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(BOARD_SPAN, BOARD_SPAN)
	top.mesh = plane
	var material := StandardMaterial3D.new()
	# A textura já **é** a cor: sem isto o tampo recebe o realce especular do sol
	# em cima do texto e o nome da casa fica lavado no ponto de brilho.
	material.roughness = 0.92
	material.metallic_specular = 0.12
	# Mipmap e anisotropia. A fileira do fundo é vista quase de perfil, e ali cada
	# pixel da tela cobre dezenas de pixels da textura: sem uma pirâmide de
	# reduções para amostrar, a placa escolhe **um** deles e o resultado ferve a
	# cada quadro em que a câmera se mexe — é o serrilhado que aparece longe do
	# peão, e não some por mais resolução que se dê à janela.
	#
	# A anisotropia é o que salva justamente o caso rasante: a filtragem
	# isotrópica escolheria um nível de mipmap pelo eixo mais comprimido e borraria
	# o outro, apagando o nome da casa em vez de serrilhá-lo.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# A textura do viewport entra como retrato provisório: ela **não** tem mipmap —
	# alvo de render não tem — e é trocada pela versão assada assim que o tampo
	# termina de ser desenhado. Ver [method _bake_face].
	material.albedo_texture = _face_viewport.get_texture()
	_top_material = material
	top.set_surface_override_material(0, material)
	top.position.y = BOARD_THICKNESS
	# O tampo recebe sombra das peças mas não projeta a própria: ele é a mesa.
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	# Um fio mais baixo que o tampo. Com a mesma altura, a face de cima da caixa e
	# o plano da textura ocupam exatamente o mesmo plano, e o *z-fighting* pinta o
	# tabuleiro da cor da caixa em manchas que mudam conforme a câmera gira.
	#
	# E mais estreito, pelo lábio: o tampo passa a sobrar por cima do corpo, como
	# a tampa de uma caixa de jogo. Antes os dois tinham o mesmo tamanho e a peça
	# lia como uma placa maciça — a borda impressa encostava direto na mesa, sem
	# nada dizendo que aquilo era um objeto de tirar da caixa.
	box.size = Vector3(
		BOARD_SPAN - BOARD_LIP * 2.0, BOARD_THICKNESS - 0.01, BOARD_SPAN - BOARD_LIP * 2.0
	)
	body.mesh = box
	body.set_surface_override_material(0, MonopolyToken.plastic(Face.TILE_LINE, 0.85))
	body.position.y = (BOARD_THICKNESS - 0.01) * 0.5
	add_child(body)

	_build_decks()


## As duas pilhas de cartas no miolo, em cima da moldura que o tampo pinta.
##
## Elas respondem uma pergunta que a tela não respondia: **de onde vem a carta**.
## Até aqui uma casa de Sorte fazia um texto aparecer no aviso sem nenhuma origem
## visível na mesa. A pilha é também o único volume do tabuleiro que não é peça
## nem construção, e é o que impede o miolo — um quinto da área — de ser um
## retângulo bege.
##
## O lugar sai de `Face.deck_spot()`, a mesma função que pinta o contorno: duas
## coordenadas seriam duas ideias de onde é o baralho, e a pilha pousaria ao lado
## do próprio desenho.
func _build_decks() -> void:
	for which in [MonopolyBoard.CHANCE, MonopolyBoard.CHEST]:
		var ink: Color = Face.CHANCE_INK if which == MonopolyBoard.CHANCE else Face.CHEST_INK
		var spot := Face.deck_spot(which)
		var stack := Node3D.new()
		stack.position = Vector3(spot.x, BOARD_THICKNESS, spot.y)
		stack.rotation.y = -Face.DECK_ANGLE
		add_child(stack)

		# Duas caixas, e não uma. Uma caixa de cor só é uma placa de plástico; a
		# **borda colorida sob uma carta clara** é o que lê como um maço — e é o
		# único lugar em que a cor do baralho aparece de longe, porque a carta de
		# cima é clara em qualquer jogo.
		stack.add_child(_deck_slab(
			"deck_wrap", Face.DECK_SIZE, DECK_THICKNESS * 0.62, ink.darkened(0.12),
			DECK_THICKNESS * 0.31
		))
		stack.add_child(_deck_slab(
			"deck_card", Face.DECK_SIZE * 0.93, DECK_THICKNESS * 0.42,
			Face.TILE_FILL.lightened(0.42), DECK_THICKNESS * 0.62 + DECK_THICKNESS * 0.21
		))


func _deck_slab(key: String, plan: Vector2, thick: float, tint: Color, at: float) -> MeshInstance3D:
	var slab := MeshInstance3D.new()
	slab.mesh = MonopolyToken.mesh(key, func() -> Mesh:
		var box := BoxMesh.new()
		box.size = Vector3(plan.x, thick, plan.y)
		return box
	)
	slab.set_surface_override_material(0, MonopolyToken.plastic(tint, 0.9))
	slab.position.y = at
	return slab


## Um quadrado luminoso rente ao tampo, para a casa em foco. Rente e não em cima:
## uma moldura flutuando projetaria sombra e pareceria uma peça.
func _build_highlight() -> void:
	_highlight = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Face.EDGE, Face.CORNER)
	_highlight.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(AppTheme.ACCENT, 0.30)
	_highlight.set_surface_override_material(0, material)
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.visible = false
	add_child(_highlight)


# --- ciclo --------------------------------------------------------------------


func _process(delta: float) -> void:
	if _dirty_face:
		_dirty_face = false
		_face.state = state
		_face.queue_redraw()
		# Dois quadros, e não `UPDATE_ONCE`.
		#
		# `UPDATE_ONCE` renderiza o quadro seguinte e se desliga sozinho — e no
		# primeiro deles o `Control` ainda pode não ter recebido o tamanho do
		# `SubViewport`, porque âncoras são resolvidas **depois** do `_ready`. O
		# resultado é uma textura preta que nunca mais é repintada, porque o
		# gatilho já foi gasto: o tabuleiro nasce sem tampo e nada volta a pedir.
		_face_frames = 2
	if _face_frames > 0:
		_face_frames -= 1
		_face_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if _face_frames > 0 else SubViewport.UPDATE_DISABLED
		)
		if _face_frames == 0:
			_bake_face()

	if not _walk.is_empty():
		_walk["elapsed"] = float(_walk["elapsed"]) + delta
		if float(_walk["elapsed"]) >= float(_walk["duration"]):
			_walk = {}
			_dirty_pieces = true
			_sync_pieces()
			walk_finished.emit()
		else:
			_move_walking_pawn()

	_track_follow(delta)
	if not is_equal_approx(_yaw, _target_yaw):
		_yaw = _approach_angle(_yaw, _target_yaw, delta / TURN_SECONDS * PI)
	# A cada quadro, e não só quando o giro muda: o enquadramento depende do
	# formato da janela, e a janela muda de tamanho sem avisar este nó — ao girar
	# o aparelho, ao abrir o teclado, e no primeiro quadro, quando ela ainda não
	# recebeu o tamanho final. São quatro linhas de trigonometria; medir para
	# evitá-las custaria mais do que fazê-las.
	_place_camera()

	if _dirty_pieces:
		_dirty_pieces = false
		_sync_pieces()


## Copia o tampo recém-desenhado para uma textura **com mipmap**.
##
## Um alvo de render não tem mipmap e não há como pedir que tenha: o `SubViewport`
## entrega o quadro e nada mais. Sem a pirâmide de reduções, a fileira do fundo —
## vista quase de perfil, com cada pixel da tela cobrindo dezenas da textura —
## ferve a cada movimento de câmera. É o serrilhado longe do peão, e ele não some
## por resolução: quanto mais nítida a textura, pior a fervura.
##
## A cópia passa pela CPU, e é por isso que ela mora **aqui** e não num `_process`
## qualquer: este ponto é alcançado quando o tampo termina de ser redesenhado, o
## que acontece na montagem da cena e depois só quando alguém compra, hipoteca,
## constrói ou quebra. São algumas dezenas de vezes numa partida inteira, e cada
## uma cai num instante em que a tela já está anunciando o que aconteceu.
##
## Falhando, o material fica com a textura do viewport — sem mipmap, como antes.
## Um tampo que ferve é pior que um tampo nítido; um tampo preto é pior que os
## dois, e é o que uma imagem vazia daria.
func _bake_face() -> void:
	# Sem servidor de vídeo não há textura para ler de volta, e pedi-la é um erro
	# no console a cada redesenho do tampo. As suítes headless sobem esta cena para
	# provar que ela não quebra, e um tampo que ninguém desenha não precisa de
	# mipmap.
	if DisplayServer.get_name() == "headless":
		return
	var image := _face_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return
	image.generate_mipmaps()
	# Reaproveitada entre as atualizações: `update()` troca os pixels da textura
	# que já está na placa, enquanto criar outra a cada compra deixaria a anterior
	# para o coletor e faria a memória de vídeo subir degrau a degrau ao longo da
	# partida.
	if _face_texture == null:
		_face_texture = ImageTexture.create_from_image(image)
	else:
		_face_texture.update(image)
	_top_material.albedo_texture = _face_texture


## Caminho mais curto entre dois ângulos. Sem isto, ir do assento 3 para o 0 dá a
## volta inteira de 270° em vez dos 90° do outro lado — e o jogador vê o tabuleiro
## girar três vezes mais do que precisava.
static func _approach_angle(from: float, to: float, step: float) -> float:
	var difference := wrapf(to - from, -PI, PI)
	if absf(difference) <= step:
		return to
	return from + signf(difference) * step


## Persegue o peão da vez: leva a mira até ele e vira para o lado em que ele está.
##
## O alvo é amortecido e o giro passa pelo mesmo `_approach_angle` do giro por
## assento. Sem o amortecimento a câmera cola no peão — que **pula** entre casas —
## e o tabuleiro inteiro passa a pular junto, o que embrulha o estômago em três
## segundos.
func _track_follow(delta: float) -> void:
	if free:
		# Na mão do jogador a mira desliza para o meio do tabuleiro.
		#
		# Orbitar em volta do peão pareceria certo e não é: afastando de um canto,
		# o tabuleiro sai do quadro e metade da tela vira fundo. Em volta do centro,
		# a distância sozinha resolve "ver a casa" e "ver o anel inteiro" — e o
		# deslize evita o salto de quem pegou a câmera com o peão enquadrado.
		_focus = _focus.lerp(Vector3.ZERO, minf(1.0, delta * FOLLOW_LERP))
		return
	if follow < 0 or state == null or follow >= MonopolyRules.seats_of(state):
		return
	var tile := MonopolyRules.position_of(state, follow)
	var travel := tile_along(tile)
	# A câmera fica **atrás** do peão, olhando no sentido em que ele anda: o eixo
	# do giro é a direção da caminhada, e não o lado do tabuleiro.
	#
	# `tile_along` aponta para onde os índices crescem, que é para onde se anda.
	# Pondo a câmera em `-travel`, o peão caminha para dentro da tela em vez de
	# atravessá-la de lado.
	#
	# O preço é a legibilidade: a fileira em que ele está passa a ser vista de
	# enfiada, com o texto correndo para longe. É aceitável porque a escritura da
	# casa é justamente o que o painel da direita mostra — o tampo não precisa
	# ser lido de relance quando há um painel dizendo a mesma coisa em letra
	# grande.
	_target_yaw = atan2(-travel.x, -travel.z)

	var spot := _pawn_spot(tile, follow)
	if follow < _pawns.size() and _pawns[follow] != null:
		# Durante a caminhada o peão está entre duas casas, e é dele que a mira
		# sai — o estado já aponta para o destino.
		spot = _pawns[follow].position
	# À frente, para se ver aonde ele vai, e para dentro do tabuleiro. Olhando na
	# direção da caminhada, "para dentro" é a **direita da tela** — então o mesmo
	# empurrão que enche o quadro de tabuleiro também desliza o peão para a
	# esquerda, para longe do painel.
	# À frente do peão, e depois puxada para o meio do tabuleiro.
	#
	# Só "à frente" põe a mira fora do tampo sempre que ele se aproxima de um
	# canto, e a câmera acaba enquadrando o vazio ao lado: metade da tela vira
	# fundo preto. A primeira tentativa de conserto foi prender a mira numa caixa
	# dentro da borda — e a trava brigou com o avanço, empurrando a mira para
	# **trás** do peão, que passou a aparecer no fundo do quadro em vez de na
	# frente dela.
	#
	# A interpolação para o centro faz as duas coisas com um número só: a mira
	# nunca sai do tampo, e o que sobra de avanço continua mostrando aonde ele vai.
	var wanted: Vector3 = (spot + travel * FOLLOW_AHEAD).lerp(Vector3.ZERO, FOLLOW_CENTER_PULL)
	wanted.y = 0.0
	# E depois a coleira, que é o que o puxão não garante.
	#
	# O puxão é uma **preferência** — "olhe mais para dentro quando der" — e uma
	# preferência não impede o caso ruim, só o torna raro. Somado ao avanço, ele
	# punha a mira longe demais do peão: ele vivia na borda esquerda do quadro e,
	# em certas casas, saía dele. Aqui a mira volta para dentro de um raio do
	# peão, custe o que custar ao enquadramento — o peão da vez é o assunto da
	# tela, e uma câmera que o perde não está seguindo ninguém.
	var flat := Vector3(spot.x, 0.0, spot.z)
	if wanted.distance_to(flat) > FOLLOW_LEASH:
		wanted = flat + (wanted - flat).normalized() * FOLLOW_LEASH
	if not _focus_ready:
		_focus_ready = true
		_focus = wanted
		_yaw = _target_yaw
		return
	_focus = _focus.lerp(wanted, minf(1.0, delta * FOLLOW_LERP))


func _place_camera() -> void:
	# Seguindo, o pivô mora junto do peão; enquadrando o tabuleiro, ele mora no
	# meio dele. As duas contas abaixo assumem cada uma o seu.
	_pivot.position = _focus if follow >= 0 or free else Vector3.ZERO
	_pivot.rotation.y = _yaw
	var pitch := deg_to_rad(_free_pitch if free else PITCH_DEGREES)

	if free:
		# Órbita crua: a inclinação e a distância são as que o dedo deixou, e não
		# há enquadramento a calcular — quem enquadra é o jogador.
		_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * _free_distance
		_camera.look_at(_focus, Vector3.UP)
		return

	if follow >= 0:
		_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * FOLLOW_DISTANCE
		_camera.look_at(_focus + Vector3.DOWN * FOLLOW_LOOK_DROP, Vector3.UP)
		return

	# A distância **respira com o giro**, e é preciso.
	#
	# A silhueta de um quadrado girado de θ mede `|cos θ| + |sin θ|` lados: um no
	# repouso e √2 a 45°. Enquadrar sempre pelo pior caso deixaria o tabuleiro
	# pequeno o tempo todo por causa de meio segundo de transição; enquadrar pelo
	# repouso cortaria os quatro cantos no meio do giro. A conta é exata e cabe
	# numa linha, então a câmera afasta na medida em que o tabuleiro cresce e
	# volta sozinha.
	var silhouette := absf(cos(_yaw)) + absf(sin(_yaw))
	var half := BOARD_SPAN * silhouette * 0.5

	# E o quadro **também depende do formato da janela**, que não é o da tela: a
	# coluna dos jogadores come um quarto da largura, e o que sobra para o
	# tabuleiro é bem mais quadrado que 16:9.
	#
	# O `fov` do Godot é vertical, então a largura disponível encolhe junto com a
	# janela — e uma distância afinada num retângulo largo corta o tabuleiro pelos
	# lados assim que ele entra na tela de verdade. Aqui as duas exigências são
	# calculadas e vence a maior.
	var frame := Vector2(get_viewport().get_visible_rect().size)
	var aspect := frame.x / maxf(1.0, frame.y)
	var half_fov := tan(deg_to_rad(FOV_DEGREES) * 0.5)
	# Deitado, o tabuleiro ocupa a altura toda mas achatada pelo seno da
	# inclinação; de lado, ocupa a largura inteira.
	var by_height := half * sin(pitch) / half_fov
	var by_width := half / maxf(0.001, half_fov * aspect)
	var distance := maxf(by_height, by_width) * DISTANCE_FACTOR

	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * distance
	_camera.look_at(Vector3.UP * LOOK_HEIGHT, Vector3.UP)


# --- geometria: casa → mundo --------------------------------------------------


## Centro da casa no plano do tampo.
##
## A conta é a mesma de [monopoly_face.gd], em unidades de mundo em vez de pixels
## — é por isso que `tile_rect` é estática e recebe a escala. O tampo desenhado e
## a peça de pé pousam no mesmo lugar porque consultam a mesma função, e não
## porque duas tabelas foram mantidas iguais à mão.
##
## O tampo é um `PlaneMesh` no plano XZ: o `x` do desenho vira `x` do mundo e o
## `y` do desenho vira `z`, os dois recentrados no meio do tabuleiro.
static func tile_center(tile: int) -> Vector3:
	var rect := Face.tile_rect(tile, 1.0, Vector2.ZERO)
	var middle := rect.get_center() - Vector2.ONE * BOARD_SPAN * 0.5
	return Vector3(middle.x, BOARD_THICKNESS, middle.y)


## "Para dentro do tabuleiro" em vetor de mundo. O mesmo `inward` do desenho, com
## o `y` da tela virando `z`.
static func tile_inward(tile: int) -> Vector3:
	var toward := Face.inward(tile)
	return Vector3(toward.x, 0.0, toward.y)


## Direção comprida da casa: perpendicular ao "dentro", no plano do tampo. É por
## onde os peões e as construções se enfileiram.
static func tile_along(tile: int) -> Vector3:
	var toward := tile_inward(tile)
	return Vector3(toward.z, 0.0, -toward.x)


## Profundidade da casa — do lado de dentro ao de fora. Um no meio de um lado,
## `CORNER` no canto.
static func tile_depth(tile: int) -> float:
	return Face.CORNER


## Largura da casa ao longo do lado. É o que limita quantos peões cabem lado a
## lado antes de encostarem.
static func tile_width(tile: int) -> float:
	return Face.CORNER if Face.is_corner(tile) else Face.EDGE


## Ponto na casa a uma fração da profundidade, contada da borda de **dentro**. As
## frações vêm do desenho (`Face.BAND_AT`, `Face.PAWN_AT`), então a casinha pousa
## exatamente sobre a faixa de cor pintada, e não perto dela.
static func tile_spot(tile: int, depth_fraction: float, offset: float) -> Vector3:
	var depth := tile_depth(tile)
	return (
		tile_center(tile)
		+ tile_inward(tile) * (depth * 0.5 - depth * depth_fraction)
		+ tile_along(tile) * offset
	)


# --- peças --------------------------------------------------------------------


## Refaz peões e construções a partir do estado.
##
## Reconstrói em vez de atualizar: são no máximo 6 peões e 32 construções, e
## comparar o que mudou custaria mais código do que refazer. O que **não** se
## refaz é a malha — ela é compartilhada, e o que se cria é a instância.
func _sync_pieces() -> void:
	for child in _pieces.get_children():
		child.queue_free()
	_pawns.clear()
	if state == null:
		return

	for tile in MonopolyBoard.SIZE:
		_spawn_buildings(tile)

	var traveller := int(_walk["player"]) if not _walk.is_empty() else -1
	for player in MonopolyRules.seats_of(state):
		if MonopolyRules.is_out(state, player):
			_pawns.append(null)
			continue
		var pawn := _spawn_pawn(player)
		_pawns.append(pawn)
		if player != traveller:
			var tile := MonopolyRules.position_of(state, player)
			pawn.position = _pawn_spot(tile, player)
			_face_along(pawn, tile)

	if not _walk.is_empty():
		_move_walking_pawn()

	_highlight.visible = focused >= 0
	if focused >= 0:
		var plane: PlaneMesh = _highlight.mesh
		plane.size = Vector2(tile_width(focused), tile_depth(focused))
		_highlight.position = tile_center(focused) + Vector3.UP * 0.004
		# O canto é quadrado e o texto dele é diagonal: girar o realce junto com o
		# texto poria um losango em cima de um quadrado.
		_highlight.rotation.y = 0.0 if Face.is_corner(focused) else -Face.text_angle(focused)


func _spawn_buildings(tile: int) -> void:
	var built := MonopolyRules.houses_on(state, tile)
	if built <= 0:
		return
	if built >= MonopolyBoard.HOTEL:
		var hotel := _make_building(HOTEL_WIDTH, AppTheme.DANGER)
		hotel.position = tile_spot(tile, Face.BAND_AT, 0.0)
		hotel.rotation.y = -Face.text_angle(tile)
		_pieces.add_child(hotel)
		return
	for index in built:
		var house := _make_building(HOUSE_WIDTH, AppTheme.SUCCESS)
		# Quatro vagas ao longo da casa, ocupadas da esquerda para a direita: é
		# como elas aparecem no tabuleiro de papelão, e é o que faz "três casas"
		# ser contável de relance em vez de medido.
		var slot := (index + 0.5) / 4.0 - 0.5
		house.position = tile_spot(tile, Face.BAND_AT, slot * tile_width(tile))
		house.rotation.y = -Face.text_angle(tile)
		_pieces.add_child(house)


## Casa e hotel são o mesmo volume em duas larguras: uma caixa com telhado de
## duas águas. O hotel é largo e vermelho, a casa é quadrada e verde — as duas
## diferenças juntas, porque só a cor não sobrevive a quem não distingue verde de
## vermelho.
func _make_building(width: float, color: Color) -> Node3D:
	var node := Node3D.new()
	var walls := MeshInstance3D.new()
	walls.mesh = MonopolyToken.mesh("walls_%.2f" % width, func() -> Mesh:
		var box := BoxMesh.new()
		box.size = Vector3(width, BUILDING_WALLS, BUILDING_DEPTH)
		return box
	)
	walls.set_surface_override_material(0, MonopolyToken.plastic(color, 0.55))
	walls.position.y = BUILDING_WALLS * 0.5
	node.add_child(walls)

	var roof := MeshInstance3D.new()
	roof.mesh = MonopolyToken.mesh("roof_%.2f" % width, func() -> Mesh:
		var prism := PrismMesh.new()
		prism.size = Vector3(width, BUILDING_ROOF, BUILDING_DEPTH)
		return prism
	)
	roof.set_surface_override_material(0, MonopolyToken.plastic(color.darkened(0.28), 0.55))
	roof.position.y = BUILDING_WALLS + BUILDING_ROOF * 0.5
	node.add_child(roof)
	return node


## A peça deste assento: chapéu, carro, avião, bola, barco ou bota.
##
## A forma vem de [monopoly_token.gd] e a cor continua sendo a do jogador. As
## duas coisas juntas, e não uma ou outra: a cor é o que liga a peça à faixa da
## coluna da esquerda, e a forma é o que se reconhece de relance num anel com
## seis peças espalhadas.
##
## Aqui ficou só o que depende do **estado da partida** — o anel de preso —,
## porque o arquivo das peças não conhece regra nenhuma.
func _spawn_pawn(player: int) -> Node3D:
	var color: Color = Face.PLAYER_COLORS[player % Face.PLAYER_COLORS.size()]
	var node := MonopolyToken.build(player, color)

	if MonopolyRules.in_jail(state, player):
		# Preso é uma condição, não um lugar: a peça fica na mesma casa 10 de quem
		# está de visita, e sem esta marca as duas situações são idênticas.
		var ring := MeshInstance3D.new()
		ring.mesh = MonopolyToken.mesh("jail_ring", func() -> Mesh:
			var torus := TorusMesh.new()
			torus.inner_radius = 0.26
			torus.outer_radius = 0.31
			return torus
		)
		var mark := MonopolyToken.plastic(AppTheme.DANGER, 0.4)
		mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.set_surface_override_material(0, mark)
		ring.position.y = 0.01
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(ring)

	_pieces.add_child(node)
	return node


## Vira a peça para o sentido em que se anda naquela casa.
##
## `tile_along` aponta para onde os índices crescem, que é para onde se caminha.
## As peças são modeladas com a frente em -Z, e a mesma conta do giro da câmera
## alinha as duas: o carro anda de frente, o avião voa para onde vai, e o anel
## passa a ter sentido em vez de ser uma coleção de objetos parados.
static func _face_along(node: Node3D, tile: int) -> void:
	var travel := tile_along(tile)
	node.rotation.y = atan2(-travel.x, -travel.z)


## Onde o peão deste jogador pousa na casa.
##
## O espaçamento sai de **quem está nesta casa**, e não do número do assento.
## Reservar uma vaga fixa para os seis significaria seis vagas numa casa de uma
## unidade, e o peão sozinho — que é o caso quase sempre — apareceria deslocado
## para o canto por causa de cinco peões que não estão ali.
func _pawn_spot(tile: int, player: int) -> Vector3:
	var here := _occupants(tile)
	var index := here.find(player)
	var count := here.size()
	# Quem está de passagem não divide a casa com ninguém: ele atravessa dez
	# delas por lance e não pode ser empurrado para o canto de cada uma.
	if index < 0:
		index = 0
		count = 1
	var room := tile_width(tile)
	# No máximo o tamanho da peça mais uma folga: mais que isso espalha peças que
	# caberiam juntas, menos que isso as faz se atravessar.
	var spacing := minf(MonopolyToken.footprint() * 1.08, room / maxf(1.0, float(count)))
	var offset := (index - (count - 1) * 0.5) * spacing
	# No canto o nome vem para fora e a peça fica depois dele; no meio de um lado
	# ela fica entre a faixa de cor e o nome. Os dois números saem do mesmo eixo do
	# desenho, então peça e palavra nunca disputam o mesmo lugar.
	return tile_spot(
		tile, Face.CORNER_PAWN_AT if Face.is_corner(tile) else Face.PAWN_AT, offset
	)


## Quem está **parado** nesta casa, em ordem de assento. Eliminado não conta — não
## tem mais peão. Quem está andando também não: o estado já diz que ele chegou, e
## contá-lo no destino empurraria para o lado os peões que já estão lá, meio
## segundo antes de ele encostar neles.
func _occupants(tile: int) -> PackedInt32Array:
	var here := PackedInt32Array()
	if state == null:
		return here
	var traveller := int(_walk["player"]) if not _walk.is_empty() else -1
	for player in MonopolyRules.seats_of(state):
		if player == traveller or MonopolyRules.is_out(state, player):
			continue
		if MonopolyRules.position_of(state, player) == tile:
			here.append(player)
	return here


# --- caminhada ----------------------------------------------------------------


## Anda o peão pelas casas de `path`, na ordem. A cena monta o caminho porque é
## ela que sabe a regra: uma rolagem anda casa a casa, uma carta de "avance até"
## atravessa o tabuleiro pelo mesmo caminho, e "volte três casas" anda para trás.
##
## `from` é a casa de onde ele sai, que o estado já não tem — quem chama leu antes
## de aplicar o lance. **O estado já é o final**, e quem anda é o desenho: uma
## posição intermediária guardada no `MatchState` seria um segundo tabuleiro, que
## discorda do verdadeiro no primeiro bug, e é o verdadeiro que viaja pela rede.
func walk(player: int, from: int, path: PackedInt32Array) -> void:
	if path.is_empty():
		walk_finished.emit()
		return
	# A caminhada **não** mexe na câmera.
	#
	# Ela retomava o acompanhamento sozinha, com o argumento de que o peão andando
	# é o momento em que a câmera automática vale o que custa. O argumento é bom e
	# a conclusão estava errada: quem pegou a câmera pegou para olhar alguma coisa,
	# e um peão qualquer andando do outro lado do tabuleiro desfazia o
	# enquadramento sem ninguém ter pedido — a cada turno, inclusive nos dos
	# outros jogadores.
	#
	# Uma vista que se desfaz sozinha não é uma vista que se possa usar. Quem
	# quiser o acompanhamento de volta toca em "Recentrar", que existe para isso e
	# está na tela justamente enquanto a câmera está solta.
	_walk = {
		"player": player,
		"from": from,
		"path": path,
		"elapsed": 0.0,
		"duration": path.size() * STEP_SECONDS,
	}
	_dirty_pieces = true


func _move_walking_pawn() -> void:
	var player := int(_walk["player"])
	if player >= _pawns.size() or _pawns[player] == null:
		return
	var path: PackedInt32Array = _walk["path"]
	var ratio := clampf(
		float(_walk["elapsed"]) / maxf(0.001, float(_walk["duration"])), 0.0, 1.0
	)
	var travelled := ratio * path.size()
	var step := mini(floori(travelled), path.size() - 1)
	var between := travelled - step
	var from := _pawn_spot(int(_walk["from"]) if step == 0 else path[step - 1], player)
	var to := _pawn_spot(path[step], player)
	# Um pulo por casa, e não um por lance: `between` volta a zero a cada casa, e
	# é isso que faz uma rolagem de 8 parecer oito passos em vez de um voo.
	_pawns[player].position = from.lerp(to, between) + Vector3.UP * sin(between * PI) * HOP_HEIGHT
	# Vira ao entrar na casa nova, e não no meio do salto: dobrar a esquina no ar
	# faz o carro girar em torno do próprio eixo entre duas casas.
	_face_along(_pawns[player], path[step])


# --- toque --------------------------------------------------------------------


## Um gesto só faz duas coisas, e o que as separa é a distância.
##
## Encostar e soltar sem sair do lugar abre a casa; encostar e arrastar gira a
## mesa. Os dois começam idênticos — um dedo pousando —, então a decisão só pode
## ser tomada depois, e é `DRAG_SLOP` quem a toma.
##
## Dois dedos são pinça, e nada além disso. Girar com dois seria ambíguo com a
## pinça (dois dedos que se afastam também se movem), e panorâmica com dois é o
## que o acompanhamento automático já faz melhor.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		# O primeiro toque de verdade **apaga o dedo que o mouse emulado deixou**.
		#
		# No Android o `emulate_mouse_from_touch` vem ligado de fábrica e cada dedo
		# gera os dois eventos. Se o do mouse chega primeiro, ele registra o
		# ponteiro -1 antes de `_touch_device` existir — e a partir daí a mesa tem
		# dois "dedos" com um dedo só encostado, então todo arrasto era lido como
		# pinça. Era exatamente o sintoma: no aparelho só o zoom respondia.
		if not _touch_device:
			_touch_device = true
			_touches.erase(-1)
			_dragging = false
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton and not _touch_device:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and not _touch_device:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_moved(motion.position, motion.relative)
			get_viewport().set_input_as_handled()


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		_touches[touch.index] = touch.position
		if _touches.size() == 1:
			_press_at = touch.position
			_dragging = false
		return
	# Soltou sem ter arrastado, e era o único dedo: isto foi um toque numa casa.
	var was_tap := _touches.size() == 1 and not _dragging
	_touches.erase(touch.index)
	if _touches.is_empty():
		_dragging = false
	if was_tap:
		_tap(touch.position)


func _on_drag(drag: InputEventScreenDrag) -> void:
	_touches[drag.index] = drag.position
	if _touches.size() >= 2:
		_pinch(drag)
	else:
		_moved(drag.position, drag.relative)
	get_viewport().set_input_as_handled()


## Um ponteiro se moveu com o dedo ou o botão em baixo.
##
## A folga é medida contra **onde o gesto começou**, e não contra o passo
## anterior: um arrasto lento entrega dez eventos de um pixel cada, e comparar
## passo a passo nunca alcançaria o limiar — o gesto ficaria sendo toque para
## sempre, girando a mesa sem nunca abrir a casa nem terminar de decidir.
func _moved(position: Vector2, relative: Vector2) -> void:
	if not _dragging:
		if position.distance_to(_press_at) < DRAG_SLOP:
			return
		_dragging = true
	_orbit(relative)


func _on_mouse_button(click: InputEventMouseButton) -> void:
	match click.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if click.pressed:
				_zoom(-ZOOM_PER_NOTCH)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if click.pressed:
				_zoom(ZOOM_PER_NOTCH)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if click.pressed:
				_touches[-1] = click.position
				_press_at = click.position
				_dragging = false
				return
			var was_tap := not _dragging
			_touches.erase(-1)
			_dragging = false
			if was_tap:
				_tap(click.position)


func _tap(point: Vector2) -> void:
	var tile := pick(point)
	if tile >= 0:
		get_viewport().set_input_as_handled()
		tile_tapped.emit(tile)


## Gira e inclina. O primeiro arrasto **tira a câmera do automático**: enquanto o
## jogador está segurando a mesa, o acompanhamento puxando para o peão da vez
## seria a tela brigando com o dedo.
func _orbit(motion: Vector2) -> void:
	if not free:
		_enter_free()
	_target_yaw = wrapf(_target_yaw - motion.x * ORBIT_PER_PIXEL, -PI, PI)
	# Sem amortecimento no giro manual: aqui o dedo **é** o alvo, e interpolar
	# para ele acrescentaria um atraso entre a mão e a mesa.
	_yaw = _target_yaw
	_free_pitch = clampf(
		_free_pitch + motion.y * ORBIT_PER_PIXEL * 34.0, FREE_PITCH_MIN, FREE_PITCH_MAX
	)


func _pinch(drag: InputEventScreenDrag) -> void:
	if not free:
		_enter_free()
	var others := []
	for index in _touches:
		if index != drag.index:
			others.append(_touches[index])
	if others.is_empty():
		return
	var anchor: Vector2 = others[0]
	var now := drag.position.distance_to(anchor)
	var before := (drag.position - drag.relative).distance_to(anchor)
	_zoom((before - now) * ZOOM_PER_PIXEL)


func _zoom(amount: float) -> void:
	if not free:
		_enter_free()
	_free_distance = clampf(
		_free_distance + amount, FREE_DISTANCE_MIN, FREE_DISTANCE_MAX
	)


## Semeia a câmera livre com o enquadramento que está na tela agora.
##
## Sem isto, pegar a câmera durante um acompanhamento saltaria da distância de
## terceira pessoa para o valor guardado da última vez — e o jogador veria a mesa
## pular antes de ela responder ao dedo.
func _enter_free() -> void:
	free = true
	_free_pitch = PITCH_DEGREES
	_free_distance = FOLLOW_DISTANCE if follow >= 0 else _free_distance
	camera_freed.emit()


## Devolve a câmera ao automático.
func recenter() -> void:
	if not free:
		return
	free = false
	_focus_ready = false
	camera_freed.emit()


## Casa sob o ponto da tela, ou -1.
##
## Projeta o toque no plano do tampo e devolve a conta ao espaço do desenho. Não
## há corpo de colisão nenhum: o tabuleiro é **plano**, então a interseção tem
## solução fechada, e 40 `StaticBody3D` só para descobrir em qual retângulo o
## ponto caiu seriam 40 nós fazendo à mão o que uma divisão resolve.
func pick(point: Vector2) -> int:
	if _camera == null:
		return -1
	var origin := _camera.project_ray_origin(point)
	var direction := _camera.project_ray_normal(point)
	if is_zero_approx(direction.y):
		return -1
	var distance := (BOARD_THICKNESS - origin.y) / direction.y
	if distance < 0.0:
		return -1
	var hit := origin + direction * distance
	# De volta ao espaço do desenho: o tampo é o mesmo retângulo, recentrado.
	var flat := Vector2(hit.x, hit.z) + Vector2.ONE * BOARD_SPAN * 0.5
	for tile in MonopolyBoard.SIZE:
		if Face.tile_rect(tile, 1.0, Vector2.ZERO).has_point(flat):
			return tile
	return -1


