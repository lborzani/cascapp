class_name Tap

## Um toque, contado **uma vez**.
##
## ## O problema
##
## Um clique chega duas vezes. O projeto liga
## `input_devices/pointing/emulate_touch_from_mouse`, então todo
## `InputEventMouseButton` também vira um `InputEventScreenTouch`; no Android é o
## contrário — `emulate_mouse_from_touch` vem ligado de fábrica e todo dedo
## também vira mouse. Nos dois casos, um `_gui_input` que trate as duas espécies
## conta o mesmo toque duas vezes.
##
## Onde a ação é idempotente isso passa despercebido: escolher um jogo duas vezes
## abre a mesma tela, e o dado já rolando ignora o segundo pedido. Onde ela
## **alterna**, não passa: a estrela do favorito era marcada e desmarcada no mesmo
## clique, e o sintoma era o botão simplesmente não funcionar.
##
## ## A saída
##
## Escutar um canal só, e o canal certo é decidido pela configuração do projeto,
## não adivinhado. Com a emulação de toque ligada — que é o caso aqui — todo
## clique de mouse chega como toque, então o toque cobre os dois e o mouse é
## descartado. Com ela desligada, o mouse volta a ser necessário.
##
## Ler de `ProjectSettings` em vez de escrever `true` aqui é o que impede este
## arquivo de mentir no dia em que a opção mudar: os menus parariam de responder
## no desktop, e o motivo estaria escondido numa constante de outro arquivo.
##
## `monopoly_board_3d.gd` resolve o mesmo problema por outro caminho — ele
## precisa de **gestos** e aprende com o primeiro dedo de verdade qual canal
## importa. Aqui basta o toque simples, e o simples é decidir antes.

const EMULATION := "input_devices/pointing/emulate_touch_from_mouse"

## Lido uma vez por execução: a configuração não muda com o app aberto, e
## perguntar ao `ProjectSettings` a cada evento de dedo seria um dicionário
## consultado sessenta vezes por segundo para dar sempre a mesma resposta.
static var _mouse_is_mirrored := -1


## O evento é o **começo** de um toque que conta.
static func began(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton and not _mirrored():
		var click := event as InputEventMouseButton
		return click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	return false


## O evento é o **fim** de um toque que conta.
static func ended(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton and not _mirrored():
		var click := event as InputEventMouseButton
		return not click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	return false


## Onde o dedo encostou, em coordenadas do `Control` que recebeu o evento.
static func at(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).position
	return Vector2.ZERO


## O mouse é só um espelho do toque, e portanto descartável.
static func _mirrored() -> bool:
	if _mouse_is_mirrored < 0:
		_mouse_is_mirrored = 1 if ProjectSettings.get_setting(EMULATION, false) else 0
	return _mouse_is_mirrored == 1


## Só para os testes: obriga a próxima pergunta a reler a configuração.
static func forget() -> void:
	_mouse_is_mirrored = -1
