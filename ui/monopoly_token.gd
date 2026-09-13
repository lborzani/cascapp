class_name MonopolyToken

## As seis peças de Metrópole: chapéu, carro, avião, bola, barco e bota.
##
## Uma por assento, e a cor **continua** sendo a do jogador. As duas coisas
## juntas, e não uma ou outra: a cor é o que liga a peça à faixa da coluna da
## esquerda, e a forma é o que se reconhece de relance num tabuleiro com seis
## peças espalhadas — a cor sozinha falha em quem não distingue vermelho de
## verde, e a forma sozinha obrigaria a decorar qual é a sua.
##
## ## Primitivas, e não malhas importadas
##
## Cada peça é meia dúzia de caixas, cilindros e prismas. É a mesma decisão do
## peão que estas substituem, e ela se sustenta melhor aqui: o estilo é de
## **brinquedo de plástico**, que é exatamente o que primitivas produzem sem
## esforço, e o que se lê a 42° de inclinação é a silhueta, não o detalhe.
##
## As seis silhuetas foram escolhidas para **não se confundirem vistas de cima**:
## disco com aba (chapéu), retângulo com rodas (carro), cruz (avião), esfera
## (bola), casco com vela triangular (barco) e um "L" deitado (bota).
##
## Uma malha importada custaria o arquivo no repositório, a licença a conferir, a
## escala e a orientação a acertar peça por peça, e o tingimento por jogador —
## que numa malha pronta é sobrescrever o material dela e torcer para o mapa de
## UV não depender da cor. Seis silhuetas é o que este jogo precisa, e é o que
## cabe em código.
##
## ## A peça aponta para onde se anda
##
## `tile_along` é a direção em que os índices crescem, que é a direção da
## caminhada. Todas as peças são modeladas com a frente em **-Z** e giradas por
## quem as posiciona, então o carro anda de frente e o avião voa para onde vai —
## o anel passa a ter sentido em vez de ser uma coleção de objetos parados.
##
## ## O cache é estático de propósito
##
## Malha e material aqui são constantes do jogo: a mesma caixa de roda serve às
## quatro rodas dos seis carros de todas as partidas da sessão. Guardá-los num
## dicionário estático é o que permite ao renderizador agrupar as instâncias, e
## o que sobra vivo entre partidas são algumas dezenas de recursos minúsculos.

enum Kind { HAT, CAR, PLANE, BALL, BOAT, BOOT }

## Ordem de distribuição pelos assentos. Chapéu e carro primeiro porque são as
## duas mais reconhecíveis, e mesa de dois é o caso mais comum depois do de
## quatro.
const ORDER := [Kind.HAT, Kind.CAR, Kind.PLANE, Kind.BALL, Kind.BOAT, Kind.BOOT]

## Raio do pedestal comum. Casa com o espaçamento de peões do tabuleiro: quatro
## peças ainda cabem lado a lado numa casa de borda sem encostar.
const BASE_RADIUS := 0.17
const BASE_HEIGHT := 0.028

## Escala geral, aplicada na raiz da peça.
##
## As medidas de baixo foram desenhadas em proporção umas às outras — a roda cabe
## sob a carroceria, a vela cabe no mastro — e mexer nelas uma a uma para a peça
## crescer é a forma de quebrar todas as proporções de uma vez. Um número na raiz
## cresce o conjunto inteiro.
##
## Um e pouco porque a câmera de jogo fica **perto**: no enquadramento de
## tabuleiro inteiro as peças em tamanho de escritura sumiriam, mas esse
## enquadramento não é o que se joga.
const SCALE := 1.16


## Diâmetro que a peça ocupa na casa, já com a escala.
##
## É o que o tabuleiro usa para espaçar duas peças na mesma casa. Público porque
## esse número **é** o tamanho da peça, e deixá-lo do outro lado seria uma
## constante de espaçamento que se esquece de acompanhar quando a peça cresce.
static func footprint() -> float:
	return BASE_RADIUS * SCALE * 2.0

## Malhas e materiais, compartilhados por todas as instâncias e todas as
## partidas. Ver o cabeçalho.
static var _meshes := {}
static var _materials := {}


static func kind_for(player: int) -> int:
	return ORDER[player % ORDER.size()]


## A peça deste assento, montada e tingida, apoiada em y = 0 e apontando para -Z.
static func build(player: int, tint: Color) -> Node3D:
	var node := Node3D.new()
	node.scale = Vector3.ONE * SCALE
	node.add_child(_disc("base", BASE_RADIUS, BASE_RADIUS * 1.02, BASE_HEIGHT, tint.darkened(0.30)))

	match kind_for(player):
		Kind.HAT:
			_build_hat(node, tint)
		Kind.CAR:
			_build_car(node, tint)
		Kind.PLANE:
			_build_plane(node, tint)
		Kind.BALL:
			_build_ball(node, tint)
		Kind.BOAT:
			_build_boat(node, tint)
		Kind.BOOT:
			_build_boot(node, tint)
	return node


# --- as seis ------------------------------------------------------------------


## Aba larga e copa alta. A aba é o que se vê de cima e a copa é o que se vê de
## lado, então ela sobrevive aos dois ângulos que a câmera usa.
static func _build_hat(node: Node3D, tint: Color) -> void:
	node.add_child(_disc("hat_brim", 0.165, 0.165, 0.022, tint, 0.045))
	node.add_child(_disc("hat_crown", 0.098, 0.104, 0.215, tint, 0.163))
	# A fita é a única coisa que impede a copa de ler como um carretel.
	node.add_child(_disc("hat_band", 0.108, 0.108, 0.035, tint.darkened(0.42), 0.078))


## Carroceria, cabine recuada e quatro rodas. As rodas são o que faz a caixa
## virar carro — sem elas, é uma caixa.
static func _build_car(node: Node3D, tint: Color) -> void:
	node.add_child(_box("car_body", Vector3(0.17, 0.085, 0.33), tint, Vector3(0.0, 0.098, 0.0)))
	# Recuada, e mais estreita: é o degrau da cabine que dá frente e traseira ao
	# carro visto de cima, e sem ele os dois lados são iguais.
	node.add_child(_box("car_cab", Vector3(0.135, 0.072, 0.145), tint.lightened(0.14), Vector3(0.0, 0.176, 0.045)))
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var wheel := _disc("car_wheel", 0.05, 0.05, 0.032, tint.darkened(0.55))
			# Cilindro nasce com o eixo em Y; a roda gira em torno de X.
			wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			wheel.position = Vector3(side * 0.088, 0.05, end * 0.105)
			node.add_child(wheel)


## Fuselagem, asa e cauda. É a peça que fala com o tabuleiro: as quatro ferrovias
## do jogo original viraram quatro aeroportos aqui.
static func _build_plane(node: Node3D, tint: Color) -> void:
	var body := _capsule("plane_body", 0.046, 0.20, tint, Vector3(0.0, 0.115, 0.0))
	# Cápsula nasce de pé; o avião é comprido em Z.
	body.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	node.add_child(body)
	node.add_child(_box("plane_wing", Vector3(0.33, 0.018, 0.085), tint.lightened(0.12), Vector3(0.0, 0.108, 0.012)))
	node.add_child(_box("plane_tail_h", Vector3(0.135, 0.016, 0.05), tint.lightened(0.12), Vector3(0.0, 0.112, 0.128)))
	node.add_child(_box("plane_fin", Vector3(0.016, 0.085, 0.07), tint.darkened(0.25), Vector3(0.0, 0.158, 0.135)))


## Uma esfera e nada mais. É a única silhueta redonda do conjunto, e qualquer
## detalhe a mais só a faria parecer outra coisa.
static func _build_ball(node: Node3D, tint: Color) -> void:
	node.add_child(_ball("ball", 0.135, tint, 0.163))


## Casco, mastro e vela. A vela triangular é a silhueta — o casco sozinho seria
## um sabonete.
static func _build_boat(node: Node3D, tint: Color) -> void:
	node.add_child(_box("boat_hull", Vector3(0.155, 0.07, 0.26), tint, Vector3(0.0, 0.063, 0.02)))
	# Proa em cunha: dá frente ao casco, que de cima é simétrico sem ela.
	var bow := _prism("boat_bow", Vector3(0.155, 0.07, 0.11), tint, Vector3(0.0, 0.063, -0.15))
	bow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	node.add_child(bow)
	node.add_child(_disc("boat_mast", 0.012, 0.014, 0.24, tint.darkened(0.45), 0.218))
	node.add_child(_prism("boat_sail", Vector3(0.145, 0.20, 0.014), tint.lightened(0.22), Vector3(0.045, 0.22, 0.0)))


## Cano e pé, em "L". A única peça do conjunto assimétrica de cima, e é por isso
## que ela não se confunde com o carro apesar de as duas serem caixas.
static func _build_boot(node: Node3D, tint: Color) -> void:
	node.add_child(_box("boot_leg", Vector3(0.105, 0.24, 0.105), tint, Vector3(0.0, 0.148, 0.075)))
	node.add_child(_box("boot_foot", Vector3(0.105, 0.075, 0.215), tint, Vector3(0.0, 0.065, -0.02)))
	node.add_child(_box("boot_sole", Vector3(0.115, 0.028, 0.225), tint.darkened(0.45), Vector3(0.0, 0.042, -0.022)))


# --- primitivas ---------------------------------------------------------------


static func _box(key: String, dimensions: Vector3, tint: Color, at: Vector3) -> MeshInstance3D:
	return _piece(key, tint, at, func() -> Mesh:
		var box := BoxMesh.new()
		box.size = dimensions
		return box
	)


static func _prism(key: String, dimensions: Vector3, tint: Color, at: Vector3) -> MeshInstance3D:
	return _piece(key, tint, at, func() -> Mesh:
		var prism := PrismMesh.new()
		prism.size = dimensions
		return prism
	)


static func _disc(
	key: String, top: float, bottom: float, height: float, tint: Color, at := 0.0
) -> MeshInstance3D:
	return _piece(key, tint, Vector3(0.0, at if at > 0.0 else height * 0.5, 0.0), func() -> Mesh:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = top
		cylinder.bottom_radius = bottom
		cylinder.height = height
		# Dezesseis lados: a peça mede um sexto de casa na tela, e a diferença para
		# 32 não aparece nem no print em 1280.
		cylinder.radial_segments = 16
		return cylinder
	)


static func _capsule(key: String, radius: float, height: float, tint: Color, at: Vector3) -> MeshInstance3D:
	return _piece(key, tint, at, func() -> Mesh:
		var capsule := CapsuleMesh.new()
		capsule.radius = radius
		capsule.height = height
		capsule.radial_segments = 12
		capsule.rings = 4
		return capsule
	)


static func _ball(key: String, radius: float, tint: Color, at: float) -> MeshInstance3D:
	return _piece(key, tint, Vector3(0.0, at, 0.0), func() -> Mesh:
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 18
		sphere.rings = 9
		return sphere
	)


static func _piece(key: String, tint: Color, at: Vector3, make: Callable) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh(key, make)
	node.set_surface_override_material(0, plastic(tint, 0.42))
	node.position = at
	return node


## Plástico fosco: sem metal, sem reflexo de ambiente, um brilho de leve. É o que
## faz seis cores fortes conviverem sem nenhuma parecer molhada.
##
## Público e estático porque o tabuleiro usa o mesmo material para as construções
## e para o corpo da caixa — duas fábricas de plástico dariam dois acabamentos
## para o mesmo brinquedo.
static func plastic(color: Color, roughness: float) -> StandardMaterial3D:
	var key := "%s_%.2f" % [color.to_html(true), roughness]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = 0.0
		material.metallic_specular = 0.35
		_materials[key] = material
	return _materials[key]


## Malha compartilhada por chave. Sessenta casinhas verdes com sessenta
## `BoxMesh` idênticos são sessenta recursos que o renderizador não agrupa.
static func mesh(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]
