extends Control

## Entrar numa partida que já existe.
##
## Tela própria, alcançada por um botão da tela inicial, e **sem passar pela
## escolha do jogo**: quem entra joga o que o anfitrião abriu, então perguntar
## "xadrez ou damas?" antes de mostrar a lista só servia para o jogador
## descobrir depois que a única sala aberta era do outro jogo. Escolher jogo
## ficou sendo só o caminho de *criar* partida.
##
## O conteúdo é `ui/join_panel.tscn` inteiro — os quatro caminhos até uma sala.
## O que esta cena acrescenta é o que só uma tela sabe: o título, o caminho de
## volta, o toast dos erros e para onde ir quando o anfitrião responde.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

var _waiting: WaitingPanel = null


func _on_waiting(game_id: StringName, code: String, taken: int, capacity: int) -> void:
	_waiting.show_room(game_id, code, taken, capacity)


## Desistir fecha o painel e **larga a cadeira**, e continua na tela de entrar: a
## intenção de quem desiste de uma sala costuma ser tentar outra, não sair.
func _on_give_up() -> void:
	%JoinPanel.give_up()
	_waiting.hide_room()


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	%JoinPanel.failed.connect(_show_error)
	%JoinPanel.waiting.connect(_on_waiting)
	%JoinPanel.waiting_ended.connect(func() -> void: _waiting.hide_room())

	# Fora da área segura e por cima de tudo: durante a espera não há mais nada
	# nesta tela em que se possa tocar.
	_waiting = WaitingPanel.new()
	_waiting.set_anchors_preset(Control.PRESET_FULL_RECT)
	_waiting.cancelled.connect(_on_give_up)
	add_child(_waiting)
	Net.opponent_joined.connect(_on_opponent_joined)
	# Mesa de mais de dois: a partida começa quando ela enche.
	Net.table_ready.connect(_on_table_ready)
	# A mesma barra e a mesma gaveta da tela inicial: multiplayer não é uma etapa
	# dentro da coleção de jogos, é um lugar do app ao lado dela. Com uma seta de
	# voltar ele pareceria um desvio do caminho de escolher jogo, que é
	# exatamente o que ele não é.
	%AppBar.title = "Olá, %s!" % Prefs.player_name()
	%AppBar.leading = IconButton.Kind.MENU
	%AppBar.action = IconButton.Kind.GEAR
	%AppBar.leading_pressed.connect(_open_drawer)
	%AppBar.action_pressed.connect(_open_settings)
	%Unavailable.visible = not Net.relay_available()

	# Um QR lido antes de o Android recolher o app: a tela inicial recuperou o
	# payload e mandou junto, e o pareamento continua como se tivesse acabado de
	# ser lido.
	if not Game.join_info.is_empty():
		var pending := Game.join_info
		Game.join_info = {}
		%JoinPanel.join_payload(pending)


## Mesa cheia num jogo de mais de dois. O assento é a identidade — no Ludo, a
## cor que se joga —, e é a única coisa que muda em relação ao caminho de dois.
func _on_table_ready(_seats: int) -> void:
	Game.local_seat = Net.local_seat
	_enter_match()


func _on_opponent_joined(_remote_side: int) -> void:
	Game.local_side = Net.local_side
	_enter_match()


## O aperto de mão é onde quem entrou descobre o que foi realmente aberto: o
## jogo, o ritmo e o lugar na mesa. Nada disso vem do código digitado nem do
## cartão tocado — quem entrou numa sala de damas com o app aberto no xadrez
## chega no jogo certo por aqui.
func _enter_match() -> void:
	Game.game_id = Net.game_id
	Game.time_control = Net.time_control
	Pairing.nfc.stop()
	Pairing.qr_scanner.stop()
	# Depois de `Game.game_id` receber o valor do aperto de mão, e não antes: cada
	# jogo tem a sua cena de partida.
	get_tree().change_scene_to_file(Game.match_scene())


## Toast no topo, e não a linha de status do painel. A distinção entre os dois é
## o que acontece *sozinho* e o que **muda o que o jogador deve fazer**: um
## código digitado errado ou um QR de outro app precisam ser lidos, e uma linha
## de rodapé é onde um texto morre sem ninguém ver.
func _show_error(message: String) -> void:
	%Toast.show_message(message, Banner.Kind.DANGER)


## A gaveta, montada a cada abertura como na tela inicial. Marcada em
## `MULTIPLAYER`: é onde o jogador está, e uma gaveta que não diz isso é uma lista
## de links.
func _open_drawer() -> void:
	if _drawer() != null:
		return
	var drawer := NavDrawer.new()
	drawer.current = NavDrawer.MULTIPLAYER
	drawer.picked.connect(_go)
	add_child(drawer)
	drawer.open()


func _go(route: StringName) -> void:
	match route:
		NavDrawer.HOME:
			_back_to_menu()
		# Já se está aqui.
		NavDrawer.MULTIPLAYER:
			return
		NavDrawer.SETTINGS:
			_open_settings()


func _drawer() -> NavDrawer:
	for child in get_children():
		if child is NavDrawer:
			return child as NavDrawer
	return null


func _open_settings() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(SETTINGS_SCENE)


## Com a gaveta aberta o gesto fecha **ela**; sem ela, volta para a coleção de
## jogos, que é de onde se chegou aqui em todos os caminhos.
func go_back() -> void:
	var drawer := _drawer()
	if drawer != null:
		drawer.close()
		return
	_back_to_menu()


func _back_to_menu() -> void:
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
