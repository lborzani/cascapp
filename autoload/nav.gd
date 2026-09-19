extends Node

## Autoload `Nav`: o botão de voltar do sistema, ligado à tela que está aberta.
##
## No Android o gesto de voltar chega ao app como
## `NOTIFICATION_WM_GO_BACK_REQUEST`, e o padrão do Godot é
## `quit_on_go_back = true` — **fecha o app**, de qualquer tela, sem consultar
## ninguém. Era o que acontecia aqui: o gesto mais natural do aparelho matava o
## processo no meio de uma partida em rede, e quem estava do outro lado via um
## abandono.
##
## O app tem uma pilha de navegação de verdade — inicial → jogo → ajustes →
## tabuleiro —, só que ela não está guardada em lugar nenhum: cada tela já sabe
## para onde volta, e o botão "Voltar" dela é essa resposta escrita. Este arquivo
## não inventa uma segunda pilha para o gesto consultar; ele entrega o gesto ao
## mesmo caminho que o botão da tela já percorria. Duas pilhas seriam duas
## respostas para "onde eu estava", e a que ficasse desatualizada mandaria o
## jogador para uma tela que ele nunca abriu.
##
## ## Por que um autoload, e não `_notification` em cada cena
##
## `quit_on_go_back` mora no `SceneTree`, e o `quit()` dele roda junto com a
## notificação — não depois. Uma cena que escrevesse o tratador certo e
## esquecesse de desligar a bandeira fecharia o app assim mesmo, e esquecer seria
## o normal: a bandeira é global e a cena é local. Desligada uma vez aqui, nenhuma
## tela precisa saber que ela existe.
##
## ## O contrato: `go_back()` na raiz da cena
##
## Cada tela declara um método público `go_back()`. Quem não declara **volta à
## tela inicial**, e não fecha o app: uma tela nova que esqueça o método vira um
## incômodo, e não a perda da partida de quem está do outro lado. `scene_probe.gd`
## varre `res://scenes/` e reprova quem faltar, então o incômodo também não chega
## ao aparelho.
##
## A única tela que **fecha** o app é a inicial, e ela fecha porque é a raiz: ali
## o gesto chegou ao fim da pilha, e sair para o sistema é o que o Android
## promete. O comportamento antigo não estava errado — estava aplicado em todo
## lugar.

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Quadro do último gesto atendido. Existe porque o mesmo "voltar" pode chegar
## duas vezes no mesmo quadro — pela notificação e pelo atalho de teclado — e duas
## trocas de cena empilhadas deixam a segunda mandando numa tela que a primeira já
## descartou.
##
## Só o mesmo quadro: dois toques seguidos de verdade são duas voltas, e é isso
## que se espera de quem quer atravessar a pilha depressa.
var _served_frame := -1


func _ready() -> void:
	get_tree().quit_on_go_back = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


## `ui_cancel` é o Esc, e está aqui para o gesto ser **exercitável fora do
## Android**. Sem ele, a única forma de verificar a volta seria exportar um APK e
## tocar na tela — que é o tipo de conferência que não acontece toda vez.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()


## Entrega o gesto à tela aberta, ou volta ao menu se ela não souber recebê-lo.
func go_back() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var frame := Engine.get_process_frames()
	if frame == _served_frame:
		return
	_served_frame = frame

	# Uma camada aberta por cima da tela — a página de regras, a gaveta da mesa —
	# fecha antes de a tela ouvir o gesto: voltar é sair do que está na frente, e
	# quem está na frente é ela.
	var layers := tree.get_nodes_in_group(&"back_layer")
	if not layers.is_empty():
		layers[layers.size() - 1].call(&"dismiss")
		return
	var screen := tree.current_scene
	if screen != null and screen.has_method(&"go_back"):
		screen.call(&"go_back")
		return
	Game.reset_to_menu()
	tree.change_scene_to_file(MENU_SCENE)
