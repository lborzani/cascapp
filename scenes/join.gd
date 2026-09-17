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
var _sheet: GameSheet = null
var _leaving := false


func _on_waiting(
	game_id: StringName, code: String, present: PackedInt32Array, capacity: int, local_seat: int
) -> void:
	_waiting.show_room(game_id, code, present, capacity, local_seat)


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
	%AppBar.title = "Online"
	# Aba é lugar, e de um lugar não se volta: quem quer outro lugar toca noutra aba.
	%AppBar.leading = -1
	%Unavailable.visible = not Net.relay_available()

	%Tabs.current = AppTabs.ONLINE
	%Tabs.picked.connect(_go_tab)

	# A folha do jogo também mora aqui: a fileira de "Criar sala" abre a mesma folha
	# do cardápio, já em Online.
	_sheet = GameSheet.new()
	add_child(_sheet)
	_sheet.confirmed.connect(_launch)
	%JoinPanel.create_requested.connect(_create_room)

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


func _create_room(id: StringName) -> void:
	Sound.play(Sound.Cue.TAP)
	_sheet.open(id, Game.Mode.ONLINE)


func _launch(mode: int) -> void:
	if _leaving:
		return
	_leaving = true
	GameSheet.launch(get_tree(), mode)


func _go_tab(route: StringName) -> void:
	Sound.play(Sound.Cue.TAP)
	match route:
		AppTabs.GAMES:
			_back_to_menu()
		AppTabs.YOU:
			_open_settings()


func _open_settings() -> void:
	if _leaving:
		return
	_leaving = true
	Game.reset_to_menu()
	get_tree().change_scene_to_file(SETTINGS_SCENE)


## As camadas primeiro: a folha do jogo, depois a espera de uma sala — desistir da
## espera larga a cadeira que o servidor já reservou. Sem camada nenhuma, volta
## para a coleção de jogos.
func go_back() -> void:
	if _sheet != null and _sheet.is_open():
		_sheet.close()
		return
	if _waiting != null and _waiting.visible:
		_on_give_up()
		return
	_back_to_menu()


func _back_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	Game.reset_to_menu()
	get_tree().change_scene_to_file(MENU_SCENE)
